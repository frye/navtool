using Navtool.App.Models;
using Navtool.App.Services;
using Navtool.Core;

namespace Navtool.App.Tests;

public sealed class RouteInspectionTimelineTests
{
    private static readonly DateTimeOffset Departure = new(2026, 9, 9, 0, 0, 0, TimeSpan.Zero);

    [Fact]
    public void Preview_only_timeline_is_bounded_and_has_no_destination_hold()
    {
        var preview = CreatePreview(Departure);
        var timeline = new RouteInspectionTimeline(preview.Model, [preview]);
        Assert.Equal(Departure, timeline.Start);
        Assert.Equal(Departure.AddHours(1), timeline.End);
        Assert.Equal(timeline.Start, timeline.Clamp(Departure.AddDays(-1)));
        Assert.Equal(timeline.End, timeline.Clamp(Departure.AddDays(1)));
        Assert.False(timeline.TryGetPreviousTimestamp(timeline.Start, out _));
        Assert.False(timeline.TryGetNextTimestamp(timeline.End, out _));
        Assert.True(timeline.TryGetNextTimestamp(timeline.Start, out var next));
        Assert.Equal(timeline.End, next);
        Assert.True(timeline.TryGetPreviousTimestamp(timeline.End, out var previous));
        Assert.Equal(timeline.Start, previous);
        var (selection, label) = timeline.Select(Departure.AddDays(1));
        Assert.Null(label);
        Assert.True(selection.IsProvisional);
        Assert.False(selection.IsPlannedHold);
        Assert.Null(selection.Route);
        Assert.Equal(1, selection.PointIndex);
        Assert.Equal("PROVISIONAL POINT", selection.TelemetryLabel);
        Assert.Equal("unavailable", selection.ApparentWindSpeedText);
    }

    [Fact]
    public void Completed_hold_transitions_to_preview_without_clamping_to_completed_arrival()
    {
        var from = new RouteWaypoint("Start", new Coordinate(0, 0));
        var to = new RouteWaypoint("Stop", new Coordinate(1, 1), stopover: TimeSpan.FromHours(2));
        var route = new RouteResult(
            new RouteRequest("accepted", from.Coordinate, to.Coordinate, Departure, Departure.AddDays(1)),
            ForecastModel.NoaaGfs,
            [Point(from.Coordinate, Departure), Point(to.Coordinate, Departure.AddHours(2))],
            new RouteDiagnostics(1, 2, 1, 2));
        var leg = new RouteLegVisualization(
            new RouteVisualizationKey(new RoutePlanId(), new RouteLegId(), route.Model,
                new RouteCalculationSessionId(), route.Request.RouteId),
            0, from, to, RouteLegOutcomeState.Succeeded, RouteLegOutcomeReason.CalculationSucceeded,
            route, null, false, Departure, Departure.AddHours(2));
        var preview = CreatePreview(Departure.AddHours(4));
        var otherModel = CreatePreview(Departure.AddDays(2), ForecastModel.EcmwfIfs);
        var timeline = new RouteInspectionTimeline(ForecastModel.NoaaGfs,
            [new RouteInspectionSource(route, leg), preview, otherModel]);

        var hold = timeline.Select(Departure.AddHours(3));
        Assert.True(hold.Selection.IsPlannedHold);
        Assert.False(hold.Selection.IsProvisional);
        Assert.Equal("Stopover at Stop", hold.StopoverLabel);
        Assert.Equal(Departure.AddHours(3), hold.Selection.TimelineTimestamp);
        var transition = timeline.Select(Departure.AddHours(4));
        Assert.True(transition.Selection.IsProvisional);
        Assert.False(transition.Selection.IsPlannedHold);
        Assert.Null(transition.StopoverLabel);
        Assert.Equal(Departure.AddHours(5), timeline.End);
    }

    [Fact]
    public void Hit_testing_combines_sources_and_preserves_point_first_priority_and_dateline_geometry()
    {
        var preview = CreatePreview(Departure);
        var accepted = new RouteInspectionSource(new RouteResult(preview.Request, preview.Model,
            preview.Points, preview.Preview!.Snapshot.Diagnostics, RouteCompletion.ForecastExhausted));
        var hit = RouteHitTester.FindNearest([accepted, preview],
            source => source.IsProvisional
                ? [new ScreenPoint(0, 0), new ScreenPoint(100, 0)]
                : [new ScreenPoint(98, -50), new ScreenPoint(98, 50)],
            new ScreenPoint(98, 2));
        Assert.True(hit!.IsProvisional);
        Assert.Equal(RouteHitKind.RoutePoint, hit.HitKind);

        var datelineHit = RouteHitTester.FindNearest([preview],
            _ => [new ScreenPoint(179, 0), new ScreenPoint(181, 0)],
            new ScreenPoint(180, 5), pointTolerancePixels: 1);
        Assert.True(datelineHit!.IsProvisional);
        Assert.Equal(RouteHitKind.Route, datelineHit.HitKind);
        Assert.Null(RouteHitTester.FindNearest([preview],
            _ => [new ScreenPoint(179, 0), new ScreenPoint(181, 0)],
            new ScreenPoint(0, 0)));
    }

    private static RouteInspectionSource CreatePreview(DateTimeOffset departure,
        ForecastModel model = ForecastModel.NoaaGfs)
    {
        var origin = new Coordinate(1, 1);
        var endpoint = new Coordinate(1.25, 1.25);
        var snapshot = new RouteCalculationSnapshot(departure.AddHours(1),
            [new RouteCalculationEnvelopeSegment([origin, endpoint], false)],
            [new RouteCalculationFrontSegment([origin, endpoint])],
            [Point(origin, departure), Point(endpoint, departure.AddHours(1))],
            new RouteDiagnostics(1, 2, 1, 1));
        return new RouteInspectionSource(new InterruptedRouteInspection(new RoutePlanId(), 1, 1,
            new RouteLegId(), 1, Guid.NewGuid(), model,
            new RouteRequest("preview", origin, new Coordinate(2, 2), departure, departure.AddDays(1)),
            snapshot, null, "Cancelled by user."));
    }

    private static RoutePoint Point(Coordinate coordinate, DateTimeOffset timestamp) =>
        new(coordinate, timestamp, 90, 6, 15, 180, 0);
}
