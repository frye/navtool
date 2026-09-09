using System.Collections.Immutable;
using System.Security.Cryptography;

namespace Navtool.Core;

public readonly record struct RoutePlanId(Guid Value)
{
    public RoutePlanId() : this(Guid.NewGuid())
    {
    }

    public override string ToString() => Value.ToString("N");
}

public readonly record struct RouteWaypointId(Guid Value)
{
    public RouteWaypointId() : this(Guid.NewGuid())
    {
    }

    public override string ToString() => Value.ToString("N");
}

public readonly record struct RouteCalculationSessionId(Guid Value)
{
    public RouteCalculationSessionId() : this(Guid.NewGuid())
    {
    }

    public override string ToString() => Value.ToString("N");
}

public readonly record struct RouteLegId(Guid Value)
{
    public static RouteLegId FromEndpoints(RouteWaypointId from, RouteWaypointId to)
    {
        Span<byte> input = stackalloc byte[32];
        from.Value.TryWriteBytes(input[..16]);
        to.Value.TryWriteBytes(input[16..]);
        Span<byte> hash = stackalloc byte[32];
        SHA256.HashData(input, hash);
        return new RouteLegId(new Guid(hash[..16]));
    }

    public override string ToString() => Value.ToString("N");
}

public sealed record RouteWaypoint
{
    public RouteWaypoint(
        RouteWaypointId id,
        string name,
        Coordinate coordinate,
        TimeSpan? stopover = null)
    {
        if (id.Value == Guid.Empty)
        {
            throw new ArgumentException("A waypoint ID cannot be empty.", nameof(id));
        }

        ArgumentException.ThrowIfNullOrWhiteSpace(name);
        if (stopover <= TimeSpan.Zero)
        {
            throw new ArgumentOutOfRangeException(nameof(stopover), "A stopover must be greater than zero.");
        }

        Id = id;
        Name = name.Trim();
        Coordinate = coordinate;
        Stopover = stopover;
    }

    public RouteWaypoint(string name, Coordinate coordinate, TimeSpan? stopover = null)
        : this(new RouteWaypointId(), name, coordinate, stopover)
    {
    }

    public RouteWaypointId Id { get; }

    public string Name { get; }

    public Coordinate Coordinate { get; }

    public TimeSpan? Stopover { get; }

    public RouteWaypoint Rename(string name) => new(Id, name, Coordinate, Stopover);

    public RouteWaypoint MoveTo(Coordinate coordinate) => new(Id, Name, coordinate, Stopover);

    public RouteWaypoint WithStopover(TimeSpan? stopover) => new(Id, Name, Coordinate, stopover);
}

public sealed record RouteLeg(
    RouteLegId Id,
    int Index,
    RouteWaypointId FromWaypointId,
    RouteWaypointId ToWaypointId)
{
    public static RouteLeg Create(int index, RouteWaypoint from, RouteWaypoint to) =>
        new(RouteLegId.FromEndpoints(from.Id, to.Id), index, from.Id, to.Id);
}

public sealed record RouteCalculationSession
{
    public RouteCalculationSession(
        RouteCalculationSessionId id,
        RoutePlanId planId,
        ForecastModel model,
        DateTimeOffset startedAt,
        DateTimeOffset? completedAt = null)
    {
        if (id.Value == Guid.Empty)
        {
            throw new ArgumentException("A calculation session ID cannot be empty.", nameof(id));
        }

        if (planId.Value == Guid.Empty)
        {
            throw new ArgumentException("A route plan ID cannot be empty.", nameof(planId));
        }

        _ = model.Provider();
        var utcStartedAt = startedAt.ToUniversalTime();
        var utcCompletedAt = completedAt?.ToUniversalTime();
        if (utcCompletedAt < utcStartedAt)
        {
            throw new ArgumentOutOfRangeException(nameof(completedAt), "Completion cannot precede the start.");
        }

        Id = id;
        PlanId = planId;
        Model = model;
        StartedAt = utcStartedAt;
        CompletedAt = utcCompletedAt;
    }

    public RouteCalculationSession(
        RoutePlanId planId,
        ForecastModel model,
        DateTimeOffset startedAt)
        : this(new RouteCalculationSessionId(), planId, model, startedAt)
    {
    }

    public RouteCalculationSessionId Id { get; }

    public RoutePlanId PlanId { get; }

    public ForecastModel Model { get; }

    public DateTimeOffset StartedAt { get; }

    public DateTimeOffset? CompletedAt { get; }

    public RouteCalculationSession Complete(DateTimeOffset completedAt) =>
        new(Id, PlanId, Model, StartedAt, completedAt);
}

public enum RouteLegOutcomeState
{
    Pending,
    NotCalculated,
    Succeeded,
    Failed,
    Cancelled,
    Blocked,
    OutsideForecastWindow,
    Invalidated
}

public enum RouteLegOutcomeReason
{
    None,
    BeforeActiveLeg,
    CalculationSucceeded,
    ForecastExhausted,
    ForecastAcquisitionFailed,
    RouteCalculationFailed,
    ResultValidationFailed,
    CalculationCancelled,
    BlockedByPriorFailure,
    OutsideForecastWindow,
    WaypointCoordinateChanged,
    WaypointsReordered,
    StopoverChanged,
    WaypointAdded,
    WaypointRemoved,
    CurrentPositionChanged,
    DurationExhausted,
    RoutingSetupChanged,
    StopoverExclusionConflict,
    StopoverValidationUnavailable,
    PredecessorChanged,
    ResourceLimit,
    InvalidBoat,
    MissingRequiredSource,
    DepartureChanged
}

public static class RouteCompletionOutcome
{
    public static RouteLegOutcomeReason ToLegOutcomeReason(this RouteCompletion completion) =>
        completion switch
        {
            RouteCompletion.DestinationReached => RouteLegOutcomeReason.CalculationSucceeded,
            RouteCompletion.ForecastExhausted => RouteLegOutcomeReason.ForecastExhausted,
            RouteCompletion.DurationExhausted => RouteLegOutcomeReason.DurationExhausted,
            _ => throw new ArgumentOutOfRangeException(nameof(completion))
        };
}

public sealed record RouteLegResult
{
    public RouteLegResult(
        RouteLegId legId,
        RouteLegOutcomeState state,
        RouteLegOutcomeReason reason,
        RouteResult? route = null,
        string? detail = null,
        RouteLegOutcomeReason? deferredInvalidationReason = null,
        RouteCalculationSession? executionSession = null,
        RouteLegOrigin? origin = null,
        RoutePlannedHold? plannedHold = null,
        ModelRouteFailure? failure = null)
    {
        if (legId.Value == Guid.Empty)
        {
            throw new ArgumentException("A route leg ID cannot be empty.", nameof(legId));
        }

        if (!Enum.IsDefined(state))
        {
            throw new ArgumentOutOfRangeException(nameof(state));
        }

        if (!Enum.IsDefined(reason))
        {
            throw new ArgumentOutOfRangeException(nameof(reason));
        }

        if (state == RouteLegOutcomeState.Succeeded && route is null)
        {
            throw new ArgumentException("A successful leg outcome requires a route.", nameof(route));
        }

        if (state != RouteLegOutcomeState.Succeeded && route is not null)
        {
            throw new ArgumentException("Only successful leg outcomes may contain a route.", nameof(route));
        }
        if (route is not null && reason != route.Completion.ToLegOutcomeReason())
            throw new ArgumentException("The outcome reason must match the native route completion.", nameof(reason));

        if ((state == RouteLegOutcomeState.Pending && reason != RouteLegOutcomeReason.None) ||
            (state != RouteLegOutcomeState.Pending && reason == RouteLegOutcomeReason.None))
        {
            throw new ArgumentException("The outcome state and reason are inconsistent.", nameof(reason));
        }

        if (deferredInvalidationReason is not null &&
            (deferredInvalidationReason == RouteLegOutcomeReason.None ||
             !Enum.IsDefined(deferredInvalidationReason.Value)))
        {
            throw new ArgumentOutOfRangeException(
                nameof(deferredInvalidationReason),
                "A deferred invalidation requires a defined non-empty reason.");
        }

        LegId = legId;
        State = state;
        Reason = reason;
        Route = route;
        Detail = string.IsNullOrWhiteSpace(detail) ? null : detail.Trim();
        DeferredInvalidationReason = deferredInvalidationReason;
        if (executionSession is not null && route is not null && executionSession.Model != route.Model)
            throw new ArgumentException("Execution model does not match the route.", nameof(executionSession));
        if (origin is not null &&
            (!Enum.IsDefined(origin.Source) ||
             (origin.Source == RouteLegOriginSource.AcceptedPredecessor) != (origin.Predecessor is not null)))
            throw new ArgumentException("An accepted-predecessor origin requires exactly one predecessor reference.", nameof(origin));
        if (plannedHold is not null &&
            (route is null || !route.IsComplete ||
             !plannedHold.Location.IsSameLocation(route.Points[^1].Location) ||
             plannedHold.From != route.ArrivalTime))
            throw new ArgumentException("A planned hold must follow the actual complete route arrival.", nameof(plannedHold));
        ExecutionSession = executionSession;
        Origin = origin;
        PlannedHold = plannedHold;
        if (failure is not null)
        {
            if (state is not (RouteLegOutcomeState.Failed or RouteLegOutcomeState.Cancelled) ||
                (state == RouteLegOutcomeState.Cancelled) != (failure.Kind == RoutingFailureKind.Cancelled) ||
                !Enum.IsDefined(failure.Stage) || !Enum.IsDefined(failure.Kind) ||
                string.IsNullOrWhiteSpace(failure.Code) || string.IsNullOrWhiteSpace(failure.Message))
                throw new ArgumentException("Failure audit must describe a failed or cancelled leg.", nameof(failure));
            var attempts = failure.Attempts.IsDefault ? ImmutableArray<RouteAttemptAudit>.Empty : failure.Attempts;
            if (attempts.Any(attempt => attempt is null || attempt.AttemptId == Guid.Empty ||
                    !Enum.IsDefined(attempt.Solver) || attempt.CompletedAt < attempt.StartedAt ||
                    (attempt.FailureKind is { } kind && !Enum.IsDefined(kind))) ||
                attempts.Select(attempt => attempt.AttemptId).Distinct().Count() != attempts.Length)
                throw new ArgumentException("Failure attempt identities and times must be consistent.", nameof(failure));
            Failure = failure with { Attempts = attempts };
        }
    }

    public RouteLegId LegId { get; }

    public RouteLegOutcomeState State { get; }

    public RouteLegOutcomeReason Reason { get; }

    public RouteResult? Route { get; }

    public string? Detail { get; }

    public RouteLegOutcomeReason? DeferredInvalidationReason { get; }

    public RouteCalculationSession? ExecutionSession { get; }
    public RouteLegOrigin? Origin { get; }
    public RoutePlannedHold? PlannedHold { get; }
    public ModelRouteFailure? Failure { get; }

    public RouteLegResult WithExecutionSession(RouteCalculationSession session) =>
        new(LegId, State, Reason, Route, Detail, DeferredInvalidationReason, session, Origin, PlannedHold, Failure);

    public RouteLegResult WithPlannedHold(RoutePlannedHold? hold) =>
        new(LegId, State, Reason, Route, Detail, DeferredInvalidationReason, ExecutionSession, Origin, hold, Failure);

    public RouteLegResult Invalidate(RouteLegOutcomeReason reason) =>
        new(LegId, RouteLegOutcomeState.Invalidated, reason);

    public RouteLegResult DeferInvalidation(RouteLegOutcomeReason reason) =>
        State == RouteLegOutcomeState.Invalidated
            ? this
            : new(LegId, State, Reason, Route, Detail, reason, ExecutionSession, Origin, PlannedHold, Failure);
}

public sealed record RoutePlanResult
{
    public RoutePlanResult(
        RouteCalculationSession session,
        IEnumerable<RouteLegResult> legs)
    {
        ArgumentNullException.ThrowIfNull(session);
        ArgumentNullException.ThrowIfNull(legs);
        var immutableLegs = legs.Select(leg =>
            (leg.Route is not null || leg.Failure is not null) && leg.ExecutionSession is null
                ? leg.WithExecutionSession(session)
                : leg).ToImmutableArray();
        if (immutableLegs.Select(leg => leg.LegId).Distinct().Count() != immutableLegs.Length)
        {
            throw new ArgumentException("A route plan result cannot contain duplicate leg IDs.", nameof(legs));
        }

        if (immutableLegs.Any(leg => leg.Route is not null && leg.Route.Model != session.Model))
        {
            throw new ArgumentException("Every route leg result must use the calculation session model.", nameof(legs));
        }

        Session = session;
        Legs = immutableLegs;
    }

    public RouteCalculationSession Session { get; }

    public ForecastModel Model => Session.Model;

    public ImmutableArray<RouteLegResult> Legs { get; }

    public bool IsInvalidated => Legs.Any(leg =>
        leg.State == RouteLegOutcomeState.Invalidated ||
        leg.DeferredInvalidationReason is not null);
}

/// <summary>
/// A user-placed current-start marker: an arbitrary position (not a permanent waypoint) plus
/// the explicit departure time from that position. Never inferred from wall clock or GPS.
/// </summary>
public sealed record RouteCurrentPosition
{
    public RouteCurrentPosition(Coordinate coordinate, DateTimeOffset departureTime)
    {
        Coordinate = coordinate;
        DepartureTime = departureTime.ToUniversalTime();
    }

    public Coordinate Coordinate { get; }

    public DateTimeOffset DepartureTime { get; }
}

public sealed record RoutePlan
{
    public RoutePlan(
        RoutePlanId id,
        string name,
        IEnumerable<RouteWaypoint> waypoints,
        IEnumerable<RoutePlanResult>? results = null,
        IEnumerable<RouteLegId>? sailedLegIds = null,
        RouteCurrentPosition? currentPosition = null,
        RouteLegId? activeLegId = null,
        RoutingSetup? routingSetup = null,
        RoutePlanningInputs? planningInputs = null)
    {
        if (id.Value == Guid.Empty)
        {
            throw new ArgumentException("A route plan ID cannot be empty.", nameof(id));
        }

        ArgumentException.ThrowIfNullOrWhiteSpace(name);
        ArgumentNullException.ThrowIfNull(waypoints);
        var immutableWaypoints = waypoints.ToImmutableArray();
        ValidateWaypoints(immutableWaypoints);
        var legs = CreateLegs(immutableWaypoints);
        var immutableResults = (results ?? []).ToImmutableArray();
        var immutableSailed = (sailedLegIds ?? []).ToImmutableHashSet();
        ValidateReferences(
            id,
            immutableWaypoints,
            legs,
            immutableResults,
            immutableSailed,
            currentPosition,
            activeLegId);

        Id = id;
        Name = name.Trim();
        Waypoints = immutableWaypoints;
        Legs = legs;
        Results = immutableResults;
        SailedLegIds = immutableSailed;
        CurrentPosition = currentPosition;
        ActiveLegId = activeLegId;
        RoutingSetup = routingSetup;
        planningInputs?.Validate();
        PlanningInputs = planningInputs;
    }

    public RoutePlan(string name, IEnumerable<RouteWaypoint> waypoints)
        : this(new RoutePlanId(), name, waypoints)
    {
    }

    public RoutePlanId Id { get; }

    public string Name { get; }

    public ImmutableArray<RouteWaypoint> Waypoints { get; }

    public ImmutableArray<RouteLeg> Legs { get; }

    public ImmutableArray<RoutePlanResult> Results { get; }

    public ImmutableHashSet<RouteLegId> SailedLegIds { get; }

    public RoutingSetup? RoutingSetup { get; }
    public RoutePlanningInputs? PlanningInputs { get; }

    public RoutePlan WithPlanningInputs(RoutePlanningInputs? inputs)
    {
        if (PlanningInputs == inputs) return this;
        return new(Id, Name, Waypoints,
            Results.Select(result => RebuildResult(result, Legs, ActiveLegIndex, RouteLegOutcomeReason.RoutingSetupChanged)),
            SailedLegIds, CurrentPosition, ActiveLegId, RoutingSetup, inputs);
    }

    public RoutePlan WithRoutingSetup(RoutingSetup? setup)
    {
        if (RoutingSetup == setup) return this;
        var results = Results.Select(result =>
            RebuildResult(result, Legs, 0, RouteLegOutcomeReason.RoutingSetupChanged));
        return new(Id, Name, Waypoints, results, SailedLegIds, CurrentPosition, ActiveLegId, setup, PlanningInputs);
    }

    public RoutePlan SetRoutingSetup(RoutingSetup? setup) => WithRoutingSetup(setup);

    public RoutePlan InvalidateFromActiveLeg(RouteLegOutcomeReason reason)
    {
        if (reason == RouteLegOutcomeReason.None || !Enum.IsDefined(reason))
            throw new ArgumentOutOfRangeException(nameof(reason));
        return new(Id, Name, Waypoints,
            Results.Select(result => RebuildResult(result, Legs, ActiveLegIndex, reason)),
            SailedLegIds, CurrentPosition, ActiveLegId, RoutingSetup, PlanningInputs);
    }

    /// <summary>
    /// The user-placed current position and explicit departure time, or <c>null</c> when routing
    /// should begin from the itinerary start. Never inferred from wall clock or GPS.
    /// </summary>
    public RouteCurrentPosition? CurrentPosition { get; }

    /// <summary>
    /// An explicit override for the leg future routing should resume from. When <c>null</c>, the
    /// active leg defaults to the first unsailed leg.
    /// </summary>
    public RouteLegId? ActiveLegId { get; }

    /// <summary>
    /// The index of the leg future routing should resume from: the explicit <see cref="ActiveLegId"/>
    /// when set, otherwise the first leg that has not been marked sailed. Equal to <see cref="Legs"/>
    /// length when every leg has been sailed.
    /// </summary>
    public int ActiveLegIndex => ResolveActiveLegIndex(Legs, SailedLegIds, ActiveLegId);

    public RouteLeg? ActiveLeg
    {
        get
        {
            var index = ActiveLegIndex;
            return index < Legs.Length ? Legs[index] : null;
        }
    }

    public bool IsItineraryComplete => ActiveLegIndex >= Legs.Length;

    public bool HasInvalidatedResults => Results.Any(result => result.IsInvalidated);

    public RoutePlanResult? LatestResult(ForecastModel model) =>
        Results.SingleOrDefault(result => result.Model == model);

    public RoutePlan Rename(string name) =>
        new(Id, name, Waypoints, Results, SailedLegIds, CurrentPosition, ActiveLegId, RoutingSetup, PlanningInputs);

    public RoutePlan CopyAs(RoutePlanId id, string name)
    {
        var copiedWaypoints = Waypoints.Select(point =>
            new RouteWaypoint(point.Name, point.Coordinate, point.Stopover)).ToImmutableArray();
        var copiedLegs = CreateLegs(copiedWaypoints);
        var legMap = Legs.ToDictionary(leg => leg.Id, leg => copiedLegs[leg.Index].Id);
        var results = Results.Select(result => new RoutePlanResult(
            new RouteCalculationSession(new RouteCalculationSessionId(), id, result.Model,
                result.Session.StartedAt, result.Session.CompletedAt),
            result.Legs.Select(outcome => new RouteLegResult(
                legMap[outcome.LegId], outcome.State, outcome.Reason, outcome.Route,
                outcome.Detail, outcome.DeferredInvalidationReason, outcome.ExecutionSession,
                outcome.Origin?.Predecessor is { } predecessor
                    ? outcome.Origin with
                    {
                        Predecessor = predecessor with { PlanId = id, LegId = legMap[predecessor.LegId] }
                    }
                    : outcome.Origin,
                outcome.PlannedHold, outcome.Failure))));
        return new RoutePlan(id, name, copiedWaypoints, results,
            SailedLegIds.Select(legId => legMap[legId]), CurrentPosition,
            ActiveLegId is { } active ? legMap[active] : null, RoutingSetup, PlanningInputs);
    }

    public RoutePlan RenameWaypoint(RouteWaypointId waypointId, string name)
    {
        var index = FindWaypointIndex(waypointId);
        return ReplaceWaypoint(index, Waypoints[index].Rename(name), null, RouteLegOutcomeReason.None);
    }

    public RoutePlan ChangeWaypointCoordinate(RouteWaypointId waypointId, Coordinate coordinate)
    {
        var index = FindWaypointIndex(waypointId);
        if (Waypoints[index].Coordinate.IsSameLocation(coordinate))
        {
            return this;
        }

        return ReplaceWaypoint(
            index,
            Waypoints[index].MoveTo(coordinate),
            Math.Max(0, index - 1),
            RouteLegOutcomeReason.WaypointCoordinateChanged);
    }

    public RoutePlan ChangeStopover(RouteWaypointId waypointId, TimeSpan? stopover)
    {
        var index = FindWaypointIndex(waypointId);
        EnsureIntermediate(index, "Only intermediate waypoints may have stopovers.");
        if (Waypoints[index].Stopover == stopover)
        {
            return this;
        }

        return ReplaceWaypoint(
            index,
            Waypoints[index].WithStopover(stopover),
            index,
            RouteLegOutcomeReason.StopoverChanged);
    }

    public RoutePlan AddWaypoint(RouteWaypoint waypoint, int index)
    {
        ArgumentNullException.ThrowIfNull(waypoint);
        if (index <= 0 || index >= Waypoints.Length)
        {
            throw new ArgumentOutOfRangeException(nameof(index), "A waypoint can only be added between start and finish.");
        }

        if (Waypoints.Any(existing => existing.Id == waypoint.Id))
        {
            throw new ArgumentException("Waypoint IDs must be unique.", nameof(waypoint));
        }

        var updated = Waypoints.Insert(index, waypoint);
        return Rebuild(updated, Math.Max(0, index - 1), RouteLegOutcomeReason.WaypointAdded);
    }

    public RoutePlan RemoveWaypoint(RouteWaypointId waypointId)
    {
        var index = FindWaypointIndex(waypointId);
        EnsureIntermediate(index, "Start and finish waypoints cannot be removed.");
        return Rebuild(
            Waypoints.RemoveAt(index),
            Math.Max(0, index - 1),
            RouteLegOutcomeReason.WaypointRemoved);
    }

    public RoutePlan MoveWaypoint(RouteWaypointId waypointId, int newIndex)
    {
        var oldIndex = FindWaypointIndex(waypointId);
        EnsureIntermediate(oldIndex, "Start and finish waypoints cannot be reordered.");
        if (newIndex <= 0 || newIndex >= Waypoints.Length - 1)
        {
            throw new ArgumentOutOfRangeException(nameof(newIndex), "Intermediate waypoints must remain between start and finish.");
        }

        if (newIndex == oldIndex)
        {
            return this;
        }

        var waypoint = Waypoints[oldIndex];
        var updated = Waypoints.RemoveAt(oldIndex).Insert(newIndex, waypoint);
        return Rebuild(
            updated,
            Math.Max(0, Math.Min(oldIndex, newIndex) - 1),
            RouteLegOutcomeReason.WaypointsReordered);
    }

    public RoutePlan WithResult(RoutePlanResult result)
    {
        ArgumentNullException.ThrowIfNull(result);
        if (result.Session.PlanId != Id)
        {
            throw new ArgumentException("The calculation session belongs to a different route plan.", nameof(result));
        }

        ValidateResultLegs(result, Legs);
        var existingForModel = LatestResult(result.Model);
        if (existingForModel is not null && SailedLegIds.Count > 0)
        {
            var existingByLeg = existingForModel.Legs.ToDictionary(leg => leg.LegId);
            result = new RoutePlanResult(
                result.Session,
                result.Legs.Select(outcome =>
                    SailedLegIds.Contains(outcome.LegId) &&
                    existingByLeg.TryGetValue(outcome.LegId, out var sailed)
                        ? sailed
                        : outcome));
        }

        var retained = Results.Where(existing => existing.Model != result.Model);
        return new RoutePlan(
            Id,
            Name,
            Waypoints,
            retained.Append(result),
            SailedLegIds,
            CurrentPosition,
            ActiveLegId,
            RoutingSetup, PlanningInputs);
    }

    /// <summary>
    /// Marks a leg as sailed (a real-world, model-independent itinerary fact). Sailed results are
    /// retained as history and are never invalidated by forecast recalculation. Does not itself
    /// invalidate any results.
    /// </summary>
    public RoutePlan MarkSailed(RouteLegId legId)
    {
        EnsureLegExists(legId);
        var newActiveLegId = ActiveLegId == legId ? null : ActiveLegId;
        return new RoutePlan(
            Id,
            Name,
            Waypoints,
            Results,
            SailedLegIds.Add(legId),
            CurrentPosition,
            newActiveLegId,
            RoutingSetup, PlanningInputs);
    }

    public RoutePlan UnmarkSailed(RouteLegId legId)
    {
        EnsureLegExists(legId);
        var leg = Legs.Single(item => item.Id == legId);
        var from = Waypoints.Single(item => item.Id == leg.FromWaypointId);
        var to = Waypoints.Single(item => item.Id == leg.ToWaypointId);
        var newSailed = SailedLegIds.Remove(legId);
        var newActiveIndex = ResolveActiveLegIndex(Legs, newSailed, ActiveLegId);
        var updatedResults = Results.Select(result => new RoutePlanResult(
            result.Session,
            result.Legs.Select(outcome =>
            {
                if (outcome.LegId != legId)
                {
                    return outcome;
                }

                if (outcome.DeferredInvalidationReason is { } deferredReason)
                {
                    return outcome.Invalidate(deferredReason);
                }

                if (outcome.Route is null)
                {
                    return outcome;
                }

                var originMatchesWaypoint = outcome.Route.Request.Origin.IsSameLocation(from.Coordinate);
                var originMatchesCurrentPosition =
                    CurrentPosition is not null &&
                    leg.Index == newActiveIndex &&
                    outcome.Route.Request.Origin.IsSameLocation(CurrentPosition.Coordinate) &&
                    (outcome.Origin is null || outcome.Route.Request.DepartureTime == NormalizeDeparture(CurrentPosition.DepartureTime));
                var originMatchesPredecessor = HasValidPredecessor(outcome, result, leg, Id,
                    leg.Index > 0 ? Legs[leg.Index - 1].Id : null);
                var destinationMatches = outcome.Route.Request.Destination.IsSameLocation(to.Coordinate);
                var validOrigin = outcome.Origin?.Source switch
                {
                    RouteLegOriginSource.DeclaredWaypoint => originMatchesWaypoint,
                    RouteLegOriginSource.CurrentPosition => originMatchesCurrentPosition,
                    RouteLegOriginSource.AcceptedPredecessor => originMatchesPredecessor,
                    _ => originMatchesWaypoint || originMatchesCurrentPosition
                };
                if (validOrigin && destinationMatches)
                {
                    return outcome;
                }

                var usedCurrentPosition =
                    CurrentPosition is not null &&
                    !originMatchesWaypoint &&
                    outcome.Route.Request.Origin.IsSameLocation(CurrentPosition.Coordinate);
                return outcome.Invalidate(usedCurrentPosition
                    ? RouteLegOutcomeReason.CurrentPositionChanged
                    : RouteLegOutcomeReason.WaypointCoordinateChanged);
            }))).ToArray();
        updatedResults = updatedResults.Select(result =>
        {
            var changed = result.Legs.Single(item => item.LegId == legId);
            return changed.State == RouteLegOutcomeState.Invalidated
                ? RebuildResult(result, Legs, leg.Index + 1, RouteLegOutcomeReason.PredecessorChanged)
                : result;
        }).ToArray();
        return new RoutePlan(
            Id,
            Name,
            Waypoints,
            updatedResults,
            newSailed,
            CurrentPosition,
            ActiveLegId,
            RoutingSetup, PlanningInputs);
    }

    /// <summary>
    /// Records the user-placed current position and its explicit departure time. Retains the
    /// existing stable leg identity of the active leg and never inserts a permanent waypoint.
    /// Invalidates only unsailed results from the active leg forward; sailed results and earlier
    /// legs are untouched.
    /// </summary>
    public RoutePlan SetCurrentPosition(Coordinate coordinate, DateTimeOffset departureTime)
    {
        var updatedPosition = new RouteCurrentPosition(coordinate, departureTime);
        if (CurrentPosition == updatedPosition)
        {
            return this;
        }

        var updatedResults = Results
            .Select(result => RebuildResult(
                result,
                Legs,
                ActiveLegIndex,
                RouteLegOutcomeReason.CurrentPositionChanged))
            .ToArray();
        return new RoutePlan(
            Id,
            Name,
            Waypoints,
            updatedResults,
            SailedLegIds,
            updatedPosition,
            ActiveLegId,
            RoutingSetup, PlanningInputs);
    }

    /// <summary>
    /// Clears the current position so routing resumes from the itinerary start (or the active
    /// leg's own start waypoint). Invalidates only unsailed results from the active leg forward
    /// (mirroring <see cref="SetCurrentPosition"/>), since any accepted route for the active leg
    /// may have used the now-removed current-position origin. Sailed results and earlier legs are
    /// untouched.
    /// </summary>
    public RoutePlan ClearCurrentPosition()
    {
        if (CurrentPosition is null)
        {
            return this;
        }

        var updatedResults = Results
            .Select(result => RebuildResult(
                result,
                Legs,
                ActiveLegIndex,
                RouteLegOutcomeReason.CurrentPositionChanged))
            .ToArray();
        return new RoutePlan(Id, Name, Waypoints, updatedResults, SailedLegIds, null, ActiveLegId, RoutingSetup, PlanningInputs);
    }

    /// <summary>
    /// Explicitly selects the leg that future routing should resume from, overriding the default
    /// first-unfinished-leg resolution. The leg must exist and must not already be sailed.
    /// Invalidates any other unsailed leg's stored route whose origin depended on the current
    /// position, since that origin is only valid for whichever leg is currently active.
    /// </summary>
    public RoutePlan SetActiveLeg(RouteLegId legId)
    {
        EnsureLegExists(legId);
        if (SailedLegIds.Contains(legId))
        {
            throw new InvalidOperationException("A sailed leg cannot be selected as the active leg.");
        }

        return ActiveLegId == legId
            ? this
            : WithActiveLeg(legId);
    }

    /// <summary>
    /// Clears any explicit active-leg selection, reverting to the default first-unfinished-leg
    /// resolution. Invalidates any unsailed leg's stored route left stranded by the resulting
    /// active-leg change, mirroring <see cref="SetActiveLeg"/>.
    /// </summary>
    public RoutePlan ClearActiveLeg() =>
        ActiveLegId is null
            ? this
            : WithActiveLeg(null);

    private RoutePlan WithActiveLeg(RouteLegId? activeLegId)
    {
        var newActiveIndex = ResolveActiveLegIndex(Legs, SailedLegIds, activeLegId);
        var updatedResults = Results
            .Select(result => InvalidateStaleCurrentPositionOrigin(result, newActiveIndex))
            .ToArray();
        return new RoutePlan(Id, Name, Waypoints, updatedResults, SailedLegIds, CurrentPosition, activeLegId, RoutingSetup, PlanningInputs);
    }

    /// <summary>
    /// Invalidates any non-sailed leg outcome (other than <paramref name="newActiveIndex"/>) whose
    /// accepted route origin matches <see cref="CurrentPosition"/>. Such an origin is only ever
    /// valid for the current active leg (see <see cref="ValidateReferences"/>), so it becomes
    /// stale the moment a different leg becomes active.
    /// </summary>
    private RoutePlanResult InvalidateStaleCurrentPositionOrigin(RoutePlanResult result, int newActiveIndex)
    {
        var firstInvalid = Legs.Length;
        foreach (var outcome in result.Legs)
        {
            if (outcome.Route is null || SailedLegIds.Contains(outcome.LegId))
            {
                continue;
            }

            var leg = Legs.Single(item => item.Id == outcome.LegId);
            var from = Waypoints[leg.Index];
            if (leg.Index == newActiveIndex)
            {
                var expectedOrigin = CurrentPosition?.Coordinate ?? from.Coordinate;
                if (!outcome.Route.Request.Origin.IsSameLocation(expectedOrigin))
                    firstInvalid = Math.Min(firstInvalid, leg.Index);
                continue;
            }

            var originIsCurrentPosition = CurrentPosition is not null &&
                outcome.Route.Request.Origin.IsSameLocation(CurrentPosition.Coordinate);
            var originIsOwnWaypoint = outcome.Route.Request.Origin.IsSameLocation(from.Coordinate);
            if (outcome.Origin?.Source == RouteLegOriginSource.CurrentPosition ||
                (outcome.Origin is null && originIsCurrentPosition && !originIsOwnWaypoint))
                firstInvalid = Math.Min(firstInvalid, leg.Index);
        }
        return firstInvalid < Legs.Length
            ? RebuildResult(result, Legs, firstInvalid, RouteLegOutcomeReason.CurrentPositionChanged)
            : result;
    }

    private RoutePlan ReplaceWaypoint(
        int index,
        RouteWaypoint waypoint,
        int? invalidFromLeg,
        RouteLegOutcomeReason reason)
    {
        var updated = Waypoints.SetItem(index, waypoint);
        return invalidFromLeg is null
            ? new RoutePlan(Id, Name, updated, Results, SailedLegIds, CurrentPosition, ActiveLegId, RoutingSetup, PlanningInputs)
            : Rebuild(updated, invalidFromLeg.Value, reason);
    }

    private RoutePlan Rebuild(
        ImmutableArray<RouteWaypoint> waypoints,
        int invalidFromLeg,
        RouteLegOutcomeReason reason)
    {
        ValidateWaypoints(waypoints);
        var newLegs = CreateLegs(waypoints);
        var newLegIds = newLegs.Select(leg => leg.Id).ToImmutableHashSet();
        var removedSailed = SailedLegIds.Except(newLegIds).ToArray();
        if (removedSailed.Length > 0)
        {
            throw new InvalidOperationException("Unmark sailed legs before changing their waypoint boundaries.");
        }

        if (ActiveLegId is { } activeId && !newLegIds.Contains(activeId))
        {
            throw new InvalidOperationException(
                "Clear or reassign the active leg before changing its waypoint boundaries.");
        }

        var updatedResults = Results
            .Select(result => RebuildResult(result, newLegs, invalidFromLeg, reason))
            .ToArray();
        return new RoutePlan(
            Id,
            Name,
            waypoints,
            updatedResults,
            SailedLegIds,
            CurrentPosition,
            ActiveLegId,
            RoutingSetup, PlanningInputs);
    }

    private RoutePlanResult RebuildResult(
        RoutePlanResult result,
        ImmutableArray<RouteLeg> newLegs,
        int invalidFromLeg,
        RouteLegOutcomeReason reason)
    {
        var existing = result.Legs.ToDictionary(leg => leg.LegId);
        var rebuilt = newLegs.Select(leg =>
        {
            if (SailedLegIds.Contains(leg.Id) && existing.TryGetValue(leg.Id, out var sailed))
            {
                return leg.Index >= invalidFromLeg
                    ? sailed.DeferInvalidation(reason)
                    : sailed;
            }

            if (leg.Index < invalidFromLeg && existing.TryGetValue(leg.Id, out var unchanged))
            {
                return unchanged;
            }

            return new RouteLegResult(
                leg.Id,
                RouteLegOutcomeState.Invalidated,
                reason);
        });
        return new RoutePlanResult(result.Session, rebuilt);
    }

    private int FindWaypointIndex(RouteWaypointId waypointId)
    {
        for (var index = 0; index < Waypoints.Length; index++)
        {
            if (Waypoints[index].Id == waypointId)
            {
                return index;
            }
        }

        throw new KeyNotFoundException($"Waypoint '{waypointId}' was not found.");
    }

    private void EnsureIntermediate(int index, string message)
    {
        if (index == 0 || index == Waypoints.Length - 1)
        {
            throw new InvalidOperationException(message);
        }
    }

    private void EnsureLegExists(RouteLegId legId)
    {
        if (!Legs.Any(leg => leg.Id == legId))
        {
            throw new KeyNotFoundException($"Route leg '{legId}' was not found.");
        }
    }

    private static ImmutableArray<RouteLeg> CreateLegs(ImmutableArray<RouteWaypoint> waypoints)
    {
        var builder = ImmutableArray.CreateBuilder<RouteLeg>(waypoints.Length - 1);
        for (var index = 0; index < waypoints.Length - 1; index++)
        {
            builder.Add(RouteLeg.Create(index, waypoints[index], waypoints[index + 1]));
        }

        return builder.MoveToImmutable();
    }

    private static void ValidateWaypoints(ImmutableArray<RouteWaypoint> waypoints)
    {
        if (waypoints.Length < 2)
        {
            throw new ArgumentException("A route plan requires at least a start and finish.", nameof(waypoints));
        }

        if (waypoints.Any(waypoint => waypoint is null))
        {
            throw new ArgumentException("Route waypoints cannot be null.", nameof(waypoints));
        }

        if (waypoints.Select(waypoint => waypoint.Id).Distinct().Count() != waypoints.Length)
        {
            throw new ArgumentException("Waypoint IDs must be unique.", nameof(waypoints));
        }

        if (waypoints[0].Stopover is not null || waypoints[^1].Stopover is not null)
        {
            throw new ArgumentException("Start and finish waypoints cannot have stopovers.", nameof(waypoints));
        }

        for (var index = 1; index < waypoints.Length; index++)
        {
            if (waypoints[index - 1].Coordinate.IsSameLocation(waypoints[index].Coordinate))
            {
                throw new ArgumentException("Adjacent waypoint coordinates must differ.", nameof(waypoints));
            }
        }
    }

    private static void ValidateReferences(
        RoutePlanId planId,
        ImmutableArray<RouteWaypoint> waypoints,
        ImmutableArray<RouteLeg> legs,
        ImmutableArray<RoutePlanResult> results,
        ImmutableHashSet<RouteLegId> sailedLegIds,
        RouteCurrentPosition? currentPosition,
        RouteLegId? activeLegId)
    {
        if (results.Select(result => result.Model).Distinct().Count() != results.Length)
        {
            throw new ArgumentException("Only the latest result for each forecast model may be stored.", nameof(results));
        }

        var legIds = legs.Select(leg => leg.Id).ToImmutableHashSet();
        if (!sailedLegIds.IsSubsetOf(legIds))
        {
            throw new ArgumentException("A sailed-leg reference does not exist in the route plan.", nameof(sailedLegIds));
        }

        if (activeLegId is { } explicitActiveId)
        {
            if (!legIds.Contains(explicitActiveId))
            {
                throw new ArgumentException("The active-leg reference does not exist in the route plan.", nameof(activeLegId));
            }

            if (sailedLegIds.Contains(explicitActiveId))
            {
                throw new ArgumentException("The active leg cannot already be marked sailed.", nameof(activeLegId));
            }
        }

        var activeIndex = ResolveActiveLegIndex(legs, sailedLegIds, activeLegId);
        foreach (var result in results)
        {
            if (result.Session.PlanId != planId)
            {
                throw new ArgumentException("A calculation session references a different route plan.", nameof(results));
            }

            ValidateResultLegs(result, legs);
            foreach (var legResult in result.Legs.Where(item => item.Route is not null))
            {
                if (sailedLegIds.Contains(legResult.LegId))
                {
                    continue;
                }

                var leg = legs.Single(item => item.Id == legResult.LegId);
                var from = waypoints.Single(item => item.Id == leg.FromWaypointId);
                var to = waypoints.Single(item => item.Id == leg.ToWaypointId);
                if (!legResult.Route!.Request.Destination.IsSameLocation(to.Coordinate))
                {
                    throw new ArgumentException("A route result does not match its referenced leg endpoints.", nameof(results));
                }

                var originMatchesWaypoint = legResult.Route.Request.Origin.IsSameLocation(from.Coordinate);
                var originMatchesCurrentPosition =
                    currentPosition is not null &&
                    leg.Index == activeIndex &&
                    legResult.Route.Request.Origin.IsSameLocation(currentPosition.Coordinate) &&
                    (legResult.Origin is null ||
                     legResult.Route.Request.DepartureTime == NormalizeDeparture(currentPosition.DepartureTime));
                var originMatchesPredecessor = HasValidPredecessor(legResult, result, leg, planId,
                    leg.Index > 0 ? legs[leg.Index - 1].Id : null);
                if (legResult.Origin is { } origin)
                {
                    var valid = origin.Source switch
                    {
                        RouteLegOriginSource.DeclaredWaypoint => originMatchesWaypoint,
                        RouteLegOriginSource.CurrentPosition => originMatchesCurrentPosition,
                        RouteLegOriginSource.AcceptedPredecessor => originMatchesPredecessor,
                        _ => false
                    };
                    if (!valid)
                        throw new ArgumentException("A route origin has invalid physical or causal provenance.", nameof(results));
                }
                if (!originMatchesWaypoint && !originMatchesCurrentPosition && !originMatchesPredecessor)
                {
                    throw new ArgumentException("A route result does not match its referenced leg endpoints.", nameof(results));
                }
            }
        }
    }

    private static bool HasValidPredecessor(
        RouteLegResult outcome, RoutePlanResult result, RouteLeg leg, RoutePlanId planId,
        RouteLegId? expectedPredecessor)
    {
        if (outcome.Origin?.Predecessor is not { } reference ||
            reference.PlanId != planId || reference.Model != result.Model || leg.Index == 0 ||
            reference.LegId != expectedPredecessor)
            return false;
        // Result order is not an authority: callers restore arrays in arbitrary order.
        var predecessor = result.Legs.SingleOrDefault(item => item.LegId == reference.LegId);
        if (predecessor?.Route is not { IsComplete: true } route ||
            predecessor.DeferredInvalidationReason is not null ||
            predecessor.ExecutionSession?.Id != reference.SessionId ||
            route.Request.RouteId != reference.RouteId ||
            predecessor.PlannedHold is { AllowsHandoff: false })
            return false;
        var departure = predecessor.PlannedHold?.Until ?? route.ArrivalTime;
        return outcome.Route is { } next &&
            next.Request.Origin.IsSameLocation(route.Points[^1].Location) &&
            next.Request.DepartureTime == NormalizeDeparture(departure);
    }

    internal static DateTimeOffset NormalizeDeparture(DateTimeOffset value) =>
        DateTimeOffset.FromUnixTimeSeconds(value.ToUnixTimeSeconds());

    private static int ResolveActiveLegIndex(
        ImmutableArray<RouteLeg> legs,
        ImmutableHashSet<RouteLegId> sailedLegIds,
        RouteLegId? activeLegId)
    {
        if (activeLegId is { } explicitId)
        {
            return legs.Single(leg => leg.Id == explicitId).Index;
        }

        for (var index = 0; index < legs.Length; index++)
        {
            if (!sailedLegIds.Contains(legs[index].Id))
            {
                return index;
            }
        }

        return legs.Length;
    }

    private static void ValidateResultLegs(RoutePlanResult result, ImmutableArray<RouteLeg> legs)
    {
        var expected = legs.Select(leg => leg.Id).ToImmutableHashSet();
        var actual = result.Legs.Select(leg => leg.LegId).ToImmutableHashSet();
        if (!expected.SetEquals(actual))
        {
            throw new ArgumentException("A route plan result must contain exactly one outcome for every current leg.");
        }
    }
}

public sealed record RoutePlanSummary(RoutePlanId Id, string Name, int WaypointCount);

public sealed class RoutePlanRepositoryException : Exception
{
    public RoutePlanRepositoryException(string message, Exception? innerException = null)
        : base(message, innerException)
    {
    }
}

public interface IRoutePlanRepository
{
    ValueTask<ImmutableArray<RoutePlanSummary>> ListAsync(CancellationToken cancellationToken = default);

    ValueTask<RoutePlan> OpenAsync(RoutePlanId id, CancellationToken cancellationToken = default);

    ValueTask SaveAsync(RoutePlan plan, CancellationToken cancellationToken = default);

    ValueTask<RoutePlan> SaveAsAsync(
        RoutePlan plan,
        string name,
        CancellationToken cancellationToken = default);

    ValueTask DeleteAsync(RoutePlanId id, CancellationToken cancellationToken = default);
}
