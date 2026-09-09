using CommunityToolkit.Mvvm.ComponentModel;
using Microsoft.Extensions.Logging;
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
        _previewStartLeg = planRequest?.StartLegIndex ?? 0;
        _previewRequest = planRequest is null ? request : new RouteRequest(request.RouteId,
            planRequest.StartOrigin, planRequest.Plan.Waypoints[_previewStartLeg + 1].Coordinate,
            planRequest.DepartureTime, planRequest.ForecastCutoff);
    }

    private void ClearRoutePreviews()
    {
        lock (_progressGate)
        {
            if (HasInterruptedRoute)
            {
                StatusMessage = "Provisional path cleared; calculate again for the current itinerary.";
                LiveSearchStatus = "Native search audit is unavailable until a calculation starts. Environment diagnostics are final-only.";
            }
            _routePreviews.Clear();
            _previewPlanId = null;
            _previewRequest = null;
            InterruptedRouteMessage = null;
            _mapLayers.ClearInterruptedRoutes();
        }
    }

    private void CaptureRoutePreview(long generation, ForecastModel model, int leg, Guid? attempt,
        bool calculating, bool succeeded, string? failureMessage, RouteCalculationSnapshot? snapshot)
    {
        lock (_progressGate)
        {
            if (!IsCurrentCalculation(generation) || !IsCalculating ||
                _previewPlanId != Itinerary.PlanId || _previewRevision != Itinerary.CalculationRevision)
                return;

            if (snapshot is not null && leg == _previewStartLeg && _previewRequest is { } request &&
                (!snapshot.ProvisionalRoute[0].Location.IsSameLocation(request.Origin) ||
                 snapshot.ProvisionalRoute[0].Timestamp != request.DepartureTime))
            {
                _routePreviews.Remove(model);
                _logger.LogWarning("Ignoring provisional geometry with an incorrect origin or departure for {Model}", model);
                return;
            }
            _routePreviews.Observe(model, leg, attempt, calculating, succeeded, failureMessage, snapshot);
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
            // Forecast coverage appended to the native error is diagnostic context, not the stop reason.
            var coverageIndex = reason.IndexOf(" The loaded forecast covers ", StringComparison.Ordinal);
            if (coverageIndex >= 0) reason = reason[..coverageIndex];
            messages.Add($"{ModelName(preview.Model)} - leg {preview.LegIndex + 1}: {reason}");
            SetModelStatus(preview.Model, $"leg {preview.LegIndex + 1} interrupted - provisional path retained");
        }
        InterruptedRouteMessage = string.Join(Environment.NewLine, messages) +
            Environment.NewLine +
            "Incomplete: the last provisional path remains visible, not a completed route. Recalculate to try again.";
        LiveSearchStatus = InterruptedRouteMessage;
    }

    private void FinishInterruptedPresentation()
    {
        if (!HasInterruptedRoute) return;
        StatusMessage = "Calculation interrupted; provisional path retained.";
        _mapLayers.KeepInterruptedRoutesVisible();
    }
}
