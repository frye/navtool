namespace Navtool.Core.Tests;

public sealed class RouteCausalityTests
{
    private static readonly DateTimeOffset Now = new(2026, 8, 1, 0, 0, 0, TimeSpan.Zero);

    private static RoutePlan CalculatedPlan()
    {
        var plan = new RoutePlan("Causal", [new("A", new(30, -70)),
            new("B", new(35, -60), TimeSpan.FromHours(2)), new("C", new(40, -50))]);
        var session = new RouteCalculationSession(plan.Id, ForecastModel.NoaaGfs, Now).Complete(Now.AddHours(1));
        var inbound = Route(new RouteRequest("in", plan.Waypoints[0].Coordinate, plan.Waypoints[1].Coordinate,
            Now, Now.AddDays(10)), new(34.99, -60.01));
        var hold = new RoutePlannedHold(inbound.Points[^1].Location, inbound.ArrivalTime,
            inbound.ArrivalTime.AddHours(2), RouteHoldCheckStatus.Clear);
        var outbound = Route(new RouteRequest("out", hold.Location, plan.Waypoints[2].Coordinate,
            hold.Until, Now.AddDays(10)), plan.Waypoints[2].Coordinate);
        return plan.WithResult(new RoutePlanResult(session,
            [new(plan.Legs[0].Id, RouteLegOutcomeState.Succeeded, RouteLegOutcomeReason.CalculationSucceeded,
                inbound, executionSession: session, origin: new(RouteLegOriginSource.DeclaredWaypoint), plannedHold: hold),
             new(plan.Legs[1].Id, RouteLegOutcomeState.Succeeded, RouteLegOutcomeReason.CalculationSucceeded,
                outbound, executionSession: session, origin: new(RouteLegOriginSource.AcceptedPredecessor,
                    new(plan.Id, plan.Legs[0].Id, session.Model, session.Id, inbound.Request.RouteId)))]));
    }

    private static RouteResult Route(RouteRequest request, Coordinate endpoint) =>
        new(request, ForecastModel.NoaaGfs,
            [new(request.Origin, request.DepartureTime, 90, 6, 15, 180, 0),
             new(endpoint, request.DepartureTime.AddHours(4), 90, 6, 15, 180, 50)], new(1, 1, 1, 1));

    [Theory]
    [InlineData("model")]
    [InlineData("session")]
    [InlineData("result")]
    [InlineData("plan")]
    [InlineData("self")]
    [InlineData("time")]
    [InlineData("position")]
    [InlineData("partial")]
    [InlineData("conflict")]
    [InlineData("stale")]
    public void Forged_predecessor_never_authorizes_downstream_geometry(string corruption)
    {
        var plan = CalculatedPlan();
        var result = plan.Results[0];
        var first = result.Legs[0];
        var second = result.Legs[1];
        var reference = second.Origin!.Predecessor!;
        reference = corruption switch
        {
            "model" => reference with { Model = ForecastModel.EcmwfIfs },
            "session" => reference with { SessionId = new RouteCalculationSessionId() },
            "result" => reference with { RouteId = "not-the-accepted-result" },
            "plan" => reference with { PlanId = new RoutePlanId() },
            "self" => reference with { LegId = second.LegId },
            _ => reference
        };
        var route = second.Route!;
        if (corruption is "position" or "time")
        {
            var request = new RouteRequest(route.Request.RouteId,
                corruption == "position" ? plan.Waypoints[1].Coordinate : route.Request.Origin,
                route.Request.Destination,
                corruption == "time" ? route.Request.DepartureTime.AddHours(1) : route.Request.DepartureTime,
                route.Request.LatestArrivalTime);
            route = Route(request, route.Points[^1].Location);
        }
        if (corruption == "partial")
            first = new(first.LegId, RouteLegOutcomeState.Succeeded, RouteLegOutcomeReason.ForecastExhausted,
                new RouteResult(first.Route!.Request, first.Route.Model, first.Route.Points, first.Route.Diagnostics,
                    RouteCompletion.ForecastExhausted), executionSession: first.ExecutionSession, origin: first.Origin);
        if (corruption == "stale") first = first.DeferInvalidation(RouteLegOutcomeReason.RoutingSetupChanged);
        if (corruption == "conflict")
            first = first.WithPlannedHold(new RoutePlannedHold(first.PlannedHold!.Location,
                first.PlannedHold.From, first.PlannedHold.Until, RouteHoldCheckStatus.Conflict, "zone"));
        second = new(second.LegId, second.State, second.Reason, route, executionSession: second.ExecutionSession,
            origin: new(RouteLegOriginSource.AcceptedPredecessor, reference));
        Assert.Throws<ArgumentException>(() => plan.WithResult(new RoutePlanResult(result.Session, [first, second])));
    }

    [Fact]
    public void New_outer_session_does_not_rebrand_sailed_history_or_historical_hold()
    {
        var plan = CalculatedPlan();
        plan = plan.MarkSailed(plan.Legs[0].Id);
        var original = plan.Results[0].Legs[0];
        var outer = new RouteCalculationSession(plan.Id, ForecastModel.NoaaGfs, Now.AddDays(1));
        var replacement = plan.WithResult(new RoutePlanResult(outer, plan.Results[0].Legs));
        replacement = replacement.ChangeStopover(plan.Waypoints[1].Id, TimeSpan.FromHours(8));
        var visual = RoutePlanVisualization.Create(replacement)[0];
        Assert.Equal(original.ExecutionSession!.Id, visual.Key.SessionId);
        Assert.NotEqual(outer.Id, visual.Key.SessionId);
        Assert.Same(original.PlannedHold, visual.PlannedHold);
        Assert.Equal(TimeSpan.FromHours(2), visual.StopoverAfter);
        Assert.Equal(original.ExecutionSession.StartedAt, visual.SessionStartedAt);
    }

    [Fact]
    public void Save_as_remaps_only_plan_scoped_references_preserving_original_execution()
    {
        var original = CalculatedPlan();
        var copied = original.CopyAs(new RoutePlanId(), "Copy");
        var first = copied.Results[0].Legs[0];
        var second = copied.Results[0].Legs[1];
        Assert.NotEqual(original.Id, copied.Id);
        Assert.Equal(copied.Id, second.Origin!.Predecessor!.PlanId);
        Assert.Equal(first.LegId, second.Origin.Predecessor.LegId);
        Assert.Equal(first.ExecutionSession!.Id, second.Origin.Predecessor.SessionId);
        Assert.Same(original.Results[0].Legs[0].Route, first.Route);
        Assert.Equal(original.Id, first.ExecutionSession.PlanId);
    }

    [Fact]
    public void Setup_edits_keep_sailed_geometry_and_invalidate_dependent_unsailed_suffix()
    {
        var plan = CalculatedPlan();
        var firstId = plan.Legs[0].Id;
        plan = plan.MarkSailed(firstId);
        var historical = plan.Results[0].Legs[0];
        var changed = plan.WithRoutingSetup(new RoutingSetup(RoutingSetupTests.Demo()));
        Assert.Same(historical.Route, changed.Results[0].Legs[0].Route);
        Assert.Equal(RouteLegOutcomeReason.RoutingSetupChanged, changed.Results[0].Legs[0].DeferredInvalidationReason);
        Assert.Equal(RouteLegOutcomeState.Invalidated, changed.Results[0].Legs[1].State);
        Assert.Equal(RouteLegOutcomeState.Invalidated, changed.UnmarkSailed(firstId).Results[0].Legs[0].State);
    }

    [Fact]
    public void Changing_active_leg_rejects_inherited_origin_but_unmark_retains_valid_causal_history()
    {
        var plan = CalculatedPlan();
        var second = plan.Legs[1].Id;
        var unmarked = plan.MarkSailed(second).UnmarkSailed(second);
        Assert.Equal(RouteLegOutcomeState.Succeeded, unmarked.Results[0].Legs[1].State);
        var changed = plan.SetActiveLeg(second);
        Assert.Equal(RouteLegOutcomeState.Succeeded, changed.Results[0].Legs[0].State);
        Assert.Equal(RouteLegOutcomeState.Invalidated, changed.Results[0].Legs[1].State);
    }
}
