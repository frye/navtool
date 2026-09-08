using System.Collections.Immutable;

namespace Navtool.Core;

public readonly record struct RouteVisualizationKey(
    RoutePlanId PlanId,
    RouteLegId LegId,
    ForecastModel Model,
    RouteCalculationSessionId SessionId,
    string RouteId);

public sealed record RouteLegVisualization(
    RouteVisualizationKey Key,
    int LegIndex,
    RouteWaypoint From,
    RouteWaypoint To,
    RouteLegOutcomeState State,
    RouteLegOutcomeReason Reason,
    RouteResult? Route,
    string? Detail,
    bool IsSailed,
    DateTimeOffset SessionStartedAt,
    DateTimeOffset? SessionCompletedAt,
    RoutePlannedHold? PlannedHold = null,
    bool HasHistoricalHoldContext = false)
{
    public TimeSpan? StopoverAfter => HasHistoricalHoldContext
        ? PlannedHold is null ? null : PlannedHold.Until - PlannedHold.From
        : To.Stopover;

    public bool HasOptimizedGeometry =>
        Route is not null &&
        State == RouteLegOutcomeState.Succeeded;
}

public static class RoutePlanVisualization
{
    public static ImmutableArray<RouteLegVisualization> Create(RoutePlan plan)
    {
        ArgumentNullException.ThrowIfNull(plan);
        var legs = plan.Legs.ToDictionary(leg => leg.Id);
        var waypoints = plan.Waypoints.ToDictionary(waypoint => waypoint.Id);
        return plan.Results
            .SelectMany(result => result.Legs.Select(outcome =>
            {
                var leg = legs[outcome.LegId];
                var execution = outcome.ExecutionSession ?? result.Session;
                return new RouteLegVisualization(
                    new RouteVisualizationKey(
                        plan.Id,
                        leg.Id,
                        result.Model,
                        execution.Id,
                        outcome.Route?.Request.RouteId ?? string.Empty),
                    leg.Index,
                    waypoints[leg.FromWaypointId],
                    waypoints[leg.ToWaypointId],
                    outcome.State,
                    outcome.Reason,
                    outcome.Route,
                    outcome.Detail,
                    plan.SailedLegIds.Contains(leg.Id),
                    execution.StartedAt,
                    execution.CompletedAt,
                    outcome.PlannedHold,
                    outcome.Origin is not null || outcome.PlannedHold is not null);
            }))
            .OrderBy(item => item.LegIndex)
            .ThenBy(item => item.Key.Model)
            .ToImmutableArray();
    }
}
