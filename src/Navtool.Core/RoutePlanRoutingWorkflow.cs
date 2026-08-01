using System.Collections.Immutable;

namespace Navtool.Core;

public sealed record RoutePlanRoutingRequest
{
    public static readonly TimeSpan MaximumForecastWindow = TimeSpan.FromDays(10);

    public RoutePlanRoutingRequest(
        RoutePlan plan,
        DateTimeOffset departureTime,
        DateTimeOffset forecastCutoff,
        IEnumerable<ForecastSelection> selections)
    {
        ArgumentNullException.ThrowIfNull(plan);
        ArgumentNullException.ThrowIfNull(selections);
        var immutableSelections = selections.ToImmutableArray();
        if (immutableSelections.Length is < 1 or > 2 ||
            immutableSelections.Select(selection => selection.Model).Distinct().Count() !=
            immutableSelections.Length)
        {
            throw new ArgumentException(
                "Select one or two distinct forecast models.",
                nameof(selections));
        }

        var departureUtc = departureTime.ToUniversalTime();
        var cutoffUtc = forecastCutoff.ToUniversalTime();
        if (cutoffUtc <= departureUtc)
        {
            throw new ArgumentException(
                "The forecast cutoff must be after the departure.",
                nameof(forecastCutoff));
        }

        if (cutoffUtc - departureUtc > MaximumForecastWindow)
        {
            throw new ArgumentOutOfRangeException(
                nameof(forecastCutoff),
                "The forecast window cannot exceed ten days.");
        }

        Plan = plan;
        DepartureTime = departureUtc;
        ForecastCutoff = cutoffUtc;
        Selections = immutableSelections;
        Models = immutableSelections.Select(selection => selection.Model).ToImmutableArray();
        StartLegIndex = plan.ActiveLegIndex;
        StartOrigin = plan.CurrentPosition?.Coordinate ??
            (StartLegIndex < plan.Waypoints.Length
                ? plan.Waypoints[StartLegIndex].Coordinate
                : plan.Waypoints[^1].Coordinate);
    }

    public RoutePlan Plan { get; }

    public DateTimeOffset DepartureTime { get; }

    public DateTimeOffset ForecastCutoff { get; }

    public ImmutableArray<ForecastSelection> Selections { get; }

    public ImmutableArray<ForecastModel> Models { get; }

    /// <summary>
    /// The index of the leg routing should resume from: <see cref="RoutePlan.ActiveLegIndex"/> at
    /// the time the request was built. Legs before this index are carried forward unchanged
    /// (sailed history, or explicitly skipped legs) rather than recalculated.
    /// </summary>
    public int StartLegIndex { get; }

    /// <summary>
    /// The origin coordinate for <see cref="StartLegIndex"/>: the plan's user-placed current
    /// position when set, otherwise that leg's own start waypoint. Never a synthetic/permanent
    /// waypoint.
    /// </summary>
    public Coordinate StartOrigin { get; }
}

public enum RoutePlanRoutingUnitStatus
{
    AcquiringForecast,
    CalculatingRoute,
    Succeeded,
    ForecastLimited,
    Failed,
    Cancelled,
    Blocked,
    OutsideForecastWindow
}

public sealed record RoutePlanRoutingProgress(
    ForecastProvider Provider,
    ForecastModel Model,
    int LegIndex,
    RouteLegId LegId,
    RoutePlanRoutingUnitStatus Status,
    double UnitFraction,
    double OverallFraction,
    string? Message = null,
    RouteCalculationSnapshot? Snapshot = null);

public enum RoutePlanModelStatus
{
    Succeeded,
    PartialSuccess,
    ForecastLimited,
    Failed,
    Cancelled,
    OutsideForecastWindow
}

public sealed record RoutePlanModelOutcome(
    ForecastModel Model,
    RoutePlanModelStatus Status,
    ImmutableArray<RouteLegResult> Legs,
    ImmutableArray<ForecastAcquisition> Acquisitions);

public enum RoutePlanRoutingStatus
{
    Succeeded,
    PartialSuccess,
    Failed,
    Cancelled
}

public sealed record RoutePlanRoutingResult(
    RoutePlanRoutingRequest Request,
    RoutePlan Plan,
    ImmutableArray<RoutePlanModelOutcome> Models,
    RoutePlanRoutingStatus Status,
    bool IsCurrent);

public sealed class RoutePlanRoutingWorkflow
{
    private readonly RoutingWorkflow _singleLegWorkflow;
    private readonly IRoutePlanRepository _repository;
    private readonly TimeProvider _timeProvider;
    private readonly SemaphoreSlim _publicationGate = new(1, 1);
    private readonly Dictionary<RoutePlanId, Guid> _activeOperations = [];

    public RoutePlanRoutingWorkflow(
        RoutingWorkflow singleLegWorkflow,
        IRoutePlanRepository repository,
        TimeProvider? timeProvider = null)
    {
        ArgumentNullException.ThrowIfNull(singleLegWorkflow);
        ArgumentNullException.ThrowIfNull(repository);
        _singleLegWorkflow = singleLegWorkflow;
        _repository = repository;
        _timeProvider = timeProvider ?? TimeProvider.System;
    }

    public async Task<RoutePlanRoutingResult> ExecuteAsync(
        RoutePlanRoutingRequest request,
        IProgress<RoutePlanRoutingProgress>? progress = null,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(request);
        var operationId = Guid.NewGuid();
        var currentPlan = request.Plan;
        await _publicationGate.WaitAsync(CancellationToken.None).ConfigureAwait(false);
        try
        {
            _activeOperations[request.Plan.Id] = operationId;
        }
        finally
        {
            _publicationGate.Release();
        }

        var progressState = new ProgressState(request, progress);
        var modelStates = request.Selections.ToDictionary(
            selection => selection.Model,
            selection => new ModelExecutionState(
                selection,
                new RouteCalculationSession(
                    request.Plan.Id,
                    selection.Model,
                    _timeProvider.GetUtcNow()),
                BuildInitialLegs(request, selection.Model)));

        async Task<bool> PublishAsync(ModelExecutionState modelState, bool completeSession)
        {
            await _publicationGate.WaitAsync(CancellationToken.None).ConfigureAwait(false);
            try
            {
                if (!_activeOperations.TryGetValue(request.Plan.Id, out var currentOperation) ||
                    currentOperation != operationId)
                {
                    return false;
                }

                var session = completeSession
                    ? modelState.Session.Complete(_timeProvider.GetUtcNow())
                    : modelState.Session;
                var updatedPlan = currentPlan.WithResult(
                    new RoutePlanResult(session, modelState.Legs));
                await _repository.SaveAsync(updatedPlan, CancellationToken.None).ConfigureAwait(false);
                currentPlan = updatedPlan;
                return true;
            }
            finally
            {
                _publicationGate.Release();
            }
        }

        async Task RunModelAsync(ModelExecutionState modelState)
        {
            var departure = request.DepartureTime;
            try
            {
                for (var legIndex = request.StartLegIndex; legIndex < request.Plan.Legs.Length; legIndex++)
                {
                    cancellationToken.ThrowIfCancellationRequested();
                    if (departure >= request.ForecastCutoff)
                    {
                        await MarkRemainingAsync(
                            modelState,
                            legIndex,
                            RouteLegOutcomeState.OutsideForecastWindow,
                            RouteLegOutcomeReason.OutsideForecastWindow,
                            RoutePlanRoutingUnitStatus.OutsideForecastWindow,
                            "Departure is at or after the forecast cutoff.",
                            PublishAsync,
                            progressState).ConfigureAwait(false);
                        return;
                    }

                    var leg = request.Plan.Legs[legIndex];
                    var origin = legIndex == request.StartLegIndex
                        ? request.StartOrigin
                        : request.Plan.Waypoints[legIndex].Coordinate;
                    var to = request.Plan.Waypoints[legIndex + 1];
                    var route = new RouteRequest(
                        $"{request.Plan.Id}-leg-{legIndex}-{modelState.Session.Id}",
                        origin,
                        to.Coordinate,
                        departure,
                        request.ForecastCutoff);
                    var workflowRequest = new RoutingWorkflowRequest(
                        route,
                        [modelState.Selection],
                        ForecastCorridor.Create(route.Origin, route.Destination));
                    var legProgress = new InlineProgress<RoutingProgress>(value =>
                        progressState.Report(
                            value.Model,
                            legIndex,
                            value.Stage switch
                            {
                                RoutingProgressStage.AcquiringForecast =>
                                    RoutePlanRoutingUnitStatus.AcquiringForecast,
                                RoutingProgressStage.CalculatingRoute =>
                                    RoutePlanRoutingUnitStatus.CalculatingRoute,
                                RoutingProgressStage.Completed =>
                                    RoutePlanRoutingUnitStatus.Succeeded,
                                _ => RoutePlanRoutingUnitStatus.Failed
                            },
                            value.Fraction,
                            value.Message,
                            value.Snapshot));
                    var workflowResult = await _singleLegWorkflow.ExecuteAsync(
                        workflowRequest,
                        legProgress,
                        cancellationToken).ConfigureAwait(false);
                    cancellationToken.ThrowIfCancellationRequested();
                    var outcome = workflowResult.Outcomes[0];
                    if (outcome.Acquisition is not null)
                    {
                        modelState.Acquisitions.Add(outcome.Acquisition);
                    }

                    if (outcome.Route is { } acceptedRoute)
                    {
                        var limited = acceptedRoute.IsForecastLimited;
                        modelState.Legs[legIndex] = new RouteLegResult(
                            leg.Id,
                            RouteLegOutcomeState.Succeeded,
                            limited
                                ? RouteLegOutcomeReason.ForecastExhausted
                                : RouteLegOutcomeReason.CalculationSucceeded,
                            acceptedRoute);
                        if (!await PublishAsync(
                                modelState,
                                completeSession: limited || legIndex == request.Plan.Legs.Length - 1)
                            .ConfigureAwait(false))
                        {
                            return;
                        }

                        progressState.Report(
                            modelState.Selection.Model,
                            legIndex,
                            limited
                                ? RoutePlanRoutingUnitStatus.ForecastLimited
                                : RoutePlanRoutingUnitStatus.Succeeded,
                            1,
                            limited ? "Forecast coverage ended before the destination." : null);
                        if (limited)
                        {
                            await MarkRemainingAsync(
                                modelState,
                                legIndex + 1,
                                RouteLegOutcomeState.Blocked,
                                RouteLegOutcomeReason.BlockedByPriorFailure,
                                RoutePlanRoutingUnitStatus.Blocked,
                                "Blocked because the prior leg exhausted forecast coverage.",
                                PublishAsync,
                                progressState).ConfigureAwait(false);
                            return;
                        }

                        departure = acceptedRoute.ArrivalTime + (to.Stopover ?? TimeSpan.Zero);
                        continue;
                    }

                    var failure = outcome.Failure!;
                    modelState.Legs[legIndex] = new RouteLegResult(
                        leg.Id,
                        RouteLegOutcomeState.Failed,
                        FailureReason(failure.Stage),
                        detail: failure.Message);
                    if (!await PublishAsync(
                            modelState,
                            completeSession: legIndex == request.Plan.Legs.Length - 1)
                        .ConfigureAwait(false))
                    {
                        return;
                    }

                    progressState.Report(
                        modelState.Selection.Model,
                        legIndex,
                        RoutePlanRoutingUnitStatus.Failed,
                        1,
                        failure.Message);
                    await MarkRemainingAsync(
                        modelState,
                        legIndex + 1,
                        RouteLegOutcomeState.Blocked,
                        RouteLegOutcomeReason.BlockedByPriorFailure,
                        RoutePlanRoutingUnitStatus.Blocked,
                        "Blocked because the prior leg failed.",
                        PublishAsync,
                        progressState).ConfigureAwait(false);
                    return;
                }
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
            {
                await MarkCancelledAsync(
                    modelState,
                    request.StartLegIndex,
                    PublishAsync,
                    progressState).ConfigureAwait(false);
            }
        }

        var tasks = modelStates.Values.Select(RunModelAsync).ToArray();
        await Task.WhenAll(tasks).ConfigureAwait(false);

        var isCurrent = false;
        await _publicationGate.WaitAsync(CancellationToken.None).ConfigureAwait(false);
        try
        {
            if (_activeOperations.TryGetValue(request.Plan.Id, out var currentOperation) &&
                currentOperation == operationId)
            {
                _activeOperations.Remove(request.Plan.Id);
                isCurrent = true;
            }
        }
        finally
        {
            _publicationGate.Release();
        }

        var outcomes = modelStates.Values
            .Select(state =>
            {
                var result = currentPlan.LatestResult(state.Selection.Model);
                var legs = result?.Legs ?? state.Legs.ToImmutableArray();
                return new RoutePlanModelOutcome(
                    state.Selection.Model,
                    DetermineModelStatus(legs),
                    legs,
                    state.Acquisitions.ToImmutableArray());
            })
            .OrderBy(outcome => Array.IndexOf(request.Models.ToArray(), outcome.Model))
            .ToImmutableArray();
        return new RoutePlanRoutingResult(
            request,
            currentPlan,
            outcomes,
            DetermineOverallStatus(outcomes),
            isCurrent);
    }

    private static async Task MarkRemainingAsync(
        ModelExecutionState modelState,
        int firstLegIndex,
        RouteLegOutcomeState state,
        RouteLegOutcomeReason reason,
        RoutePlanRoutingUnitStatus status,
        string detail,
        Func<ModelExecutionState, bool, Task<bool>> publish,
        ProgressState progress)
    {
        for (var index = firstLegIndex; index < modelState.Legs.Length; index++)
        {
            modelState.Legs[index] = new RouteLegResult(
                modelState.Legs[index].LegId,
                state,
                reason,
                detail: detail);
            if (!await publish(modelState, index == modelState.Legs.Length - 1).ConfigureAwait(false))
            {
                return;
            }

            progress.Report(modelState.Selection.Model, index, status, 1, detail);
        }
    }

    private static async Task MarkCancelledAsync(
        ModelExecutionState modelState,
        int firstLegIndex,
        Func<ModelExecutionState, bool, Task<bool>> publish,
        ProgressState progress)
    {
        var pending = Enumerable.Range(firstLegIndex, modelState.Legs.Length - firstLegIndex)
            .Where(index => modelState.Legs[index].State == RouteLegOutcomeState.Pending)
            .ToArray();
        for (var pendingIndex = 0; pendingIndex < pending.Length; pendingIndex++)
        {
            var legIndex = pending[pendingIndex];
            modelState.Legs[legIndex] = new RouteLegResult(
                modelState.Legs[legIndex].LegId,
                RouteLegOutcomeState.Cancelled,
                RouteLegOutcomeReason.CalculationCancelled,
                detail: "Not calculated because the calculation was cancelled.");
            if (!await publish(modelState, pendingIndex == pending.Length - 1).ConfigureAwait(false))
            {
                return;
            }

            progress.Report(
                modelState.Selection.Model,
                legIndex,
                RoutePlanRoutingUnitStatus.Cancelled,
                1,
                "Calculation cancelled.");
        }
    }

    /// <summary>
    /// Seeds the per-model leg outcomes before a routing pass: legs before
    /// <see cref="RoutePlanRoutingRequest.StartLegIndex"/> are carried forward unchanged from the
    /// plan's latest result for this model (sailed history, or legs explicitly skipped by an
    /// active-leg selection) rather than recalculated. Legs from that index forward start Pending.
    /// A carried, unsailed leg whose accepted route used a current-position origin that no longer
    /// applies (because a later leg is now active) is invalidated rather than carried as-is.
    /// </summary>
    private static RouteLegResult[] BuildInitialLegs(RoutePlanRoutingRequest request, ForecastModel model)
    {
        var plan = request.Plan;
        var existingByLeg = plan.LatestResult(model)?.Legs.ToDictionary(leg => leg.LegId);
        return plan.Legs.Select(leg =>
        {
            if (leg.Index >= request.StartLegIndex)
            {
                return new RouteLegResult(leg.Id, RouteLegOutcomeState.Pending, RouteLegOutcomeReason.None);
            }

            if (existingByLeg is null ||
                !existingByLeg.TryGetValue(leg.Id, out var carried))
            {
                return new RouteLegResult(
                    leg.Id,
                    RouteLegOutcomeState.NotCalculated,
                    RouteLegOutcomeReason.BeforeActiveLeg,
                    detail: "Not calculated because the leg is before the active leg.");
            }

            if (plan.SailedLegIds.Contains(leg.Id) || carried.Route is null)
            {
                return carried;
            }

            var from = plan.Waypoints[leg.Index];
            return carried.Route.Request.Origin.IsSameLocation(from.Coordinate)
                ? carried
                : carried.Invalidate(RouteLegOutcomeReason.CurrentPositionChanged);
        }).ToArray();
    }

    private static RouteLegOutcomeReason FailureReason(ModelRouteFailureStage stage) => stage switch
    {
        ModelRouteFailureStage.ForecastAcquisition =>
            RouteLegOutcomeReason.ForecastAcquisitionFailed,
        ModelRouteFailureStage.RouteCalculation =>
            RouteLegOutcomeReason.RouteCalculationFailed,
        _ => RouteLegOutcomeReason.ResultValidationFailed
    };

    private static RoutePlanModelStatus DetermineModelStatus(ImmutableArray<RouteLegResult> legs)
    {
        var hasAccepted = legs.Any(leg => leg.Route is not null);
        if (legs.Any(leg => leg.State == RouteLegOutcomeState.Cancelled))
        {
            return RoutePlanModelStatus.Cancelled;
        }

        if (legs.Any(leg => leg.Reason == RouteLegOutcomeReason.ForecastExhausted))
        {
            return RoutePlanModelStatus.ForecastLimited;
        }

        if (legs.Any(leg => leg.State == RouteLegOutcomeState.Failed))
        {
            return hasAccepted ? RoutePlanModelStatus.PartialSuccess : RoutePlanModelStatus.Failed;
        }

        if (legs.Any(leg => leg.State == RouteLegOutcomeState.OutsideForecastWindow))
        {
            return hasAccepted
                ? RoutePlanModelStatus.PartialSuccess
                : RoutePlanModelStatus.OutsideForecastWindow;
        }

        return RoutePlanModelStatus.Succeeded;
    }

    private static RoutePlanRoutingStatus DetermineOverallStatus(
        ImmutableArray<RoutePlanModelOutcome> outcomes)
    {
        if (outcomes.Any(outcome => outcome.Status == RoutePlanModelStatus.Cancelled))
        {
            return RoutePlanRoutingStatus.Cancelled;
        }

        if (outcomes.All(outcome => outcome.Status == RoutePlanModelStatus.Succeeded))
        {
            return RoutePlanRoutingStatus.Succeeded;
        }

        if (outcomes.Any(outcome => outcome.Legs.Any(leg => leg.Route is not null)))
        {
            return RoutePlanRoutingStatus.PartialSuccess;
        }

        return RoutePlanRoutingStatus.Failed;
    }

    private sealed class ModelExecutionState(
        ForecastSelection selection,
        RouteCalculationSession session,
        RouteLegResult[] legs)
    {
        public ForecastSelection Selection { get; } = selection;

        public RouteCalculationSession Session { get; } = session;

        public RouteLegResult[] Legs { get; } = legs;

        public List<ForecastAcquisition> Acquisitions { get; } = [];
    }

    private sealed class ProgressState
    {
        private readonly RoutePlanRoutingRequest _request;
        private readonly IProgress<RoutePlanRoutingProgress>? _progress;
        private readonly Dictionary<(ForecastModel Model, int LegIndex), double> _fractions;
        private readonly object _gate = new();

        public ProgressState(
            RoutePlanRoutingRequest request,
            IProgress<RoutePlanRoutingProgress>? progress)
        {
            _request = request;
            _progress = progress;
            _fractions = request.Models
                .SelectMany(model => Enumerable.Range(0, request.Plan.Legs.Length)
                    .Select(index => new KeyValuePair<(ForecastModel, int), double>(
                        (model, index),
                        0)))
                .ToDictionary();
        }

        public void Report(
            ForecastModel model,
            int legIndex,
            RoutePlanRoutingUnitStatus status,
            double fraction,
            string? message = null,
            RouteCalculationSnapshot? snapshot = null)
        {
            lock (_gate)
            {
                _fractions[(model, legIndex)] = fraction;
                _progress?.Report(new RoutePlanRoutingProgress(
                    model.Provider(),
                    model,
                    legIndex,
                    _request.Plan.Legs[legIndex].Id,
                    status,
                    fraction,
                    _fractions.Values.Average(),
                    message,
                    snapshot));
            }
        }
    }

    private sealed class InlineProgress<T>(Action<T> report) : IProgress<T>
    {
        public void Report(T value) => report(value);
    }
}
