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
    private enum DrawerSide
    {
        Planning,
        Route
    }

    internal const double DrawerBreakpoint = 1220;
    internal const double ClosedDrawerWidth = 44;
    internal const double PlanningDrawerWidth = 320;
    internal const double RouteDrawerWidth = 340;

    private const double RadialActionWidth = 112;
    private const double RadialActionHeight = 48;
    private const double RadialRadius = 82;
    private const double RadialSafeMargin = 16;
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
    private ColumnDefinition? _routeDrawerColumn;
    private Border? _planningDrawerContent;
    private Border? _routeDrawerContent;
    private ToggleButton? _planningDrawerHandle;
    private ToggleButton? _routeDrawerHandle;
    private Canvas? _radialMenuLayer;
    private Button? _setStartRadialButton;
    private Button? _setDestinationRadialButton;
    private Button? _inspectRadialButton;
    private Line? _radialConnector;
    private Ellipse? _radialAnchor;
    private ScreenPoint? _lastPointerPosition;
    private MPoint? _capturedWorldPoint;
    private RouteMapSelection? _capturedRouteSelection;
    private DrawerSide? _lastOpenedDrawer;

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

    internal bool IsPlanningDrawerOpen { get; private set; }

    internal bool IsRouteDrawerOpen { get; private set; }

    internal bool IsRadialMenuOpen => _radialMenuLayer?.IsVisible is true;

    internal static bool AllowsBothDrawers(double width) => width >= DrawerBreakpoint;

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
        _routeDrawerColumn = shellGrid.ColumnDefinitions[2];
        _planningDrawerContent = this.FindControl<Border>("PlanningDrawerContent")!;
        _routeDrawerContent = this.FindControl<Border>("RouteDrawerContent")!;
        _planningDrawerHandle = this.FindControl<ToggleButton>("PlanningDrawerHandle")!;
        _routeDrawerHandle = this.FindControl<ToggleButton>("RouteDrawerHandle")!;

        _radialMenuLayer = this.FindControl<Canvas>("RadialMenuLayer")!;
        _setStartRadialButton = this.FindControl<Button>("SetStartRadialButton")!;
        _setDestinationRadialButton = this.FindControl<Button>("SetDestinationRadialButton")!;
        _inspectRadialButton = this.FindControl<Button>("InspectRadialButton")!;
        _radialConnector = this.FindControl<Line>("RadialConnector")!;
        _radialAnchor = this.FindControl<Ellipse>("RadialAnchor")!;
        ApplyDrawerState();
    }

    private void OnLoaded(object? sender, RoutedEventArgs e)
    {
        if (DataContext is not MainViewModel viewModel)
        {
            return;
        }

        _subscribedNavigator = viewModel.Map.Navigator;
        _subscribedNavigator.ViewportChanged += OnViewportChanged;
        ScheduleWeatherRefresh();
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
        if (!IsRadialMenuOpen || IsRadialActionSource(e.Source))
        {
            return;
        }

        CloseRadialMenu();
        e.Handled = true;
    }

    private bool IsRadialActionSource(object? source)
    {
        if (source is Button button)
        {
            return button == _setStartRadialButton ||
                   button == _setDestinationRadialButton ||
                   button == _inspectRadialButton;
        }

        return source is Visual visual &&
               visual.GetVisualAncestors().OfType<Button>().Any(button =>
                   button == _setStartRadialButton ||
                   button == _setDestinationRadialButton ||
                   button == _inspectRadialButton);
    }

    private void OnWindowKeyDown(object? sender, KeyEventArgs e)
    {
        if (e.Key == Key.Escape && IsRadialMenuOpen)
        {
            e.Handled = true;
            CloseRadialMenu();
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
            _inspectRadialButton is null ||
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
        _capturedRouteSelection = viewModel.FindRouteAt(worldPoint, screenPoint);
        _inspectRadialButton.IsEnabled = _capturedRouteSelection is not null;

        var placement = RadialMenuPlacement.Calculate(
            new ScreenRect(0, 0, _mapControl.Bounds.Width, _mapControl.Bounds.Height),
            screenPoint,
            new ScreenSize(RadialActionWidth, RadialActionHeight),
            RadialRadius,
            RadialSafeMargin);
        PositionRadialAction(_setStartRadialButton, placement.Actions[0].Bounds);
        PositionRadialAction(_setDestinationRadialButton, placement.Actions[1].Bounds);
        PositionRadialAction(_inspectRadialButton, placement.Actions[2].Bounds);
        ApplyConnector(placement);
        _radialMenuLayer.IsVisible = true;
        _setStartRadialButton.Focus();
    }

    private void ApplyConnector(RadialMenuPlacementResult placement)
    {
        if (_radialConnector is null || _radialAnchor is null)
        {
            return;
        }

        _radialConnector.IsVisible = placement.Connector is not null;
        _radialAnchor.IsVisible = placement.Connector is not null;
        if (placement.Connector is not { } connector)
        {
            return;
        }

        _radialConnector.StartPoint = new Point(connector.Start.X, connector.Start.Y);
        _radialConnector.EndPoint = new Point(connector.End.X, connector.End.Y);
        Canvas.SetLeft(_radialAnchor, connector.Start.X - (_radialAnchor.Width / 2));
        Canvas.SetTop(_radialAnchor, connector.Start.Y - (_radialAnchor.Height / 2));
    }

    private static void PositionRadialAction(Control control, ScreenRect bounds)
    {
        control.Width = bounds.Width;
        control.Height = bounds.Height;
        Canvas.SetLeft(control, bounds.X);
        Canvas.SetTop(control, bounds.Y);
    }

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

    private void OnInspectRadialClicked(object? sender, RoutedEventArgs e)
    {
        e.Handled = true;
        if (_capturedRouteSelection is { } selection &&
            DataContext is MainViewModel viewModel)
        {
            viewModel.SelectRoutePoint(selection);
        }

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
        _capturedRouteSelection = null;
        _mapControl?.Focus();
    }

    private void OnPlanningDrawerClicked(object? sender, RoutedEventArgs e)
    {
        SetPlanningDrawerOpen(!IsPlanningDrawerOpen);
    }

    private void OnRouteDrawerClicked(object? sender, RoutedEventArgs e)
    {
        SetRouteDrawerOpen(!IsRouteDrawerOpen);
    }

    internal void SetPlanningDrawerOpen(bool isOpen)
    {
        if (isOpen && !AllowsBothDrawers(Bounds.Width))
        {
            IsRouteDrawerOpen = false;
        }

        IsPlanningDrawerOpen = isOpen;
        if (isOpen)
        {
            _lastOpenedDrawer = DrawerSide.Planning;
        }

        ApplyDrawerState();
    }

    internal void SetRouteDrawerOpen(bool isOpen)
    {
        if (isOpen && !AllowsBothDrawers(Bounds.Width))
        {
            IsPlanningDrawerOpen = false;
        }

        IsRouteDrawerOpen = isOpen;
        if (isOpen)
        {
            _lastOpenedDrawer = DrawerSide.Route;
        }

        ApplyDrawerState();
    }

    private void ApplyDrawerState()
    {
        if (_planningDrawerColumn is null ||
            _routeDrawerColumn is null ||
            _planningDrawerContent is null ||
            _routeDrawerContent is null ||
            _planningDrawerHandle is null ||
            _routeDrawerHandle is null)
        {
            return;
        }

        CloseRadialMenu();
        _planningDrawerColumn.Width = new GridLength(
            IsPlanningDrawerOpen ? PlanningDrawerWidth : ClosedDrawerWidth);
        _routeDrawerColumn.Width = new GridLength(
            IsRouteDrawerOpen ? RouteDrawerWidth : ClosedDrawerWidth);
        _planningDrawerContent.IsVisible = IsPlanningDrawerOpen;
        _routeDrawerContent.IsVisible = IsRouteDrawerOpen;
        _planningDrawerHandle.IsChecked = IsPlanningDrawerOpen;
        _routeDrawerHandle.IsChecked = IsRouteDrawerOpen;
        _planningDrawerHandle.Content = IsPlanningDrawerOpen ? "‹" : "›";
        _routeDrawerHandle.Content = IsRouteDrawerOpen ? "›" : "‹";
        ScheduleWeatherRefresh();
    }

    private void OnWindowSizeChanged(object? sender, SizeChangedEventArgs e)
    {
        if (!AllowsBothDrawers(e.NewSize.Width) &&
            IsPlanningDrawerOpen &&
            IsRouteDrawerOpen)
        {
            if (_lastOpenedDrawer == DrawerSide.Route)
            {
                IsPlanningDrawerOpen = false;
            }
            else
            {
                IsRouteDrawerOpen = false;
            }

            ApplyDrawerState();
            return;
        }

        ScheduleWeatherRefresh();
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
