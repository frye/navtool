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
            progress?.Report(new RouteCalculationProgress(1));
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

        var execution = workflow.ExecuteAsync(CreateWorkflowRequest(), new InlineProgress<RoutingProgress>(reports.Enqueue));
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
            report.Stage == RoutingProgressStage.Completed &&
            report.Fraction == 1);
        Assert.Contains(reports, report =>
            report.Model == ForecastModel.EcmwfIfs &&
            report.Stage == RoutingProgressStage.Failed);
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
    }

    private sealed class InlineProgress<T>(Action<T> report) : IProgress<T>
    {
        public void Report(T value) => report(value);
    }
}
