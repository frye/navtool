namespace Navtool.Core;

public enum RouteSolver
{
    IsochroneBeam,
    TimeDependentLattice
}

public enum RouteHeadingAugmentation
{
    None,
    DestinationBearing,
    VelocityMadeGood,
    DestinationBearingAndVelocityMadeGood
}

public enum RouteWindSampling
{
    SegmentStart,
    Midpoint
}

public enum RoutePolarAngleInterpolation
{
    Linear,
    MonotoneCubic
}

public enum RouteAbovePolarRangePolicy
{
    Clamp,
    NoSpeed
}

public enum RoutePruningStrategy
{
    DestinationDistanceGrid,
    BearingSectors
}

public enum RouteDestinationFrontSegmentPolicy
{
    ProvisionalComponent,
    AllMeaningfulComponents
}

public enum RouteLatticeSearchAlgorithm
{
    AStar,
    Dijkstra
}

public sealed record RouteManeuverOptions
{
    public RouteManeuverOptions(
        TimeSpan tackPenalty,
        TimeSpan gybePenalty,
        double downwindTrueWindAngleDegrees = 150)
    {
        if (tackPenalty < TimeSpan.Zero)
        {
            throw new ArgumentOutOfRangeException(nameof(tackPenalty));
        }

        if (gybePenalty < TimeSpan.Zero)
        {
            throw new ArgumentOutOfRangeException(nameof(gybePenalty));
        }

        if (!double.IsFinite(downwindTrueWindAngleDegrees) ||
            downwindTrueWindAngleDegrees is < 0 or > 180)
        {
            throw new ArgumentOutOfRangeException(nameof(downwindTrueWindAngleDegrees));
        }

        TackPenalty = tackPenalty;
        GybePenalty = gybePenalty;
        DownwindTrueWindAngleDegrees = downwindTrueWindAngleDegrees;
    }

    public TimeSpan TackPenalty { get; }

    public TimeSpan GybePenalty { get; }

    public double DownwindTrueWindAngleDegrees { get; }

    public static RouteManeuverOptions None { get; } = new(TimeSpan.Zero, TimeSpan.Zero);
}

public sealed record RouteDestinationFrontOptions
{
    public RouteDestinationFrontOptions(
        double halfAngleDegrees = 120,
        RouteDestinationFrontSegmentPolicy segmentPolicy =
            RouteDestinationFrontSegmentPolicy.ProvisionalComponent,
        int minimumSecondarySegmentPoints = 3)
    {
        if (!double.IsFinite(halfAngleDegrees) || halfAngleDegrees is <= 0 or > 180)
        {
            throw new ArgumentOutOfRangeException(nameof(halfAngleDegrees));
        }

        if (!Enum.IsDefined(segmentPolicy))
        {
            throw new ArgumentOutOfRangeException(nameof(segmentPolicy));
        }

        if (minimumSecondarySegmentPoints <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(minimumSecondarySegmentPoints));
        }

        HalfAngleDegrees = halfAngleDegrees;
        SegmentPolicy = segmentPolicy;
        MinimumSecondarySegmentPoints = minimumSecondarySegmentPoints;
    }

    public double HalfAngleDegrees { get; }

    public RouteDestinationFrontSegmentPolicy SegmentPolicy { get; }

    public int MinimumSecondarySegmentPoints { get; }
}

public sealed record RouteLatticeOptions
{
    public const int MaximumCombinedSubdivisionLevel = 8;

    public RouteLatticeOptions(
        int subdivisionLevel = 4,
        TimeSpan? timeBucket = null,
        int refinementLevels = 1,
        double corridorWidthNauticalMiles = 450,
        int corridorWideningRetries = 2,
        int progressEveryExpansions = 250,
        RouteLatticeSearchAlgorithm searchAlgorithm = RouteLatticeSearchAlgorithm.AStar)
    {
        var effectiveTimeBucket = timeBucket ?? TimeSpan.FromMinutes(30);
        if (subdivisionLevel < 0)
        {
            throw new ArgumentOutOfRangeException(nameof(subdivisionLevel));
        }

        if (refinementLevels < 0 ||
            subdivisionLevel + refinementLevels > MaximumCombinedSubdivisionLevel)
        {
            throw new ArgumentOutOfRangeException(nameof(refinementLevels));
        }

        if (effectiveTimeBucket <= TimeSpan.Zero ||
            effectiveTimeBucket.Ticks % TimeSpan.TicksPerMinute != 0)
        {
            throw new ArgumentOutOfRangeException(nameof(timeBucket));
        }

        if (!double.IsFinite(corridorWidthNauticalMiles) ||
            corridorWidthNauticalMiles <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(corridorWidthNauticalMiles));
        }

        if (corridorWideningRetries < 0)
        {
            throw new ArgumentOutOfRangeException(nameof(corridorWideningRetries));
        }

        if (progressEveryExpansions <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(progressEveryExpansions));
        }

        if (!Enum.IsDefined(searchAlgorithm))
        {
            throw new ArgumentOutOfRangeException(nameof(searchAlgorithm));
        }

        SubdivisionLevel = subdivisionLevel;
        TimeBucket = effectiveTimeBucket;
        RefinementLevels = refinementLevels;
        CorridorWidthNauticalMiles = corridorWidthNauticalMiles;
        CorridorWideningRetries = corridorWideningRetries;
        ProgressEveryExpansions = progressEveryExpansions;
        SearchAlgorithm = searchAlgorithm;
    }

    public int SubdivisionLevel { get; }

    public TimeSpan TimeBucket { get; }

    public int RefinementLevels { get; }

    public double CorridorWidthNauticalMiles { get; }

    public int CorridorWideningRetries { get; }

    public int ProgressEveryExpansions { get; }

    public RouteLatticeSearchAlgorithm SearchAlgorithm { get; }
}

public sealed record RouteOptimizationOptions
{
    public RouteOptimizationOptions(
        RouteSolver solver = RouteSolver.IsochroneBeam,
        RouteManeuverOptions? maneuver = null,
        RouteHeadingAugmentation headingAugmentation =
            RouteHeadingAugmentation.DestinationBearingAndVelocityMadeGood,
        RouteWindSampling windSampling = RouteWindSampling.Midpoint,
        TimeSpan? midpointWindSamplingThreshold = null,
        RoutePolarAngleInterpolation polarAngleInterpolation =
            RoutePolarAngleInterpolation.MonotoneCubic,
        double? maximumTrueWindSpeedKnots = null,
        RouteAbovePolarRangePolicy abovePolarRange = RouteAbovePolarRangePolicy.Clamp,
        RoutePruningStrategy pruningStrategy = RoutePruningStrategy.DestinationDistanceGrid,
        double pruningSectorDegrees = 2,
        RouteDestinationFrontOptions? destinationFront = null,
        RouteLatticeOptions? lattice = null)
    {
        if (!Enum.IsDefined(solver))
        {
            throw new ArgumentOutOfRangeException(nameof(solver));
        }

        if (!Enum.IsDefined(headingAugmentation))
        {
            throw new ArgumentOutOfRangeException(nameof(headingAugmentation));
        }

        if (!Enum.IsDefined(windSampling))
        {
            throw new ArgumentOutOfRangeException(nameof(windSampling));
        }

        if (!Enum.IsDefined(polarAngleInterpolation))
        {
            throw new ArgumentOutOfRangeException(nameof(polarAngleInterpolation));
        }

        if (!Enum.IsDefined(abovePolarRange))
        {
            throw new ArgumentOutOfRangeException(nameof(abovePolarRange));
        }

        if (!Enum.IsDefined(pruningStrategy))
        {
            throw new ArgumentOutOfRangeException(nameof(pruningStrategy));
        }

        var effectiveThreshold = midpointWindSamplingThreshold ?? TimeSpan.Zero;
        if (effectiveThreshold < TimeSpan.Zero ||
            effectiveThreshold.Ticks % TimeSpan.TicksPerMinute != 0)
        {
            throw new ArgumentOutOfRangeException(nameof(midpointWindSamplingThreshold));
        }

        if (maximumTrueWindSpeedKnots is { } maximumWind &&
            (!double.IsFinite(maximumWind) || maximumWind <= 0))
        {
            throw new ArgumentOutOfRangeException(nameof(maximumTrueWindSpeedKnots));
        }

        if (!double.IsFinite(pruningSectorDegrees) ||
            pruningSectorDegrees is <= 0 or > 180)
        {
            throw new ArgumentOutOfRangeException(nameof(pruningSectorDegrees));
        }

        Solver = solver;
        Maneuver = maneuver ?? RouteManeuverOptions.None;
        HeadingAugmentation = headingAugmentation;
        WindSampling = windSampling;
        MidpointWindSamplingThreshold = effectiveThreshold;
        PolarAngleInterpolation = polarAngleInterpolation;
        MaximumTrueWindSpeedKnots = maximumTrueWindSpeedKnots;
        AbovePolarRange = abovePolarRange;
        PruningStrategy = pruningStrategy;
        PruningSectorDegrees = pruningSectorDegrees;
        DestinationFront = destinationFront ?? new RouteDestinationFrontOptions();
        Lattice = lattice ?? new RouteLatticeOptions();
    }

    public RouteSolver Solver { get; }

    public RouteManeuverOptions Maneuver { get; }

    public RouteHeadingAugmentation HeadingAugmentation { get; }

    public RouteWindSampling WindSampling { get; }

    public TimeSpan MidpointWindSamplingThreshold { get; }

    public RoutePolarAngleInterpolation PolarAngleInterpolation { get; }

    public double? MaximumTrueWindSpeedKnots { get; }

    public RouteAbovePolarRangePolicy AbovePolarRange { get; }

    public RoutePruningStrategy PruningStrategy { get; }

    public double PruningSectorDegrees { get; }

    public RouteDestinationFrontOptions DestinationFront { get; }

    public RouteLatticeOptions Lattice { get; }

    public static RouteOptimizationOptions Balanced { get; } = new();

    public static RouteOptimizationOptions UpstreamCompatible { get; } = new(
        headingAugmentation: RouteHeadingAugmentation.None,
        windSampling: RouteWindSampling.SegmentStart,
        polarAngleInterpolation: RoutePolarAngleInterpolation.Linear);
}
