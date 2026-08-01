using Navtool.Core;

namespace Navtool.Core.Tests;

public sealed class RoutePlanTests
{
    private static readonly DateTimeOffset Now =
        new(2026, 8, 1, 18, 0, 0, TimeSpan.Zero);

    [Fact]
    public void Validates_fixed_boundaries_minimum_and_adjacent_coordinates()
    {
        Assert.Throws<ArgumentException>(() => new RoutePlan(
            "Too short",
            [Waypoint("Start", 0)]));
        Assert.Throws<ArgumentException>(() => new RoutePlan(
            "Duplicate coordinate",
            [Waypoint("Start", 0), Waypoint("Finish", 0)]));
        Assert.Throws<ArgumentException>(() => new RoutePlan(
            "Start stopover",
            [Waypoint("Start", 0, TimeSpan.FromHours(1)), Waypoint("Finish", 2)]));

        var plan = CreatePlan();

        Assert.Throws<InvalidOperationException>(() =>
            plan.RemoveWaypoint(plan.Waypoints[0].Id));
        Assert.Throws<InvalidOperationException>(() =>
            plan.MoveWaypoint(plan.Waypoints[^1].Id, 1));
        Assert.Throws<InvalidOperationException>(() =>
            plan.ChangeStopover(plan.Waypoints[0].Id, TimeSpan.FromHours(1)));
    }

    [Fact]
    public void Coordinate_change_invalidates_inbound_and_later_legs()
    {
        var plan = WithSuccessfulResult(CreatePlan());

        var changed = plan.ChangeWaypointCoordinate(
            plan.Waypoints[1].Id,
            new Coordinate(1, 1.5));

        Assert.All(changed.Results[0].Legs, leg =>
        {
            Assert.Equal(RouteLegOutcomeState.Invalidated, leg.State);
            Assert.Equal(RouteLegOutcomeReason.WaypointCoordinateChanged, leg.Reason);
        });
    }

    [Fact]
    public void Rename_does_not_invalidate_and_stopover_invalidates_outbound_only()
    {
        var plan = WithSuccessfulResult(CreatePlan());
        var renamed = plan.RenameWaypoint(plan.Waypoints[1].Id, "Lunch");
        var changed = renamed.ChangeStopover(plan.Waypoints[1].Id, TimeSpan.FromHours(2));

        Assert.All(renamed.Results[0].Legs, leg =>
            Assert.Equal(RouteLegOutcomeState.Succeeded, leg.State));
        Assert.Equal(RouteLegOutcomeState.Succeeded, changed.Results[0].Legs[0].State);
        Assert.Equal(RouteLegOutcomeState.Invalidated, changed.Results[0].Legs[1].State);
        Assert.Equal(RouteLegOutcomeReason.StopoverChanged, changed.Results[0].Legs[1].Reason);
    }

    [Fact]
    public void Reorder_invalidates_from_earliest_changed_leg()
    {
        var plan = WithSuccessfulResult(new RoutePlan(
            "Four",
            [Waypoint("Start", 0), Waypoint("A", 1), Waypoint("B", 2), Waypoint("Finish", 3)]));

        var changed = plan.MoveWaypoint(plan.Waypoints[2].Id, 1);

        Assert.All(changed.Results[0].Legs, leg =>
        {
            Assert.Equal(RouteLegOutcomeState.Invalidated, leg.State);
            Assert.Equal(RouteLegOutcomeReason.WaypointsReordered, leg.Reason);
        });
    }

    [Fact]
    public void Sailed_result_is_retained_until_unmarked()
    {
        var plan = WithSuccessfulResult(CreatePlan());
        var sailedLeg = plan.Legs[0].Id;
        plan = plan.MarkSailed(sailedLeg);

        var changed = plan.ChangeWaypointCoordinate(
            plan.Waypoints[1].Id,
            new Coordinate(1, 1.5));

        Assert.Equal(RouteLegOutcomeState.Succeeded, changed.Results[0].Legs[0].State);
        Assert.Equal(RouteLegOutcomeState.Invalidated, changed.Results[0].Legs[1].State);

        var unmarked = changed.UnmarkSailed(sailedLeg);
        Assert.Equal(RouteLegOutcomeState.Invalidated, unmarked.Results[0].Legs[0].State);
    }

    [Fact]
    public void Sailed_result_survives_recalculation_and_defers_stopover_invalidation()
    {
        var plan = WithSuccessfulResult(CreatePlan());
        var sailedLeg = plan.Legs[1].Id;
        plan = plan.MarkSailed(sailedLeg);
        var originalSailed = plan.Results[0].Legs[1];
        var replacementSession = new RouteCalculationSession(
            plan.Id,
            ForecastModel.NoaaGfs,
            Now.AddHours(2));
        var replacement = new RoutePlanResult(
            replacementSession,
            plan.Legs.Select(leg =>
                new RouteLegResult(
                    leg.Id,
                    RouteLegOutcomeState.Failed,
                    RouteLegOutcomeReason.RouteCalculationFailed)));

        var recalculated = plan.WithResult(replacement);
        var changed = recalculated.ChangeStopover(
            plan.Waypoints[1].Id,
            TimeSpan.FromHours(3));

        Assert.Same(originalSailed.Route, recalculated.Results[0].Legs[1].Route);
        Assert.Equal(RouteLegOutcomeReason.StopoverChanged,
            changed.Results[0].Legs[1].DeferredInvalidationReason);
        var unmarked = changed.UnmarkSailed(sailedLeg);
        Assert.Equal(RouteLegOutcomeState.Invalidated, unmarked.Results[0].Legs[1].State);
        Assert.Equal(RouteLegOutcomeReason.StopoverChanged, unmarked.Results[0].Legs[1].Reason);
    }

    [Fact]
    public void Results_reject_wrong_plan_leg_and_endpoint_references()
    {
        var plan = CreatePlan();
        var wrongSession = new RouteCalculationSession(
            new RoutePlanId(),
            ForecastModel.NoaaGfs,
            Now);
        var outcomes = plan.Legs.Select(leg =>
            new RouteLegResult(leg.Id, RouteLegOutcomeState.Pending, RouteLegOutcomeReason.None));

        Assert.Throws<ArgumentException>(() =>
            plan.WithResult(new RoutePlanResult(wrongSession, outcomes)));
        Assert.Throws<ArgumentException>(() => plan.WithResult(new RoutePlanResult(
            new RouteCalculationSession(plan.Id, ForecastModel.NoaaGfs, Now),
            [new RouteLegResult(plan.Legs[0].Id, RouteLegOutcomeState.Pending, RouteLegOutcomeReason.None)])));
    }

    private static RoutePlan CreatePlan() =>
        new("Passage", [Waypoint("Start", 0), Waypoint("Mid", 1), Waypoint("Finish", 2)]);

    private static RouteWaypoint Waypoint(string name, double longitude, TimeSpan? stopover = null) =>
        new(name, new Coordinate(0, longitude), stopover);

    private static RoutePlan WithSuccessfulResult(RoutePlan plan)
    {
        var session = new RouteCalculationSession(plan.Id, ForecastModel.NoaaGfs, Now).Complete(Now.AddMinutes(1));
        var outcomes = plan.Legs.Select(leg =>
        {
            var from = plan.Waypoints[leg.Index];
            var to = plan.Waypoints[leg.Index + 1];
            var request = new RouteRequest(
                $"leg-{leg.Index}",
                from.Coordinate,
                to.Coordinate,
                Now,
                Now.AddHours(2));
            var route = new RouteResult(
                request,
                ForecastModel.NoaaGfs,
                [
                    new RoutePoint(from.Coordinate, Now, 90, 5, 10, 180, 0),
                    new RoutePoint(to.Coordinate, Now.AddHours(1), 90, 5, 10, 180, 60)
                ],
                new RouteDiagnostics(1, 2, 1, 1));
            return new RouteLegResult(
                leg.Id,
                RouteLegOutcomeState.Succeeded,
                RouteLegOutcomeReason.CalculationSucceeded,
                route);
        });
        return plan.WithResult(new RoutePlanResult(session, outcomes));
    }
}
