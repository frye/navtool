using System.Collections.Immutable;

namespace Navtool.Core;

public sealed record RoutePointSelection(
    RouteLegVisualization Leg,
    RoutePoint Point,
    TimeSpan OffsetFromRequestedTime,
    bool IsStopover,
    string? StopoverLabel);

public sealed class SharedRouteTimeline
{
    private readonly ImmutableArray<RouteLegVisualization> _legs;

    private SharedRouteTimeline(
        ForecastModel model,
        ImmutableArray<RouteLegVisualization> legs,
        ImmutableArray<DateTimeOffset> timestamps)
    {
        Model = model;
        _legs = legs;
        Timestamps = timestamps;
        Start = legs.Min(leg => leg.Route!.Request.DepartureTime);
        End = legs.Max(GetLegTimelineEnd);
    }

    public ForecastModel Model { get; }

    public DateTimeOffset Start { get; }

    public DateTimeOffset End { get; }

    public ImmutableArray<DateTimeOffset> Timestamps { get; }

    public static SharedRouteTimeline Create(
        ForecastModel model,
        IEnumerable<RouteLegVisualization> legs)
    {
        ArgumentNullException.ThrowIfNull(legs);
        var successfulLegs = legs
            .Where(leg => leg.Key.Model == model && leg.HasOptimizedGeometry)
            .OrderBy(leg => leg.Route!.Request.DepartureTime)
            .ThenBy(leg => leg.LegIndex)
            .ToImmutableArray();
        if (successfulLegs.IsEmpty)
        {
            throw new ArgumentException(
                "At least one successful route leg is required for the selected model.",
                nameof(legs));
        }

        var duplicate = successfulLegs
            .GroupBy(leg => leg.Key)
            .FirstOrDefault(group => group.Count() > 1);
        if (duplicate is not null)
        {
            throw new ArgumentException($"Duplicate route leg '{duplicate.Key}'.", nameof(legs));
        }

        var timestamps = successfulLegs
            .SelectMany(leg => leg.Route!.Points
                .Select(point => point.Timestamp)
                .Append(GetLegTimelineEnd(leg)))
            .Distinct()
            .Order()
            .ToImmutableArray();

        return new SharedRouteTimeline(model, successfulLegs, timestamps);
    }

    public RoutePointSelection Select(DateTimeOffset timestamp)
    {
        var selected = Clamp(timestamp);
        var active = _legs.LastOrDefault(leg =>
            selected >= leg.Route!.Request.DepartureTime &&
            selected <= leg.Route.ArrivalTime);
        if (active is not null)
        {
            var point = FindNearest(active.Route!.Points, selected);
            return new RoutePointSelection(active, point, point.Timestamp - selected, false, null);
        }

        var previous = _legs.LastOrDefault(leg => leg.Route!.ArrivalTime < selected);
        if (previous is not null &&
            GetStopover(previous) is { } stopover &&
            selected <= previous.Route!.ArrivalTime + stopover)
        {
            var arrival = previous.Route.Points[^1];
            var hold = new RoutePoint(
                arrival.Location,
                selected,
                arrival.HeadingDegrees,
                0,
                arrival.TrueWindSpeedKnots,
                arrival.TrueWindDirectionDegrees,
                arrival.CumulativeDistanceNauticalMiles);
            return new RoutePointSelection(
                previous,
                hold,
                TimeSpan.Zero,
                true,
                $"Stopover at {previous.To.Name}");
        }

        var nearestLeg = _legs
            .OrderBy(leg => DistanceFromInterval(selected, leg.Route!))
            .ThenBy(leg => leg.LegIndex)
            .First();
        var nearestPoint = FindNearest(nearestLeg.Route!.Points, selected);
        return new RoutePointSelection(
            nearestLeg,
            nearestPoint,
            nearestPoint.Timestamp - selected,
            false,
            null);
    }

    public bool TryGetPreviousTimestamp(DateTimeOffset timestamp, out DateTimeOffset previous)
    {
        var index = LowerBound(Timestamps, timestamp.ToUniversalTime()) - 1;
        if (index >= 0)
        {
            previous = Timestamps[index];
            return true;
        }

        previous = default;
        return false;
    }

    public bool TryGetNextTimestamp(DateTimeOffset timestamp, out DateTimeOffset next)
    {
        var utcTimestamp = timestamp.ToUniversalTime();
        var index = LowerBound(Timestamps, utcTimestamp);
        while (index < Timestamps.Length && Timestamps[index] <= utcTimestamp)
        {
            index++;
        }

        if (index < Timestamps.Length)
        {
            next = Timestamps[index];
            return true;
        }

        next = default;
        return false;
    }

    public DateTimeOffset Clamp(DateTimeOffset timestamp)
    {
        var utcTimestamp = timestamp.ToUniversalTime();
        return utcTimestamp < Start ? Start : utcTimestamp > End ? End : utcTimestamp;
    }

    private static DateTimeOffset GetLegTimelineEnd(RouteLegVisualization leg) =>
        leg.Route!.ArrivalTime + (GetStopover(leg) ?? TimeSpan.Zero);

    private static TimeSpan? GetStopover(RouteLegVisualization leg) =>
        leg.Reason == RouteLegOutcomeReason.CalculationSucceeded &&
        leg.Route!.IsComplete
            ? leg.StopoverAfter
            : null;

    private static TimeSpan DistanceFromInterval(DateTimeOffset timestamp, RouteResult route)
    {
        if (timestamp < route.Request.DepartureTime)
        {
            return route.Request.DepartureTime - timestamp;
        }

        return timestamp > route.ArrivalTime
            ? timestamp - route.ArrivalTime
            : TimeSpan.Zero;
    }

    private static RoutePoint FindNearest(
        ImmutableArray<RoutePoint> points,
        DateTimeOffset timestamp)
    {
        var index = LowerBound(points, timestamp);
        if (index == 0)
        {
            return points[0];
        }

        if (index == points.Length)
        {
            return points[^1];
        }

        var before = points[index - 1];
        var after = points[index];
        return timestamp - before.Timestamp <= after.Timestamp - timestamp ? before : after;
    }

    private static int LowerBound(
        ImmutableArray<DateTimeOffset> values,
        DateTimeOffset value)
    {
        var low = 0;
        var high = values.Length;
        while (low < high)
        {
            var middle = low + ((high - low) / 2);
            if (values[middle] < value)
            {
                low = middle + 1;
            }
            else
            {
                high = middle;
            }
        }

        return low;
    }

    private static int LowerBound(
        ImmutableArray<RoutePoint> values,
        DateTimeOffset value)
    {
        var low = 0;
        var high = values.Length;
        while (low < high)
        {
            var middle = low + ((high - low) / 2);
            if (values[middle].Timestamp < value)
            {
                low = middle + 1;
            }
            else
            {
                high = middle;
            }
        }

        return low;
    }
}
