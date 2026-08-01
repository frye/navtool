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
