using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.Primitives;
using Avalonia.Controls.Shapes;
using Avalonia.Input;
using Avalonia.Interactivity;
using Avalonia.Markup.Xaml;
using Avalonia.Platform.Storage;
using Avalonia.Threading;
using Avalonia.VisualTree;
using Mapsui;
using Mapsui.Extensions;
using Mapsui.Manipulations;
using Mapsui.UI.Avalonia;
using Navtool.App.Models;
using Navtool.App.Services;
using Navtool.App.ViewModels;
using Navtool.Infrastructure;

namespace Navtool.App.Views;

public partial class MainWindow : Window
{
    internal enum WorkingPanel
    {
        Plan,
        Results,
        Settings
    }

    internal const double DefaultPanelWidth = 400;
    internal const double MinimumPanelWidth = 320;
    internal const double MinimumMapWidth = 560;
    private const double SplitterWidth = 6;

    private const double RadialActionWidth = 112;
    private const double RadialActionHeight = 48;
    private const double RadialRadius = 104;
    private const double RadialSafeMargin = 16;
    private const double RouteTelemetryWidth = 296;
    private const double RouteTelemetryHeight = 132;
    private const double RouteTelemetryGap = 18;
    private const double RouteTelemetrySafeMargin = 12;
    private static AppThemeService? _defaultThemeService;
    private static readonly FilePickerFileType GribFileType = new("GRIB forecasts")
    {
        Patterns = ["*.grib", "*.grb", "*.grib2", "*.grb2", "*.gri"],
        MimeTypes = ["application/octet-stream"]
    };

    private readonly AppThemeService _themeService;
    private Navigator? _subscribedNavigator;
    private MapControl? _mapControl;
    private ColumnDefinition? _planningDrawerColumn;
    private Border? _planningDrawerContent;
    private Border? _routeDrawerContent;
    private ToggleButton? _planningDrawerHandle;
    private ToggleButton? _routeDrawerHandle;
    private Canvas? _radialMenuLayer;
    private Button? _setStartRadialButton;
    private Button? _setDestinationRadialButton;
    private Button? _addWaypointRadialButton;
    private Button? _calculateRadialButton;
    private ToggleButton? _refreshWeatherRadialToggle;
    private Line? _radialConnector;
    private Ellipse? _radialAnchor;
    private Canvas? _routeTelemetryLayer;
    private Button? _routeTelemetryCard;
    private Line? _routeTelemetryConnector;
    private Ellipse? _routeTelemetryAnchor;
    private ListBox? _waypointList;
    private MainViewModel? _subscribedViewModel;
    private RouteMapSelection? _routeTelemetrySelection;
    private MPoint? _routeTelemetryProjection;
    private ScreenPoint? _lastPointerPosition;
    private MPoint? _capturedWorldPoint;
    private WorkingPanel _previousPanel = WorkingPanel.Plan;
    private double _panelWidth = DefaultPanelWidth;
    private readonly Dictionary<WorkingPanel, Control> _panelFocus = [];
    private readonly Dictionary<WorkingPanel, Vector> _panelScroll = [];
    private Navtool.Core.RoutePlanId? _displayedPlanId;

    public MainWindow() : this(GetDefaultThemeService())
    {
    }

    public MainWindow(AppThemeService themeService)
    {
        ArgumentNullException.ThrowIfNull(themeService);
        _themeService = themeService;
        AvaloniaXamlLoader.Load(this);
        InitializeControls();
        Loaded += OnLoaded;
        Closed += OnClosed;
        SizeChanged += OnWindowSizeChanged;
        Deactivated += OnWindowDeactivated;
        KeyDown += OnWindowKeyDown;
        AddHandler(PointerPressedEvent, OnWindowPointerPressed, RoutingStrategies.Tunnel);
    }

    internal bool IsPanelOpen { get; private set; } = true;

    internal WorkingPanel SelectedPanel { get; private set; } = WorkingPanel.Plan;

    internal bool IsPlanningDrawerOpen => IsPanelOpen && SelectedPanel == WorkingPanel.Plan;

    internal bool IsRouteDrawerOpen => IsPanelOpen && SelectedPanel == WorkingPanel.Results;

    internal bool IsRadialMenuOpen => _radialMenuLayer?.IsVisible is true;

    internal static double MaximumPanelWidth(double windowWidth) =>
        Math.Max(MinimumPanelWidth, windowWidth - MinimumMapWidth - SplitterWidth);

    private void InitializeControls()
    {
        var themeSelector = this.FindControl<ComboBox>("ThemeSelector")!;
        themeSelector.ItemsSource = AppThemeService.AvailableThemes;
        themeSelector.SelectedItem = AppThemeService.AvailableThemes.Single(
            option => option.Theme == _themeService.SelectedTheme);
        themeSelector.SelectionChanged += OnThemeSelectionChanged;

        _mapControl = this.FindControl<MapControl>("MapView")!;
        _mapControl.MapTapped += OnMapTapped;
        _mapControl.PointerMoved += OnMapPointerMoved;
        _mapControl.AddHandler(
            PointerPressedEvent,
            OnMapPointerPressed,
            RoutingStrategies.Tunnel);

        var shellGrid = this.FindControl<Grid>("ShellGrid")!;
        _planningDrawerColumn = shellGrid.ColumnDefinitions[0];
        _planningDrawerContent = this.FindControl<Border>("PlanningDrawerContent")!;
        _routeDrawerContent = this.FindControl<Border>("RouteDrawerContent")!;
        _planningDrawerHandle = this.FindControl<ToggleButton>("PlanningDrawerHandle")!;
        _routeDrawerHandle = this.FindControl<ToggleButton>("RouteDrawerHandle")!;

        _radialMenuLayer = this.FindControl<Canvas>("RadialMenuLayer")!;
        _setStartRadialButton = this.FindControl<Button>("SetStartRadialButton")!;
        _setDestinationRadialButton = this.FindControl<Button>("SetDestinationRadialButton")!;
        _addWaypointRadialButton = this.FindControl<Button>("AddWaypointRadialButton")!;
        _calculateRadialButton = this.FindControl<Button>("CalculateRadialButton")!;
        _refreshWeatherRadialToggle =
            this.FindControl<ToggleButton>("RefreshWeatherRadialToggle")!;
        _radialConnector = this.FindControl<Line>("RadialConnector")!;
        _radialAnchor = this.FindControl<Ellipse>("RadialAnchor")!;
        _routeTelemetryLayer = this.FindControl<Canvas>("RouteTelemetryLayer")!;
        _routeTelemetryCard = this.FindControl<Button>("RouteTelemetryCard")!;
        _routeTelemetryConnector = this.FindControl<Line>("RouteTelemetryConnector")!;
        _routeTelemetryAnchor = this.FindControl<Ellipse>("RouteTelemetryAnchor")!;
        _waypointList = this.FindControl<ListBox>("WaypointList")!;
        ApplyPanelState();
    }

    private void OnLoaded(object? sender, RoutedEventArgs e)
    {
        if (DataContext is not MainViewModel viewModel)
        {
            return;
        }

        _subscribedViewModel = viewModel;
        _subscribedViewModel.RouteSelectionChanged += OnRouteSelectionChanged;
        _subscribedViewModel.RoutePointInspectionRequested += OnRoutePointInspectionRequested;
        _subscribedViewModel.Itinerary.WaypointSelectionChanged += OnWaypointSelectionChanged;
        _displayedPlanId = viewModel.Itinerary.PlanId;
        _subscribedViewModel.Itinerary.ItineraryChanged += OnItineraryChanged;
        _subscribedViewModel.PropertyChanged += OnViewModelPropertyChanged;
        _subscribedViewModel.RoutingSetup.PropertyChanged += OnRoutingSetupPropertyChanged;
        _subscribedNavigator = viewModel.Map.Navigator;
        _subscribedNavigator.ViewportChanged += OnViewportChanged;
        ScheduleRouteTelemetryRefresh();
        ScheduleWeatherRefresh();
        ScheduleMessageRefresh();
    }

    private void OnClosed(object? sender, EventArgs e)
    {
        this.FindControl<ComboBox>("ThemeSelector")!.SelectionChanged -= OnThemeSelectionChanged;
        if (_mapControl is not null)
        {
            _mapControl.MapTapped -= OnMapTapped;
            _mapControl.PointerMoved -= OnMapPointerMoved;
            _mapControl.RemoveHandler(PointerPressedEvent, OnMapPointerPressed);
        }

        if (_subscribedNavigator is not null)
        {
            _subscribedNavigator.ViewportChanged -= OnViewportChanged;
        }

        if (_subscribedViewModel is not null)
        {
            _subscribedViewModel.RouteSelectionChanged -= OnRouteSelectionChanged;
            _subscribedViewModel.RoutePointInspectionRequested -= OnRoutePointInspectionRequested;
            _subscribedViewModel.Itinerary.WaypointSelectionChanged -= OnWaypointSelectionChanged;
            _subscribedViewModel.Itinerary.ItineraryChanged -= OnItineraryChanged;
            _subscribedViewModel.PropertyChanged -= OnViewModelPropertyChanged;
            _subscribedViewModel.RoutingSetup.PropertyChanged -= OnRoutingSetupPropertyChanged;
        }

        Loaded -= OnLoaded;
        Closed -= OnClosed;
        SizeChanged -= OnWindowSizeChanged;
        Deactivated -= OnWindowDeactivated;
        KeyDown -= OnWindowKeyDown;
        RemoveHandler(PointerPressedEvent, OnWindowPointerPressed);
    }

    private void OnThemeSelectionChanged(object? sender, SelectionChangedEventArgs e)
    {
        if (sender is ComboBox { SelectedItem: AppThemeOption option })
        {
            _themeService.SelectTheme(option.Theme);
        }
    }

    private void OnViewportChanged(object? sender, ViewportChangedEventArgs e)
    {
        CloseRadialMenu();
        ScheduleRouteTelemetryRefresh();
        if (DataContext is MainViewModel viewModel)
        {
            viewModel.RequestWeatherRefreshFromViewport();
        }
    }

    private void OnMapTapped(object? sender, MapEventArgs e)
    {
        if (e.GestureType == GestureType.LongPress)
        {
            OpenRadialMenu(
                e.WorldPosition,
                new ScreenPoint(e.ScreenPosition.X, e.ScreenPosition.Y));
            e.Handled = true;
            return;
        }

        if (e.GestureType == GestureType.SingleTap &&
            DataContext is MainViewModel viewModel)
        {
            viewModel.HandleMapClick(e.WorldPosition, e.ScreenPosition);
            e.Handled = true;
        }
    }

    internal static bool IsRadialGesture(GestureType gestureType) =>
        gestureType == GestureType.LongPress;

    private void OnMapPointerPressed(object? sender, PointerPressedEventArgs e)
    {
        if (_mapControl is null ||
            !e.GetCurrentPoint(_mapControl).Properties.IsRightButtonPressed)
        {
            return;
        }

        // Tunneling handles the secondary press before Mapsui starts a manipulation.
        e.Handled = true;
        var position = e.GetPosition(_mapControl);
        var screenPosition = new ScreenPoint(position.X, position.Y);
        _lastPointerPosition = screenPosition;
        OpenRadialMenu(
            _mapControl.Map.Navigator.Viewport.ScreenToWorld(position.X, position.Y),
            screenPosition);
    }

    private void OnMapPointerMoved(object? sender, PointerEventArgs e)
    {
        if (_mapControl is null)
        {
            return;
        }

        var position = e.GetPosition(_mapControl);
        _lastPointerPosition = new ScreenPoint(position.X, position.Y);
    }

    private void OnWindowPointerPressed(object? sender, PointerPressedEventArgs e)
    {
        if (!IsRadialMenuOpen ||
            IsRadialActionSource(e.Source) ||
            IsRadialActionPointer(e))
        {
            return;
        }

        CloseRadialMenu();
        e.Handled = true;
    }

    private bool IsRadialActionSource(object? source)
    {
        if (source is not Visual visual)
        {
            return false;
        }

        return IsRadialAction(visual) ||
               visual.GetVisualAncestors().Any(IsRadialAction);
    }

    private bool IsRadialAction(Visual visual) =>
        visual == _setStartRadialButton ||
        visual == _setDestinationRadialButton ||
        visual == _addWaypointRadialButton ||
        visual == _calculateRadialButton ||
        visual == _refreshWeatherRadialToggle;

    private bool IsRadialActionPointer(PointerEventArgs e)
    {
        if (_radialMenuLayer is null)
        {
            return false;
        }

        var position = e.GetPosition(_radialMenuLayer);
        return new Control?[]
        {
            _setStartRadialButton,
            _setDestinationRadialButton,
            _addWaypointRadialButton,
            _calculateRadialButton,
            _refreshWeatherRadialToggle
        }.Any(control => control?.Bounds.Contains(position) is true);
    }

    private void OnWindowKeyDown(object? sender, KeyEventArgs e)
    {
        if (e.KeyModifiers.HasFlag(KeyModifiers.Control))
        {
            switch (e.Key)
            {
                case Key.D1: SelectPanel(WorkingPanel.Plan); break;
                case Key.D2: SelectPanel(WorkingPanel.Results); break;
                case Key.D3: SelectPanel(WorkingPanel.Settings); break;
                case Key.OemPipe: SetPanelOpen(!IsPanelOpen); break;
                default: return;
            }
            e.Handled = true;
            return;
        }

        if (e.Key == Key.Escape && IsRadialMenuOpen)
        {
            e.Handled = true;
            CloseRadialMenu();
            return;
        }

        if (e.Key == Key.Escape && IsMessagePopupOpen)
        {
            e.Handled = true;
            CloseMessages();
            return;
        }

        if (e.Key == Key.Escape && _routeTelemetrySelection is not null)
        {
            e.Handled = true;
            _subscribedViewModel?.ClearRoutePointSelection();
            return;
        }

        if (_mapControl?.IsKeyboardFocusWithin is true &&
            (e.Key == Key.Apps ||
             (e.Key == Key.F10 && e.KeyModifiers.HasFlag(KeyModifiers.Shift))))
        {
            e.Handled = true;
            OpenRadialMenuFromKeyboard();
        }
    }

    private void OpenRadialMenuFromKeyboard()
    {
        if (_mapControl is null)
        {
            return;
        }

        var width = _mapControl.Bounds.Width;
        var height = _mapControl.Bounds.Height;
        var screenPosition = _lastPointerPosition is { } last &&
                             last.X >= 0 &&
                             last.Y >= 0 &&
                             last.X <= width &&
                             last.Y <= height
            ? last
            : new ScreenPoint(width / 2, height / 2);
        OpenRadialMenu(
            _mapControl.Map.Navigator.Viewport.ScreenToWorld(
                screenPosition.X,
                screenPosition.Y),
            screenPosition);
    }

    internal void OpenRadialMenu(MPoint worldPoint, ScreenPoint screenPoint)
    {
        if (_mapControl is null ||
            _radialMenuLayer is null ||
            _setStartRadialButton is null ||
            _setDestinationRadialButton is null ||
            _addWaypointRadialButton is null ||
            _calculateRadialButton is null ||
            _refreshWeatherRadialToggle is null ||
            _radialConnector is null ||
            _radialAnchor is null ||
            DataContext is not MainViewModel viewModel ||
            _mapControl.Bounds.Width <= 0 ||
            _mapControl.Bounds.Height <= 0)
        {
            return;
        }

        _lastPointerPosition = screenPoint;
        _capturedWorldPoint = worldPoint;

        var placement = RadialMenuPlacement.Calculate(
            new ScreenRect(0, 0, _mapControl.Bounds.Width, _mapControl.Bounds.Height),
            screenPoint,
            new ScreenSize(RadialActionWidth, RadialActionHeight),
            RadialRadius,
            RadialSafeMargin);
        PositionRadialAction(
            _setStartRadialButton,
            GetActionBounds(placement, RadialMenuAction.SetStart));
        PositionRadialAction(
            _setDestinationRadialButton,
            GetActionBounds(placement, RadialMenuAction.SetDestination));
        PositionRadialAction(
            _addWaypointRadialButton,
            GetActionBounds(placement, RadialMenuAction.AddWaypoint));
        PositionRadialAction(
            _calculateRadialButton,
            GetActionBounds(placement, RadialMenuAction.CalculateRoute));
        PositionRadialAction(
            _refreshWeatherRadialToggle,
            GetActionBounds(placement, RadialMenuAction.RefreshWeather));
        ApplyConnector(placement);
        _radialMenuLayer.IsVisible = true;
        new Control[]
        {
            _addWaypointRadialButton,
            _setStartRadialButton,
            _setDestinationRadialButton,
            _calculateRadialButton,
            _refreshWeatherRadialToggle
        }.First(control => control.IsEffectivelyEnabled).Focus();
    }

    private void ApplyConnector(RadialMenuPlacementResult placement)
    {
        if (_radialConnector is null || _radialAnchor is null)
        {
            return;
        }

        _radialConnector.IsVisible = placement.Connector is not null;
        _radialAnchor.IsVisible = true;
        Canvas.SetLeft(_radialAnchor, placement.Anchor.X - (_radialAnchor.Width / 2));
        Canvas.SetTop(_radialAnchor, placement.Anchor.Y - (_radialAnchor.Height / 2));
        if (placement.Connector is not { } connector)
        {
            return;
        }

        _radialConnector.StartPoint = new Point(connector.Start.X, connector.Start.Y);
        _radialConnector.EndPoint = new Point(connector.End.X, connector.End.Y);
    }

    private static void PositionRadialAction(Control control, ScreenRect bounds)
    {
        control.Width = bounds.Width;
        control.Height = bounds.Height;
        Canvas.SetLeft(control, bounds.X);
        Canvas.SetTop(control, bounds.Y);
    }

    private static ScreenRect GetActionBounds(
        RadialMenuPlacementResult placement,
        RadialMenuAction action) =>
        placement.Actions.Single(candidate => candidate.Action == action).Bounds;

    private void OnSetStartRadialClicked(object? sender, RoutedEventArgs e)
    {
        e.Handled = true;
        if (_capturedWorldPoint is { } worldPoint &&
            DataContext is MainViewModel viewModel)
        {
            viewModel.SetStartAt(MapProjection.ToCoordinate(worldPoint));
        }

        CloseRadialMenu();
    }

    private void OnSetDestinationRadialClicked(object? sender, RoutedEventArgs e)
    {
        e.Handled = true;
        if (_capturedWorldPoint is { } worldPoint &&
            DataContext is MainViewModel viewModel)
        {
            viewModel.SetDestinationAt(MapProjection.ToCoordinate(worldPoint));
        }

        CloseRadialMenu();
    }

    private void OnAddWaypointRadialClicked(object? sender, RoutedEventArgs e)
    {
        e.Handled = true;
        if (_capturedWorldPoint is { } worldPoint &&
            DataContext is MainViewModel viewModel)
        {
            viewModel.AddWaypointAt(MapProjection.ToCoordinate(worldPoint));
        }

        CloseRadialMenu();
    }

    private void OnCalculateRadialClicked(object? sender, RoutedEventArgs e)
    {
        CloseRadialMenu();
    }

    private void CloseRadialMenu()
    {
        if (_radialMenuLayer is null || !_radialMenuLayer.IsVisible)
        {
            return;
        }

        _radialMenuLayer.IsVisible = false;
        _capturedWorldPoint = null;
        _mapControl?.Focus();
    }

    private void OnRouteSelectionChanged(object? sender, RouteMapSelection? selection)
    {
        if (selection is null)
        {
            SetRouteTelemetrySelection(null);
        }
        else if (_routeTelemetrySelection is not null)
        {
            SetRouteTelemetrySelection(selection);
        }

        ScheduleRouteTelemetryRefresh();
    }

    private void OnWaypointSelectionChanged(
        object? sender,
        WaypointEditorItemViewModel? waypoint)
    {
        if (waypoint is null)
        {
            return;
        }

        var waypoints = _subscribedViewModel?.Itinerary.Waypoints;
        if (waypoints is null || waypoint == waypoints[0] || waypoint == waypoints[^1])
            return;

        SetPlanningDrawerOpen(true);
        this.FindControl<Expander>("WaypointEditorExpander")!.IsExpanded = true;
        Dispatcher.UIThread.Post(() => _waypointList?.ScrollIntoView(waypoint), DispatcherPriority.Loaded);
    }

    private void OnRoutePointInspectionRequested(object? sender, RouteMapSelection selection)
    {
        SetRouteTelemetrySelection(selection);
        ScheduleRouteTelemetryRefresh();
    }

    private void SetRouteTelemetrySelection(RouteMapSelection? selection)
    {
        _routeTelemetrySelection = selection;
        _routeTelemetryProjection = null;
    }

    private void OnRouteTelemetryCardClicked(object? sender, RoutedEventArgs e)
    {
        e.Handled = true;
        _subscribedViewModel?.ClearRoutePointSelection();
        _mapControl?.Focus();
    }

    private void ScheduleRouteTelemetryRefresh()
    {
        Dispatcher.UIThread.Post(() =>
        {
            UpdateRouteTelemetryOverlay();
            UpdateMessagePlacement();
        }, DispatcherPriority.Loaded);
    }

    private void UpdateRouteTelemetryOverlay()
    {
        if (_mapControl is null ||
            _routeTelemetryLayer is null ||
            _routeTelemetryCard is null ||
            _routeTelemetryConnector is null ||
            _routeTelemetryAnchor is null ||
            _subscribedViewModel is null ||
            _routeTelemetrySelection is not { } selection ||
            _mapControl.Bounds.Width <= 0 ||
            _mapControl.Bounds.Height <= 0)
        {
            HideRouteTelemetryOverlay();
            return;
        }

        var projected = _routeTelemetryProjection ??=
            _subscribedViewModel.GetProjectedRoutePoint(selection);
        var screen = _mapControl.Map.Navigator.Viewport.WorldToScreen(projected);
        var anchor = new ScreenPoint(screen.X, screen.Y);
        var visibleBounds = new ScreenRect(
            0,
            0,
            _mapControl.Bounds.Width,
            _mapControl.Bounds.Height);
        if (anchor.X < visibleBounds.X ||
            anchor.Y < visibleBounds.Y ||
            anchor.X > visibleBounds.Right ||
            anchor.Y > visibleBounds.Bottom ||
            !CanPlaceRouteTelemetry(visibleBounds))
        {
            HideRouteTelemetryOverlay();
            return;
        }

        var placement = RouteTelemetryPlacement.Calculate(
            visibleBounds,
            anchor,
            new ScreenSize(RouteTelemetryWidth, RouteTelemetryHeight),
            RouteTelemetryGap,
            RouteTelemetrySafeMargin);
        Canvas.SetLeft(_routeTelemetryAnchor, anchor.X - (_routeTelemetryAnchor.Width / 2));
        Canvas.SetTop(_routeTelemetryAnchor, anchor.Y - (_routeTelemetryAnchor.Height / 2));
        Canvas.SetLeft(_routeTelemetryCard, placement.PopupBounds.X);
        Canvas.SetTop(_routeTelemetryCard, placement.PopupBounds.Y);
        _routeTelemetryConnector.StartPoint = new Point(
            placement.Connector.Start.X,
            placement.Connector.Start.Y);
        _routeTelemetryConnector.EndPoint = new Point(
            placement.Connector.End.X,
            placement.Connector.End.Y);
        _routeTelemetryLayer.IsVisible = true;
    }

    private static bool CanPlaceRouteTelemetry(ScreenRect visibleBounds) =>
        visibleBounds.Width - (RouteTelemetrySafeMargin * 2) >= RouteTelemetryWidth &&
        visibleBounds.Height - (RouteTelemetrySafeMargin * 2) >= RouteTelemetryHeight;

    private void HideRouteTelemetryOverlay()
    {
        if (_routeTelemetryLayer is not null)
        {
            _routeTelemetryLayer.IsVisible = false;
        }
    }

    private void OnPlanningDrawerClicked(object? sender, RoutedEventArgs e)
    {
        SelectPanel(WorkingPanel.Plan);
    }

    private void OnRouteDrawerClicked(object? sender, RoutedEventArgs e)
    {
        SelectPanel(WorkingPanel.Results);
    }

    private void OnSettingsClicked(object? sender, RoutedEventArgs e) => SelectPanel(WorkingPanel.Settings);

    private void OnSettingsBackClicked(object? sender, RoutedEventArgs e) => SelectPanel(_previousPanel);

    private void OnCollapsePanelClicked(object? sender, RoutedEventArgs e) => SetPanelOpen(!IsPanelOpen);

    private void OnBoatChangeClicked(object? sender, RoutedEventArgs e)
    {
        SelectPanel(WorkingPanel.Settings);
        var setup = this.FindControl<RoutingSetupView>("CruisingSetupPanel")!;
        var section = setup.FindControl<Expander>("BoatSettingsExpander")!;
        section.IsExpanded = true;
        Dispatcher.UIThread.Post(() => { section.BringIntoView(); section.Focus(); }, DispatcherPriority.Loaded);
    }

    private void OnForecastOptionsClicked(object? sender, RoutedEventArgs e)
    {
        SelectPanel(WorkingPanel.Settings);
        var section = this.FindControl<Expander>("ForecastSettingsExpander")!;
        section.IsExpanded = true;
        Dispatcher.UIThread.Post(() => { section.BringIntoView(); section.Focus(); }, DispatcherPriority.Loaded);
    }

    internal void SetPlanningDrawerOpen(bool isOpen)
    {
        if (isOpen) SelectPanel(WorkingPanel.Plan);
        else if (IsPlanningDrawerOpen) SetPanelOpen(false);
    }

    internal void SetRouteDrawerOpen(bool isOpen)
    {
        if (isOpen) SelectPanel(WorkingPanel.Results);
        else if (IsRouteDrawerOpen) SetPanelOpen(false);
    }

    internal void SelectPanel(WorkingPanel panel)
    {
        RememberPanelState();
        if (panel == WorkingPanel.Settings && SelectedPanel != WorkingPanel.Settings)
        {
            _previousPanel = SelectedPanel;
        }
        SelectedPanel = panel;
        IsPanelOpen = true;
        ApplyPanelState();
        RestorePanelFocus();
    }

    internal void SetPanelOpen(bool isOpen)
    {
        RememberPanelState();
        IsPanelOpen = isOpen;
        ApplyPanelState();
        if (isOpen) RestorePanelFocus();
        else _mapControl?.Focus();
    }

    private ScrollViewer PanelScrollViewer => this.FindControl<ScrollViewer>(
        SelectedPanel == WorkingPanel.Results ? "ResultsScrollViewer" : "PlanningScrollViewer")!;

    private void RememberPanelState()
    {
        if (!IsPanelOpen) return;
        _panelWidth = _planningDrawerColumn?.ActualWidth > 0
            ? _planningDrawerColumn.ActualWidth : _panelWidth;
        _panelScroll[SelectedPanel] = PanelScrollViewer.Offset;
        if (FocusManager?.GetFocusedElement() is Control control &&
            (PanelScrollViewer.IsKeyboardFocusWithin ||
             this.FindControl<Border>("CalculationFooter")!.IsKeyboardFocusWithin))
        {
            _panelFocus[SelectedPanel] = control;
        }
    }

    private void RestorePanelFocus()
    {
        Dispatcher.UIThread.Post(() =>
        {
            if (!IsPanelOpen) return;
            PanelScrollViewer.Offset = _panelScroll.GetValueOrDefault(SelectedPanel);
            var fallback = SelectedPanel switch
            {
                WorkingPanel.Plan => "SetStartButton",
                WorkingPanel.Results => "SetCurrentPositionButton",
                _ => "SettingsTabButton"
            };
            var target = _panelFocus.GetValueOrDefault(SelectedPanel);
            if (target?.IsEffectivelyVisible is true && target.IsEffectivelyEnabled)
                target.Focus();
            else this.FindControl<Control>(fallback)?.Focus();
        }, DispatcherPriority.Loaded);
    }

    private void ApplyPanelState()
    {
        if (_planningDrawerColumn is null) return;
        CloseRadialMenu();
        var shell = this.FindControl<Grid>("ShellGrid")!;
        _planningDrawerColumn.MinWidth = IsPanelOpen ? MinimumPanelWidth : 0;
        _planningDrawerColumn.MaxWidth = IsPanelOpen ? MaximumPanelWidth(Bounds.Width > 0 ? Bounds.Width : Width) : 0;
        _planningDrawerColumn.Width = new GridLength(
            IsPanelOpen ? Math.Clamp(_panelWidth, MinimumPanelWidth, _planningDrawerColumn.MaxWidth) : 0);
        shell.ColumnDefinitions[1].Width = new GridLength(IsPanelOpen ? SplitterWidth : 0);
        _planningDrawerContent!.IsVisible = IsPanelOpen && SelectedPanel != WorkingPanel.Results;
        _routeDrawerContent!.IsVisible = IsRouteDrawerOpen;
        this.FindControl<Grid>("PlanningDrawer")!.IsVisible = _planningDrawerContent.IsVisible;
        this.FindControl<Grid>("RouteDrawer")!.IsVisible = _routeDrawerContent.IsVisible;
        _planningDrawerHandle!.IsChecked = IsPlanningDrawerOpen;
        _routeDrawerHandle!.IsChecked = IsRouteDrawerOpen;
        this.FindControl<ToggleButton>("SettingsTabButton")!.IsChecked = IsPanelOpen && SelectedPanel == WorkingPanel.Settings;
        this.FindControl<Button>("CollapsePanelButton")!.Content = IsPanelOpen ? "Collapse" : "Show panel";
        this.FindControl<Border>("CalculationFooter")!.IsVisible = IsPanelOpen;
        this.FindControl<GridSplitter>("WorkingPanelSplitter")!.IsVisible = IsPanelOpen;
        this.FindControl<StackPanel>("SettingsContent")!.IsVisible = SelectedPanel == WorkingPanel.Settings;
        foreach (var name in new[] { "EndpointsPanel", "ForecastModelsPanel", "BoatSummaryPanel" })
            this.FindControl<Border>(name)!.IsVisible = SelectedPanel == WorkingPanel.Plan;
        UpdateCollapsedAlerts();
        PanelScrollViewer.Offset = _panelScroll.GetValueOrDefault(SelectedPanel);
        ScheduleRouteTelemetryRefresh();
        ScheduleWeatherRefresh();
    }

    private void OnWindowSizeChanged(object? sender, SizeChangedEventArgs e)
    {
        if (_planningDrawerColumn is not null && IsPanelOpen)
        {
            _planningDrawerColumn.MaxWidth = MaximumPanelWidth(e.NewSize.Width);
        }
        ScheduleRouteTelemetryRefresh();
        ScheduleWeatherRefresh();
    }

    private void OnItineraryChanged(object? sender, EventArgs e)
    {
        if (_subscribedViewModel is { } model && model.Itinerary.PlanId != _displayedPlanId)
        {
            _displayedPlanId = model.Itinerary.PlanId;
            this.FindControl<Expander>("WaypointEditorExpander")!.IsExpanded = false;
            Dispatcher.UIThread.Post(() =>
            {
                SelectPanel(WorkingPanel.Plan);
                _panelScroll.Clear();
                _panelFocus.Clear();
                PanelScrollViewer.Offset = default;
            });
        }
    }

    private void OnViewModelPropertyChanged(object? sender, System.ComponentModel.PropertyChangedEventArgs e)
    {
        if (e.PropertyName is nameof(MainViewModel.IsCalculating) or nameof(MainViewModel.ErrorMessage) or
            nameof(MainViewModel.WarningMessage) or nameof(MainViewModel.PreferenceError) or
            nameof(MainViewModel.CurrentMessages))
        {
            UpdateCollapsedAlerts();
            ScheduleMessageRefresh();
        }
    }

    private void OnRoutingSetupPropertyChanged(object? sender, System.ComponentModel.PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(RoutingSetupViewModel.ErrorMessage))
        {
            UpdateCollapsedAlerts();
            ScheduleMessageRefresh();
        }
    }

    private void UpdateCollapsedAlerts()
    {
        this.FindControl<Grid>("InstrumentRailHost")!.IsVisible =
            !IsPanelOpen && DataContext is MainViewModel { IsCalculating: true };
    }

    private void OnWindowDeactivated(object? sender, EventArgs e)
    {
        CloseRadialMenu();
    }

    private void ScheduleWeatherRefresh()
    {
        Dispatcher.UIThread.Post(
            () =>
            {
                if (DataContext is MainViewModel viewModel)
                {
                    viewModel.RequestWeatherRefreshFromViewport();
                }
            },
            DispatcherPriority.Loaded);
    }

    private async void OnChooseGribFileClicked(object? sender, RoutedEventArgs e)
    {
        if (DataContext is not MainViewModel viewModel)
        {
            return;
        }

        // async void is required by the UI event; surface all picker failures in the drawer.
        var storageProvider = StorageProvider;
        if (storageProvider is null || !storageProvider.CanOpen)
        {
            viewModel.ErrorMessage = "This platform does not support opening files.";
            return;
        }

        try
        {
            var files = await storageProvider.OpenFilePickerAsync(new FilePickerOpenOptions
            {
                Title = "Choose an existing GRIB forecast",
                AllowMultiple = false,
                FileTypeFilter = [GribFileType, FilePickerFileTypes.All]
            });
            var path = files.FirstOrDefault()?.TryGetLocalPath();
            if (!string.IsNullOrWhiteSpace(path))
            {
                await viewModel.SelectLocalGribAsync(path);
            }
        }
        catch (Exception exception)
        {
            viewModel.ErrorMessage = $"Choosing a GRIB file failed: {exception.Message}";
        }
    }

    private static AppThemeService GetDefaultThemeService()
    {
        if (_defaultThemeService is not null)
        {
            return _defaultThemeService;
        }

        _defaultThemeService = AppThemeService.CreateTransient();
        _defaultThemeService.Initialize(Avalonia.Application.Current ??
            throw new InvalidOperationException("An Avalonia application is required."));
        return _defaultThemeService;
    }
}
