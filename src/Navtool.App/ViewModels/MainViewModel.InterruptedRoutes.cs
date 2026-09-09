using CommunityToolkit.Mvvm.ComponentModel;
using Microsoft.Extensions.Logging;
using Navtool.App.Models;
using Navtool.App.Services;
using Navtool.Core;

namespace Navtool.App.ViewModels;

public partial class MainViewModel
{
    private readonly InterruptedRoutePreviewTracker _routePreviews = new();
    private RoutePlanId? _previewPlanId;
    private long _previewRevision;
    private int _previewStartLeg;
    private RouteRequest? _previewRequest;
    private long _previewGeneration;
    private RouteInspectionSource[] _interruptedSources = [];

    private IEnumerable<RouteInspectionSource> InspectionSources =>
        _visualizationLegs.Where(leg => leg.HasOptimizedGeometry)
            .Select(leg => new RouteInspectionSource(leg.Route!, leg))
            .Concat(_interruptedSources);

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(HasInterruptedRoute))]
    [NotifyPropertyChangedFor(nameof(CalculationProgressDisplay))]
    private string? _interruptedRouteMessage;

    public bool HasInterruptedRoute => InterruptedRouteMessage is not null;
    public string CalculationProgressDisplay => HasInterruptedRoute ? "Stopped" : ProgressFraction.ToString("P0");

    private void BeginRoutePreviews(RouteRequest request, RoutePlanRoutingRequest? planRequest)
    {
        ClearRoutePreviews();
        _previewPlanId = Itinerary.PlanId;
        _previewRevision = Itinerary.CalculationRevision;
        _previewGeneration = Volatile.Read(ref _calculationGeneration);
        _previewStartLeg = planRequest?.StartLegIndex ?? 0;
        _previewRequest = planRequest is null ? request : new RouteRequest(request.RouteId,
            planRequest.StartOrigin, planRequest.Plan.Waypoints[_previewStartLeg + 1].Coordinate,
            planRequest.DepartureTime, planRequest.ForecastCutoff);
    }

    private void ClearRoutePreviews()
    {
        lock (_progressGate)
        {
            var hadInspection = _interruptedSources.Length > 0;
            if (HasInterruptedRoute)
            {
                StatusMessage = "Provisional path cleared; calculate again for the current itinerary.";
                LiveSearchStatus = "Native search audit is unavailable until a calculation starts. Environment diagnostics are final-only.";
            }
            _routePreviews.Clear();
            ClearRoutingMessages();
            _interruptedSources = [];
            _previewPlanId = null;
            _previewRequest = null;
            InterruptedRouteMessage = null;
            _mapLayers.ClearInterruptedRoutes();
            if (hadInspection)
            {
                CancelWeather();
                RefreshInspectionTimeline();
                UpdateWeatherAvailability();
            }
        }
    }

    private void CaptureRoutePreview(long generation, ForecastModel model, int leg, Guid? attempt,
        bool calculating, bool succeeded, string? failureMessage, RouteCalculationSnapshot? snapshot,
        RouteRequest? routeRequest = null, ForecastAcquisition? acquisition = null)
    {
        lock (_progressGate)
        {
            if (!IsCurrentCalculation(generation) || !IsCalculating ||
                _previewPlanId != Itinerary.PlanId || _previewRevision != Itinerary.CalculationRevision)
                return;

            var expectedRequest = routeRequest ?? (leg == _previewStartLeg ? _previewRequest : null);
            if (snapshot is not null && expectedRequest is { } request &&
                (!snapshot.ProvisionalRoute[0].Location.IsSameLocation(request.Origin) ||
                 snapshot.ProvisionalRoute[0].Timestamp != request.DepartureTime))
            {
                _routePreviews.Remove(model);
                _logger.LogWarning("Ignoring provisional geometry with an incorrect origin or departure for {Model}", model);
                return;
            }
            _routePreviews.Observe(model, leg, attempt, calculating, succeeded, failureMessage, snapshot,
                routeRequest, acquisition);
        }
    }

    private void PrepareInterruptedRoutes(RoutingWorkflowResult result)
    {
        foreach (var outcome in result.Outcomes)
        {
            if (outcome.Route is not null || !CanRetainPreview(outcome.Failure))
                _routePreviews.Remove(outcome.Model);
        }
        ShowInterruptedRoutes("Calculation stopped.");
    }

    private void PrepareInterruptedRoutes(RoutePlanRoutingResult result)
    {
        foreach (var preview in _routePreviews.Previews.ToArray())
        {
            var outcome = result.Models.FirstOrDefault(model => model.Model == preview.Model);
            var leg = outcome?.Legs.ElementAtOrDefault(preview.LegIndex);
            if (leg is null || leg.State is not (RouteLegOutcomeState.Failed or RouteLegOutcomeState.Cancelled) ||
                (leg.State == RouteLegOutcomeState.Failed && !CanRetainPreview(leg.Failure)))
            {
                _routePreviews.Remove(preview.Model);
                continue;
            }

            if (preview.LegIndex > _previewStartLeg)
            {
                var predecessor = outcome!.Legs[preview.LegIndex - 1];
                var first = preview.Snapshot.ProvisionalRoute[0];
                if (predecessor.Route is not { IsComplete: true } previous ||
                    !first.Location.IsSameLocation(previous.Points[^1].Location) ||
                    first.Timestamp != DateTimeOffset.FromUnixTimeSeconds(
                        (predecessor.PlannedHold?.Until ?? previous.ArrivalTime).ToUnixTimeSeconds()))
                {
                    _logger.LogWarning("Ignoring provisional geometry without a matching predecessor for {Model} leg {Leg}",
                        preview.Model, preview.LegIndex + 1);
                    _routePreviews.Remove(preview.Model);
                }
            }
        }
        ShowInterruptedRoutes(result.Status == RoutePlanRoutingStatus.Cancelled
            ? "Cancelled by user." : "Calculation stopped.");
    }

    private static bool CanRetainPreview(ModelRouteFailure? failure) =>
        failure is { Stage: ModelRouteFailureStage.RouteCalculation } &&
        failure.Kind is not (RoutingFailureKind.InvalidNativeOutput or RoutingFailureKind.InvalidForecast or
            RoutingFailureKind.InvalidBoat or RoutingFailureKind.InvalidConfiguration or
            RoutingFailureKind.MissingRequiredSource or RoutingFailureKind.NativeUnavailable);

    private void ShowInterruptedRoutes(string defaultReason)
    {
        var previews = _routePreviews.Previews.OrderBy(preview => preview.Model).ToArray();
        if (_routingMessages.RemoveAll(message => message.IsInterrupted &&
                !previews.Any(preview => preview.Model == message.Model && preview.LegIndex == message.LegIndex)) > 0)
            OnPropertyChanged(nameof(CurrentMessages));
        _interruptedSources = previews.Select(preview =>
        {
            var first = preview.Snapshot.ProvisionalRoute[0];
            var leg = Itinerary.CurrentPlan?.Legs.ElementAtOrDefault(preview.LegIndex);
            var destination = Itinerary.Waypoints.ElementAtOrDefault(preview.LegIndex + 1)?.Coordinate ??
                              _previewRequest!.Destination;
            var request = preview.Request ?? new RouteRequest(_previewRequest!.RouteId,
                first.Location, destination, first.Timestamp, _previewRequest.LatestArrivalTime);
            return new RouteInspectionSource(new InterruptedRouteInspection(
                _previewPlanId!.Value, _previewRevision, _previewGeneration,
                leg?.Id ?? new RouteLegId(), preview.LegIndex, preview.AttemptId, preview.Model,
                request, preview.Snapshot, preview.Acquisition, preview.FailureMessage ?? defaultReason));
        }).ToArray();
        _mapLayers.SetInterruptedRoutes(previews.Select(preview => (preview.Model, preview.Snapshot)));
        if (previews.Length == 0)
        {
            InterruptedRouteMessage = null;
            return;
        }
        var messages = new List<string>();
        foreach (var preview in previews)
        {
            _mapLayers.ClearCalculationOverlay(preview.Model);
            var reason = preview.FailureMessage ?? defaultReason;
            SetRoutingFailure(preview.Model, preview.LegIndex, reason, preview.Snapshot.ProvisionalRoute[^1].Location);
            // Forecast coverage appended to the native error is diagnostic context, not the stop reason.
            var coverageIndex = reason.IndexOf(" The loaded forecast covers ", StringComparison.Ordinal);
            if (coverageIndex >= 0) reason = reason[..coverageIndex];
            messages.Add($"{ModelName(preview.Model)} - leg {preview.LegIndex + 1}: {reason}");
            SetModelStatus(preview.Model, $"leg {preview.LegIndex + 1} interrupted - provisional path retained");
        }
        InterruptedRouteMessage = string.Join(Environment.NewLine, messages) +
            Environment.NewLine +
            "Incomplete: the last provisional path remains visible, not a completed route. Recalculate to try again.";
        LiveSearchStatus = "Calculation interrupted; see Messages for details.";
    }

    private void FinishInterruptedPresentation()
    {
        lock (_progressGate)
        {
            if (!HasInterruptedRoute) return;
            RefreshInspectionTimeline();
            UpdateWeatherAvailability();
            StatusMessage = "Calculation interrupted; provisional path retained.";
            _mapLayers.KeepInterruptedRoutesVisible();
        }
    }

    private void RefreshInspectionTimeline()
    {
        NotifyRouteModelAvailability();
        var sources = InspectionSources.ToArray();
        var model = ActiveRouteModel is { } active && sources.Any(source => source.Model == active)
            ? active
            : sources.OrderBy(source => source.Model).FirstOrDefault()?.Model;
        if (ActiveRouteModel != model)
            ActiveRouteModel = model;
        else
            BuildTimeline(model);
    }
}
