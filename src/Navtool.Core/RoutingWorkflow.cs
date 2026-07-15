using System.Collections.Immutable;

namespace Navtool.Core;

public sealed record RoutingWorkflowRequest
{
    public RoutingWorkflowRequest(
        RouteRequest route,
        IEnumerable<ForecastModel> models,
        GeographicBounds? forecastBounds = null)
        : this(
            route,
            models.Select(ForecastSelection.OfficialDownload),
            forecastBounds)
    {
    }

    public RoutingWorkflowRequest(
        RouteRequest route,
        IEnumerable<ForecastSelection> selections,
        GeographicBounds? forecastBounds = null)
    {
        ArgumentNullException.ThrowIfNull(route);
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

        foreach (var selection in immutableSelections)
        {
            _ = selection.Model.Provider();
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
        Selections = immutableSelections;
        Models = immutableSelections.Select(selection => selection.Model).ToImmutableArray();
        ForecastBounds = forecastBounds ?? GeographicBounds.FromCoordinates(
            new[] { route.Origin, route.Destination });
    }

    public RouteRequest Route { get; }

    public ImmutableArray<ForecastModel> Models { get; }

    public ImmutableArray<ForecastSelection> Selections { get; }

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
    string? Message = null,
    RouteCalculationSnapshot? Snapshot = null);

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

        var tasks = request.Selections
            .Select(selection => RunModelAsync(request, selection, progress, cancellationToken))
            .ToArray();

        var outcomes = await Task.WhenAll(tasks).WaitAsync(cancellationToken).ConfigureAwait(false);
        cancellationToken.ThrowIfCancellationRequested();
        return new RoutingWorkflowResult(request, outcomes);
    }

    private async Task<ModelRouteOutcome> RunModelAsync(
        RoutingWorkflowRequest request,
        ForecastSelection selection,
        IProgress<RoutingProgress>? progress,
        CancellationToken cancellationToken)
    {
        var model = selection.Model;
        var providerId = model.Provider();
        if (selection.Kind == ForecastSelectionKind.OfficialDownload &&
            !_providers.TryGetValue(model, out _))
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

            acquisition = selection.Kind == ForecastSelectionKind.LocalFile
                ? AcquireLocal(selection, forecastRequest, forecastProgress, cancellationToken)
                : await _providers[model]
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
                    value.Message,
                    value.Snapshot));

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

    private static ForecastAcquisition AcquireLocal(
        ForecastSelection selection,
        ForecastRequest request,
        IProgress<ForecastProgress> progress,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var local = selection.LocalForecast ??
            throw new InvalidOperationException("Local forecast metadata is missing.");
        if (request.From < local.ValidFrom || request.Through > local.ValidThrough)
        {
            throw new InvalidOperationException(
                $"The selected GRIB is valid from {local.ValidFrom:u} through {local.ValidThrough:u}, " +
                "which does not cover the requested route window.");
        }

        if (!local.Bounds.Contains(request.Bounds))
        {
            throw new InvalidOperationException(
                "The selected GRIB does not cover the buffered route region.");
        }

        progress.Report(new ForecastProgress(
            request.Provider,
            request.Model,
            ForecastProgressStage.Completed,
            1,
            "Using selected local GRIB"));
        return new ForecastAcquisition(
            request,
            new ForecastRun(request.Provider, request.Model, local.InitializedAt),
            local.Artifact,
            ForecastAcquisitionSource.LocalFile);
    }

    private static void Report(
        IProgress<RoutingProgress>? progress,
        ForecastProvider provider,
        ForecastModel model,
        RoutingProgressStage stage,
        double fraction,
        string? message = null,
        RouteCalculationSnapshot? snapshot = null) =>
        progress?.Report(new RoutingProgress(provider, model, stage, fraction, message, snapshot));

    private sealed class SynchronousProgress<T>(Action<T> report) : IProgress<T>
    {
        public void Report(T value) => report(value);
    }
}
