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
using Polygon = NetTopologySuite.Geometries.Polygon;

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
    public void MainWindowLegendDistinguishesReachabilityEnvelopeAndLatestFront()
    {
        var window = new MainWindow
        {
            DataContext = CreateViewModel(tilesEnabled: false)
        };

        try
        {
            window.Show();

            var envelopeSwatch = window.FindControl<Border>("ReachabilityEnvelopeLegendSwatch");
            var frontSwatch = window.FindControl<Border>("DestinationFrontLegendSwatch");
            Assert.NotNull(envelopeSwatch);
            Assert.NotNull(frontSwatch);
            var brush = Assert.IsAssignableFrom<ISolidColorBrush>(frontSwatch.Background);
            Assert.Equal(AvaloniaColor.Parse("#D32F2F"), brush.Color);
            Assert.Equal(0.92, frontSwatch.Opacity);
            Assert.True(envelopeSwatch.Opacity < frontSwatch.Opacity);
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
                "NOAA GFS reachability envelopes",
                "ECMWF IFS reachability envelopes",
                "NOAA GFS destination front",
                "ECMWF IFS destination front",
                "NOAA GFS provisional route",
                "ECMWF IFS provisional route",
                "NOAA GFS routes",
                "ECMWF IFS routes"
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
    public void StreamingLayersAccumulateEnvelopesReplaceCurrentFrontAndProvisionalRoute()
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

        Assert.Equal(2, layers.GetReachabilityEnvelopeCount(ForecastModel.NoaaGfs));
        Assert.True(layers.HasDestinationFront(ForecastModel.NoaaGfs));
        Assert.True(layers.HasProvisionalRoute(ForecastModel.NoaaGfs));
        var provisional = Assert.IsType<MemoryLayer>(
            map.Layers.Single(layer => layer.Name == "NOAA GFS provisional route"));
        Assert.Same(second, Assert.Single(provisional.Features).Data);

        var envelopes = Assert.IsType<MemoryLayer>(
            map.Layers.Single(layer => layer.Name == "NOAA GFS reachability envelopes"));
        var geometry = Assert.IsType<GeometryFeature>(envelopes.Features.First()).Geometry;
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
        var destinationFront = Assert.IsType<MemoryLayer>(
            map.Layers.Single(layer => layer.Name == "NOAA GFS destination front"));
        Assert.Same(second, Assert.Single(destinationFront.Features).Data);

        layers.ClearCalculationOverlay(ForecastModel.NoaaGfs);

        Assert.Equal(0, layers.GetReachabilityEnvelopeCount(ForecastModel.NoaaGfs));
        Assert.False(layers.HasDestinationFront(ForecastModel.NoaaGfs));
        Assert.False(layers.HasProvisionalRoute(ForecastModel.NoaaGfs));
    }

    [Fact]
    public void ReachabilityLayersUseSubtleEnvelopesAndStrongLatestFronts()
    {
        var map = new Map();
        _ = new RouteMapLayers(map);

        var envelopeLayers = map.Layers
            .Where(layer => layer.Name?.EndsWith(" reachability envelopes", StringComparison.Ordinal) is true)
            .Cast<MemoryLayer>()
            .ToArray();
        var frontLayers = map.Layers
            .Where(layer => layer.Name?.EndsWith(" destination front", StringComparison.Ordinal) is true)
            .Cast<MemoryLayer>()
            .ToArray();

        Assert.Equal(2, envelopeLayers.Length);
        Assert.All(envelopeLayers, layer => Assert.Null(layer.Style));
        Assert.Equal(2, frontLayers.Length);
        Assert.Equal(2.0, RouteMapLayers.DestinationFrontLineWidth);
        Assert.All(frontLayers, layer =>
        {
            var style = Assert.IsType<VectorStyle>(layer.Style);
            Assert.NotNull(style.Line);
            Assert.Equal(RouteMapLayers.ReachabilityColor, style.Line.Color);
            Assert.Equal(RouteMapLayers.DestinationFrontLineWidth, style.Line.Width);
            Assert.Equal(RouteMapLayers.DestinationFrontOpacity, style.Opacity);
            Assert.Equal(PenStrokeCap.Round, style.Line.PenStrokeCap);
        });
    }

    [Fact]
    public void IsochronesRenderRouterProvidedDestinationFrontOrder()
    {
        var map = new Map();
        var layers = new RouteMapLayers(map);
        var east = new Coordinate(0, 2);
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
            expectedArc,
            east);

        layers.AddCalculationSnapshot(ForecastModel.NoaaGfs, snapshot);

        var front = Assert.IsType<MemoryLayer>(
            map.Layers.Single(layer => layer.Name == "NOAA GFS destination front"));
        var feature = Assert.IsType<GeometryFeature>(Assert.Single(front.Features));
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
    public void AntimeridianSplitFrontRendersAsSeparateOpenLines()
    {
        var map = new Map();
        var layers = new RouteMapLayers(map);
        var timestamp = new DateTimeOffset(2026, 7, 15, 1, 0, 0, TimeSpan.Zero);
        var west = new[]
        {
            new Coordinate(9, 179),
            new Coordinate(10, 179.8)
        };
        var east = new[]
        {
            new Coordinate(10, -179.8),
            new Coordinate(11, -179)
        };
        var snapshot = new RouteCalculationSnapshot(
            timestamp,
            new[]
            {
                new RouteCalculationEnvelopeSegment(west, closed: false),
                new RouteCalculationEnvelopeSegment(east, closed: false)
            },
            new[]
            {
                new RouteCalculationFrontSegment(west),
                new RouteCalculationFrontSegment(east)
            },
            new[]
            {
                new RoutePoint(new Coordinate(8, 178), timestamp.AddHours(-1), 90, 6, 15, 180, 0),
                new RoutePoint(east[0], timestamp, 90, 6, 15, 180, 10)
            },
            new RouteDiagnostics(10, 20, 5, 1));

        layers.AddCalculationSnapshot(ForecastModel.NoaaGfs, snapshot);

        var front = Assert.IsType<MemoryLayer>(
            map.Layers.Single(layer => layer.Name == "NOAA GFS destination front"));
        var lines = front.Features
            .Cast<GeometryFeature>()
            .Select(feature => Assert.IsType<LineString>(feature.Geometry))
            .ToArray();
        Assert.Equal(2, lines.Length);
        Assert.All(lines, line => Assert.NotEqual(line.Coordinates[0], line.Coordinates[^1]));
        var centers = lines
            .Select(line => line.Coordinates.Average(coordinate => coordinate.X))
            .ToArray();
        Assert.True(Math.Abs(centers[1] - centers[0]) < 500_000);
        var routeEndX = MapProjection.ToContinuousMapPoints(
            snapshot.ProvisionalRoute.Select(point => point.Location))[^1].X;
        Assert.All(centers, center => Assert.True(Math.Abs(center - routeEndX) < 500_000));
    }

    [Fact]
    public void ReachabilityLayersRetainSingletonsWithoutInventingExtent()
    {
        var map = new Map();
        var layers = new RouteMapLayers(map);
        var timestamp = new DateTimeOffset(2026, 7, 15, 1, 0, 0, TimeSpan.Zero);
        var location = new Coordinate(10, 170);
        var point = new RoutePoint(location, timestamp, 90, 6, 15, 180, 0);
        var diagnostics = new RouteDiagnostics(1, 2, 1, 1);
        var snapshot = new RouteCalculationSnapshot(
            timestamp,
            new[] { new RouteCalculationEnvelopeSegment(new[] { location }, closed: false) },
            new[] { new RouteCalculationFrontSegment(new[] { location }) },
            new[] { point },
            diagnostics);
        var request = new RouteRequest(
            "singleton",
            location,
            new Coordinate(11, 171),
            timestamp,
            timestamp.AddHours(1));
        var route = new RouteResult(
            request,
            ForecastModel.NoaaGfs,
            new[] { point },
            diagnostics,
            RouteCompletion.ForecastExhausted);

        layers.AddCalculationSnapshot(ForecastModel.NoaaGfs, snapshot);
        layers.SetRoutes(new[] { route });

        var envelope = Assert.IsType<GeometryFeature>(Assert.Single(Assert.IsType<MemoryLayer>(
            map.Layers.Single(layer => layer.Name == "NOAA GFS reachability envelopes")).Features));
        var envelopeLine = Assert.IsType<LineString>(envelope.Geometry);
        Assert.Equal(envelopeLine.Coordinates[0], envelopeLine.Coordinates[1]);
        var front = Assert.IsType<GeometryFeature>(Assert.Single(Assert.IsType<MemoryLayer>(
            map.Layers.Single(layer => layer.Name == "NOAA GFS destination front")).Features));
        var frontLine = Assert.IsType<LineString>(front.Geometry);
        Assert.Equal(frontLine.Coordinates[0], frontLine.Coordinates[1]);
        Assert.Empty(Assert.IsType<MemoryLayer>(
            map.Layers.Single(layer => layer.Name == "NOAA GFS provisional route")).Features);
        Assert.Empty(Assert.IsType<MemoryLayer>(
            map.Layers.Single(layer => layer.Name == "NOAA GFS routes")).Features);
        Assert.DoesNotContain(map.Layers, layer => layer.Name == "Route endpoints");
        Assert.DoesNotContain(map.Layers, layer => layer.Name == "Timeline route points");
        Assert.DoesNotContain(map.Layers, layer => layer.Name == "Selected route point");
    }

    [Fact]
    public void EnvelopeTopologyRendersClosedOpenAndDisconnectedComponentsWithoutJoining()
    {
        var map = new Map();
        var layers = new RouteMapLayers(map);
        var timestamp = new DateTimeOffset(2026, 7, 15, 1, 0, 0, TimeSpan.Zero);
        var closed = new[]
        {
            new Coordinate(10, 170),
            new Coordinate(11, 171),
            new Coordinate(9, 172)
        };
        var open = new[]
        {
            new Coordinate(8, 169),
            new Coordinate(8.5, 170)
        };
        var snapshot = new RouteCalculationSnapshot(
            timestamp,
            new[]
            {
                new RouteCalculationEnvelopeSegment(closed, closed: true),
                new RouteCalculationEnvelopeSegment(open, closed: false)
            },
            new[] { new RouteCalculationFrontSegment(open) },
            new[]
            {
                new RoutePoint(closed[0], timestamp.AddHours(-1), 90, 6, 15, 180, 0),
                new RoutePoint(open[0], timestamp, 90, 6, 15, 180, 10)
            },
            new RouteDiagnostics(10, 20, 5, 1));

        layers.AddCalculationSnapshot(ForecastModel.NoaaGfs, snapshot);

        var envelopes = Assert.IsType<MemoryLayer>(
            map.Layers.Single(layer => layer.Name == "NOAA GFS reachability envelopes"));
        var geometries = envelopes.Features
            .Cast<GeometryFeature>()
            .Select(feature => feature.Geometry)
            .ToArray();
        Assert.Equal(2, geometries.Length);
        Assert.IsType<Polygon>(geometries[0]);
        Assert.IsType<LineString>(geometries[1]);
        Assert.All(envelopes.Features, feature =>
        {
            var style = Assert.IsType<VectorStyle>(Assert.Single(feature.Styles));
            Assert.Equal(RouteMapLayers.ReachabilityOpacity, style.Opacity);
        });
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
            new[]
            {
                new RouteCalculationEnvelopeSegment(frontierPoints, closed: false)
            },
            new[]
            {
                new RouteCalculationFrontSegment(frontierPoints)
            },
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
