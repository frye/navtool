namespace Navtool.Core.Tests;

public sealed class SharedRouteTimelineTests
{
    [Fact]
    public void Timeline_spans_routes_and_navigates_union_timestamps()
    {
        var start = new DateTimeOffset(2026, 7, 15, 0, 0, 0, TimeSpan.Zero);
        var first = CreateRoute(
            "route-a",
            ForecastModel.NoaaGfs,
            start,
            start.AddHours(4),
            (start, 0),
            (start.AddHours(1), 1_000),
            (start.AddHours(4), 4_000));
        var second = CreateRoute(
            "route-a",
            ForecastModel.EcmwfIfs,
            start.AddHours(-1),
            start.AddHours(3),
            (start, 0),
            (start.AddHours(2), 2_000),
            (start.AddHours(3), 3_000));

        var timeline = SharedRouteTimeline.Create(new[] { first, second });

        Assert.Equal(start.AddHours(-1), timeline.Start);
        Assert.Equal(start.AddHours(4), timeline.End);
        Assert.Equal(
            new[] { start, start.AddHours(1), start.AddHours(2), start.AddHours(3), start.AddHours(4) },
            timeline.Timestamps);
        Assert.True(timeline.TryGetPreviousTimestamp(start.AddHours(2), out var previous));
        Assert.Equal(start.AddHours(1), previous);
        Assert.True(timeline.TryGetNextTimestamp(start.AddHours(2), out var next));
        Assert.Equal(start.AddHours(3), next);
        Assert.False(timeline.TryGetPreviousTimestamp(start, out _));
        Assert.False(timeline.TryGetNextTimestamp(start.AddHours(4), out _));
    }

    [Fact]
    public void Timeline_selects_each_routes_nearest_point_and_prefers_earlier_on_ties()
    {
        var start = new DateTimeOffset(2026, 7, 15, 0, 0, 0, TimeSpan.Zero);
        var first = CreateRoute(
            "route-a",
            ForecastModel.NoaaGfs,
            start,
            start.AddHours(2),
            (start, 0),
            (start.AddHours(2), 2_000));
        var second = CreateRoute(
            "route-a",
            ForecastModel.EcmwfIfs,
            start,
            start.AddHours(3),
            (start.AddHours(1), 0),
            (start.AddHours(3), 2_000));

        var selections = SharedRouteTimeline
            .Create(new[] { first, second })
            .NearestPoints(start.AddHours(1));

        Assert.Equal(start, selections[new RouteKey("route-a", ForecastModel.NoaaGfs)].Point.Timestamp);
        Assert.Equal(
            start.AddHours(1),
            selections[new RouteKey("route-a", ForecastModel.EcmwfIfs)].Point.Timestamp);
    }

    private static RouteResult CreateRoute(
        string routeId,
        ForecastModel model,
        DateTimeOffset departure,
        DateTimeOffset latestArrival,
        params (DateTimeOffset Timestamp, double Distance)[] points)
    {
        var request = new RouteRequest(
            routeId,
            new Coordinate(40, -70),
            new Coordinate(45, -50),
            departure,
            latestArrival);
        return new RouteResult(
            request,
            model,
            points.Select(point => new RoutePoint(
                new Coordinate(40, -70 + point.Distance / 1_000),
                point.Timestamp,
                90,
                6,
                15,
                180,
                point.Distance)),
            new RouteDiagnostics(10, 20, 5, points.Length, TimeSpan.FromSeconds(1)));
    }
}
