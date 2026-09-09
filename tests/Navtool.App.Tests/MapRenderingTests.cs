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
using BruTile.Web;
using LineString = NetTopologySuite.Geometries.LineString;
using MultiLineString = NetTopologySuite.Geometries.MultiLineString;
using Point = NetTopologySuite.Geometries.Point;

namespace Navtool.App.Tests;

public sealed class MapRenderingTests
{
    [Fact]
    public void Interrupted_paths_already_visible_with_margin_do_not_change_the_viewport()
    {
        var layers = CreateSizedMapLayers(new Coordinate(10, 170));
        var before = layers.Map.Navigator.Viewport;
        layers.SetInterruptedRoutes([(ForecastModel.NoaaGfs, CreateInterruptedSnapshot(
            new Coordinate(10, 170), new Coordinate(11, 171)))]);

        Assert.Equal(before, layers.Map.Navigator.Viewport);
        Assert.False(layers.KeepInterruptedRoutesVisible());
        Assert.Equal(before, layers.Map.Navigator.Viewport);
        Assert.True(layers.HasInterruptedRoutes);
        Assert.Empty(layers.Routes);
        Assert.Empty(layers.RouteLegs);
    }

    [Fact]
    public void Offscreen_interrupted_paths_fit_without_including_accepted_routes()
    {
        var layers = CreateSizedMapLayers(new Coordinate(0, 0));
        var withoutAccepted = CreateSizedMapLayers(new Coordinate(0, 0));
        var accepted = CreateVisualizationLeg(
            ForecastModel.EcmwfIfs, 0, new Coordinate(-40, -80), new Coordinate(-39, -79));
        layers.SetRouteLegs([accepted], accepted.Key);
        var snapshot = CreateInterruptedSnapshot(new Coordinate(10, 170), new Coordinate(11, 171));
        layers.SetInterruptedRoutes([(ForecastModel.NoaaGfs, snapshot)]);
        withoutAccepted.SetInterruptedRoutes([(ForecastModel.NoaaGfs, snapshot)]);
        var before = layers.Map.Navigator.Viewport;

        Assert.True(layers.KeepInterruptedRoutesVisible());
        Assert.True(withoutAccepted.KeepInterruptedRoutesVisible());

        Assert.NotEqual(before, layers.Map.Navigator.Viewport);
        Assert.Equal(withoutAccepted.Map.Navigator.Viewport, layers.Map.Navigator.Viewport);
        AssertInterruptedGeometryVisible(layers);
        Assert.True(layers.Map.Navigator.Viewport.ToExtent().Width < 500_000);
        Assert.Same(accepted.Route, Assert.Single(layers.Routes));
        Assert.Equal(accepted.Key, layers.SelectedRouteKey);
        var fitted = layers.Map.Navigator.Viewport;
        Assert.False(layers.KeepInterruptedRoutesVisible());
        Assert.Equal(fitted, layers.Map.Navigator.Viewport);
    }

    [Fact]
    public void Interrupted_path_near_viewport_edge_is_fitted_with_padding()
    {
        var layers = CreateSizedMapLayers(new Coordinate(0, 0));
        layers.SetInterruptedRoutes([(ForecastModel.NoaaGfs, CreateInterruptedSnapshot(
            new Coordinate(0, 0), new Coordinate(0, 4.4)))]);

        Assert.True(layers.KeepInterruptedRoutesVisible());
        AssertInterruptedGeometryVisible(layers);
        Assert.False(layers.KeepInterruptedRoutesVisible());
    }

    [Fact]
    public void Interrupted_fit_preserves_rotation_and_keeps_all_geometry_inside_screen_margin()
    {
        var layers = CreateSizedMapLayers(new Coordinate(0, 0));
        layers.Map.Navigator.RotateTo(45);
        layers.SetInterruptedRoutes([(ForecastModel.NoaaGfs, CreateInterruptedSnapshot(
            new Coordinate(20, 20), new Coordinate(21, 22)))]);
        var rotation = layers.Map.Navigator.Viewport.Rotation;

        Assert.True(layers.KeepInterruptedRoutesVisible());
        Assert.Equal(rotation, layers.Map.Navigator.Viewport.Rotation);
        AssertInterruptedGeometryVisible(layers);
        var fitted = layers.Map.Navigator.Viewport;
        Assert.False(layers.KeepInterruptedRoutesVisible());
        Assert.Equal(fitted, layers.Map.Navigator.Viewport);
    }

    [Fact]
    public void Interrupted_path_under_banner_fits_below_it_even_when_endpoints_are_uncovered()
    {
        var layers = CreateSizedMapLayers(new Coordinate(0, 0));
        layers.SetInterruptedRoutes([(ForecastModel.NoaaGfs, CreateInterruptedSnapshot(
            new Coordinate(2.7, -3.6), new Coordinate(2.7, 3.6)))]);

        Assert.True(layers.KeepInterruptedRoutesVisible());
        AssertInterruptedGeometryVisible(layers);
        var viewport = layers.Map.Navigator.Viewport;
        Assert.All(InterruptedFeatures(layers).SelectMany(feature => feature.Geometry!.Coordinates), coordinate =>
            Assert.True(viewport.WorldToScreen(new MPoint(coordinate.X, coordinate.Y)).Y >= 222));
        Assert.False(layers.KeepInterruptedRoutesVisible());
    }

    [Fact]
    public void Visible_interrupted_paths_beside_banner_preserve_viewport()
    {
        var layers = CreateSizedMapLayers(new Coordinate(0, 0));
        layers.SetInterruptedRoutes([
            (ForecastModel.NoaaGfs, CreateInterruptedSnapshot(
                new Coordinate(2.7, -3.6), new Coordinate(2.7, -3.4))),
            (ForecastModel.EcmwfIfs, CreateInterruptedSnapshot(
                new Coordinate(2.7, 3.4), new Coordinate(2.7, 3.6)))
        ]);
        var before = layers.Map.Navigator.Viewport;

        Assert.False(layers.KeepInterruptedRoutesVisible());
        Assert.Equal(before, layers.Map.Navigator.Viewport);
        AssertInterruptedGeometryVisible(layers);
    }

    [Theory]
    [InlineData(-1)]
    [InlineData(0)]
    [InlineData(1)]
    public void Interrupted_dateline_paths_use_the_nearest_viewport_world_copy(int worldCopy)
    {
        var layers = CreateSizedMapLayers(new Coordinate(10, 180));
        var center = MapProjection.ToMapPoint(new Coordinate(10, 180));
        center.X += worldCopy * MapProjection.WebMercatorWorldWidth;
        layers.Map.Navigator.CenterOnAndZoomTo(center, 1_000);
        var before = layers.Map.Navigator.Viewport;
        layers.SetInterruptedRoutes([
            (ForecastModel.NoaaGfs, CreateInterruptedSnapshot(
                new Coordinate(10, 179), new Coordinate(10, -179))),
            (ForecastModel.EcmwfIfs, CreateInterruptedSnapshot(
                new Coordinate(11, -179), new Coordinate(11, 179)))
        ]);

        Assert.False(layers.KeepInterruptedRoutesVisible());
        Assert.Equal(before, layers.Map.Navigator.Viewport);
        AssertInterruptedGeometryVisible(layers);
        var lines = InterruptedFeatures(layers).Select(feature => feature.Geometry).OfType<LineString>().ToArray();
        Assert.Equal(2, lines.Length);
        Assert.All(lines, line =>
        {
            Assert.InRange(line.EnvelopeInternal.Width, 200_000, 250_000);
            Assert.InRange(Math.Abs(line.Centroid.X - center.X), 0, 1);
        });
    }

    [Fact]
    public void Interrupted_dateline_fit_stays_compact_and_reprojects_after_accepted_fit()
    {
        var layers = CreateSizedMapLayers(new Coordinate(10, -170));
        var accepted = CreateVisualizationLeg(
            ForecastModel.NoaaGfs, 0, new Coordinate(10, 179), new Coordinate(10, -179));
        layers.SetRouteLegs([accepted]);
        layers.SetInterruptedRoutes([(ForecastModel.EcmwfIfs, CreateInterruptedSnapshot(
            new Coordinate(11, 179), new Coordinate(11, -179)))]);

        Assert.True(layers.KeepInterruptedRoutesVisible());
        AssertInterruptedGeometryVisible(layers);
        Assert.True(layers.Map.Navigator.Viewport.CenterX < 0);
        Assert.True(layers.Map.Navigator.Viewport.ToExtent().Width < 500_000);

        layers.FitRoutes();
        Assert.True(layers.Map.Navigator.Viewport.CenterX > 0);
        layers.KeepInterruptedRoutesVisible();

        AssertInterruptedGeometryVisible(layers);
        Assert.True(layers.Map.Navigator.Viewport.CenterX > 0);
        Assert.True(layers.Map.Navigator.Viewport.ToExtent().Width < 500_000);
    }

    [Fact]
    public void Accepted_route_and_leg_fits_ignore_interrupted_paths()
    {
        var layers = CreateSizedMapLayers(new Coordinate(0, 0));
        var acceptedOnly = CreateSizedMapLayers(new Coordinate(0, 0));
        var leg = CreateVisualizationLeg(
            ForecastModel.NoaaGfs, 0, new Coordinate(0, 0), new Coordinate(1, 1));
        layers.SetRouteLegs([leg]);
        acceptedOnly.SetRouteLegs([leg]);
        layers.SetInterruptedRoutes([(ForecastModel.EcmwfIfs, CreateInterruptedSnapshot(
            new Coordinate(10, 170), new Coordinate(11, 171)))]);

        layers.FitRoutes();
        acceptedOnly.FitRoutes();
        Assert.Equal(acceptedOnly.Map.Navigator.Viewport, layers.Map.Navigator.Viewport);
        layers.FitRouteLeg(leg.Key);
        acceptedOnly.FitRouteLeg(leg.Key);
        Assert.Equal(acceptedOnly.Map.Navigator.Viewport, layers.Map.Navigator.Viewport);
        Assert.True(layers.HasInterruptedRoutes);
    }

    [Fact]
    public void Interrupted_paths_have_dashed_model_lines_and_distinct_endpoints_without_snapshots()
    {
        var layers = CreateSizedMapLayers(new Coordinate(10, 170));
        var snapshot = CreateInterruptedSnapshot(new Coordinate(10, 170), new Coordinate(11, 171));
        layers.SetInterruptedRoutes([
            (ForecastModel.NoaaGfs, snapshot),
            (ForecastModel.EcmwfIfs, snapshot)
        ]);

        var features = InterruptedFeatures(layers);
        Assert.Equal(4, features.Length);
        foreach (var model in new[] { ForecastModel.NoaaGfs, ForecastModel.EcmwfIfs })
        {
            var modelFeatures = features.Where(feature => Equals(feature.Data, model)).ToArray();
            var line = Assert.Single(modelFeatures, feature => feature.Geometry is LineString);
            var endpoint = Assert.Single(modelFeatures, feature => feature.Geometry is Point);
            var lineStyle = Assert.IsType<VectorStyle>(Assert.Single(line.Styles));
            Assert.Equal(PenStyle.Dash, lineStyle.Line!.PenStyle);
            Assert.Equal(model == ForecastModel.NoaaGfs ? RouteMapLayers.NoaaColor : RouteMapLayers.EcmwfColor,
                lineStyle.Line.Color);
            var label = Assert.IsType<LabelStyle>(Assert.Single(endpoint.Styles));
            Assert.Equal(lineStyle.Line.Color, label.ForeColor);
            Assert.Contains("interrupted", label.GetLabelText(endpoint));
            Assert.Equal(line.Geometry!.Coordinates[^1], endpoint.Geometry!.Coordinate);
            Assert.All(modelFeatures, feature => Assert.IsType<ForecastModel>(feature.Data));
        }
        Assert.Empty(layers.Routes);
    }

    [Fact]
    public void Interrupted_and_live_overlays_clear_independently_and_do_not_clear_accepted_routes()
    {
        var layers = CreateSizedMapLayers(new Coordinate(10, 170));
        var snapshot = CreateInterruptedSnapshot(new Coordinate(10, 170), new Coordinate(11, 171));
        var accepted = CreateVisualizationLeg(
            ForecastModel.EcmwfIfs, 0, new Coordinate(10, 170), new Coordinate(11, 171));
        layers.SetRouteLegs([accepted]);
        layers.AddCalculationSnapshot(ForecastModel.NoaaGfs, snapshot);
        layers.AddCalculationSnapshot(ForecastModel.EcmwfIfs, snapshot);

        layers.SetInterruptedRoutes([(ForecastModel.NoaaGfs, snapshot)]);

        Assert.False(layers.HasSearchPoint(ForecastModel.NoaaGfs));
        Assert.False(layers.HasProvisionalRoute(ForecastModel.NoaaGfs));
        Assert.False(layers.HasLatestIsochroneFront(ForecastModel.NoaaGfs));
        Assert.Equal(0, layers.GetIsochroneFrontCount(ForecastModel.NoaaGfs));
        Assert.True(layers.HasSearchPoint(ForecastModel.EcmwfIfs));
        layers.ClearCalculationOverlays();
        Assert.True(layers.HasInterruptedRoutes);
        Assert.Equal(2, InterruptedFeatures(layers).Length);
        Assert.False(layers.HasProvisionalRoute(ForecastModel.EcmwfIfs));

        layers.AddCalculationSnapshot(ForecastModel.EcmwfIfs, snapshot);
        layers.ClearInterruptedRoutes();

        Assert.False(layers.HasInterruptedRoutes);
        Assert.Empty(InterruptedFeatures(layers));
        Assert.True(layers.HasProvisionalRoute(ForecastModel.EcmwfIfs));
        Assert.True(layers.HasLatestIsochroneFront(ForecastModel.EcmwfIfs));
        Assert.True(layers.HasSearchPoint(ForecastModel.EcmwfIfs));
        Assert.Same(accepted.Route, Assert.Single(layers.Routes));
        var before = layers.Map.Navigator.Viewport;
        Assert.False(layers.KeepInterruptedRoutesVisible());
        Assert.Equal(before, layers.Map.Navigator.Viewport);
    }

    [Fact]
    public void Interrupted_single_point_is_an_endpoint_and_set_replaces_previous_paths()
    {
        var layers = CreateSizedMapLayers(new Coordinate(0, 0));
        layers.SetInterruptedRoutes([(ForecastModel.NoaaGfs, CreateInterruptedSnapshot(
            new Coordinate(10, 170), new Coordinate(11, 171)))]);
        layers.SetInterruptedRoutes([(ForecastModel.EcmwfIfs, CreateInterruptedSnapshot(new Coordinate(0, 1)))]);

        var endpoint = Assert.Single(InterruptedFeatures(layers));
        Assert.IsType<Point>(endpoint.Geometry);
        Assert.Equal(ForecastModel.EcmwfIfs, endpoint.Data);
        Assert.True(layers.HasInterruptedRoutes);
        Assert.False(layers.KeepInterruptedRoutesVisible());
        layers.SetInterruptedRoutes([]);
        Assert.False(layers.HasInterruptedRoutes);
        Assert.Empty(InterruptedFeatures(layers));
    }

    private static RouteMapLayers CreateSizedMapLayers(Coordinate center)
    {
        var layers = new RouteMapLayers(new Map());
        layers.Map.Navigator.SetSize(1_000, 800);
        layers.Map.Navigator.CenterOnAndZoomTo(MapProjection.ToMapPoint(center), 1_000);
        return layers;
    }

    private static GeometryFeature[] InterruptedFeatures(RouteMapLayers layers) =>
        layers.Map.Layers.Where(layer => layer.Name is
                "NOAA GFS interrupted route" or "ECMWF IFS interrupted route" or "Interrupted route endpoints")
            .Cast<MemoryLayer>().SelectMany(layer => layer.Features).Cast<GeometryFeature>().ToArray();

    private static void AssertInterruptedGeometryVisible(RouteMapLayers layers)
    {
        var viewport = layers.Map.Navigator.Viewport;
        Assert.All(InterruptedFeatures(layers).SelectMany(feature => feature.Geometry!.Coordinates), coordinate =>
        {
            var screen = viewport.WorldToScreen(new MPoint(coordinate.X, coordinate.Y));
            Assert.InRange(screen.X, 24, viewport.Width - 24);
            Assert.InRange(screen.Y, 24, viewport.Height - 24);
        });
    }

    private static RouteCalculationSnapshot CreateInterruptedSnapshot(params Coordinate[] path)
    {
        var start = new DateTimeOffset(2026, 7, 15, 0, 0, 0, TimeSpan.Zero);
        return new RouteCalculationSnapshot(
            start.AddHours(path.Length - 1),
            RouteSolver.IsochroneBeam,
            [new RouteCalculationEnvelopeSegment(path, closed: false)],
            [new RouteCalculationFrontSegment(path)],
            [path[^1]],
            path.Select((location, index) => new RoutePoint(location, start.AddHours(index), 90, 6, 15, 180, index)),
            new RouteDiagnostics(10, 20, 5, 1),
            null);
    }

    [Fact]
    public void Progress_history_is_bounded_and_does_not_retain_route_snapshots()
    {
        var map = new Map();
        var layers = new RouteMapLayers(map);
        var time = DateTimeOffset.UtcNow;
        for (var index = 0; index < 500; index++)
            layers.AddCalculationSnapshot(ForecastModel.NoaaGfs,
                CreateSnapshot(time.AddMinutes(index), [new Coordinate(10, 171), new Coordinate(11, 172)]));
        Assert.Equal(RouteMapLayers.MaximumHistoricalFrontFeatures,
            layers.GetIsochroneFrontCount(ForecastModel.NoaaGfs));
        var history = Assert.IsType<MemoryLayer>(map.Layers.Single(layer => layer.Name == "NOAA GFS isochrone fronts"));
        Assert.All(history.Features, feature => Assert.IsType<DateTimeOffset>(feature.Data));
    }

    [Fact]
    public void Nominal_arrival_area_is_separate_from_actual_endpoint_and_never_connects_to_it()
    {
        var layers = new RouteMapLayers(new Map());
        var leg = CreateVisualizationLeg(ForecastModel.NoaaGfs, 0, new Coordinate(10, 179), new Coordinate(10, -179));
        layers.SetRouteLegs([leg]);
        layers.SetArrivalAreas([(leg.Route!.Request.Destination, 1d)]);
        var endpointLayer = Assert.IsType<MemoryLayer>(layers.Map.Layers.Single(layer => layer.Name == "Actual model endpoints"));
        var point = Assert.IsType<Point>(Assert.IsType<GeometryFeature>(Assert.Single(endpointLayer.Features)).Geometry);
        var expected = MapProjection.ToContinuousMapPoints(leg.Route!.Points.Select(p => p.Location))[^1];
        Assert.Equal(expected.X, point.X);
        var arrivalLayer = Assert.IsType<MemoryLayer>(layers.Map.Layers.Single(layer => layer.Name == "Nominal arrival areas"));
        var circle = Assert.IsType<LineString>(Assert.IsType<GeometryFeature>(Assert.Single(arrivalLayer.Features)).Geometry);
        Assert.Equal(73, circle.NumPoints);
        Assert.True(circle.EnvelopeInternal.Width < 10000);
        Assert.InRange(Math.Abs(circle.Centroid.X - point.X), 0, 10000);
        Assert.Equal(leg.Route.Points, Assert.Single(layers.Routes).Points);
    }

    [Fact]
    public void One_point_arrival_is_an_actual_point_not_a_connector_to_the_nominal_waypoint()
    {
        var departure = DateTimeOffset.UtcNow;
        var request = new RouteRequest("already-in-area", new Coordinate(0, 0),
            new Coordinate(0, 0.01), departure, departure.AddHours(1));
        var route = new RouteResult(request, ForecastModel.NoaaGfs,
            [new RoutePoint(request.Origin, departure, 90, 0, 12, 180, 0)],
            new RouteDiagnostics(0, 0, 0, 0));
        var layers = new RouteMapLayers(new Map());
        layers.SetRoutes([route]);
        var routeLayer = Assert.IsType<MemoryLayer>(layers.Map.Layers.Single(layer => layer.Name == "NOAA GFS routes"));
        var feature = Assert.IsType<GeometryFeature>(Assert.Single(routeLayer.Features));
        var point = Assert.IsType<Point>(feature.Geometry);
        Assert.Equal(0, point.X);
        Assert.Single(Assert.Single(layers.Routes).Points);
        var endpointLayer = Assert.IsType<MemoryLayer>(layers.Map.Layers.Single(layer => layer.Name == "Actual model endpoints"));
        var endpoint = Assert.IsType<GeometryFeature>(Assert.Single(endpointLayer.Features));
        Assert.Equal("NOAA arrival", Assert.IsType<LabelStyle>(Assert.Single(endpoint.Styles)).GetLabelText(endpoint));
    }

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
            "https://www.openstreetmap.org/copyright",
            baseLayer.Attribution.Url);
        Assert.True(baseLayer.Attribution.Enabled);
        Assert.Contains(
            baseLayer.Attribution,
            viewModel.Map.GetWidgetsOfMapAndLayers());
        Assert.Equal(
            [
                "Wind speed",
                "Wind direction",
                "Waypoint guide",
                "NOAA GFS isochrone fronts",
                "ECMWF IFS isochrone fronts",
                "NOAA GFS latest isochrone front",
                "ECMWF IFS latest isochrone front",
                "NOAA GFS lattice search",
                "ECMWF IFS lattice search",
                "NOAA GFS provisional route",
                "ECMWF IFS provisional route",
                "NOAA GFS interrupted route",
                "ECMWF IFS interrupted route",
                "Interrupted route endpoints",
                "NOAA GFS routes",
                "ECMWF IFS routes",
                "Nominal arrival areas",
                "Actual model endpoints",
                "Waypoint markers",
                "Current position"
            ],
            layers.Skip(1).Select(layer => layer.Name));
    }

    [Fact]
    public void MapCompositionUsesConfiguredPersistentCacheAndUserAgent()
    {
        var cacheDirectory = Path.Combine(
            Path.GetTempPath(),
            $"navtool-map-cache-{Guid.NewGuid():N}");
        var options = new OsmTileOptions(
            UserAgent: "Navtool.Tests/1.0 (+https://github.com/frye/navtool)",
            CacheDirectory: cacheDirectory);

        try
        {
            var viewModel = new MainViewModel(
                null,
                null,
                TimeProvider.System,
                TimeZoneInfo.Utc,
                options);
            var layer = Assert.IsType<TileLayer>(viewModel.Map.Layers.First());
            var source = Assert.IsType<HttpTileSource>(layer.TileSource);
            Assert.IsType<BruTile.Cache.FileCache>(source.PersistentCache);

            using var request = new HttpRequestMessage();
            source.ConfigureHttpRequestMessage!(request);
            Assert.Equal(options.UserAgent, request.Headers.UserAgent.ToString());
        }
        finally
        {
            if (Directory.Exists(cacheDirectory))
            {
                Directory.Delete(cacheDirectory, recursive: true);
            }
        }
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
    public void Selected_waypoint_marker_is_emphasized_and_carries_accessible_details()
    {
        var map = new Map();
        var layers = new RouteMapLayers(map);
        layers.SetWaypoints(
        [
            new WaypointMapMarker(
                1,
                "Start",
                new Coordinate(10, 20),
                new RouteWaypointId(),
                IsSelected: false),
            new WaypointMapMarker(
                2,
                "Lunch",
                new Coordinate(11, 21),
                new RouteWaypointId(),
                IsSelected: true)
        ]);

        var markerLayer = Assert.IsType<MemoryLayer>(
            map.Layers.Single(layer => layer.Name == "Waypoint markers"));
        var markers = markerLayer.Features.ToArray();
        var normalStyle = Assert.IsType<LabelStyle>(Assert.Single(markers[0].Styles));
        var selectedStyle = Assert.IsType<LabelStyle>(Assert.Single(markers[1].Styles));
        var selected = Assert.IsType<WaypointMapMarker>(markers[1].Data);

        Assert.True(selectedStyle.BorderThickness > normalStyle.BorderThickness);
        Assert.NotEqual(selectedStyle.BorderColor, normalStyle.BorderColor);
        Assert.Contains("Lunch", selected.AccessibleName);
        Assert.Contains("11.000 degrees north", selected.AccessibleName);
        Assert.Contains("21.000 degrees east", selected.AccessibleName);
    }

    [Fact]
    public void Current_position_marker_is_distinct_from_waypoint_markers_and_clears_on_null()
    {
        var map = new Map();
        var layers = new RouteMapLayers(map);
        layers.SetWaypoints(
        [
            new WaypointMapMarker(1, "Start", new Coordinate(10, 20)),
            new WaypointMapMarker(2, "Finish", new Coordinate(11, 21))
        ]);

        Assert.Equal(0, layers.CurrentPositionMarkerCount);

        var position = new Coordinate(10.5, 20.5);
        layers.SetCurrentPosition(position);

        Assert.Equal(1, layers.CurrentPositionMarkerCount);
        // Waypoint markers are unaffected: a current-position marker is a distinct session
        // marker, not an itinerary waypoint.
        Assert.Equal(2, layers.WaypointMarkerCount);
        var markerLayer = Assert.IsType<MemoryLayer>(
            map.Layers.Single(layer => layer.Name == "Current position"));
        var feature = Assert.Single(markerLayer.Features);
        var point = Assert.IsType<Point>(Assert.IsType<GeometryFeature>(feature).Geometry);
        var expected = MapProjection.ToMapPoint(position);
        Assert.Equal(expected.X, point.X, 6);
        Assert.Equal(expected.Y, point.Y, 6);
        var label = Assert.IsType<LabelStyle>(Assert.Single(feature.Styles));
        Assert.Equal("\u2693", label.GetLabelText(feature));

        layers.SetCurrentPosition(null);

        Assert.Equal(0, layers.CurrentPositionMarkerCount);
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
    public void LatticeStreamingRendersSearchPointAndRouteWithoutBeamGeometry()
    {
        var map = new Map();
        var layers = new RouteMapLayers(map);
        var timestamp = new DateTimeOffset(2026, 7, 15, 2, 0, 0, TimeSpan.Zero);
        var searchPoint = new Coordinate(10.5, 171.5);
        var snapshot = new RouteCalculationSnapshot(
            timestamp,
            RouteSolver.TimeDependentLattice,
            Array.Empty<RouteCalculationEnvelopeSegment>(),
            Array.Empty<RouteCalculationFrontSegment>(),
            new[] { searchPoint },
            new[]
            {
                new RoutePoint(new Coordinate(10, 170), timestamp.AddHours(-1), 90, 6, 15, 180, 0),
                new RoutePoint(searchPoint, timestamp, 90, 6, 15, 180, 10)
            },
            new RouteDiagnostics(10, 20, 5, 1),
            new RouteLatticeSearchProgress(12, 7, 30, 1, 2));

        layers.AddCalculationSnapshot(ForecastModel.NoaaGfs, snapshot);

        Assert.True(layers.HasSearchPoint(ForecastModel.NoaaGfs));
        Assert.True(layers.HasProvisionalRoute(ForecastModel.NoaaGfs));
        Assert.False(layers.HasLatestIsochroneFront(ForecastModel.NoaaGfs));
        Assert.Equal(0, layers.GetIsochroneFrontCount(ForecastModel.NoaaGfs));
        var search = Assert.IsType<MemoryLayer>(
            map.Layers.Single(layer => layer.Name == "NOAA GFS lattice search"));
        var feature = Assert.IsType<GeometryFeature>(Assert.Single(search.Features));
        Assert.IsType<Point>(feature.Geometry);
        Assert.Same(snapshot, feature.Data);

        layers.ClearCalculationOverlay(ForecastModel.NoaaGfs);

        Assert.False(layers.HasSearchPoint(ForecastModel.NoaaGfs));
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
        var finalPoint = Assert.IsType<GeometryFeature>(Assert.Single(Assert.IsType<MemoryLayer>(
            map.Layers.Single(layer => layer.Name == "NOAA GFS routes")).Features));
        Assert.IsType<Point>(finalPoint.Geometry);
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
        Assert.Equal(snapshot.FrontierTime, feature.Data);
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

    [Fact]
    public void Route_leg_features_keep_identity_and_selected_emphasis_across_antimeridian()
    {
        var map = new Map();
        var layers = new RouteMapLayers(map);
        var first = CreateVisualizationLeg(
            ForecastModel.NoaaGfs,
            0,
            new Coordinate(10, 179),
            new Coordinate(10, -179));
        var second = CreateVisualizationLeg(
            ForecastModel.NoaaGfs,
            1,
            new Coordinate(10, -179),
            new Coordinate(11, -175));

        layers.SetRouteLegs([first, second], second.Key);

        var routeLayer = Assert.IsType<MemoryLayer>(
            map.Layers.Single(layer => layer.Name == "NOAA GFS routes"));
        var features = routeLayer.Features.Cast<GeometryFeature>().ToArray();
        Assert.Equal(2, features.Length);
        Assert.Equal(first.Key, Assert.IsType<RouteLegVisualization>(features[0].Data).Key);
        Assert.Equal(second.Key, Assert.IsType<RouteLegVisualization>(features[1].Data).Key);
        var subdued = Assert.IsType<VectorStyle>(Assert.Single(features[0].Styles));
        var selected = Assert.IsType<VectorStyle>(Assert.Single(features[1].Styles));
        Assert.Equal(0.3f, subdued.Opacity);
        Assert.Equal(2.25, subdued.Line!.Width);
        Assert.Equal(1f, selected.Opacity);
        Assert.Equal(6, selected.Line!.Width);
        var datelineLine = Assert.IsType<LineString>(features[0].Geometry);
        var followingLine = Assert.IsType<LineString>(features[1].Geometry);
        Assert.True(Math.Abs(datelineLine.Coordinates[1].X - datelineLine.Coordinates[0].X) < 500_000);
        Assert.Equal(datelineLine.Coordinates[^1].X, followingLine.Coordinates[0].X, 6);
        Assert.Equal(
            followingLine.Coordinates[1].X,
            layers.GetProjectedRoutePoint(second.Key, 1)!.X,
            6);
        Assert.Equal(second.Key, layers.SelectedRouteKey);
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

    private static RouteLegVisualization CreateVisualizationLeg(
        ForecastModel model,
        int index,
        Coordinate fromCoordinate,
        Coordinate toCoordinate)
    {
        var planId = new RoutePlanId();
        var sessionId = new RouteCalculationSessionId();
        var from = new RouteWaypoint($"From {index}", fromCoordinate);
        var to = new RouteWaypoint($"To {index}", toCoordinate);
        var legId = RouteLegId.FromEndpoints(from.Id, to.Id);
        var departure = new DateTimeOffset(2026, 7, 15, index * 2, 0, 0, TimeSpan.Zero);
        var request = new RouteRequest(
            $"{planId}-leg-{index}-{sessionId}",
            fromCoordinate,
            toCoordinate,
            departure,
            departure.AddHours(4));
        var route = new RouteResult(
            request,
            model,
            [
                new RoutePoint(fromCoordinate, departure, 90, 6, 15, 180, 0),
                new RoutePoint(toCoordinate, departure.AddHours(2), 90, 6, 15, 180, 100)
            ],
            new RouteDiagnostics(10, 20, 5, 2));
        return new RouteLegVisualization(
            new RouteVisualizationKey(planId, legId, model, sessionId, request.RouteId),
            index,
            from,
            to,
            RouteLegOutcomeState.Succeeded,
            RouteLegOutcomeReason.CalculationSucceeded,
            route,
            null,
            false,
            departure,
            departure.AddHours(2));
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
