using System.Collections.Immutable;

namespace Navtool.Core;

public sealed record RoutingWorkflowRequest
{
    public RoutingWorkflowRequest(
        RouteRequest route,
        IEnumerable<ForecastModel> models,
        GeographicBounds? forecastBounds = null,
        ForecastRefreshPolicy refreshPolicy = ForecastRefreshPolicy.PreferCache,
        RouteOptimizationOptions? optimization = null,
        RoutingCalculationContext? calculationContext = null)
        : this(
            route,
            CreateDownloadSelections(models),
            forecastBounds,
            refreshPolicy,
            optimization,
            calculationContext)
    {
    }

    public RoutingWorkflowRequest(
        RouteRequest route,
        IEnumerable<ForecastSelection> selections,
        GeographicBounds? forecastBounds = null,
        ForecastRefreshPolicy refreshPolicy = ForecastRefreshPolicy.PreferCache,
        RouteOptimizationOptions? optimization = null,
        RoutingCalculationContext? calculationContext = null)
    {
        ArgumentNullException.ThrowIfNull(route);
        ArgumentNullException.ThrowIfNull(selections);
        if (!Enum.IsDefined(refreshPolicy))
        {
            throw new ArgumentOutOfRangeException(nameof(refreshPolicy));
        }

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

        if (route.LatestArrivalTime <= route.DepartureTime)
        {
            throw new ArgumentException("Latest arrival must be after departure.", nameof(route));
        }

        Route = route;
        Selections = immutableSelections;
        Models = immutableSelections.Select(selection => selection.Model).ToImmutableArray();
        ForecastBounds = forecastBounds ??
            (calculationContext?.Setup is { LandSource: RoutingLandSource.RegionalGshhg, RegionalLand: { } regional }
                ? regional.StudyBounds
                : ForecastCorridor.Create(route.Origin, route.Destination));
        RefreshPolicy = refreshPolicy;
        Optimization = optimization ?? calculationContext?.Resolved.Optimization ?? RouteOptimizationOptions.Balanced;
        if (calculationContext is not null && Optimization != calculationContext.Resolved.Optimization)
            throw new ArgumentException("Optimization changes must be resolved and frozen before acquisition.", nameof(optimization));
        CalculationContext = calculationContext;
    }

    public RouteRequest Route { get; }

    public ImmutableArray<ForecastModel> Models { get; }

    public ImmutableArray<ForecastSelection> Selections { get; }

    public GeographicBounds ForecastBounds { get; }

    public ForecastRefreshPolicy RefreshPolicy { get; }

    public RouteOptimizationOptions Optimization { get; }

    public RoutingCalculationContext? CalculationContext { get; }

    private static IEnumerable<ForecastSelection> CreateDownloadSelections(
        IEnumerable<ForecastModel> models)
    {
        ArgumentNullException.ThrowIfNull(models);
        return models
            .Distinct()
            .Select(ForecastSelection.OfficialDownload);
    }
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
    RouteCalculationSnapshot? Snapshot = null,
    Guid? AttemptId = null)
{
    public RouteRequest? Request { get; init; }
    public ForecastAcquisition? Acquisition { get; init; }
}

public enum ModelRouteStatus
{
    Succeeded,
    ForecastLimited,
    Failed,
    DurationLimited,
    Cancelled
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
    string Message,
    RoutingFailureKind Kind = RoutingFailureKind.Unknown,
    ImmutableArray<RouteAttemptAudit> Attempts = default);

public sealed record ModelRouteOutcome
{
    private ModelRouteOutcome(
        ForecastModel model,
        ModelRouteStatus status,
        ForecastAcquisition? acquisition,
        RouteResult? route,
        ModelRouteFailure? failure,
        string? solverFallback,
        ImmutableArray<RouteAttemptAudit> attempts = default)
    {
        Model = model;
        Provider = model.Provider();
        Status = status;
        Acquisition = acquisition;
        Route = route;
        Failure = failure;
        SolverFallback = solverFallback;
        Attempts = attempts.IsDefault ? [] : attempts;
    }

    public ForecastProvider Provider { get; }

    public ForecastModel Model { get; }

    public ModelRouteStatus Status { get; }

    public ForecastAcquisition? Acquisition { get; }

    public RouteResult? Route { get; }

    public ModelRouteFailure? Failure { get; }

    /// <summary>
    /// Set when the requested solver failed and the workflow completed the route with a
    /// different one. Callers surface this to the user because the route they received was
    /// not produced by the solver they asked for.
    /// </summary>
    public string? SolverFallback { get; }

    public ImmutableArray<RouteAttemptAudit> Attempts { get; }

    public static ModelRouteOutcome Succeeded(
        ForecastModel model,
        ForecastAcquisition acquisition,
        RouteResult route,
        string? solverFallback = null,
        ImmutableArray<RouteAttemptAudit> attempts = default) =>
        new(
            model,
            route.Completion switch
            {
                RouteCompletion.DestinationReached => ModelRouteStatus.Succeeded,
                RouteCompletion.ForecastExhausted => ModelRouteStatus.ForecastLimited,
                RouteCompletion.DurationExhausted => ModelRouteStatus.DurationLimited,
                _ => throw new ArgumentOutOfRangeException(nameof(route.Completion))
            },
            acquisition,
            route,
            null,
            solverFallback,
            attempts);

    public static ModelRouteOutcome Failed(
        ForecastModel model,
        ModelRouteFailureStage stage,
        string code,
        string message,
        ForecastAcquisition? acquisition = null,
        RoutingFailureKind kind = RoutingFailureKind.Unknown,
        ImmutableArray<RouteAttemptAudit> attempts = default) =>
        new(
            model,
            kind == RoutingFailureKind.Cancelled ? ModelRouteStatus.Cancelled : ModelRouteStatus.Failed,
            acquisition,
            null,
            new ModelRouteFailure(stage, code, message, kind, attempts),
            null,
            attempts);
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
        if (request.CalculationContext is not null && _routeEngine is not IConfiguredRouteEngine)
            throw new RoutingException(RoutingFailureKind.InvalidConfiguration,
                "The route engine cannot apply the frozen routing setup.");

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
        var attempts = new List<RouteAttemptAudit>();
        var failureStage = ModelRouteFailureStage.ForecastAcquisition;
        try
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (request.CalculationContext?.Setup is { LandSource: RoutingLandSource.RegionalGshhg } regionalSetup &&
                (!regionalSetup.RegionalLand!.StudyBounds.Contains(request.ForecastBounds) ||
                 !regionalSetup.RegionalLand.StudyBounds.Contains(request.Route.Origin) ||
                 !regionalSetup.RegionalLand.StudyBounds.Contains(request.Route.Destination)))
                throw new RoutingException(RoutingFailureKind.MissingRequiredSource,
                    "The selected regional land study domain does not cover the declared search bounds and endpoints. " +
                    "Expand the explicit domain or change the source; routing will not silently clip bounds or allow unknown water.");
            Report(progress, providerId, model, RoutingProgressStage.AcquiringForecast, 0);
            var forecastRequest = new ForecastRequest(
                model,
                request.ForecastBounds,
                request.Route.DepartureTime,
                request.Route.LatestArrivalTime,
                request.RefreshPolicy);
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
            if (acquisition.Coverage is { } coverage)
            {
                ForecastTimePolicy.Validate(acquisition.Run, coverage.ValidTimes,
                    selection.Kind == ForecastSelectionKind.OfficialDownload,
                    request.CalculationContext?.Setup.LocalForecastMaximumGap ?? coverage.MaximumInterpolationGap);
                if (request.Route.DepartureTime < coverage.ValidFrom || request.Route.DepartureTime > coverage.ValidThrough ||
                    !coverage.EffectiveBounds.Contains(request.ForecastBounds))
                    throw new RoutingException(RoutingFailureKind.InvalidForecast,
                        "The loaded forecast does not cover the departure time and declared search corridor.");
            }

            failureStage = ModelRouteFailureStage.RouteCalculation;
            Report(progress, providerId, model, RoutingProgressStage.CalculatingRoute, 0.5,
                request: request.Route, acquisition: acquisition);
            // Route calculation occupies the upper half of the bar. Clamp to the highest
            // fraction reported so far so progress never runs backwards: the fallback below
            // re-runs the engine from zero, and a raw projection would rewind the bar.
            var highestFraction = 0.5;
            var attemptId = Guid.NewGuid();
            var routeProgress = new SynchronousProgress<RouteCalculationProgress>(value =>
            {
                highestFraction = Math.Max(highestFraction, 0.5 + (value.Fraction * 0.5));
                Report(
                    progress,
                    providerId,
                    model,
                    RoutingProgressStage.CalculatingRoute,
                    highestFraction,
                    value.Message,
                    value.Snapshot,
                    attemptId,
                    request.Route,
                    acquisition);
            });

            async ValueTask<RouteResult> CalculateAsync(RouteOptimizationOptions options)
            {
                var started = DateTimeOffset.UtcNow;
                try
                {
                    var result = request.CalculationContext is { } context
                        ? await ((IConfiguredRouteEngine)_routeEngine).CalculateConfiguredAsync(context,
                            request.Route, acquisition, options, routeProgress, cancellationToken).ConfigureAwait(false)
                        : await _routeEngine.CalculateAsync(request.Route, acquisition, options,
                            routeProgress, cancellationToken).ConfigureAwait(false);
                    attempts.Add(new RouteAttemptAudit(attemptId, options.Solver, started, DateTimeOffset.UtcNow));
                    return result;
                }
                catch (Exception exception)
                {
                    attempts.Add(new RouteAttemptAudit(attemptId, options.Solver, started, DateTimeOffset.UtcNow,
                        Classify(exception), exception.Message));
                    throw;
                }
            }

            RouteResult route;
            string? solverFallback = null;
            try
            {
                route = await CalculateAsync(request.Optimization).ConfigureAwait(false);
            }
            catch (RoutingException solverException)
                when (!cancellationToken.IsCancellationRequested &&
                      solverException.Kind == RoutingFailureKind.RecoverableSolver &&
                      request.Optimization.Solver == RouteSolver.TimeDependentLattice)
            {
                // Only an explicit recoverable search failure authorizes one beam attempt.
                var fallbackOptions = request.Optimization.WithSolver(FallbackSolver);
                solverFallback =
                    $"The {Describe(request.Optimization.Solver)} solver could not complete this route " +
                    $"({solverException.Message}) so the {Describe(FallbackSolver)} solver was used instead.";
                Report(
                    progress,
                    providerId,
                    model,
                    RoutingProgressStage.CalculatingRoute,
                    highestFraction,
                    solverFallback,
                    request: request.Route,
                    acquisition: acquisition);

                attemptId = Guid.NewGuid();
                route = await CalculateAsync(fallbackOptions).ConfigureAwait(false);
            }

            cancellationToken.ThrowIfCancellationRequested();
            failureStage = ModelRouteFailureStage.ResultValidation;
            if (route.Model != model || route.Request != request.Route)
            {
                throw new RoutingException(RoutingFailureKind.InvalidNativeOutput, "The route engine returned a route for a different request or model.");
            }
            if (!route.Points[0].Location.IsSameLocation(request.Route.Origin) ||
                route.Points[0].Timestamp != request.Route.DepartureTime)
                throw new RoutingException(RoutingFailureKind.InvalidNativeOutput,
                    "The accepted route must begin at the requested physical origin and departure.");
            if (request.CalculationContext is { } frozen)
            {
                var actualSolver = attempts[^1].Solver;
                if (route.Solver != actualSolver || route.NativeAudit is not { Schema: "route_result_v2" } native ||
                    native.Solver != actualSolver || native.Routing is not { } observed)
                    throw new RoutingException(RoutingFailureKind.InvalidNativeOutput, "Missing or mismatched native v2 run audit.");
                if (native.EffectiveArrivalRadiusNauticalMiles is { } effectiveRadius &&
                    Math.Abs(effectiveRadius - frozen.Resolved.ArrivalRadiusNauticalMiles) > 1e-9 ||
                    native.HardDuration is { } hardDuration && frozen.Resolved.HardDuration is { } requestedDuration &&
                    hardDuration != requestedDuration)
                    throw new RoutingException(RoutingFailureKind.InvalidNativeOutput, "The native result audit contradicts the resolved request settings.");
                if (Math.Abs(observed.ArrivalRadiusNauticalMiles - frozen.Resolved.ArrivalRadiusNauticalMiles) > 1e-9 ||
                    Math.Abs(observed.BoatSpeedFactor - frozen.Resolved.PerformanceFactor) > 1e-9 ||
                    Math.Abs(observed.HeadingStepDegrees - frozen.Resolved.Search.HeadingStepDegrees) > 1e-9 ||
                    Math.Abs(observed.SpatialBucketNauticalMiles - frozen.Resolved.Search.SpatialBucketNauticalMiles) > 1e-9 ||
                    observed.MaximumIntegrationStep != frozen.Resolved.Search.MaximumIntegrationStep ||
                    observed.StrategicRetention != frozen.Resolved.Search.StrategicRetention ||
                    observed.WindSampling != request.Optimization.WindSampling ||
                    observed.AbovePolarRange != request.Optimization.AbovePolarRange ||
                    observed.MaximumForecastWindKnots != request.Optimization.MaximumTrueWindSpeedKnots ||
                    observed.TackPenalty != request.Optimization.Maneuver.TackPenalty ||
                    observed.GybePenalty != request.Optimization.Maneuver.GybePenalty ||
                    observed.ForecastInitialization != acquisition.Run.InitializedAt ||
                    observed.ForecastFirstValid > request.Route.DepartureTime ||
                    observed.ForecastLastValid < route.ArrivalTime)
                    throw new RoutingException(RoutingFailureKind.InvalidNativeOutput,
                        "Observed native numerical, polar, or forecast settings contradict the frozen calculation.");
                if (route.IsComplete &&
                    ForecastCorridor.GreatCircleDistanceNauticalMiles(route.Points[^1].Location, request.Route.Destination) >
                    frozen.Resolved.ArrivalRadiusNauticalMiles + 1e-6)
                    throw new RoutingException(RoutingFailureKind.InvalidNativeOutput, "The arrived endpoint lies outside the resolved arrival radius.");
                var engineAudit = route.RunAudit;
                var engineForecast = engineAudit?.Forecast;
                if (engineAudit is not null &&
                    (engineAudit.CalculationId != frozen.CalculationId || engineAudit.Setup != frozen.Setup ||
                     engineAudit.NativeIdentity != frozen.NativeIdentity))
                    throw new RoutingException(RoutingFailureKind.InvalidNativeOutput,
                        "The engine run audit belongs to a different frozen calculation.");
                if (engineForecast is not null &&
                    (engineForecast.Run != acquisition.Run || engineForecast.DeclaredBounds != request.ForecastBounds ||
                     engineForecast.ValidFrom != observed.ForecastFirstValid ||
                     engineForecast.ValidThrough != observed.ForecastLastValid))
                    throw new RoutingException(RoutingFailureKind.InvalidNativeOutput,
                        "The engine forecast audit contradicts the native routing metadata or request.");
                var loadedCoverage = native.ForecastCoverage ??
                    (engineForecast is { EffectiveBounds: { } effectiveBounds, ValidTimes.IsDefaultOrEmpty: false }
                        ? new ForecastCoverage(effectiveBounds, engineForecast.ValidTimes, engineForecast.MaximumInterpolationGap)
                        : acquisition.Coverage);
                if (loadedCoverage is not null)
                {
                    ForecastTimePolicy.Validate(acquisition.Run, loadedCoverage.ValidTimes,
                        selection.Kind == ForecastSelectionKind.OfficialDownload,
                        frozen.Setup.LocalForecastMaximumGap);
                    if (!loadedCoverage.EffectiveBounds.Contains(request.ForecastBounds) ||
                        loadedCoverage.ValidFrom != observed.ForecastFirstValid ||
                        loadedCoverage.ValidThrough != observed.ForecastLastValid)
                        throw new RoutingException(RoutingFailureKind.InvalidNativeOutput,
                            "The native loaded coverage contradicts its routing metadata or declared corridor.");
                }
                var effectiveOptions = frozen.Resolved with { Optimization = request.Optimization.WithSolver(actualSolver) };
                var audit = new RouteRunAudit(frozen.CalculationId, frozen.Setup,
                    effectiveOptions,
                    frozen.NativeIdentity, request.Optimization.Solver, attempts,
                    forecast: engineForecast ?? new RouteForecastAudit(acquisition.Run, request.ForecastBounds,
                        loadedCoverage?.EffectiveBounds ?? selection.LocalForecast?.Bounds,
                        observed.ForecastFirstValid,
                        observed.ForecastLastValid,
                        loadedCoverage?.MaximumInterpolationGap ??
                            (selection.Kind == ForecastSelectionKind.LocalFile ? frozen.Setup.LocalForecastMaximumGap : null),
                        loadedCoverage?.MinimumTimeSpacing,
                        loadedCoverage?.MaximumTimeSpacing,
                        loadedCoverage?.ValidTimes ?? []),
                    native: native, professionalOverrides: frozen.ProfessionalOverrides,
                    applicationLand: route.LandAvoidance);
                route = route.WithRunAudit(engineAudit?.Forecast is not null
                    ? engineAudit.WithAttempts(request.Optimization.Solver, attempts, effectiveOptions, route.LandAvoidance)
                    : audit);
            }

            Report(progress, providerId, model, RoutingProgressStage.Completed, 1);
            return ModelRouteOutcome.Succeeded(model, acquisition, route, solverFallback, attempts.ToImmutableArray());
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception exception)
        {
            if (failureStage == ModelRouteFailureStage.ResultValidation && attempts.Count > 0)
                attempts[^1] = attempts[^1] with
                {
                    FailureKind = RoutingFailureKind.InvalidNativeOutput,
                    FailureMessage = exception.Message
                };
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
                acquisition,
                failureStage == ModelRouteFailureStage.ResultValidation
                    ? RoutingFailureKind.InvalidNativeOutput : Classify(exception),
                attempts.ToImmutableArray());
        }

    }

    private static RoutingFailureKind Classify(Exception exception) => exception switch
    {
        RoutingException routing => routing.Kind,
        OperationCanceledException => RoutingFailureKind.Cancelled,
        OutOfMemoryException => RoutingFailureKind.ResourceLimit,
        _ => RoutingFailureKind.Unknown
    };

    /// <summary>
    /// The solver the workflow falls back to when the requested solver fails. The isochrone
    /// beam is the most robust of the available solvers and degrades to a partial route
    /// instead of erroring when it cannot reach the destination.
    /// </summary>
    private const RouteSolver FallbackSolver = RouteSolver.IsochroneBeam;

    private static string Describe(RouteSolver solver) => solver switch
    {
        RouteSolver.IsochroneBeam => "isochrone beam",
        RouteSolver.TimeDependentLattice => "time-dependent lattice",
        _ => solver.ToString()
    };

    private static ForecastAcquisition AcquireLocal(
        ForecastSelection selection,
        ForecastRequest request,
        IProgress<ForecastProgress> progress,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var local = selection.LocalForecast ??
            throw new InvalidOperationException("Local forecast metadata is missing.");
        if (request.From < local.ValidFrom || request.From > local.ValidThrough)
        {
            throw new InvalidOperationException(
                $"The selected GRIB is valid from {local.ValidFrom:u} through {local.ValidThrough:u}, " +
                $"which does not include the requested departure {request.From:u}.");
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
        RouteCalculationSnapshot? snapshot = null,
        Guid? attemptId = null,
        RouteRequest? request = null,
        ForecastAcquisition? acquisition = null) =>
        progress?.Report(new RoutingProgress(
            provider, model, stage, fraction, message, snapshot, attemptId)
        {
            Request = request,
            Acquisition = acquisition
        });

    private sealed class SynchronousProgress<T>(Action<T> report) : IProgress<T>
    {
        public void Report(T value) => report(value);
    }
}
