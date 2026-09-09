using Navtool.Core;

namespace Navtool.Infrastructure;

public sealed partial class NativeRouteEngine
{
    public async ValueTask<RouteResult> CalculateConfiguredAsync(RoutingCalculationContext context,
        RouteRequest request, ForecastAcquisition forecast, RouteOptimizationOptions optimization,
        IProgress<RouteCalculationProgress>? progress, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(context);
        ArgumentNullException.ThrowIfNull(request);
        ArgumentNullException.ThrowIfNull(forecast);
        ArgumentNullException.ThrowIfNull(optimization);
        NativeRoutingSetupService.ValidateLandConfiguration(context.Setup, optimization);
        if (context.NativeIdentity != _bridge.BuildIdentity)
            throw new RoutingException(RoutingFailureKind.NativeUnavailable, "Native build identity changed after routing setup was frozen.");
        cancellationToken.ThrowIfCancellationRequested();
        if (context.Setup.LandSource == RoutingLandSource.RegionalGshhg &&
            (context.Setup.RegionalLand is not { } policy ||
                !policy.StudyBounds.Contains(request.Origin) || !policy.StudyBounds.Contains(request.Destination)))
            throw new RoutingException(RoutingFailureKind.InvalidConfiguration, "The route must lie within its explicitly selected GSHHG study domain.");
        var bounds = GetLoadBounds(forecast);
        LandDataAcquisition? land = null;
        if (context.Setup.LandSource is RoutingLandSource.NaturalEarth or RoutingLandSource.OpenStreetMap)
        {
            progress?.Report(new RouteCalculationProgress(0, "Resolving required land geometry"));
            var provider = ResolvePolygonProvider(context.Setup.LandSource);
            var geometryBounds = optimization.Environment?.LandRequest is { } maskRequest
                ? SignedDistanceLandmaskBuilder.RequiredGeometryBounds(bounds, maskRequest.ResolutionNauticalMiles)
                : bounds;
            land = await provider.AcquireAsync(geometryBounds, cancellationToken).ConfigureAwait(false);
            RequireLandGeometry(land);
        }
        RouteResult CalculateOnWorker()
        {
            cancellationToken.ThrowIfCancellationRequested();
            using var polar = NativeBoatExecution.Load(_bridge, context.Boat, _executionDirectory, cancellationToken);
            using var nativeLand = context.Setup.LandSource == RoutingLandSource.RegionalGshhg
                ? _bridge.LoadRegionalLand(context.Setup.RegionalLand!.SourcePath,
                    RegionalLandOptions.FromPolicy(context.Setup.RegionalLand), context.Setup.RegionalLand.SourceIdentity, cancellationToken)
                : null;
            var effective = context.Resolved with { Optimization = optimization };
            var usesMask = optimization.Environment?.Land is not null || optimization.Environment?.LandRequest is not null;
            if (optimization.Environment?.LandRequest is not null)
            {
                if (land is null)
                    throw new RoutingException(RoutingFailureKind.MissingRequiredSource, "A requested polygon-derived mask requires the explicitly selected polygon source.");
                effective = effective with { Optimization = ResolveLandmask(optimization, land, bounds, cancellationToken) };
            }
            Func<Coordinate, Coordinate, bool>? eligible = land is null || usesMask ? null :
                (parent, candidate) => !land.Geometry!.IntersectsSegment(parent, candidate);
            progress?.Report(new RouteCalculationProgress(.1, "Loading and validating forecast"));
            var gap = NativeForecastPolicy.MaximumGap(forecast, context.Setup.LocalForecastMaximumGap);
            var descriptor = _bridge.InspectGrib(forecast.Artifact.Path, cancellationToken);
            var expectedModel = forecast.Run.Model == ForecastModel.NoaaGfs ? NativeGribModelId.NoaaGfs : NativeGribModelId.EcmwfIfs;
            if (descriptor.ModelId != expectedModel)
                throw new RoutingException(RoutingFailureKind.InvalidForecast, "The GRIB model no longer matches the selected forecast.");
            using var loaded = _bridge.LoadForecast(forecast.Artifact.Path, bounds, cancellationToken, gap);
            NativeForecastPolicy.Validate(loaded.Metadata, forecast);
            CoastalTopologyPreparation? topology = null;
            if (effective.CoastalPruning != RouteCoastalPruningMode.Off)
            {
                progress?.Report(new RouteCalculationProgress(.15, "Preparing conservative coastal bounds"));
                var mask = effective.Optimization.Environment?.Land;
                var sourceIdentity = eligible is not null ? land!.Geometry!.GeometryIdentity
                    : nativeLand?.SourceFingerprint ??
                      (mask is not null ? CoastalTopologyPreparation.IdentifyLandmask(mask, cancellationToken) :
                          throw new RoutingException(RoutingFailureKind.InvalidConfiguration,
                              "Coastal pruning requires the selected land enforcement source."));
                topology = CoastalTopologyPreparation.Create(
                    loaded.Metadata.EffectiveBounds ?? throw new NativeRouteFormatException("Missing forecast bounds."),
                    request, eligible is not null ? land!.Geometry : null, sourceIdentity, cancellationToken);
            }
            var elapsed = TimeSpan.Zero;
            var started = DateTimeOffset.UtcNow;
            var attemptId = Guid.NewGuid();
            var result = _bridge.CalculateWithCoastalTopology(loaded, polar, request, forecast.Run.Model, effective,
                snapshot =>
                {
                    var fraction = AdvanceProgressFraction(request, snapshot, ref elapsed);
                    progress?.Report(new RouteCalculationProgress(.2 + .79 * fraction, "Optimizing route", snapshot));
                }, eligible, cancellationToken, nativeLand, topology,
                status => progress?.Report(new RouteCalculationProgress(.18, status)));
            if (land is not null) result = ApplyLandData(result, land, usesMask);
            else if (nativeLand is not null)
            {
                if (result.NativeAudit?.NativeLandmaskApplied != true)
                    throw new NativeRouteFormatException("The selected native GSHHG mask was not applied.");
                result = result.WithLandAvoidance(new RouteLandAvoidance(LandAvoidanceStatus.Applied,
                    "Routing was restricted to the explicitly selected regional study domain. GSHHG does not certify source completeness or replace nautical charts.",
                    context.Setup.RegionalLand!.Attribution));
            }
            else if (context.Setup.LandSource == RoutingLandSource.None)
                result = result.WithLandAvoidance(new RouteLandAvoidance(LandAvoidanceStatus.DataUnconfigured,
                    "Land protection was explicitly disabled for this calculation."));
            var audit = new RouteRunAudit(context.CalculationId, context.Setup, effective, context.NativeIdentity,
                optimization.Solver,
                [new RouteAttemptAudit(attemptId, optimization.Solver, started, DateTimeOffset.UtcNow)],
                new RouteForecastAudit(forecast.Run, forecast.Request.Bounds, loaded.Metadata.EffectiveBounds,
                    loaded.Metadata.FirstValidAt, loaded.Metadata.LastValidAt, gap,
                    loaded.Metadata.MinimumTimeSpacing, loaded.Metadata.MaximumTimeSpacing, loaded.Metadata.ValidTimes),
                result.NativeAudit, context.ProfessionalOverrides, result.LandAvoidance);
            result = result.WithRunAudit(audit);
            cancellationToken.ThrowIfCancellationRequested();
            progress?.Report(new RouteCalculationProgress(1, result.IsPartial ? "Partial route calculated" : "Destination arrival area reached"));
            return result;
        }
        try
        {
            return await Task.Run(CalculateOnWorker, cancellationToken).ConfigureAwait(false);
        }
        catch (NativeRouteFormatException exception)
        {
            throw new RoutingException(RoutingFailureKind.InvalidNativeOutput, exception.Message, exception);
        }
        catch (FileNotFoundException exception)
        {
            throw new RoutingException(RoutingFailureKind.InvalidForecast, exception.Message, exception);
        }
    }

    private ILandDataProvider ResolvePolygonProvider(RoutingLandSource source) => source switch
    {
        RoutingLandSource.NaturalEarth => _landDataProvider is not null and not OsmLandDataProvider
            ? _landDataProvider : new NaturalEarthLandDataProvider(),
        RoutingLandSource.OpenStreetMap when _landDataProvider is OsmLandDataProvider { IsConfigured: true } => _landDataProvider,
        _ => throw new RoutingException(RoutingFailureKind.MissingRequiredSource, $"The selected land source {source} is unavailable.")
    };

    internal static void RequireLandGeometry(LandDataAcquisition land)
    {
        if (land.Status != LandDataStatus.Available || land.Geometry is null)
            throw new RoutingException(RoutingFailureKind.MissingRequiredSource,
                land.Warning ?? "The required land source did not return usable geometry. Routing is blocked; select another source explicitly.");
    }
}
