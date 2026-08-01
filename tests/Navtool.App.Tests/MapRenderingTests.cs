using Avalonia.Controls;
using Avalonia.Headless.XUnit;
using Avalonia.Media;
using Mapsui;
using Mapsui.Extensions;
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
    public void MainWindowOpensOnBufferedSalishSeaRegion()
    {
        var viewModel = CreateViewModel(tilesEnabled: false);
        var window = new MainWindow
        {
            DataContext = viewModel
        };

        try
        {
            window.Show();

            var visible = viewModel.Map.Navigator.Viewport.ToExtent();
            Coordinate[] requiredVisibleLocations =
            [
                new(48.1163, -122.7583), // Port Townsend
                new(48.5343, -123.0171), // Friday Harbor
                new(48.5126, -122.6127), // Anacortes
                new(48.9416, -125.5464), // Ucluelet
                new(47.95, -122.7583),   // 10 NM south
                new(49.108, -125.5464),  // 10 NM north
                new(48.9416, -125.8),    // 10 NM west
                new(48.5126, -122.36)    // 10 NM east
            ];
            Assert.All(requiredVisibleLocations, location =>
            {
                var point = MapProjection.ToMapPoint(location);
                Assert.InRange(point.X, visible.Left, visible.Right);
                Assert.InRange(point.Y, visible.Bottom, visible.Top);
            });
            Assert.True(visible.Width < 500_000);
            Assert.True(visible.Height < 400_000);
        }
        finally
        {
            window.Close();
        }
    }

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
    public void MainWindowLegendDistinguishesHistoricalAndLatestFronts()
    {
        var window = new MainWindow
        {
            DataContext = CreateViewModel(tilesEnabled: false)
        };

        try
        {
            window.Show();

            var historicalSwatch = window.FindControl<Border>("HistoricalIsochroneLegendSwatch");
            var frontSwatch = window.FindControl<Border>("DestinationFrontLegendSwatch");
            Assert.NotNull(historicalSwatch);
            Assert.NotNull(frontSwatch);
            var brush = Assert.IsAssignableFrom<ISolidColorBrush>(frontSwatch.Background);
            Assert.Equal(AvaloniaColor.Parse("#D32F2F"), brush.Color);
            Assert.Equal(0.92, frontSwatch.Opacity);
            Assert.True(historicalSwatch.Opacity < frontSwatch.Opacity);
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
                "Waypoint guide",
                "NOAA GFS isochrone fronts",
                "ECMWF IFS isochrone fronts",
                "NOAA GFS latest isochrone front",
                "ECMWF IFS latest isochrone front",
                "NOAA GFS provisional route",
                "ECMWF IFS provisional route",
                "NOAA GFS routes",
                "ECMWF IFS routes",
                "Waypoint markers"
            ],
            layers.Skip(1).Select(layer => layer.Name));
    }

    [Fact]
    public void Waypoint_markers_are_numbered_and_guide_is_antimeridian_safe()
    {
        var map = new Map();
        var layers = new RouteMapLayers(map);
        layers.SetWaypoints(
        [
            new WaypointMapMarker(1, "Start", new Coordinate(10, 179)),
            new WaypointMapMarker(2, "Stop", new Coordinate(11, -179.5)),
            new WaypointMapMarker(3, "Finish", new Coordinate(12, -178))
        ]);

        Assert.Equal(3, layers.WaypointMarkerCount);
        Assert.Equal(1, layers.WaypointGuideSegmentCount);
        var markerLayer = Assert.IsType<MemoryLayer>(
            map.Layers.Single(layer => layer.Name == "Waypoint markers"));
        Assert.Equal(
            [1, 2, 3],
            markerLayer.Features.Select(feature =>
                Assert.IsType<WaypointMapMarker>(feature.Data).Number));
        Assert.Equal(
            ["1", "2", "3"],
            markerLayer.Features.Select(feature =>
                Assert.IsType<LabelStyle>(Assert.Single(feature.Styles)).GetLabelText(feature)));

        var guide = Assert.IsType<MemoryLayer>(
            map.Layers.Single(layer => layer.Name == "Waypoint guide"));
        var line = Assert.IsType<LineString>(
            Assert.IsType<GeometryFeature>(Assert.Single(guide.Features)).Geometry);
        for (var index = 1; index < line.Coordinates.Length; index++)
        {
            Assert.True(Math.Abs(line.Coordinates[index].X - line.Coordinates[index - 1].X) < 500_000);
        }
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
    public void StreamingLayersAccumulateFrontsAndReplaceLatestFrontAndProvisionalRoute()
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

        Assert.Equal(2, layers.GetIsochroneFrontCount(ForecastModel.NoaaGfs));
        Assert.True(layers.HasLatestIsochroneFront(ForecastModel.NoaaGfs));
        Assert.True(layers.HasProvisionalRoute(ForecastModel.NoaaGfs));
        var provisional = Assert.IsType<MemoryLayer>(
            map.Layers.Single(layer => layer.Name == "NOAA GFS provisional route"));
        Assert.Same(second, Assert.Single(provisional.Features).Data);

        var historicalFronts = Assert.IsType<MemoryLayer>(
            map.Layers.Single(layer => layer.Name == "NOAA GFS isochrone fronts"));
        var geometry = Assert.IsType<GeometryFeature>(historicalFronts.Features.First()).Geometry;
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
            map.Layers.Single(layer => layer.Name == "NOAA GFS latest isochrone front"));
        Assert.Same(second, Assert.Single(destinationFront.Features).Data);

        layers.ClearCalculationOverlay(ForecastModel.NoaaGfs);

        Assert.Equal(0, layers.GetIsochroneFrontCount(ForecastModel.NoaaGfs));
        Assert.False(layers.HasLatestIsochroneFront(ForecastModel.NoaaGfs));
        Assert.False(layers.HasProvisionalRoute(ForecastModel.NoaaGfs));
    }

    [Fact]
    public void IsochroneLayersUseSubtleHistoricalAndStrongLatestFronts()
    {
        var map = new Map();
        _ = new RouteMapLayers(map);

        var historicalLayers = map.Layers
            .Where(layer => layer.Name?.EndsWith(" isochrone fronts", StringComparison.Ordinal) is true)
            .Cast<MemoryLayer>()
            .ToArray();
        var frontLayers = map.Layers
            .Where(layer => layer.Name?.EndsWith(" latest isochrone front", StringComparison.Ordinal) is true)
            .Cast<MemoryLayer>()
            .ToArray();

        Assert.Equal(2, historicalLayers.Length);
        Assert.All(historicalLayers, layer =>
        {
            var style = Assert.IsType<VectorStyle>(layer.Style);
            Assert.NotNull(style.Line);
            Assert.Equal(RouteMapLayers.HistoricalFrontLineWidth, style.Line.Width);
            Assert.Equal(RouteMapLayers.HistoricalFrontOpacity, style.Opacity);
            Assert.Null(style.Fill);
        });
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
    public void IsochronesSmoothRouterProvidedFrontWithoutClosingOrOvershooting()
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
            map.Layers.Single(layer => layer.Name == "NOAA GFS latest isochrone front"));
        var feature = Assert.IsType<GeometryFeature>(Assert.Single(front.Features));
        var line = Assert.IsType<LineString>(feature.Geometry);
        var expectedPoints = MapProjection.ToContinuousMapPoints(expectedArc);

        Assert.True(line.Coordinates.Length > expectedPoints.Count);
        Assert.Equal(expectedPoints[0].X, line.Coordinates[0].X, 6);
        Assert.Equal(expectedPoints[0].Y, line.Coordinates[0].Y, 6);
        Assert.Equal(expectedPoints[^1].X, line.Coordinates[^1].X, 6);
        Assert.Equal(expectedPoints[^1].Y, line.Coordinates[^1].Y, 6);
        var minimumX = expectedPoints.Min(expected => expected.X);
        var maximumX = expectedPoints.Max(expected => expected.X);
        var minimumY = expectedPoints.Min(expected => expected.Y);
        var maximumY = expectedPoints.Max(expected => expected.Y);
        Assert.All(line.Coordinates, point =>
        {
            Assert.InRange(point.X, minimumX, maximumX);
            Assert.InRange(point.Y, minimumY, maximumY);
        });
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
            map.Layers.Single(layer => layer.Name == "NOAA GFS latest isochrone front"));
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
    public void IsochroneLayersOmitSingletonsInsteadOfDrawingZeroLengthLines()
    {
        var map = new Map();
        var layers = new RouteMapLayers(map);
        var timestamp = new DateTimeOffset(2026, 7, 15, 1, 0, 0, TimeSpan.Zero);
        var location = new Coordinate(10, 170);
        var point = new RoutePoint(location, timestamp, 90, 6, 15, 180, 0);
        var diagnostics = new RouteDiagnostics(1, 2, 1, 1);
        var snapshot = new RouteCalculationSnapshot(
            timestamp,
            new[] { new RouteCalculationEnvelopeSegment(new[] { location }, closed: true) },
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

        Assert.Equal(0, layers.GetIsochroneFrontCount(ForecastModel.NoaaGfs));
        Assert.False(layers.HasLatestIsochroneFront(ForecastModel.NoaaGfs));
        Assert.Empty(Assert.IsType<MemoryLayer>(
            map.Layers.Single(layer => layer.Name == "NOAA GFS isochrone fronts")).Features);
        Assert.Empty(Assert.IsType<MemoryLayer>(
            map.Layers.Single(layer => layer.Name == "NOAA GFS latest isochrone front")).Features);
        Assert.Empty(Assert.IsType<MemoryLayer>(
            map.Layers.Single(layer => layer.Name == "NOAA GFS provisional route")).Features);
        Assert.Empty(Assert.IsType<MemoryLayer>(
            map.Layers.Single(layer => layer.Name == "NOAA GFS routes")).Features);
        Assert.DoesNotContain(map.Layers, layer => layer.Name == "Route endpoints");
        Assert.DoesNotContain(map.Layers, layer => layer.Name == "Timeline route points");
        Assert.DoesNotContain(map.Layers, layer => layer.Name == "Selected route point");
    }

    [Fact]
    public void HistoricalIsochronesUseOpenFrontsInsteadOfFilledEnvelopeContours()
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

        var historicalFronts = Assert.IsType<MemoryLayer>(
            map.Layers.Single(layer => layer.Name == "NOAA GFS isochrone fronts"));
        var feature = Assert.IsType<GeometryFeature>(Assert.Single(historicalFronts.Features));
        var line = Assert.IsType<LineString>(feature.Geometry);
        var expected = MapProjection.ToContinuousMapPointsNear(
            open,
            MapProjection.ToContinuousMapPoints(
                snapshot.ProvisionalRoute.Select(point => point.Location))[^1].X);

        Assert.Equal(2, line.Coordinates.Length);
        Assert.Equal(expected[0].X, line.Coordinates[0].X, 6);
        Assert.Equal(expected[1].X, line.Coordinates[1].X, 6);
        Assert.NotEqual(line.Coordinates[0], line.Coordinates[^1]);
        Assert.Same(snapshot, feature.Data);
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
