using Avalonia.Controls;
using Avalonia.Headless.XUnit;
using Avalonia.Media;
using Mapsui;
using Mapsui.Layers;
using Mapsui.Nts;
using Mapsui.Styles;
using Mapsui.Tiling.Layers;
using Mapsui.UI.Avalonia;
using Navtool.App.Services;
using Navtool.App.ViewModels;
using Navtool.Core;
using Navtool.App.Views;
using AvaloniaColor = Avalonia.Media.Color;
using LineString = NetTopologySuite.Geometries.LineString;
using MultiLineString = NetTopologySuite.Geometries.MultiLineString;

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

    [AvaloniaFact]
    public void MainWindowExposesDurationAndExistingGribControls()
    {
        var window = new MainWindow
        {
            DataContext = CreateViewModel(tilesEnabled: false)
        };

        try
        {
            window.Show();

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
    public void MainWindowLegendShowsVisibleRedIsochrones()
    {
        var window = new MainWindow
        {
            DataContext = CreateViewModel(tilesEnabled: false)
        };

        try
        {
            window.Show();

            var swatch = window.FindControl<Border>("IsochroneLegendSwatch");
            Assert.NotNull(swatch);
            var brush = Assert.IsType<SolidColorBrush>(swatch.Background);
            Assert.Equal(AvaloniaColor.Parse("#D32F2F"), brush.Color);
            Assert.Equal(0.85, swatch.Opacity);
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
                "NOAA GFS isochrones",
                "ECMWF IFS isochrones",
                "NOAA GFS provisional route",
                "ECMWF IFS provisional route",
                "NOAA GFS routes",
                "ECMWF IFS routes",
                "Route endpoints",
                "Timeline route points",
                "Selected route point"
            ],
            layers.Skip(1).Select(layer => layer.Name));
    }

    [Fact]
    public void WindOverlayLayersHaveNoDefaultLayerStyle()
    {
        var viewModel = CreateViewModel(tilesEnabled: true);
        var layers = viewModel.Map.Layers.ToArray();

        var windSpeed = layers.Single(layer => layer.Name == "Wind speed");
        var windDirection = layers.Single(layer => layer.Name == "Wind direction");

        // A MemoryLayer with no explicit Style falls back to Mapsui's default
        // VectorStyle (gray fill + outline), which would paint a grid over the map.
        // Only per-feature styles should render, so the layer Style must be null.
        Assert.Null(windSpeed.Style);
        Assert.Null(windDirection.Style);
    }

    [Fact]
    public void StreamingLayersAccumulateFrontiersReplaceProvisionalRoutesAndClearPerModel()
    {
        var map = new Map();
        var layers = new RouteMapLayers(map);
        var firstFrontier = CreateDatelineFrontier(0);
        var first = CreateSnapshot(
            new DateTimeOffset(2026, 7, 15, 1, 0, 0, TimeSpan.Zero),
            firstFrontier);
        var secondFrontier = CreateDatelineFrontier(-0.5);
        var second = CreateSnapshot(
            first.FrontierTime.AddHours(1),
            secondFrontier);

        layers.AddCalculationSnapshot(ForecastModel.NoaaGfs, first);
        layers.AddCalculationSnapshot(ForecastModel.NoaaGfs, second);

        Assert.Equal(2, layers.GetIsochroneCount(ForecastModel.NoaaGfs));
        Assert.True(layers.HasProvisionalRoute(ForecastModel.NoaaGfs));
        var provisional = Assert.IsType<MemoryLayer>(
            map.Layers.Single(layer => layer.Name == "NOAA GFS provisional route"));
        Assert.Same(second, Assert.Single(provisional.Features).Data);

        var isochrones = Assert.IsType<MemoryLayer>(
            map.Layers.Single(layer => layer.Name == "NOAA GFS isochrones"));
        var geometry = Assert.IsType<GeometryFeature>(isochrones.Features.First()).Geometry;
        var lines = geometry is MultiLineString multi
            ? multi.Geometries.Cast<LineString>()
            : new[] { Assert.IsType<LineString>(geometry) };
        Assert.All(lines, line =>
        {
            for (var index = 1; index < line.Coordinates.Length; index++)
            {
                Assert.True(
                    Math.Abs(line.Coordinates[index].X - line.Coordinates[index - 1].X) <
                    20_100_000);
            }
        });

        layers.ClearCalculationOverlay(ForecastModel.NoaaGfs);

        Assert.Equal(0, layers.GetIsochroneCount(ForecastModel.NoaaGfs));
        Assert.False(layers.HasProvisionalRoute(ForecastModel.NoaaGfs));
    }

    [Fact]
    public void IsochroneLayersUseSharedVisibleRedStyle()
    {
        var map = new Map();
        _ = new RouteMapLayers(map);

        var isochroneLayers = map.Layers
            .Where(layer => layer.Name?.EndsWith(" isochrones", StringComparison.Ordinal) is true)
            .Cast<MemoryLayer>()
            .ToArray();

        Assert.Equal(2, isochroneLayers.Length);
        Assert.Equal(1.0, RouteMapLayers.IsochroneLineWidth);
        Assert.All(isochroneLayers, layer =>
        {
            var style = Assert.IsType<VectorStyle>(layer.Style);
            Assert.NotNull(style.Line);
            Assert.Equal(RouteMapLayers.IsochroneColor, style.Line.Color);
            Assert.Equal(RouteMapLayers.IsochroneLineWidth, style.Line.Width);
            Assert.Equal(RouteMapLayers.IsochroneOpacity, style.Opacity);
            Assert.Equal(PenStrokeCap.Round, style.Line.PenStrokeCap);
        });
    }

    [Fact]
    public void IsochronesRenderOpenDestinationFacingHalfFront()
    {
        var map = new Map();
        var layers = new RouteMapLayers(map);
        var east = new Coordinate(0, 2);
        var frontier = new[]
        {
            new Coordinate(1, -1),
            new Coordinate(-1, 1),
            new Coordinate(0, -2),
            new Coordinate(2, 0),
            east,
            new Coordinate(-2, 0),
            new Coordinate(1, 1),
            new Coordinate(-1, -1)
        };
        var expectedArc = new[]
        {
            new Coordinate(-2, 0),
            new Coordinate(-1, 1),
            east,
            new Coordinate(1, 1),
            new Coordinate(2, 0)
        };
        var snapshot = CreateSnapshot(
            new DateTimeOffset(2026, 7, 15, 1, 0, 0, TimeSpan.Zero),
            frontier,
            east);

        layers.AddCalculationSnapshot(ForecastModel.NoaaGfs, snapshot);

        var isochrones = Assert.IsType<MemoryLayer>(
            map.Layers.Single(layer => layer.Name == "NOAA GFS isochrones"));
        var feature = Assert.IsType<GeometryFeature>(Assert.Single(isochrones.Features));
        var line = Assert.IsType<LineString>(feature.Geometry);
        var expectedPoints = MapProjection.ToContinuousMapPoints(expectedArc);

        Assert.Equal(expectedPoints.Count, line.Coordinates.Length);
        for (var index = 0; index < expectedPoints.Count; index++)
        {
            Assert.Equal(expectedPoints[index].X, line.Coordinates[index].X, 6);
            Assert.Equal(expectedPoints[index].Y, line.Coordinates[index].Y, 6);
        }

        Assert.NotEqual(line.Coordinates[0], line.Coordinates[^1]);
    }

    [Fact]
    public void ContinuousProjectionKeepsDatelinePointsInOneWorldCopy()
    {
        var points = MapProjection.ToContinuousMapPoints(
            new[]
            {
                new Coordinate(10, 179),
                new Coordinate(10, -179)
            });
        var nearWesternCopy = MapProjection.ToContinuousMapPointsNear(
            new[]
            {
                new Coordinate(10, 179),
                new Coordinate(10, -179)
            },
            -MapProjection.WebMercatorWorldWidth / 2);

        Assert.True(Math.Abs(points[1].X - points[0].X) < 500_000);
        Assert.True(Math.Abs(nearWesternCopy[1].X - nearWesternCopy[0].X) < 500_000);
        Assert.True(nearWesternCopy.Average(point => point.X) < 0);
    }

    private static MainViewModel CreateViewModel(bool tilesEnabled) =>
        new(
            null,
            null,
            TimeProvider.System,
            TimeZoneInfo.Utc,
            new OsmTileOptions(Enabled: tilesEnabled));

    private static RouteCalculationSnapshot CreateSnapshot(
        DateTimeOffset frontierTime,
        IEnumerable<Coordinate> frontier,
        Coordinate? optimalPoint = null)
    {
        var frontierPoints = frontier.ToArray();
        var start = new Coordinate(10, 170);
        return new RouteCalculationSnapshot(
            frontierTime,
            frontierPoints,
            new[]
            {
                new RoutePoint(start, frontierTime.AddHours(-1), 90, 6, 15, 180, 0),
                new RoutePoint(
                    optimalPoint ?? frontierPoints[0],
                    frontierTime,
                    90,
                    6,
                    15,
                    180,
                    10)
            },
            new RouteDiagnostics(10, 20, 5, (int)(frontierTime.Hour + 1)));
    }

    private static Coordinate[] CreateDatelineFrontier(double longitudeOffset) =>
    [
        new Coordinate(10, NormalizeLongitude(-179 + longitudeOffset)),
        new Coordinate(11, NormalizeLongitude(-179.3 + longitudeOffset)),
        new Coordinate(11.5, NormalizeLongitude(180 + longitudeOffset)),
        new Coordinate(11, NormalizeLongitude(179.3 + longitudeOffset)),
        new Coordinate(10, NormalizeLongitude(179 + longitudeOffset)),
        new Coordinate(9, NormalizeLongitude(179.3 + longitudeOffset)),
        new Coordinate(8.5, NormalizeLongitude(180 + longitudeOffset)),
        new Coordinate(9, NormalizeLongitude(-179.3 + longitudeOffset))
    ];

    private static double NormalizeLongitude(double longitude) =>
        (longitude + 540) % 360 - 180;
}
