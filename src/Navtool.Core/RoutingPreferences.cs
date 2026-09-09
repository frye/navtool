namespace Navtool.Core;

public enum PlanningForecastSource { Download, LocalFile }

/// <summary>Mutable planning intent, separate from immutable calculation audit.</summary>
public sealed record RoutePlanningInputs
{
    public bool DepartureNow { get; init; } = true;
    public DateTimeOffset? ScheduledDepartureUtc { get; init; }
    public int PassageDays { get; init; } = 3;
    public int PassageHours { get; init; }
    public PlanningForecastSource ForecastSource { get; init; }
    public bool UseNoaa { get; init; } = true;
    public bool UseEcmwf { get; init; }
    public string? LocalGribPath { get; init; }

    public void Validate()
    {
        if (!DepartureNow && ScheduledDepartureUtc is null)
            throw new ArgumentException("Choose a valid scheduled departure.");
        if (PassageDays < 0 || PassageHours is < 0 or > 23)
            throw new ArgumentException("Passage days cannot be negative and hours must be between 0 and 23.");
        if (PassageDays > 10 || PassageDays * 24 + PassageHours > 240)
            throw new ArgumentException("Passage duration cannot exceed 10 days.");
        if (PassageDays * 24 + PassageHours == 0)
            throw new ArgumentException("Passage duration must be greater than zero.");
        if (!Enum.IsDefined(ForecastSource) || (!UseNoaa && !UseEcmwf))
            throw new ArgumentException("Select a forecast source and at least one model.");
        if (ForecastSource == PlanningForecastSource.LocalFile &&
            (string.IsNullOrWhiteSpace(LocalGribPath) || !Path.IsPathFullyQualified(LocalGribPath)))
            throw new ArgumentException("Choose an absolute local GRIB file path.");
    }
}

public sealed record RoutingSetupPreferences
{
    public BoatAsset? Boat { get; init; }
    public RoutingQuality Quality { get; init; } = RoutingQuality.NativeBalanced;
    public double PerformanceFactor { get; init; } = 1;
    public double ArrivalRadiusNauticalMiles { get; init; } = 1;
    public RoutingLandSource LandSource { get; init; } = RoutingLandSource.NaturalEarth;
    public ForecastRefreshPolicy ForecastPolicy { get; init; } = ForecastRefreshPolicy.PreferCache;
    public double LocalForecastMaximumGapHours { get; init; } = 6;
    public RouteRegionalLandPolicy? RegionalLand { get; init; }
    public double HardDurationHours { get; init; } = 240;

    public void Validate()
    {
        if (!Enum.IsDefined(Quality) || !Enum.IsDefined(LandSource) || !Enum.IsDefined(ForecastPolicy) ||
            !double.IsFinite(PerformanceFactor) || PerformanceFactor <= 0 ||
            !double.IsFinite(ArrivalRadiusNauticalMiles) || ArrivalRadiusNauticalMiles <= 0 ||
            !double.IsFinite(LocalForecastMaximumGapHours) || LocalForecastMaximumGapHours <= 0 ||
            LocalForecastMaximumGapHours > TimeSpan.MaxValue.TotalHours ||
            !double.IsFinite(HardDurationHours) || HardDurationHours <= 0 ||
            HardDurationHours % 1 != 0 || HardDurationHours > TimeSpan.MaxValue.TotalHours)
            throw new ArgumentException("Routing preferences contain invalid values.");
        if (LandSource == RoutingLandSource.RegionalGshhg && RegionalLand is null)
            throw new ArgumentException("Regional GSHHG requires a source and bounded study policy.");
    }
}

/// <summary>Remember tuning values, never session activation or illustrative provider enablement.</summary>
public sealed record AdvancedRoutingPreferences
{
    public RouteSolver SelectedRouteSolver { get; init; } = RouteSolver.IsochroneBeam;
    public int TackPenaltySeconds { get; init; }
    public int GybePenaltySeconds { get; init; }
    public double DownwindTrueWindAngleDegrees { get; init; } = 150;
    public RouteHeadingAugmentation HeadingAugmentation { get; init; } = RouteHeadingAugmentation.DestinationBearingAndVelocityMadeGood;
    public RouteWindSampling WindSampling { get; init; } = RouteWindSampling.Midpoint;
    public int MidpointWindSamplingThresholdMinutes { get; init; }
    public RoutePolarAngleInterpolation PolarAngleInterpolation { get; init; } = RoutePolarAngleInterpolation.MonotoneCubic;
    public double MaximumTrueWindSpeedKnots { get; init; } = 45;
    public RouteAbovePolarRangePolicy AbovePolarRange { get; init; } = RouteAbovePolarRangePolicy.NoSpeed;
    public RoutePruningStrategy PruningStrategy { get; init; } = RoutePruningStrategy.DestinationDistanceGrid;
    public double PruningSectorDegrees { get; init; } = 2;
    public double DestinationFrontHalfAngleDegrees { get; init; } = 120;
    public RouteDestinationFrontSegmentPolicy DestinationFrontSegmentPolicy { get; init; } = RouteDestinationFrontSegmentPolicy.ProvisionalComponent;
    public int DestinationFrontMinimumSecondarySegmentPoints { get; init; } = 3;
    public int LatticeSubdivisionLevel { get; init; } = 4;
    public int LatticeTimeBucketMinutes { get; init; } = 30;
    public int LatticeRefinementLevels { get; init; } = 1;
    public double LatticeCorridorWidthNauticalMiles { get; init; } = 450;
    public int LatticeCorridorWideningRetries { get; init; } = 2;
    public int LatticeProgressEveryExpansions { get; init; } = 250;
    public RouteLatticeSearchAlgorithm LatticeSearchAlgorithm { get; init; } = RouteLatticeSearchAlgorithm.AStar;
    public double CurrentEastKnots { get; init; }
    public double CurrentNorthKnots { get; init; }
    public RouteMissingDataPolicy CurrentMissingDataPolicy { get; init; } = RouteMissingDataPolicy.FailRoute;
    public double SignificantWaveHeightMetres { get; init; } = 2;
    public double WavePeriodSeconds { get; init; } = 8;
    public double WaveFromDirectionDegrees { get; init; }
    public RouteMissingDataPolicy WaveMissingDataPolicy { get; init; } = RouteMissingDataPolicy.FailRoute;
    public RouteLandAvoidanceMode LandAvoidanceMode { get; init; } = RouteLandAvoidanceMode.SegmentEligibilityCallback;
    public double LandmaskResolutionNauticalMiles { get; init; } = 5;
    public double LandmaskClearanceNauticalMiles { get; init; }
    public int LandmaskMaximumSubdivisionDepth { get; init; } = 12;
    public RouteMissingDataPolicy LandmaskMissingDataPolicy { get; init; } = RouteMissingDataPolicy.RejectTransition;
    public RouteExclusionBoundaryPolicy ExclusionBoundaryPolicy { get; init; } = RouteExclusionBoundaryPolicy.BoundaryExcluded;
    public RouteEnvironmentSampling EnvironmentSampling { get; init; } = RouteEnvironmentSampling.SegmentStart;

    public void Validate()
    {
        _ = new RouteOptimizationOptions(SelectedRouteSolver,
            new RouteManeuverOptions(TimeSpan.FromSeconds(TackPenaltySeconds), TimeSpan.FromSeconds(GybePenaltySeconds), DownwindTrueWindAngleDegrees),
            HeadingAugmentation, WindSampling, TimeSpan.FromMinutes(MidpointWindSamplingThresholdMinutes),
            PolarAngleInterpolation, MaximumTrueWindSpeedKnots, AbovePolarRange, PruningStrategy, PruningSectorDegrees,
            new RouteDestinationFrontOptions(DestinationFrontHalfAngleDegrees, DestinationFrontSegmentPolicy, DestinationFrontMinimumSecondarySegmentPoints),
            new RouteLatticeOptions(LatticeSubdivisionLevel, TimeSpan.FromMinutes(LatticeTimeBucketMinutes),
                LatticeRefinementLevels, LatticeCorridorWidthNauticalMiles, LatticeCorridorWideningRetries,
                LatticeProgressEveryExpansions, LatticeSearchAlgorithm));
        _ = new RouteLandmaskRequest(LandmaskResolutionNauticalMiles, LandmaskClearanceNauticalMiles,
            LandmaskMaximumSubdivisionDepth, LandmaskMissingDataPolicy);
        var metadata = new RouteProviderMetadata("Remembered settings", "Navtool", "manual");
        _ = RouteCurrentOptions.Uniform(CurrentEastKnots, CurrentNorthKnots, metadata, CurrentMissingDataPolicy);
        _ = RouteWaveOptions.Uniform(SignificantWaveHeightMetres, WavePeriodSeconds, WaveFromDirectionDegrees,
            metadata, missingDataPolicy: WaveMissingDataPolicy);
        if (!Enum.IsDefined(LandAvoidanceMode) || !Enum.IsDefined(ExclusionBoundaryPolicy) || !Enum.IsDefined(EnvironmentSampling))
            throw new ArgumentException("Invalid advanced environment preference.");
    }
}

public sealed record RoutingUserPreferences
{
    [System.Text.Json.Serialization.JsonRequired]
    public int SchemaVersion { get; init; } = 1;
    [System.Text.Json.Serialization.JsonRequired]
    public RoutingSetupPreferences Setup { get; init; } = new();
    [System.Text.Json.Serialization.JsonRequired]
    public RoutePlanningInputs Planning { get; init; } = new();
    [System.Text.Json.Serialization.JsonRequired]
    public AdvancedRoutingPreferences Advanced { get; init; } = new();

    public void Validate()
    {
        if (SchemaVersion != 1 || Setup is null || Planning is null || Advanced is null)
            throw new ArgumentException("Unsupported or incomplete routing preferences.");
        Setup.Validate();
        Planning.Validate();
        Advanced.Validate();
        if (!Planning.DepartureNow || Planning.ScheduledDepartureUtc is not null)
            throw new ArgumentException("An absolute departure cannot be a user default.");
    }
}

public interface IRoutingPreferencesRepository
{
    RoutingUserPreferences? Load();
    void Save(RoutingUserPreferences preferences);
}
