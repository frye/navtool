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

public sealed record RouteCalculationSnapshot
{
    public RouteCalculationSnapshot(
        DateTimeOffset frontierTime,
        IEnumerable<Coordinate> frontier,
        IEnumerable<RoutePoint> provisionalRoute,
        RouteDiagnostics diagnostics)
    {
        ArgumentNullException.ThrowIfNull(frontier);
        ArgumentNullException.ThrowIfNull(provisionalRoute);
        ArgumentNullException.ThrowIfNull(diagnostics);

        var immutableFrontier = frontier.ToImmutableArray();
        var immutableRoute = provisionalRoute.ToImmutableArray();
        if (immutableFrontier.IsEmpty)
        {
            throw new ArgumentException("A routing frontier must contain at least one point.", nameof(frontier));
        }

        if (immutableRoute.IsEmpty)
        {
            throw new ArgumentException("A provisional route must contain at least one point.", nameof(provisionalRoute));
        }

        var utcFrontierTime = frontierTime.ToUniversalTime();
        if (immutableRoute[^1].Timestamp != utcFrontierTime)
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
        Frontier = immutableFrontier;
        ProvisionalRoute = immutableRoute;
        Diagnostics = diagnostics;
    }

    public DateTimeOffset FrontierTime { get; }

    public ImmutableArray<Coordinate> Frontier { get; }

    public ImmutableArray<RoutePoint> ProvisionalRoute { get; }

    public RouteDiagnostics Diagnostics { get; }
}

public sealed record RouteResult
{
    public RouteResult(
        RouteRequest request,
        ForecastModel model,
        IEnumerable<RoutePoint> points,
        RouteDiagnostics diagnostics)
    {
        ArgumentNullException.ThrowIfNull(request);
        ArgumentNullException.ThrowIfNull(points);
        ArgumentNullException.ThrowIfNull(diagnostics);
        _ = model.Provider();
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
    }

    public RouteRequest Request { get; }

    public ForecastModel Model { get; }

    public ImmutableArray<RoutePoint> Points { get; }

    public RouteDiagnostics Diagnostics { get; }

    public DateTimeOffset ArrivalTime => Points[^1].Timestamp;

    /// <summary>
    /// True when the computed arrival lands after the requested passage duration
    /// target. Informational only: the router is never asked to honor the target,
    /// so exceeding it is expected and must not be treated as a failure.
    /// </summary>
    public bool ExceedsRequestedArrival => ArrivalTime > Request.LatestArrivalTime;
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
}
