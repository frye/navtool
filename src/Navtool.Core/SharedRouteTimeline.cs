using System.Collections.Immutable;

namespace Navtool.Core;

public readonly record struct RouteKey(string RouteId, ForecastModel Model);

public sealed record RoutePointSelection(
    RouteKey Route,
    RoutePoint Point,
    TimeSpan OffsetFromRequestedTime);

public sealed class SharedRouteTimeline
{
    private readonly ImmutableArray<RouteResult> _routes;

    private SharedRouteTimeline(
        ImmutableArray<RouteResult> routes,
        ImmutableArray<DateTimeOffset> timestamps)
    {
        _routes = routes;
        Timestamps = timestamps;
        Start = routes.Min(route => route.Request.DepartureTime);
        End = routes.Max(route => route.ArrivalTime);
    }

    public DateTimeOffset Start { get; }

    public DateTimeOffset End { get; }

    public ImmutableArray<DateTimeOffset> Timestamps { get; }

    public static SharedRouteTimeline Create(IEnumerable<RouteResult> routes)
    {
        ArgumentNullException.ThrowIfNull(routes);
        var immutableRoutes = routes.ToImmutableArray();
        if (immutableRoutes.IsEmpty)
        {
            throw new ArgumentException("At least one route is required.", nameof(routes));
        }

        var duplicate = immutableRoutes
            .GroupBy(route => new RouteKey(route.Request.RouteId, route.Model))
            .FirstOrDefault(group => group.Count() > 1);
        if (duplicate is not null)
        {
            throw new ArgumentException($"Duplicate route '{duplicate.Key}'.", nameof(routes));
        }

        var timestamps = immutableRoutes
            .SelectMany(route => route.Points)
            .Select(point => point.Timestamp)
            .Distinct()
            .Order()
            .ToImmutableArray();

        return new SharedRouteTimeline(immutableRoutes, timestamps);
    }

    public ImmutableDictionary<RouteKey, RoutePointSelection> NearestPoints(DateTimeOffset timestamp)
    {
        var utcTimestamp = timestamp.ToUniversalTime();
        return _routes.ToImmutableDictionary(
            route => new RouteKey(route.Request.RouteId, route.Model),
            route =>
            {
                var point = FindNearest(route.Points, utcTimestamp);
                return new RoutePointSelection(
                    new RouteKey(route.Request.RouteId, route.Model),
                    point,
                    point.Timestamp - utcTimestamp);
            });
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
