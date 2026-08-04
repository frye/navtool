using Avalonia;
using Avalonia.Automation;
using Avalonia.Controls;
using Avalonia.Controls.Primitives;
using Avalonia.Headless;
using Avalonia.Headless.XUnit;
using Avalonia.Input;
using Avalonia.Interactivity;
using Avalonia.LogicalTree;
using Avalonia.Layout;
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
            Assert.NotNull(window.FindControl<Button>("CalculateRadialButton"));
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
        Assert.False(MainWindow.AllowsBothDrawers(1279.99));
        Assert.False(MainWindow.AllowsBothDrawers(1219.99));
        Assert.True(MainWindow.AllowsBothDrawers(1280));
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
        window.Width = 1280;

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
        window.Width = 1280;

        try
        {
            window.Show();
            window.SetPlanningDrawerOpen(true);
            window.SetRouteDrawerOpen(true);

            window.Width = 1279;
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
                Assert.IsType<Button>(window.FindControl<Button>("CalculateRadialButton")),
                Assert.IsType<Button>(window.FindControl<Button>("InspectRadialButton"))
            };
            Assert.Equal(buttons, layer.Children.OfType<Button>());
            Assert.All(buttons, button =>
            {
                Assert.True(button.Width >= 44);
                Assert.True(button.Height >= 44);
                Assert.NotNull(ToolTip.GetTip(button));
                Assert.Equal(HorizontalAlignment.Center, button.HorizontalContentAlignment);
                Assert.Equal(VerticalAlignment.Center, button.VerticalContentAlignment);
            });
            var viewModel = Assert.IsType<MainViewModel>(window.DataContext);
            Assert.Same(viewModel.CalculateCommand, buttons[2].Command);
            Assert.True(buttons[2].IsEffectivelyEnabled);
            Assert.False(buttons[3].IsEnabled);
            viewModel.ForecastInputMode = ForecastInputMode.LocalFile;
            Dispatcher.UIThread.RunJobs();
            Assert.False(buttons[2].IsEffectivelyEnabled);
            Assert.Equal(
                HorizontalAlignment.Center,
                Assert.IsType<ToggleButton>(
                    window.FindControl<ToggleButton>("PlanningDrawerHandle"))
                    .HorizontalContentAlignment);
            Assert.Equal(
                VerticalAlignment.Center,
                Assert.IsType<ToggleButton>(
                    window.FindControl<ToggleButton>("RouteDrawerHandle"))
                    .VerticalContentAlignment);
            var anchor = Assert.IsType<Avalonia.Controls.Shapes.Ellipse>(
                window.FindControl<Avalonia.Controls.Shapes.Ellipse>("RadialAnchor"));
            var connector = Assert.IsType<Avalonia.Controls.Shapes.Line>(
                window.FindControl<Avalonia.Controls.Shapes.Line>("RadialConnector"));
            Assert.True(anchor.IsVisible);
            Assert.False(connector.IsVisible);
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
    public void InstrumentRailShowsProgressWithoutOpeningDrawersOrCoveringMapInstructions()
    {
        var window = CreateWindow();
        var viewModel = Assert.IsType<MainViewModel>(window.DataContext);

        try
        {
            window.Show();
            viewModel.SetStartCommand.Execute(null);
            Dispatcher.UIThread.RunJobs();

            var mapShell = Assert.IsType<Grid>(window.FindControl<Grid>("MapShell"));
            var rail = Assert.IsType<Border>(window.FindControl<Border>("InstrumentRail"));
            var idleRow = Assert.IsType<StackPanel>(
                window.FindControl<StackPanel>("InstrumentRailIdleRow"));
            var progressRow = Assert.IsType<StackPanel>(
                window.FindControl<StackPanel>("InstrumentRailProgressRow"));
            var progress = Assert.IsType<ProgressBar>(
                window.FindControl<ProgressBar>("InstrumentRailProgressBar"));
            var cancel = Assert.IsType<Button>(
                window.FindControl<Button>("InstrumentRailCancelButton"));

            Assert.True(idleRow.IsVisible);
            Assert.False(progressRow.IsVisible);
            Assert.False(progress.IsVisible);
            Assert.False(cancel.IsVisible);
            Assert.Contains(mapShell, rail.GetLogicalAncestors());

            viewModel.ProgressFraction = 0.64;
            viewModel.IsCalculating = true;
            Dispatcher.UIThread.RunJobs();

            Assert.False(idleRow.IsVisible);
            Assert.True(progressRow.IsVisible);
            Assert.True(progress.IsVisible);
            Assert.True(cancel.IsVisible);
            Assert.True(cancel.IsEnabled);
            Assert.Same(viewModel.CancelCommand, cancel.Command);
            Assert.Equal(0.64, progress.Value);
            Assert.Equal("Route calculation progress", AutomationProperties.GetName(progress));
            Assert.Equal(
                "Preparing route calculation",
                AutomationProperties.GetHelpText(progress));
            Assert.False(window.IsPlanningDrawerOpen);
            Assert.False(window.IsRouteDrawerOpen);

            var instruction = Assert.IsType<Border>(
                window.FindControl<Border>("MapInstructionOverlay"));
            Assert.True(instruction.IsVisible);
            var railBottom = rail.TranslatePoint(
                new Point(0, rail.Bounds.Height),
                window);
            var instructionTop = instruction.TranslatePoint(default, window);
            Assert.NotNull(railBottom);
            Assert.NotNull(instructionTop);
            Assert.True(railBottom.Value.Y <= instructionTop.Value.Y);

            cancel.Command!.Execute(null);
            Dispatcher.UIThread.RunJobs();
            Assert.False(viewModel.IsCalculating);
            Assert.True(idleRow.IsVisible);
            Assert.False(progressRow.IsVisible);
            Assert.False(progress.IsVisible);
        }
        finally
        {
            window.Close();
        }
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

    [AvaloniaFact]
    public void PlanningDrawerUsesContentAndHandleColumnsWithoutDuplicateGutter()
    {
        var window = CreateWindow();
        window.Width = 1040;
        window.Height = 680;

        try
        {
            window.Show();
            window.SetPlanningDrawerOpen(true);
            Assert.IsType<MainViewModel>(window.DataContext)
                .Itinerary.AddWaypointCommand.Execute(null);
            Dispatcher.UIThread.RunJobs();

            var shell = Assert.IsType<Grid>(window.FindControl<Grid>("ShellGrid"));
            var drawer = Assert.IsType<Grid>(window.FindControl<Grid>("PlanningDrawer"));
            var content = Assert.IsType<Border>(
                window.FindControl<Border>("PlanningDrawerContent"));
            var handle = Assert.IsType<ToggleButton>(
                window.FindControl<ToggleButton>("PlanningDrawerHandle"));
            var endpoints = Assert.IsType<Grid>(
                window.FindControl<Grid>("EndpointActions"));

            Assert.Equal(380, shell.ColumnDefinitions[0].Width.Value);
            Assert.Equal(2, drawer.ColumnDefinitions.Count);
            Assert.Equal(new GridLength(1, GridUnitType.Star), drawer.ColumnDefinitions[0].Width);
            Assert.Equal(44, drawer.ColumnDefinitions[1].Width.Value);
            Assert.Equal(0, Grid.GetColumn(content));
            Assert.Equal(1, Grid.GetColumn(handle));
            Assert.Equal(default, content.Padding);
            Assert.Equal(2, endpoints.ColumnDefinitions.Count);
            Assert.Equal(
                endpoints.ColumnDefinitions[0].Width,
                endpoints.ColumnDefinitions[1].Width);
            Assert.True(shell.ColumnDefinitions[1].ActualWidth >= 560);
            var stopoverHours = content
                .GetVisualDescendants()
                .OfType<NumericUpDown>()
                .Single(input => input.Maximum == 240 && input.IsEffectivelyVisible);
            Assert.True(stopoverHours.Bounds.Width >= 88);
        }
        finally
        {
            window.Close();
        }
    }

    [AvaloniaFact]
    public void FieldLayoutsExposeLabelsAndAlignedActionRows()
    {
        var window = CreateWindow();

        try
        {
            window.Show();
            window.SetPlanningDrawerOpen(true);

            var departure = Assert.IsType<Grid>(
                window.FindControl<Grid>("DepartureFields"));
            var saved = Assert.IsType<Grid>(
                window.FindControl<Grid>("SavedRouteActions"));
            var save = Assert.IsType<Grid>(
                window.FindControl<Grid>("SaveRouteActions"));

            Assert.Equal(2, departure.Children.OfType<StackPanel>().Count());
            Assert.All(
                departure.Children.OfType<StackPanel>(),
                field => Assert.Contains(
                    field.Children.OfType<TextBlock>(),
                    label => label.Classes.Contains("field-label")));
            Assert.Equal(8, departure.ColumnSpacing);
            Assert.Equal(3, saved.ColumnDefinitions.Count);
            Assert.Equal(8, saved.ColumnSpacing);
            Assert.Contains("compact-action-row", saved.Classes);
            Assert.Equal(3, save.ColumnDefinitions.Count);
            Assert.Equal(8, save.ColumnSpacing);
            Assert.Contains("compact-action-row", save.Classes);
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
