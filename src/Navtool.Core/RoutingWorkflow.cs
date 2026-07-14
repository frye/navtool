using System.Collections.Immutable;

namespace Navtool.Core;

public sealed record RoutingWorkflowRequest
{
    public RoutingWorkflowRequest(
        RouteRequest route,
        IEnumerable<ForecastModel> models,
        GeographicBounds? forecastBounds = null)
    {
        ArgumentNullException.ThrowIfNull(route);
        ArgumentNullException.ThrowIfNull(models);
        var immutableModels = models.Distinct().ToImmutableArray();
        if (immutableModels.Length is < 1 or > 2)
        {
            throw new ArgumentException("Select one or two distinct forecast models.", nameof(models));
        }

        foreach (var model in immutableModels)
        {
            _ = model.Provider();
        }

        if (route.Origin.IsSameLocation(route.Destination))
        {
            throw new ArgumentException("Origin and destination must be different.", nameof(route));
        }

        if (route.LatestArrivalTime <= route.DepartureTime)
        {
            throw new ArgumentException("Latest arrival must be after departure.", nameof(route));
        }

        Route = route;
        Models = immutableModels;
        ForecastBounds = forecastBounds ?? GeographicBounds.FromCoordinates(
            new[] { route.Origin, route.Destination });
    }

    public RouteRequest Route { get; }

    public ImmutableArray<ForecastModel> Models { get; }

    public GeographicBounds ForecastBounds { get; }
}

public enum RoutingProgressStage
{
    AcquiringForecast,
    CalculatingRoute,
    Completed,
    Failed
}

public sealed record RoutingProgress(
    ForecastProvider Provider,
    ForecastModel Model,
    RoutingProgressStage Stage,
    double Fraction,
    string? Message = null);

public enum ModelRouteStatus
{
    Succeeded,
    Failed
}

public enum ModelRouteFailureStage
{
    ProviderRegistration,
    ForecastAcquisition,
    RouteCalculation,
    ResultValidation
}

public sealed record ModelRouteFailure(
    ModelRouteFailureStage Stage,
    string Code,
    string Message);

public sealed record ModelRouteOutcome
{
    private ModelRouteOutcome(
        ForecastModel model,
        ModelRouteStatus status,
        ForecastAcquisition? acquisition,
        RouteResult? route,
        ModelRouteFailure? failure)
    {
        Model = model;
        Provider = model.Provider();
        Status = status;
        Acquisition = acquisition;
        Route = route;
        Failure = failure;
    }

    public ForecastProvider Provider { get; }

    public ForecastModel Model { get; }

    public ModelRouteStatus Status { get; }

    public ForecastAcquisition? Acquisition { get; }

    public RouteResult? Route { get; }

    public ModelRouteFailure? Failure { get; }

    public static ModelRouteOutcome Succeeded(
        ForecastModel model,
        ForecastAcquisition acquisition,
        RouteResult route) =>
        new(model, ModelRouteStatus.Succeeded, acquisition, route, null);

    public static ModelRouteOutcome Failed(
        ForecastModel model,
        ModelRouteFailureStage stage,
        string code,
        string message,
        ForecastAcquisition? acquisition = null) =>
        new(
            model,
            ModelRouteStatus.Failed,
            acquisition,
            null,
            new ModelRouteFailure(stage, code, message));
}

public sealed record RoutingWorkflowResult
{
    public RoutingWorkflowResult(
        RoutingWorkflowRequest request,
        IEnumerable<ModelRouteOutcome> outcomes)
    {
        ArgumentNullException.ThrowIfNull(request);
        ArgumentNullException.ThrowIfNull(outcomes);
        Request = request;
        Outcomes = outcomes.ToImmutableArray();
        if (Outcomes.Length != request.Models.Length ||
            Outcomes.Select(outcome => outcome.Model).Distinct().Count() != Outcomes.Length ||
            Outcomes.Any(outcome => !request.Models.Contains(outcome.Model)))
        {
            throw new ArgumentException(
                "Outcomes must contain exactly one entry for every requested model.",
                nameof(outcomes));
        }
    }

    public RoutingWorkflowRequest Request { get; }

    public ImmutableArray<ModelRouteOutcome> Outcomes { get; }

    public ImmutableArray<RouteResult> SuccessfulRoutes =>
        Outcomes
            .Where(outcome => outcome.Route is not null)
            .Select(outcome => outcome.Route!)
            .ToImmutableArray();
}

public sealed class RoutingWorkflow
{
    private readonly ImmutableDictionary<ForecastModel, IForecastProvider> _providers;
    private readonly IRouteEngine _routeEngine;

    public RoutingWorkflow(
        IEnumerable<IForecastProvider> providers,
        IRouteEngine routeEngine)
    {
        ArgumentNullException.ThrowIfNull(providers);
        ArgumentNullException.ThrowIfNull(routeEngine);

        var providerArray = providers.ToArray();
        foreach (var provider in providerArray)
        {
            if (provider.Model.Provider() != provider.Provider)
            {
                throw new ArgumentException(
                    $"Provider {provider.Provider} cannot supply {provider.Model}.",
                    nameof(providers));
            }
        }

        var duplicateModel = providerArray
            .GroupBy(provider => provider.Model)
            .FirstOrDefault(group => group.Count() > 1);
        if (duplicateModel is not null)
        {
            throw new ArgumentException(
                $"More than one provider is registered for {duplicateModel.Key}.",
                nameof(providers));
        }

        _providers = providerArray.ToImmutableDictionary(provider => provider.Model);
        _routeEngine = routeEngine;
    }

    public async Task<RoutingWorkflowResult> ExecuteAsync(
        RoutingWorkflowRequest request,
        IProgress<RoutingProgress>? progress = null,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(request);
        cancellationToken.ThrowIfCancellationRequested();

        var tasks = request.Models
            .Select(model => RunModelAsync(request, model, progress, cancellationToken))
            .ToArray();

        var outcomes = await Task.WhenAll(tasks).WaitAsync(cancellationToken).ConfigureAwait(false);
        cancellationToken.ThrowIfCancellationRequested();
        return new RoutingWorkflowResult(request, outcomes);
    }

    private async Task<ModelRouteOutcome> RunModelAsync(
        RoutingWorkflowRequest request,
        ForecastModel model,
        IProgress<RoutingProgress>? progress,
        CancellationToken cancellationToken)
    {
        var providerId = model.Provider();
        if (!_providers.TryGetValue(model, out var provider))
        {
            var missing = ModelRouteOutcome.Failed(
                model,
                ModelRouteFailureStage.ProviderRegistration,
                "provider-not-registered",
                $"No provider is registered for {model}.");
            Report(progress, providerId, model, RoutingProgressStage.Failed, 1, missing.Failure!.Message);
            return missing;
        }

        ForecastAcquisition? acquisition = null;
        var failureStage = ModelRouteFailureStage.ForecastAcquisition;
        try
        {
            cancellationToken.ThrowIfCancellationRequested();
            Report(progress, providerId, model, RoutingProgressStage.AcquiringForecast, 0);
            var forecastRequest = new ForecastRequest(
                model,
                request.ForecastBounds,
                request.Route.DepartureTime,
                request.Route.LatestArrivalTime);
            var forecastProgress = new SynchronousProgress<ForecastProgress>(value =>
                Report(
                    progress,
                    providerId,
                    model,
                    RoutingProgressStage.AcquiringForecast,
                    value.Fraction * 0.5,
                    value.Message));

            acquisition = await provider
                .AcquireAsync(forecastRequest, forecastProgress, cancellationToken)
                .ConfigureAwait(false);

            cancellationToken.ThrowIfCancellationRequested();
            if (acquisition.Request != forecastRequest)
            {
                throw new InvalidOperationException("The provider returned forecast data for a different request.");
            }

            failureStage = ModelRouteFailureStage.RouteCalculation;
            Report(progress, providerId, model, RoutingProgressStage.CalculatingRoute, 0.5);
            var routeProgress = new SynchronousProgress<RouteCalculationProgress>(value =>
                Report(
                    progress,
                    providerId,
                    model,
                    RoutingProgressStage.CalculatingRoute,
                    0.5 + (value.Fraction * 0.5),
                    value.Message));

            var route = await _routeEngine
                .CalculateAsync(request.Route, acquisition, routeProgress, cancellationToken)
                .ConfigureAwait(false);

            cancellationToken.ThrowIfCancellationRequested();
            failureStage = ModelRouteFailureStage.ResultValidation;
            if (route.Model != model || route.Request != request.Route)
            {
                throw new InvalidOperationException("The route engine returned a route for a different request or model.");
            }

            Report(progress, providerId, model, RoutingProgressStage.Completed, 1);
            return ModelRouteOutcome.Succeeded(model, acquisition, route);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception exception)
        {
            Report(progress, providerId, model, RoutingProgressStage.Failed, 1, exception.Message);
            return ModelRouteOutcome.Failed(
                model,
                failureStage,
                failureStage switch
                {
                    ModelRouteFailureStage.ForecastAcquisition => "forecast-acquisition-failed",
                    ModelRouteFailureStage.ResultValidation => "route-result-invalid",
                    _ => "route-calculation-failed"
                },
                exception.Message,
                acquisition);
        }
    }

    private static void Report(
        IProgress<RoutingProgress>? progress,
        ForecastProvider provider,
        ForecastModel model,
        RoutingProgressStage stage,
        double fraction,
        string? message = null) =>
        progress?.Report(new RoutingProgress(provider, model, stage, fraction, message));

    private sealed class SynchronousProgress<T>(Action<T> report) : IProgress<T>
    {
        public void Report(T value) => report(value);
    }
}
