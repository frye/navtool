using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.Primitives;
using Avalonia.Headless;
using Avalonia.Headless.XUnit;
using Avalonia.Input;
using Avalonia.Interactivity;
using Avalonia.LogicalTree;
using Avalonia.Threading;
using Avalonia.VisualTree;
using Mapsui.Extensions;
using Mapsui.UI.Avalonia;
using Navtool.App.Models;
using Navtool.App.Services;
using Navtool.App.ViewModels;
using Navtool.App.Views;
using Navtool.Core;
using Navtool.Infrastructure;

namespace Navtool.App.Tests;

public sealed class MainWindowLayoutTests
{
    [AvaloniaFact]
    public void DrawersAreAlwaysInTheWindowNameScopeAndClosedByDefault()
    {
        var window = CreateWindow();

        try
        {
            window.Show();

            Assert.False(window.IsPlanningDrawerOpen);
            Assert.False(window.IsRouteDrawerOpen);
            Assert.False(Assert.IsType<Border>(
                window.FindControl<Border>("PlanningDrawerContent")).IsVisible);
            Assert.False(Assert.IsType<Border>(
                window.FindControl<Border>("RouteDrawerContent")).IsVisible);
            Assert.NotNull(window.FindControl<ComboBox>("ThemeSelector"));
            Assert.NotNull(window.FindControl<ToggleButton>("SetStartButton"));
            Assert.NotNull(window.FindControl<ToggleButton>("SetDestinationButton"));
            Assert.NotNull(window.FindControl<ToggleButton>("SetCurrentPositionButton"));
            Assert.NotNull(window.FindControl<Button>("CalculateRoutesButton"));
            Assert.NotNull(window.FindControl<NumericUpDown>("PassageDaysInput"));
            Assert.NotNull(window.FindControl<NumericUpDown>("PassageHoursInput"));
            Assert.NotNull(window.FindControl<RadioButton>("DownloadForecastSource"));
            Assert.NotNull(window.FindControl<RadioButton>("LocalForecastSource"));
            Assert.NotNull(window.FindControl<Button>("ChooseGribFileButton"));
        }
        finally
        {
            window.Close();
        }
    }

    [Fact]
    public void SizingPolicyPreservesTheMapFloorAndUsesTheRequestedBreakpoint()
    {
        Assert.False(MainWindow.AllowsBothDrawers(1219.99));
        Assert.True(MainWindow.AllowsBothDrawers(1220));
        Assert.Equal(
            560,
            MainWindow.DrawerBreakpoint -
            MainWindow.PlanningDrawerWidth -
            MainWindow.RouteDrawerWidth);
        Assert.True(
            1040 - MainWindow.RouteDrawerWidth >= 560,
            "The larger single drawer must leave the map at least 560px wide.");
    }

    [AvaloniaFact]
    public void NarrowWindowsKeepOnlyTheMostRecentlyOpenedDrawer()
    {
        var window = CreateWindow();
        window.Width = 1040;

        try
        {
            window.Show();
            window.SetPlanningDrawerOpen(true);
            window.SetRouteDrawerOpen(true);

            Assert.False(window.IsPlanningDrawerOpen);
            Assert.True(window.IsRouteDrawerOpen);
            var shell = Assert.IsType<Grid>(window.FindControl<Grid>("ShellGrid"));
            Assert.Equal(MainWindow.ClosedDrawerWidth, shell.ColumnDefinitions[0].Width.Value);
            Assert.Equal(MainWindow.RouteDrawerWidth, shell.ColumnDefinitions[2].Width.Value);
        }
        finally
        {
            window.Close();
        }
    }

    [AvaloniaFact]
    public void WideWindowsCanKeepBothDrawersOpen()
    {
        var window = CreateWindow();
        window.Width = 1220;

        try
        {
            window.Show();
            window.SetPlanningDrawerOpen(true);
            window.SetRouteDrawerOpen(true);

            Assert.True(window.IsPlanningDrawerOpen);
            Assert.True(window.IsRouteDrawerOpen);
            var shell = Assert.IsType<Grid>(window.FindControl<Grid>("ShellGrid"));
            Assert.Equal(MainWindow.PlanningDrawerWidth, shell.ColumnDefinitions[0].Width.Value);
            Assert.Equal(MainWindow.RouteDrawerWidth, shell.ColumnDefinitions[2].Width.Value);
        }
        finally
        {
            window.Close();
        }
    }

    [AvaloniaFact]
    public void CrossingBelowTheBreakpointKeepsTheMostRecentlyOpenedDrawer()
    {
        var window = CreateWindow();
        window.Width = 1220;

        try
        {
            window.Show();
            window.SetPlanningDrawerOpen(true);
            window.SetRouteDrawerOpen(true);

            window.Width = 1219;
            Dispatcher.UIThread.RunJobs();

            Assert.False(window.IsPlanningDrawerOpen);
            Assert.True(window.IsRouteDrawerOpen);
        }
        finally
        {
            window.Close();
        }
    }

    [AvaloniaFact]
    public void RouteLegendTimelineAndWeatherLiveInTheRightDrawer()
    {
        var window = CreateWindow();

        try
        {
            window.Show();
            window.SetRouteDrawerOpen(true);
            Assert.IsType<Expander>(
                window.FindControl<Expander>("RouteDetailsExpander")).IsExpanded = true;
            Assert.IsType<Expander>(
                window.FindControl<Expander>("WeatherDetailsExpander")).IsExpanded = true;
            var rightDrawer = Assert.IsType<Border>(
                window.FindControl<Border>("RouteDrawerContent"));
            foreach (var control in new Control[]
                     {
                         Assert.IsType<Border>(
                             window.FindControl<Border>("HistoricalIsochroneLegendSwatch")),
                         Assert.IsType<Border>(
                             window.FindControl<Border>("DestinationFrontLegendSwatch")),
                         Assert.IsType<Slider>(
                             window.FindControl<Slider>("TimelineSlider")),
                         Assert.IsType<Expander>(
                             window.FindControl<Expander>("WeatherDetailsExpander"))
                     })
            {
                Assert.Contains(rightDrawer, control.GetLogicalAncestors());
            }
        }
        finally
        {
            window.Close();
        }
    }

    [AvaloniaFact]
    public void RadialActionsUseTheSharedAccessibleTouchSizedLayout()
    {
        var window = CreateWindow();

        try
        {
            window.Show();
            var map = Assert.IsType<MapControl>(window.FindControl<MapControl>("MapView"));
            var point = map.TranslatePoint(map.Bounds.Center, window);
            Assert.NotNull(point);

            window.MouseDown(point.Value, MouseButton.Right, RawInputModifiers.None);

            Assert.True(window.IsRadialMenuOpen);
            var layer = Assert.IsType<Canvas>(window.FindControl<Canvas>("RadialMenuLayer"));
            var buttons = new[]
            {
                Assert.IsType<Button>(window.FindControl<Button>("SetStartRadialButton")),
                Assert.IsType<Button>(window.FindControl<Button>("SetDestinationRadialButton")),
                Assert.IsType<Button>(window.FindControl<Button>("InspectRadialButton"))
            };
            Assert.Equal(buttons, layer.Children.OfType<Button>());
            Assert.All(buttons, button =>
            {
                Assert.True(button.Width >= 44);
                Assert.True(button.Height >= 44);
                Assert.NotNull(ToolTip.GetTip(button));
            });
            Assert.False(buttons[2].IsEnabled);
        }
        finally
        {
            window.Close();
        }
    }

    [AvaloniaFact]
    public void RadialEndpointActionUsesTheCapturedMapPointAndCloses()
    {
        var viewModel = CreateViewModel();
        var window = new MainWindow { DataContext = viewModel };

        try
        {
            window.Show();
            var map = Assert.IsType<MapControl>(window.FindControl<MapControl>("MapView"));
            var point = map.TranslatePoint(map.Bounds.Center, window);
            Assert.NotNull(point);
            window.MouseDown(point.Value, MouseButton.Right, RawInputModifiers.None);
            var start = Assert.IsType<Button>(
                window.FindControl<Button>("SetStartRadialButton"));

            start.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));

            Assert.NotNull(viewModel.Start);
            Assert.False(window.IsRadialMenuOpen);
            Assert.Equal(MapInteractionMode.Browse, viewModel.InteractionMode);
        }
        finally
        {
            window.Close();
        }
    }

    [AvaloniaFact]
    public void ContextMenuKeyOpensAndEscapeClosesTheRadialMenu()
    {
        var window = CreateWindow();

        try
        {
            window.Show();
            var map = Assert.IsType<MapControl>(window.FindControl<MapControl>("MapView"));
            map.Focus();
            window.KeyPress(
                Key.Apps,
                RawInputModifiers.None,
                PhysicalKey.ContextMenu,
                string.Empty);
            Assert.True(window.IsRadialMenuOpen);

            window.KeyPress(
                Key.Escape,
                RawInputModifiers.None,
                PhysicalKey.Escape,
                string.Empty);
            Assert.False(window.IsRadialMenuOpen);
        }
        finally
        {
            window.Close();
        }
    }

    [AvaloniaFact]
    public void ContextMenuKeyDoesNotOpenMapActionsFromDrawerControls()
    {
        var window = CreateWindow();

        try
        {
            window.Show();
            window.SetPlanningDrawerOpen(true);
            var calculate = Assert.IsType<Button>(
                window.FindControl<Button>("CalculateRoutesButton"));
            calculate.Focus();

            window.KeyPress(
                Key.Apps,
                RawInputModifiers.None,
                PhysicalKey.ContextMenu,
                string.Empty);

            Assert.False(window.IsRadialMenuOpen);
        }
        finally
        {
            window.Close();
        }
    }

    [AvaloniaFact]
    public void EveryRadialOpenUpdatesTheNextKeyboardAnchor()
    {
        var window = CreateWindow();

        try
        {
            window.Show();
            var map = Assert.IsType<MapControl>(window.FindControl<MapControl>("MapView"));
            var anchor = new ScreenPoint(map.Bounds.Width * 0.25, map.Bounds.Height * 0.25);
            window.OpenRadialMenu(
                map.Map.Navigator.Viewport.ScreenToWorld(anchor.X, anchor.Y),
                anchor);
            var start = Assert.IsType<Button>(
                window.FindControl<Button>("SetStartRadialButton"));
            var expectedLeft = Canvas.GetLeft(start);
            var expectedTop = Canvas.GetTop(start);
            window.KeyPress(
                Key.Escape,
                RawInputModifiers.None,
                PhysicalKey.Escape,
                string.Empty);

            window.KeyPress(
                Key.Apps,
                RawInputModifiers.None,
                PhysicalKey.ContextMenu,
                string.Empty);

            Assert.True(window.IsRadialMenuOpen);
            Assert.Equal(expectedLeft, Canvas.GetLeft(start));
            Assert.Equal(expectedTop, Canvas.GetTop(start));
        }
        finally
        {
            window.Close();
        }
    }

    [AvaloniaFact]
    public void MinimumWindowSizeMatchesTheProductionFloor()
    {
        var window = CreateWindow();
        Assert.Equal(1040, window.MinWidth);
        Assert.Equal(680, window.MinHeight);
    }

    [AvaloniaFact]
    public void LegsListButtonsAreWiredToTheRealMarkAndUnmarkSailedCommands()
    {
        var viewModel = new MainViewModel(
            null,
            null,
            TimeProvider.System,
            TimeZoneInfo.Utc,
            new OsmTileOptions(Enabled: false));
        viewModel.SetEndpoints(new Coordinate(34, -64), new Coordinate(39, -52));
        viewModel.Itinerary.AddWaypointCommand.Execute(null);
        var intermediate = viewModel.Itinerary.Waypoints[1];
        intermediate.SetOnMapCommand.Execute(null);
        viewModel.HandleMapClick(
            MapProjection.ToMapPoint(new Coordinate(36, -58)),
            default);
        var window = new MainWindow { DataContext = viewModel };

        try
        {
            window.Show();
            window.SetPlanningDrawerOpen(true);
            Dispatcher.UIThread.RunJobs();
            Assert.Equal(2, viewModel.Itinerary.Legs.Count);
            var firstLegId = viewModel.Itinerary.Legs[0].Id;

            var sailedButton = window.GetVisualDescendants()
                .OfType<Button>()
                .Single(button =>
                    button.DataContext is RouteLegEditorItemViewModel leg &&
                    leg.Id == firstLegId &&
                    Equals(button.Content, "Sailed"));
            Assert.True(sailedButton.Command?.CanExecute(null));
            sailedButton.Command!.Execute(null);
            Dispatcher.UIThread.RunJobs();

            // Marking sailed rebuilds the Legs collection with fresh items, so re-index instead
            // of relying on the (now stale) view-model instance captured before the click.
            Assert.True(viewModel.Itinerary.Legs[0].IsSailed);
            Assert.Equal("Sailed", viewModel.Itinerary.Legs[0].StatusLabel);

            var unmarkButton = window.GetVisualDescendants()
                .OfType<Button>()
                .Single(button =>
                    button.DataContext is RouteLegEditorItemViewModel leg &&
                    leg.Id == firstLegId &&
                    Equals(button.Content, "Unmark"));
            Assert.True(unmarkButton.Command?.CanExecute(null));
            unmarkButton.Command!.Execute(null);

            Assert.False(viewModel.Itinerary.Legs[0].IsSailed);
        }
        finally
        {
            window.Close();
        }
    }

    [AvaloniaFact]
    public void CurrentPositionButtonArmsPlacementModeThroughTheRealBinding()
    {
        var window = CreateWindow();
        var viewModel = Assert.IsType<MainViewModel>(window.DataContext);

        try
        {
            window.Show();
            var setCurrentPosition = Assert.IsType<ToggleButton>(
                window.FindControl<ToggleButton>("SetCurrentPositionButton"));

            setCurrentPosition.Command?.Execute(null);

            Assert.Equal(MapInteractionMode.SetCurrentPosition, viewModel.InteractionMode);
            Assert.True(viewModel.IsSettingCurrentPosition);
            Assert.True(viewModel.Itinerary.IsAwaitingCurrentPositionPlacement);
        }
        finally
        {
            window.Close();
        }
    }

    private static MainWindow CreateWindow() =>
        new() { DataContext = CreateViewModel() };

    private static MainViewModel CreateViewModel() =>
        new(
            null,
            null,
            TimeProvider.System,
            TimeZoneInfo.Utc,
            new OsmTileOptions(Enabled: false));
}
