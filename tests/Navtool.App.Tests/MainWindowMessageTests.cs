using Avalonia;
using Avalonia.Controls;
using Avalonia.Headless;
using Avalonia.Headless.XUnit;
using Avalonia.Input;
using Avalonia.Interactivity;
using Avalonia.Threading;
using Avalonia.VisualTree;
using Mapsui.Extensions;
using Navtool.App.Models;
using Navtool.App.Services;
using Navtool.App.ViewModels;
using Navtool.App.Views;
using Navtool.Core;
using Navtool.Infrastructure;

namespace Navtool.App.Tests;

public sealed class MainWindowMessageTests
{
    [AvaloniaFact]
    public void Outcome_opens_after_calculation_and_dismissal_survives_unrelated_updates()
    {
        using var fixture = new MessageWindow();
        var (window, model) = (fixture.Window, fixture.Model);
        model.IsCalculating = true;
        model.WarningMessage = "A newer run is available.";
        Dispatcher.UIThread.RunJobs();
        Assert.False(window.IsMessagePopupOpen);
        model.IsCalculating = false;
        Dispatcher.UIThread.RunJobs();
        Assert.True(window.IsMessagePopupOpen);
        Click(window, "CloseMessagesButton");
        model.ProgressFraction = .5;
        model.StatusMessage = "Unrelated status update";
        window.SetPanelOpen(false);
        Dispatcher.UIThread.RunJobs();
        Assert.False(window.IsMessagePopupOpen);
        Assert.Single(model.CurrentMessages);
        model.WarningMessage = "Forecast coverage is incomplete.";
        Dispatcher.UIThread.RunJobs();
        Assert.True(window.IsMessagePopupOpen);
    }

    [AvaloniaFact]
    public async Task Repeated_explicit_validation_failure_reopens_and_keeps_keyboard_focus()
    {
        using var fixture = new MessageWindow();
        var (window, model) = (fixture.Window, fixture.Model);
        var focused = window.FindControl<Control>("SetStartButton")!;
        focused.Focus();
        await model.CalculateRoutesAsync();
        Dispatcher.UIThread.RunJobs();
        Assert.True(window.IsMessagePopupOpen);
        Assert.True(focused.IsKeyboardFocusWithin);
        Click(window, "CloseMessagesButton");
        Assert.False(window.IsMessagePopupOpen);
        await model.CalculateRoutesAsync();
        Dispatcher.UIThread.RunJobs();
        Assert.True(window.IsMessagePopupOpen);
        Click(window, "CloseMessagesButton");
        var opener = window.FindControl<Button>("MessagesButton")!;
        Click(window, "MessagesButton");
        Assert.True(window.FindControl<Button>("CloseMessagesButton")!.IsFocused);
        window.KeyPress(Key.Escape, RawInputModifiers.None, PhysicalKey.Escape, "\u001b");
        Assert.False(window.IsMessagePopupOpen);
        Assert.True(opener.IsFocused);
    }

    [AvaloniaFact]
    public void New_messages_preserve_open_popup_filter_and_scroll_position()
    {
        using var fixture = new MessageWindow();
        var (window, model) = (fixture.Window, fixture.Model);
        var reason = string.Join(" ", Enumerable.Repeat("Detailed NOAA interruption context.", 200));
        model.SetRoutingFailure(ForecastModel.NoaaGfs, 0, reason, new Coordinate(0, 0));
        Dispatcher.UIThread.RunJobs();
        var button = Assert.Single(window.FindControl<Canvas>("InterruptedEndpointLayer")!.Children.OfType<Button>());
        button.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
        Dispatcher.UIThread.RunJobs();
        var scroll = window.FindControl<ScrollViewer>("MessageScrollViewer")!;
        scroll.Offset = new Vector(0, 180);
        Dispatcher.UIThread.RunJobs();
        var offset = scroll.Offset;
        Assert.True(offset.Y > 0);

        model.SetRoutingFailure(ForecastModel.EcmwfIfs, 0, "New ECMWF interruption.", new Coordinate(0, 1));
        Dispatcher.UIThread.RunJobs();

        Assert.True(window.IsMessagePopupOpen);
        Assert.Equal("NOAA GFS interrupted", window.FindControl<TextBlock>("MessagePopupTitle")!.Text);
        Assert.Equal(offset, scroll.Offset);
        Assert.DoesNotContain(window.FindControl<StackPanel>("MessageItems")!.GetVisualDescendants().OfType<TextBlock>(),
            text => text.Text == "New ECMWF interruption.");
        Click(window, "CloseMessagesButton");
        model.StatusMessage = "Unrelated update";
        Dispatcher.UIThread.RunJobs();
        Assert.False(window.IsMessagePopupOpen);
    }

    [AvaloniaFact]
    public void Endpoint_click_uses_updated_message_before_the_queued_refresh()
    {
        using var fixture = new MessageWindow();
        var (window, model) = (fixture.Window, fixture.Model);
        model.Map.Navigator.CenterOnAndZoomTo(MapProjection.ToMapPoint(new Coordinate(0, 0)), 10_000);
        model.SetRoutingFailure(ForecastModel.NoaaGfs, 0, "Initial reason.", new Coordinate(0, 0));
        Dispatcher.UIThread.RunJobs();
        var button = Assert.Single(window.FindControl<Canvas>("InterruptedEndpointLayer")!.Children.OfType<Button>());
        Click(window, "CloseMessagesButton");

        model.SetRoutingFailure(ForecastModel.NoaaGfs, 0, "Updated reason.");
        button.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));

        Assert.True(window.IsMessagePopupOpen);
        Assert.Equal("NOAA GFS interrupted", window.FindControl<TextBlock>("MessagePopupTitle")!.Text);
        var texts = window.FindControl<StackPanel>("MessageItems")!.GetVisualDescendants().OfType<TextBlock>()
            .Select(text => text.Text).ToArray();
        Assert.Contains("Updated reason.", texts);
        Assert.DoesNotContain("Initial reason.", texts);
        Click(window, "CloseMessagesButton");
        var currentButton = Assert.Single(window.FindControl<Canvas>("InterruptedEndpointLayer")!.Children.OfType<Button>());
        Assert.True(currentButton.IsFocused);
        Dispatcher.UIThread.RunJobs();
        Assert.False(window.IsMessagePopupOpen);
    }

    [AvaloniaFact]
    public async Task Old_endpoint_cannot_reopen_after_a_new_attempt_clears_its_outcome()
    {
        using var fixture = new MessageWindow();
        var (window, model) = (fixture.Window, fixture.Model);
        model.SetRoutingFailure(ForecastModel.NoaaGfs, 1, "Search stopped.", new Coordinate(0, 0));
        Dispatcher.UIThread.RunJobs();
        var oldButton = Assert.Single(window.FindControl<Canvas>("InterruptedEndpointLayer")!.Children.OfType<Button>());
        Click(window, "CloseMessagesButton");
        await model.CalculateRoutesAsync();
        Dispatcher.UIThread.RunJobs();
        Click(window, "CloseMessagesButton");
        oldButton.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
        Assert.False(window.IsMessagePopupOpen);
        Assert.Empty(window.FindControl<Canvas>("InterruptedEndpointLayer")!.Children);
        Assert.DoesNotContain(model.CurrentMessages, message => message.IsInterrupted);
    }

    [AvaloniaTheory]
    [InlineData(AppTheme.Light)]
    [InlineData(AppTheme.Dark)]
    [InlineData(AppTheme.KindOfBlue)]
    public void Long_messages_scroll_and_have_one_prominent_copy(AppTheme theme)
    {
        using var fixture = new MessageWindow(theme);
        var (window, model) = (fixture.Window, fixture.Model);
        window.Width = 1040;
        window.Height = 680;
        var reason = string.Join(" ", Enumerable.Repeat("An actionable diagnostic with supporting context.", 160));
        model.ErrorMessage = reason;
        model.WarningMessage = "Distinct notice.\nDistinct notice.";
        Dispatcher.UIThread.RunJobs();
        Assert.Equal(2, model.CurrentMessages.Count);
        var popup = window.FindControl<Border>("MessagePopup")!;
        var map = window.FindControl<Grid>("MapShell")!;
        Assert.True(popup.Bounds.Width <= map.Bounds.Width);
        Assert.True(popup.Bounds.Bottom < map.Bounds.Height);
        var scroll = window.FindControl<ScrollViewer>("MessageScrollViewer")!;
        Assert.True(scroll.Extent.Height > scroll.Viewport.Height);
        Assert.Single(window.GetVisualDescendants().OfType<TextBlock>(),
            text => text.IsEffectivelyVisible && text.Text == reason);
        Assert.Single(window.GetVisualDescendants().OfType<TextBlock>(),
            text => text.IsEffectivelyVisible && text.Text == "Distinct notice.");
        var close = window.FindControl<Button>("CloseMessagesButton")!;
        Assert.True(close.IsEffectivelyVisible);
        AvaloniaHeadlessPlatform.ForceRenderTimerTick();
        var point = close.TranslatePoint(new Rect(close.Bounds.Size).Center, window)!.Value;
        var target = window.InputHitTest(point);
        Assert.True(target is Visual visual && (visual == close || visual.GetVisualAncestors().Contains(close)),
            $"Close at {point}, bounds {close.Bounds}, popup {popup.Bounds}, window {window.Bounds}, hit {target}");
    }

    [AvaloniaFact]
    public void Coverage_context_is_in_details_but_real_coverage_errors_are_not_hidden()
    {
        using var fixture = new MessageWindow();
        var model = fixture.Model;
        model.SetRoutingFailure(ForecastModel.NoaaGfs, 0,
            "Search work limit reached. The loaded forecast covers the requested passage.", new Coordinate(0, 0));
        var interrupted = Assert.Single(model.CurrentMessages);
        Assert.Equal("Search work limit reached.", interrupted.Summary);
        Assert.Equal("The loaded forecast covers the requested passage.", interrupted.Details);
        model.SetRoutingFailure(ForecastModel.EcmwfIfs, 0, "Forecast does not cover the requested passage.");
        Assert.Contains(model.CurrentMessages, message => message.Summary == "Forecast does not cover the requested passage.");
    }

    [AvaloniaTheory]
    [InlineData(-1)]
    [InlineData(0)]
    [InlineData(1)]
    public void Overlapping_labels_are_clickable_in_rotated_world_copies_without_placing_endpoints(int worldCopy)
    {
        using var fixture = new MessageWindow();
        var (window, model) = (fixture.Window, fixture.Model);
        var endpoint = new Coordinate(0, 179);
        var projected = MapProjection.ToMapPoint(endpoint);
        model.Map.Navigator.CenterOnAndZoomTo(
            new Mapsui.MPoint(projected.X + worldCopy * MapProjection.WebMercatorWorldWidth, projected.Y), 10_000);
        model.Map.Navigator.RotateTo(30);
        model.SetRoutingFailure(ForecastModel.NoaaGfs, 0, "NOAA stopped.", endpoint);
        model.SetRoutingFailure(ForecastModel.EcmwfIfs, 0, "ECMWF stopped.", endpoint);
        Dispatcher.UIThread.RunJobs();
        AvaloniaHeadlessPlatform.ForceRenderTimerTick();
        Dispatcher.UIThread.RunJobs();
        AvaloniaHeadlessPlatform.ForceRenderTimerTick();
        var canvas = window.FindControl<Canvas>("InterruptedEndpointLayer")!;
        var labels = canvas.Children.OfType<Button>().ToArray();
        Assert.All(labels, label => Assert.True(label.IsEffectivelyVisible));
        Assert.False(labels[0].Bounds.Intersects(labels[1].Bounds));
        var popup = window.FindControl<Border>("MessagePopup")!;
        Assert.All(labels, label =>
        {
            Assert.False(label.Bounds.Intersects(popup.Bounds));
            Assert.True(new Rect(canvas.Bounds.Size).Contains(label.Bounds), $"Label {label.Bounds}, canvas {canvas.Bounds}");
            var center = label.TranslatePoint(new Rect(label.Bounds.Size).Center, window)!.Value;
            var hit = window.InputHitTest(center) as Visual;
            Assert.True(hit == label || hit?.GetVisualAncestors().Contains(label) is true,
                $"Label {label.Bounds}, center {center}, hit {hit}, popup {popup.Bounds}");
        });
        Click(window, "CloseMessagesButton");
        model.SetStartCommand.Execute(null);
        Dispatcher.UIThread.RunJobs();
        AvaloniaHeadlessPlatform.ForceRenderTimerTick();
        Dispatcher.UIThread.RunJobs();
        AvaloniaHeadlessPlatform.ForceRenderTimerTick();
        var oldStart = model.Itinerary.Start;
        var point = labels[1].TranslatePoint(new Rect(labels[1].Bounds.Size).Center, window)!.Value;
        window.MouseDown(point, MouseButton.Left, RawInputModifiers.None);
        window.MouseUp(point, MouseButton.Left, RawInputModifiers.None);
        Dispatcher.UIThread.RunJobs();
        Assert.True(window.IsMessagePopupOpen);
        Assert.Equal("ECMWF IFS interrupted", window.FindControl<TextBlock>("MessagePopupTitle")!.Text);
        Assert.Equal(oldStart, model.Itinerary.Start);
    }

    private static void Click(MainWindow window, string name)
    {
        window.FindControl<Button>(name)!.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
        Dispatcher.UIThread.RunJobs();
    }

    private sealed class MessageWindow : IDisposable
    {
        public MainViewModel Model { get; } = new(null, null, TimeProvider.System, TimeZoneInfo.Utc,
            new OsmTileOptions(Enabled: false));
        public MainWindow Window { get; }

        public MessageWindow(AppTheme theme = AppTheme.Light)
        {
            var service = AppThemeService.CreateTransient();
            service.Initialize(Application.Current!);
            service.SelectTheme(theme);
            Window = new MainWindow(service) { DataContext = Model };
            Window.Show();
            Dispatcher.UIThread.RunJobs();
        }

        public void Dispose() => Window.Close();
    }
}
