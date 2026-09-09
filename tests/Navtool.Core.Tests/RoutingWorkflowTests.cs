using System.Collections.Concurrent;

namespace Navtool.Core.Tests;

public sealed class RoutingWorkflowTests
{
    [Fact]
    public void Progress_preserves_its_original_positional_contract()
    {
        var progress = new RoutingProgress(ForecastModel.NoaaGfs.Provider(), ForecastModel.NoaaGfs,
            RoutingProgressStage.CalculatingRoute, .5);
        var (provider, model, stage, fraction, message, snapshot, attemptId) = progress;
        Assert.Equal(ForecastModel.NoaaGfs.Provider(), provider);
        Assert.Equal(ForecastModel.NoaaGfs, model);
        Assert.Equal(RoutingProgressStage.CalculatingRoute, stage);
        Assert.Equal(.5, fraction);
        Assert.Null(message);
        Assert.Null(snapshot);
        Assert.Null(attemptId);
        Assert.Null(progress.Request);
        Assert.Null(progress.Acquisition);
    }

    [Fact]
    public void Workflow_request_without_solver_selection_uses_balanced_beam()
    {
        var request = new RoutingWorkflowRequest(
            CreateRouteRequest(),
            new[] { ForecastModel.NoaaGfs });

        Assert.Same(RouteOptimizationOptions.Balanced, request.Optimization);
        Assert.Equal(RouteSolver.IsochroneBeam, request.Optimization.Solver);
    }

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
        Assert.All(reports.Where(report => report.Stage == RoutingProgressStage.CalculatingRoute), report =>
        {
            Assert.Same(request.Route, report.Request);
            Assert.Same(result.Outcomes.Single(outcome => outcome.Model == report.Model).Acquisition,
                report.Acquisition);
        });
        Assert.All(reports.Where(report => report.Stage == RoutingProgressStage.AcquiringForecast), report =>
        {
            Assert.Null(report.Request);
            Assert.Null(report.Acquisition);
        });
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
    public async Task Snapshot_retains_validated_context_when_cancellation_prevents_an_outcome()
    {
        var reports = new List<RoutingProgress>();
        using var cancellation = new CancellationTokenSource();
        ForecastAcquisition? acquired = null;
        var workflow = new RoutingWorkflow(
            [new StubForecastProvider(ForecastModel.NoaaGfs, (request, _, _) =>
                ValueTask.FromResult(acquired = CreateAcquisition(request)))],
            new StubRouteEngine((request, _, progress, token) =>
            {
                progress?.Report(new RouteCalculationProgress(0.4, snapshot: Snapshot(request)));
                cancellation.Cancel();
                token.ThrowIfCancellationRequested();
                throw new InvalidOperationException("Unreachable.");
            }));
        var request = new RoutingWorkflowRequest(CreateRouteRequest(), [ForecastModel.NoaaGfs]);

        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => workflow.ExecuteAsync(
            request, new InlineProgress<RoutingProgress>(reports.Add), cancellation.Token));

        var snapshot = Assert.Single(reports, report => report.Snapshot is not null);
        Assert.Same(request.Route, snapshot.Request);
        Assert.Same(acquired, snapshot.Acquisition);
        Assert.NotNull(snapshot.AttemptId);
        Assert.DoesNotContain(reports, report =>
            report.Stage is RoutingProgressStage.Completed or RoutingProgressStage.Failed);
    }

    [Theory]
    [InlineData(true)]
    [InlineData(false)]
    public async Task Invalid_acquisition_never_exposes_progress_context(bool differentRequest)
    {
        var reports = new List<RoutingProgress>();
        var workflow = new RoutingWorkflow(
            [new StubForecastProvider(ForecastModel.NoaaGfs, (request, _, _) =>
            {
                if (differentRequest)
                    return ValueTask.FromResult(CreateAcquisition(new ForecastRequest(
                        request.Model, request.Bounds, request.From.AddHours(1), request.Through,
                        request.RefreshPolicy)));
                var acquired = CreateAcquisition(request);
                return ValueTask.FromResult(new ForecastAcquisition(
                    request, acquired.Run, acquired.Artifact, acquired.Source,
                    coverage: new ForecastCoverage(request.Bounds,
                        [request.From.AddHours(1), request.From.AddHours(2)])));
            })],
            new StubRouteEngine((_, _, _, _) =>
                throw new InvalidOperationException("Invalid forecasts must not reach the engine.")));

        var result = await workflow.ExecuteAsync(
            new RoutingWorkflowRequest(CreateRouteRequest(), [ForecastModel.NoaaGfs]),
            new InlineProgress<RoutingProgress>(reports.Add));

        Assert.Equal(ModelRouteFailureStage.ForecastAcquisition, Assert.Single(result.Outcomes).Failure!.Stage);
        Assert.DoesNotContain(reports, report => report.Stage == RoutingProgressStage.CalculatingRoute);
        Assert.All(reports, report =>
        {
            Assert.Null(report.Request);
            Assert.Null(report.Acquisition);
        });
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
    public async Task Workflow_classifies_duration_exhaustion_as_a_selectable_partial_result()
    {
        var provider = new StubForecastProvider(
            ForecastModel.NoaaGfs,
            (request, _, _) => ValueTask.FromResult(CreateAcquisition(request)));
        var workflow = new RoutingWorkflow(
            new[] { provider },
            new StubRouteEngine((request, acquisition, _, _) =>
                ValueTask.FromResult(new RouteResult(
                    request,
                    acquisition.Request.Model,
                    new[]
                    {
                        new RoutePoint(request.Origin, request.DepartureTime, 90, 6, 15, 180, 0),
                        new RoutePoint(
                            new Coordinate(42, -60),
                            request.DepartureTime.AddHours(12),
                            90,
                            6,
                            15,
                            180,
                            60)
                    },
                    new RouteDiagnostics(10, 20, 5, 4),
                    RouteCompletion.DurationExhausted))));
        var request = new RoutingWorkflowRequest(
            CreateRouteRequest(),
            new[] { ForecastModel.NoaaGfs });

        var result = await workflow.ExecuteAsync(request);

        var outcome = Assert.Single(result.Outcomes);
        Assert.Equal(ModelRouteStatus.DurationLimited, outcome.Status);
        Assert.True(outcome.Route!.IsDurationLimited);
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

    [Fact]
    public async Task Workflow_falls_back_to_the_beam_solver_when_the_lattice_solver_fails()
    {
        StubRouteEngine? engine = null;
        engine = new StubRouteEngine((request, acquisition, progress, _) =>
        {
            progress?.Report(new RouteCalculationProgress(0.4, snapshot: Snapshot(request)));
            return engine!.Optimizations[^1].Solver == RouteSolver.TimeDependentLattice
                ? throw new RoutingException(RoutingFailureKind.RecoverableSolver,
                    "time-dependent lattice search exhausted every reachable state")
                : ValueTask.FromResult(CreateRoute(request, acquisition.Request.Model));
        });
        var workflow = new RoutingWorkflow(
            new[]
            {
                new StubForecastProvider(
                    ForecastModel.NoaaGfs,
                    (request, _, _) => ValueTask.FromResult(CreateAcquisition(request)))
            },
            engine);
        var reports = new ConcurrentQueue<RoutingProgress>();

        var result = await workflow.ExecuteAsync(
            new RoutingWorkflowRequest(
                CreateRouteRequest(),
                new[] { ForecastModel.NoaaGfs },
                optimization: new RouteOptimizationOptions(
                    solver: RouteSolver.TimeDependentLattice)),
            new InlineProgress<RoutingProgress>(reports.Enqueue));

        var outcome = Assert.Single(result.Outcomes);
        Assert.Equal(ModelRouteStatus.Succeeded, outcome.Status);
        Assert.NotNull(outcome.Route);
        Assert.Equal(
            new[] { RouteSolver.TimeDependentLattice, RouteSolver.IsochroneBeam },
            engine.Optimizations.Select(item => item.Solver));
        Assert.NotNull(outcome.SolverFallback);
        Assert.Contains("time-dependent lattice", outcome.SolverFallback);
        Assert.Contains("isochrone beam", outcome.SolverFallback);
        Assert.Contains("exhausted every reachable state", outcome.SolverFallback);
        Assert.Contains(reports, report =>
            report.Stage == RoutingProgressStage.CalculatingRoute &&
            report.Message is not null &&
            report.Message.Contains("isochrone beam", StringComparison.Ordinal));
        Assert.All(reports.Where(report => report.Stage == RoutingProgressStage.CalculatingRoute), report =>
        {
            Assert.Same(outcome.Route.Request, report.Request);
            Assert.Same(outcome.Acquisition, report.Acquisition);
        });
        var snapshots = reports.Where(report => report.Snapshot is not null).ToArray();
        Assert.Equal(2, snapshots.Length);
        Assert.All(snapshots, report => Assert.NotNull(report.AttemptId));
        Assert.NotEqual(snapshots[0].AttemptId, snapshots[1].AttemptId);
    }

    [Fact]
    public async Task Workflow_keeps_progress_monotonic_across_a_solver_fallback()
    {
        StubRouteEngine? engine = null;
        engine = new StubRouteEngine((request, acquisition, progress, _) =>
        {
            if (engine!.Optimizations[^1].Solver == RouteSolver.TimeDependentLattice)
            {
                // The lattice searches for a while before giving up, so the bar has
                // already advanced when the fallback message is reported.
                progress?.Report(new RouteCalculationProgress(0.8));
                throw new RoutingException(RoutingFailureKind.RecoverableSolver, "lattice failed");
            }

            progress?.Report(new RouteCalculationProgress(0.1));
            return ValueTask.FromResult(CreateRoute(request, acquisition.Request.Model));
        });
        var workflow = new RoutingWorkflow(
            new[]
            {
                new StubForecastProvider(
                    ForecastModel.NoaaGfs,
                    (request, _, _) => ValueTask.FromResult(CreateAcquisition(request)))
            },
            engine);
        var fractions = new List<double>();

        var result = await workflow.ExecuteAsync(
            new RoutingWorkflowRequest(
                CreateRouteRequest(),
                new[] { ForecastModel.NoaaGfs },
                optimization: new RouteOptimizationOptions(
                    solver: RouteSolver.TimeDependentLattice)),
            new InlineProgress<RoutingProgress>(report => fractions.Add(report.Fraction)));

        Assert.Equal(ModelRouteStatus.Succeeded, Assert.Single(result.Outcomes).Status);
        Assert.NotEmpty(fractions);
        for (var index = 1; index < fractions.Count; index++)
        {
            Assert.True(
                fractions[index] >= fractions[index - 1],
                $"Progress went backwards: {fractions[index - 1]} then {fractions[index]}.");
        }
    }

    [Fact]
    public async Task Workflow_does_not_fall_back_when_the_solver_runs_out_of_memory()
    {
        var engine = new StubRouteEngine((_, _, _, _) => throw new OutOfMemoryException());
        var workflow = new RoutingWorkflow(
            new[]
            {
                new StubForecastProvider(
                    ForecastModel.NoaaGfs,
                    (request, _, _) => ValueTask.FromResult(CreateAcquisition(request)))
            },
            engine);

        var result = await workflow.ExecuteAsync(
            new RoutingWorkflowRequest(
                CreateRouteRequest(),
                new[] { ForecastModel.NoaaGfs },
                optimization: new RouteOptimizationOptions(
                    solver: RouteSolver.TimeDependentLattice)));

        // Retrying after memory exhaustion would paper over the real failure, so the
        // lattice attempt must be the only one and the outcome must report the failure.
        var outcome = Assert.Single(result.Outcomes);
        Assert.Equal(ModelRouteStatus.Failed, outcome.Status);
        Assert.Null(outcome.SolverFallback);
        Assert.Equal(
            new[] { RouteSolver.TimeDependentLattice },
            engine.Optimizations.Select(item => item.Solver));
    }

    [Fact]
    public async Task Workflow_preserves_every_other_option_when_it_falls_back()
    {
        StubRouteEngine? engine = null;
        engine = new StubRouteEngine((request, acquisition, _, _) =>
            engine!.Optimizations[^1].Solver == RouteSolver.TimeDependentLattice
                ? throw new RoutingException(RoutingFailureKind.RecoverableSolver, "lattice failed")
                : ValueTask.FromResult(CreateRoute(request, acquisition.Request.Model)));
        var workflow = new RoutingWorkflow(
            new[]
            {
                new StubForecastProvider(
                    ForecastModel.NoaaGfs,
                    (request, _, _) => ValueTask.FromResult(CreateAcquisition(request)))
            },
            engine);
        var optimization = new RouteOptimizationOptions(
            solver: RouteSolver.TimeDependentLattice,
            headingAugmentation: RouteHeadingAugmentation.VelocityMadeGood,
            windSampling: RouteWindSampling.SegmentStart,
            pruningSectorDegrees: 7,
            lattice: new RouteLatticeOptions(subdivisionLevel: 5),
            environment: new RouteEnvironmentOptions(
                landRequest: new RouteLandmaskRequest(),
                sampling: RouteEnvironmentSampling.Midpoint));

        await workflow.ExecuteAsync(
            new RoutingWorkflowRequest(
                CreateRouteRequest(),
                new[] { ForecastModel.NoaaGfs },
                optimization: optimization));

        var fallback = engine.Optimizations[^1];
        Assert.Equal(RouteSolver.IsochroneBeam, fallback.Solver);
        Assert.Equal(optimization.WithSolver(RouteSolver.IsochroneBeam), fallback);
        Assert.Equal(RouteHeadingAugmentation.VelocityMadeGood, fallback.HeadingAugmentation);
        Assert.Equal(RouteWindSampling.SegmentStart, fallback.WindSampling);
        Assert.Equal(7, fallback.PruningSectorDegrees);
        Assert.Equal(5, fallback.Lattice.SubdivisionLevel);
        // The Stage 3 environment must survive the fallback: dropping it would
        // silently route the retry without the caller's landmask or exclusions.
        Assert.NotNull(fallback.Environment);
        Assert.Equal(
            RouteEnvironmentSampling.Midpoint,
            fallback.Environment.Sampling);
    }

    [Fact]
    public async Task Workflow_does_not_retry_when_the_beam_solver_itself_fails()
    {
        var engine = new StubRouteEngine((_, _, _, _) =>
            throw new InvalidOperationException("beam failed"));
        var workflow = new RoutingWorkflow(
            new[]
            {
                new StubForecastProvider(
                    ForecastModel.NoaaGfs,
                    (request, _, _) => ValueTask.FromResult(CreateAcquisition(request)))
            },
            engine);

        var result = await workflow.ExecuteAsync(
            new RoutingWorkflowRequest(
                CreateRouteRequest(),
                new[] { ForecastModel.NoaaGfs },
                optimization: new RouteOptimizationOptions(solver: RouteSolver.IsochroneBeam)));

        var outcome = Assert.Single(result.Outcomes);
        Assert.Equal(ModelRouteStatus.Failed, outcome.Status);
        Assert.Null(outcome.SolverFallback);
        Assert.Single(engine.Optimizations);
    }

    [Fact]
    public async Task Workflow_reports_the_original_failure_when_the_fallback_also_fails()
    {
        var engine = new StubRouteEngine((_, _, _, _) =>
            throw new RoutingException(RoutingFailureKind.RecoverableSolver, "solver failed"));
        var workflow = new RoutingWorkflow(
            new[]
            {
                new StubForecastProvider(
                    ForecastModel.NoaaGfs,
                    (request, _, _) => ValueTask.FromResult(CreateAcquisition(request)))
            },
            engine);

        var result = await workflow.ExecuteAsync(
            new RoutingWorkflowRequest(
                CreateRouteRequest(),
                new[] { ForecastModel.NoaaGfs },
                optimization: new RouteOptimizationOptions(
                    solver: RouteSolver.TimeDependentLattice)));

        var outcome = Assert.Single(result.Outcomes);
        Assert.Equal(ModelRouteStatus.Failed, outcome.Status);
        Assert.Equal(ModelRouteFailureStage.RouteCalculation, outcome.Failure!.Stage);
        Assert.Equal(2, engine.Optimizations.Count);
    }

    [Fact]
    public void WithSolver_returns_the_same_instance_when_the_solver_is_unchanged()
    {
        var options = new RouteOptimizationOptions(solver: RouteSolver.IsochroneBeam);

        Assert.Same(options, options.WithSolver(RouteSolver.IsochroneBeam));
    }

    private static RoutingWorkflowRequest CreateWorkflowRequest() =>
        new(
            CreateRouteRequest(),
            new[] { ForecastModel.NoaaGfs, ForecastModel.EcmwfIfs });

    private static RouteCalculationSnapshot Snapshot(RouteRequest request) =>
        new(request.DepartureTime.AddHours(1),
            [new RouteCalculationEnvelopeSegment([request.Origin, request.Destination], closed: false)],
            [new RouteCalculationFrontSegment([request.Origin, request.Destination])],
            [new RoutePoint(request.Origin, request.DepartureTime, 90, 6, 15, 180, 0),
             new RoutePoint(request.Destination, request.DepartureTime.AddHours(1), 90, 6, 15, 180, 6)],
            new RouteDiagnostics(1, 2, 1, 1));

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

        public List<RouteOptimizationOptions> Optimizations { get; } = [];

        public ValueTask<RouteResult> CalculateAsync(
            RouteRequest request,
            ForecastAcquisition forecast,
            RouteOptimizationOptions optimization,
            IProgress<RouteCalculationProgress>? progress,
            CancellationToken cancellationToken)
        {
            LastOptimization = optimization;
            Optimizations.Add(optimization);
            return calculate(request, forecast, progress, cancellationToken);
        }
    }

    private sealed class InlineProgress<T>(Action<T> report) : IProgress<T>
    {
        public void Report(T value) => report(value);
    }
}
