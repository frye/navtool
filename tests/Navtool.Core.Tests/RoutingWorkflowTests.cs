using System.Collections.Concurrent;

namespace Navtool.Core.Tests;

public sealed class RoutingWorkflowTests
{
    [Fact]
    public async Task Workflow_runs_models_concurrently_and_keeps_success_and_failure_separate()
    {
        var entered = 0;
        var bothEntered = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var release = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        async ValueTask<ForecastAcquisition> Acquire(
            ForecastRequest request,
            IProgress<ForecastProgress>? progress,
            CancellationToken cancellationToken)
        {
            if (Interlocked.Increment(ref entered) == 2)
            {
                bothEntered.TrySetResult();
            }

            await release.Task.WaitAsync(cancellationToken);
            progress?.Report(new(
                request.Provider,
                request.Model,
                ForecastProgressStage.Completed,
                1));
            return CreateAcquisition(request);
        }

        var engine = new StubRouteEngine((request, acquisition, progress, _) =>
        {
            var frontierTime = request.DepartureTime.AddHours(1);
            var snapshot = new RouteCalculationSnapshot(
                frontierTime,
                new[]
                {
                    new RouteCalculationEnvelopeSegment(
                        new[]
                        {
                            request.Origin,
                            new Coordinate(
                                request.Origin.Latitude + 0.25,
                                request.Origin.Longitude + 0.25)
                        },
                        closed: false)
                },
                new[]
                {
                    new RouteCalculationFrontSegment(
                        new[]
                        {
                            request.Origin,
                            new Coordinate(
                                request.Origin.Latitude + 0.25,
                                request.Origin.Longitude + 0.25)
                        })
                },
                new[]
                {
                    new RoutePoint(request.Origin, request.DepartureTime, 90, 6, 15, 180, 0),
                    new RoutePoint(
                        new Coordinate(
                            request.Origin.Latitude + 0.25,
                            request.Origin.Longitude + 0.25),
                        frontierTime,
                        90,
                        6,
                        15,
                        180,
                        10)
                },
                new RouteDiagnostics(10, 20, 5, 1));
            progress?.Report(new RouteCalculationProgress(0.5, "frontier", snapshot));
            if (acquisition.Request.Model == ForecastModel.EcmwfIfs)
            {
                throw new InvalidOperationException("ECMWF route calculation failed.");
            }

            return ValueTask.FromResult(CreateRoute(request, acquisition.Request.Model));
        });
        var workflow = new RoutingWorkflow(
            new[]
            {
                new StubForecastProvider(ForecastModel.NoaaGfs, Acquire),
                new StubForecastProvider(ForecastModel.EcmwfIfs, Acquire)
            },
            engine);
        var reports = new ConcurrentQueue<RoutingProgress>();
        var request = CreateWorkflowRequest();

        var execution = workflow.ExecuteAsync(
            request,
            new InlineProgress<RoutingProgress>(reports.Enqueue));
        await bothEntered.Task.WaitAsync(TimeSpan.FromSeconds(2));
        release.SetResult();
        var result = await execution;

        Assert.Equal(2, result.Outcomes.Length);
        var noaa = Assert.Single(result.Outcomes, outcome => outcome.Model == ForecastModel.NoaaGfs);
        Assert.Equal(ModelRouteStatus.Succeeded, noaa.Status);
        Assert.Equal(ForecastModel.NoaaGfs, noaa.Route!.Model);
        var ecmwf = Assert.Single(result.Outcomes, outcome => outcome.Model == ForecastModel.EcmwfIfs);
        Assert.Equal(ModelRouteStatus.Failed, ecmwf.Status);
        Assert.Null(ecmwf.Route);
        Assert.NotNull(ecmwf.Acquisition);
        Assert.Equal(ModelRouteFailureStage.RouteCalculation, ecmwf.Failure!.Stage);
        Assert.Contains("ECMWF", ecmwf.Failure!.Message);
        Assert.Single(result.SuccessfulRoutes);
        Assert.Contains(reports, report =>
            report.Model == ForecastModel.NoaaGfs &&
            report.Stage == RoutingProgressStage.CalculatingRoute &&
            report.Snapshot is { Diagnostics.TimeSteps: 1 } &&
            report.Snapshot.FrontSegments[0].Points.Length == 2);
        Assert.Contains(reports, report =>
            report.Model == ForecastModel.NoaaGfs &&
            report.Stage == RoutingProgressStage.Completed &&
            report.Fraction == 1);
        Assert.Contains(reports, report =>
            report.Model == ForecastModel.EcmwfIfs &&
            report.Stage == RoutingProgressStage.Failed);
    }

    [Fact]
    public void Workflow_request_without_solver_selection_uses_balanced_beam()
    {
        var request = CreateWorkflowRequest();

        Assert.Same(RouteOptimizationOptions.Balanced, request.Optimization);
        Assert.Equal(RouteSolver.IsochroneBeam, request.Optimization.Solver);
    }

    [Fact]
    public async Task Workflow_does_not_substitute_a_provider_for_a_missing_model()
    {
        var noaa = new StubForecastProvider(
            ForecastModel.NoaaGfs,
            (request, _, _) => ValueTask.FromResult(CreateAcquisition(request)));
        var workflow = new RoutingWorkflow(
            new[] { noaa },
            new StubRouteEngine((request, acquisition, _, _) =>
                ValueTask.FromResult(CreateRoute(request, acquisition.Request.Model))));

        var result = await workflow.ExecuteAsync(CreateWorkflowRequest());

        Assert.Equal(1, noaa.CallCount);
        Assert.Equal(
            ModelRouteStatus.Failed,
            Assert.Single(result.Outcomes, outcome => outcome.Model == ForecastModel.EcmwfIfs).Status);
        Assert.Equal(
            "provider-not-registered",
            Assert.Single(result.Outcomes, outcome => outcome.Model == ForecastModel.EcmwfIfs).Failure!.Code);
    }

    [Fact]
    public async Task Workflow_propagates_cancellation_instead_of_returning_a_model_failure()
    {
        var entered = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var provider = new StubForecastProvider(
            ForecastModel.NoaaGfs,
            async (_, _, cancellationToken) =>
            {
                entered.SetResult();
                await Task.Delay(Timeout.InfiniteTimeSpan, cancellationToken);
                throw new InvalidOperationException("Unreachable.");
            });
        var workflow = new RoutingWorkflow(
            new[] { provider },
            new StubRouteEngine((_, _, _, _) => throw new InvalidOperationException("Unreachable.")));
        var request = new RoutingWorkflowRequest(
            CreateRouteRequest(),
            new[] { ForecastModel.NoaaGfs });
        using var cancellation = new CancellationTokenSource();

        var execution = workflow.ExecuteAsync(request, cancellationToken: cancellation.Token);
        await entered.Task.WaitAsync(TimeSpan.FromSeconds(2));
        cancellation.Cancel();

        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => execution);
    }

    [Fact]
    public void Model_overload_rejects_null_and_preserves_duplicate_tolerance()
    {
        Assert.Throws<ArgumentNullException>(() =>
            new RoutingWorkflowRequest(CreateRouteRequest(), (IEnumerable<ForecastModel>)null!));

        var request = new RoutingWorkflowRequest(
            CreateRouteRequest(),
            new[] { ForecastModel.NoaaGfs, ForecastModel.NoaaGfs });

        Assert.Equal([ForecastModel.NoaaGfs], request.Models.ToArray());
    }

    [Fact]
    public async Task Local_forecast_routes_without_a_registered_or_remote_provider()
    {
        var route = CreateRouteRequest();
        var local = new LocalForecastDescriptor(
            ForecastModel.NoaaGfs,
            new LocalGribArtifact(Path.GetFullPath("existing.grib2"), 1_024),
            route.DepartureTime.AddHours(-6),
            route.DepartureTime.AddHours(-1),
            route.LatestArrivalTime.AddHours(1),
            new GeographicBounds(30, 55, -90, -30));
        var workflow = new RoutingWorkflow(
            Array.Empty<IForecastProvider>(),
            new StubRouteEngine((request, acquisition, _, _) =>
            {
                Assert.Equal(ForecastAcquisitionSource.LocalFile, acquisition.Source);
                Assert.Equal(local.Artifact, acquisition.Artifact);
                return ValueTask.FromResult(CreateRoute(request, acquisition.Request.Model));
            }));
        var request = new RoutingWorkflowRequest(
            route,
            new[] { ForecastSelection.LocalFile(local) },
            new GeographicBounds(35, 50, -75, -45));

        var result = await workflow.ExecuteAsync(request);

        var outcome = Assert.Single(result.Outcomes);
        Assert.Equal(ModelRouteStatus.Succeeded, outcome.Status);
        Assert.Equal(ForecastAcquisitionSource.LocalFile, outcome.Acquisition!.Source);
    }

    [Fact]
    public async Task Local_forecast_allows_requested_window_to_outlast_forecast()
    {
        var route = CreateRouteRequest();
        var local = new LocalForecastDescriptor(
            ForecastModel.NoaaGfs,
            new LocalGribArtifact(Path.GetFullPath("existing.grib2")),
            route.DepartureTime.AddHours(-6),
            route.DepartureTime,
            route.LatestArrivalTime.AddHours(-1),
            new GeographicBounds(30, 55, -90, -30));
        var workflow = new RoutingWorkflow(
            Array.Empty<IForecastProvider>(),
            new StubRouteEngine((request, acquisition, _, _) =>
            {
                Assert.Equal(local.Artifact, acquisition.Artifact);
                return ValueTask.FromResult(CreateRoute(request, acquisition.Request.Model));
            }));
        var request = new RoutingWorkflowRequest(
            route,
            new[] { ForecastSelection.LocalFile(local) },
            new GeographicBounds(35, 50, -75, -45));

        var result = await workflow.ExecuteAsync(request);

        var outcome = Assert.Single(result.Outcomes);
        Assert.Equal(ModelRouteStatus.Succeeded, outcome.Status);
        Assert.NotNull(outcome.Route);
    }

    [Fact]
    public async Task Local_forecast_still_rejects_departure_outside_coverage()
    {
        var route = CreateRouteRequest();
        var local = new LocalForecastDescriptor(
            ForecastModel.NoaaGfs,
            new LocalGribArtifact(Path.GetFullPath("existing.grib2")),
            route.DepartureTime.AddHours(-12),
            route.DepartureTime.AddHours(-6),
            route.DepartureTime.AddHours(-1),
            new GeographicBounds(30, 55, -90, -30));
        var workflow = new RoutingWorkflow(
            Array.Empty<IForecastProvider>(),
            new StubRouteEngine((_, _, _, _) =>
                throw new InvalidOperationException("Route engine must not run.")));
        var request = new RoutingWorkflowRequest(
            route,
            new[] { ForecastSelection.LocalFile(local) },
            new GeographicBounds(35, 50, -75, -45));

        var result = await workflow.ExecuteAsync(request);

        var outcome = Assert.Single(result.Outcomes);
        Assert.Equal(ModelRouteStatus.Failed, outcome.Status);
        Assert.Equal(ModelRouteFailureStage.ForecastAcquisition, outcome.Failure!.Stage);
        Assert.Contains("does not include the requested departure", outcome.Failure.Message);
    }

    [Fact]
    public async Task Workflow_classifies_forecast_exhaustion_as_a_selectable_result()
    {
        var provider = new StubForecastProvider(
            ForecastModel.NoaaGfs,
            (request, _, _) => ValueTask.FromResult(CreateAcquisition(request)));
        var workflow = new RoutingWorkflow(
            new[] { provider },
            new StubRouteEngine((request, acquisition, _, _) =>
            {
                var endpoint = new Coordinate(42, -60);
                return ValueTask.FromResult(new RouteResult(
                    request,
                    acquisition.Request.Model,
                    new[]
                    {
                        new RoutePoint(request.Origin, request.DepartureTime, 90, 6, 15, 180, 0),
                        new RoutePoint(endpoint, request.DepartureTime.AddHours(12), 90, 6, 15, 180, 60)
                    },
                    new RouteDiagnostics(10, 20, 5, 4),
                    RouteCompletion.ForecastExhausted));
            }));
        var request = new RoutingWorkflowRequest(
            CreateRouteRequest(),
            new[] { ForecastModel.NoaaGfs });

        var result = await workflow.ExecuteAsync(request);

        var outcome = Assert.Single(result.Outcomes);
        Assert.Equal(ModelRouteStatus.ForecastLimited, outcome.Status);
        Assert.True(outcome.Route!.IsForecastLimited);
        Assert.Single(result.SuccessfulRoutes);
    }

    [Fact]
    public async Task Workflow_passes_the_same_optimization_snapshot_to_route_engine()
    {
        var provider = new StubForecastProvider(
            ForecastModel.NoaaGfs,
            (request, _, _) => ValueTask.FromResult(CreateAcquisition(request)));
        var engine = new StubRouteEngine((request, acquisition, _, _) =>
            ValueTask.FromResult(CreateRoute(request, acquisition.Request.Model)));
        var optimization = new RouteOptimizationOptions(
            solver: RouteSolver.TimeDependentLattice,
            maneuver: new RouteManeuverOptions(
                TimeSpan.FromMinutes(2),
                TimeSpan.FromMinutes(3)),
            lattice: new RouteLatticeOptions(searchAlgorithm: RouteLatticeSearchAlgorithm.Dijkstra));
        var workflow = new RoutingWorkflow(new[] { provider }, engine);
        var request = new RoutingWorkflowRequest(
            CreateRouteRequest(),
            new[] { ForecastModel.NoaaGfs },
            optimization: optimization);

        await workflow.ExecuteAsync(request);

        Assert.Same(optimization, engine.LastOptimization);
    }

    private static RoutingWorkflowRequest CreateWorkflowRequest() =>
        new(
            CreateRouteRequest(),
            new[] { ForecastModel.NoaaGfs, ForecastModel.EcmwfIfs });

    private static RouteRequest CreateRouteRequest()
    {
        var departure = new DateTimeOffset(2026, 7, 15, 0, 0, 0, TimeSpan.Zero);
        return new RouteRequest(
            "route-a",
            new Coordinate(40, -70),
            new Coordinate(45, -50),
            departure,
            departure.AddDays(2));
    }

    private static ForecastAcquisition CreateAcquisition(ForecastRequest request)
    {
        var run = new ForecastRun(
            request.Provider,
            request.Model,
            request.From.AddHours(-6));
        var artifact = new LocalGribArtifact(
            $"/var/lib/navtool/{request.Model.ToString().ToLowerInvariant()}.grib2",
            1_024);
        return new ForecastAcquisition(
            request,
            run,
            artifact,
            ForecastAcquisitionSource.Remote);
    }

    private static RouteResult CreateRoute(RouteRequest request, ForecastModel model) =>
        new(
            request,
            model,
            new[]
            {
                new RoutePoint(request.Origin, request.DepartureTime, 90, 6, 15, 180, 0),
                new RoutePoint(request.Destination, request.DepartureTime.AddDays(1), 90, 6, 18, 200, 54)
            },
            new RouteDiagnostics(100, 250, 40, 24, TimeSpan.FromSeconds(1)));

    private sealed class StubForecastProvider(
        ForecastModel model,
        Func<
            ForecastRequest,
            IProgress<ForecastProgress>?,
            CancellationToken,
            ValueTask<ForecastAcquisition>> acquire) : IForecastProvider
    {
        private int _callCount;

        public ForecastProvider Provider => model.Provider();

        public ForecastModel Model => model;

        public int CallCount => _callCount;

        public ValueTask<ForecastAcquisition> AcquireAsync(
            ForecastRequest request,
            IProgress<ForecastProgress>? progress,
            CancellationToken cancellationToken)
        {
            Interlocked.Increment(ref _callCount);
            Assert.Equal(Model, request.Model);
            return acquire(request, progress, cancellationToken);
        }
    }

    private sealed class StubRouteEngine(
        Func<
            RouteRequest,
            ForecastAcquisition,
            IProgress<RouteCalculationProgress>?,
            CancellationToken,
            ValueTask<RouteResult>> calculate) : IRouteEngine
    {
        public ValueTask<RouteResult> CalculateAsync(
            RouteRequest request,
            ForecastAcquisition forecast,
            IProgress<RouteCalculationProgress>? progress,
            CancellationToken cancellationToken) =>
            calculate(request, forecast, progress, cancellationToken);

        public RouteOptimizationOptions? LastOptimization { get; private set; }

        public ValueTask<RouteResult> CalculateAsync(
            RouteRequest request,
            ForecastAcquisition forecast,
            RouteOptimizationOptions optimization,
            IProgress<RouteCalculationProgress>? progress,
            CancellationToken cancellationToken)
        {
            LastOptimization = optimization;
            return calculate(request, forecast, progress, cancellationToken);
        }
    }

    private sealed class InlineProgress<T>(Action<T> report) : IProgress<T>
    {
        public void Report(T value) => report(value);
    }
}
