using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text.Json;
using Navtool.Core;

namespace Navtool.Infrastructure;

public sealed record RegionalLandOptions(
    GeographicBounds Bounds,
    double ResolutionNauticalMiles,
    double DistanceCapNauticalMiles = 60,
    ulong MaximumGridNodes = 250_000,
    ulong MaximumSourcePoints = 10_000_000,
    ulong MaximumGeometryTests = 100_000_000,
    double ClearanceNauticalMiles = 0,
    int MaximumSubdivisionDepth = 12,
    RouteMissingDataPolicy MissingDataPolicy = RouteMissingDataPolicy.RejectTransition)
{
    public static RegionalLandOptions FromPolicy(RouteRegionalLandPolicy policy) =>
        new(policy.StudyBounds, policy.ResolutionNauticalMiles, policy.DistanceCapNauticalMiles,
            policy.MaximumGridNodes, policy.MaximumSourcePoints, policy.MaximumGeometryTests,
            policy.ClearanceNauticalMiles, policy.MaximumSubdivisionDepth, policy.MissingDataPolicy);

    internal NativeLandOptionsV8 ToNative()
    {
        var span = Bounds.CrossesAntimeridian ? Bounds.East - Bounds.West + 360 : Bounds.East - Bounds.West;
        if (Bounds.South < -85 || Bounds.North > 85 || Bounds.North - Bounds.South > 120 ||
            span > 120 || span <= 0 || Bounds.North <= Bounds.South)
            throw new ArgumentOutOfRangeException(nameof(Bounds),
                "GSHHG study domains must have positive spans no greater than 120 degrees and remain within ±85°.");
        if (!double.IsFinite(ResolutionNauticalMiles) || ResolutionNauticalMiles is < .05 or > 120)
            throw new ArgumentOutOfRangeException(nameof(ResolutionNauticalMiles));
        if (!double.IsFinite(DistanceCapNauticalMiles) || DistanceCapNauticalMiles is < 1 or > 600)
            throw new ArgumentOutOfRangeException(nameof(DistanceCapNauticalMiles));
        if (MaximumGridNodes is 0 or > 250_000 || MaximumSourcePoints is 0 or > 10_000_000 ||
            MaximumGeometryTests is 0 or > 100_000_000)
            throw new ArgumentOutOfRangeException(nameof(MaximumGridNodes), "Native safety budgets may be lowered, never raised.");
        if (!double.IsFinite(ClearanceNauticalMiles) || ClearanceNauticalMiles < 0 ||
            ClearanceNauticalMiles >= DistanceCapNauticalMiles ||
            MaximumSubdivisionDepth is < 1 or > 32 || !Enum.IsDefined(MissingDataPolicy))
            throw new ArgumentOutOfRangeException(nameof(ClearanceNauticalMiles));
        return new NativeLandOptionsV8
        {
            StructSize = checked((uint)Marshal.SizeOf<NativeLandOptionsV8>()),
            South = Bounds.South, West = Bounds.West, North = Bounds.North, East = Bounds.East,
            ResolutionNauticalMiles = ResolutionNauticalMiles,
            DistanceCapNauticalMiles = DistanceCapNauticalMiles,
            MaximumGridNodes = MaximumGridNodes, MaximumSourcePoints = MaximumSourcePoints,
            MaximumGeometryTests = MaximumGeometryTests
        };
    }
}

public sealed class NativeRegionalLandSourceService(NativeRouterBridge bridge)
{
    public RegionalLandEstimate Estimate(RegionalLandOptions options) => bridge.EstimateRegionalLand(options);

    public ValueTask<RouteRegionalLandPolicy> ValidateSourceAsync(string path, RegionalLandOptions options,
        CancellationToken cancellationToken = default) =>
        new(Task.Run(() =>
        {
            using var land = bridge.LoadRegionalLand(path, options, cancellationToken: cancellationToken);
            return new RouteRegionalLandPolicy(Path.GetFullPath(path), land.SourceFingerprint, options.Bounds,
                options.ResolutionNauticalMiles, options.ClearanceNauticalMiles, options.DistanceCapNauticalMiles,
                options.MaximumGridNodes, options.MaximumSourcePoints, options.MaximumGeometryTests,
                options.MaximumSubdivisionDepth, NativeRegionalLand.Attribution, options.MissingDataPolicy);
        }, cancellationToken));
}

public sealed record RegionalLandEstimate(
    ulong LatitudeCount,
    ulong LongitudeCount,
    ulong GridNodes,
    double LatitudeStepDegrees,
    double LongitudeStepDegrees,
    double NativeNumericalAllowanceNauticalMiles,
    double HaloSouth,
    double HaloNorth,
    double HaloWestUnwrapped,
    double HaloEastUnwrapped);

public sealed class NativeRegionalLand : IDisposable
{
    internal NativeRegionalLand(NativeLandSafeHandle handle, RegionalLandOptions options,
        RegionalLandEstimate estimate, string fingerprint, string metadata)
    {
        Handle = handle;
        Options = options;
        Estimate = estimate;
        SourceFingerprint = fingerprint;
        NativeMetadataJson = metadata;
    }
    internal NativeLandSafeHandle Handle { get; }
    public RegionalLandOptions Options { get; }
    public RegionalLandEstimate Estimate { get; }
    public string SourceFingerprint { get; }
    public string NativeMetadataJson { get; }
    public const string Attribution = "GSHHG — Wessel and Smith; user-supplied source. Source completeness is not certified.";
    public void Dispose() => Handle.Dispose();
}

public sealed partial class NativeRouterBridge
{
    public RegionalLandEstimate EstimateRegionalLand(RegionalLandOptions options)
    {
        ArgumentNullException.ThrowIfNull(options);
        if ((_capabilities & NativeRouterCapabilities.Gshhg) == 0)
            throw new NotSupportedException("The installed bridge does not include GSHHG support.");
        var native = options.ToNative();
        var estimate = new NativeLandEstimateV8 { StructSize = checked((uint)Marshal.SizeOf<NativeLandEstimateV8>()) };
        ThrowIfFailed(NativeMethods.LandEstimate(ref native, ref estimate), "Estimating GSHHG feasibility");
        if (estimate.GridNodes == 0 || estimate.GridNodes > options.MaximumGridNodes ||
            estimate.LatitudeCount > estimate.GridNodes || estimate.LongitudeCount > estimate.GridNodes ||
            estimate.LatitudeCount * estimate.LongitudeCount != estimate.GridNodes ||
            !double.IsFinite(estimate.InterpolationErrorNauticalMiles) || estimate.InterpolationErrorNauticalMiles < 0)
            throw new NativeRouteFormatException("Native GSHHG estimate has invalid sizes or numerical allowance.");
        if (options.ClearanceNauticalMiles + estimate.InterpolationErrorNauticalMiles >= options.DistanceCapNauticalMiles)
            throw new RoutingException(RoutingFailureKind.InvalidConfiguration,
                "The GSHHG distance cap must exceed the selected clearance plus the native numerical allowance.");
        return new RegionalLandEstimate(estimate.LatitudeCount, estimate.LongitudeCount, estimate.GridNodes,
            estimate.LatitudeStepDegrees, estimate.LongitudeStepDegrees, estimate.InterpolationErrorNauticalMiles,
            estimate.HaloSouth, estimate.HaloNorth, estimate.HaloWest, estimate.HaloEast);
    }

    public NativeRegionalLand LoadRegionalLand(string path, RegionalLandOptions options,
        string? expectedFingerprint = null, CancellationToken cancellationToken = default)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(path);
        var estimate = EstimateRegionalLand(options);
        cancellationToken.ThrowIfCancellationRequested();
        var fullPath = Path.GetFullPath(path);
        if (!File.Exists(fullPath))
            throw new RoutingException(RoutingFailureKind.MissingRequiredSource, $"Selected GSHHG source is missing: {fullPath}");
        var fingerprint = FingerprintFile(fullPath);
        if (expectedFingerprint is not null && !string.Equals(expectedFingerprint, fingerprint, StringComparison.OrdinalIgnoreCase))
            throw new RoutingException(RoutingFailureKind.MissingRequiredSource, "Selected GSHHG source content has changed; explicitly reselect it.");
        var native = options.ToNative();
        var status = NativeMethods.LandLoad(fullPath, ref native, out var raw);
        var handle = new NativeLandSafeHandle(raw);
        try
        {
            ThrowIfFailed(status, "Loading GSHHG source");
            if (handle.IsInvalid) throw new NativeRouteFormatException("Native GSHHG load returned an invalid handle.");
            cancellationToken.ThrowIfCancellationRequested();
            if (FingerprintFile(fullPath) != fingerprint)
                throw new RoutingException(RoutingFailureKind.MissingRequiredSource, "GSHHG source changed during native loading.");
            status = NativeMethods.LandMetadata(handle, out var json, out var length);
            using var buffer = new NativeAllocatedBufferSafeHandle(json);
            ThrowIfFailed(status, "Reading GSHHG source metadata");
            var metadata = CopyUtf8(json, length, _options.MaximumTextBytes, "GSHHG metadata");
            using var document = JsonDocument.Parse(metadata);
            var root = document.RootElement;
            if (root.GetProperty("source_completeness_certified").GetBoolean() ||
                root.GetProperty("latitude_count").GetUInt64() != estimate.LatitudeCount ||
                root.GetProperty("longitude_count").GetUInt64() != estimate.LongitudeCount ||
                Math.Abs(root.GetProperty("interpolation_error_nautical_miles").GetDouble() -
                    estimate.NativeNumericalAllowanceNauticalMiles) > 1e-9 ||
                root.GetProperty("resolution_nautical_miles").GetDouble() != options.ResolutionNauticalMiles ||
                root.GetProperty("distance_cap_nautical_miles").GetDouble() != options.DistanceCapNauticalMiles)
                throw new NativeRouteFormatException("Native GSHHG load metadata disagrees with its source policy and feasibility estimate.");
            cancellationToken.ThrowIfCancellationRequested();
            return new NativeRegionalLand(handle, options, estimate, fingerprint, metadata);
        }
        catch
        {
            handle.Dispose();
            throw;
        }
    }

    internal static string FingerprintFile(string path)
    {
        using var source = File.OpenRead(path);
        return Convert.ToHexString(SHA256.HashData(source)).ToLowerInvariant();
    }
}

public sealed class NativeStopoverValidator(NativeRouterBridge bridge) : IRouteStopoverValidator
{
    public ValueTask<RoutePlannedHold> CheckAsync(Coordinate location, DateTimeOffset from,
        DateTimeOffset until, RouteExclusionOptions exclusions, CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(exclusions);
        if (until <= from) throw new ArgumentOutOfRangeException(nameof(until));
        return new ValueTask<RoutePlannedHold>(Task.Run(() =>
            bridge.CheckPlannedHold(location, from, until, exclusions, cancellationToken), cancellationToken));
    }
}

public sealed partial class NativeRouterBridge
{
    public RoutePlannedHold CheckPlannedHold(Coordinate location, DateTimeOffset from,
        DateTimeOffset until, RouteExclusionOptions exclusions, CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(exclusions);
        if (until <= from || from.Ticks % TimeSpan.TicksPerSecond != 0 || until.Ticks % TimeSpan.TicksPerSecond != 0)
            throw new ArgumentException("A planned hold requires an increasing interval in whole seconds.");
        cancellationToken.ThrowIfCancellationRequested();
        using var environment = NativeEnvironmentScope.Create(new RouteEnvironmentOptions(exclusions: exclusions));
        var native = environment.Environment.Exclusions;
        var status = NativeMethods.PlannedHold(ref native, CoordinateToNative(location),
            from.ToUnixTimeSeconds(), until.ToUnixTimeSeconds(), out var conflict, out _, out var zone, out var length);
        using var buffer = new NativeAllocatedBufferSafeHandle(zone);
        ThrowIfFailed(status, "Checking planned hold exclusions");
        if (conflict > 1) throw new NativeRouteFormatException("Native hold check returned an invalid conflict flag.");
        var identifier = CopyUtf8(zone, length, _options.MaximumTextBytes, "hold conflict identifier");
        if (conflict == 1 && string.IsNullOrWhiteSpace(identifier))
            throw new NativeRouteFormatException("Native hold conflict has no zone identity.");
        cancellationToken.ThrowIfCancellationRequested();
        return new RoutePlannedHold(location, from, until,
            conflict == 1 ? RouteHoldCheckStatus.Conflict : RouteHoldCheckStatus.Clear,
            conflict == 1 ? identifier : null, "Native timed exclusion check only; not anchorage or station-keeping certification.");
    }
}
