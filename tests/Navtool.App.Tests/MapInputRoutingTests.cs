using Avalonia;
using Avalonia.Controls;
using Avalonia.Headless;
using Avalonia.Headless.XUnit;
using Avalonia.Input;
using Avalonia.Interactivity;
using Mapsui.Manipulations;
using Mapsui.UI.Avalonia;
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
}
