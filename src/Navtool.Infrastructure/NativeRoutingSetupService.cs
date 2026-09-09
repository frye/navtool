using Navtool.Core;

namespace Navtool.Infrastructure;

public sealed class NativeRoutingSetupService : IRoutingSetupService
{
    private readonly NativeRouterBridge _bridge;
    private readonly IBoatAssetService _boats;
    private readonly ILandDataProvider? _landDataProvider;
    private readonly string _executionDirectory;

    public NativeRoutingSetupService(NativeRouterBridge bridge, IBoatAssetService boats,
        ILandDataProvider? landDataProvider = null, string? executionDirectory = null)
    {
        _bridge = bridge;
        _boats = boats;
        _landDataProvider = landDataProvider;
        _executionDirectory = executionDirectory ?? NativeBoatExecution.DefaultDirectory;
    }

    public async ValueTask<RoutingCalculationContext> FreezeAsync(RoutingSetup setup,
        RoutingProfessionalOverrides? professionalOverrides = null, CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(setup);
        if (setup.LocalForecastMaximumGap.Ticks % TimeSpan.TicksPerSecond != 0 ||
            setup.LocalForecastMaximumGap > TimeSpan.FromDays(366))
            throw new RoutingException(RoutingFailureKind.InvalidConfiguration, "Local forecast gap policy requires whole seconds, no greater than 366 days.");
        _bridge.EnsureAvailable();
        var resolved = _bridge.ResolveRoutingOptions(setup, professionalOverrides);
        ValidateLandConfiguration(setup, resolved.Optimization);
        _bridge.ValidateCoastalPruning(resolved);
        if (setup.CoastalPruning != RouteCoastalPruningMode.Off && setup.LandSource == RoutingLandSource.None)
            throw new RoutingException(RoutingFailureKind.InvalidConfiguration,
                "Conservative coastal pruning requires an explicitly selected land source.");
        if (resolved.Optimization.Environment is { } environment &&
            NativeRouterBridge.DescribeMissingCapability(_bridge.Capabilities, environment) is { } missing)
            throw new RoutingException(RoutingFailureKind.NativeUnavailable, $"The native bridge does not provide configured {missing}.");
        var boat = await _boats.ResolveAsync(setup.Boat, cancellationToken).ConfigureAwait(false);
        await Task.Run(() =>
        {
            using var native = NativeBoatExecution.Load(_bridge, boat, _executionDirectory, cancellationToken);
            if (setup.LandSource == RoutingLandSource.RegionalGshhg)
            {
                var policy = setup.RegionalLand ??
                    throw new RoutingException(RoutingFailureKind.MissingRequiredSource, "Regional GSHHG requires an explicit source and study domain.");
                using var land = _bridge.LoadRegionalLand(policy.SourcePath, RegionalLandOptions.FromPolicy(policy),
                    policy.SourceIdentity, cancellationToken);
            }
        }, cancellationToken).ConfigureAwait(false);
        if (setup.LandSource == RoutingLandSource.NaturalEarth)
        {
            var provider = _landDataProvider is not null and not OsmLandDataProvider ? _landDataProvider : new NaturalEarthLandDataProvider();
            var data = await provider.AcquireAsync(new GeographicBounds(-1, 1, -1, 1), cancellationToken).ConfigureAwait(false);
            NativeRouteEngine.RequireLandGeometry(data);
        }
        else if (setup.LandSource == RoutingLandSource.OpenStreetMap &&
                 (_landDataProvider is not OsmLandDataProvider osm || !osm.IsConfigured))
        {
            throw new RoutingException(RoutingFailureKind.MissingRequiredSource, "The selected OpenStreetMap source is not configured.");
        }
        cancellationToken.ThrowIfCancellationRequested();
        return new RoutingCalculationContext(Guid.NewGuid(), setup, boat, _bridge.BuildIdentity, resolved, professionalOverrides);
    }

    internal static void ValidateLandConfiguration(RoutingSetup setup, RouteOptimizationOptions optimization)
    {
        if (setup.LandSource is RoutingLandSource.None or RoutingLandSource.RegionalGshhg &&
            (optimization.Environment?.Land is not null || optimization.Environment?.LandRequest is not null))
            throw new RoutingException(RoutingFailureKind.InvalidConfiguration,
                "The selected land source conflicts with the configured polygon-derived signed-distance mask.");
    }
}

internal static class NativeBoatExecution
{
    internal static string DefaultDirectory => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Navtool", "native-executions");

    internal static NativePolar Load(NativeRouterBridge bridge, ResolvedBoatAsset boat,
        string directory, CancellationToken cancellationToken)
    {
        if (boat.Asset.MaximumTrueWindAngleDegrees is not null)
            throw new RoutingException(RoutingFailureKind.InvalidBoat, "The native polar parser does not support a maximum sailing-angle restriction.");
        if (boat.Asset.Kind == BoatAssetKind.Demo)
        {
            if (boat.Asset.MinimumTrueWindAngleDegrees is not null)
                throw new RoutingException(RoutingFailureKind.InvalidBoat, "Demo polar angle restrictions are not supported.");
            return bridge.CreateDemoPolar(cancellationToken);
        }
        cancellationToken.ThrowIfCancellationRequested();
        Directory.CreateDirectory(directory);
        var path = Path.Combine(directory, Guid.NewGuid().ToString("N") + ".polar");
        try
        {
            using (var stream = new FileStream(path, FileMode.CreateNew, FileAccess.Write, FileShare.None))
                stream.Write(boat.PolarBytes.AsSpan());
            return bridge.LoadPolar(path, boat.Asset.RequestedFormat, boat.Asset.MinimumTrueWindAngleDegrees, cancellationToken);
        }
        finally
        {
            if (File.Exists(path)) File.Delete(path);
        }
    }
}
