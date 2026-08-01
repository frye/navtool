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

    [Fact]
    public void Active_leg_index_defaults_to_first_unsailed_leg()
    {
        var plan = CreatePlan();
        Assert.Equal(0, plan.ActiveLegIndex);
        Assert.Equal(plan.Legs[0].Id, plan.ActiveLeg!.Id);
        Assert.False(plan.IsItineraryComplete);

        var sailedFirst = plan.MarkSailed(plan.Legs[0].Id);
        Assert.Equal(1, sailedFirst.ActiveLegIndex);
        Assert.Equal(plan.Legs[1].Id, sailedFirst.ActiveLeg!.Id);

        var sailedAll = sailedFirst.MarkSailed(plan.Legs[1].Id);
        Assert.Equal(plan.Legs.Length, sailedAll.ActiveLegIndex);
        Assert.Null(sailedAll.ActiveLeg);
        Assert.True(sailedAll.IsItineraryComplete);
    }

    [Fact]
    public void Explicit_active_leg_overrides_default_and_is_validated()
    {
        var plan = CreatePlan();
        var withActive = plan.SetActiveLeg(plan.Legs[1].Id);
        Assert.Equal(plan.Legs[1].Id, withActive.ActiveLegId);
        Assert.Equal(1, withActive.ActiveLegIndex);

        Assert.Throws<KeyNotFoundException>(() => plan.SetActiveLeg(new RouteLegId(Guid.NewGuid())));

        var sailed = plan.MarkSailed(plan.Legs[0].Id);
        Assert.Throws<InvalidOperationException>(() => sailed.SetActiveLeg(plan.Legs[0].Id));

        var cleared = withActive.ClearActiveLeg();
        Assert.Null(cleared.ActiveLegId);
        Assert.Equal(0, cleared.ActiveLegIndex);
    }

    [Fact]
    public void Set_current_position_invalidates_only_active_and_later_unsailed_legs()
    {
        var plan = WithSuccessfulResult(CreatePlan());
        plan = plan.MarkSailed(plan.Legs[0].Id);

        var withPosition = plan.SetCurrentPosition(new Coordinate(0.2, 0.5), Now.AddHours(1));

        Assert.NotNull(withPosition.CurrentPosition);
        Assert.Equal(RouteLegOutcomeState.Succeeded, withPosition.Results[0].Legs[0].State);
        Assert.Equal(RouteLegOutcomeState.Invalidated, withPosition.Results[0].Legs[1].State);
        Assert.Equal(RouteLegOutcomeReason.CurrentPositionChanged, withPosition.Results[0].Legs[1].Reason);
    }

    [Fact]
    public void Clear_current_position_invalidates_only_active_and_later_unsailed_legs()
    {
        var plan = WithSuccessfulResult(CreatePlan());
        var sailedLeg = plan.Legs[0].Id;
        plan = plan.MarkSailed(sailedLeg).SetCurrentPosition(new Coordinate(0.2, 0.5), Now.AddHours(1));

        var cleared = plan.ClearCurrentPosition();

        Assert.Null(cleared.CurrentPosition);
        Assert.Equal(RouteLegOutcomeState.Succeeded, cleared.Results[0].Legs[0].State);
        Assert.Equal(RouteLegOutcomeState.Invalidated, cleared.Results[0].Legs[1].State);
        Assert.Equal(RouteLegOutcomeReason.CurrentPositionChanged, cleared.Results[0].Legs[1].Reason);
    }

    [Fact]
    public void Clear_current_position_is_a_no_op_when_none_is_set()
    {
        var plan = WithSuccessfulResult(CreatePlan());

        var cleared = plan.ClearCurrentPosition();

        Assert.Same(plan, cleared);
    }

    [Fact]
    public void Route_result_origin_may_match_current_position_only_for_the_active_leg()
    {
        var plan = CreatePlan();
        var currentPosition = new Coordinate(0.4, 0.9);
        var activeLegRequest = new RouteRequest(
            "active",
            currentPosition,
            plan.Waypoints[1].Coordinate,
            Now,
            Now.AddHours(2));
        var activeLegRoute = new RouteResult(
            activeLegRequest,
            ForecastModel.NoaaGfs,
            [
                new RoutePoint(currentPosition, Now, 90, 5, 10, 180, 0),
                new RoutePoint(plan.Waypoints[1].Coordinate, Now.AddHours(1), 90, 5, 10, 180, 30)
            ],
            new RouteDiagnostics(1, 1, 1, 1));
        var laterLegRequest = new RouteRequest(
            "later",
            plan.Waypoints[1].Coordinate,
            plan.Waypoints[2].Coordinate,
            Now.AddHours(1),
            Now.AddHours(3));
        var laterLegRoute = new RouteResult(
            laterLegRequest,
            ForecastModel.NoaaGfs,
            [
                new RoutePoint(plan.Waypoints[1].Coordinate, Now.AddHours(1), 90, 5, 10, 180, 0),
                new RoutePoint(plan.Waypoints[2].Coordinate, Now.AddHours(2), 90, 5, 10, 180, 30)
            ],
            new RouteDiagnostics(1, 1, 1, 1));
        var session = new RouteCalculationSession(plan.Id, ForecastModel.NoaaGfs, Now).Complete(Now.AddHours(2));
        var result = new RoutePlanResult(session,
        [
            new RouteLegResult(plan.Legs[0].Id, RouteLegOutcomeState.Succeeded,
                RouteLegOutcomeReason.CalculationSucceeded, activeLegRoute),
            new RouteLegResult(plan.Legs[1].Id, RouteLegOutcomeState.Succeeded,
                RouteLegOutcomeReason.CalculationSucceeded, laterLegRoute)
        ]);

        // Accepted while leg 0 is the active leg (default, since nothing is sailed yet) and its
        // origin matches the current position.
        var withCurrentPosition = plan.SetCurrentPosition(currentPosition, Now);
        var accepted = withCurrentPosition.WithResult(result);
        Assert.Equal(RouteLegOutcomeState.Succeeded, accepted.Results[0].Legs[0].State);

        // The same origin substitution is rejected for a leg that is not the active leg: swap
        // which leg claims the current-position origin and confirm the constructor rejects it.
        var swappedResult = new RoutePlanResult(session,
        [
            new RouteLegResult(plan.Legs[0].Id, RouteLegOutcomeState.Succeeded,
                RouteLegOutcomeReason.CalculationSucceeded, laterLegRoute),
            new RouteLegResult(plan.Legs[1].Id, RouteLegOutcomeState.Succeeded,
                RouteLegOutcomeReason.CalculationSucceeded, activeLegRoute)
        ]);
        Assert.Throws<ArgumentException>(() => withCurrentPosition.WithResult(swappedResult));
    }

    [Fact]
    public void Unmark_sailed_retains_result_routed_from_current_position_while_leg_was_active()
    {
        var plan = CreatePlan();
        var currentPosition = new Coordinate(0.4, 0.9);
        var withPosition = plan.SetCurrentPosition(currentPosition, Now);
        var request = new RouteRequest(
            "from-current-position",
            currentPosition,
            plan.Waypoints[1].Coordinate,
            Now,
            Now.AddHours(2));
        var route = new RouteResult(
            request,
            ForecastModel.NoaaGfs,
            [
                new RoutePoint(currentPosition, Now, 90, 5, 10, 180, 0),
                new RoutePoint(plan.Waypoints[1].Coordinate, Now.AddHours(1), 90, 5, 10, 180, 30)
            ],
            new RouteDiagnostics(1, 1, 1, 1));
        var session = new RouteCalculationSession(plan.Id, ForecastModel.NoaaGfs, Now).Complete(Now.AddHours(1));
        var laterLegRequest = new RouteRequest(
            "later",
            plan.Waypoints[1].Coordinate,
            plan.Waypoints[2].Coordinate,
            Now.AddHours(1),
            Now.AddHours(3));
        var laterLegRoute = new RouteResult(
            laterLegRequest,
            ForecastModel.NoaaGfs,
            [
                new RoutePoint(plan.Waypoints[1].Coordinate, Now.AddHours(1), 90, 5, 10, 180, 0),
                new RoutePoint(plan.Waypoints[2].Coordinate, Now.AddHours(2), 90, 5, 10, 180, 30)
            ],
            new RouteDiagnostics(1, 1, 1, 1));
        var calculated = withPosition.WithResult(new RoutePlanResult(session,
        [
            new RouteLegResult(plan.Legs[0].Id, RouteLegOutcomeState.Succeeded,
                RouteLegOutcomeReason.CalculationSucceeded, route),
            new RouteLegResult(plan.Legs[1].Id, RouteLegOutcomeState.Succeeded,
                RouteLegOutcomeReason.CalculationSucceeded, laterLegRoute)
        ]));

        var sailed = calculated.MarkSailed(plan.Legs[0].Id);
        var unmarked = sailed.UnmarkSailed(plan.Legs[0].Id);

        // Leg 0 becomes active again after unmarking, so its current-position-origin result
        // should be retained rather than incorrectly invalidated for a coordinate "mismatch".
        Assert.Equal(RouteLegOutcomeState.Succeeded, unmarked.Results[0].Legs[0].State);
        Assert.Equal(0, unmarked.ActiveLegIndex);

        var laterActive = sailed
            .SetActiveLeg(plan.Legs[1].Id)
            .UnmarkSailed(plan.Legs[0].Id);
        Assert.Equal(RouteLegOutcomeState.Invalidated, laterActive.Results[0].Legs[0].State);
        Assert.Equal(
            RouteLegOutcomeReason.CurrentPositionChanged,
            laterActive.Results[0].Legs[0].Reason);
        Assert.Equal(1, laterActive.ActiveLegIndex);
    }

    [Fact]
    public void Active_leg_must_be_cleared_or_reassigned_before_removing_its_boundary_waypoint()
    {
        var plan = new RoutePlan(
            "Four",
            [Waypoint("Start", 0), Waypoint("A", 1), Waypoint("B", 2), Waypoint("Finish", 3)]);
        var withActive = plan.SetActiveLeg(plan.Legs[1].Id);

        Assert.Throws<InvalidOperationException>(() =>
            withActive.RemoveWaypoint(withActive.Waypoints[2].Id));

        var cleared = withActive.ClearActiveLeg();
        var removed = cleared.RemoveWaypoint(cleared.Waypoints[2].Id);
        Assert.Null(removed.ActiveLegId);
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
