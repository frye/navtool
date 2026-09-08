using System.Collections.Immutable;

namespace Navtool.Core.Tests;

public sealed class RouteAuditWorkflowTests
{
    private static readonly DateTimeOffset Now = new(2026, 8, 1, 0, 0, 0, TimeSpan.Zero);

    private static RoutingWorkflowRequest Request(RoutingCalculationContext context) =>
        new(new RouteRequest("route", new(30, -70), new(35, -60), Now, Now.AddDays(10)),
            [ForecastModel.NoaaGfs], calculationContext: context);

    [Fact]
    public async Task Recoverable_lattice_failure_records_distinct_attempts_and_actual_effective_solver()
    {
        var context = RoutingSetupTests.Context(new RouteOptimizationOptions(solver: RouteSolver.TimeDependentLattice));
        var engine = new Engine((request, model, options) =>
            options.Solver == RouteSolver.TimeDependentLattice
                ? throw new RoutingException(RoutingFailureKind.RecoverableSolver, "No connected lattice solution")
                : Route(request, model, options));
        var progress = new List<RoutingProgress>();
        var result = await new RoutingWorkflow([new ForecastSource()], engine)
            .ExecuteAsync(Request(context), new ProgressSink(progress));
        var outcome = Assert.Single(result.Outcomes);
        Assert.Equal(ModelRouteStatus.Succeeded, outcome.Status);
        Assert.Equal(2, outcome.Attempts.Length);
        Assert.NotEqual(outcome.Attempts[0].AttemptId, outcome.Attempts[1].AttemptId);
        Assert.Equal(RoutingFailureKind.RecoverableSolver, outcome.Attempts[0].FailureKind);
        Assert.Null(outcome.Attempts[1].FailureKind);
        var audit = Assert.IsType<RouteRunAudit>(outcome.Route!.RunAudit);
        Assert.Equal(context.CalculationId, audit.CalculationId);
        Assert.Equal(RouteSolver.TimeDependentLattice, audit.RequestedSolver);
        Assert.Equal(RouteSolver.IsochroneBeam, audit.Resolved.Optimization.Solver);
        Assert.Same(context.Resolved.Search, audit.Resolved.Search);
        Assert.Same(context, engine.Contexts[0]);
        Assert.Same(context, engine.Contexts[1]);
        Assert.Equal(context.Setup.Boat.ContentIdentity, audit.Setup.Boat.ContentIdentity);
        Assert.Equal(2, progress.Where(item => item.AttemptId is not null).Select(item => item.AttemptId).Distinct().Count());
        Assert.Equal("route_result_v2", audit.Native!.Schema);
        Assert.Equal(Request(context).ForecastBounds, audit.Forecast!.DeclaredBounds);
        Assert.Null(audit.Forecast.EffectiveBounds);
    }

    [Theory]
    [InlineData(RoutingFailureKind.InvalidBoat)]
    [InlineData(RoutingFailureKind.InvalidConfiguration)]
    [InlineData(RoutingFailureKind.InvalidForecast)]
    [InlineData(RoutingFailureKind.InvalidNativeOutput)]
    [InlineData(RoutingFailureKind.MissingRequiredSource)]
    [InlineData(RoutingFailureKind.ResourceLimit)]
    [InlineData(RoutingFailureKind.Cancelled)]
    [InlineData(RoutingFailureKind.NativeUnavailable)]
    [InlineData(RoutingFailureKind.Unknown)]
    public async Task Nonrecoverable_errors_never_retry_or_publish_provisional_geometry(RoutingFailureKind kind)
    {
        var context = RoutingSetupTests.Context(new RouteOptimizationOptions(solver: RouteSolver.TimeDependentLattice));
        var engine = new Engine((_, _, _) => throw new RoutingException(kind, "classified failure"));
        var result = await new RoutingWorkflow([new ForecastSource()], engine).ExecuteAsync(Request(context));
        var outcome = Assert.Single(result.Outcomes);
        Assert.Single(engine.Contexts);
        Assert.Single(outcome.Attempts);
        Assert.Null(outcome.Route);
        Assert.Null(outcome.SolverFallback);
        Assert.Equal(kind, outcome.Failure!.Kind);
        Assert.Equal(kind == RoutingFailureKind.Cancelled ? ModelRouteStatus.Cancelled : ModelRouteStatus.Failed,
            outcome.Status);
    }

    [Fact]
    public async Task Generic_lattice_exception_is_not_a_recoverable_solver_failure()
    {
        var context = RoutingSetupTests.Context(new RouteOptimizationOptions(solver: RouteSolver.TimeDependentLattice));
        var engine = new Engine((_, _, _) => throw new InvalidOperationException("unknown failure"));
        var outcome = Assert.Single((await new RoutingWorkflow([new ForecastSource()], engine)
            .ExecuteAsync(Request(context))).Outcomes);
        Assert.Single(engine.Contexts);
        Assert.Equal(RoutingFailureKind.Unknown, outcome.Failure!.Kind);
    }

    [Theory]
    [InlineData("missing-audit")]
    [InlineData("solver")]
    [InlineData("origin")]
    [InlineData("departure")]
    [InlineData("radius")]
    [InlineData("endpoint")]
    public async Task Configured_result_requires_authoritative_matching_v2_audit(string corruption)
    {
        var context = RoutingSetupTests.Context();
        var engine = new Engine((request, model, options) =>
        {
            var solver = corruption == "solver" ? RouteSolver.TimeDependentLattice : options.Solver;
            return new RouteResult(request, model,
                [new(corruption == "origin" ? new Coordinate(20, -40) : request.Origin,
                    corruption == "departure" ? request.DepartureTime.AddMinutes(1) : request.DepartureTime,
                    90, 6, 15, 180, 0),
                 new(corruption == "endpoint" ? new Coordinate(20, -40) : request.Destination,
                    request.DepartureTime.AddHours(4), 90, 6, 15, 180, 50)],
                new(1, 1, 1, 1), RouteCompletion.DestinationReached, null, solver: solver,
                nativeAudit: corruption == "missing-audit" ? null : new RouteNativeRunAudit(
                    "route_result_v2", solver, corruption == "radius" ? 10 : 1));
        });
        var outcome = Assert.Single((await new RoutingWorkflow([new ForecastSource()], engine)
            .ExecuteAsync(Request(context))).Outcomes);
        Assert.Null(outcome.Route);
        Assert.Equal(ModelRouteFailureStage.ResultValidation, outcome.Failure!.Stage);
        Assert.Equal(RoutingFailureKind.InvalidNativeOutput, outcome.Failure.Kind);
        Assert.Equal(RoutingFailureKind.InvalidNativeOutput, Assert.Single(outcome.Attempts).FailureKind);
        Assert.Single(engine.Contexts);
    }

    [Fact]
    public async Task Final_partial_output_wins_and_all_native_points_and_nullable_audit_are_retained()
    {
        var context = RoutingSetupTests.Context();
        var engine = new Engine((request, model, options) => Route(request, model, options, RouteCompletion.DurationExhausted));
        var outcome = Assert.Single((await new RoutingWorkflow([new ForecastSource()], engine)
            .ExecuteAsync(Request(context))).Outcomes);
        Assert.Equal(ModelRouteStatus.DurationLimited, outcome.Status);
        Assert.Equal(3, outcome.Route!.Points.Length);
        Assert.Null(outcome.Route.NativeAudit!.FutureProbeMisses);
        Assert.Equal(9, outcome.Route.Points[1].PolarWindSpeedKnots);
        Assert.Equal(15, outcome.Route.Points[1].TrueWindSpeedKnots);
        Assert.Null(outcome.Route.Points[0].PolarWindSpeedKnots);
    }

    [Theory]
    [InlineData("factor")]
    [InlineData("heading")]
    [InlineData("bucket")]
    [InlineData("integration")]
    [InlineData("strategic")]
    [InlineData("wind")]
    [InlineData("polar")]
    [InlineData("wind-limit")]
    [InlineData("tack")]
    [InlineData("gybe")]
    [InlineData("forecast")]
    public async Task Native_observed_settings_cannot_silently_differ_from_frozen_context(string corruption)
    {
        var context = RoutingSetupTests.Context();
        var warnings = new List<string> { "native landmask disabled" };
        var engine = new Engine((request, model, options) =>
        {
            var metadata = new RouteNativeRunMetadata("earliest_arrival", "best_found", options.Solver,
                request.Destination, 1, 0, corruption == "factor" ? 0.8 : 1,
                corruption == "heading" ? 10 : 5, corruption == "bucket" ? 10 : 5,
                TimeSpan.FromMinutes(corruption == "integration" ? 10 : 5), corruption != "strategic", false,
                corruption == "wind" ? RouteWindSampling.SegmentStart : options.WindSampling,
                corruption == "polar" ? RouteAbovePolarRangePolicy.Clamp : options.AbovePolarRange,
                corruption == "wind-limit" ? 25 : null,
                corruption == "tack" ? TimeSpan.FromSeconds(30) : TimeSpan.Zero,
                corruption == "gybe" ? TimeSpan.FromSeconds(30) : TimeSpan.Zero,
                corruption == "forecast" ? Now.AddHours(-6) : Now, Now, Now.AddDays(10), warnings);
            warnings.Clear();
            Assert.Single(metadata.Warnings);
            return new RouteResult(request, model,
                [new(request.Origin, request.DepartureTime, 90, 6, 15, 180, 0),
                 new(request.Destination, request.DepartureTime.AddHours(4), 90, 6, 15, 180, 50)],
                new(1, 1, 1, 1), RouteCompletion.DestinationReached, null,
                nativeAudit: new RouteNativeRunAudit("route_result_v2", options.Solver, 1, Routing: metadata));
        });
        var outcome = Assert.Single((await new RoutingWorkflow([new ForecastSource()], engine)
            .ExecuteAsync(Request(context))).Outcomes);
        Assert.Null(outcome.Route);
        Assert.Equal(RoutingFailureKind.InvalidNativeOutput, outcome.Failure!.Kind);
        Assert.Equal(ModelRouteFailureStage.ResultValidation, outcome.Failure.Stage);
        Assert.Single(engine.Contexts);
    }

    [Fact]
    public async Task Regional_domain_does_not_silently_shrink_the_broad_search_corridor()
    {
        var baseline = RoutingSetupTests.Context();
        var regional = new RouteRegionalLandPolicy(Path.Combine(Directory.GetCurrentDirectory(), "regional.b"),
            new string('a', 64), new(29.9, 35.1, -70.1, -59.9), 1, 0, 20, 100000, 1000000, 10000000);
        var setup = new RoutingSetup(baseline.Setup.Boat, landSource: RoutingLandSource.RegionalGshhg,
            regionalLand: regional);
        var context = new RoutingCalculationContext(Guid.NewGuid(), setup, baseline.Boat,
            baseline.NativeIdentity, baseline.Resolved);
        var provider = new ForecastSource();
        var engine = new Engine((request, model, options) => Route(request, model, options));
        var initial = Request(context);
        var request = new RoutingWorkflowRequest(initial.Route, initial.Selections,
            ForecastCorridor.Create(initial.Route.Origin, initial.Route.Destination),
            calculationContext: context);
        Assert.True(regional.StudyBounds.Contains(request.Route.Origin));
        Assert.True(regional.StudyBounds.Contains(request.Route.Destination));
        var outcome = Assert.Single((await new RoutingWorkflow([provider], engine).ExecuteAsync(request)).Outcomes);
        Assert.Equal(RoutingFailureKind.MissingRequiredSource, outcome.Failure!.Kind);
        Assert.Equal(0, provider.CallCount);
        Assert.Empty(engine.Contexts);
    }

    [Fact]
    public async Task Explicit_regional_study_domain_is_used_and_audited_without_changing_normal_corridors()
    {
        var baseline = RoutingSetupTests.Context();
        var regional = new RouteRegionalLandPolicy(Path.Combine(Directory.GetCurrentDirectory(), "regional.b"),
            new string('a', 64), new(29.9, 35.1, -70.1, -59.9), 1, 0, 20, 100000, 1000000, 10000000);
        var setup = new RoutingSetup(baseline.Setup.Boat, landSource: RoutingLandSource.RegionalGshhg,
            regionalLand: regional);
        var context = new RoutingCalculationContext(Guid.NewGuid(), setup, baseline.Boat,
            baseline.NativeIdentity, baseline.Resolved);
        var request = Request(context);
        Assert.Equal(regional.StudyBounds, request.ForecastBounds);
        Assert.Equal(ForecastCorridor.Create(request.Route.Origin, request.Route.Destination),
            Request(baseline).ForecastBounds);
        var outcome = Assert.Single((await new RoutingWorkflow([new ForecastSource()],
            new Engine((route, model, options) => Route(route, model, options))).ExecuteAsync(request)).Outcomes);
        Assert.Equal(ModelRouteStatus.Succeeded, outcome.Status);
        Assert.Equal(regional.StudyBounds, outcome.Route!.RunAudit!.Forecast!.DeclaredBounds);
    }

    [Theory]
    [InlineData(0)]
    [InlineData(1)]
    [InlineData(2)]
    public async Task Actual_native_loaded_cadence_and_effective_bounds_survive_application_run_audit(int mode)
    {
        var context = RoutingSetupTests.Context(new RouteOptimizationOptions(
            solver: mode == 2 ? RouteSolver.TimeDependentLattice : RouteSolver.IsochroneBeam));
        var request = Request(context);
        var validTimes = Enumerable.Range(0, 121).Select(hour => Now.AddHours(hour))
            .Concat(Enumerable.Range(41, 40).Select(step => Now.AddHours(step * 3))).ToArray();
        var coverage = new ForecastCoverage(request.ForecastBounds, validTimes, TimeSpan.FromHours(3));
        var engine = new Engine((routeRequest, model, options) =>
        {
            if (mode == 2 && options.Solver == RouteSolver.TimeDependentLattice)
                throw new RoutingException(RoutingFailureKind.RecoverableSolver, "Retry this search with beam.");
            var route = Route(routeRequest, model, options);
            if (mode > 0)
                return route.WithRunAudit(new RouteRunAudit(context.CalculationId, context.Setup,
                    context.Resolved with { Optimization = options }, context.NativeIdentity, options.Solver,
                    [new RouteAttemptAudit(Guid.NewGuid(), options.Solver, Now, Now)],
                    forecast: new RouteForecastAudit(new ForecastRun(model.Provider(), model, Now),
                        request.ForecastBounds, request.ForecastBounds, Now, Now.AddDays(10),
                        TimeSpan.FromHours(3), TimeSpan.FromHours(1), TimeSpan.FromHours(3), validTimes.ToImmutableArray()),
                    native: route.NativeAudit));
            return new RouteResult(route.Request, route.Model, route.Points, route.Diagnostics,
                route.Completion, route.LandAvoidance, route.Solver,
                nativeAudit: route.NativeAudit! with { ForecastCoverage = coverage });
        });
        var outcome = Assert.Single((await new RoutingWorkflow([new ForecastSource()], engine)
            .ExecuteAsync(request)).Outcomes);
        var audit = Assert.IsType<RouteForecastAudit>(outcome.Route!.RunAudit!.Forecast);
        Assert.Equal(161, audit.ValidTimes.Length);
        Assert.Equal(TimeSpan.FromHours(1), audit.MinimumTimeSpacing);
        Assert.Equal(TimeSpan.FromHours(3), audit.MaximumTimeSpacing);
        Assert.Equal(TimeSpan.FromHours(3), audit.MaximumInterpolationGap);
        Assert.Equal(request.ForecastBounds, audit.EffectiveBounds);
        Assert.Equal(Now.AddDays(10), audit.ValidThrough);
        Assert.Equal(mode == 2 ? 2 : 1, outcome.Route.RunAudit!.Attempts.Length);
        Assert.Equal(context.Resolved.Optimization.Solver, outcome.Route.RunAudit.RequestedSolver);
        validTimes[0] = Now.AddYears(1);
        Assert.Equal(Now, audit.ValidTimes[0]);
    }

    [Fact]
    public void Restored_duplicate_native_audits_compare_collection_contents_not_array_identity()
    {
        var context = RoutingSetupTests.Context();
        var request = Request(context).Route;
        RouteNativeRunAudit Audit(string warning)
        {
            var times = Enumerable.Range(0, 121).Select(hour => Now.AddHours(hour))
                .Concat(Enumerable.Range(41, 40).Select(step => Now.AddHours(step * 3))).ToList();
            var metadata = new RouteNativeRunMetadata("earliest_arrival", "best_found",
                RouteSolver.IsochroneBeam, request.Destination, 1, 0, 1, 5, 5,
                TimeSpan.FromMinutes(5), true, false, RouteWindSampling.Midpoint,
                RouteAbovePolarRangePolicy.NoSpeed, null, TimeSpan.Zero, TimeSpan.Zero,
                Now, Now, Now.AddDays(10), new List<string> { warning });
            return new RouteNativeRunAudit("route_result_v2", RouteSolver.IsochroneBeam, 1,
                Routing: metadata, ForecastCoverage: new ForecastCoverage(new(20, 50, -90, -40), times));
        }
        var original = Audit("native landmask disabled");
        var restored = Audit("native landmask disabled");
        Assert.False(original.Routing!.Warnings.Equals(restored.Routing!.Warnings));
        var run = new RouteRunAudit(context.CalculationId, context.Setup, context.Resolved,
            context.NativeIdentity, RouteSolver.IsochroneBeam,
            [new RouteAttemptAudit(Guid.NewGuid(), RouteSolver.IsochroneBeam, Now, Now)],
            native: original);
        var route = Route(request, ForecastModel.NoaaGfs, context.Resolved.Optimization);
        var reconstructed = new RouteResult(request, route.Model, route.Points, route.Diagnostics,
            route.Completion, route.LandAvoidance, runAudit: run, nativeAudit: restored);
        Assert.NotNull(reconstructed.RunAudit);
        Assert.Throws<ArgumentException>(() => new RouteResult(request, route.Model, route.Points, route.Diagnostics,
            route.Completion, route.LandAvoidance, runAudit: run, nativeAudit: Audit("different native warning")));
    }

    private static RouteResult Route(RouteRequest request, ForecastModel model, RouteOptimizationOptions options,
        RouteCompletion completion = RouteCompletion.DestinationReached) =>
        new(request, model,
            [new(request.Origin, request.DepartureTime, 90, 6, 15, 180, 0),
             new(new(32, -65), request.DepartureTime.AddHours(2), 90, 6, 15, 180, 25, null, 9, 170),
             new(request.Destination, request.DepartureTime.AddHours(4), 90, 6, 15, 180, 50)],
            new(1, 1, 1, 1), completion, null, solver: options.Solver,
            nativeAudit: new RouteNativeRunAudit("route_result_v2", options.Solver, 1,
                Routing: new RouteNativeRunMetadata("earliest_arrival", "best_found", options.Solver,
                    request.Destination, 1, 0, 1, 5, 5, TimeSpan.FromMinutes(5), true, false,
                    options.WindSampling, options.AbovePolarRange, options.MaximumTrueWindSpeedKnots,
                    options.Maneuver.TackPenalty, options.Maneuver.GybePenalty,
                    Now, Now, Now.AddDays(10), [])));

    private sealed class Engine(Func<RouteRequest, ForecastModel, RouteOptimizationOptions, RouteResult> calculate)
        : IConfiguredRouteEngine
    {
        public List<RoutingCalculationContext> Contexts { get; } = [];
        public ValueTask<RouteResult> CalculateAsync(RouteRequest request, ForecastAcquisition forecast,
            IProgress<RouteCalculationProgress>? progress, CancellationToken cancellationToken) =>
            throw new InvalidOperationException("Configured routing cannot downgrade.");

        public ValueTask<RouteResult> CalculateConfiguredAsync(RoutingCalculationContext context,
            RouteRequest request, ForecastAcquisition forecast, RouteOptimizationOptions optimization,
            IProgress<RouteCalculationProgress>? progress, CancellationToken cancellationToken)
        {
            Contexts.Add(context);
            progress?.Report(new RouteCalculationProgress(0.7));
            cancellationToken.ThrowIfCancellationRequested();
            return ValueTask.FromResult(calculate(request, forecast.Run.Model, optimization));
        }
    }

    private sealed class ForecastSource : IForecastProvider
    {
        public int CallCount { get; private set; }
        public ForecastProvider Provider => ForecastProvider.Noaa;
        public ForecastModel Model => ForecastModel.NoaaGfs;
        public ValueTask<ForecastAcquisition> AcquireAsync(ForecastRequest request,
            IProgress<ForecastProgress>? progress, CancellationToken cancellationToken)
        {
            CallCount++;
            return ValueTask.FromResult(new ForecastAcquisition(request,
                new ForecastRun(Provider, Model, Now),
                new LocalGribArtifact(Path.Combine(Directory.GetCurrentDirectory(), "test.grib2")),
                ForecastAcquisitionSource.Cache));
        }
    }

    private sealed class ProgressSink(List<RoutingProgress> reports) : IProgress<RoutingProgress>
    {
        public void Report(RoutingProgress value) => reports.Add(value);
    }
}
