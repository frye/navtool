namespace Navtool.Core;

/// <summary>
/// What to do when a configured environmental provider has no usable sample.
/// Missing data is never reinterpreted as zero current, calm sea, or open water.
/// </summary>
public enum RouteMissingDataPolicy
{
    /// <summary>Abandons the whole route. This is router-lib's default.</summary>
    FailRoute,

    /// <summary>Rejects only the transition that could not be evaluated.</summary>
    RejectTransition
}

/// <summary>Whether a zone boundary counts as inside the exclusion.</summary>
public enum RouteExclusionBoundaryPolicy
{
    BoundaryExcluded,
    BoundaryAllowed
}

/// <summary>Where along a transition the environment is sampled.</summary>
public enum RouteEnvironmentSampling
{
    SegmentStart,
    Midpoint
}

/// <summary>Which environmental provider backs the land avoidance check.</summary>
public enum RouteLandAvoidanceMode
{
    /// <summary>
    /// Navtool's own NetTopologySuite segment-eligibility callback. This is the
    /// default and matches every release before Stage 3.
    /// </summary>
    SegmentEligibilityCallback,

    /// <summary>router-lib's built-in signed-distance landmask.</summary>
    SignedDistanceLandmask
}

/// <summary>Attribution of an environmental data source or model.</summary>
public sealed record RouteProviderMetadata
{
    public RouteProviderMetadata(string name, string source, string revision)
    {
        if (string.IsNullOrWhiteSpace(name))
        {
            throw new ArgumentException("A provider name is required.", nameof(name));
        }

        if (string.IsNullOrWhiteSpace(source))
        {
            throw new ArgumentException("A provider source is required.", nameof(source));
        }

        Name = name;
        Source = source;
        Revision = revision ?? string.Empty;
    }

    public string Name { get; }

    /// <summary>Human-readable attribution of the underlying data or formula.</summary>
    public string Source { get; }

    /// <summary>Dataset or model revision, free-form but stable for a given input.</summary>
    public string Revision { get; }
}

/// <summary>
/// A regular latitude/longitude sample grid. Values are row-major from the
/// south-west corner at index <c>row * LongitudeCount + column</c>, with row
/// increasing north and column increasing east.
/// </summary>
public sealed record RouteEnvironmentGrid
{
    public RouteEnvironmentGrid(
        double southLatitudeDegrees,
        double westLongitudeDegrees,
        double latitudeStepDegrees,
        double longitudeStepDegrees,
        int latitudeCount,
        int longitudeCount,
        bool globalLongitudeCoverage = false)
    {
        if (!double.IsFinite(southLatitudeDegrees) || southLatitudeDegrees is < -90 or > 90)
        {
            throw new ArgumentOutOfRangeException(nameof(southLatitudeDegrees));
        }

        if (!double.IsFinite(westLongitudeDegrees) || westLongitudeDegrees is < -180 or > 180)
        {
            throw new ArgumentOutOfRangeException(nameof(westLongitudeDegrees));
        }

        if (!double.IsFinite(latitudeStepDegrees) || latitudeStepDegrees <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(latitudeStepDegrees));
        }

        if (!double.IsFinite(longitudeStepDegrees) || longitudeStepDegrees <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(longitudeStepDegrees));
        }

        // Bilinear interpolation needs two nodes on each axis, so a degenerate
        // grid is rejected here rather than at the ABI boundary.
        if (latitudeCount < 2)
        {
            throw new ArgumentOutOfRangeException(nameof(latitudeCount));
        }

        if (longitudeCount < 2)
        {
            throw new ArgumentOutOfRangeException(nameof(longitudeCount));
        }

        SouthLatitudeDegrees = southLatitudeDegrees;
        WestLongitudeDegrees = westLongitudeDegrees;
        LatitudeStepDegrees = latitudeStepDegrees;
        LongitudeStepDegrees = longitudeStepDegrees;
        LatitudeCount = latitudeCount;
        LongitudeCount = longitudeCount;
        GlobalLongitudeCoverage = globalLongitudeCoverage;
    }

    public double SouthLatitudeDegrees { get; }

    public double WestLongitudeDegrees { get; }

    public double LatitudeStepDegrees { get; }

    public double LongitudeStepDegrees { get; }

    public int LatitudeCount { get; }

    public int LongitudeCount { get; }

    public bool GlobalLongitudeCoverage { get; }

    public int SampleCount => LatitudeCount * LongitudeCount;

    public double NorthLatitudeDegrees =>
        SouthLatitudeDegrees + (LatitudeStepDegrees * (LatitudeCount - 1));

    public double EastLongitudeDegrees =>
        WestLongitudeDegrees + (LongitudeStepDegrees * (LongitudeCount - 1));

    internal void RequireSampleCount(IReadOnlyList<double> values, string parameterName)
    {
        ArgumentNullException.ThrowIfNull(values, parameterName);
        if (values.Count != SampleCount)
        {
            throw new ArgumentException(
                $"Expected {SampleCount} samples to match the grid but received {values.Count}.",
                parameterName);
        }

        for (var index = 0; index < values.Count; index++)
        {
            if (!double.IsFinite(values[index]))
            {
                throw new ArgumentException(
                    $"Sample {index} is not finite. Absent data must be modelled by " +
                    "shrinking the grid, never by a sentinel value.",
                    parameterName);
            }
        }
    }
}

/// <summary>
/// Surface current, as an east/north vector in knots pointing the way the water
/// flows (the oceanographic set convention, opposite to meteorological wind).
/// </summary>
public sealed record RouteCurrentOptions
{
    private RouteCurrentOptions(
        double? uniformEastKnots,
        double? uniformNorthKnots,
        RouteEnvironmentGrid? grid,
        IReadOnlyList<double>? eastKnots,
        IReadOnlyList<double>? northKnots,
        RouteMissingDataPolicy missingDataPolicy,
        RouteProviderMetadata metadata)
    {
        UniformEastKnots = uniformEastKnots;
        UniformNorthKnots = uniformNorthKnots;
        Grid = grid;
        EastKnots = eastKnots;
        NorthKnots = northKnots;
        MissingDataPolicy = missingDataPolicy;
        Metadata = metadata;
    }

    public static RouteCurrentOptions Uniform(
        double eastKnots,
        double northKnots,
        RouteProviderMetadata metadata,
        RouteMissingDataPolicy missingDataPolicy = RouteMissingDataPolicy.FailRoute)
    {
        ArgumentNullException.ThrowIfNull(metadata);
        if (!double.IsFinite(eastKnots))
        {
            throw new ArgumentOutOfRangeException(nameof(eastKnots));
        }

        if (!double.IsFinite(northKnots))
        {
            throw new ArgumentOutOfRangeException(nameof(northKnots));
        }

        if (!Enum.IsDefined(missingDataPolicy))
        {
            throw new ArgumentOutOfRangeException(nameof(missingDataPolicy));
        }

        return new RouteCurrentOptions(
            eastKnots,
            northKnots,
            grid: null,
            eastKnots: null,
            northKnots: null,
            missingDataPolicy,
            metadata);
    }

    public static RouteCurrentOptions FromGrid(
        RouteEnvironmentGrid grid,
        IReadOnlyList<double> eastKnots,
        IReadOnlyList<double> northKnots,
        RouteProviderMetadata metadata,
        RouteMissingDataPolicy missingDataPolicy = RouteMissingDataPolicy.FailRoute)
    {
        ArgumentNullException.ThrowIfNull(grid);
        ArgumentNullException.ThrowIfNull(metadata);
        if (!Enum.IsDefined(missingDataPolicy))
        {
            throw new ArgumentOutOfRangeException(nameof(missingDataPolicy));
        }

        grid.RequireSampleCount(eastKnots, nameof(eastKnots));
        grid.RequireSampleCount(northKnots, nameof(northKnots));

        return new RouteCurrentOptions(
            uniformEastKnots: null,
            uniformNorthKnots: null,
            grid,
            eastKnots,
            northKnots,
            missingDataPolicy,
            metadata);
    }

    public double? UniformEastKnots { get; }

    public double? UniformNorthKnots { get; }

    public RouteEnvironmentGrid? Grid { get; }

    public IReadOnlyList<double>? EastKnots { get; }

    public IReadOnlyList<double>? NorthKnots { get; }

    public RouteMissingDataPolicy MissingDataPolicy { get; }

    public RouteProviderMetadata Metadata { get; }

    public bool IsUniform => Grid is null;
}

/// <summary>
/// Coefficients of router-lib's built-in significant-wave-height derating model.
/// The retained speed fraction is
/// <c>1 - min(MaximumLossFraction, HeightCoefficient * Hs^HeightExponent * directional)</c>,
/// where the directional factor interpolates between <see cref="FollowingSeaFactor"/>,
/// one at a beam sea, and <see cref="HeadSeaFactor"/>.
/// </summary>
public sealed record RouteWaveDeratingCoefficients
{
    public RouteWaveDeratingCoefficients(
        double heightCoefficient = 0.03,
        double heightExponent = 1.5,
        double headSeaFactor = 1.6,
        double followingSeaFactor = 0.35,
        double maximumLossFraction = 0.6,
        double periodSensitivity = 0.0,
        double referencePeriodSeconds = 8.0,
        double minimumPeriodSeconds = 2.0)
    {
        RequireNonNegative(heightCoefficient, nameof(heightCoefficient));
        RequirePositive(heightExponent, nameof(heightExponent));
        RequireNonNegative(headSeaFactor, nameof(headSeaFactor));
        RequireNonNegative(followingSeaFactor, nameof(followingSeaFactor));
        RequireNonNegative(periodSensitivity, nameof(periodSensitivity));
        RequirePositive(referencePeriodSeconds, nameof(referencePeriodSeconds));
        RequirePositive(minimumPeriodSeconds, nameof(minimumPeriodSeconds));

        // A loss fraction of one or more would let the model stop the vessel
        // outright, which router-lib treats as an invalid environment.
        if (!double.IsFinite(maximumLossFraction) || maximumLossFraction is <= 0 or >= 1)
        {
            throw new ArgumentOutOfRangeException(nameof(maximumLossFraction));
        }

        if (minimumPeriodSeconds > referencePeriodSeconds)
        {
            throw new ArgumentOutOfRangeException(
                nameof(minimumPeriodSeconds),
                "The minimum period must not exceed the reference period.");
        }

        HeightCoefficient = heightCoefficient;
        HeightExponent = heightExponent;
        HeadSeaFactor = headSeaFactor;
        FollowingSeaFactor = followingSeaFactor;
        MaximumLossFraction = maximumLossFraction;
        PeriodSensitivity = periodSensitivity;
        ReferencePeriodSeconds = referencePeriodSeconds;
        MinimumPeriodSeconds = minimumPeriodSeconds;
    }

    private static void RequireNonNegative(double value, string parameterName)
    {
        if (!double.IsFinite(value) || value < 0)
        {
            throw new ArgumentOutOfRangeException(parameterName);
        }
    }

    private static void RequirePositive(double value, string parameterName)
    {
        if (!double.IsFinite(value) || value <= 0)
        {
            throw new ArgumentOutOfRangeException(parameterName);
        }
    }

    public double HeightCoefficient { get; }

    public double HeightExponent { get; }

    public double HeadSeaFactor { get; }

    public double FollowingSeaFactor { get; }

    public double MaximumLossFraction { get; }

    public double PeriodSensitivity { get; }

    public double ReferencePeriodSeconds { get; }

    public double MinimumPeriodSeconds { get; }

    public static RouteWaveDeratingCoefficients Default { get; } = new();
}

/// <summary>
/// Sea state and the performance model applied to it. Significant height is
/// metres, period is seconds, and direction is the meteorological direction the
/// waves come <em>from</em>, degrees true.
/// </summary>
public sealed record RouteWaveOptions
{
    private RouteWaveOptions(
        double? uniformSignificantHeightMetres,
        double? uniformPeakPeriodSeconds,
        double? uniformDirectionFromDegrees,
        RouteEnvironmentGrid? grid,
        IReadOnlyList<double>? significantHeightMetres,
        IReadOnlyList<double>? peakPeriodSeconds,
        IReadOnlyList<double>? directionFromDegrees,
        RouteWaveDeratingCoefficients derating,
        RouteMissingDataPolicy missingDataPolicy,
        RouteProviderMetadata metadata)
    {
        UniformSignificantHeightMetres = uniformSignificantHeightMetres;
        UniformPeakPeriodSeconds = uniformPeakPeriodSeconds;
        UniformDirectionFromDegrees = uniformDirectionFromDegrees;
        Grid = grid;
        SignificantHeightMetres = significantHeightMetres;
        PeakPeriodSeconds = peakPeriodSeconds;
        DirectionFromDegrees = directionFromDegrees;
        Derating = derating;
        MissingDataPolicy = missingDataPolicy;
        Metadata = metadata;
    }

    public static RouteWaveOptions Uniform(
        double significantHeightMetres,
        double peakPeriodSeconds,
        double directionFromDegrees,
        RouteProviderMetadata metadata,
        RouteWaveDeratingCoefficients? derating = null,
        RouteMissingDataPolicy missingDataPolicy = RouteMissingDataPolicy.FailRoute)
    {
        ArgumentNullException.ThrowIfNull(metadata);
        RequireHeight(significantHeightMetres, nameof(significantHeightMetres));
        RequirePeriod(peakPeriodSeconds, nameof(peakPeriodSeconds));
        RequireDirection(directionFromDegrees, nameof(directionFromDegrees));
        if (!Enum.IsDefined(missingDataPolicy))
        {
            throw new ArgumentOutOfRangeException(nameof(missingDataPolicy));
        }

        return new RouteWaveOptions(
            significantHeightMetres,
            peakPeriodSeconds,
            directionFromDegrees,
            grid: null,
            significantHeightMetres: null,
            peakPeriodSeconds: null,
            directionFromDegrees: null,
            derating ?? RouteWaveDeratingCoefficients.Default,
            missingDataPolicy,
            metadata);
    }

    public static RouteWaveOptions FromGrid(
        RouteEnvironmentGrid grid,
        IReadOnlyList<double> significantHeightMetres,
        IReadOnlyList<double> peakPeriodSeconds,
        IReadOnlyList<double> directionFromDegrees,
        RouteProviderMetadata metadata,
        RouteWaveDeratingCoefficients? derating = null,
        RouteMissingDataPolicy missingDataPolicy = RouteMissingDataPolicy.FailRoute)
    {
        ArgumentNullException.ThrowIfNull(grid);
        ArgumentNullException.ThrowIfNull(metadata);
        if (!Enum.IsDefined(missingDataPolicy))
        {
            throw new ArgumentOutOfRangeException(nameof(missingDataPolicy));
        }

        grid.RequireSampleCount(significantHeightMetres, nameof(significantHeightMetres));
        grid.RequireSampleCount(peakPeriodSeconds, nameof(peakPeriodSeconds));
        grid.RequireSampleCount(directionFromDegrees, nameof(directionFromDegrees));

        for (var index = 0; index < significantHeightMetres.Count; index++)
        {
            RequireHeight(significantHeightMetres[index], nameof(significantHeightMetres));
            RequirePeriod(peakPeriodSeconds[index], nameof(peakPeriodSeconds));
            RequireDirection(directionFromDegrees[index], nameof(directionFromDegrees));
        }

        return new RouteWaveOptions(
            uniformSignificantHeightMetres: null,
            uniformPeakPeriodSeconds: null,
            uniformDirectionFromDegrees: null,
            grid,
            significantHeightMetres,
            peakPeriodSeconds,
            directionFromDegrees,
            derating ?? RouteWaveDeratingCoefficients.Default,
            missingDataPolicy,
            metadata);
    }

    private static void RequireHeight(double value, string parameterName)
    {
        if (!double.IsFinite(value) || value < 0)
        {
            throw new ArgumentOutOfRangeException(parameterName);
        }
    }

    private static void RequirePeriod(double value, string parameterName)
    {
        if (!double.IsFinite(value) || value <= 0)
        {
            throw new ArgumentOutOfRangeException(parameterName);
        }
    }

    private static void RequireDirection(double value, string parameterName)
    {
        if (!double.IsFinite(value) || value is < 0 or > 360)
        {
            throw new ArgumentOutOfRangeException(parameterName);
        }
    }

    public double? UniformSignificantHeightMetres { get; }

    public double? UniformPeakPeriodSeconds { get; }

    public double? UniformDirectionFromDegrees { get; }

    public RouteEnvironmentGrid? Grid { get; }

    public IReadOnlyList<double>? SignificantHeightMetres { get; }

    public IReadOnlyList<double>? PeakPeriodSeconds { get; }

    public IReadOnlyList<double>? DirectionFromDegrees { get; }

    public RouteWaveDeratingCoefficients Derating { get; }

    public RouteMissingDataPolicy MissingDataPolicy { get; }

    public RouteProviderMetadata Metadata { get; }

    public bool IsUniform => Grid is null;
}

/// <summary>
/// A signed-distance landmask sampled on a regular grid. Distances are nautical
/// miles, positive over water and negative over land.
/// </summary>
/// <summary>
/// A request to derive a signed-distance landmask from whatever land geometry
/// the route engine acquires. The grid itself cannot be built until the route
/// corridor and coastline are known, so callers that want the built-in landmask
/// express intent here and the engine produces the
/// <see cref="RouteLandmaskOptions"/> it marshals.
/// </summary>
public sealed record RouteLandmaskRequest
{
    public RouteLandmaskRequest(
        double resolutionNauticalMiles = 5,
        double clearanceNauticalMiles = 0,
        int maximumSubdivisionDepth = 12,
        RouteMissingDataPolicy missingDataPolicy = RouteMissingDataPolicy.RejectTransition)
    {
        if (!double.IsFinite(resolutionNauticalMiles) || resolutionNauticalMiles <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(resolutionNauticalMiles));
        }

        if (!double.IsFinite(clearanceNauticalMiles) || clearanceNauticalMiles < 0)
        {
            throw new ArgumentOutOfRangeException(nameof(clearanceNauticalMiles));
        }

        if (maximumSubdivisionDepth is < 1 or > 32)
        {
            throw new ArgumentOutOfRangeException(nameof(maximumSubdivisionDepth));
        }

        if (!Enum.IsDefined(missingDataPolicy))
        {
            throw new ArgumentOutOfRangeException(nameof(missingDataPolicy));
        }

        ResolutionNauticalMiles = resolutionNauticalMiles;
        ClearanceNauticalMiles = clearanceNauticalMiles;
        MaximumSubdivisionDepth = maximumSubdivisionDepth;
        MissingDataPolicy = missingDataPolicy;
    }

    public double ResolutionNauticalMiles { get; }

    public double ClearanceNauticalMiles { get; }

    public int MaximumSubdivisionDepth { get; }

    public RouteMissingDataPolicy MissingDataPolicy { get; }
}

public sealed record RouteLandmaskOptions
{
    public RouteLandmaskOptions(
        RouteEnvironmentGrid grid,
        IReadOnlyList<double> signedDistanceNauticalMiles,
        double resolutionNauticalMiles,
        double interpolationErrorNauticalMiles,
        RouteProviderMetadata metadata,
        double clearanceNauticalMiles = 0,
        int maximumSubdivisionDepth = 12,
        RouteMissingDataPolicy missingDataPolicy = RouteMissingDataPolicy.RejectTransition)
    {
        ArgumentNullException.ThrowIfNull(grid);
        ArgumentNullException.ThrowIfNull(metadata);
        grid.RequireSampleCount(signedDistanceNauticalMiles, nameof(signedDistanceNauticalMiles));

        if (!double.IsFinite(resolutionNauticalMiles) || resolutionNauticalMiles <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(resolutionNauticalMiles));
        }

        if (!double.IsFinite(interpolationErrorNauticalMiles) ||
            interpolationErrorNauticalMiles < 0)
        {
            throw new ArgumentOutOfRangeException(nameof(interpolationErrorNauticalMiles));
        }

        if (!double.IsFinite(clearanceNauticalMiles) || clearanceNauticalMiles < 0)
        {
            throw new ArgumentOutOfRangeException(nameof(clearanceNauticalMiles));
        }

        // router-lib rejects zero and anything above 32, so mirror that here
        // rather than surfacing the failure only after a native round trip.
        if (maximumSubdivisionDepth is < 1 or > 32)
        {
            throw new ArgumentOutOfRangeException(nameof(maximumSubdivisionDepth));
        }

        if (!Enum.IsDefined(missingDataPolicy))
        {
            throw new ArgumentOutOfRangeException(nameof(missingDataPolicy));
        }

        Grid = grid;
        SignedDistanceNauticalMiles = signedDistanceNauticalMiles;
        ResolutionNauticalMiles = resolutionNauticalMiles;
        InterpolationErrorNauticalMiles = interpolationErrorNauticalMiles;
        ClearanceNauticalMiles = clearanceNauticalMiles;
        MaximumSubdivisionDepth = maximumSubdivisionDepth;
        MissingDataPolicy = missingDataPolicy;
        Metadata = metadata;
    }

    public RouteEnvironmentGrid Grid { get; }

    public IReadOnlyList<double> SignedDistanceNauticalMiles { get; }

    /// <summary>Nominal node spacing of the sampled grid, nautical miles.</summary>
    public double ResolutionNauticalMiles { get; }

    /// <summary>
    /// Upper bound on the error of an interpolated distance. Segment
    /// certification adds this to the clearance, so a mask that under-reports
    /// its own error can never round a decision toward accepting land.
    /// </summary>
    public double InterpolationErrorNauticalMiles { get; }

    /// <summary>Water that must remain under the vessel, nautical miles.</summary>
    public double ClearanceNauticalMiles { get; }

    public int MaximumSubdivisionDepth { get; }

    public RouteMissingDataPolicy MissingDataPolicy { get; }

    public RouteProviderMetadata Metadata { get; }
}

/// <summary>One closed ring of an exclusion polygon. The ring is implicitly closed.</summary>
public sealed record RouteExclusionRing
{
    public RouteExclusionRing(IReadOnlyList<Coordinate> vertices)
    {
        ArgumentNullException.ThrowIfNull(vertices);

        // Three distinct vertices is the minimum that bounds any area at all.
        if (vertices.Count < 3)
        {
            throw new ArgumentException(
                "An exclusion ring needs at least three vertices.",
                nameof(vertices));
        }

        Vertices = vertices;
    }

    public IReadOnlyList<Coordinate> Vertices { get; }
}

/// <summary>One simple polygon of an exclusion zone, with optional holes.</summary>
public sealed record RouteExclusionPolygon
{
    public RouteExclusionPolygon(
        RouteExclusionRing outer,
        IReadOnlyList<RouteExclusionRing>? holes = null)
    {
        ArgumentNullException.ThrowIfNull(outer);
        Outer = outer;
        Holes = holes ?? Array.Empty<RouteExclusionRing>();
    }

    public RouteExclusionRing Outer { get; }

    public IReadOnlyList<RouteExclusionRing> Holes { get; }
}

/// <summary>
/// A versioned, optionally time-limited operational exclusion. The activation
/// window is the half-open UTC interval <c>[ActiveFrom, ActiveUntil)</c>; an
/// unset bound is open ended.
/// </summary>
public sealed record RouteExclusionZone
{
    public RouteExclusionZone(
        string identifier,
        string source,
        IReadOnlyList<RouteExclusionPolygon> polygons,
        ulong revision = 1,
        DateTimeOffset? activeFrom = null,
        DateTimeOffset? activeUntil = null)
    {
        if (string.IsNullOrWhiteSpace(identifier))
        {
            throw new ArgumentException("An exclusion zone identifier is required.", nameof(identifier));
        }

        if (string.IsNullOrWhiteSpace(source))
        {
            throw new ArgumentException("An exclusion zone source is required.", nameof(source));
        }

        ArgumentNullException.ThrowIfNull(polygons);
        if (polygons.Count == 0)
        {
            throw new ArgumentException(
                "An exclusion zone needs at least one polygon.",
                nameof(polygons));
        }

        if (activeFrom is { } from && activeUntil is { } until && until <= from)
        {
            throw new ArgumentException(
                "An exclusion zone's activation window must not be inverted or empty.",
                nameof(activeUntil));
        }

        Identifier = identifier;
        Source = source;
        Polygons = polygons;
        Revision = revision;
        ActiveFrom = activeFrom;
        ActiveUntil = activeUntil;
    }

    /// <summary>Stable identity, unique within a set, used for deterministic ordering.</summary>
    public string Identifier { get; }

    /// <summary>Attribution of the record, for example a notice-to-mariners reference.</summary>
    public string Source { get; }

    public ulong Revision { get; }

    public DateTimeOffset? ActiveFrom { get; }

    public DateTimeOffset? ActiveUntil { get; }

    public IReadOnlyList<RouteExclusionPolygon> Polygons { get; }
}

/// <summary>A validated set of exclusion zones and the boundary policy applied to them.</summary>
public sealed record RouteExclusionOptions
{
    public RouteExclusionOptions(
        IReadOnlyList<RouteExclusionZone> zones,
        RouteProviderMetadata metadata,
        RouteExclusionBoundaryPolicy boundaryPolicy =
            RouteExclusionBoundaryPolicy.BoundaryExcluded)
    {
        ArgumentNullException.ThrowIfNull(zones);
        ArgumentNullException.ThrowIfNull(metadata);
        if (zones.Count == 0)
        {
            throw new ArgumentException(
                "Configured exclusions need at least one zone. Leave exclusions " +
                "unconfigured instead of supplying an empty set.",
                nameof(zones));
        }

        if (!Enum.IsDefined(boundaryPolicy))
        {
            throw new ArgumentOutOfRangeException(nameof(boundaryPolicy));
        }

        var identifiers = new HashSet<string>(StringComparer.Ordinal);
        foreach (var zone in zones)
        {
            if (!identifiers.Add(zone.Identifier))
            {
                throw new ArgumentException(
                    $"Exclusion zone identifier '{zone.Identifier}' is not unique.",
                    nameof(zones));
            }
        }

        Zones = zones;
        Metadata = metadata;
        BoundaryPolicy = boundaryPolicy;
    }

    public IReadOnlyList<RouteExclusionZone> Zones { get; }

    public RouteProviderMetadata Metadata { get; }

    public RouteExclusionBoundaryPolicy BoundaryPolicy { get; }
}

/// <summary>
/// The complete opt-in Stage 3 environment. An instance with no configured
/// provider reproduces pre-Stage-3 route arithmetic exactly.
/// </summary>
public sealed record RouteEnvironmentOptions
{
    public RouteEnvironmentOptions(
        RouteCurrentOptions? currents = null,
        RouteWaveOptions? waves = null,
        RouteLandmaskOptions? land = null,
        RouteExclusionOptions? exclusions = null,
        RouteEnvironmentSampling sampling = RouteEnvironmentSampling.SegmentStart,
        RouteLandmaskRequest? landRequest = null)
    {
        if (!Enum.IsDefined(sampling))
        {
            throw new ArgumentOutOfRangeException(nameof(sampling));
        }

        // A built mask and a request to build one are contradictory; refusing
        // the combination stops a stale grid silently winning.
        if (land is not null && landRequest is not null)
        {
            throw new ArgumentException(
                "Supply either a built landmask or a request to derive one, not both.",
                nameof(landRequest));
        }

        // Midpoint sampling only means something when there is a field to
        // sample; router-lib rejects the combination outright.
        if (sampling == RouteEnvironmentSampling.Midpoint &&
            currents is null && waves is null && land is null &&
            exclusions is null && landRequest is null)
        {
            throw new ArgumentException(
                "Midpoint sampling requires at least one configured provider.",
                nameof(sampling));
        }

        Currents = currents;
        Waves = waves;
        Land = land;
        Exclusions = exclusions;
        Sampling = sampling;
        LandRequest = landRequest;
    }

    public RouteCurrentOptions? Currents { get; }

    public RouteWaveOptions? Waves { get; }

    public RouteLandmaskOptions? Land { get; }

    public RouteExclusionOptions? Exclusions { get; }

    public RouteEnvironmentSampling Sampling { get; }

    /// <summary>
    /// Set when the caller wants router-lib's signed-distance landmask but the
    /// grid has not been rasterized yet. The route engine resolves this into
    /// <see cref="Land"/> before marshalling.
    /// </summary>
    public RouteLandmaskRequest? LandRequest { get; }

    /// <summary>True when at least one provider is configured.</summary>
    public bool IsActive =>
        Currents is not null || Waves is not null || Land is not null ||
        Exclusions is not null || LandRequest is not null;

    /// <summary>
    /// Replaces an unresolved <see cref="LandRequest"/> with the mask the
    /// engine rasterized for the corridor.
    /// </summary>
    public RouteEnvironmentOptions WithResolvedLand(RouteLandmaskOptions? land) =>
        new(Currents, Waves, land, Exclusions, Sampling);

    /// <summary>An environment with nothing configured, equivalent to omitting it.</summary>
    public static RouteEnvironmentOptions None { get; } = new();
}
