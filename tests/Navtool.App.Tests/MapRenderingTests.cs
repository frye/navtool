using Avalonia.Controls;
using Avalonia.Headless.XUnit;
using Mapsui.Tiling.Layers;
using Mapsui.UI.Avalonia;
using Navtool.App.Services;
using Navtool.App.ViewModels;
using Navtool.App.Views;

namespace Navtool.App.Tests;

public sealed class MapRenderingTests
{
    [AvaloniaFact]
    public void MainWindowLeavesMapsuiSurfaceUncoveredAndEnablesContinuousZoom()
    {
        var viewModel = CreateViewModel(tilesEnabled: false);
        var window = new MainWindow
        {
            DataContext = viewModel
        };

        try
        {
            window.Show();
            var mapControl = window.FindControl<MapControl>("MapView");

            Assert.NotNull(mapControl);
            Assert.Same(viewModel.Map, mapControl.Map);
            Assert.Null(mapControl.Background);
            Assert.True(mapControl.UseContinuousMouseWheelZoom);
        }
        finally
        {
            window.Close();
        }
    }

    [Fact]
    public void MapCompositionPlacesOpenStreetMapBelowRouteOverlays()
    {
        var viewModel = CreateViewModel(tilesEnabled: true);
        var layers = viewModel.Map.Layers.ToArray();

        var baseLayer = Assert.IsType<TileLayer>(layers[0]);
        Assert.True(baseLayer.Enabled);
        Assert.Equal("OpenStreetMap", baseLayer.Name);
        Assert.Equal("© OpenStreetMap contributors", baseLayer.Attribution.Text);
        Assert.Equal(
            [
                "Wind speed",
                "Wind direction",
                "NOAA GFS routes",
                "ECMWF IFS routes",
                "Route endpoints",
                "Timeline route points",
                "Selected route point"
            ],
            layers.Skip(1).Select(layer => layer.Name));
    }

    private static MainViewModel CreateViewModel(bool tilesEnabled) =>
        new(
            null,
            null,
            TimeProvider.System,
            TimeZoneInfo.Utc,
            new OsmTileOptions(Enabled: tilesEnabled));
}
