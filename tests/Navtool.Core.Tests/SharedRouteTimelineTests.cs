namespace Navtool.Core.Tests;

public sealed class SharedRouteTimelineTests
{
    [Fact]
    public void Timeline_uses_full_identity_and_spans_only_the_active_model()
    {
        var planId = new RoutePlanId();
        var legId = new RouteLegId(Guid.NewGuid());
        var start = new DateTimeOffset(2026, 7, 15, 0, 0, 0, TimeSpan.Zero);
        var noaa = CreateLeg(
            planId,
            legId,
            ForecastModel.NoaaGfs,
            new RouteCalculationSessionId(),
            start,
            start.AddHours(4));
        var revisedNoaa = CreateLeg(
            planId,
            legId,
            ForecastModel.NoaaGfs,
            new RouteCalculationSessionId(),
            start.AddHours(1),
            start.AddHours(5));
        var ecmwf = CreateLeg(
            planId,
            legId,
            ForecastModel.EcmwfIfs,
            new RouteCalculationSessionId(),
            start.AddHours(8),
            start.AddHours(12));

        Assert.NotEqual(noaa.Key, revisedNoaa.Key);
        var timeline = SharedRouteTimeline.Create(ForecastModel.NoaaGfs, [noaa]);

        Assert.Equal(ForecastModel.NoaaGfs, timeline.Model);
        Assert.Equal(start, timeline.Start);
        Assert.Equal(start.AddHours(4), timeline.End);
        Assert.DoesNotContain(ecmwf.Route!.Request.DepartureTime, timeline.Timestamps);
    }

    [Fact]
    public void Timeline_represents_stopover_as_stationary_hold_and_navigates_boundaries()
    {
        var planId = new RoutePlanId();
        var sessionId = new RouteCalculationSessionId();
        var start = new DateTimeOffset(2026, 7, 15, 0, 0, 0, TimeSpan.Zero);
        var first = CreateLeg(
            planId,
            new RouteLegId(Guid.NewGuid()),
            ForecastModel.NoaaGfs,
            sessionId,
            start,
            start.AddHours(2),
            TimeSpan.FromHours(2),
            0);
        var second = CreateLeg(
            planId,
            new RouteLegId(Guid.NewGuid()),
            ForecastModel.NoaaGfs,
            sessionId,
            start.AddHours(4),
            start.AddHours(6),
            null,
            1);
        var timeline = SharedRouteTimeline.Create(ForecastModel.NoaaGfs, [first, second]);

        var hold = timeline.Select(start.AddHours(3));

        Assert.True(hold.IsStopover);
        Assert.Equal("Stopover at Waypoint 1", hold.StopoverLabel);
        Assert.Equal(first.Route!.Points[^1].Location, hold.Point.Location);
        Assert.Equal(0, hold.Point.BoatSpeedKnots);
        Assert.Equal(start.AddHours(3), hold.Point.Timestamp);
        Assert.Contains(start.AddHours(4), timeline.Timestamps);
        Assert.True(timeline.TryGetPreviousTimestamp(start.AddHours(4), out var previous));
        Assert.Equal(start.AddHours(2), previous);
        Assert.True(timeline.TryGetNextTimestamp(start.AddHours(4), out var next));
        Assert.Equal(start.AddHours(6), next);
        Assert.False(timeline.TryGetPreviousTimestamp(start, out _));
        Assert.False(timeline.TryGetNextTimestamp(start.AddHours(6), out _));
    }

    [Fact]
    public void Timeline_handles_missing_later_legs_without_inventing_geometry()
    {
        var start = new DateTimeOffset(2026, 7, 15, 0, 0, 0, TimeSpan.Zero);
        var leg = CreateLeg(
            new RoutePlanId(),
            new RouteLegId(Guid.NewGuid()),
            ForecastModel.NoaaGfs,
            new RouteCalculationSessionId(),
            start,
            start.AddHours(2),
            TimeSpan.FromHours(1));
        var timeline = SharedRouteTimeline.Create(ForecastModel.NoaaGfs, [leg]);

        Assert.Equal(start.AddHours(3), timeline.End);
        Assert.True(timeline.Select(timeline.End).IsStopover);
    }

    [Fact]
    public void Forecast_limited_leg_does_not_hold_at_unreached_stopover()
    {
        var start = new DateTimeOffset(2026, 7, 15, 0, 0, 0, TimeSpan.Zero);
        var leg = CreateLeg(
            new RoutePlanId(),
            new RouteLegId(Guid.NewGuid()),
            ForecastModel.NoaaGfs,
            new RouteCalculationSessionId(),
            start,
            start.AddHours(2),
            TimeSpan.FromHours(4),
            reason: RouteLegOutcomeReason.ForecastExhausted);
        var timeline = SharedRouteTimeline.Create(ForecastModel.NoaaGfs, [leg]);

        Assert.Equal(start.AddHours(2), timeline.End);
        Assert.False(timeline.Select(timeline.End).IsStopover);
    }

    private static RouteLegVisualization CreateLeg(
        RoutePlanId planId,
        RouteLegId legId,
        ForecastModel model,
        RouteCalculationSessionId sessionId,
        DateTimeOffset departure,
        DateTimeOffset arrival,
        TimeSpan? stopover = null,
        int index = 0,
        RouteLegOutcomeReason reason = RouteLegOutcomeReason.CalculationSucceeded)
    {
        var from = new RouteWaypoint($"Waypoint {index}", new Coordinate(40 + index, -70 + index));
        var to = new RouteWaypoint(
            $"Waypoint {index + 1}",
            new Coordinate(41 + index, -69 + index),
            stopover);
        var request = new RouteRequest(
            $"{planId}-leg-{index}-{sessionId}",
            from.Coordinate,
            to.Coordinate,
            departure,
            arrival.AddHours(1));
        var route = new RouteResult(
            request,
            model,
            [
                new RoutePoint(from.Coordinate, departure, 90, 6, 15, 180, 0),
                new RoutePoint(to.Coordinate, arrival, 90, 6, 15, 180, 100)
            ],
            new RouteDiagnostics(10, 20, 5, 2));
        return new RouteLegVisualization(
            new RouteVisualizationKey(planId, legId, model, sessionId, request.RouteId),
            index,
            from,
            to,
            RouteLegOutcomeState.Succeeded,
            reason,
            route,
            null,
            false,
            departure,
            arrival);
    }
}
