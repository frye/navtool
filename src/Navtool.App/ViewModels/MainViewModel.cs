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
    private const double DefaultChartBufferNauticalMiles = 10;
    private const double RouteHitTolerancePixels = 10;
    private const double RoutePointHitTolerancePixels = 14;
    private static readonly Coordinate[] DefaultChartLocations =
    [
        new(48.1163, -122.7583), // Port Townsend
        new(48.5343, -123.0171), // Friday Harbor
        new(48.5126, -122.6127), // Anacortes
        new(48.9416, -125.5464)  // Ucluelet
    ];
    private static readonly TimeSpan MaximumRouteWindow = TimeSpan.FromDays(10);
    private static readonly TimeSpan MaximumDepartureLeadTime = TimeSpan.FromDays(5);
    private static readonly TimeSpan WeatherDebounce = TimeSpan.FromMilliseconds(220);
    private readonly MapInteractionState _interaction = new();
    private readonly RouteMapLayers _mapLayers;
    private readonly RoutingWorkflow? _workflow;
    private readonly RoutePlanRoutingWorkflow? _routePlanWorkflow;
    private readonly IWeatherSampler? _weatherSampler;
    private readonly ILocalGribInspector? _localGribInspector;
    private readonly INativeRoutingPreflight? _nativeRoutingPreflight;
    private readonly NoaaGfsForecastProvider? _noaaProvider;
    private readonly TimeProvider _timeProvider;
    private readonly TimeZoneInfo _localTimeZone;
    private readonly ILogger<MainViewModel> _logger;
    private readonly Dictionary<ForecastModel, double> _modelProgress = new();
    private readonly Dictionary<ForecastModel, ImmutableArray<ForecastAcquisition>> _acquisitions = new();
    private readonly object _progressGate = new();
    private CancellationTokenSource? _calculationCancellation;
    private CancellationTokenSource? _weatherCancellation;
    private CancellationTokenSource? _inspectionCancellation;
    private SharedRouteTimeline? _timeline;
    private long _calculationGeneration;
    private RoutePlanId? _displayedRoutePlanId;
    private RoutePlanId? _activeCalculationPlanId;
    private long _activeCalculationRevision;
    private long _weatherGeneration;
    private bool _updatingTimelinePosition;
    private ImmutableArray<RouteLegVisualization> _visualizationLegs = [];
    private string? _selectedStopoverLabel;

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
    private string? _warningMessage;

    [ObservableProperty]
    private string? _landAvoidanceWarning;

    [ObservableProperty]
    private string? _weatherLayerError;

    [ObservableProperty]
    private string _noaaStatus = "Ready";

    [ObservableProperty]
    private string _ecmwfStatus = "Experimental · not selected";

    [ObservableProperty]
    private RouteMapSelection? _selectedRoutePoint;

    [ObservableProperty]
    private RouteLegVisualization? _selectedLeg;

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
    private ForecastModel? _activeRouteModel;

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
            localGribInspector,
            nativeRoutingPreflight,
            noaaProvider,
            logger,
            null)
    {
    }

    public MainViewModel(
        RoutingWorkflow workflow,
        IWeatherSampler weatherSampler,
        ILocalGribInspector localGribInspector,
        INativeRoutingPreflight nativeRoutingPreflight,
        NoaaGfsForecastProvider noaaProvider,
        ILogger<MainViewModel> logger,
        IRoutePlanRepository? routePlanRepository)
        : this(
            workflow,
            weatherSampler,
            TimeProvider.System,
            TimeZoneInfo.Local,
            new OsmTileOptions(),
            logger,
            localGribInspector,
            nativeRoutingPreflight,
            noaaProvider,
            routePlanRepository)
    {
    }

    public MainViewModel(
        RoutingWorkflow workflow,
        IWeatherSampler weatherSampler,
        ILocalGribInspector localGribInspector,
        INativeRoutingPreflight nativeRoutingPreflight,
        NoaaGfsForecastProvider noaaProvider,
        ILogger<MainViewModel> logger,
        IRoutePlanRepository routePlanRepository,
        RoutePlanRoutingWorkflow routePlanWorkflow)
        : this(
            workflow,
            weatherSampler,
            TimeProvider.System,
            TimeZoneInfo.Local,
            new OsmTileOptions(),
            logger,
            localGribInspector,
            nativeRoutingPreflight,
            noaaProvider,
            routePlanRepository,
            routePlanWorkflow)
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
        NoaaGfsForecastProvider? noaaProvider = null,
        IRoutePlanRepository? routePlanRepository = null,
        RoutePlanRoutingWorkflow? routePlanWorkflow = null)
    {
        ArgumentNullException.ThrowIfNull(timeProvider);
        ArgumentNullException.ThrowIfNull(localTimeZone);
        ArgumentNullException.ThrowIfNull(tileOptions);
        _workflow = workflow;
        _routePlanWorkflow = routePlanWorkflow ?? (workflow is null || routePlanRepository is null
            ? null
            : new RoutePlanRoutingWorkflow(workflow, routePlanRepository, timeProvider));
        _weatherSampler = weatherSampler;
        _localGribInspector = localGribInspector;
        _nativeRoutingPreflight = nativeRoutingPreflight;
        _noaaProvider = noaaProvider;
        _timeProvider = timeProvider;
        _localTimeZone = localTimeZone;
        _logger = logger ?? NullLogger<MainViewModel>.Instance;
        Itinerary = new ItineraryEditorViewModel(routePlanRepository);
        Itinerary.ItineraryChanged += OnItineraryChanged;
        Itinerary.MapPlacementStarted += OnMapPlacementStarted;
        Itinerary.CurrentPositionPlacementStarted += OnCurrentPositionPlacementStarted;
        Itinerary.LegSelected += OnLegSelected;

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
        UpdateWaypointLayers();
        UtcOffsetDisplay = FormatUtcOffset(localTimeZone.GetUtcOffset(timeProvider.GetLocalNow()));
        Map.Navigator.ZoomToBox(CreateDefaultChartExtent());
        UpdateForecastAreaSummary();
    }

    public event EventHandler<RouteMapSelection?>? RouteSelectionChanged;

    public Map Map { get; }

    public ItineraryEditorViewModel Itinerary { get; }

    public string UtcOffsetDisplay { get; }

    public MapInteractionMode InteractionMode => _interaction.Mode;

    public Coordinate? Start => Itinerary.Start;

    public Coordinate? Destination => Itinerary.Finish;

    public string StartDisplay => FormatCoordinate(Start, "Not set");

    public string DestinationDisplay => FormatCoordinate(Destination, "Not set");

    public bool IsDownloadForecast => ForecastInputMode == ForecastInputMode.Download;

    public bool IsLocalForecast => ForecastInputMode == ForecastInputMode.LocalFile;

    public bool IsSettingStart => InteractionMode == MapInteractionMode.SetStart;

    public bool IsSettingDestination => InteractionMode == MapInteractionMode.SetDestination;

    public bool IsEndpointPlacementArmed => InteractionMode != MapInteractionMode.Browse;

    public bool HasWarning => !string.IsNullOrWhiteSpace(WarningMessage);

    public bool HasError => !string.IsNullOrWhiteSpace(ErrorMessage);

    public bool IsSettingWaypoint => InteractionMode == MapInteractionMode.SetWaypoint;

    public bool IsSettingCurrentPosition => InteractionMode == MapInteractionMode.SetCurrentPosition;

    public string LocalGribDisplay => LocalForecast is null
        ? "No file selected"
        : $"{Path.GetFileName(LocalForecast.Artifact.Path)} · {ModelName(LocalForecast.Model)}\n" +
          $"Run {LocalForecast.InitializedAt:yyyy-MM-dd HH:mm} UTC · " +
          $"valid through {LocalForecast.ValidThrough:yyyy-MM-dd HH:mm} UTC\n" +
          FormatBounds(LocalForecast.Bounds);

    public string MapInstruction => InteractionMode switch
    {
        MapInteractionMode.SetStart => "Click the map to place the start",
        MapInteractionMode.SetDestination => "Click the map to place the finish",
        MapInteractionMode.SetWaypoint => $"Click the map to place {Itinerary.ActiveWaypoint?.Name ?? "the waypoint"}",
        MapInteractionMode.SetCurrentPosition =>
            "Click the map to place the current position (where the vessel is now)",
        _ => "Pan and zoom, or select an endpoint tool"
    };

    public string SelectedRouteTitle => SelectedLeg is null && SelectedRoutePoint is null
        ? "No route point selected"
        : (SelectedLeg ?? SelectedRoutePoint!.Leg) is { } leg
            ? $"Leg {leg.LegIndex + 1}: {leg.From.Name} → {leg.To.Name} · {ModelName(leg.Key.Model)}"
            : $"{ModelName(SelectedRoutePoint!.Route.Model)} · point {SelectedRoutePoint.PointIndex + 1}";

    public string SelectedRouteDetails
    {
        get
        {
            if (SelectedRoutePoint is null)
            {
                return SelectedLeg is null
                    ? "Select an itinerary leg or click near a displayed route."
                    : FormatSelectedLegDetails(SelectedLeg);
            }

            var selection = SelectedRoutePoint;
            var point = selection.Point;
            var acquisition = FindCompatibleAcquisition(selection.Leg, selection.Route.Model);
            var forecast = acquisition is null
                ? "weather unavailable (saved geometry does not include forecast binaries)"
                : $"run {acquisition.Run.InitializedAt:yyyy-MM-dd HH:mm} UTC · " +
                  $"{acquisition.Source} · {acquisition.Artifact.Path}";
            var legDetails = selection.Leg is null
                ? string.Empty
                : FormatSelectedLegDetails(selection.Leg);
            var stopover = _selectedStopoverLabel is null
                ? string.Empty
                : $"{_selectedStopoverLabel} · stationary hold\n";
            return $"{legDetails}{stopover}{point.Timestamp:yyyy-MM-dd HH:mm:ss} UTC\n" +
                  $"{point.Location.Latitude:0.0000}°, {point.Location.Longitude:0.0000}° · " +
                   $"heading {point.HeadingDegrees:0}° · boat {point.BoatSpeedKnots:0.0} kt · " +
                   $"{FormatApparentWind(point)}\n" +
                   $"true wind {point.TrueWindSpeedKnots:0.0} kt @ {point.TrueWindDirectionDegrees:0}° · " +
                   $"cumulative {point.CumulativeDistanceNauticalMiles:0.0} NM\n" +
                   $"{ModelName(selection.Route.Model)} · " +
                   $"{(selection.Route.IsForecastLimited ? "forecast-limited endpoint" : "arrival")} " +
                   $"{selection.Route.ArrivalTime:yyyy-MM-dd HH:mm} UTC · " +
                   $"distance {selection.Route.Points[^1].CumulativeDistanceNauticalMiles:0.0} NM · {forecast}";
        }
    }

    public string TimelineDisplay => SelectedTimelineUtc is null
        ? "Timeline unavailable"
        : $"{(ActiveRouteModel is { } model ? $"{ModelShortName(model)} · " : string.Empty)}" +
          $"{SelectedTimelineUtc:yyyy-MM-dd HH:mm:ss} UTC" +
          $"{(_selectedStopoverLabel is null ? string.Empty : $" · {_selectedStopoverLabel}")}";

    public string ActiveWeatherDisplay => ActiveWeatherModel is null
        ? "No weather overlay"
        : $"{ModelName(ActiveWeatherModel.Value)} wind · knots";

    public bool IsNoaaWeatherActive => ActiveWeatherModel == ForecastModel.NoaaGfs;

    public bool IsEcmwfWeatherActive => ActiveWeatherModel == ForecastModel.EcmwfIfs;

    public bool IsNoaaRouteActive => ActiveRouteModel == ForecastModel.NoaaGfs;

    public bool IsEcmwfRouteActive => ActiveRouteModel == ForecastModel.EcmwfIfs;

    public bool HasNoaaRoutes => _visualizationLegs.Any(leg =>
        leg.Key.Model == ForecastModel.NoaaGfs && leg.HasOptimizedGeometry);

    public bool HasEcmwfRoutes => _visualizationLegs.Any(leg =>
        leg.Key.Model == ForecastModel.EcmwfIfs && leg.HasOptimizedGeometry);

    public int WeatherCellCount => _mapLayers.WeatherCellCount;

    public int SuccessfulRouteCount => _mapLayers.Routes.Count;

    public IReadOnlyList<RouteResult> SuccessfulRoutes => _mapLayers.Routes;

    public IReadOnlyList<RouteLegVisualization> VisualizedRouteLegs => _visualizationLegs;

    partial void OnWarningMessageChanged(string? value) =>
        OnPropertyChanged(nameof(HasWarning));

    partial void OnErrorMessageChanged(string? value) =>
        OnPropertyChanged(nameof(HasError));

    public void SetEndpoints(Coordinate start, Coordinate destination)
    {
        _interaction.SetStart(start);
        _interaction.SetDestination(destination);
        Itinerary.SetEndpoints(start, destination);
        NotifyInteractionChanged();
    }

    public void SetStartAt(Coordinate coordinate)
    {
        _interaction.SetStart(coordinate);
        Itinerary.CancelMapPlacement();
        Itinerary.Waypoints[0].Coordinate = coordinate;
        CompleteEndpointPlacement();
    }

    public void SetDestinationAt(Coordinate coordinate)
    {
        _interaction.SetDestination(coordinate);
        Itinerary.CancelMapPlacement();
        Itinerary.Waypoints[^1].Coordinate = coordinate;
        CompleteEndpointPlacement();
    }

    public void DisplayRoutes(IEnumerable<RouteResult> routes)
    {
        var successful = routes.ToArray();
        _visualizationLegs = CreateTransientVisualizations(successful);
        _mapLayers.SetRouteLegs(_visualizationLegs);
        _mapLayers.FitRoutes();
        OnPropertyChanged(nameof(SuccessfulRouteCount));
        OnPropertyChanged(nameof(VisualizedRouteLegs));
        NotifyRouteModelAvailability();
        ActiveRouteModel = successful.FirstOrDefault()?.Model;
        BuildTimeline(ActiveRouteModel);
        UpdateLandAvoidanceWarning(successful);
        StatusMessage = successful.Length == 0
            ? "No routes are currently displayed."
            : $"{successful.Length} route{(successful.Length == 1 ? string.Empty : "s")} displayed.";
    }

    public void HandleMapClick(MPoint worldPosition, ScreenPosition screenPosition)
    {
        var coordinate = MapProjection.ToCoordinate(worldPosition);
        if (Itinerary.ActiveWaypoint is not null)
        {
            var waypoint = Itinerary.ActiveWaypoint;
            Itinerary.PlaceActiveWaypoint(coordinate);
            if (waypoint.IsStart)
            {
                _interaction.SetStart(coordinate);
            }
            else if (waypoint.IsFinish)
            {
                _interaction.SetDestination(coordinate);
            }
            else
            {
                _interaction.Activate(MapInteractionMode.Browse);
            }

            CompleteEndpointPlacement();
            return;
        }

        if (Itinerary.IsAwaitingCurrentPositionPlacement)
        {
            if (!Itinerary.TryPlaceCurrentPosition(coordinate, _localTimeZone, out var error))
            {
                ErrorMessage = error;
            }

            _interaction.Activate(MapInteractionMode.Browse);
            CompleteEndpointPlacement();
            return;
        }

        if (_interaction.HandleMapClick(coordinate))
        {
            CompleteEndpointPlacement();
            return;
        }

        InspectRouteAt(
            worldPosition,
            new ScreenPoint(screenPosition.X, screenPosition.Y));
    }

    public RouteMapSelection? FindRouteAt(
        MPoint worldPosition,
        ScreenPoint screenPosition)
    {
        ArgumentNullException.ThrowIfNull(worldPosition);
        var viewport = Map.Navigator.Viewport;
        if (_mapLayers.RouteLegs.Count > 0)
        {
            return RouteHitTester.FindNearest(
                _mapLayers.RouteLegs,
                (RouteLegVisualization leg) => MapProjection
                    .ToContinuousMapPointsNear(
                        leg.Route!.Points.Select(point => point.Location),
                        worldPosition.X)
                    .Select(point =>
                    {
                        var projected = viewport.WorldToScreen(point);
                        return new ScreenPoint(projected.X, projected.Y);
                    })
                    .ToArray(),
                screenPosition,
                RouteHitTolerancePixels,
                RoutePointHitTolerancePixels);
        }

        return RouteHitTester.FindNearest(
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
            screenPosition,
            RouteHitTolerancePixels,
            RoutePointHitTolerancePixels);
    }

    public bool CanInspectRouteAt(
        MPoint worldPosition,
        ScreenPoint screenPosition) =>
        FindRouteAt(worldPosition, screenPosition) is not null;

    public bool InspectRouteAt(
        MPoint worldPosition,
        ScreenPoint screenPosition,
        bool focus = true)
    {
        var hit = FindRouteAt(worldPosition, screenPosition);
        if (hit is not null)
        {
            SelectRoutePoint(hit, focus);
            return true;
        }

        return false;
    }

    public void SelectRoutePoint(RouteMapSelection selection, bool focus = true)
    {
        ArgumentNullException.ThrowIfNull(selection);
        if (selection.Leg is { } leg)
        {
            ActiveRouteModel = leg.Key.Model;
            SelectLegGeometry(leg.Key);
        }

        if (_timeline is not null && _timeline.Model == selection.Route.Model)
        {
            SetTimelineUtc(selection.TimelineTimestamp);
        }

        SelectedRoutePoint = selection;
        _selectedStopoverLabel = null;
        UpdateWeatherAvailability();
        if (focus)
        {
            FocusSelectedRoutePoint();
        }
    }

    public async Task CalculateRoutesAsync()
    {
        ErrorMessage = null;
        WarningMessage = null;
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

        RoutePlanRoutingRequest? planRequest = null;
        var useSequentialWorkflow = Itinerary.Waypoints.Count > 2;
        RoutePlan? sequentialPlan = null;
        if (!useSequentialWorkflow && Itinerary.Waypoints.Count == 2 &&
            Itinerary.TryBuildPlan(out var twoPointPlan, out _) &&
            (twoPointPlan!.CurrentPosition is not null || twoPointPlan.SailedLegIds.Count > 0))
        {
            // A two-waypoint itinerary with resume state (a placed current position, or a sailed
            // leg) still needs sequential/mid-leg resume semantics, so route it through the same
            // plan workflow used for longer itineraries instead of the legacy two-point path.
            useSequentialWorkflow = true;
            sequentialPlan = twoPointPlan;
        }

        if (useSequentialWorkflow)
        {
            if (_routePlanWorkflow is null)
            {
                ErrorMessage = "Route plan storage is required for multi-leg calculation.";
                return;
            }

            if (sequentialPlan is null && !Itinerary.TryBuildPlan(out sequentialPlan, out validationError))
            {
                ErrorMessage = validationError;
                return;
            }

            // The explicit current-position departure time (never wall clock/GPS) takes priority
            // over the itinerary-start departure fields once a current position has been placed.
            var departureTime = sequentialPlan!.CurrentPosition?.DepartureTime ?? request!.Route.DepartureTime;
            planRequest = new RoutePlanRoutingRequest(
                sequentialPlan,
                departureTime,
                request!.Route.LatestArrivalTime,
                request.Selections);
        }

        try
        {
            _nativeRoutingPreflight?.EnsureAvailable();
            if (_nativeRoutingPreflight is { LandAvoidanceAvailable: false })
            {
                throw new NotSupportedException(
                    "Active land avoidance is unavailable with the installed router-lib. " +
                    "Route calculation is blocked to prevent unchecked land crossings.");
            }
        }
        catch (Exception exception)
        {
            _logger.LogError(exception, "Native routing preflight failed");
            ErrorMessage = $"Routing engine unavailable: {exception.Message}";
            StatusMessage = "No forecast was downloaded.";
            return;
        }

        var generation = Interlocked.Increment(ref _calculationGeneration);
        var calculationPlanId = Itinerary.PlanId;
        var calculationRevision = Itinerary.CalculationRevision;
        _activeCalculationPlanId = calculationPlanId;
        _activeCalculationRevision = calculationRevision;
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
        var planProgress = new Progress<RoutePlanRoutingProgress>(value =>
        {
            if (!IsCurrentCalculation(generation) || !IsCalculating)
            {
                return;
            }

            ProgressFraction = value.OverallFraction;
            SetModelStatus(
                value.Model,
                $"{(IsExperimentalDownload(request, value.Model) ? "Experimental · " : string.Empty)}" +
                $"leg {value.LegIndex + 1} {PlanProgressStageName(value.Status)} " +
                $"{value.UnitFraction:P0}" +
                $"{(string.IsNullOrWhiteSpace(value.Message) ? string.Empty : $" · {value.Message}")}");
            if (value.Snapshot is not null)
            {
                _mapLayers.AddCalculationSnapshot(value.Model, value.Snapshot);
            }
            else if (value.Status is RoutePlanRoutingUnitStatus.Failed or
                     RoutePlanRoutingUnitStatus.Cancelled)
            {
                _mapLayers.ClearCalculationOverlay(value.Model);
            }
        });

        try
        {
            if (planRequest is not null)
            {
                var planResult = await _routePlanWorkflow!.ExecuteAsync(
                    planRequest,
                    planProgress,
                    cancellation.Token);
                if (!IsCurrentCalculation(generation) || !planResult.IsCurrent)
                {
                    return;
                }

                if (Itinerary.PlanId != calculationPlanId ||
                    Itinerary.CalculationRevision != calculationRevision)
                {
                    StatusMessage = "Calculation result discarded because the itinerary changed.";
                    return;
                }

                ApplyPlanWorkflowResult(planResult);
                return;
            }

            var result = await _workflow.ExecuteAsync(request!, progress, cancellation.Token);
            if (!IsCurrentCalculation(generation) || cancellation.IsCancellationRequested)
            {
                return;
            }

            if (Itinerary.PlanId != calculationPlanId ||
                Itinerary.CalculationRevision != calculationRevision)
            {
                StatusMessage = "Calculation result discarded because the itinerary changed.";
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
                _activeCalculationPlanId = null;
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
            if (cancellation == Volatile.Read(ref _inspectionCancellation))
            {
                LocalGribStatus = LocalForecast is null
                    ? "GRIB inspection cancelled."
                    : "Inspection cancelled; the previous GRIB remains selected.";
            }
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
        Itinerary.BeginMapPlacement(Itinerary.Waypoints[0]);
    }

    [RelayCommand]
    private void SetDestination()
    {
        Itinerary.BeginMapPlacement(Itinerary.Waypoints[^1]);
    }

    /// <summary>
    /// Arms the distinct current-position map placement mode. This is never the same interaction
    /// as placing a waypoint: it records a session-scoped "where the vessel is now" marker used
    /// to resume routing mid-itinerary, not a permanent route point.
    /// </summary>
    [RelayCommand]
    private void SetCurrentPosition() => Itinerary.BeginCurrentPositionPlacement();

    [RelayCommand(CanExecute = nameof(CanClearCurrentPosition))]
    private void ClearCurrentPosition() => Itinerary.ClearCurrentPosition();

    private bool CanClearCurrentPosition() => Itinerary.HasCurrentPosition;

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
        if (IsInspectingLocalGrib)
        {
            Interlocked.Increment(ref _calculationGeneration);
        }
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

        var projected = SelectedRoutePoint.Key is { } key
            ? _mapLayers.GetProjectedRoutePoint(key, SelectedRoutePoint.PointIndex)
            : null;
        projected ??= MapProjection.ToContinuousMapPoints(
            SelectedRoutePoint.Route.Points.Select(point => point.Location))[
            SelectedRoutePoint.PointIndex];
        Map.Navigator.CenterOnAndZoomTo(projected, Math.Min(resolution, 10_000));
    }

    [RelayCommand]
    private void FocusSelectedLeg()
    {
        if (SelectedRoutePoint?.Key is { } key)
        {
            _mapLayers.FitRouteLeg(key);
        }
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

    [RelayCommand(CanExecute = nameof(HasNoaaRoutes))]
    private void ActivateNoaaRoute() => ActiveRouteModel = ForecastModel.NoaaGfs;

    [RelayCommand(CanExecute = nameof(HasEcmwfRoutes))]
    private void ActivateEcmwfRoute() => ActiveRouteModel = ForecastModel.EcmwfIfs;

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
        RequestWeatherRefreshFromViewport();
    }

    partial void OnActiveRouteModelChanged(ForecastModel? value)
    {
        var selectedLegId = SelectedLeg?.Key.LegId;
        OnPropertyChanged(nameof(IsNoaaRouteActive));
        OnPropertyChanged(nameof(IsEcmwfRouteActive));
        BuildTimeline(value);
        if (value is { } model)
        {
            var sameLeg = selectedLegId is { } legId
                ? _visualizationLegs.FirstOrDefault(leg =>
                    leg.Key.Model == model &&
                    leg.Key.LegId == legId &&
                    leg.HasOptimizedGeometry)
                : null;
            var target = sameLeg ?? _visualizationLegs.FirstOrDefault(leg =>
                leg.Key.Model == model && leg.HasOptimizedGeometry);
            if (target is not null)
            {
                SelectLegGeometry(target.Key);
                SetTimelineUtc(target.Route!.Request.DepartureTime);
                ApplyTimelineSelection();
            }
        }

        UpdateWeatherAvailability();
    }

    private void ApplyPlanWorkflowResult(RoutePlanRoutingResult result)
    {
        Itinerary.AcceptCalculationResult(result.Plan);
        _acquisitions.Clear();
        var failures = new List<string>();
        var warnings = new List<string>();
        foreach (var outcome in result.Models)
        {
            if (!outcome.Acquisitions.IsEmpty)
            {
                _acquisitions[outcome.Model] = outcome.Acquisitions;
            }

            var legStatuses = outcome.Legs.Select((leg, index) =>
                $"leg {index + 1} {LegStatusName(leg, result.Plan.SailedLegIds.Contains(leg.LegId))}");
            var modelStatus =
                $"{(IsExperimentalDownload(result.Request.Selections, outcome.Model) ? "Experimental · " : string.Empty)}" +
                string.Join(" · ", legStatuses);
            SetModelStatus(outcome.Model, modelStatus);

            foreach (var leg in outcome.Legs)
            {
                if (leg.State == RouteLegOutcomeState.Failed)
                {
                    failures.Add(
                        $"{ModelName(outcome.Model)} failed: {leg.Detail ?? LegStatusName(leg)}");
                }
                else if (leg.Reason == RouteLegOutcomeReason.ForecastExhausted ||
                         leg.State == RouteLegOutcomeState.OutsideForecastWindow)
                {
                    warnings.Add(
                        $"{ModelName(outcome.Model)} {LegStatusName(leg)}" +
                        $"{(string.IsNullOrWhiteSpace(leg.Detail) ? "." : $": {leg.Detail}")}");
                }
            }
        }

        DisplayPlanVisualization(result.Plan, fit: true);
        var routes = _mapLayers.Routes;
        _displayedRoutePlanId = Itinerary.PlanId;
        ProgressFraction = 1;
        ErrorMessage = failures.Count == 0 ? null : string.Join(Environment.NewLine, failures);
        WarningMessage = warnings.Count == 0 ? null : string.Join(Environment.NewLine, warnings);
        UpdateLandAvoidanceWarning(routes);
        StatusMessage = result.Status switch
        {
            RoutePlanRoutingStatus.Succeeded => "All itinerary legs are complete.",
            RoutePlanRoutingStatus.PartialSuccess =>
                "The itinerary has partial results; review the model and leg statuses.",
            RoutePlanRoutingStatus.Cancelled =>
                "Calculation cancelled; completed legs were saved.",
            _ => "No model completed the itinerary."
        };
        OnPropertyChanged(nameof(SelectedRouteDetails));
        UpdateWeatherAvailability();
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
        if (value is not null)
        {
            if (value.Leg is not null)
            {
                SelectedLeg = value.Leg;
            }
            StatusMessage = $"{ModelName(value.Route.Model)} route selected at " +
                            $"{value.TimelineTimestamp:HH:mm} UTC.";
        }

        OnPropertyChanged(nameof(SelectedRouteTitle));
        OnPropertyChanged(nameof(SelectedRouteDetails));
        RouteSelectionChanged?.Invoke(this, value);
    }

    partial void OnSelectedLegChanged(RouteLegVisualization? value)
    {
        OnPropertyChanged(nameof(SelectedRouteTitle));
        OnPropertyChanged(nameof(SelectedRouteDetails));
        Itinerary.SetSelectedLeg(value?.Key.LegId);
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

        if (!Itinerary.TryBuildPlan(out _, out error))
        {
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
        var warnings = new List<string>();
        var recordedRoutes = new List<RouteResult>();
        foreach (var outcome in result.Outcomes)
        {
            if (outcome.Acquisition is not null)
            {
                _acquisitions[outcome.Model] = [outcome.Acquisition];
            }

            if (outcome.Route is not null)
            {
                var route = outcome.Route;
                string status;
                if (route.IsForecastLimited)
                {
                    status =
                        $"{(IsExperimentalDownload(result.Request, outcome.Model) ? "Experimental · " : string.Empty)}" +
                        $"forecast ended · best estimate through {route.ArrivalTime:MMM d HH:mm} UTC";
                    warnings.Add(
                        $"{ModelName(outcome.Model)} route calculation ended because there is no more " +
                        $"available forecast after {route.ArrivalTime:yyyy-MM-dd HH:mm} UTC. " +
                        "The displayed route to the latest forecast point is the best estimate for now; " +
                        "the destination was not reached.");
                }
                else
                {
                    status =
                        $"{(IsExperimentalDownload(result.Request, outcome.Model) ? "Experimental · " : string.Empty)}" +
                        $"complete · arrival {route.ArrivalTime:MMM d HH:mm} UTC";
                    if (route.ExceedsRequestedArrival)
                    {
                        status +=
                            $" · estimated arrival is {FormatOverDuration(route.ArrivalTime - route.Request.LatestArrivalTime)} " +
                            "beyond the expected passage duration";
                    }
                }

                if (route.LandAvoidance.HasWarning)
                {
                    status += " · land avoidance not applied";
                }
                else if (route.LandAvoidance.IsApplied)
                {
                    status += " · land avoidance applied";
                }

                SetModelStatus(outcome.Model, status);
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

        foreach (var outcome in result.Outcomes)
        {
            var reason = outcome.Route is not null
                ? outcome.Route.IsForecastLimited
                    ? RouteLegOutcomeReason.ForecastExhausted
                    : RouteLegOutcomeReason.CalculationSucceeded
                : outcome.Failure!.Stage switch
                {
                    ModelRouteFailureStage.ForecastAcquisition =>
                        RouteLegOutcomeReason.ForecastAcquisitionFailed,
                    ModelRouteFailureStage.RouteCalculation =>
                        RouteLegOutcomeReason.RouteCalculationFailed,
                    _ => RouteLegOutcomeReason.ResultValidationFailed
                };
            var recordedRoute = Itinerary.RecordSingleLegOutcome(
                outcome.Model,
                outcome.Route,
                reason,
                outcome.Failure?.Message,
                _timeProvider.GetUtcNow());
            if (recordedRoute is not null)
            {
                recordedRoutes.Add(recordedRoute);
            }
        }

        var routes = recordedRoutes.ToImmutableArray();
        if (Itinerary.CurrentPlan is { } plan)
        {
            DisplayPlanVisualization(plan, fit: true);
            routes = _mapLayers.Routes.ToImmutableArray();
        }
        else
        {
            DisplayRoutes(routes);
        }
        _displayedRoutePlanId = Itinerary.PlanId;
        ProgressFraction = 1;
        ErrorMessage = failures.Count == 0 ? null : string.Join(Environment.NewLine, failures);
        WarningMessage = warnings.Count == 0 ? null : string.Join(Environment.NewLine, warnings);
        var forecastLimitedCount = routes.Count(route => route.IsForecastLimited);
        UpdateLandAvoidanceWarning(routes);
        StatusMessage = (routes.Length, forecastLimitedCount, failures.Count) switch
        {
            (0, _, _) => "No model produced a route.",
            (1, 1, _) => "A route estimate is available through the latest forecast point.",
            (1, 0, > 0) => "One route is available; another selected model failed.",
            (1, 0, _) => "Route calculation complete.",
            (_, > 0, > 0) => "Route estimates are available; forecast coverage or another model limited the result.",
            (_, > 0, _) => "Routes are available; at least one ends at its latest forecast point.",
            _ => "Both model routes are available."
        };
        OnPropertyChanged(nameof(SelectedRouteDetails));
        UpdateWeatherAvailability();
    }

    private void DisplayPlanVisualization(RoutePlan plan, bool fit)
    {
        var previousSelection = SelectedLeg?.Key;
        _visualizationLegs = RoutePlanVisualization.Create(plan)
            .Select(leg => IsVisualizationCurrent(leg)
                ? leg
                : leg with
                {
                    State = RouteLegOutcomeState.Invalidated,
                    Reason = RouteLegOutcomeReason.WaypointCoordinateChanged,
                    Route = null,
                    Detail = "The edited waypoint boundaries no longer match this saved geometry."
                })
            .ToImmutableArray();
        var successful = _visualizationLegs.Where(leg => leg.HasOptimizedGeometry).ToArray();
        var reboundSelection = previousSelection is { } key
            ? _visualizationLegs.FirstOrDefault(leg => leg.Key == key) ??
              _visualizationLegs.FirstOrDefault(leg =>
                  leg.Key.PlanId == key.PlanId &&
                  leg.Key.LegId == key.LegId &&
                  leg.Key.Model == key.Model)
            : null;
        SelectedLeg = reboundSelection;
        var selectedKey = reboundSelection?.HasOptimizedGeometry is true
            ? reboundSelection.Key
            : (RouteVisualizationKey?)null;
        _mapLayers.SetRouteLegs(successful, selectedKey);
        if (fit)
        {
            _mapLayers.FitRoutes();
        }

        OnPropertyChanged(nameof(SuccessfulRouteCount));
        OnPropertyChanged(nameof(VisualizedRouteLegs));
        NotifyRouteModelAvailability();
        var model = ActiveRouteModel is { } active &&
                    successful.Any(leg => leg.Key.Model == active)
            ? active
            : successful.FirstOrDefault(leg => leg.Key.Model == ForecastModel.NoaaGfs)?.Key.Model ??
              successful.FirstOrDefault()?.Key.Model;
        if (ActiveRouteModel != model)
        {
            ActiveRouteModel = model;
        }
        else
        {
            BuildTimeline(model);
        }

        UpdateLandAvoidanceWarning(successful.Select(leg => leg.Route!));
    }

    private bool IsVisualizationCurrent(RouteLegVisualization leg)
    {
        if (leg.IsSailed)
        {
            return true;
        }

        if (leg.Route is not { } route ||
            leg.LegIndex < 0 ||
            leg.LegIndex + 1 >= Itinerary.Waypoints.Count ||
            Itinerary.Waypoints[leg.LegIndex].Coordinate is not { } from ||
            Itinerary.Waypoints[leg.LegIndex + 1].Coordinate is not { } to)
        {
            return leg.Route is null;
        }

        var validOrigin = route.Request.Origin.IsSameLocation(from) ||
                          (Itinerary.CurrentPositionCoordinate is { } current &&
                           route.Request.Origin.IsSameLocation(current));
        return validOrigin && route.Request.Destination.IsSameLocation(to);
    }

    private ImmutableArray<RouteLegVisualization> CreateTransientVisualizations(
        IEnumerable<RouteResult> routes)
    {
        var plan = Itinerary.CurrentPlan;
        var fallbackFrom = new RouteWaypoint("Start", Start ?? new Coordinate(0, 0));
        var fallbackTo = new RouteWaypoint("Finish", Destination ?? new Coordinate(0, 1));
        var fallbackLeg = RouteLeg.Create(0, fallbackFrom, fallbackTo);
        return routes.Select(route =>
        {
            var leg = plan?.Legs.FirstOrDefault(candidate =>
                route.Request.Origin.IsSameLocation(
                    plan.Waypoints.Single(waypoint => waypoint.Id == candidate.FromWaypointId).Coordinate) &&
                route.Request.Destination.IsSameLocation(
                    plan.Waypoints.Single(waypoint => waypoint.Id == candidate.ToWaypointId).Coordinate));
            var from = leg is null
                ? fallbackFrom
                : plan!.Waypoints.Single(waypoint => waypoint.Id == leg.FromWaypointId);
            var to = leg is null
                ? fallbackTo
                : plan!.Waypoints.Single(waypoint => waypoint.Id == leg.ToWaypointId);
            var legId = leg?.Id ?? fallbackLeg.Id;
            var sessionId = new RouteCalculationSessionId();
            return new RouteLegVisualization(
                new RouteVisualizationKey(
                    plan?.Id ?? Itinerary.PlanId,
                    legId,
                    route.Model,
                    sessionId,
                    route.Request.RouteId),
                leg?.Index ?? 0,
                from,
                to,
                RouteLegOutcomeState.Succeeded,
                route.IsForecastLimited
                    ? RouteLegOutcomeReason.ForecastExhausted
                    : RouteLegOutcomeReason.CalculationSucceeded,
                route,
                null,
                plan?.SailedLegIds.Contains(legId) is true,
                route.Request.DepartureTime,
                route.ArrivalTime);
        }).ToImmutableArray();
    }

    private void SelectLegGeometry(RouteVisualizationKey key)
    {
        var leg = _visualizationLegs.SingleOrDefault(item => item.Key == key);
        if (leg is null)
        {
            return;
        }

        SelectedLeg = leg;
        _mapLayers.SelectRouteLeg(leg.HasOptimizedGeometry ? key : null);
        Itinerary.SetSelectedLeg(leg.Key.LegId);
    }

    private void NotifyRouteModelAvailability()
    {
        OnPropertyChanged(nameof(HasNoaaRoutes));
        OnPropertyChanged(nameof(HasEcmwfRoutes));
        ActivateNoaaRouteCommand.NotifyCanExecuteChanged();
        ActivateEcmwfRouteCommand.NotifyCanExecuteChanged();
    }

    private string FormatSelectedLegDetails(RouteLegVisualization leg)
    {
        var state = VisualizationStatusName(leg);
        var sailed = leg.IsSailed ? " · sailed history" : string.Empty;
        var session = $"session {leg.Key.SessionId} · started {leg.SessionStartedAt:yyyy-MM-dd HH:mm} UTC" +
                      $"{(leg.SessionCompletedAt is { } completed ? $" · saved {completed:yyyy-MM-dd HH:mm} UTC" : string.Empty)}";
        var outcome = leg.Route is not { } route
            ? $"{state}{sailed}{(string.IsNullOrWhiteSpace(leg.Detail) ? string.Empty : $" · {leg.Detail}")}"
            : $"{state}{sailed} · depart {route.Request.DepartureTime:yyyy-MM-dd HH:mm} UTC · " +
              $"{(route.IsForecastLimited ? "forecast endpoint" : "arrive")} {route.ArrivalTime:yyyy-MM-dd HH:mm} UTC · " +
              $"{FormatDuration(route.ArrivalTime - route.Request.DepartureTime)} · " +
              $"{route.Points[^1].CumulativeDistanceNauticalMiles:0.0} NM" +
              $"{(route.LandAvoidance.HasWarning ? $" · warning: {route.LandAvoidance.Warning}" : string.Empty)}";
        var comparison = _visualizationLegs
            .Where(other => other.Key.LegId == leg.Key.LegId && other.Key.Model != leg.Key.Model)
            .Select(other => $"{ModelShortName(other.Key.Model)} {VisualizationStatusName(other)}" +
                (other.Route is null ? string.Empty : $" · arrival {other.Route.ArrivalTime:MMM d HH:mm} UTC"))
            .ToArray();
        return $"{leg.From.Name} ({FormatCoordinate(leg.From.Coordinate, "unknown")}) → " +
               $"{leg.To.Name} ({FormatCoordinate(leg.To.Coordinate, "unknown")})\n" +
               $"{outcome}\n{session}" +
               $"{(comparison.Length == 0 ? string.Empty : $"\nComparison: {string.Join(" · ", comparison)}")}\n";
    }

    private static string VisualizationStatusName(RouteLegVisualization leg) =>
        leg.IsSailed ? "sailed" : leg.State switch
        {
            RouteLegOutcomeState.Succeeded
                when leg.Reason == RouteLegOutcomeReason.ForecastExhausted => "forecast-limited",
            RouteLegOutcomeState.Succeeded => "complete",
            RouteLegOutcomeState.Failed => "failed",
            RouteLegOutcomeState.Cancelled => "cancelled",
            RouteLegOutcomeState.Blocked => "blocked by prior failure",
            RouteLegOutcomeState.OutsideForecastWindow => "outside forecast window",
            RouteLegOutcomeState.Invalidated => "stale",
            _ => "not calculated"
        };

    private static string FormatDuration(TimeSpan duration) =>
        $"{(int)duration.TotalHours}h {duration.Minutes:00}m";

    private void UpdateLandAvoidanceWarning(IEnumerable<RouteResult> routes)
    {
        var warnings = routes
            .Select(route => route.LandAvoidance.Warning)
            .Where(warning => !string.IsNullOrWhiteSpace(warning))
            .Distinct(StringComparer.Ordinal)
            .ToArray();
        LandAvoidanceWarning = warnings.Length == 0
            ? null
            : string.Join(Environment.NewLine, warnings);
    }

    private void BuildTimeline(ForecastModel? model)
    {
        var legs = model is null
            ? []
            : _visualizationLegs
                .Where(leg => leg.Key.Model == model && leg.HasOptimizedGeometry)
                .ToArray();
        if (legs.Length == 0)
        {
            _timeline = null;
            HasTimeline = false;
            SelectedTimelineUtc = null;
            SelectedRoutePoint = null;
            if (SelectedLeg is { } selected &&
                !_visualizationLegs.Any(leg => leg.Key == selected.Key))
            {
                SelectedLeg = null;
            }
            _selectedStopoverLabel = null;
            OnPropertyChanged(nameof(TimelineDisplay));
            return;
        }

        _timeline = SharedRouteTimeline.Create(model!.Value, legs);
        HasTimeline = true;
        SetTimelineUtc(_timeline.Start);
        ApplyTimelineSelection();
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

    private void ApplyTimelineSelection()
    {
        if (_timeline is null || SelectedTimelineUtc is null)
        {
            return;
        }

        var candidate = _timeline.Select(SelectedTimelineUtc.Value);
        var route = candidate.Leg.Route!;
        var pointIndex = candidate.IsStopover
            ? route.Points.Length - 1
            : route.Points.IndexOf(candidate.Point);
        _selectedStopoverLabel = candidate.StopoverLabel;
        SelectedRoutePoint = new RouteMapSelection(
            candidate.Leg,
            Math.Max(0, pointIndex),
            candidate.Point,
            RouteHitKind.RoutePoint,
            0);
        SelectLegGeometry(candidate.Leg.Key);
        OnPropertyChanged(nameof(TimelineDisplay));
        UpdateWeatherAvailability();
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
            FindCompatibleAcquisition(SelectedRoutePoint?.Leg, model) is not { } acquisition)
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

    private ForecastAcquisition? FindCompatibleAcquisition(
        RouteLegVisualization? leg,
        ForecastModel model)
    {
        if (leg?.Route is not { } route ||
            leg.Key.Model != model ||
            !_acquisitions.TryGetValue(model, out var acquisitions))
        {
            return null;
        }

        return acquisitions
            .Where(acquisition =>
                acquisition.Request.Model == model &&
                acquisition.Request.From <= route.Request.DepartureTime &&
                acquisition.Request.Through >= route.ArrivalTime &&
                acquisition.Request.Bounds.Contains(route.Request.Origin) &&
                acquisition.Request.Bounds.Contains(route.Request.Destination))
            .OrderByDescending(acquisition => acquisition.Request.From)
            .FirstOrDefault();
    }

    private void UpdateWeatherAvailability()
    {
        var selectedLeg = SelectedRoutePoint?.Leg;
        HasNoaaWeather = FindCompatibleAcquisition(selectedLeg, ForecastModel.NoaaGfs) is not null;
        HasEcmwfWeather = FindCompatibleAcquisition(selectedLeg, ForecastModel.EcmwfIfs) is not null;
        var selectedModel = selectedLeg?.Key.Model;
        var compatible = selectedModel is { } model &&
                         FindCompatibleAcquisition(selectedLeg, model) is not null;
        ActiveWeatherModel = compatible ? selectedModel : null;
        if (!compatible)
        {
            CancelWeather();
            WeatherLayerError = selectedLeg is null
                ? "Select a calculated leg to view weather."
                : "Weather is unavailable for this saved leg/model. Route geometry and details remain available.";
        }
        else
        {
            WeatherLayerError = null;
            RequestWeatherRefreshFromViewport();
        }
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
        OnPropertyChanged(nameof(IsSettingStart));
        OnPropertyChanged(nameof(IsSettingDestination));
        OnPropertyChanged(nameof(IsEndpointPlacementArmed));
        OnPropertyChanged(nameof(IsSettingWaypoint));
        OnPropertyChanged(nameof(IsSettingCurrentPosition));
        ClearCurrentPositionCommand.NotifyCanExecuteChanged();
        UpdateWaypointLayers();
        _mapLayers.SetCurrentPosition(Itinerary.CurrentPositionCoordinate);
        UpdateForecastAreaSummary();
    }

    private void CompleteEndpointPlacement()
    {
        NotifyInteractionChanged();
        StatusMessage = Start is not null && Destination is not null
            ? Itinerary.Waypoints.Count == 2
                ? "Endpoints ready. Choose forecast models and calculate."
                : "Itinerary ready. Choose forecast models and calculate."
            : "Endpoint placed. Set the remaining endpoint.";
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

    private static MRect CreateDefaultChartExtent()
    {
        var bounds = GeographicBounds.FromCoordinates(DefaultChartLocations);
        var latitudePadding = DefaultChartBufferNauticalMiles / 60d;
        var south = bounds.South - latitudePadding;
        var north = bounds.North + latitudePadding;
        var polewardLatitude = Math.Max(Math.Abs(south), Math.Abs(north));
        var longitudePadding = DefaultChartBufferNauticalMiles /
            (60d * Math.Cos(polewardLatitude * Math.PI / 180d));
        var lowerLeft = MapProjection.ToMapPoint(
            new Coordinate(south, bounds.West - longitudePadding));
        var upperRight = MapProjection.ToMapPoint(
            new Coordinate(north, bounds.East + longitudePadding));
        return new MRect(lowerLeft.X, lowerLeft.Y, upperRight.X, upperRight.Y);
    }

    private static string FormatBounds(GeographicBounds bounds) =>
        $"{bounds.South:0.##}° to {bounds.North:0.##}° latitude, " +
        $"{bounds.West:0.##}° to {bounds.East:0.##}° longitude";

    private static bool IsExperimentalDownload(
        RoutingWorkflowRequest request,
        ForecastModel model) =>
        IsExperimentalDownload(request.Selections, model);

    private static bool IsExperimentalDownload(
        IEnumerable<ForecastSelection> selections,
        ForecastModel model) =>
        model == ForecastModel.EcmwfIfs &&
        selections.Any(selection =>
            selection.Model == model &&
            selection.Kind == ForecastSelectionKind.OfficialDownload);

    private static string PlanProgressStageName(RoutePlanRoutingUnitStatus status) => status switch
    {
        RoutePlanRoutingUnitStatus.AcquiringForecast => "acquiring",
        RoutePlanRoutingUnitStatus.CalculatingRoute => "routing",
        RoutePlanRoutingUnitStatus.Succeeded => "complete",
        RoutePlanRoutingUnitStatus.ForecastLimited => "forecast-limited",
        RoutePlanRoutingUnitStatus.Failed => "failed",
        RoutePlanRoutingUnitStatus.Cancelled => "cancelled",
        RoutePlanRoutingUnitStatus.Blocked => "blocked",
        RoutePlanRoutingUnitStatus.OutsideForecastWindow => "outside forecast window",
        _ => status.ToString()
    };

    private static string LegStatusName(RouteLegResult leg, bool isSailed = false)
    {
        if (isSailed)
        {
            return "sailed";
        }

        return leg.State switch
        {
            RouteLegOutcomeState.Succeeded
                when leg.Reason == RouteLegOutcomeReason.ForecastExhausted => "forecast-limited",
            RouteLegOutcomeState.Succeeded => "complete",
            RouteLegOutcomeState.Failed => "failed",
            RouteLegOutcomeState.Cancelled => "cancelled",
            RouteLegOutcomeState.Blocked => "blocked by prior failure",
            RouteLegOutcomeState.OutsideForecastWindow => "outside forecast window",
            RouteLegOutcomeState.Invalidated
                when leg.Reason == RouteLegOutcomeReason.CurrentPositionChanged =>
                "active reroute pending (current position changed)",
            RouteLegOutcomeState.Invalidated => "invalidated",
            _ => "not calculated"
        };
    }

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

    private static string ModelShortName(ForecastModel model) =>
        model == ForecastModel.NoaaGfs ? "NOAA" : "ECMWF";

    private static string FormatApparentWind(RoutePoint point)
    {
        var signedAngle = point.ApparentWindAngleSignedDegrees;
        var roundedAngle = (int)Math.Round(Math.Abs(signedAngle), MidpointRounding.AwayFromZero);
        if (roundedAngle <= 0)
        {
            return "apparent wind 0° ahead";
        }

        if (roundedAngle >= 180)
        {
            return "apparent wind 180° astern";
        }

        var side = signedAngle > 0d ? "starboard" : "port";
        return $"apparent wind {roundedAngle:0}° {side}";
    }

    private static string FormatOverDuration(TimeSpan overrun)
    {
        if (overrun < TimeSpan.Zero)
        {
            overrun = TimeSpan.Zero;
        }

        var hours = (int)overrun.TotalHours;
        var minutes = overrun.Minutes;
        if (hours > 0)
        {
            return $"{hours}h {minutes}m";
        }

        return minutes > 0 ? $"{minutes}m" : $"{overrun.Seconds}s";
    }

    private void OnMapPlacementStarted(
        object? sender,
        WaypointEditorItemViewModel waypoint)
    {
        _interaction.Activate(waypoint.IsStart
            ? MapInteractionMode.SetStart
            : waypoint.IsFinish
                ? MapInteractionMode.SetDestination
                : MapInteractionMode.SetWaypoint);
        NotifyInteractionChanged();
    }

    private void OnCurrentPositionPlacementStarted(object? sender, EventArgs e)
    {
        _interaction.Activate(MapInteractionMode.SetCurrentPosition);
        NotifyInteractionChanged();
    }

    private void OnLegSelected(object? sender, RouteLegId legId)
    {
        var candidates = _visualizationLegs.Where(leg => leg.Key.LegId == legId).ToArray();
        if (candidates.Length == 0)
        {
            SelectedRoutePoint = null;
            SelectedLeg = null;
            _selectedStopoverLabel = null;
            _mapLayers.SelectRouteLeg(null);
            UpdateWeatherAvailability();
            Itinerary.SetSelectedLeg(legId);
            StatusMessage = "This leg has not been calculated by any forecast model.";
            return;
        }

        var target = candidates.FirstOrDefault(leg => leg.Key.Model == ActiveRouteModel) ??
                     candidates.FirstOrDefault(leg => leg.HasOptimizedGeometry) ??
                     candidates[0];
        if (target.Key.Model != ActiveRouteModel)
        {
            ActiveRouteModel = target.Key.Model;
        }

        SelectLegGeometry(target.Key);
        if (target.Route is { } route)
        {
            SetTimelineUtc(route.Request.DepartureTime);
            SelectedRoutePoint = new RouteMapSelection(
                target,
                0,
                route.Points[0],
                RouteHitKind.RoutePoint,
                0);
        }
        else
        {
            SelectedRoutePoint = null;
            UpdateWeatherAvailability();
        }
    }

    private void OnItineraryChanged(object? sender, EventArgs e)
    {
        if (IsCalculating &&
            (_activeCalculationPlanId != Itinerary.PlanId ||
             _activeCalculationRevision != Itinerary.CalculationRevision))
        {
            Interlocked.Increment(ref _calculationGeneration);
            var cancellation = Interlocked.Exchange(ref _calculationCancellation, null);
            cancellation?.Cancel();
            cancellation?.Dispose();
            _mapLayers.ClearCalculationOverlays();
            IsCalculating = false;
            _activeCalculationPlanId = null;
            StatusMessage = "Calculation cancelled because the itinerary changed.";
        }

        if (Itinerary.ActiveWaypoint is null && !Itinerary.IsAwaitingCurrentPositionPlacement)
        {
            _interaction.Activate(MapInteractionMode.Browse);
        }

        if (Itinerary.Start is { } start)
        {
            _interaction.SetStart(start);
        }

        if (Itinerary.Finish is { } finish)
        {
            _interaction.SetDestination(finish);
        }

        if (Itinerary.CurrentPlan is { } plan)
        {
            if (_displayedRoutePlanId is { } displayedPlanId && displayedPlanId != plan.Id)
            {
                _acquisitions.Clear();
            }

            DisplayPlanVisualization(plan, fit: _displayedRoutePlanId != plan.Id);
            _displayedRoutePlanId = plan.Id;
            UpdateWeatherAvailability();
        }
        else if (_mapLayers.Routes.Count > 0 || !_visualizationLegs.IsEmpty)
        {
            _visualizationLegs = [];
            _mapLayers.SetRouteLegs([]);
            _displayedRoutePlanId = null;
            BuildTimeline(null);
            _acquisitions.Clear();
            HasNoaaWeather = false;
            HasEcmwfWeather = false;
            ActiveWeatherModel = null;
            SelectedLeg = null;
            OnPropertyChanged(nameof(SuccessfulRouteCount));
            OnPropertyChanged(nameof(VisualizedRouteLegs));
            NotifyRouteModelAvailability();
            LandAvoidanceWarning = null;
        }

        NotifyInteractionChanged();
    }

    private void UpdateWaypointLayers() =>
        _mapLayers.SetWaypoints(Itinerary.Waypoints.Select(waypoint =>
            new WaypointMapMarker(waypoint.Position, waypoint.Name, waypoint.Coordinate)));
}
