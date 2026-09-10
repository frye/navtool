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
using Avalonia.Media;
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
    public void Only_selected_panel_paints_and_exposes_plan_hit_targets()
    {
        var window = CreateWindow();
        try
        {
            window.Show();
            Dispatcher.UIThread.RunJobs();
            var planning = window.FindControl<Grid>("PlanningDrawer")!;
            var results = window.FindControl<Grid>("RouteDrawer")!;
            Assert.True(planning.IsEffectivelyVisible);
            Assert.False(results.IsEffectivelyVisible);
            var start = window.FindControl<ToggleButton>("SetStartButton")!;
            var point = start.TranslatePoint(new Point(start.Bounds.Width / 2, start.Bounds.Height / 2), window)!.Value;
            var hit = window.InputHitTest(point) as Visual;
            Assert.True(hit == start || hit?.GetVisualAncestors().Contains(start) is true,
                "The start button must be the pointer target, not a hidden panel's background.");
            window.SelectPanel(MainWindow.WorkingPanel.Results);
            Dispatcher.UIThread.RunJobs();
            Assert.False(planning.IsEffectivelyVisible);
            Assert.True(results.IsEffectivelyVisible);
            window.SelectPanel(MainWindow.WorkingPanel.Settings);
            Dispatcher.UIThread.RunJobs();
            Assert.True(planning.IsEffectivelyVisible);
            Assert.False(results.IsEffectivelyVisible);
            window.SetPanelOpen(false);
            Dispatcher.UIThread.RunJobs();
            Assert.False(planning.IsEffectivelyVisible);
            Assert.False(results.IsEffectivelyVisible);
        }
        finally { window.Close(); }
    }

    [AvaloniaFact]
    public void Weather_only_entry_is_clickable_without_a_route_or_timeline()
    {
        var window = CreateWindow();
        try
        {
            window.Show();
            window.SelectPanel(MainWindow.WorkingPanel.Results);
            Dispatcher.UIThread.RunJobs();
            var viewModel = Assert.IsType<MainViewModel>(window.DataContext);
            Assert.False(viewModel.HasTimeline);
            Assert.False(viewModel.HasNoaaWeather);
            Assert.False(viewModel.HasEcmwfWeather);
            Assert.False(window.FindControl<Border>("ChartTimeline")!.IsEffectivelyVisible);
            var toggle = window.FindControl<CheckBox>("WeatherOnlyToggle")!;
            Assert.True(toggle.IsEffectivelyVisible);
            var point = toggle.TranslatePoint(new Point(toggle.Bounds.Width / 2, toggle.Bounds.Height / 2), window)!.Value;
            window.MouseDown(point, MouseButton.Left, RawInputModifiers.None);
            window.MouseUp(point, MouseButton.Left, RawInputModifiers.None);
            Assert.True(viewModel.WeatherOnlyMode);
        }
        finally { window.Close(); }
    }

    [AvaloniaFact]
    public void Boat_summary_keeps_demo_warning_but_leaves_parser_and_hash_in_details()
    {
        var window = CreateWindow();
        try
        {
            window.Show();
            Dispatcher.UIThread.RunJobs();
            var viewModel = Assert.IsType<MainViewModel>(window.DataContext);
            var panel = window.FindControl<Border>("BoatSummaryPanel")!;
            viewModel.RoutingSetup.Boat = new BoatAsset(
                new string('a', 64), "My demonstration boat", BoatAssetKind.Demo,
                BoatPolarFormat.Automatic, new BoatValidationSummary("verbose-native-parser-report"));
            Dispatcher.UIThread.RunJobs();
            var visibleText = string.Join(" ", panel.GetVisualDescendants()
                .OfType<TextBlock>().Where(text => text.IsEffectivelyVisible).Select(text => text.Text));
            Assert.Contains("My demonstration boat", visibleText);
            Assert.Contains("DEMO BOAT", visibleText);
            Assert.DoesNotContain("verbose-native-parser-report", visibleText);
            Assert.DoesNotContain(new string('a', 64), visibleText);
            var change = panel.GetLogicalDescendants().OfType<Button>().Single();
            change.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
            Dispatcher.UIThread.RunJobs();
            Assert.Equal(MainWindow.WorkingPanel.Settings, window.SelectedPanel);
            var setup = window.FindControl<RoutingSetupView>("CruisingSetupPanel")!;
            Assert.True(setup.FindControl<Expander>("BoatSettingsExpander")!.IsExpanded);
            Assert.True(setup.FindControl<Button>("ImportBoatButton")!.IsEffectivelyVisible);
            Assert.True(setup.FindControl<Button>("DemoBoatButton")!.IsEffectivelyVisible);
        }
        finally { window.Close(); }
    }

    [AvaloniaFact]
    public void Setup_failures_remain_visible_when_panel_is_collapsed()
    {
        var window = CreateWindow();
        try
        {
            window.Show();
            Dispatcher.UIThread.RunJobs();
            window.SetPanelOpen(false);
            var viewModel = Assert.IsType<MainViewModel>(window.DataContext);
            viewModel.RoutingSetup.ErrorMessage = "The selected polar asset is unavailable. Import it again.";
            Dispatcher.UIThread.RunJobs();
            var alerts = window.FindControl<Border>("MessagePopup")!;
            Assert.True(alerts.IsEffectivelyVisible);
            Assert.Contains(alerts.GetVisualDescendants().OfType<TextBlock>(),
                text => text.IsEffectivelyVisible && text.Text == viewModel.RoutingSetup.ErrorMessage);
            viewModel.RoutingSetup.ErrorMessage = null;
            Dispatcher.UIThread.RunJobs();
            Assert.False(alerts.IsVisible);
            viewModel.PreferenceError = "Routing preferences could not be saved.";
            Dispatcher.UIThread.RunJobs();
            Assert.True(alerts.IsVisible);
            window.SetPanelOpen(true);
            Dispatcher.UIThread.RunJobs();
            var messages = window.FindControl<Button>("FooterMessagesButton")!;
            Assert.True(messages.IsEffectivelyVisible);
            Assert.DoesNotContain(
                window.FindControl<ScrollViewer>("PlanningScrollViewer")!,
                messages.GetLogicalAncestors());
        }
        finally { window.Close(); }
    }

    [AvaloniaTheory]
    [InlineData(1040, 680, AppTheme.Light)]
    [InlineData(1280, 800, AppTheme.Light)]
    [InlineData(1040, 680, AppTheme.Dark)]
    [InlineData(1280, 800, AppTheme.Dark)]
    [InlineData(1040, 680, AppTheme.KindOfBlue)]
    [InlineData(1280, 800, AppTheme.KindOfBlue)]
    public void Frequent_inputs_fit_above_fold_and_footer_does_not_scroll(double width, double height, AppTheme theme)
    {
        var service = AppThemeService.CreateTransient();
        service.Initialize(Application.Current!);
        service.SelectTheme(theme);
        var window = new MainWindow(service) { DataContext = CreateViewModel() };
        window.Width = width;
        window.Height = height;
        try
        {
            window.Show();
            Dispatcher.UIThread.RunJobs();
            var scroll = window.FindControl<ScrollViewer>("PlanningScrollViewer")!;
            var footer = window.FindControl<Border>("CalculationFooter")!;
            var calculate = window.FindControl<Button>("CalculateRoutesButton")!;
            var map = window.FindControl<Grid>("MapShell")!;
            Assert.True(map.Bounds.Width >= 560);
            Assert.DoesNotContain(scroll, calculate.GetLogicalAncestors());
            var footerTop = footer.TranslatePoint(default, window)!.Value.Y;
            foreach (var name in new[] { "SetStartButton", "SetDestinationButton", "DepartureNowToggle", "NoaaModelToggle", "EcmwfModelToggle", "BoatSummaryPanel" })
            {
                var control = window.FindControl<Control>(name)!;
                Assert.True(control.IsEffectivelyVisible, name);
                var bottom = control.TranslatePoint(new Point(0, control.Bounds.Height), window)!.Value.Y;
                Assert.True(bottom <= footerTop, $"{name} bottom {bottom} must be above footer {footerTop}.");
            }
            var calculatePosition = calculate.TranslatePoint(default, window);
            window.SelectPanel(MainWindow.WorkingPanel.Settings);
            window.FindControl<Expander>("AdvancedSettingsExpander")!.IsExpanded = true;
            var viewModel = Assert.IsType<MainViewModel>(window.DataContext);
            viewModel.EnableProfessionalRouting = true;
            viewModel.ErrorMessage = "The selected forecast does not cover this passage. Choose another forecast.";
            Dispatcher.UIThread.RunJobs();
            var messages = window.FindControl<Button>("FooterMessagesButton")!;
            var messagePosition = messages.TranslatePoint(default, window);
            Assert.True(messages.IsEffectivelyVisible);
            Assert.DoesNotContain(scroll, messages.GetLogicalAncestors());
            scroll.Offset = new Vector(0, scroll.Extent.Height);
            Dispatcher.UIThread.RunJobs();
            Assert.True(scroll.Offset.Y > 0);
            Assert.Equal(calculatePosition, calculate.TranslatePoint(default, window));
            Assert.Equal(messagePosition, messages.TranslatePoint(default, window));
            Assert.Contains(window.FindControl<StackPanel>("MessageItems")!.GetVisualDescendants().OfType<TextBlock>(),
                text => text.Text == viewModel.ErrorMessage);
            Assert.True(calculate.IsEffectivelyVisible);
            Assert.True(window.FindControl<TextBlock>("CalculationReadinessText")!.IsEffectivelyVisible);
        }
        finally { window.Close(); }
    }

    [AvaloniaFact]
    public void Keyboard_panel_navigation_collapse_and_reopen_restore_focus_and_edits()
    {
        var window = CreateWindow();
        try
        {
            window.Show();
            Dispatcher.UIThread.RunJobs();
            var start = window.FindControl<ToggleButton>("SetStartButton")!;
            start.Focus();
            window.KeyPress(Key.OemPipe, RawInputModifiers.Control, PhysicalKey.Backslash, "\\");
            Assert.True(window.FindControl<MapControl>("MapView")!.IsKeyboardFocusWithin);
            window.KeyPress(Key.OemPipe, RawInputModifiers.Control, PhysicalKey.Backslash, "\\");
            Dispatcher.UIThread.RunJobs();
            Assert.True(start.IsFocused);
            window.KeyPress(Key.D2, RawInputModifiers.Control, PhysicalKey.Digit2, "2");
            Dispatcher.UIThread.RunJobs();
            Assert.True(window.IsRouteDrawerOpen);
            Assert.False(window.IsPlanningDrawerOpen);
            window.KeyPress(Key.D3, RawInputModifiers.Control, PhysicalKey.Digit3, "3");
            Dispatcher.UIThread.RunJobs();
            Assert.Equal(MainWindow.WorkingPanel.Settings, window.SelectedPanel);
            window.KeyPress(Key.D1, RawInputModifiers.Control, PhysicalKey.Digit1, "1");
            Dispatcher.UIThread.RunJobs();
            Assert.True(window.IsPlanningDrawerOpen);
            Assert.True(start.IsFocused);
            window.KeyPress(Key.Tab, RawInputModifiers.None, PhysicalKey.Tab, "\t");
            Assert.True(window.FindControl<ToggleButton>("SetDestinationButton")!.IsFocused);
        }
        finally { window.Close(); }
    }

    [AvaloniaFact]
    public void New_route_reopens_plan_and_settings_back_returns_to_previous_mode()
    {
        var window = CreateWindow();
        try
        {
            window.Show();
            Dispatcher.UIThread.RunJobs();
            window.SelectPanel(MainWindow.WorkingPanel.Results);
            window.SelectPanel(MainWindow.WorkingPanel.Settings);
            var back = window.GetLogicalDescendants().OfType<Button>()
                .Single(button => Equals(button.Content, "Back to passage"));
            back.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
            Assert.True(window.IsRouteDrawerOpen);
            window.SetPanelOpen(false);
            Assert.IsType<MainViewModel>(window.DataContext).Itinerary.NewCommand.Execute(null);
            Dispatcher.UIThread.RunJobs();
            Assert.True(window.IsPlanningDrawerOpen);
        }
        finally { window.Close(); }
    }

    [AvaloniaFact]
    public void Interrupted_popup_is_wrapped_dismissible_and_reopens_from_the_correct_label()
    {
        var window = CreateWindow();
        try
        {
            window.Width = 1040;
            window.Height = 680;
            window.Show();
            window.SetPanelOpen(false);
            var viewModel = Assert.IsType<MainViewModel>(window.DataContext);
            Dispatcher.UIThread.RunJobs();
            var center = MapProjection.ToCoordinate(new Mapsui.MPoint(viewModel.Map.Navigator.Viewport.CenterX,
                viewModel.Map.Navigator.Viewport.CenterY));
            viewModel.SetRoutingFailure(ForecastModel.NoaaGfs, 0, "NOAA work limit reached.", center);
            viewModel.SetRoutingFailure(ForecastModel.EcmwfIfs, 1, "ECMWF work limit reached.", center);
            viewModel.WarningMessage = "A newer forecast is available.";
            Dispatcher.UIThread.RunJobs();
            var popup = window.FindControl<Border>("MessagePopup")!;
            var text = window.FindControl<TextBlock>("MessageIncompleteText")!;
            Assert.False(window.IsPlanningDrawerOpen);
            Assert.False(window.IsRouteDrawerOpen);
            Assert.True(popup.IsVisible);
            Assert.True(popup.Bounds.Width > 0);
            Assert.True(popup.Bounds.Height > 0);
            Assert.Equal(TextWrapping.Wrap, text.TextWrapping);
            Assert.Contains("not completed routes", text.Text);
            var close = window.FindControl<Button>("CloseMessagesButton")!;
            close.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
            Assert.False(popup.IsVisible);
            window.SetPanelOpen(true);
            Dispatcher.UIThread.RunJobs();
            Assert.False(popup.IsVisible);
            var labels = window.FindControl<Canvas>("InterruptedEndpointLayer")!.Children.OfType<Button>().ToArray();
            Assert.Equal(2, labels.Length);
            Assert.False(labels[0].Bounds.Intersects(labels[1].Bounds));
            labels[1].RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
            Dispatcher.UIThread.RunJobs();
            Assert.True(popup.IsVisible);
            var contents = string.Join(" ", window.FindControl<StackPanel>("MessageItems")!
                .GetVisualDescendants().OfType<TextBlock>().Select(block => block.Text));
            Assert.Contains("ECMWF work limit", contents);
            Assert.Contains("leg 2", contents);
            Assert.Contains("newer forecast", contents);
            Assert.DoesNotContain("NOAA work limit", contents);
            window.KeyPress(Key.Escape, RawInputModifiers.None, PhysicalKey.Escape, "\u001b");
            Assert.False(popup.IsVisible);
            Assert.Equal(3, viewModel.CurrentMessages.Count);
            window.FindControl<Button>("MessagesButton")!.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
            Dispatcher.UIThread.RunJobs();
            Assert.True(popup.IsVisible);
        }
        finally { window.Close(); }
    }

    [AvaloniaFact]
    public void New_passage_starts_in_plan_and_all_panel_controls_remain_in_scope()
    {
        var window = CreateWindow();

        try
        {
            window.Show();

            Assert.True(window.IsPlanningDrawerOpen);
            Assert.False(window.IsRouteDrawerOpen);
            Assert.True(Assert.IsType<Border>(
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

    [AvaloniaFact]
    public void Departure_inputs_are_labelled_local_and_echo_the_resolved_utc_instant()
    {
        var window = CreateWindow();

        try
        {
            window.Show();
            window.SetPlanningDrawerOpen(true);
            var viewModel = Assert.IsType<MainViewModel>(window.DataContext);
            viewModel.DepartureNow = false;
            var preview = Assert.IsType<TextBlock>(
                window.FindControl<TextBlock>("DepartureUtcPreviewText"));
            var currentPositionDeparture = Assert.IsType<TextBlock>(
                window.FindControl<TextBlock>("CurrentPositionDepartureDisplay"));

            Assert.NotNull(window.FindControl<DatePicker>("DepartureDatePicker"));
            Assert.NotNull(window.FindControl<TimePicker>("DepartureTimePicker"));
            Assert.NotNull(window.FindControl<DatePicker>("CurrentPositionDatePicker"));
            Assert.NotNull(window.FindControl<TimePicker>("CurrentPositionTimePicker"));

            viewModel.DepartureDate = new DateTimeOffset(2026, 8, 4, 0, 0, 0, TimeSpan.Zero);
            viewModel.DepartureTime = TimeSpan.FromHours(11);
            Dispatcher.UIThread.RunJobs();

            Assert.Equal(viewModel.DepartureUtcPreview, preview.Text);
            Assert.Contains("UTC", preview.Text);
            Assert.Equal("Departs: not set", currentPositionDeparture.Text);
        }
        finally
        {
            window.Close();
        }
    }

    [AvaloniaFact]
    public void Lattice_controls_require_explicit_professional_solver_selection()
    {
        var window = CreateWindow();

        try
        {
            window.Show();
            window.SetPlanningDrawerOpen(true);
            var viewModel = Assert.IsType<MainViewModel>(window.DataContext);
            var beamOptions = Assert.IsType<StackPanel>(
                window.FindControl<StackPanel>("BeamRoutingOptions"));
            var latticeOptions = Assert.IsType<StackPanel>(
                window.FindControl<StackPanel>("LatticeRoutingOptions"));

            Assert.Equal(RouteSolver.IsochroneBeam, viewModel.SelectedRouteSolver);
            Assert.False(viewModel.EnableProfessionalRouting);
            Assert.False(beamOptions.IsVisible);
            Assert.False(latticeOptions.IsVisible);

            viewModel.EnableProfessionalRouting = true;
            Dispatcher.UIThread.RunJobs();
            Assert.True(beamOptions.IsVisible);
            Assert.False(latticeOptions.IsVisible);

            viewModel.SelectedRouteSolver = RouteSolver.TimeDependentLattice;
            Dispatcher.UIThread.RunJobs();
            Assert.False(beamOptions.IsVisible);
            Assert.True(latticeOptions.IsVisible);
        }
        finally
        {
            window.Close();
        }
    }

    [Fact]
    public void Panel_width_policy_preserves_map_floor_at_both_supported_sizes()
    {
        Assert.Equal(474, MainWindow.MaximumPanelWidth(1040));
        Assert.Equal(714, MainWindow.MaximumPanelWidth(1280));
        Assert.True(MainWindow.DefaultPanelWidth >= MainWindow.MinimumPanelWidth);
    }

    [AvaloniaFact]
    public void Narrow_window_has_one_shared_panel_column()
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
            Assert.Equal(MainWindow.DefaultPanelWidth, shell.ColumnDefinitions[0].Width.Value);
            Assert.Equal(560, shell.ColumnDefinitions[2].MinWidth);
        }
        finally
        {
            window.Close();
        }
    }

    [AvaloniaFact]
    public void Wide_window_switches_content_instead_of_opening_a_second_drawer()
    {
        var window = CreateWindow();
        window.Width = 1280;

        try
        {
            window.Show();
            window.SetPlanningDrawerOpen(true);
            window.SetRouteDrawerOpen(true);

            Assert.False(window.IsPlanningDrawerOpen);
            Assert.True(window.IsRouteDrawerOpen);
            var shell = Assert.IsType<Grid>(window.FindControl<Grid>("ShellGrid"));
            Assert.Equal(MainWindow.DefaultPanelWidth, shell.ColumnDefinitions[0].Width.Value);
            Assert.True(shell.ColumnDefinitions[2].ActualWidth >= 560);
        }
        finally
        {
            window.Close();
        }
    }

    [AvaloniaFact]
    public void Resizing_preserves_selected_panel_and_clamps_panel_width()
    {
        var window = CreateWindow();
        window.Width = 1280;

        try
        {
            window.Show();
            window.SetPlanningDrawerOpen(true);
            window.SetRouteDrawerOpen(true);

            var shell = Assert.IsType<Grid>(window.FindControl<Grid>("ShellGrid"));
            shell.ColumnDefinitions[0].Width = new GridLength(700);
            window.Width = 1040;
            Dispatcher.UIThread.RunJobs();

            Assert.False(window.IsPlanningDrawerOpen);
            Assert.True(window.IsRouteDrawerOpen);
            Assert.True(shell.ColumnDefinitions[0].ActualWidth <= 474);
            Assert.True(shell.ColumnDefinitions[2].ActualWidth >= 560);
        }
        finally
        {
            window.Close();
        }
    }

    [AvaloniaFact]
    public void Results_own_leg_details_and_legends_while_timeline_lives_on_chart()
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
                             window.FindControl<Border>("DestinationFrontLegendSwatch"))
                     })
            {
                Assert.Contains(rightDrawer, control.GetLogicalAncestors());
            }
            Assert.Contains(
                Assert.IsType<Grid>(window.FindControl<Grid>("MapShell")),
                window.FindControl<Slider>("TimelineSlider")!.GetLogicalAncestors());
            Assert.Contains(
                window.FindControl<Grid>("MapShell")!,
                window.FindControl<Expander>("WeatherDetailsExpander")!.GetLogicalAncestors());
            Assert.Contains(rightDrawer, window.FindControl<Border>("PassageProgressPanel")!.GetLogicalAncestors());
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
                Assert.IsType<Button>(window.FindControl<Button>("AddWaypointRadialButton")),
                Assert.IsType<Button>(window.FindControl<Button>("SetStartRadialButton")),
                Assert.IsType<Button>(window.FindControl<Button>("SetDestinationRadialButton")),
                Assert.IsType<Button>(window.FindControl<Button>("CalculateRadialButton")),
                Assert.IsType<ToggleButton>(
                    window.FindControl<ToggleButton>("RefreshWeatherRadialToggle"))
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
            Assert.False(buttons[0].IsEffectivelyEnabled);
            viewModel.SetEndpoints(new Coordinate(48, -123), new Coordinate(49, -124));
            Dispatcher.UIThread.RunJobs();
            Assert.True(buttons[0].IsEffectivelyEnabled);
            Assert.Same(viewModel.ForceRecalculateCommand, buttons[3].Command);
            Assert.True(buttons[3].IsEffectivelyEnabled);
            var refreshWeather = Assert.IsType<ToggleButton>(buttons[4]);
            Assert.True(refreshWeather.IsEffectivelyEnabled);
            Assert.False(refreshWeather.IsChecked);
            var refreshPoint = refreshWeather.TranslatePoint(
                new Point(refreshWeather.Bounds.Width / 2, refreshWeather.Bounds.Height / 2),
                window);
            Assert.NotNull(refreshPoint);
            window.MouseDown(refreshPoint.Value, MouseButton.Left, RawInputModifiers.None);
            window.MouseUp(refreshPoint.Value, MouseButton.Left, RawInputModifiers.None);
            Dispatcher.UIThread.RunJobs();
            Assert.True(window.IsRadialMenuOpen);
            refreshWeather.IsChecked = true;
            Dispatcher.UIThread.RunJobs();
            Assert.True(refreshWeather.IsChecked);
            Assert.True(viewModel.UseNewestWeatherData);
            viewModel.UseNewestWeatherData = false;
            Dispatcher.UIThread.RunJobs();
            Assert.False(refreshWeather.IsChecked);
            Assert.Equal(
                5,
                buttons.Select(button => (Canvas.GetLeft(button), Canvas.GetTop(button)))
                    .Distinct()
                    .Count());
            viewModel.ForecastInputMode = ForecastInputMode.LocalFile;
            Dispatcher.UIThread.RunJobs();
            Assert.Equal(viewModel.ForceRecalculateCommand.CanExecute(null), buttons[3].IsEffectivelyEnabled);
            Assert.False(refreshWeather.IsEffectivelyEnabled);
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
    public void RadialWaypointActionUsesCapturedPointAndOpensSelectedItineraryRow()
    {
        var viewModel = CreateViewModel();
        viewModel.SetEndpoints(new Coordinate(48, -123), new Coordinate(49, -124));
        var window = new MainWindow { DataContext = viewModel };

        try
        {
            window.Show();
            var map = Assert.IsType<MapControl>(window.FindControl<MapControl>("MapView"));
            var point = map.TranslatePoint(map.Bounds.Center, window);
            Assert.NotNull(point);
            window.MouseDown(point.Value, MouseButton.Right, RawInputModifiers.None);
            var add = Assert.IsType<Button>(
                window.FindControl<Button>("AddWaypointRadialButton"));

            add.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
            Dispatcher.UIThread.RunJobs();

            Assert.Equal(3, viewModel.Itinerary.Waypoints.Count);
            Assert.NotNull(viewModel.Itinerary.Waypoints[1].Coordinate);
            Assert.Same(
                viewModel.Itinerary.Waypoints[1],
                viewModel.Itinerary.SelectedWaypoint);
            Assert.True(window.IsPlanningDrawerOpen);
            Assert.False(window.IsRadialMenuOpen);
            Assert.Same(
                viewModel.Itinerary.SelectedWaypoint,
                Assert.IsType<ListBox>(window.FindControl<ListBox>("WaypointList")).SelectedItem);
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
    public void Collapsed_panel_shows_only_inflight_progress_without_covering_instructions()
    {
        var window = CreateWindow();
        var viewModel = Assert.IsType<MainViewModel>(window.DataContext);

        try
        {
            window.Show();
            window.SetPanelOpen(false);
            viewModel.SetStartCommand.Execute(null);
            Dispatcher.UIThread.RunJobs();

            var mapShell = Assert.IsType<Grid>(window.FindControl<Grid>("MapShell"));
            var rail = Assert.IsType<Border>(window.FindControl<Border>("InstrumentRail"));
            var host = Assert.IsType<Grid>(window.FindControl<Grid>("InstrumentRailHost"));
            var progressRow = Assert.IsType<StackPanel>(
                window.FindControl<StackPanel>("InstrumentRailProgressRow"));
            var progress = Assert.IsType<ProgressBar>(
                window.FindControl<ProgressBar>("InstrumentRailProgressBar"));
            var cancel = Assert.IsType<Button>(
                window.FindControl<Button>("InstrumentRailCancelButton"));

            Assert.False(host.IsVisible);
            Assert.False(progressRow.IsVisible);
            Assert.False(progress.IsVisible);
            Assert.False(cancel.IsEffectivelyVisible);
            Assert.Contains(mapShell, rail.GetLogicalAncestors());
            Assert.DoesNotContain(rail, cancel.GetLogicalAncestors());
            Assert.False(rail.IsHitTestVisible);
            Assert.True(cancel.IsHitTestVisible);

            viewModel.ProgressFraction = 0.64;
            viewModel.IsCalculating = true;
            Dispatcher.UIThread.RunJobs();

            Assert.True(host.IsVisible);
            Assert.True(progressRow.IsVisible);
            Assert.True(progress.IsVisible);
            Assert.True(cancel.IsEffectivelyVisible);
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
            Assert.False(host.IsVisible);
            Assert.False(progressRow.IsVisible);
            Assert.False(progress.IsVisible);
        }
        finally
        {
            window.Close();
        }
    }

    [AvaloniaFact]
    public void RouteTelemetryShowsRequestedFieldsAndSupportsTouchAndEscapeDismissal()
    {
        var window = CreateWindow();
        var viewModel = Assert.IsType<MainViewModel>(window.DataContext);

        try
        {
            window.Show();
            Dispatcher.UIThread.RunJobs();
            var map = Assert.IsType<MapControl>(window.FindControl<MapControl>("MapView"));
            var center = map.Bounds.Center;
            var coordinate = MapProjection.ToCoordinate(
                map.Map.Navigator.Viewport.ScreenToWorld(center.X, center.Y));
            var selection = CreateRouteSelection(coordinate);
            var projected = viewModel.GetProjectedRoutePoint(selection);
            viewModel.Map.Navigator.SetViewport(new Mapsui.Viewport(
                projected.X,
                projected.Y,
                10_000,
                0,
                map.Bounds.Width,
                map.Bounds.Height));

            viewModel.SelectRoutePoint(selection, focus: false);
            Dispatcher.UIThread.RunJobs();

            var layer = Assert.IsType<Canvas>(
                window.FindControl<Canvas>("RouteTelemetryLayer"));
            var card = Assert.IsType<Button>(
                window.FindControl<Button>("RouteTelemetryCard"));
            Assert.True(layer.IsVisible);
            Assert.Equal("Route point telemetry", AutomationProperties.GetName(card));
            Assert.Contains("Click or tap to close", AutomationProperties.GetHelpText(card));
            Assert.Equal(
                "14 Jul · 12:00 UTC",
                Assert.IsType<TextBlock>(
                    window.FindControl<TextBlock>("RouteTelemetryTime")).Text);
            Assert.Equal(
                "6.0 kt",
                Assert.IsType<TextBlock>(
                    window.FindControl<TextBlock>("RouteTelemetryBoatSpeed")).Text);
            Assert.Equal(
                "15.0 kt",
                Assert.IsType<TextBlock>(
                    window.FindControl<TextBlock>("RouteTelemetryTrueWind")).Text);
            Assert.Equal(
                "180°",
                Assert.IsType<TextBlock>(
                    window.FindControl<TextBlock>("RouteTelemetryTrueWindDirection")).Text);
            Assert.Equal(
                "16.2 kt",
                Assert.IsType<TextBlock>(
                    window.FindControl<TextBlock>("RouteTelemetryApparentWind")).Text);
            Assert.Equal(
                "68° S",
                Assert.IsType<TextBlock>(
                    window.FindControl<TextBlock>("RouteTelemetryApparentWindAngle")).Text);
            Assert.Equal(
                "90°",
                Assert.IsType<TextBlock>(
                    window.FindControl<TextBlock>("RouteTelemetryHeading")).Text);
            Assert.True(new ScreenRect(0, 0, map.Bounds.Width, map.Bounds.Height).Contains(
                new ScreenRect(
                    Canvas.GetLeft(card),
                    Canvas.GetTop(card),
                    card.Width,
                    card.Height)));

            card.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
            Dispatcher.UIThread.RunJobs();

            Assert.Null(viewModel.SelectedRoutePoint);
            Assert.False(layer.IsVisible);

            viewModel.SelectRoutePoint(selection, focus: false);
            Dispatcher.UIThread.RunJobs();
            map.Focus();
            window.KeyPress(
                Key.Escape,
                RawInputModifiers.None,
                PhysicalKey.Escape,
                string.Empty);
            Dispatcher.UIThread.RunJobs();

            Assert.Null(viewModel.SelectedRoutePoint);
            Assert.False(layer.IsVisible);
        }
        finally
        {
            window.Close();
        }
    }

    [AvaloniaFact]
    public void ExistingRouteSelectionDoesNotOpenTelemetryWhenWindowLoads()
    {
        var viewModel = CreateViewModel();
        viewModel.SelectRoutePoint(
            CreateRouteSelection(new Coordinate(0, 0)),
            focus: false);
        var window = new MainWindow { DataContext = viewModel };

        try
        {
            window.Show();
            Dispatcher.UIThread.RunJobs();

            Assert.NotNull(viewModel.SelectedRoutePoint);
            Assert.False(Assert.IsType<Canvas>(
                window.FindControl<Canvas>("RouteTelemetryLayer")).IsVisible);
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
            window.SetRouteDrawerOpen(true);
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
    public void Waypoint_editing_is_disclosed_on_selection_without_a_second_gutter()
    {
        var window = CreateWindow();
        window.Width = 1040;
        window.Height = 680;

        try
        {
            window.Show();
            Dispatcher.UIThread.RunJobs();
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

            Assert.Equal(400, shell.ColumnDefinitions[0].Width.Value);
            Assert.Empty(drawer.ColumnDefinitions);
            Assert.Equal(0, Grid.GetColumn(content));
            Assert.Equal("Plan", handle.Content);
            Assert.Equal(default, content.Padding);
            Assert.Equal(2, endpoints.ColumnDefinitions.Count);
            Assert.Equal(
                endpoints.ColumnDefinitions[0].Width,
                endpoints.ColumnDefinitions[1].Width);
            Assert.True(shell.ColumnDefinitions[2].ActualWidth >= 560);
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
    public void CompactPickersKeepEveryValueSegmentInsideTheDrawerFields()
    {
        var window = CreateWindow();
        window.Width = 1040;
        window.Height = 680;

        try
        {
            window.Show();
            window.SetPlanningDrawerOpen(true);
            Assert.IsType<MainViewModel>(window.DataContext).DepartureNow = false;
            var datePicker = Assert.IsType<DatePicker>(
                window.FindControl<DatePicker>("DepartureDatePicker"));
            var timePicker = Assert.IsType<TimePicker>(
                window.FindControl<TimePicker>("DepartureTimePicker"));
            datePicker.SelectedDate = new DateTimeOffset(
                2026,
                8,
                4,
                0,
                0,
                0,
                TimeSpan.Zero);
            timePicker.SelectedTime = new TimeSpan(8, 22, 0);
            Dispatcher.UIThread.RunJobs();

            AssertPickerFits(
                datePicker,
                "PART_DayTextBlock",
                "PART_MonthTextBlock",
                "PART_YearTextBlock");
            AssertPickerFits(
                timePicker,
                "PART_HourTextBlock",
                "PART_MinuteTextBlock");
            AssertPickerTextIsCentered(
                datePicker,
                "PART_DayTextBlock",
                "PART_MonthTextBlock",
                "PART_YearTextBlock");
            AssertPickerTextIsCentered(
                timePicker,
                "PART_HourTextBlock",
                "PART_MinuteTextBlock");
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
            Assert.Equal(6, saved.ColumnSpacing);
            Assert.Equal(3, save.ColumnDefinitions.Count);
            Assert.Equal(6, save.ColumnSpacing);
        }
        finally
        {
            window.Close();
        }
    }

    private static MainWindow CreateWindow() =>
        new() { DataContext = CreateViewModel() };

    private static void AssertPickerFits(
        TemplatedControl picker,
        params string[] partNames)
    {
        picker.ApplyTemplate();
        var descendants = picker.GetVisualDescendants().ToArray();
        var flyoutButton = descendants
            .OfType<Button>()
            .Single(control => control.Name == "PART_FlyoutButton");
        var textParts = descendants
            .OfType<TextBlock>()
            .Where(part => partNames.Contains(part.Name))
            .ToArray();

        Assert.True(picker.Bounds.Width > 1, $"{picker.Name} must be arranged.");
        Assert.True(flyoutButton.Bounds.Width > 1, $"{picker.Name} flyout must be arranged.");
        Assert.True(
            flyoutButton.Bounds.Width <= picker.Bounds.Width + 0.5,
            $"{picker.Name} flyout content must not exceed its allocated width.");
        Assert.Equal(partNames.Length, textParts.Length);

        foreach (var part in textParts)
        {
            Assert.True(part.IsEffectivelyVisible, $"{part.Name} must be visible.");
            Assert.False(string.IsNullOrWhiteSpace(part.Text), $"{part.Name} must display a value.");
            var origin = part.TranslatePoint(default, flyoutButton);
            Assert.NotNull(origin);
            Assert.True(origin.Value.X >= -0.5, $"{part.Name} must start inside the picker.");
            Assert.True(
                origin.Value.X + part.Bounds.Width <= flyoutButton.Bounds.Width + 0.5,
                $"{part.Name} must end inside the picker.");
        }
    }

    private static void AssertPickerTextIsCentered(
        TemplatedControl picker,
        params string[] partNames)
    {
        var descendants = picker.GetVisualDescendants().ToArray();
        var flyoutButton = descendants
            .OfType<Button>()
            .Single(control => control.Name == "PART_FlyoutButton");
        var textParts = descendants
            .OfType<TextBlock>()
            .Where(part => partNames.Contains(part.Name))
            .ToArray();

        Assert.Equal(partNames.Length, textParts.Length);
        foreach (var part in textParts)
        {
            Assert.Equal(HorizontalAlignment.Center, part.HorizontalAlignment);
            Assert.Equal(VerticalAlignment.Center, part.VerticalAlignment);
            if (picker is TimePicker)
            {
                Assert.Equal(TextAlignment.Center, part.TextAlignment);
            }
            Assert.Equal(default, part.Padding);
            var origin = part.TranslatePoint(default, flyoutButton);
            Assert.NotNull(origin);
            var center = origin.Value.Y + (part.Bounds.Height / 2);
            Assert.InRange(Math.Abs(center - (flyoutButton.Bounds.Height / 2)), 0, 0.5);
        }
    }

    private static RouteMapSelection CreateRouteSelection(Coordinate coordinate)
    {
        var departure = new DateTimeOffset(2026, 7, 14, 12, 0, 0, TimeSpan.Zero);
        var destination = new Coordinate(
            Math.Clamp(coordinate.Latitude + 0.25, -89, 89),
            coordinate.Longitude <= 179.5
                ? coordinate.Longitude + 0.25
                : coordinate.Longitude - 0.25);
        var request = new RouteRequest(
            "telemetry-test",
            coordinate,
            destination,
            departure,
            departure.AddHours(6));
        var point = new RoutePoint(coordinate, departure, 90, 6, 15, 180, 0,
            environment: null, polarWindSpeedKnots: 15, polarWindDirectionDegrees: 180);
        var route = new RouteResult(
            request,
            ForecastModel.NoaaGfs,
            [
                point,
                new RoutePoint(destination, departure.AddHours(6), 90, 6, 15, 180, 30)
            ],
            new RouteDiagnostics(10, 20, 5, 2));
        return new RouteMapSelection(
            route,
            0,
            point,
            RouteHitKind.RoutePoint,
            0);
    }

    private static MainViewModel CreateViewModel() =>
        new(
            null,
            null,
            TimeProvider.System,
            TimeZoneInfo.Utc,
            new OsmTileOptions(Enabled: false));
}
