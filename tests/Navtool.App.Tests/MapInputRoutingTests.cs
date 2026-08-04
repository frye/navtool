using Avalonia;
using Avalonia.Controls;
using Avalonia.Headless;
using Avalonia.Headless.XUnit;
using Avalonia.Input;
using Avalonia.Interactivity;
using Mapsui.Manipulations;
using Mapsui.UI.Avalonia;
using Navtool.App.Models;
using Navtool.App.Services;
using Navtool.App.ViewModels;
using Navtool.App.Views;
using Navtool.Infrastructure;

namespace Navtool.App.Tests;

public sealed class MapInputRoutingTests
{
    [AvaloniaFact]
    public void RightClickIsHandledDuringTunnelBeforeMapManipulation()
    {
        var window = new MainWindow
        {
            DataContext = new MainViewModel(
                null,
                null,
                TimeProvider.System,
                TimeZoneInfo.Utc,
                new OsmTileOptions(Enabled: false))
        };
        var bubblePresses = 0;

        try
        {
            window.Show();
            var map = Assert.IsType<MapControl>(window.FindControl<MapControl>("MapView"));
            map.AddHandler(
                InputElement.PointerPressedEvent,
                (_, _) => bubblePresses++,
                RoutingStrategies.Bubble);
            var point = map.TranslatePoint(map.Bounds.Center, window);
            Assert.NotNull(point);

            window.MouseDown(point.Value, MouseButton.Right, RawInputModifiers.None);

            Assert.True(window.IsRadialMenuOpen);
            Assert.Equal(0, bubblePresses);
        }
        finally
        {
            window.Close();
        }
    }

    [Fact]
    public void MapsuiLongPressIsTheOnlyTapGestureThatInvokesRadialInput()
    {
        Assert.True(MainWindow.IsRadialGesture(GestureType.LongPress));
        Assert.False(MainWindow.IsRadialGesture(GestureType.SingleTap));
        Assert.False(MainWindow.IsRadialGesture(GestureType.DoubleTap));
    }

    [AvaloniaFact]
    public void ClickAwayDismissalIsConsumedBeforeTheMapActionPath()
    {
        var viewModel = new MainViewModel(
            null,
            null,
            TimeProvider.System,
            TimeZoneInfo.Utc,
            new OsmTileOptions(Enabled: false));
        var window = new MainWindow { DataContext = viewModel };
        var bubblePresses = 0;

        try
        {
            window.Show();
            var map = Assert.IsType<MapControl>(window.FindControl<MapControl>("MapView"));
            var point = map.TranslatePoint(map.Bounds.Center, window);
            Assert.NotNull(point);
            window.MouseDown(point.Value, MouseButton.Right, RawInputModifiers.None);
            window.MouseUp(point.Value, MouseButton.Right, RawInputModifiers.None);
            Assert.True(window.IsRadialMenuOpen);
            map.AddHandler(
                InputElement.PointerPressedEvent,
                (_, _) => bubblePresses++,
                RoutingStrategies.Bubble);
            viewModel.SetStartCommand.Execute(null);

            var dismissPoint = point.Value + new Point(24, 24);
            window.MouseDown(dismissPoint, MouseButton.Left, RawInputModifiers.None);
            window.MouseUp(dismissPoint, MouseButton.Left, RawInputModifiers.None);

            Assert.False(window.IsRadialMenuOpen);
            Assert.Equal(0, bubblePresses);
            Assert.Null(viewModel.Start);
            Assert.Equal(MapInteractionMode.SetStart, viewModel.InteractionMode);
        }
        finally
        {
            window.Close();
        }
    }

    [AvaloniaFact]
    public void CalculateRadialActionExecutesBoundCommandClosesAndDoesNotLeakToMap()
    {
        var viewModel = new MainViewModel(
            null,
            null,
            TimeProvider.System,
            TimeZoneInfo.Utc,
            new OsmTileOptions(Enabled: false));
        var window = new MainWindow { DataContext = viewModel };
        var mapPresses = 0;

        try
        {
            window.Show();
            var map = Assert.IsType<MapControl>(window.FindControl<MapControl>("MapView"));
            map.AddHandler(
                InputElement.PointerPressedEvent,
                (_, _) => mapPresses++,
                RoutingStrategies.Bubble);
            var mapPoint = map.TranslatePoint(map.Bounds.Center, window);
            Assert.NotNull(mapPoint);
            window.MouseDown(mapPoint.Value, MouseButton.Right, RawInputModifiers.None);
            window.MouseUp(mapPoint.Value, MouseButton.Right, RawInputModifiers.None);
            var calculate = Assert.IsType<Button>(
                window.FindControl<Button>("CalculateRadialButton"));
            Assert.Same(viewModel.ForceRecalculateCommand, calculate.Command);
            calculate.Focus();
            window.KeyPress(
                Key.Enter,
                RawInputModifiers.None,
                PhysicalKey.Enter,
                "\r");

            Assert.False(window.IsRadialMenuOpen);
            Assert.Equal("Routing services are unavailable in the designer.", viewModel.ErrorMessage);
            Assert.Equal(0, mapPresses);
        }
        finally
        {
            window.Close();
        }
    }
}
