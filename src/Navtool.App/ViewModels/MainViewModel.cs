using System.Collections.Immutable;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using Mapsui;
using Mapsui.Extensions;
using Mapsui.Manipulations;
using Mapsui.Styles;
using Mapsui.Tiling;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Logging.Abstractions;
using Navtool.App.Models;
using Navtool.App.Services;
using Navtool.Core;
using Navtool.Infrastructure;

namespace Navtool.App.ViewModels;

public enum ForecastInputMode
{
    Download,
    LocalFile
}

public partial class MainViewModel : ViewModelBase
{
    private const double RouteHitTolerancePixels = 10;
    private const double RoutePointHitTolerancePixels = 14;
    private static readonly TimeSpan MaximumRouteWindow = TimeSpan.FromDays(10);
    private static readonly TimeSpan MaximumDepartureLeadTime = TimeSpan.FromDays(5);
    private static readonly TimeSpan WeatherDebounce = TimeSpan.FromMilliseconds(220);
    private readonly MapInteractionState _interaction = new();
    private readonly RouteMapLayers _mapLayers;
    private readonly RoutingWorkflow? _workflow;
    private readonly IWeatherSampler? _weatherSampler;
    private readonly ILocalGribInspector? _localGribInspector;
    private readonly INativeRoutingPreflight? _nativeRoutingPreflight;
    private readonly NoaaGfsForecastProvider? _noaaProvider;
    private readonly TimeProvider _timeProvider;
    private readonly TimeZoneInfo _localTimeZone;
    private readonly ILogger<MainViewModel> _logger;
    private readonly Dictionary<ForecastModel, double> _modelProgress = new();
    private readonly Dictionary<ForecastModel, ForecastAcquisition> _acquisitions = new();
    private readonly object _progressGate = new();
    private CancellationTokenSource? _calculationCancellation;
    private CancellationTokenSource? _weatherCancellation;
    private CancellationTokenSource? _inspectionCancellation;
    private SharedRouteTimeline? _timeline;
    private long _calculationGeneration;
    private long _weatherGeneration;
    private bool _updatingTimelinePosition;

    [ObservableProperty]
    private DateTimeOffset? _departureDate = DateTimeOffset.Now.Date;

    [ObservableProperty]
    private TimeSpan? _departureTime = DateTimeOffset.Now.TimeOfDay;

    [ObservableProperty]
    private int _passageDays = 3;

    [ObservableProperty]
    private int _passageHours;

    [ObservableProperty]
    private ForecastInputMode _forecastInputMode;

    [ObservableProperty]
    [NotifyCanExecuteChangedFor(nameof(CalculateCommand))]
    [NotifyCanExecuteChangedFor(nameof(CancelCommand))]
    private bool _isInspectingLocalGrib;

    [ObservableProperty]
    private LocalForecastDescriptor? _localForecast;

    [ObservableProperty]
    private string _localGribStatus = "Choose a GRIB file to inspect.";

    [ObservableProperty]
    private string _forecastAreaSummary = "Set both endpoints to estimate the forecast download.";

    [ObservableProperty]
    private bool _useNoaa = true;

    [ObservableProperty]
    private bool _useEcmwf;

    [ObservableProperty]
    [NotifyCanExecuteChangedFor(nameof(CalculateCommand))]
    [NotifyCanExecuteChangedFor(nameof(CancelCommand))]
    private bool _isCalculating;

    [ObservableProperty]
    private double _progressFraction;

    [ObservableProperty]
    private string _statusMessage = "Set a start and destination to prepare a route.";

    [ObservableProperty]
    private string? _errorMessage;

    [ObservableProperty]
    private string? _weatherLayerError;

    [ObservableProperty]
    private string _noaaStatus = "Ready";

    [ObservableProperty]
    private string _ecmwfStatus = "Experimental · not selected";

    [ObservableProperty]
    private RouteMapSelection? _selectedRoutePoint;

    [ObservableProperty]
    private double _timelinePosition;

    [ObservableProperty]
    [NotifyCanExecuteChangedFor(nameof(PreviousTimelineCommand))]
    [NotifyCanExecuteChangedFor(nameof(NextTimelineCommand))]
    private bool _hasTimeline;

    [ObservableProperty]
    private DateTimeOffset? _selectedTimelineUtc;

    [ObservableProperty]
    private ForecastModel? _activeWeatherModel;

    [ObservableProperty]
    private bool _hasNoaaWeather;

    [ObservableProperty]
    private bool _hasEcmwfWeather;

    public MainViewModel()
        : this(null, null, TimeProvider.System, TimeZoneInfo.Local, new OsmTileOptions())
    {
    }

    public MainViewModel(RoutingWorkflow workflow, IWeatherSampler weatherSampler)
        : this(
            workflow,
            weatherSampler,
            TimeProvider.System,
            TimeZoneInfo.Local,
            new OsmTileOptions())
    {
    }

    public MainViewModel(
        RoutingWorkflow workflow,
        IWeatherSampler weatherSampler,
        ILocalGribInspector localGribInspector,
        INativeRoutingPreflight nativeRoutingPreflight,
        NoaaGfsForecastProvider noaaProvider,
        ILogger<MainViewModel> logger)
        : this(
            workflow,
            weatherSampler,
            TimeProvider.System,
            TimeZoneInfo.Local,
            new OsmTileOptions(),
            logger,
            localGribInspector,
            nativeRoutingPreflight,
            noaaProvider)
    {
    }

    public MainViewModel(
        RoutingWorkflow? workflow,
        IWeatherSampler? weatherSampler,
        TimeProvider timeProvider,
        TimeZoneInfo localTimeZone,
        OsmTileOptions tileOptions,
        ILogger<MainViewModel>? logger = null,
        ILocalGribInspector? localGribInspector = null,
        INativeRoutingPreflight? nativeRoutingPreflight = null,
        NoaaGfsForecastProvider? noaaProvider = null)
    {
        ArgumentNullException.ThrowIfNull(timeProvider);
        ArgumentNullException.ThrowIfNull(localTimeZone);
        ArgumentNullException.ThrowIfNull(tileOptions);
        _workflow = workflow;
        _weatherSampler = weatherSampler;
        _localGribInspector = localGribInspector;
        _nativeRoutingPreflight = nativeRoutingPreflight;
        _noaaProvider = noaaProvider;
        _timeProvider = timeProvider;
        _localTimeZone = localTimeZone;
        _logger = logger ?? NullLogger<MainViewModel>.Instance;

        Map = new Map
        {
            CRS = "EPSG:3857",
            BackColor = Color.FromString("#DDE7EC")
        };
        Map.Navigator.MouseWheelAnimation.UseContinuousMouseWheelZoom = true;
        var osmLayer = OpenStreetMap.CreateTileLayer(tileOptions.UserAgent);
        osmLayer.Enabled = tileOptions.Enabled;
        osmLayer.Name = "OpenStreetMap";
        Map.Layers.Add(osmLayer);

        _mapLayers = new RouteMapLayers(Map);
        UtcOffsetDisplay = FormatUtcOffset(localTimeZone.GetUtcOffset(timeProvider.GetLocalNow()));
        Map.Navigator.CenterOnAndZoomTo(
            MapProjection.ToMapPoint(new Coordinate(35, -55)),
            25_000);
        UpdateForecastAreaSummary();
    }

    public event EventHandler<RouteMapSelection?>? RouteSelectionChanged;

    public Map Map { get; }

    public string UtcOffsetDisplay { get; }

    public MapInteractionMode InteractionMode => _interaction.Mode;

    public Coordinate? Start => _interaction.Start;

    public Coordinate? Destination => _interaction.Destination;

    public string StartDisplay => FormatCoordinate(Start, "Not set");

    public string DestinationDisplay => FormatCoordinate(Destination, "Not set");

    public bool IsDownloadForecast => ForecastInputMode == ForecastInputMode.Download;

    public bool IsLocalForecast => ForecastInputMode == ForecastInputMode.LocalFile;

    public string LocalGribDisplay => LocalForecast is null
        ? "No file selected"
        : $"{Path.GetFileName(LocalForecast.Artifact.Path)} · {ModelName(LocalForecast.Model)}\n" +
          $"Run {LocalForecast.InitializedAt:yyyy-MM-dd HH:mm} UTC · " +
          $"valid through {LocalForecast.ValidThrough:yyyy-MM-dd HH:mm} UTC\n" +
          FormatBounds(LocalForecast.Bounds);

    public string MapInstruction => InteractionMode switch
    {
        MapInteractionMode.SetStart => "Click the map to place the start",
        MapInteractionMode.SetDestination => "Click the map to place the destination",
        _ => "Pan and zoom, or select an endpoint tool"
    };

    public string SelectedRouteTitle => SelectedRoutePoint is null
        ? "No route point selected"
        : $"{ModelName(SelectedRoutePoint.Route.Model)} · point {SelectedRoutePoint.PointIndex + 1}";

    public string SelectedRouteDetails
    {
        get
        {
            if (SelectedRoutePoint is null)
            {
                return "Click near a displayed route to inspect its nearest point.";
            }

            var selection = SelectedRoutePoint;
            var point = selection.Point;
            _acquisitions.TryGetValue(selection.Route.Model, out var acquisition);
            var forecast = acquisition is null
                ? "forecast metadata unavailable"
                : $"run {acquisition.Run.InitializedAt:yyyy-MM-dd HH:mm} UTC · " +
                  $"{acquisition.Source} · {acquisition.Artifact.Path}";
            return $"{point.Timestamp:yyyy-MM-dd HH:mm:ss} UTC\n" +
                   $"{point.Location.Latitude:0.0000}°, {point.Location.Longitude:0.0000}° · " +
                   $"heading {point.HeadingDegrees:0}° · boat {point.BoatSpeedKnots:0.0} kt\n" +
                   $"true wind {point.TrueWindSpeedKnots:0.0} kt @ {point.TrueWindDirectionDegrees:0}° · " +
                   $"cumulative {point.CumulativeDistanceNauticalMiles:0.0} NM\n" +
                   $"{ModelName(selection.Route.Model)} · arrival {selection.Route.ArrivalTime:yyyy-MM-dd HH:mm} UTC · " +
                   $"distance {selection.Route.Points[^1].CumulativeDistanceNauticalMiles:0.0} NM · {forecast}";
        }
    }

    public string TimelineDisplay => SelectedTimelineUtc is null
        ? "Timeline unavailable"
        : $"{SelectedTimelineUtc:yyyy-MM-dd HH:mm:ss} UTC";

    public string ActiveWeatherDisplay => ActiveWeatherModel is null
        ? "No weather overlay"
        : $"{ModelName(ActiveWeatherModel.Value)} wind · knots";

    public bool IsNoaaWeatherActive => ActiveWeatherModel == ForecastModel.NoaaGfs;

    public bool IsEcmwfWeatherActive => ActiveWeatherModel == ForecastModel.EcmwfIfs;

    public int WeatherCellCount => _mapLayers.WeatherCellCount;

    public int SuccessfulRouteCount => _mapLayers.Routes.Count;

    public IReadOnlyList<RouteResult> SuccessfulRoutes => _mapLayers.Routes;

    public void SetEndpoints(Coordinate start, Coordinate destination)
    {
        _interaction.Activate(MapInteractionMode.SetStart);
        _interaction.HandleMapClick(start);
        _interaction.Activate(MapInteractionMode.SetDestination);
        _interaction.HandleMapClick(destination);
        _mapLayers.SetEndpoints(start, destination);
        NotifyInteractionChanged();
    }

    public void DisplayRoutes(IEnumerable<RouteResult> routes)
    {
        var successful = routes.ToArray();
        _mapLayers.SetRoutes(successful);
        _mapLayers.FitRoutes();
        OnPropertyChanged(nameof(SuccessfulRouteCount));
        BuildTimeline(successful);
        StatusMessage = successful.Length == 0
            ? "No routes are currently displayed."
            : $"{successful.Length} route{(successful.Length == 1 ? string.Empty : "s")} displayed.";
    }

    public void HandleMapClick(MPoint worldPosition, ScreenPosition screenPosition)
    {
        var coordinate = MapProjection.ToCoordinate(worldPosition);
        if (_interaction.HandleMapClick(coordinate))
        {
            _mapLayers.SetEndpoints(Start, Destination);
            NotifyInteractionChanged();
            StatusMessage = Start is not null && Destination is not null
                ? "Endpoints ready. Choose forecast models and calculate."
                : "Endpoint placed. Set the remaining endpoint.";
            return;
        }

        var viewport = Map.Navigator.Viewport;
        var hit = RouteHitTester.FindNearest(
            _mapLayers.Routes,
            (RouteResult route) => MapProjection
                .ToContinuousMapPointsNear(
                    route.Points.Select(point => point.Location),
                    worldPosition.X)
                .Select(point =>
                {
                    var projected = viewport.WorldToScreen(point);
                    return new ScreenPoint(projected.X, projected.Y);
                })
                .ToArray(),
            new ScreenPoint(screenPosition.X, screenPosition.Y),
            RouteHitTolerancePixels,
            RoutePointHitTolerancePixels);
        if (hit is not null)
        {
            SelectRoutePoint(hit, focus: true);
        }
    }

    public void SelectRoutePoint(RouteMapSelection selection, bool focus = true)
    {
        ArgumentNullException.ThrowIfNull(selection);
        if (_timeline is not null)
        {
            SetTimelineUtc(selection.TimelineTimestamp);
        }

        if (_acquisitions.ContainsKey(selection.Route.Model))
        {
            ActiveWeatherModel = selection.Route.Model;
        }

        SelectedRoutePoint = selection;
        ApplyTimelineSelection(selection.Route.Model);
        if (focus)
        {
            FocusSelectedRoutePoint();
        }
    }

    public async Task CalculateRoutesAsync()
    {
        ErrorMessage = null;
        WeatherLayerError = null;
        if (_workflow is null)
        {
            ErrorMessage = "Routing services are unavailable in the designer.";
            return;
        }

        if (ForecastInputMode == ForecastInputMode.LocalFile && LocalForecast is not null)
        {
            var inspectionGeneration = Volatile.Read(ref _calculationGeneration);
            await SelectLocalGribAsync(LocalForecast.Artifact.Path);
            if (LocalForecast is null ||
                inspectionGeneration != Volatile.Read(ref _calculationGeneration))
            {
                return;
            }
        }

        if (!TryCreateWorkflowRequest(out var request, out var validationError))
        {
            ErrorMessage = validationError;
            return;
        }

        try
        {
            _nativeRoutingPreflight?.EnsureAvailable();
        }
        catch (Exception exception)
        {
            _logger.LogError(exception, "Native routing preflight failed");
            ErrorMessage = $"Routing engine unavailable: {exception.Message}";
            StatusMessage = "No forecast was downloaded.";
            return;
        }

        var generation = Interlocked.Increment(ref _calculationGeneration);
        var cancellation = new CancellationTokenSource();
        var previous = Interlocked.Exchange(ref _calculationCancellation, cancellation);
        previous?.Cancel();
        previous?.Dispose();
        CancelWeather();

        IsCalculating = true;
        ProgressFraction = 0;
        StatusMessage = "Starting forecast acquisition and route calculations…";
        _mapLayers.ClearCalculationOverlays();
        _modelProgress.Clear();
        foreach (var model in request!.Models)
        {
            _modelProgress[model] = 0;
            SetModelStatus(model, IsExperimentalDownload(request, model)
                ? "Experimental · queued"
                : "Queued");
        }

        var progress = new Progress<RoutingProgress>(value =>
        {
            if (!IsCurrentCalculation(generation) || !IsCalculating)
            {
                return;
            }

            lock (_progressGate)
            {
                _modelProgress[value.Model] = value.Fraction;
                ProgressFraction = _modelProgress.Values.Average();
            }
            SetModelStatus(
                value.Model,
                $"{(IsExperimentalDownload(request, value.Model) ? "Experimental · " : string.Empty)}" +
                $"{ProgressStageName(value.Stage)} {value.Fraction:P0}" +
                $"{(string.IsNullOrWhiteSpace(value.Message) ? string.Empty : $" · {value.Message}")}");
            if (value.Snapshot is not null)
            {
                _mapLayers.AddCalculationSnapshot(value.Model, value.Snapshot);
            }
            else if (value.Stage == RoutingProgressStage.Failed)
            {
                _mapLayers.ClearCalculationOverlay(value.Model);
            }
        });

        try
        {
            var result = await _workflow.ExecuteAsync(request, progress, cancellation.Token);
            if (!IsCurrentCalculation(generation))
            {
                return;
            }

            ApplyWorkflowResult(result);
        }
        catch (OperationCanceledException) when (cancellation.IsCancellationRequested)
        {
            if (IsCurrentCalculation(generation))
            {
                StatusMessage = "Calculation cancelled.";
            }
        }
        catch (Exception exception)
        {
            if (IsCurrentCalculation(generation))
            {
                _logger.LogError(exception, "Route calculation workflow failed");
                ErrorMessage = $"Route calculation failed: {exception.Message}";
                StatusMessage = "No route result was accepted.";
                _mapLayers.ClearCalculationOverlays();
            }
        }
        finally
        {
            if (IsCurrentCalculation(generation))
            {
                IsCalculating = false;
            }
        }
    }

    public async Task SelectLocalGribAsync(string path)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(path);
        ErrorMessage = null;
        if (_localGribInspector is null)
        {
            ErrorMessage = "Local GRIB inspection is unavailable.";
            return;
        }

        var cancellation = new CancellationTokenSource();
        var previous = Interlocked.Exchange(ref _inspectionCancellation, cancellation);
        previous?.Cancel();
        previous?.Dispose();
        IsInspectingLocalGrib = true;
        LocalGribStatus = "Inspecting selected GRIB...";
        try
        {
            var inspected = await _localGribInspector.InspectAsync(path, cancellation.Token);
            if (cancellation != Volatile.Read(ref _inspectionCancellation))
            {
                return;
            }

            LocalForecast = inspected;
            ForecastInputMode = ForecastInputMode.LocalFile;
            UseNoaa = inspected.Model == ForecastModel.NoaaGfs;
            UseEcmwf = inspected.Model == ForecastModel.EcmwfIfs;
            LocalGribStatus = "GRIB is compatible and ready.";
            StatusMessage = $"{ModelName(inspected.Model)} local forecast selected.";
        }
        catch (OperationCanceledException) when (cancellation.IsCancellationRequested)
        {
        }
        catch (Exception exception)
        {
            if (cancellation == Volatile.Read(ref _inspectionCancellation))
            {
                LocalForecast = null;
                LocalGribStatus = "Selected file is not usable.";
                ErrorMessage = $"GRIB file rejected: {exception.Message}";
            }
        }
        finally
        {
            if (cancellation == Interlocked.CompareExchange(
                    ref _inspectionCancellation,
                    null,
                    cancellation))
            {
                IsInspectingLocalGrib = false;
                cancellation.Dispose();
            }
        }
    }

    public void RequestWeatherRefreshFromViewport()
    {
        if (!TryGetVisibleBounds(out var bounds))
        {
            return;
        }

        var viewport = Map.Navigator.Viewport;
        var size = WeatherGridSizing.FromViewport(viewport.Width, viewport.Height);
        RequestWeatherRefresh(bounds, size.LatitudeCount, size.LongitudeCount);
    }

    public Task RefreshWeatherAsync(
        GeographicBounds bounds,
        int latitudeCount,
        int longitudeCount)
    {
        var generation = StartWeatherRequest(out var cancellation);
        return RefreshWeatherCoreAsync(
            bounds,
            latitudeCount,
            longitudeCount,
            generation,
            cancellation.Token);
    }

    [RelayCommand]
    private void SetStart()
    {
        _interaction.Activate(MapInteractionMode.SetStart);
        NotifyInteractionChanged();
    }

    [RelayCommand]
    private void SetDestination()
    {
        _interaction.Activate(MapInteractionMode.SetDestination);
        NotifyInteractionChanged();
    }

    [RelayCommand(CanExecute = nameof(CanCalculate))]
    private Task Calculate() => CalculateRoutesAsync();

    private bool CanCalculate() =>
        !IsCalculating &&
        !IsInspectingLocalGrib &&
        (ForecastInputMode == ForecastInputMode.Download || LocalForecast is not null);

    [RelayCommand]
    private void SelectDownloadSource() => ForecastInputMode = ForecastInputMode.Download;

    [RelayCommand]
    private void SelectLocalFileSource() => ForecastInputMode = ForecastInputMode.LocalFile;

    [RelayCommand(CanExecute = nameof(CanCancel))]
    private void Cancel()
    {
        var wasCalculating = IsCalculating;
        Interlocked.Increment(ref _calculationGeneration);
        var cancellation = Interlocked.Exchange(ref _calculationCancellation, null);
        cancellation?.Cancel();
        cancellation?.Dispose();
        Volatile.Read(ref _inspectionCancellation)?.Cancel();
        CancelWeather();
        _mapLayers.ClearCalculationOverlays();
        IsCalculating = false;
        StatusMessage = wasCalculating
            ? "Calculation cancelled."
            : "GRIB inspection cancelled.";
    }

    private bool CanCancel() => IsCalculating || IsInspectingLocalGrib;

    [RelayCommand]
    private void FocusSelectedRoutePoint()
    {
        if (SelectedRoutePoint is null)
        {
            return;
        }

        var resolution = Map.Navigator.Viewport.Resolution;
        if (!double.IsFinite(resolution) || resolution <= 0)
        {
            resolution = 10_000;
        }

        Map.Navigator.CenterOnAndZoomTo(
            MapProjection.ToContinuousMapPoints(
                SelectedRoutePoint.Route.Points.Select(point => point.Location))[
                SelectedRoutePoint.PointIndex],
            Math.Min(resolution, 10_000));
    }

    [RelayCommand(CanExecute = nameof(CanMovePrevious))]
    private void PreviousTimeline()
    {
        if (_timeline is not null &&
            SelectedTimelineUtc is { } selected &&
            _timeline.TryGetPreviousTimestamp(selected, out var previous))
        {
            SetTimelineUtc(previous);
            ApplyTimelineSelection();
        }
    }

    private bool CanMovePrevious() =>
        _timeline is not null &&
        SelectedTimelineUtc is { } selected &&
        _timeline.TryGetPreviousTimestamp(selected, out _);

    [RelayCommand(CanExecute = nameof(CanMoveNext))]
    private void NextTimeline()
    {
        if (_timeline is not null &&
            SelectedTimelineUtc is { } selected &&
            _timeline.TryGetNextTimestamp(selected, out var next))
        {
            SetTimelineUtc(next);
            ApplyTimelineSelection();
        }
    }

    private bool CanMoveNext() =>
        _timeline is not null &&
        SelectedTimelineUtc is { } selected &&
        _timeline.TryGetNextTimestamp(selected, out _);

    [RelayCommand(CanExecute = nameof(HasNoaaWeather))]
    private void ActivateNoaaWeather() => ActiveWeatherModel = ForecastModel.NoaaGfs;

    [RelayCommand(CanExecute = nameof(HasEcmwfWeather))]
    private void ActivateEcmwfWeather() => ActiveWeatherModel = ForecastModel.EcmwfIfs;

    partial void OnTimelinePositionChanged(double value)
    {
        if (_updatingTimelinePosition || _timeline is null)
        {
            return;
        }

        var clamped = Math.Clamp(value, 0, 1);
        var duration = _timeline.End - _timeline.Start;
        SetTimelineUtc(_timeline.Start + TimeSpan.FromTicks((long)(duration.Ticks * clamped)));
        ApplyTimelineSelection();
    }

    partial void OnSelectedTimelineUtcChanged(DateTimeOffset? value)
    {
        OnPropertyChanged(nameof(TimelineDisplay));
        PreviousTimelineCommand.NotifyCanExecuteChanged();
        NextTimelineCommand.NotifyCanExecuteChanged();
    }

    partial void OnActiveWeatherModelChanged(ForecastModel? value)
    {
        OnPropertyChanged(nameof(IsNoaaWeatherActive));
        OnPropertyChanged(nameof(IsEcmwfWeatherActive));
        OnPropertyChanged(nameof(ActiveWeatherDisplay));
        ApplyTimelineSelection(value);
        RequestWeatherRefreshFromViewport();
    }

    partial void OnHasNoaaWeatherChanged(bool value) =>
        ActivateNoaaWeatherCommand.NotifyCanExecuteChanged();

    partial void OnHasEcmwfWeatherChanged(bool value) =>
        ActivateEcmwfWeatherCommand.NotifyCanExecuteChanged();

    partial void OnDepartureDateChanged(DateTimeOffset? value) => UpdateForecastAreaSummary();

    partial void OnDepartureTimeChanged(TimeSpan? value) => UpdateForecastAreaSummary();

    partial void OnPassageDaysChanged(int value) => UpdateForecastAreaSummary();

    partial void OnPassageHoursChanged(int value) => UpdateForecastAreaSummary();

    partial void OnUseNoaaChanged(bool value) => UpdateForecastAreaSummary();

    partial void OnForecastInputModeChanged(ForecastInputMode value)
    {
        OnPropertyChanged(nameof(IsDownloadForecast));
        OnPropertyChanged(nameof(IsLocalForecast));
        CalculateCommand.NotifyCanExecuteChanged();
        UpdateForecastAreaSummary();
    }

    partial void OnLocalForecastChanged(LocalForecastDescriptor? value)
    {
        OnPropertyChanged(nameof(LocalGribDisplay));
        CalculateCommand.NotifyCanExecuteChanged();
        UpdateForecastAreaSummary();
    }

    partial void OnSelectedRoutePointChanged(RouteMapSelection? value)
    {
        _mapLayers.SetSelectedPoint(value);
        if (value is not null)
        {
            StatusMessage = $"{ModelName(value.Route.Model)} route selected at " +
                            $"{value.TimelineTimestamp:HH:mm} UTC.";
        }

        OnPropertyChanged(nameof(SelectedRouteTitle));
        OnPropertyChanged(nameof(SelectedRouteDetails));
        RouteSelectionChanged?.Invoke(this, value);
    }

    private bool TryCreateWorkflowRequest(
        out RoutingWorkflowRequest? request,
        out string? error)
    {
        request = null;
        if (Start is null || Destination is null)
        {
            error = "Set both endpoints before calculating.";
            return false;
        }

        var selections = new List<ForecastSelection>();
        if (ForecastInputMode == ForecastInputMode.LocalFile)
        {
            if (LocalForecast is null)
            {
                error = "Choose a compatible GRIB file before calculating.";
                return false;
            }

            selections.Add(ForecastSelection.LocalFile(LocalForecast));
        }
        else
        {
            if (UseNoaa)
            {
                selections.Add(ForecastSelection.OfficialDownload(ForecastModel.NoaaGfs));
            }

            if (UseEcmwf)
            {
                selections.Add(ForecastSelection.OfficialDownload(ForecastModel.EcmwfIfs));
            }
        }

        if (selections.Count == 0)
        {
            error = "Select at least one forecast model.";
            return false;
        }

        if (!LocalDepartureConverter.TryConvertToUtc(
                DepartureDate,
                DepartureTime,
                _localTimeZone,
                out var departureUtc,
                out error))
        {
            return false;
        }

        if (!TryGetPassageDuration(out var passageDuration, out error))
        {
            return false;
        }

        var route = new RouteRequest(
            $"route-{Guid.NewGuid():N}",
            Start.Value,
            Destination.Value,
            departureUtc,
            departureUtc + passageDuration);
        var validation = new RouteRequestValidator().Validate(
            route,
            _timeProvider.GetUtcNow(),
            new RouteValidationOptions(
                maximumDepartureLeadTime: MaximumDepartureLeadTime,
                maximumRouteDuration: MaximumRouteWindow,
                pastTolerance: TimeSpan.FromMinutes(5)));
        if (!validation.IsValid)
        {
            error = string.Join(" ", validation.Errors.Select(item => item.Message));
            return false;
        }

        request = new RoutingWorkflowRequest(
            route,
            selections,
            ForecastCorridor.Create(route.Origin, route.Destination));
        error = null;
        return true;
    }

    private void ApplyWorkflowResult(RoutingWorkflowResult result)
    {
        _acquisitions.Clear();
        var failures = new List<string>();
        foreach (var outcome in result.Outcomes)
        {
            if (outcome.Acquisition is not null)
            {
                _acquisitions[outcome.Model] = outcome.Acquisition;
            }

            if (outcome.Status == ModelRouteStatus.Succeeded)
            {
                SetModelStatus(
                    outcome.Model,
                    $"{(IsExperimentalDownload(result.Request, outcome.Model) ? "Experimental · " : string.Empty)}" +
                    $"complete · arrival {outcome.Route!.ArrivalTime:MMM d HH:mm} UTC");
            }
            else
            {
                _mapLayers.ClearCalculationOverlay(outcome.Model);
                var experimental = IsExperimentalDownload(result.Request, outcome.Model)
                    ? "Experimental ECMWF"
                    : ModelName(outcome.Model);
                var failedStage = outcome.Failure!.Stage switch
                {
                    ModelRouteFailureStage.ForecastAcquisition => "forecast acquisition",
                    ModelRouteFailureStage.RouteCalculation => "route calculation",
                    ModelRouteFailureStage.ResultValidation => "route result validation",
                    _ => "provider setup"
                };
                var message = $"{experimental} failed during {failedStage}: {outcome.Failure.Message}";
                failures.Add(message);
                _logger.LogWarning(
                    "Forecast model {Model} failed during {FailureStage}: {FailureMessage}",
                    outcome.Model,
                    outcome.Failure.Stage,
                    outcome.Failure.Message);
                SetModelStatus(outcome.Model, message);
            }
        }

        HasNoaaWeather = _acquisitions.ContainsKey(ForecastModel.NoaaGfs);
        HasEcmwfWeather = _acquisitions.ContainsKey(ForecastModel.EcmwfIfs);
        ActiveWeatherModel = HasNoaaWeather
            ? ForecastModel.NoaaGfs
            : HasEcmwfWeather
                ? ForecastModel.EcmwfIfs
                : null;

        var routes = result.SuccessfulRoutes;
        _mapLayers.SetRoutes(routes);
        _mapLayers.FitRoutes();
        OnPropertyChanged(nameof(SuccessfulRouteCount));
        BuildTimeline(routes);
        ProgressFraction = 1;
        ErrorMessage = failures.Count == 0 ? null : string.Join(Environment.NewLine, failures);
        StatusMessage = routes.Length switch
        {
            0 => "No model produced a route.",
            1 when failures.Count > 0 => "One route is available; another selected model failed.",
            1 => "Route calculation complete.",
            _ => "Both model routes are available."
        };
        OnPropertyChanged(nameof(SelectedRouteDetails));
        RequestWeatherRefreshFromViewport();
    }

    private void BuildTimeline(IReadOnlyCollection<RouteResult> routes)
    {
        if (routes.Count == 0)
        {
            _timeline = null;
            HasTimeline = false;
            SelectedTimelineUtc = null;
            SelectedRoutePoint = null;
            _mapLayers.SetTimelinePoints(Array.Empty<RoutePointSelection>(), null);
            return;
        }

        _timeline = SharedRouteTimeline.Create(routes);
        HasTimeline = true;
        SetTimelineUtc(_timeline.Start);
        ApplyTimelineSelection(ActiveWeatherModel ?? routes.First().Model);
    }

    private void SetTimelineUtc(DateTimeOffset timestamp)
    {
        if (_timeline is null)
        {
            return;
        }

        var selected = _timeline.Clamp(timestamp);
        SelectedTimelineUtc = selected;
        var duration = _timeline.End - _timeline.Start;
        _updatingTimelinePosition = true;
        TimelinePosition = duration == TimeSpan.Zero
            ? 0
            : (selected - _timeline.Start).Ticks / (double)duration.Ticks;
        _updatingTimelinePosition = false;
    }

    private void ApplyTimelineSelection(ForecastModel? preferredModel = null)
    {
        if (_timeline is null || SelectedTimelineUtc is null)
        {
            return;
        }

        var nearest = _timeline.NearestPoints(SelectedTimelineUtc.Value);
        var model = preferredModel ??
                    SelectedRoutePoint?.Route.Model ??
                    ActiveWeatherModel ??
                    nearest.Keys.First().Model;
        var candidate = nearest.Values.FirstOrDefault(selection => selection.Route.Model == model) ??
                        nearest.Values.First();
        var route = _mapLayers.Routes.First(item =>
            item.Request.RouteId == candidate.Route.RouteId &&
            item.Model == candidate.Route.Model);
        var pointIndex = route.Points.IndexOf(candidate.Point);
        SelectedRoutePoint = new RouteMapSelection(
            route,
            Math.Max(0, pointIndex),
            candidate.Point,
            RouteHitKind.RoutePoint,
            0);
        _mapLayers.SetTimelinePoints(nearest.Values, model);
        RequestWeatherRefreshFromViewport();
    }

    private void RequestWeatherRefresh(
        GeographicBounds bounds,
        int latitudeCount,
        int longitudeCount)
    {
        var generation = StartWeatherRequest(out var cancellation);
        _ = DebounceWeatherAsync(
            bounds,
            latitudeCount,
            longitudeCount,
            generation,
            cancellation.Token);
    }

    private async Task DebounceWeatherAsync(
        GeographicBounds bounds,
        int latitudeCount,
        int longitudeCount,
        long generation,
        CancellationToken cancellationToken)
    {
        try
        {
            await Task.Delay(WeatherDebounce, cancellationToken);
            await RefreshWeatherCoreAsync(
                bounds,
                latitudeCount,
                longitudeCount,
                generation,
                cancellationToken);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
        }
    }

    private async Task RefreshWeatherCoreAsync(
        GeographicBounds bounds,
        int latitudeCount,
        int longitudeCount,
        long generation,
        CancellationToken cancellationToken)
    {
        if (_weatherSampler is null ||
            ActiveWeatherModel is not { } model ||
            SelectedTimelineUtc is not { } selected ||
            !_acquisitions.TryGetValue(model, out var acquisition))
        {
            if (generation == Volatile.Read(ref _weatherGeneration))
            {
                _mapLayers.ClearWeather();
            }

            return;
        }

        if (selected < acquisition.Request.From || selected > acquisition.Request.Through)
        {
            if (generation == Volatile.Read(ref _weatherGeneration))
            {
                _mapLayers.ClearWeather();
                WeatherLayerError =
                    $"{ModelName(model)} has no forecast at {selected:yyyy-MM-dd HH:mm} UTC.";
            }

            return;
        }

        try
        {
            WeatherLayerError = null;
            var samples = await _weatherSampler.SampleViewportAsync(
                acquisition,
                bounds,
                latitudeCount,
                longitudeCount,
                selected,
                cancellationToken);
            if (generation != Volatile.Read(ref _weatherGeneration) ||
                cancellationToken.IsCancellationRequested)
            {
                return;
            }

            _mapLayers.SetWeather(samples, bounds, latitudeCount, longitudeCount);
            OnPropertyChanged(nameof(WeatherCellCount));
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
        }
        catch (Exception exception)
        {
            if (generation == Volatile.Read(ref _weatherGeneration))
            {
                _logger.LogWarning(
                    exception,
                    "Weather layer refresh failed for {Model} at {SelectedTimelineUtc}",
                    model,
                    selected);
                _mapLayers.ClearWeather();
                OnPropertyChanged(nameof(WeatherCellCount));
                WeatherLayerError = $"{ModelName(model)} weather layer failed: {exception.Message}";
            }
        }
    }

    private long StartWeatherRequest(out CancellationTokenSource cancellation)
    {
        var generation = Interlocked.Increment(ref _weatherGeneration);
        cancellation = new CancellationTokenSource();
        var previous = Interlocked.Exchange(ref _weatherCancellation, cancellation);
        previous?.Cancel();
        previous?.Dispose();
        return generation;
    }

    private void CancelWeather()
    {
        Interlocked.Increment(ref _weatherGeneration);
        var cancellation = Interlocked.Exchange(ref _weatherCancellation, null);
        cancellation?.Cancel();
        cancellation?.Dispose();
        _mapLayers.ClearWeather();
        OnPropertyChanged(nameof(WeatherCellCount));
    }

    private bool TryGetVisibleBounds(out GeographicBounds bounds)
    {
        var extent = Map.Navigator.Viewport.ToExtent();
        if (!double.IsFinite(extent.Width) || !double.IsFinite(extent.Height) ||
            extent.Width <= 0 || extent.Height <= 0)
        {
            bounds = default;
            return false;
        }

        var lowerLeft = MapProjection.ToCoordinate(new MPoint(extent.Left, extent.Bottom));
        var upperRight = MapProjection.ToCoordinate(new MPoint(extent.Right, extent.Top));
        bounds = new GeographicBounds(
            Math.Max(-85, Math.Min(lowerLeft.Latitude, upperRight.Latitude)),
            Math.Min(85, Math.Max(lowerLeft.Latitude, upperRight.Latitude)),
            lowerLeft.Longitude,
            upperRight.Longitude);
        return true;
    }

    private bool IsCurrentCalculation(long generation) =>
        generation == Volatile.Read(ref _calculationGeneration);

    private void SetModelStatus(ForecastModel model, string status)
    {
        if (model == ForecastModel.NoaaGfs)
        {
            NoaaStatus = status;
        }
        else
        {
            EcmwfStatus = status;
        }
    }

    private void NotifyInteractionChanged()
    {
        OnPropertyChanged(nameof(InteractionMode));
        OnPropertyChanged(nameof(Start));
        OnPropertyChanged(nameof(Destination));
        OnPropertyChanged(nameof(StartDisplay));
        OnPropertyChanged(nameof(DestinationDisplay));
        OnPropertyChanged(nameof(MapInstruction));
        UpdateForecastAreaSummary();
    }

    private bool TryGetPassageDuration(out TimeSpan duration, out string? error)
    {
        duration = default;
        if (PassageDays < 0 || PassageHours is < 0 or > 23)
        {
            error = "Passage duration requires non-negative days and hours from 0 through 23.";
            return false;
        }

        duration = TimeSpan.FromDays(PassageDays) + TimeSpan.FromHours(PassageHours);
        if (duration <= TimeSpan.Zero)
        {
            error = "Passage duration must be greater than zero.";
            return false;
        }

        if (duration > MaximumRouteWindow)
        {
            error = "Passage duration cannot exceed 10 days.";
            return false;
        }

        error = null;
        return true;
    }

    private void UpdateForecastAreaSummary()
    {
        if (Start is null || Destination is null)
        {
            ForecastAreaSummary = "Set both endpoints to estimate the forecast download.";
            return;
        }

        var corridor = ForecastCorridor.Calculate(Start.Value, Destination.Value);
        var bounds = corridor.Bounds;
        var area = $"Buffered area {FormatBounds(bounds)} · {corridor.BufferNauticalMiles:0} NM buffer";
        if (ForecastInputMode == ForecastInputMode.LocalFile)
        {
            ForecastAreaSummary = LocalForecast is null
                ? $"{area}. Choose a local GRIB to check coverage."
                : $"{area}. The selected GRIB will be checked against this area.";
            return;
        }

        if (!UseNoaa ||
            _noaaProvider is null ||
            !TryGetPassageDuration(out var duration, out _) ||
            !LocalDepartureConverter.TryConvertToUtc(
                DepartureDate,
                DepartureTime,
                _localTimeZone,
                out var departure,
                out _))
        {
            ForecastAreaSummary = area;
            return;
        }

        try
        {
            var estimate = _noaaProvider.Estimate(new ForecastRequest(
                ForecastModel.NoaaGfs,
                bounds,
                departure,
                departure + duration));
            ForecastAreaSummary =
                $"{area} · {estimate.ForecastStepCount} times, " +
                $"{estimate.PartCount} forecast part{(estimate.PartCount == 1 ? string.Empty : "s")} " +
                "(cached parts are reused)";
        }
        catch (Exception exception)
        {
            ForecastAreaSummary = $"{area} · estimate unavailable: {exception.Message}";
        }
    }

    private static string FormatBounds(GeographicBounds bounds) =>
        $"{bounds.South:0.##}° to {bounds.North:0.##}° latitude, " +
        $"{bounds.West:0.##}° to {bounds.East:0.##}° longitude";

    private static bool IsExperimentalDownload(
        RoutingWorkflowRequest request,
        ForecastModel model) =>
        model == ForecastModel.EcmwfIfs &&
        request.Selections.Any(selection =>
            selection.Model == model &&
            selection.Kind == ForecastSelectionKind.OfficialDownload);

    private static string ProgressStageName(RoutingProgressStage stage) => stage switch
    {
        RoutingProgressStage.AcquiringForecast => "acquiring",
        RoutingProgressStage.CalculatingRoute => "routing",
        RoutingProgressStage.Completed => "complete",
        RoutingProgressStage.Failed => "failed",
        _ => stage.ToString()
    };

    private static string FormatCoordinate(Coordinate? coordinate, string fallback) =>
        coordinate is null
            ? fallback
            : $"{Math.Abs(coordinate.Value.Latitude):0.000}° " +
              $"{(coordinate.Value.Latitude >= 0 ? "N" : "S")}, " +
              $"{Math.Abs(coordinate.Value.Longitude):0.000}° " +
              $"{(coordinate.Value.Longitude >= 0 ? "E" : "W")}";

    private static string FormatUtcOffset(TimeSpan offset)
    {
        var sign = offset < TimeSpan.Zero ? "−" : "+";
        var absolute = offset.Duration();
        return $"UTC{sign}{absolute.Hours:00}:{absolute.Minutes:00}";
    }

    private static string ModelName(ForecastModel model) => model switch
    {
        ForecastModel.NoaaGfs => "NOAA GFS",
        ForecastModel.EcmwfIfs => "ECMWF IFS (experimental)",
        _ => model.ToString()
    };
}
