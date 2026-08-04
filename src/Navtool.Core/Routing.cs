using System.Collections.Immutable;

namespace Navtool.Core;

public sealed record RouteRequest
{
    public RouteRequest(
        string routeId,
        Coordinate origin,
        Coordinate destination,
        DateTimeOffset departureTime,
        DateTimeOffset latestArrivalTime)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(routeId);
        RouteId = routeId;
        Origin = origin;
        Destination = destination;
        // Normalize departure to whole seconds so the managed request and the native
        // epoch-second departure agree exactly at the RouteResult boundary check.
        DepartureTime = NormalizeToWholeSeconds(departureTime);
        LatestArrivalTime = latestArrivalTime.ToUniversalTime();
    }

    private static DateTimeOffset NormalizeToWholeSeconds(DateTimeOffset value)
    {
        var utc = value.ToUniversalTime();
        return new DateTimeOffset(
            utc.Ticks - (utc.Ticks % TimeSpan.TicksPerSecond),
            TimeSpan.Zero);
    }

    public string RouteId { get; }

    public Coordinate Origin { get; }

    public Coordinate Destination { get; }

    public DateTimeOffset DepartureTime { get; }

    public DateTimeOffset LatestArrivalTime { get; }
}

public enum RouteValidationErrorCode
{
    IdenticalEndpoints,
    DepartureInPast,
    DepartureBeyondForecastHorizon,
    ArrivalNotAfterDeparture,
    RouteDurationTooLong
}

public sealed record RouteValidationError(RouteValidationErrorCode Code, string Message);

public sealed record RouteValidationOptions
{
    public RouteValidationOptions(
        TimeSpan maximumDepartureLeadTime,
        TimeSpan maximumRouteDuration,
        TimeSpan? pastTolerance = null)
    {
        if (maximumDepartureLeadTime <= TimeSpan.Zero)
        {
            throw new ArgumentOutOfRangeException(nameof(maximumDepartureLeadTime));
        }

        if (maximumRouteDuration <= TimeSpan.Zero)
        {
            throw new ArgumentOutOfRangeException(nameof(maximumRouteDuration));
        }

        if (pastTolerance < TimeSpan.Zero)
        {
            throw new ArgumentOutOfRangeException(nameof(pastTolerance));
        }

        MaximumDepartureLeadTime = maximumDepartureLeadTime;
        MaximumRouteDuration = maximumRouteDuration;
        PastTolerance = pastTolerance ?? TimeSpan.Zero;
    }

    public TimeSpan MaximumDepartureLeadTime { get; }

    public TimeSpan MaximumRouteDuration { get; }

    public TimeSpan PastTolerance { get; }
}

public sealed record RouteValidationResult
{
    public RouteValidationResult(IEnumerable<RouteValidationError> errors)
    {
        ArgumentNullException.ThrowIfNull(errors);
        Errors = errors.ToImmutableArray();
    }

    public ImmutableArray<RouteValidationError> Errors { get; }

    public bool IsValid => Errors.IsEmpty;
}

public interface IRouteRequestValidator
{
    RouteValidationResult Validate(
        RouteRequest request,
        DateTimeOffset now,
        RouteValidationOptions options);
}

public sealed class RouteRequestValidator : IRouteRequestValidator
{
    public RouteValidationResult Validate(
        RouteRequest request,
        DateTimeOffset now,
        RouteValidationOptions options)
    {
        ArgumentNullException.ThrowIfNull(request);
        ArgumentNullException.ThrowIfNull(options);
        var utcNow = now.ToUniversalTime();
        var errors = ImmutableArray.CreateBuilder<RouteValidationError>();

        if (request.Origin.IsSameLocation(request.Destination))
        {
            errors.Add(new(
                RouteValidationErrorCode.IdenticalEndpoints,
                "Origin and destination must be different."));
        }

        if (request.DepartureTime < utcNow - options.PastTolerance)
        {
            errors.Add(new(
                RouteValidationErrorCode.DepartureInPast,
                "Departure cannot be in the past."));
        }

        if (request.DepartureTime > utcNow + options.MaximumDepartureLeadTime)
        {
            errors.Add(new(
                RouteValidationErrorCode.DepartureBeyondForecastHorizon,
                "Departure is beyond the available forecast horizon."));
        }

        if (request.LatestArrivalTime <= request.DepartureTime)
        {
            errors.Add(new(
                RouteValidationErrorCode.ArrivalNotAfterDeparture,
                "Latest arrival must be after departure."));
        }
        else if (request.LatestArrivalTime - request.DepartureTime > options.MaximumRouteDuration)
        {
            errors.Add(new(
                RouteValidationErrorCode.RouteDurationTooLong,
                "The requested route duration is too long."));
        }

        return new RouteValidationResult(errors);
    }
}

public sealed record RoutePoint
{
    public RoutePoint(
        Coordinate location,
        DateTimeOffset timestamp,
        double headingDegrees,
        double boatSpeedKnots,
        double trueWindSpeedKnots,
        double trueWindDirectionDegrees,
        double cumulativeDistanceNauticalMiles)
    {
        ValidateDirection(headingDegrees, nameof(headingDegrees));
        ValidateNonNegative(boatSpeedKnots, nameof(boatSpeedKnots));
        ValidateNonNegative(trueWindSpeedKnots, nameof(trueWindSpeedKnots));
        ValidateDirection(trueWindDirectionDegrees, nameof(trueWindDirectionDegrees));
        ValidateNonNegative(cumulativeDistanceNauticalMiles, nameof(cumulativeDistanceNauticalMiles));

        Location = location;
        Timestamp = timestamp.ToUniversalTime();
        HeadingDegrees = headingDegrees;
        BoatSpeedKnots = boatSpeedKnots;
        TrueWindSpeedKnots = trueWindSpeedKnots;
        TrueWindDirectionDegrees = trueWindDirectionDegrees;
        CumulativeDistanceNauticalMiles = cumulativeDistanceNauticalMiles;
    }

    public Coordinate Location { get; }

    public DateTimeOffset Timestamp { get; }

    public double HeadingDegrees { get; }

    public double BoatSpeedKnots { get; }

    public double TrueWindSpeedKnots { get; }

    public double TrueWindDirectionDegrees { get; }

    public double CumulativeDistanceNauticalMiles { get; }

    public double ApparentWindAngleSignedDegrees
    {
        get
        {
            var (apparentEast, apparentNorth) = GetApparentWindVector();
            if (Math.Abs(apparentEast) < 1e-9 && Math.Abs(apparentNorth) < 1e-9)
            {
                return 0d;
            }

            var apparentFromDirection = NormalizeDirection(
                Math.Atan2(-apparentEast, -apparentNorth) * (180d / Math.PI));
            return NormalizeSignedAngle(apparentFromDirection - HeadingDegrees);
        }
    }

    public double ApparentWindAngleDegrees => Math.Abs(ApparentWindAngleSignedDegrees);

    public double ApparentWindSpeedKnots
    {
        get
        {
            var (apparentEast, apparentNorth) = GetApparentWindVector();
            return Math.Sqrt(
                (apparentEast * apparentEast) +
                (apparentNorth * apparentNorth));
        }
    }

    private (double East, double North) GetApparentWindVector()
    {
        var (trueWindEast, trueWindNorth) = ToVectorToward(
            TrueWindSpeedKnots,
            NormalizeDirection(TrueWindDirectionDegrees + 180d));
        var (boatEast, boatNorth) = ToVectorToward(BoatSpeedKnots, HeadingDegrees);
        return (trueWindEast - boatEast, trueWindNorth - boatNorth);
    }

    private static (double East, double North) ToVectorToward(double speed, double directionDegrees)
    {
        var radians = directionDegrees * (Math.PI / 180d);
        return (speed * Math.Sin(radians), speed * Math.Cos(radians));
    }

    private static double NormalizeDirection(double value)
    {
        var normalized = value % 360d;
        return normalized < 0d ? normalized + 360d : normalized;
    }

    private static double NormalizeSignedAngle(double value)
    {
        var normalized = (value + 180d) % 360d;
        if (normalized < 0d)
        {
            normalized += 360d;
        }

        normalized -= 180d;
        return normalized <= -180d ? 180d : normalized;
    }

    private static void ValidateDirection(double value, string parameterName)
    {
        if (!double.IsFinite(value) || value is < 0 or >= 360)
        {
            throw new ArgumentOutOfRangeException(
                parameterName,
                "Direction must be finite and between zero (inclusive) and 360 degrees (exclusive).");
        }
    }

    private static void ValidateNonNegative(double value, string parameterName)
    {
        if (!double.IsFinite(value) || value < 0)
        {
            throw new ArgumentOutOfRangeException(parameterName, "Value must be finite and nonnegative.");
        }
    }
}

public sealed record RouteDiagnostics
{
    public RouteDiagnostics(
        long expandedNodes,
        long generatedCandidates,
        long retainedCandidates,
        int timeSteps,
        TimeSpan? calculationDuration = null)
    {
        if (expandedNodes < 0)
        {
            throw new ArgumentOutOfRangeException(nameof(expandedNodes));
        }

        if (generatedCandidates < 0)
        {
            throw new ArgumentOutOfRangeException(nameof(generatedCandidates));
        }

        if (retainedCandidates < 0)
        {
            throw new ArgumentOutOfRangeException(nameof(retainedCandidates));
        }

        if (timeSteps < 0)
        {
            throw new ArgumentOutOfRangeException(nameof(timeSteps));
        }

        if (calculationDuration < TimeSpan.Zero)
        {
            throw new ArgumentOutOfRangeException(nameof(calculationDuration));
        }

        ExpandedNodes = expandedNodes;
        GeneratedCandidates = generatedCandidates;
        RetainedCandidates = retainedCandidates;
        TimeSteps = timeSteps;
        CalculationDuration = calculationDuration;
    }

    public long ExpandedNodes { get; }

    public long GeneratedCandidates { get; }

    public long RetainedCandidates { get; }

    public int TimeSteps { get; }

    public TimeSpan? CalculationDuration { get; }
}

public sealed record RouteLatticeSearchProgress
{
    public RouteLatticeSearchProgress(
        long settledLabels,
        long queuedLabels,
        long relaxedLabels,
        int refinementIndex,
        int subdivisionLevel)
    {
        if (settledLabels < 0 || queuedLabels < 0 || relaxedLabels < 0)
        {
            throw new ArgumentOutOfRangeException(nameof(settledLabels));
        }

        if (refinementIndex < 0 || subdivisionLevel < 0)
        {
            throw new ArgumentOutOfRangeException(nameof(refinementIndex));
        }

        SettledLabels = settledLabels;
        QueuedLabels = queuedLabels;
        RelaxedLabels = relaxedLabels;
        RefinementIndex = refinementIndex;
        SubdivisionLevel = subdivisionLevel;
    }

    public long SettledLabels { get; }

    public long QueuedLabels { get; }

    public long RelaxedLabels { get; }

    public int RefinementIndex { get; }

    public int SubdivisionLevel { get; }
}

public sealed record RouteLatticeDiagnostics
{
    public RouteLatticeDiagnostics(
        long settledLabels,
        long queuedLabels,
        long relaxedLabels,
        long waitTransitions,
        int refinementRuns,
        int acceptedRefinements,
        int subdivisionLevel,
        bool refinementFallback)
    {
        if (settledLabels < 0 || queuedLabels < 0 || relaxedLabels < 0 ||
            waitTransitions < 0)
        {
            throw new ArgumentOutOfRangeException(nameof(settledLabels));
        }

        if (refinementRuns < 0 || acceptedRefinements < 0 || subdivisionLevel < 0)
        {
            throw new ArgumentOutOfRangeException(nameof(refinementRuns));
        }

        SettledLabels = settledLabels;
        QueuedLabels = queuedLabels;
        RelaxedLabels = relaxedLabels;
        WaitTransitions = waitTransitions;
        RefinementRuns = refinementRuns;
        AcceptedRefinements = acceptedRefinements;
        SubdivisionLevel = subdivisionLevel;
        RefinementFallback = refinementFallback;
    }

    public long SettledLabels { get; }

    public long QueuedLabels { get; }

    public long RelaxedLabels { get; }

    public long WaitTransitions { get; }

    public int RefinementRuns { get; }

    public int AcceptedRefinements { get; }

    public int SubdivisionLevel { get; }

    public bool RefinementFallback { get; }
}

public sealed record RouteCalculationFrontSegment
{
    public RouteCalculationFrontSegment(IEnumerable<Coordinate> points)
    {
        ArgumentNullException.ThrowIfNull(points);
        var immutablePoints = points.ToImmutableArray();
        if (immutablePoints.IsEmpty)
        {
            throw new ArgumentException(
                "A routing front segment must contain at least one point.",
                nameof(points));
        }

        Points = immutablePoints;
    }

    public ImmutableArray<Coordinate> Points { get; }
}

public sealed record RouteCalculationEnvelopeSegment
{
    public RouteCalculationEnvelopeSegment(
        IEnumerable<Coordinate> points,
        bool closed)
    {
        ArgumentNullException.ThrowIfNull(points);
        var immutablePoints = points.ToImmutableArray();
        if (immutablePoints.IsEmpty)
        {
            throw new ArgumentException(
                "A routing envelope segment must contain at least one point.",
                nameof(points));
        }

        Points = immutablePoints;
        Closed = closed;
    }

    public ImmutableArray<Coordinate> Points { get; }

    public bool Closed { get; }
}

public sealed record RouteCalculationSnapshot
{
    public RouteCalculationSnapshot(
        DateTimeOffset frontierTime,
        IEnumerable<RouteCalculationEnvelopeSegment> envelopeSegments,
        IEnumerable<RouteCalculationFrontSegment> frontSegments,
        IEnumerable<RoutePoint> provisionalRoute,
        RouteDiagnostics diagnostics)
        : this(
            frontierTime,
            RouteSolver.IsochroneBeam,
            envelopeSegments,
            frontSegments,
            Array.Empty<Coordinate>(),
            provisionalRoute,
            diagnostics,
            null)
    {
    }

    public RouteCalculationSnapshot(
        DateTimeOffset frontierTime,
        RouteSolver solver,
        IEnumerable<RouteCalculationEnvelopeSegment> envelopeSegments,
        IEnumerable<RouteCalculationFrontSegment> frontSegments,
        IEnumerable<Coordinate> searchPoints,
        IEnumerable<RoutePoint> provisionalRoute,
        RouteDiagnostics diagnostics,
        RouteLatticeSearchProgress? latticeSearch)
    {
        ArgumentNullException.ThrowIfNull(envelopeSegments);
        ArgumentNullException.ThrowIfNull(frontSegments);
        ArgumentNullException.ThrowIfNull(searchPoints);
        ArgumentNullException.ThrowIfNull(provisionalRoute);
        ArgumentNullException.ThrowIfNull(diagnostics);
        if (!Enum.IsDefined(solver))
        {
            throw new ArgumentOutOfRangeException(nameof(solver));
        }

        var immutableEnvelopeSegments = envelopeSegments.ToImmutableArray();
        var immutableFrontSegments = frontSegments.ToImmutableArray();
        var immutableSearchPoints = searchPoints.ToImmutableArray();
        var immutableRoute = provisionalRoute.ToImmutableArray();
        if (solver == RouteSolver.IsochroneBeam && immutableEnvelopeSegments.IsEmpty)
        {
            throw new ArgumentException(
                "A routing snapshot must contain at least one reachability envelope segment.",
                nameof(envelopeSegments));
        }

        if (solver == RouteSolver.IsochroneBeam && immutableFrontSegments.IsEmpty)
        {
            throw new ArgumentException(
                "A routing snapshot must contain at least one isochrone front segment.",
                nameof(frontSegments));
        }

        if (immutableRoute.IsEmpty)
        {
            throw new ArgumentException("A provisional route must contain at least one point.", nameof(provisionalRoute));
        }

        var utcFrontierTime = frontierTime.ToUniversalTime();
        if (solver == RouteSolver.IsochroneBeam &&
            immutableRoute[^1].Timestamp != utcFrontierTime)
        {
            throw new ArgumentException(
                "The provisional route must end at the frontier time.",
                nameof(provisionalRoute));
        }
        for (var index = 1; index < immutableRoute.Length; index++)
        {
            if (immutableRoute[index].Timestamp < immutableRoute[index - 1].Timestamp ||
                immutableRoute[index].CumulativeDistanceNauticalMiles <
                immutableRoute[index - 1].CumulativeDistanceNauticalMiles)
            {
                throw new ArgumentException(
                    "Provisional route points must be ordered by time and distance.",
                    nameof(provisionalRoute));
            }
        }

        FrontierTime = utcFrontierTime;
        Solver = solver;
        EnvelopeSegments = immutableEnvelopeSegments;
        FrontSegments = immutableFrontSegments;
        SearchPoints = immutableSearchPoints;
        ProvisionalRoute = immutableRoute;
        Diagnostics = diagnostics;
        LatticeSearch = latticeSearch;
        if ((solver == RouteSolver.TimeDependentLattice) != (latticeSearch is not null))
        {
            throw new ArgumentException(
                "Lattice progress is required only for the lattice solver.",
                nameof(latticeSearch));
        }
    }

    public DateTimeOffset FrontierTime { get; }

    public RouteSolver Solver { get; }

    public ImmutableArray<RouteCalculationEnvelopeSegment> EnvelopeSegments { get; }

    public ImmutableArray<RouteCalculationFrontSegment> FrontSegments { get; }

    public ImmutableArray<Coordinate> SearchPoints { get; }

    public ImmutableArray<RoutePoint> ProvisionalRoute { get; }

    public RouteDiagnostics Diagnostics { get; }

    public RouteLatticeSearchProgress? LatticeSearch { get; }
}

public enum RouteCompletion
{
    DestinationReached,
    ForecastExhausted
}

public enum LandAvoidanceStatus
{
    NotEvaluated,
    Applied,
    RouterUnsupported,
    DataUnconfigured,
    DataUnavailable
}

public sealed record RouteLandAvoidance(
    LandAvoidanceStatus Status,
    string? Warning = null,
    string? Attribution = null)
{
    public bool IsApplied => Status == LandAvoidanceStatus.Applied;

    public bool HasWarning => !string.IsNullOrWhiteSpace(Warning);

    public static RouteLandAvoidance NotEvaluated { get; } =
        new(LandAvoidanceStatus.NotEvaluated);
}

public sealed record RouteResult
{
    public RouteResult(
        RouteRequest request,
        ForecastModel model,
        IEnumerable<RoutePoint> points,
        RouteDiagnostics diagnostics)
        : this(
            request,
            model,
            points,
            diagnostics,
            RouteCompletion.DestinationReached,
            landAvoidance: null)
    {
    }

    public RouteResult(
        RouteRequest request,
        ForecastModel model,
        IEnumerable<RoutePoint> points,
        RouteDiagnostics diagnostics,
        RouteCompletion completion)
        : this(request, model, points, diagnostics, completion, landAvoidance: null)
    {
    }

    public RouteResult(
        RouteRequest request,
        ForecastModel model,
        IEnumerable<RoutePoint> points,
        RouteDiagnostics diagnostics,
        RouteLandAvoidance? landAvoidance)
        : this(
            request,
            model,
            points,
            diagnostics,
            RouteCompletion.DestinationReached,
            landAvoidance)
    {
    }

    public RouteResult(
        RouteRequest request,
        ForecastModel model,
        IEnumerable<RoutePoint> points,
        RouteDiagnostics diagnostics,
        RouteCompletion completion,
        RouteLandAvoidance? landAvoidance,
        RouteSolver solver = RouteSolver.IsochroneBeam,
        RouteLatticeDiagnostics? latticeDiagnostics = null)
    {
        ArgumentNullException.ThrowIfNull(request);
        ArgumentNullException.ThrowIfNull(points);
        ArgumentNullException.ThrowIfNull(diagnostics);
        _ = model.Provider();
        if (!Enum.IsDefined(completion))
        {
            throw new ArgumentOutOfRangeException(nameof(completion));
        }
        if (!Enum.IsDefined(solver))
        {
            throw new ArgumentOutOfRangeException(nameof(solver));
        }
        if (solver != RouteSolver.TimeDependentLattice &&
            latticeDiagnostics is not null)
        {
            throw new ArgumentException(
                "Lattice diagnostics are valid only for lattice results.",
                nameof(latticeDiagnostics));
        }

        var immutablePoints = points.ToImmutableArray();
        if (immutablePoints.IsEmpty)
        {
            throw new ArgumentException("A route must contain at least one point.", nameof(points));
        }

        // LatestArrivalTime is a planning TARGET (it sizes the forecast window), not a
        // hard ceiling on the achieved arrival. Keep only the genuine lower bound: a
        // route may not begin before departure. See ExceedsRequestedArrival below.
        if (immutablePoints[0].Timestamp < request.DepartureTime)
        {
            throw new ArgumentException(
                "Route points must not begin before the requested departure time.",
                nameof(points));
        }

        for (var index = 1; index < immutablePoints.Length; index++)
        {
            if (immutablePoints[index].Timestamp < immutablePoints[index - 1].Timestamp)
            {
                throw new ArgumentException("Route points must be ordered by timestamp.", nameof(points));
            }

            if (immutablePoints[index].CumulativeDistanceNauticalMiles <
                immutablePoints[index - 1].CumulativeDistanceNauticalMiles)
            {
                throw new ArgumentException("Route points must be ordered by distance.", nameof(points));
            }
        }

        Request = request;
        Model = model;
        Points = immutablePoints;
        Diagnostics = diagnostics;
        Completion = completion;
        LandAvoidance = landAvoidance ?? RouteLandAvoidance.NotEvaluated;
        Solver = solver;
        LatticeDiagnostics = latticeDiagnostics;
    }

    public RouteRequest Request { get; }

    public ForecastModel Model { get; }

    public ImmutableArray<RoutePoint> Points { get; }

    public RouteDiagnostics Diagnostics { get; }

    public RouteCompletion Completion { get; }

    public RouteLandAvoidance LandAvoidance { get; }

    public RouteSolver Solver { get; }

    public RouteLatticeDiagnostics? LatticeDiagnostics { get; }

    public DateTimeOffset ArrivalTime => Points[^1].Timestamp;

    /// <summary>
    /// True when the computed arrival lands after the requested passage duration
    /// target. Informational only: the router is never asked to honor the target,
    /// so exceeding it is expected and must not be treated as a failure.
    /// </summary>
    public bool ExceedsRequestedArrival => ArrivalTime > Request.LatestArrivalTime;

    public bool IsForecastLimited => Completion == RouteCompletion.ForecastExhausted;

    public RouteResult WithLandAvoidance(RouteLandAvoidance landAvoidance)
    {
        ArgumentNullException.ThrowIfNull(landAvoidance);
        return new RouteResult(
            Request,
            Model,
            Points,
            Diagnostics,
            Completion,
            landAvoidance,
            Solver,
            LatticeDiagnostics);
    }
}

public sealed record RouteCalculationProgress
{
    public RouteCalculationProgress(
        double fraction,
        string? message = null,
        RouteCalculationSnapshot? snapshot = null)
    {
        if (!double.IsFinite(fraction) || fraction is < 0 or > 1)
        {
            throw new ArgumentOutOfRangeException(nameof(fraction));
        }

        Fraction = fraction;
        Message = message;
        Snapshot = snapshot;
    }

    public double Fraction { get; }

    public string? Message { get; }

    public RouteCalculationSnapshot? Snapshot { get; }
}

public interface IRouteEngine
{
    ValueTask<RouteResult> CalculateAsync(
        RouteRequest request,
        ForecastAcquisition forecast,
        IProgress<RouteCalculationProgress>? progress,
        CancellationToken cancellationToken);

    ValueTask<RouteResult> CalculateAsync(
        RouteRequest request,
        ForecastAcquisition forecast,
        RouteOptimizationOptions optimization,
        IProgress<RouteCalculationProgress>? progress,
        CancellationToken cancellationToken) =>
        CalculateAsync(request, forecast, progress, cancellationToken);
}
