using System.Collections.Concurrent;
using System.Collections.Immutable;

namespace Navtool.Core.Tests;

public sealed class RoutePlanRoutingWorkflowTests
{
    private static readonly DateTimeOffset Now =
        new(2026, 8, 1, 18, 0, 0, TimeSpan.Zero);

    [Fact]
    public async Task Models_chain_independently_with_stopovers_one_cutoff_and_leg_corridors()
    {
        var bothModelsStarted = new TaskCompletionSource(
            TaskCreationOptions.RunContinuationsAsynchronously);
        var releaseFirstLegs = new TaskCompletionSource(
            TaskCreationOptions.RunContinuationsAsynchronously);
        var firstLegCalls = 0;
        async ValueTask<ForecastAcquisition> Acquire(
            ForecastRequest request,
            IProgress<ForecastProgress>? progress,
            CancellationToken cancellationToken)
        {
            if (Interlocked.Increment(ref firstLegCalls) <= 2)
            {
                if (Volatile.Read(ref firstLegCalls) == 2)
                {
                    bothModelsStarted.SetResult();
                }

                await releaseFirstLegs.Task.WaitAsync(cancellationToken);
            }

            progress?.Report(new(
                request.Provider,
                request.Model,
                ForecastProgressStage.Downloading,
                0.5));
            return Acquisition(request, ForecastAcquisitionSource.Cache);
        }

        var noaa = new RecordingProvider(ForecastModel.NoaaGfs, Acquire);
        var ecmwf = new RecordingProvider(ForecastModel.EcmwfIfs, Acquire);
        var plan = Plan(
            new RouteWaypoint("Start", new Coordinate(30, -70)),
            new RouteWaypoint("Stop", new Coordinate(35, -60), TimeSpan.FromHours(2)),
            new RouteWaypoint("Finish", new Coordinate(40, -50)));
        var departure = Now.AddHours(1);
        var cutoff = departure.AddDays(10);
        var engine = new DelegateRouteEngine((request, forecast, _) =>
        {
            var isFirstLeg = request.Origin == plan.Waypoints[0].Coordinate;
            var duration = isFirstLeg
                ? forecast.Request.Model == ForecastModel.NoaaGfs
                    ? TimeSpan.FromDays(6) + TimeSpan.FromMilliseconds(900)
                    : TimeSpan.FromDays(3) + TimeSpan.FromMilliseconds(400)
                : TimeSpan.FromHours(4);
            return ValueTask.FromResult(Route(request, forecast.Request.Model, duration));
        });
        var repository = new RecordingRepository();
        var workflow = new RoutePlanRoutingWorkflow(
            new RoutingWorkflow([noaa, ecmwf], engine),
            repository,
            new FixedTimeProvider(Now));
        var reports = new ConcurrentQueue<RoutePlanRoutingProgress>();
        var request = new RoutePlanRoutingRequest(
            plan,
            departure,
            cutoff,
            [ForecastSelection.OfficialDownload(ForecastModel.NoaaGfs),
             ForecastSelection.OfficialDownload(ForecastModel.EcmwfIfs)]);

        var execution = workflow.ExecuteAsync(
            request,
            new InlineProgress<RoutePlanRoutingProgress>(reports.Enqueue));
        await bothModelsStarted.Task.WaitAsync(TimeSpan.FromSeconds(2));
        releaseFirstLegs.SetResult();
        var result = await execution;

        Assert.Equal(RoutePlanRoutingStatus.Succeeded, result.Status);
        Assert.All(result.Models, model => Assert.Equal(RoutePlanModelStatus.Succeeded, model.Status));
        Assert.Equal(2, noaa.Requests.Count);
        Assert.Equal(2, ecmwf.Requests.Count);
        Assert.All(noaa.Requests.Concat(ecmwf.Requests), item =>
            Assert.Equal(cutoff, item.Through));
        Assert.Equal(
            departure.AddDays(6).AddHours(2),
            noaa.Requests[1].From);
        Assert.True(noaa.Requests[1].From > Now.AddDays(5));
        Assert.Equal(
            ForecastCorridor.Create(plan.Waypoints[0].Coordinate, plan.Waypoints[1].Coordinate),
            noaa.Requests[0].Bounds);
        Assert.Equal(
            ForecastCorridor.Create(plan.Waypoints[1].Coordinate, plan.Waypoints[2].Coordinate),
            noaa.Requests[1].Bounds);
        Assert.True(repository.SaveCount >= 4);
        Assert.Equal(1, reports.Last().OverallFraction);
        AssertProgressAverages(reports, request.Models.Length * plan.Legs.Length);
        Assert.All(result.Models.SelectMany(model => model.Acquisitions), acquisition =>
            Assert.Equal(ForecastAcquisitionSource.Cache, acquisition.Source));
    }

    [Fact]
    public async Task Result_derived_departure_at_cutoff_marks_remaining_legs_outside_window()
    {
        var provider = new RecordingProvider(
            ForecastModel.NoaaGfs,
            (request, _, _) => ValueTask.FromResult(Acquisition(request)));
        var plan = Plan(
            new RouteWaypoint("Start", new Coordinate(30, -70)),
            new RouteWaypoint("Stop", new Coordinate(35, -60)),
            new RouteWaypoint("Finish", new Coordinate(40, -50)));
        var departure = Now.AddHours(1);
        var cutoff = departure.AddDays(2);
        var workflow = CreateWorkflow(
            provider,
            new DelegateRouteEngine((request, forecast, _) =>
                ValueTask.FromResult(Route(
                    request,
                    forecast.Request.Model,
                    cutoff - request.DepartureTime))));

        var result = await workflow.ExecuteAsync(Request(plan, departure, cutoff));

        Assert.Single(provider.Requests);
        var model = Assert.Single(result.Models);
        Assert.Equal(RoutePlanModelStatus.PartialSuccess, model.Status);
        Assert.Equal(RouteLegOutcomeState.Succeeded, model.Legs[0].State);
        Assert.Equal(RouteLegOutcomeState.OutsideForecastWindow, model.Legs[1].State);
        Assert.Equal(RouteLegOutcomeReason.OutsideForecastWindow, model.Legs[1].Reason);
    }

    [Fact]
    public async Task Forecast_exhaustion_accepts_partial_route_and_never_schedules_later_leg()
    {
        var provider = new RecordingProvider(
            ForecastModel.NoaaGfs,
            (request, _, _) => ValueTask.FromResult(Acquisition(request)));
        var plan = ThreeLegPlan();
        var repository = new RecordingRepository();
        var workflow = new RoutePlanRoutingWorkflow(
            new RoutingWorkflow(
                [provider],
                new DelegateRouteEngine((request, forecast, _) =>
                    ValueTask.FromResult(Route(
                        request,
                        forecast.Request.Model,
                        TimeSpan.FromHours(4),
                        RouteCompletion.ForecastExhausted)))),
            repository,
            new FixedTimeProvider(Now));

        var result = await workflow.ExecuteAsync(
            Request(plan, Now.AddHours(1), Now.AddDays(8)));

        Assert.Single(provider.Requests);
        var model = Assert.Single(result.Models);
        Assert.Equal(RoutePlanModelStatus.ForecastLimited, model.Status);
        Assert.Equal(RouteLegOutcomeReason.ForecastExhausted, model.Legs[0].Reason);
        Assert.All(model.Legs.Skip(1), leg =>
        {
            Assert.Equal(RouteLegOutcomeState.Blocked, leg.State);
            Assert.Equal(RouteLegOutcomeReason.BlockedByPriorFailure, leg.Reason);
        });
        Assert.Equal(
            [false, false, true],
            repository.SavedPlans.Select(saved =>
                saved.LatestResult(ForecastModel.NoaaGfs)!.Session.CompletedAt is not null));
    }

    [Fact]
    public async Task Failure_blocks_only_that_model_and_other_model_completes()
    {
        var noaa = new RecordingProvider(
            ForecastModel.NoaaGfs,
            (request, _, _) => ValueTask.FromResult(Acquisition(request)));
        var ecmwf = new RecordingProvider(
            ForecastModel.EcmwfIfs,
            (request, _, _) => ValueTask.FromResult(Acquisition(request)));
        var plan = ThreeLegPlan();
        var workflow = new RoutePlanRoutingWorkflow(
            new RoutingWorkflow(
                [noaa, ecmwf],
                new DelegateRouteEngine((request, forecast, _) =>
                    forecast.Request.Model == ForecastModel.NoaaGfs
                        ? ValueTask.FromException<RouteResult>(
                            new InvalidOperationException("NOAA search failed"))
                        : ValueTask.FromResult(Route(
                            request,
                            forecast.Request.Model,
                            TimeSpan.FromHours(2))))),
            new RecordingRepository(),
            new FixedTimeProvider(Now));

        var result = await workflow.ExecuteAsync(new RoutePlanRoutingRequest(
            plan,
            Now.AddHours(1),
            Now.AddDays(8),
            [ForecastSelection.OfficialDownload(ForecastModel.NoaaGfs),
             ForecastSelection.OfficialDownload(ForecastModel.EcmwfIfs)]));

        Assert.Single(noaa.Requests);
        Assert.Equal(3, ecmwf.Requests.Count);
        var failed = result.Models.Single(model => model.Model == ForecastModel.NoaaGfs);
        Assert.Equal(RoutePlanModelStatus.Failed, failed.Status);
        Assert.Equal(RouteLegOutcomeState.Failed, failed.Legs[0].State);
        Assert.All(failed.Legs.Skip(1), leg =>
            Assert.Equal(RouteLegOutcomeState.Blocked, leg.State));
        Assert.Equal(
            RoutePlanModelStatus.Succeeded,
            result.Models.Single(model => model.Model == ForecastModel.EcmwfIfs).Status);
        Assert.Equal(RoutePlanRoutingStatus.PartialSuccess, result.Status);
    }

    [Fact]
    public async Task Mid_run_cancellation_persists_success_and_marks_unfinished_not_calculated()
    {
        var secondLegStarted = new TaskCompletionSource(
            TaskCreationOptions.RunContinuationsAsynchronously);
        var provider = new RecordingProvider(
            ForecastModel.NoaaGfs,
            (request, _, _) => ValueTask.FromResult(Acquisition(request)));
        var plan = ThreeLegPlan();
        var engineCalls = 0;
        var repository = new RecordingRepository();
        var workflow = new RoutePlanRoutingWorkflow(
            new RoutingWorkflow(
                [provider],
                new DelegateRouteEngine(async (request, forecast, cancellationToken) =>
                {
                    if (Interlocked.Increment(ref engineCalls) == 2)
                    {
                        secondLegStarted.SetResult();
                        await Task.Delay(Timeout.InfiniteTimeSpan, cancellationToken);
                    }

                    return Route(request, forecast.Request.Model, TimeSpan.FromHours(2));
                })),
            repository,
            new FixedTimeProvider(Now));
        using var cancellation = new CancellationTokenSource();

        var execution = workflow.ExecuteAsync(
            Request(plan, Now.AddHours(1), Now.AddDays(8)),
            cancellationToken: cancellation.Token);
        await secondLegStarted.Task.WaitAsync(TimeSpan.FromSeconds(2));
        cancellation.Cancel();
        var result = await execution;

        Assert.Equal(RoutePlanRoutingStatus.Cancelled, result.Status);
        var legs = Assert.Single(result.Models).Legs;
        Assert.Equal(RouteLegOutcomeState.Succeeded, legs[0].State);
        Assert.All(legs.Skip(1), leg =>
        {
            Assert.Equal(RouteLegOutcomeState.Cancelled, leg.State);
            Assert.Equal(RouteLegOutcomeReason.CalculationCancelled, leg.Reason);
            Assert.Null(leg.Route);
        });
        var persisted = await repository.OpenAsync(plan.Id);
        Assert.Equal(legs, persisted.LatestResult(ForecastModel.NoaaGfs)!.Legs);
        Assert.NotNull(persisted.LatestResult(ForecastModel.NoaaGfs)!.Session.CompletedAt);
    }

    [Fact]
    public async Task Superseded_generation_cannot_publish_after_newer_result()
    {
        var firstStarted = new TaskCompletionSource(
            TaskCreationOptions.RunContinuationsAsynchronously);
        var releaseFirst = new TaskCompletionSource<ForecastAcquisition>(
            TaskCreationOptions.RunContinuationsAsynchronously);
        var calls = 0;
        var provider = new RecordingProvider(
            ForecastModel.NoaaGfs,
            async (request, _, _) =>
            {
                if (Interlocked.Increment(ref calls) == 1)
                {
                    firstStarted.SetResult();
                    return await releaseFirst.Task;
                }

                return Acquisition(request);
            });
        var plan = Plan(
            new RouteWaypoint("Start", new Coordinate(30, -70)),
            new RouteWaypoint("Finish", new Coordinate(40, -50)));
        var repository = new RecordingRepository();
        var workflow = new RoutePlanRoutingWorkflow(
            new RoutingWorkflow(
                [provider],
                new DelegateRouteEngine((request, forecast, _) =>
                    ValueTask.FromResult(Route(
                        request,
                        forecast.Request.Model,
                        TimeSpan.FromHours(2))))),
            repository,
            new FixedTimeProvider(Now));
        var request = Request(plan, Now.AddHours(1), Now.AddDays(8));

        var staleExecution = workflow.ExecuteAsync(request);
        await firstStarted.Task.WaitAsync(TimeSpan.FromSeconds(2));
        var current = await workflow.ExecuteAsync(request);
        releaseFirst.SetResult(Acquisition(provider.Requests[0]));
        var stale = await staleExecution;

        Assert.True(current.IsCurrent);
        Assert.False(stale.IsCurrent);
        var persisted = await repository.OpenAsync(plan.Id);
        Assert.Equal(
            current.Plan.LatestResult(ForecastModel.NoaaGfs)!.Session.Id,
            persisted.LatestResult(ForecastModel.NoaaGfs)!.Session.Id);
    }

    [Fact]
    public async Task Resume_routes_only_active_and_later_legs_from_current_position()
    {
        var provider = new RecordingProvider(
            ForecastModel.NoaaGfs,
            (request, _, _) => ValueTask.FromResult(Acquisition(request)));
        var plan = ThreeLegPlan();
        var sailedResult = SuccessfulResult(plan, ForecastModel.NoaaGfs);
        plan = plan.WithResult(sailedResult).MarkSailed(plan.Legs[0].Id);
        var currentPosition = new Coordinate(31.5, -66.5);
        plan = plan.SetCurrentPosition(currentPosition, Now.AddHours(2));
        var workflow = CreateWorkflow(
            provider,
            new DelegateRouteEngine((request, forecast, _) =>
                ValueTask.FromResult(Route(request, forecast.Request.Model, TimeSpan.FromHours(2)))));

        var result = await workflow.ExecuteAsync(
            Request(plan, plan.CurrentPosition!.DepartureTime, Now.AddDays(8)));

        var model = Assert.Single(result.Models);
        // Leg 0 (sailed) is carried forward untouched; only legs 1 and 2 are recalculated.
        Assert.Equal(2, provider.Requests.Count);
        Assert.Equal(RouteLegOutcomeState.Succeeded, model.Legs[0].State);
        Assert.Same(sailedResult.Legs[0].Route, model.Legs[0].Route);
        Assert.Equal(RouteLegOutcomeState.Succeeded, model.Legs[1].State);
        Assert.Equal(currentPosition, model.Legs[1].Route!.Request.Origin);
        Assert.Equal(RouteLegOutcomeState.Succeeded, model.Legs[2].State);
        Assert.Equal(plan.Waypoints[2].Coordinate, model.Legs[2].Route!.Request.Origin);
    }

    [Fact]
    public async Task Explicit_active_leg_skips_earlier_unsailed_leg_carrying_its_history_forward()
    {
        var provider = new RecordingProvider(
            ForecastModel.NoaaGfs,
            (request, _, _) => ValueTask.FromResult(Acquisition(request)));
        var plan = ThreeLegPlan();
        var existingResult = SuccessfulResult(plan, ForecastModel.NoaaGfs);
        plan = plan.WithResult(existingResult).SetActiveLeg(plan.Legs[1].Id);
        var workflow = CreateWorkflow(
            provider,
            new DelegateRouteEngine((request, forecast, _) =>
                ValueTask.FromResult(Route(request, forecast.Request.Model, TimeSpan.FromHours(2)))));

        var result = await workflow.ExecuteAsync(
            Request(plan, Now.AddHours(1), Now.AddDays(8)));

        var model = Assert.Single(result.Models);
        Assert.Equal(2, provider.Requests.Count);
        // Leg 0 was explicitly skipped (not sailed) but its prior successful, waypoint-anchored
        // result is carried forward rather than recalculated.
        Assert.Equal(RouteLegOutcomeState.Succeeded, model.Legs[0].State);
        Assert.Same(existingResult.Legs[0].Route, model.Legs[0].Route);
        Assert.Equal(RouteLegOutcomeState.Succeeded, model.Legs[1].State);
        Assert.Equal(RouteLegOutcomeState.Succeeded, model.Legs[2].State);
    }

    [Fact]
    public async Task New_model_records_legs_before_active_leg_as_not_calculated()
    {
        var provider = new RecordingProvider(
            ForecastModel.NoaaGfs,
            (request, _, _) => ValueTask.FromResult(Acquisition(request)));
        var plan = ThreeLegPlan();
        plan = plan.MarkSailed(plan.Legs[0].Id);
        var workflow = CreateWorkflow(
            provider,
            new DelegateRouteEngine((request, forecast, _) =>
                ValueTask.FromResult(Route(request, forecast.Request.Model, TimeSpan.FromHours(2)))));

        var result = await workflow.ExecuteAsync(
            Request(plan, Now.AddHours(1), Now.AddDays(8)));

        var model = Assert.Single(result.Models);
        Assert.Equal(RouteLegOutcomeState.NotCalculated, model.Legs[0].State);
        Assert.Equal(RouteLegOutcomeReason.BeforeActiveLeg, model.Legs[0].Reason);
        Assert.Equal(RouteLegOutcomeState.Succeeded, model.Legs[1].State);
        Assert.Equal(RouteLegOutcomeState.Succeeded, model.Legs[2].State);
    }

    [Fact]
    public void Building_initial_legs_invalidates_a_carried_leg_whose_stale_current_position_origin_no_longer_applies()
    {
        var plan = ThreeLegPlan();
        var currentPosition = new Coordinate(31.5, -66.5);
        var positioned = plan.SetCurrentPosition(currentPosition, Now.AddHours(1));
        var request = new RouteRequest(
            "leg-0-from-current-position",
            currentPosition,
            plan.Waypoints[1].Coordinate,
            Now.AddHours(1),
            Now.AddDays(8));
        var route = Route(request, ForecastModel.NoaaGfs, TimeSpan.FromHours(2));
        var session = new RouteCalculationSession(plan.Id, ForecastModel.NoaaGfs, Now).Complete(Now.AddMinutes(1));
        var accepted = positioned.WithResult(new RoutePlanResult(session,
        [
            new RouteLegResult(plan.Legs[0].Id, RouteLegOutcomeState.Succeeded,
                RouteLegOutcomeReason.CalculationSucceeded, route),
            new RouteLegResult(plan.Legs[1].Id, RouteLegOutcomeState.Pending, RouteLegOutcomeReason.None),
            new RouteLegResult(plan.Legs[2].Id, RouteLegOutcomeState.Pending, RouteLegOutcomeReason.None)
        ]));

        // Skip ahead to leg 1 as the active leg without marking leg 0 sailed: leg 0's carried
        // result used the current-position origin, which no longer applies once leg 0 is not the
        // active leg, so RoutePlanRoutingWorkflow's BuildInitialLegs must invalidate it rather
        // than carry it through (avoiding a validation failure when the new result is saved).
        var skippedAhead = accepted.SetActiveLeg(plan.Legs[1].Id);
        var buildInitialLegs = typeof(RoutePlanRoutingWorkflow).GetMethod(
            "BuildInitialLegs",
            System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Static)!;
        var routingRequest = Request(skippedAhead, Now.AddHours(2), Now.AddDays(8));

        var initialLegs = (RouteLegResult[])buildInitialLegs.Invoke(
            null, [routingRequest, ForecastModel.NoaaGfs])!;

        Assert.Equal(RouteLegOutcomeState.Invalidated, initialLegs[0].State);
        Assert.Equal(RouteLegOutcomeReason.CurrentPositionChanged, initialLegs[0].Reason);
        Assert.Null(initialLegs[0].Route);
    }

    private static RoutePlanResult SuccessfulResult(RoutePlan plan, ForecastModel model)
    {
        var session = new RouteCalculationSession(plan.Id, model, Now).Complete(Now.AddMinutes(1));
        var outcomes = plan.Legs.Select(leg =>
        {
            var from = plan.Waypoints[leg.Index];
            var to = plan.Waypoints[leg.Index + 1];
            var request = new RouteRequest(
                $"existing-{leg.Index}",
                from.Coordinate,
                to.Coordinate,
                Now,
                Now.AddDays(8));
            return new RouteLegResult(
                leg.Id,
                RouteLegOutcomeState.Succeeded,
                RouteLegOutcomeReason.CalculationSucceeded,
                Route(request, model, TimeSpan.FromHours(2)));
        });
        return new RoutePlanResult(session, outcomes);
    }

    private static RoutePlanRoutingWorkflow CreateWorkflow(
        IForecastProvider provider,
        IRouteEngine engine) =>
        new(
            new RoutingWorkflow([provider], engine),
            new RecordingRepository(),
            new FixedTimeProvider(Now));

    private static RoutePlanRoutingRequest Request(
        RoutePlan plan,
        DateTimeOffset departure,
        DateTimeOffset cutoff) =>
        new(
            plan,
            departure,
            cutoff,
            [ForecastSelection.OfficialDownload(ForecastModel.NoaaGfs)]);

    private static RoutePlan Plan(params RouteWaypoint[] waypoints) =>
        new("Passage", waypoints);

    private static RoutePlan ThreeLegPlan() =>
        Plan(
            new RouteWaypoint("Start", new Coordinate(30, -70)),
            new RouteWaypoint("One", new Coordinate(33, -63), TimeSpan.FromHours(1)),
            new RouteWaypoint("Two", new Coordinate(36, -57), TimeSpan.FromHours(1)),
            new RouteWaypoint("Finish", new Coordinate(40, -50)));

    private static ForecastAcquisition Acquisition(
        ForecastRequest request,
        ForecastAcquisitionSource source = ForecastAcquisitionSource.Remote) =>
        new(
            request,
            new ForecastRun(request.Provider, request.Model, request.From.AddHours(-6)),
            new LocalGribArtifact(Path.GetFullPath($"{request.Model}.grib2")),
            source,
            source == ForecastAcquisitionSource.Cache
                ? new CacheMetadata("compatible-parts", Now, Now.AddHours(6))
                : null);

    private static RouteResult Route(
        RouteRequest request,
        ForecastModel model,
        TimeSpan duration,
        RouteCompletion completion = RouteCompletion.DestinationReached)
    {
        var destination = completion == RouteCompletion.DestinationReached
            ? request.Destination
            : new Coordinate(
                (request.Origin.Latitude + request.Destination.Latitude) / 2,
                (request.Origin.Longitude + request.Destination.Longitude) / 2);
        return new RouteResult(
            request,
            model,
            [
                new RoutePoint(request.Origin, request.DepartureTime, 90, 6, 15, 180, 0),
                new RoutePoint(destination, request.DepartureTime + duration, 90, 6, 15, 180, 50)
            ],
            new RouteDiagnostics(1, 2, 1, 1),
            completion);
    }

    private static void AssertProgressAverages(
        IEnumerable<RoutePlanRoutingProgress> reports,
        int unitCount)
    {
        var fractions = new Dictionary<(ForecastModel, int), double>();
        foreach (var report in reports)
        {
            fractions[(report.Model, report.LegIndex)] = report.UnitFraction;
            Assert.Equal(fractions.Values.Sum() / unitCount, report.OverallFraction, 10);
        }
    }

    private sealed class RecordingProvider(
        ForecastModel model,
        Func<
            ForecastRequest,
            IProgress<ForecastProgress>?,
            CancellationToken,
            ValueTask<ForecastAcquisition>> acquire) : IForecastProvider
    {
        public ForecastProvider Provider => model.Provider();

        public ForecastModel Model => model;

        public List<ForecastRequest> Requests { get; } = [];

        public ValueTask<ForecastAcquisition> AcquireAsync(
            ForecastRequest request,
            IProgress<ForecastProgress>? progress,
            CancellationToken cancellationToken)
        {
            lock (Requests)
            {
                Requests.Add(request);
            }

            return acquire(request, progress, cancellationToken);
        }
    }

    private sealed class DelegateRouteEngine(
        Func<
            RouteRequest,
            ForecastAcquisition,
            CancellationToken,
            ValueTask<RouteResult>> calculate) : IRouteEngine
    {
        public ValueTask<RouteResult> CalculateAsync(
            RouteRequest request,
            ForecastAcquisition forecast,
            IProgress<RouteCalculationProgress>? progress,
            CancellationToken cancellationToken) =>
            calculate(request, forecast, cancellationToken);
    }

    private sealed class RecordingRepository : IRoutePlanRepository
    {
        private readonly object _gate = new();
        private RoutePlan? _plan;

        public int SaveCount { get; private set; }

        public List<RoutePlan> SavedPlans { get; } = [];

        public ValueTask<ImmutableArray<RoutePlanSummary>> ListAsync(
            CancellationToken cancellationToken = default) =>
            ValueTask.FromResult(ImmutableArray<RoutePlanSummary>.Empty);

        public ValueTask<RoutePlan> OpenAsync(
            RoutePlanId id,
            CancellationToken cancellationToken = default)
        {
            lock (_gate)
            {
                return ValueTask.FromResult(
                    _plan is not null && _plan.Id == id
                        ? _plan
                        : throw new KeyNotFoundException());
            }
        }

        public ValueTask SaveAsync(
            RoutePlan plan,
            CancellationToken cancellationToken = default)
        {
            lock (_gate)
            {
                _plan = plan;
                SaveCount++;
                SavedPlans.Add(plan);
            }

            return ValueTask.CompletedTask;
        }

        public ValueTask<RoutePlan> SaveAsAsync(
            RoutePlan plan,
            string name,
            CancellationToken cancellationToken = default) =>
            throw new NotSupportedException();

        public ValueTask DeleteAsync(
            RoutePlanId id,
            CancellationToken cancellationToken = default) =>
            throw new NotSupportedException();
    }

    private sealed class FixedTimeProvider(DateTimeOffset now) : TimeProvider
    {
        public override DateTimeOffset GetUtcNow() => now;
    }

    private sealed class InlineProgress<T>(Action<T> report) : IProgress<T>
    {
        public void Report(T value) => report(value);
    }
}
