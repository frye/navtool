using System.Collections.Immutable;

namespace Navtool.Core;

public enum BoatAssetKind { Imported, Demo }
public enum BoatPolarFormat { Automatic, NativeMatrix, Expedition }
public enum RoutingQuality { NativeFast, NativeBalanced, NativeAccurate }
public enum RoutingLandSource { NaturalEarth, OpenStreetMap, RegionalGshhg, None }

public sealed record RouteRegionalLandPolicy
{
    public RouteRegionalLandPolicy(
        string sourcePath,
        string sourceIdentity,
        GeographicBounds studyBounds,
        double resolutionNauticalMiles,
        double clearanceNauticalMiles,
        double distanceCapNauticalMiles,
        ulong maximumGridNodes,
        ulong maximumSourcePoints,
        ulong maximumGeometryTests,
        int maximumSubdivisionDepth = 12,
        string attribution = "GSHHG",
        RouteMissingDataPolicy missingDataPolicy = RouteMissingDataPolicy.FailRoute)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(sourcePath);
        ArgumentException.ThrowIfNullOrWhiteSpace(sourceIdentity);
        ArgumentException.ThrowIfNullOrWhiteSpace(attribution);
        var fingerprint = sourceIdentity.StartsWith("sha256:", StringComparison.OrdinalIgnoreCase)
            ? sourceIdentity[7..] : sourceIdentity;
        if (fingerprint.Length != 64 || fingerprint.Any(character => !Uri.IsHexDigit(character)))
            throw new ArgumentException("A regional source requires a SHA-256 content fingerprint.", nameof(sourceIdentity));
        if (!Path.IsPathFullyQualified(sourcePath))
            throw new ArgumentException("A regional source path must be absolute.", nameof(sourcePath));
        var longitudeSpan = studyBounds.CrossesAntimeridian
            ? studyBounds.East - studyBounds.West + 360
            : studyBounds.East - studyBounds.West;
        if (studyBounds.South >= studyBounds.North || studyBounds.South < -85 || studyBounds.North > 85 ||
            studyBounds.North - studyBounds.South > 120 || longitudeSpan is <= 0 or > 120)
            throw new ArgumentException("A regional domain must be within ±85° and span at most 120° on either axis.", nameof(studyBounds));
        if (!double.IsFinite(resolutionNauticalMiles) || resolutionNauticalMiles is < 0.05 or > 120 ||
            !double.IsFinite(clearanceNauticalMiles) || clearanceNauticalMiles < 0 ||
            !double.IsFinite(distanceCapNauticalMiles) || distanceCapNauticalMiles is < 1 or > 600 ||
            distanceCapNauticalMiles <= clearanceNauticalMiles ||
            maximumGridNodes is < 4 or > 250000 || maximumSourcePoints is 0 or > 10000000 ||
            maximumGeometryTests is 0 or > 100000000 || maximumSubdivisionDepth is < 1 or > 32 ||
            !Enum.IsDefined(missingDataPolicy))
            throw new ArgumentOutOfRangeException(nameof(resolutionNauticalMiles));
        SourcePath = Path.GetFullPath(sourcePath);
        SourceIdentity = fingerprint.ToLowerInvariant();
        StudyBounds = studyBounds;
        ResolutionNauticalMiles = resolutionNauticalMiles;
        ClearanceNauticalMiles = clearanceNauticalMiles;
        DistanceCapNauticalMiles = distanceCapNauticalMiles;
        MaximumGridNodes = maximumGridNodes;
        MaximumSourcePoints = maximumSourcePoints;
        MaximumGeometryTests = maximumGeometryTests;
        MaximumSubdivisionDepth = maximumSubdivisionDepth;
        Attribution = attribution.Trim();
        MissingDataPolicy = missingDataPolicy;
    }
    public string SourcePath { get; }
    public string SourceIdentity { get; }
    public GeographicBounds StudyBounds { get; }
    public double ResolutionNauticalMiles { get; }
    public double ClearanceNauticalMiles { get; }
    public double DistanceCapNauticalMiles { get; }
    public ulong MaximumGridNodes { get; }
    public ulong MaximumSourcePoints { get; }
    public ulong MaximumGeometryTests { get; }
    public int MaximumSubdivisionDepth { get; }
    public string Attribution { get; }
    public RouteMissingDataPolicy MissingDataPolicy { get; }
}

public sealed record BoatValidationSummary(
    string NativeMessage,
    double? MinimumWindSpeedKnots = null,
    double? MaximumWindSpeedKnots = null,
    double? MinimumAngleDegrees = null,
    double? MaximumAngleDegrees = null,
    BoatPolarFormat? ResolvedFormat = null);

/// <summary>A durable selection, not a native handle or a reference to the original import path.</summary>
public sealed record BoatAsset
{
    public BoatAsset(
        string contentIdentity,
        string sourceDisplayName,
        BoatAssetKind kind,
        BoatPolarFormat requestedFormat,
        BoatValidationSummary validation,
        double? minimumTrueWindAngleDegrees = null,
        double? maximumTrueWindAngleDegrees = null)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(contentIdentity);
        ArgumentException.ThrowIfNullOrWhiteSpace(sourceDisplayName);
        ArgumentNullException.ThrowIfNull(validation);
        if (!Enum.IsDefined(kind) || !Enum.IsDefined(requestedFormat))
            throw new ArgumentOutOfRangeException(nameof(kind));
        if ((minimumTrueWindAngleDegrees is { } min && (!double.IsFinite(min) || min is < 0 or > 180)) ||
            (maximumTrueWindAngleDegrees is { } max && (!double.IsFinite(max) || max is < 0 or > 180)) ||
            minimumTrueWindAngleDegrees > maximumTrueWindAngleDegrees)
            throw new ArgumentOutOfRangeException(nameof(minimumTrueWindAngleDegrees));
        ContentIdentity = contentIdentity;
        SourceDisplayName = sourceDisplayName;
        Kind = kind;
        RequestedFormat = requestedFormat;
        Validation = validation;
        MinimumTrueWindAngleDegrees = minimumTrueWindAngleDegrees;
        MaximumTrueWindAngleDegrees = maximumTrueWindAngleDegrees;
    }

    public string ContentIdentity { get; }
    public string SourceDisplayName { get; }
    public BoatAssetKind Kind { get; }
    public BoatPolarFormat RequestedFormat { get; }
    public BoatValidationSummary Validation { get; }
    public double? MinimumTrueWindAngleDegrees { get; }
    public double? MaximumTrueWindAngleDegrees { get; }
}

public sealed record RoutingSetup
{
    public RoutingSetup(
        BoatAsset boat,
        RoutingQuality quality = RoutingQuality.NativeBalanced,
        double performanceFactor = 1,
        double arrivalRadiusNauticalMiles = 1,
        RoutingLandSource landSource = RoutingLandSource.NaturalEarth,
        ForecastRefreshPolicy forecastPolicy = ForecastRefreshPolicy.PreferCache,
        TimeSpan? hardDuration = null,
        TimeSpan? localForecastMaximumGap = null,
        RouteRegionalLandPolicy? regionalLand = null)
    {
        ArgumentNullException.ThrowIfNull(boat);
        if (!Enum.IsDefined(quality) || !Enum.IsDefined(landSource) || !Enum.IsDefined(forecastPolicy))
            throw new ArgumentOutOfRangeException(nameof(quality));
        if (!double.IsFinite(performanceFactor) || performanceFactor <= 0)
            throw new ArgumentOutOfRangeException(nameof(performanceFactor));
        if (!double.IsFinite(arrivalRadiusNauticalMiles) || arrivalRadiusNauticalMiles <= 0)
            throw new ArgumentOutOfRangeException(nameof(arrivalRadiusNauticalMiles));
        if (hardDuration <= TimeSpan.Zero || localForecastMaximumGap <= TimeSpan.Zero)
            throw new ArgumentOutOfRangeException(nameof(hardDuration));
        if (landSource == RoutingLandSource.RegionalGshhg && regionalLand is null)
            throw new ArgumentException("Regional GSHHG requires an explicit source and bounded study policy.", nameof(regionalLand));
        Boat = boat;
        Quality = quality;
        PerformanceFactor = performanceFactor;
        ArrivalRadiusNauticalMiles = arrivalRadiusNauticalMiles;
        LandSource = landSource;
        ForecastPolicy = forecastPolicy;
        HardDuration = hardDuration;
        LocalForecastMaximumGap = localForecastMaximumGap ?? TimeSpan.FromHours(6);
        RegionalLand = regionalLand;
    }

    public BoatAsset Boat { get; }
    public RoutingQuality Quality { get; }
    public double PerformanceFactor { get; }
    public double ArrivalRadiusNauticalMiles { get; }
    public RoutingLandSource LandSource { get; }
    public ForecastRefreshPolicy ForecastPolicy { get; }
    public TimeSpan? HardDuration { get; }
    public TimeSpan LocalForecastMaximumGap { get; }
    public RouteRegionalLandPolicy? RegionalLand { get; }
}

/// <summary>All numerical fields affected by the native quality preset; no managed preset imitation.</summary>
public sealed record RouteRoutingInterval(TimeSpan Interval, TimeSpan? UntilElapsed = null);

public sealed record RouteSearchSettings
{
    public RouteSearchSettings(
        TimeSpan TimeStep,
        TimeSpan MaximumIntegrationStep,
        double HeadingStepDegrees,
        double SpatialBucketNauticalMiles,
        ulong MaxNodesPerBucket,
        ulong WorkerCount,
        ulong MaximumGeneratedCandidates,
        ulong MaximumRetainedNodes,
        ulong ProgressEveryNSteps,
        bool UseRoutingIntervals,
        bool StrategicRetention,
        bool CaptureIsochrones,
        int DestinationFrontMode,
        double MinimumBoatSpeedKnots,
        IEnumerable<RouteRoutingInterval> Intervals)
    {
        ArgumentNullException.ThrowIfNull(Intervals);
        this.TimeStep = TimeStep;
        this.MaximumIntegrationStep = MaximumIntegrationStep;
        this.HeadingStepDegrees = HeadingStepDegrees;
        this.SpatialBucketNauticalMiles = SpatialBucketNauticalMiles;
        this.MaxNodesPerBucket = MaxNodesPerBucket;
        this.WorkerCount = WorkerCount;
        this.MaximumGeneratedCandidates = MaximumGeneratedCandidates;
        this.MaximumRetainedNodes = MaximumRetainedNodes;
        this.ProgressEveryNSteps = ProgressEveryNSteps;
        this.UseRoutingIntervals = UseRoutingIntervals;
        this.StrategicRetention = StrategicRetention;
        this.CaptureIsochrones = CaptureIsochrones;
        this.DestinationFrontMode = DestinationFrontMode;
        this.MinimumBoatSpeedKnots = MinimumBoatSpeedKnots;
        this.Intervals = Intervals.ToImmutableArray();
    }
    public TimeSpan TimeStep { get; }
    public TimeSpan MaximumIntegrationStep { get; }
    public double HeadingStepDegrees { get; }
    public double SpatialBucketNauticalMiles { get; }
    public ulong MaxNodesPerBucket { get; }
    public ulong WorkerCount { get; }
    public ulong MaximumGeneratedCandidates { get; }
    public ulong MaximumRetainedNodes { get; }
    public ulong ProgressEveryNSteps { get; }
    public bool UseRoutingIntervals { get; }
    public bool StrategicRetention { get; }
    public bool CaptureIsochrones { get; }
    public int DestinationFrontMode { get; }
    public double MinimumBoatSpeedKnots { get; }
    public ImmutableArray<RouteRoutingInterval> Intervals { get; }
}

public sealed record NativeRoutingIdentity(
    int BridgeAbiVersion,
    string LibraryVersion,
    string SourceRevision,
    string BuildIdentity,
    ulong Capabilities);

public sealed record ResolvedRoutingOptions(
    RoutingQuality Quality,
    RouteOptimizationOptions Optimization,
    RouteSearchSettings Search,
    double PerformanceFactor,
    double ArrivalRadiusNauticalMiles,
    TimeSpan? HardDuration)
{
    public static ResolvedRoutingOptions FromNativeDefaults(
        RoutingSetup setup,
        ResolvedRoutingOptions nativeDefaults,
        RoutingProfessionalOverrides? professionalOverrides = null)
    {
        ArgumentNullException.ThrowIfNull(setup);
        ArgumentNullException.ThrowIfNull(nativeDefaults);
        if (nativeDefaults.Quality != setup.Quality)
            throw new RoutingException(RoutingFailureKind.InvalidConfiguration, "Native defaults returned the wrong quality preset.");
        var normal = nativeDefaults.Optimization.WithPolarPolicies(
            RoutePolarAngleInterpolation.MonotoneCubic, RouteAbovePolarRangePolicy.NoSpeed);
        return new(setup.Quality, professionalOverrides?.Optimization ?? normal,
            professionalOverrides?.Search ?? nativeDefaults.Search,
            setup.PerformanceFactor, setup.ArrivalRadiusNauticalMiles, setup.HardDuration ?? nativeDefaults.HardDuration);
    }
}

/// <summary>Session-only requested edits. Persist the resulting effective values in run audit, not setup.</summary>
public sealed record RoutingProfessionalOverrides(
    RouteOptimizationOptions? Optimization = null,
    RouteSearchSettings? Search = null);

public sealed record ResolvedBoatAsset
{
    public ResolvedBoatAsset(BoatAsset asset, IEnumerable<byte>? polarBytes = null)
    {
        ArgumentNullException.ThrowIfNull(asset);
        Asset = asset;
        PolarBytes = (polarBytes ?? []).ToImmutableArray();
        if (asset.Kind == BoatAssetKind.Imported && PolarBytes.IsEmpty)
            throw new RoutingException(RoutingFailureKind.InvalidBoat, "The selected polar asset is empty or unavailable.");
    }
    public BoatAsset Asset { get; }
    public ImmutableArray<byte> PolarBytes { get; }
}

/// <summary>Frozen source policy and settings shared by model/leg requests. Contains no mutable native handles.</summary>
public sealed record RoutingCalculationContext
{
    public RoutingCalculationContext(
        Guid calculationId,
        RoutingSetup setup,
        ResolvedBoatAsset boat,
        NativeRoutingIdentity nativeIdentity,
        ResolvedRoutingOptions resolved,
        RoutingProfessionalOverrides? professionalOverrides = null)
    {
        if (calculationId == Guid.Empty) throw new ArgumentException("Calculation identity is required.", nameof(calculationId));
        ArgumentNullException.ThrowIfNull(setup);
        ArgumentNullException.ThrowIfNull(boat);
        ArgumentNullException.ThrowIfNull(nativeIdentity);
        ArgumentNullException.ThrowIfNull(resolved);
        if (setup.Boat != boat.Asset)
            throw new RoutingException(RoutingFailureKind.InvalidBoat, "The resolved boat does not match the selected asset.");
        if (nativeIdentity.BridgeAbiVersion < 8)
            throw new RoutingException(RoutingFailureKind.NativeUnavailable, "Configured routing requires bridge ABI 8.");
        if (resolved.Quality != setup.Quality || resolved.PerformanceFactor != setup.PerformanceFactor ||
            resolved.ArrivalRadiusNauticalMiles != setup.ArrivalRadiusNauticalMiles ||
            (setup.HardDuration is { } duration && resolved.HardDuration != duration))
            throw new RoutingException(RoutingFailureKind.InvalidConfiguration, "The resolved configuration does not match the selected setup.");
        if (professionalOverrides?.Optimization is null &&
            (resolved.Optimization.PolarAngleInterpolation != RoutePolarAngleInterpolation.MonotoneCubic ||
             resolved.Optimization.AbovePolarRange != RouteAbovePolarRangePolicy.NoSpeed))
            throw new RoutingException(RoutingFailureKind.InvalidConfiguration, "Normal cruising requires explicit PCHIP and NoSpeed polar policies.");
        if (setup.LandSource == RoutingLandSource.RegionalGshhg &&
            resolved.Optimization.Environment is { } environment &&
            (environment.Land is not null || environment.LandRequest is not null))
            throw new RoutingException(RoutingFailureKind.InvalidConfiguration,
                "Regional GSHHG cannot be combined with a second native landmask source.");
        ValidateSearch(resolved.Search);
        CalculationId = calculationId;
        Setup = setup;
        Boat = boat;
        NativeIdentity = nativeIdentity;
        Resolved = resolved;
        ProfessionalOverrides = professionalOverrides;
    }
    public Guid CalculationId { get; }
    public RoutingSetup Setup { get; }
    public ResolvedBoatAsset Boat { get; }
    public NativeRoutingIdentity NativeIdentity { get; }
    public ResolvedRoutingOptions Resolved { get; }
    public RoutingProfessionalOverrides? ProfessionalOverrides { get; }

    private static void ValidateSearch(RouteSearchSettings search)
    {
        ArgumentNullException.ThrowIfNull(search);
        if (search.TimeStep <= TimeSpan.Zero || search.TimeStep.Ticks % TimeSpan.TicksPerMinute != 0 ||
            search.MaximumIntegrationStep <= TimeSpan.Zero ||
            search.MaximumIntegrationStep.Ticks % TimeSpan.TicksPerMinute != 0 ||
            !double.IsFinite(search.HeadingStepDegrees) || search.HeadingStepDegrees is <= 0 or > 360 ||
            search.MaxNodesPerBucket == 0 ||
            !double.IsFinite(search.MinimumBoatSpeedKnots) || search.MinimumBoatSpeedKnots < 0 ||
            !double.IsFinite(search.SpatialBucketNauticalMiles) || search.SpatialBucketNauticalMiles <= 0 ||
            search.Intervals.Length > 16 ||
            search.Intervals.Any(interval => interval is null || interval.Interval <= TimeSpan.Zero ||
                interval.Interval.Ticks % TimeSpan.TicksPerMinute != 0 ||
                interval.UntilElapsed <= TimeSpan.Zero))
            throw new RoutingException(RoutingFailureKind.InvalidConfiguration, "The native search settings are invalid.");
    }
}

public interface IBoatAssetService
{
    ValueTask<BoatAsset> ImportAsync(string path, BoatPolarFormat format, CancellationToken cancellationToken = default);
    ValueTask<BoatAsset> GetDemoAsync(CancellationToken cancellationToken = default);
    ValueTask<ResolvedBoatAsset> ResolveAsync(BoatAsset asset, CancellationToken cancellationToken = default);
}

public interface IRoutingSetupService
{
    ValueTask<RoutingCalculationContext> FreezeAsync(
        RoutingSetup setup,
        RoutingProfessionalOverrides? professionalOverrides = null,
        CancellationToken cancellationToken = default);
}

/// <summary>Implementations must apply every configured field or fail before acquisition/search; never downgrade.</summary>
public interface IConfiguredRouteEngine : IRouteEngine
{
    ValueTask<RouteResult> CalculateConfiguredAsync(
        RoutingCalculationContext context,
        RouteRequest request,
        ForecastAcquisition forecast,
        RouteOptimizationOptions optimization,
        IProgress<RouteCalculationProgress>? progress,
        CancellationToken cancellationToken);
}

public enum RoutingFailureKind
{
    Unknown, RecoverableSolver, InvalidBoat, MissingRequiredSource, InvalidConfiguration,
    InvalidForecast, InvalidNativeOutput, ResourceLimit, Cancelled, NativeUnavailable
}

public class RoutingException : Exception
{
    public RoutingException(RoutingFailureKind kind, string message, Exception? innerException = null)
        : base(message, innerException) => Kind = kind;
    public RoutingFailureKind Kind { get; }
}

public enum RouteHoldCheckStatus { NoExclusionsConfigured, Clear, Conflict, Unavailable }

public sealed record RoutePlannedHold
{
    public RoutePlannedHold(
        Coordinate location,
        DateTimeOffset from,
        DateTimeOffset until,
        RouteHoldCheckStatus status,
        string? conflictZoneIdentifier = null,
        string? detail = null)
    {
        if (until <= from) throw new ArgumentOutOfRangeException(nameof(until));
        if (!Enum.IsDefined(status)) throw new ArgumentOutOfRangeException(nameof(status));
        if (status == RouteHoldCheckStatus.Conflict && string.IsNullOrWhiteSpace(conflictZoneIdentifier))
            throw new ArgumentException("A conflict requires a zone identity.", nameof(conflictZoneIdentifier));
        Location = location;
        From = from.ToUniversalTime();
        Until = until.ToUniversalTime();
        Status = status;
        ConflictZoneIdentifier = conflictZoneIdentifier;
        Detail = detail;
    }
    public Coordinate Location { get; }
    public DateTimeOffset From { get; }
    public DateTimeOffset Until { get; }
    public RouteHoldCheckStatus Status { get; }
    public string? ConflictZoneIdentifier { get; }
    public string? Detail { get; }
    public bool AllowsHandoff => Status is RouteHoldCheckStatus.Clear or RouteHoldCheckStatus.NoExclusionsConfigured;
}

/// <summary>Use the native exclusion segment evaluator at equal endpoints over the whole hold interval.</summary>
public interface IRouteStopoverValidator
{
    ValueTask<RoutePlannedHold> CheckAsync(
        Coordinate location,
        DateTimeOffset from,
        DateTimeOffset until,
        RouteExclusionOptions exclusions,
        CancellationToken cancellationToken = default);
}

public enum RouteLegOriginSource { DeclaredWaypoint, CurrentPosition, AcceptedPredecessor }
public sealed record RoutePredecessorReference(
    RoutePlanId PlanId,
    RouteLegId LegId,
    ForecastModel Model,
    RouteCalculationSessionId SessionId,
    string RouteId);
public sealed record RouteLegOrigin(RouteLegOriginSource Source, RoutePredecessorReference? Predecessor = null);

public sealed record RouteAttemptAudit(
    Guid AttemptId,
    RouteSolver Solver,
    DateTimeOffset StartedAt,
    DateTimeOffset CompletedAt,
    RoutingFailureKind? FailureKind = null,
    string? FailureMessage = null);

public sealed record RouteForecastAudit(
    ForecastRun Run,
    GeographicBounds DeclaredBounds,
    GeographicBounds? EffectiveBounds,
    DateTimeOffset? ValidFrom,
    DateTimeOffset? ValidThrough,
    TimeSpan? MaximumInterpolationGap = null,
    TimeSpan? MinimumTimeSpacing = null,
    TimeSpan? MaximumTimeSpacing = null,
    ImmutableArray<DateTimeOffset> ValidTimes = default);

public sealed record RouteNativeRunAudit(
    string Schema,
    RouteSolver Solver,
    double? EffectiveArrivalRadiusNauticalMiles = null,
    TimeSpan? HardDuration = null,
    bool? NativeLandmaskApplied = null,
    long? EligibilityEvaluations = null,
    long? PrunedCandidates = null,
    long? FutureProbeMisses = null,
    RouteNativeRunMetadata? Routing = null,
    string? ForecastSource = null,
    string? PolarSource = null,
    string? DepartureSource = null,
    ForecastCoverage? ForecastCoverage = null)
{
    internal bool HasSameContent(RouteNativeRunAudit? other) =>
        other is not null &&
        (Routing is null ? other.Routing is null : Routing.HasSameContent(other.Routing)) &&
        (ForecastCoverage is null ? other.ForecastCoverage is null : ForecastCoverage.HasSameContent(other.ForecastCoverage)) &&
        this == other with { Routing = Routing, ForecastCoverage = ForecastCoverage };
}

/// <summary>The observed native v2 routing block, distinct from requested and bridge-resolved settings.</summary>
public sealed record RouteNativeRunMetadata
{
    public RouteNativeRunMetadata(
        string objective,
        string qualityClaim,
        RouteSolver solver,
        Coordinate requestedDestination,
        double arrivalRadiusNauticalMiles,
        double remainingDistanceNauticalMiles,
        double boatSpeedFactor,
        double headingStepDegrees,
        double spatialBucketNauticalMiles,
        TimeSpan maximumIntegrationStep,
        bool strategicRetention,
        bool landAvoidance,
        RouteWindSampling windSampling,
        RouteAbovePolarRangePolicy abovePolarRange,
        double? maximumForecastWindKnots,
        TimeSpan tackPenalty,
        TimeSpan gybePenalty,
        DateTimeOffset forecastInitialization,
        DateTimeOffset forecastFirstValid,
        DateTimeOffset forecastLastValid,
        IEnumerable<string> warnings)
    {
        if (objective != "earliest_arrival" || qualityClaim != "best_found")
            throw new ArgumentException("The native objective or quality claim is unsupported.", nameof(objective));
        if (!Enum.IsDefined(solver) || !Enum.IsDefined(windSampling) || !Enum.IsDefined(abovePolarRange))
            throw new ArgumentOutOfRangeException(nameof(solver));
        if (!double.IsFinite(arrivalRadiusNauticalMiles) || arrivalRadiusNauticalMiles <= 0 ||
            !double.IsFinite(remainingDistanceNauticalMiles) || remainingDistanceNauticalMiles < 0 ||
            !double.IsFinite(boatSpeedFactor) || boatSpeedFactor <= 0 ||
            !double.IsFinite(headingStepDegrees) || headingStepDegrees is <= 0 or > 360 ||
            !double.IsFinite(spatialBucketNauticalMiles) || spatialBucketNauticalMiles <= 0 ||
            (maximumForecastWindKnots is { } maximumWind && (!double.IsFinite(maximumWind) || maximumWind <= 0)))
            throw new ArgumentOutOfRangeException(nameof(arrivalRadiusNauticalMiles));
        if (maximumIntegrationStep <= TimeSpan.Zero ||
            maximumIntegrationStep.Ticks % TimeSpan.TicksPerMinute != 0 ||
            tackPenalty < TimeSpan.Zero || gybePenalty < TimeSpan.Zero ||
            forecastLastValid < forecastFirstValid || forecastFirstValid < forecastInitialization)
            throw new ArgumentException("The native time or penalty audit is invalid.", nameof(maximumIntegrationStep));
        ArgumentNullException.ThrowIfNull(warnings);
        Warnings = warnings.ToImmutableArray();
        if (Warnings.Any(warning => warning is null))
            throw new ArgumentException("Native warnings cannot contain null entries.", nameof(warnings));
        Objective = objective;
        QualityClaim = qualityClaim;
        Solver = solver;
        RequestedDestination = requestedDestination;
        ArrivalRadiusNauticalMiles = arrivalRadiusNauticalMiles;
        RemainingDistanceNauticalMiles = remainingDistanceNauticalMiles;
        BoatSpeedFactor = boatSpeedFactor;
        HeadingStepDegrees = headingStepDegrees;
        SpatialBucketNauticalMiles = spatialBucketNauticalMiles;
        MaximumIntegrationStep = maximumIntegrationStep;
        StrategicRetention = strategicRetention;
        LandAvoidance = landAvoidance;
        WindSampling = windSampling;
        AbovePolarRange = abovePolarRange;
        MaximumForecastWindKnots = maximumForecastWindKnots;
        TackPenalty = tackPenalty;
        GybePenalty = gybePenalty;
        ForecastInitialization = forecastInitialization.ToUniversalTime();
        ForecastFirstValid = forecastFirstValid.ToUniversalTime();
        ForecastLastValid = forecastLastValid.ToUniversalTime();
    }
    public string Objective { get; }
    public string QualityClaim { get; }
    public RouteSolver Solver { get; }
    public Coordinate RequestedDestination { get; }
    public double ArrivalRadiusNauticalMiles { get; }
    public double RemainingDistanceNauticalMiles { get; }
    public double BoatSpeedFactor { get; }
    public double HeadingStepDegrees { get; }
    public double SpatialBucketNauticalMiles { get; }
    public TimeSpan MaximumIntegrationStep { get; }
    public bool StrategicRetention { get; }
    public bool LandAvoidance { get; }
    public RouteWindSampling WindSampling { get; }
    public RouteAbovePolarRangePolicy AbovePolarRange { get; }
    public double? MaximumForecastWindKnots { get; }
    public TimeSpan TackPenalty { get; }
    public TimeSpan GybePenalty { get; }
    public DateTimeOffset ForecastInitialization { get; }
    public DateTimeOffset ForecastFirstValid { get; }
    public DateTimeOffset ForecastLastValid { get; }
    public ImmutableArray<string> Warnings { get; private init; }

    internal bool HasSameContent(RouteNativeRunMetadata? other) =>
        other is not null && Warnings.SequenceEqual(other.Warnings) &&
        this == other with { Warnings = Warnings };
}

public sealed record RouteRunAudit
{
    public RouteRunAudit(
        Guid calculationId,
        RoutingSetup setup,
        ResolvedRoutingOptions resolved,
        NativeRoutingIdentity nativeIdentity,
        RouteSolver requestedSolver,
        IEnumerable<RouteAttemptAudit> attempts,
        RouteForecastAudit? forecast = null,
        RouteNativeRunAudit? native = null,
        RoutingProfessionalOverrides? professionalOverrides = null,
        RouteLandAvoidance? applicationLand = null)
    {
        if (calculationId == Guid.Empty) throw new ArgumentException("Calculation identity is required.", nameof(calculationId));
        ArgumentNullException.ThrowIfNull(setup);
        ArgumentNullException.ThrowIfNull(resolved);
        ArgumentNullException.ThrowIfNull(nativeIdentity);
        ArgumentNullException.ThrowIfNull(attempts);
        if (!Enum.IsDefined(requestedSolver)) throw new ArgumentOutOfRangeException(nameof(requestedSolver));
        var frozenAttempts = attempts.ToImmutableArray();
        if (frozenAttempts.IsEmpty || frozenAttempts[0].Solver != requestedSolver ||
            frozenAttempts.Any(attempt => attempt.AttemptId == Guid.Empty ||
                !Enum.IsDefined(attempt.Solver) || attempt.CompletedAt < attempt.StartedAt ||
                (attempt.FailureKind is { } kind && !Enum.IsDefined(kind))) ||
            frozenAttempts.Select(attempt => attempt.AttemptId).Distinct().Count() != frozenAttempts.Length)
            throw new ArgumentException("Attempt identities and execution timestamps must be consistent.", nameof(attempts));
        CalculationId = calculationId;
        Setup = setup;
        // Bulk environment grids and polygons belong to the execution context.
        // Results retain numerical settings and the native/provider metadata separately.
        Resolved = resolved with { Optimization = resolved.Optimization.WithEnvironment(null) };
        NativeIdentity = nativeIdentity;
        RequestedSolver = requestedSolver;
        Attempts = frozenAttempts;
        if (forecast is not null)
        {
            var times = forecast.ValidTimes.IsDefault ? ImmutableArray<DateTimeOffset>.Empty : forecast.ValidTimes;
            if (forecast.MinimumTimeSpacing <= TimeSpan.Zero || forecast.MaximumTimeSpacing <= TimeSpan.Zero ||
                forecast.MinimumTimeSpacing > forecast.MaximumTimeSpacing ||
                forecast.ValidThrough < forecast.ValidFrom ||
                times.Zip(times.Skip(1)).Any(pair => pair.Second <= pair.First) ||
                (!times.IsEmpty && (times[0] != forecast.ValidFrom || times[^1] != forecast.ValidThrough)))
                throw new ArgumentException("The forecast audit contains inconsistent cadence or validity.", nameof(forecast));
            forecast = forecast with { ValidTimes = times };
        }
        Forecast = forecast;
        Native = native;
        ProfessionalOverrides = professionalOverrides is null ? null : professionalOverrides with
        {
            Optimization = professionalOverrides.Optimization?.WithEnvironment(null)
        };
        ApplicationLand = applicationLand;
    }
    public Guid CalculationId { get; }
    public RoutingSetup Setup { get; }
    public ResolvedRoutingOptions Resolved { get; }
    public NativeRoutingIdentity NativeIdentity { get; }
    public RouteSolver RequestedSolver { get; }
    public ImmutableArray<RouteAttemptAudit> Attempts { get; }
    public RouteForecastAudit? Forecast { get; }
    public RouteNativeRunAudit? Native { get; }
    public RoutingProfessionalOverrides? ProfessionalOverrides { get; }
    public RouteLandAvoidance? ApplicationLand { get; }

    public RouteRunAudit WithApplicationLand(RouteLandAvoidance land) =>
        new(CalculationId, Setup, Resolved, NativeIdentity, RequestedSolver, Attempts,
            Forecast, Native, ProfessionalOverrides, land);

    public RouteRunAudit WithAttempts(
        RouteSolver requestedSolver,
        IEnumerable<RouteAttemptAudit> attempts,
        ResolvedRoutingOptions resolved,
        RouteLandAvoidance applicationLand) =>
        new(CalculationId, Setup, resolved, NativeIdentity, requestedSolver, attempts,
            Forecast, Native, ProfessionalOverrides, applicationLand);
}
