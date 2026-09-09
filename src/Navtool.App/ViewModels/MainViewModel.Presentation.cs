using CommunityToolkit.Mvvm.ComponentModel;
using Navtool.App.Services;
using Navtool.Core;

namespace Navtool.App.ViewModels;

public partial class MainViewModel
{
    [ObservableProperty]
    private bool _weatherOnlyMode;

    public string CalculationReadiness
    {
        get
        {
            if (IsCalculating) return "Calculation in progress. Cancel before starting another.";
            if (IsInspectingLocalGrib) return "Inspecting the selected forecast file.";
            if (Itinerary.Waypoints.Any(point => point.Coordinate is null))
                return "Set every waypoint, including Start and Finish.";
            if (!RoutingSetup.TryBuild(out _, out var setupError)) return setupError!;
            if (!TryGetPassageDuration(out _, out var durationError)) return durationError!;
            if (!DepartureNow && !Itinerary.HasCurrentPosition &&
                !LocalDepartureConverter.TryConvertToUtc(DepartureDate, DepartureTime, _localTimeZone, out _, out var departureError))
                return departureError!;
            if (!UseNoaa && !UseEcmwf) return "Select at least one forecast model.";
            if (IsLocalForecast && LocalGribPath is null && LocalForecast is null)
                return "Choose a local GRIB file.";
            if (Itinerary.CurrentPlan?.IsItineraryComplete is true) return "All legs are sailed. Unmark a leg to calculate again.";
            if (_workflow is null) return "Routing services are unavailable in the designer.";
            return Itinerary.ResultsInvalidated
                ? "Inputs changed. Calculate to update the route."
                : "Ready to calculate. Boat, land and forecast coverage are checked before routing.";
        }
    }

    public string SelectedRouteSummary
    {
        get
        {
            var route = SelectedRoutePoint?.Route ?? SelectedLeg?.Route;
            if (route is null) return "Select a calculated route or leg.";
            var state = route.IsForecastLimited ? "Incomplete: forecast ended"
                : route.IsDurationLimited ? "Incomplete: duration limit" : "Destination reached";
            return $"{state} · {route.Points[^1].CumulativeDistanceNauticalMiles:0.0} NM · " +
                $"{FormatDuration(route.ArrivalTime - route.Request.DepartureTime)}\n" +
                $"Arrival {TimeZoneInfo.ConvertTime(route.ArrivalTime, _localTimeZone):MMM d HH:mm} local / " +
                $"{route.ArrivalTime:HH:mm} UTC";
        }
    }

    partial void OnWeatherOnlyModeChanged(bool value)
    {
        UpdateWeatherAvailability();
        if (!value) BuildTimeline(ActiveRouteModel);
        OnPropertyChanged(nameof(TimelineDisplay));
        PreviousTimelineCommand.NotifyCanExecuteChanged();
        NextTimelineCommand.NotifyCanExecuteChanged();
    }

    private ForecastAcquisition? WeatherOnlyAcquisition(ForecastModel? model) =>
        model is { } selected && _acquisitions.TryGetValue(selected, out var acquisitions)
            ? acquisitions.OrderByDescending(item => item.Request.From).FirstOrDefault()
            : null;

    private void SetWeatherTimeline(DateTimeOffset timestamp)
    {
        if (WeatherOnlyAcquisition(ActiveWeatherModel) is not { } acquisition) return;
        var from = acquisition.Request.From;
        var through = acquisition.Request.Through;
        SelectedTimelineUtc = timestamp < from ? from : timestamp > through ? through : timestamp;
        _updatingTimelinePosition = true;
        TimelinePosition = through == from ? 0 : (SelectedTimelineUtc.Value - from).Ticks / (double)(through - from).Ticks;
        _updatingTimelinePosition = false;
        HasTimeline = true;
        RequestWeatherRefreshFromViewport();
    }
}
