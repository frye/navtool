using System.Collections.Immutable;
using Mapsui;
using Mapsui.Layers;
using Mapsui.Nts;
using Mapsui.Styles;
using Navtool.App.Models;
using Navtool.Core;
using Navtool.Infrastructure;
using NetTopologySuite.Geometries;
using CoreCoordinate = Navtool.Core.Coordinate;
using MapsuiColor = Mapsui.Styles.Color;
using NtsCoordinate = NetTopologySuite.Geometries.Coordinate;

namespace Navtool.App.Services;

public sealed record OsmTileOptions(
    bool Enabled = true,
    string UserAgent = "Navtool/1.0");

public sealed class RouteMapLayers
{
    public static readonly MapsuiColor NoaaColor = MapsuiColor.FromString("#0072B2");
    public static readonly MapsuiColor EcmwfColor = MapsuiColor.FromString("#D55E00");

    private readonly MemoryLayer _noaaRoutes = CreateRouteLayer("NOAA GFS routes", NoaaColor);
    private readonly MemoryLayer _ecmwfRoutes = CreateRouteLayer("ECMWF IFS routes", EcmwfColor);
    private readonly MemoryLayer _noaaIsochrones = CreateIsochroneLayer("NOAA GFS isochrones", NoaaColor);
    private readonly MemoryLayer _ecmwfIsochrones = CreateIsochroneLayer("ECMWF IFS isochrones", EcmwfColor);
    private readonly MemoryLayer _noaaProvisionalRoute = CreateProvisionalRouteLayer(
        "NOAA GFS provisional route",
        NoaaColor);
    private readonly MemoryLayer _ecmwfProvisionalRoute = CreateProvisionalRouteLayer(
        "ECMWF IFS provisional route",
        EcmwfColor);
    private readonly Dictionary<ForecastModel, List<IFeature>> _isochroneFeatures = new()
    {
        [ForecastModel.NoaaGfs] = new List<IFeature>(),
        [ForecastModel.EcmwfIfs] = new List<IFeature>()
    };
    private readonly MemoryLayer _windCells = new("Wind speed") { Style = null };
    private readonly MemoryLayer _windArrows = new("Wind direction") { Style = null };
    private readonly MemoryLayer _endpoints = new("Route endpoints");
    private readonly MemoryLayer _timelinePoints = new("Timeline route points");
    private readonly MemoryLayer _selection = new("Selected route point");

    public RouteMapLayers(Map map)
    {
        ArgumentNullException.ThrowIfNull(map);
        Map = map;
        map.Layers.Add(_windCells);
        map.Layers.Add(_windArrows);
        map.Layers.Add(_noaaIsochrones);
        map.Layers.Add(_ecmwfIsochrones);
        map.Layers.Add(_noaaProvisionalRoute);
        map.Layers.Add(_ecmwfProvisionalRoute);
        map.Layers.Add(_noaaRoutes);
        map.Layers.Add(_ecmwfRoutes);
        map.Layers.Add(_endpoints);
        map.Layers.Add(_timelinePoints);
        map.Layers.Add(_selection);
    }

    public Map Map { get; }

    public IReadOnlyList<RouteResult> Routes { get; private set; } = Array.Empty<RouteResult>();

    public int WeatherCellCount { get; private set; }

    public int GetIsochroneCount(ForecastModel model) =>
        GetIsochroneFeatures(model).Count;

    public bool HasProvisionalRoute(ForecastModel model) =>
        GetProvisionalRouteLayer(model).Features.Any();

    public void SetRoutes(IEnumerable<RouteResult> routes)
    {
        ArgumentNullException.ThrowIfNull(routes);
        Routes = routes.ToArray();

        _noaaRoutes.Features = CreateRouteFeatures(Routes.Where(route => route.Model == ForecastModel.NoaaGfs));
        _ecmwfRoutes.Features = CreateRouteFeatures(Routes.Where(route => route.Model == ForecastModel.EcmwfIfs));
        _noaaRoutes.FeaturesWereModified();
        _ecmwfRoutes.FeaturesWereModified();
        Map.Refresh(ChangeType.Discrete);
    }

    public void FitRoutes()
    {
        var projected = Routes
            .SelectMany(route => MapProjection.ToContinuousMapPoints(
                route.Points.Select(point => point.Location)))
            .ToArray();
        if (projected.Length == 0)
        {
            return;
        }

        var extent = new MRect(
            projected.Min(point => point.X),
            projected.Min(point => point.Y),
            projected.Max(point => point.X),
            projected.Max(point => point.Y));
        Map.Navigator.ZoomToBox(extent.Grow(
            Math.Max(extent.Width, extent.Height) * 0.08 + 1_000));
    }

    public void AddCalculationSnapshot(
        ForecastModel model,
        RouteCalculationSnapshot snapshot)
    {
        ArgumentNullException.ThrowIfNull(snapshot);
        var isochrones = GetIsochroneFeatures(model);
        isochrones.Add(CreateIsochroneFeature(snapshot));
        var isochroneLayer = GetIsochroneLayer(model);
        isochroneLayer.Features = isochrones.ToArray();
        isochroneLayer.FeaturesWereModified();

        var provisionalLayer = GetProvisionalRouteLayer(model);
        provisionalLayer.Features =
            new[] { CreateRouteFeature(snapshot.ProvisionalRoute, snapshot) };
        provisionalLayer.FeaturesWereModified();
        Map.Refresh(ChangeType.Discrete);
    }

    public void ClearCalculationOverlays()
    {
        ClearCalculationOverlay(ForecastModel.NoaaGfs, refresh: false);
        ClearCalculationOverlay(ForecastModel.EcmwfIfs, refresh: false);
        Map.Refresh(ChangeType.Discrete);
    }

    public void ClearCalculationOverlay(ForecastModel model) =>
        ClearCalculationOverlay(model, refresh: true);

    public void SetEndpoints(CoreCoordinate? start, CoreCoordinate? destination)
    {
        var features = new List<IFeature>();
        if (start is not null)
        {
            features.AddRange(CreateWorldCopyMarkers(
                start.Value,
                MapsuiColor.FromString("#009E73"),
                MapsuiColor.White));
        }

        if (destination is not null)
        {
            features.AddRange(CreateWorldCopyMarkers(
                destination.Value,
                MapsuiColor.FromString("#CC3311"),
                MapsuiColor.White));
        }

        _endpoints.Features = features;
        _endpoints.FeaturesWereModified();
        Map.Refresh(ChangeType.Discrete);
    }

    public void SetSelectedPoint(RouteMapSelection? selection)
    {
        _selection.Features = selection is null
            ? Array.Empty<IFeature>()
            : new[]
            {
                CreateMarker(
                    GetRouteMapPoint(
                        selection.Route,
                        selection.PointIndex),
                    MapsuiColor.FromString("#F0E442"),
                    MapsuiColor.Black,
                    22)
            };
        _selection.FeaturesWereModified();
        Map.Refresh(ChangeType.Discrete);
    }

    public void SetTimelinePoints(
        IEnumerable<RoutePointSelection> selections,
        ForecastModel? activeModel)
    {
        ArgumentNullException.ThrowIfNull(selections);
        _timelinePoints.Features = selections
            .Select(selection =>
            {
                var route = Routes.First(item =>
                    item.Request.RouteId == selection.Route.RouteId &&
                    item.Model == selection.Route.Model);
                var pointIndex = route.Points.IndexOf(selection.Point);
                var color = selection.Route.Model == ForecastModel.NoaaGfs
                    ? NoaaColor
                    : EcmwfColor;
                return CreateMarker(
                    GetRouteMapPoint(route, Math.Max(0, pointIndex)),
                    color,
                    MapsuiColor.White,
                    selection.Route.Model == activeModel ? 18 : 13);
            })
            .ToArray();
        _timelinePoints.FeaturesWereModified();
        Map.Refresh(ChangeType.Discrete);
    }

    public void SetWeather(
        IEnumerable<ViewportWindSample> samples,
        GeographicBounds bounds,
        int latitudeCount,
        int longitudeCount)
    {
        ArgumentNullException.ThrowIfNull(samples);
        var valid = samples.Where(sample => sample.Weather is not null).ToArray();
        var latitudeSpan = Math.Max(0.1, bounds.North - bounds.South);
        var longitudeSpan = bounds.CrossesAntimeridian
            ? bounds.East + 360 - bounds.West
            : bounds.East - bounds.West;
        longitudeSpan = Math.Max(0.1, longitudeSpan);
        var halfLatitude = latitudeSpan / Math.Max(1, latitudeCount - 1) * 0.48;
        var halfLongitude = longitudeSpan / Math.Max(1, longitudeCount - 1) * 0.48;

        _windCells.Features = valid
            .Select(sample => CreateWindCell(sample, halfLatitude, halfLongitude))
            .ToArray();
        _windArrows.Features = valid
            .Select(sample => CreateWindArrow(sample, halfLatitude, halfLongitude))
            .ToArray();
        WeatherCellCount = valid.Length;
        _windCells.FeaturesWereModified();
        _windArrows.FeaturesWereModified();
        Map.Refresh(ChangeType.Discrete);
    }

    public void ClearWeather()
    {
        _windCells.Features = Array.Empty<IFeature>();
        _windArrows.Features = Array.Empty<IFeature>();
        WeatherCellCount = 0;
        _windCells.FeaturesWereModified();
        _windArrows.FeaturesWereModified();
        Map.Refresh(ChangeType.Discrete);
    }

    private static MemoryLayer CreateRouteLayer(string name, MapsuiColor color) =>
        new(name)
        {
            Style = new VectorStyle
            {
                Line = new Pen(color, 4)
                {
                    PenStrokeCap = PenStrokeCap.Round
                }
            }
        };

    private static MemoryLayer CreateIsochroneLayer(string name, MapsuiColor color) =>
        new(name)
        {
            Style = new VectorStyle
            {
                Line = new Pen(color, 1.5)
                {
                    PenStrokeCap = PenStrokeCap.Round
                },
                Opacity = 0.28f
            }
        };

    private static MemoryLayer CreateProvisionalRouteLayer(string name, MapsuiColor color) =>
        new(name)
        {
            Style = new VectorStyle
            {
                Line = new Pen(color, 2.5)
                {
                    PenStrokeCap = PenStrokeCap.Round
                },
                Opacity = 0.72f
            }
        };

    private static IEnumerable<IFeature> CreateRouteFeatures(IEnumerable<RouteResult> routes) =>
        routes.Select(CreateRouteFeature).ToArray();

    private static IFeature CreateRouteFeature(RouteResult route) =>
        CreateRouteFeature(route.Points, route);

    private static IFeature CreateRouteFeature(
        IEnumerable<RoutePoint> points,
        object data)
    {
        var routePoints = points.ToArray();
        IFeature feature;
        if (routePoints.Length == 1)
        {
            feature = new PointFeature(MapProjection.ToMapPoint(routePoints[0].Location));
        }
        else
        {
            var coordinates = MapProjection.ToContinuousMapPoints(
                    routePoints.Select(point => point.Location))
                .Select(point => new NtsCoordinate(point.X, point.Y))
                .ToArray();
            feature = new GeometryFeature(new LineString(coordinates));
        }

        feature.Data = data;
        return feature;
    }

    private static IFeature CreateIsochroneFeature(RouteCalculationSnapshot snapshot)
    {
        var ordered = OrderFrontier(snapshot.Frontier);
        if (ordered.Length == 1)
        {
            var point = new PointFeature(MapProjection.ToMapPoint(ordered[0]))
            {
                Data = snapshot
            };
            return point;
        }

        var coordinates = MapProjection.ToContinuousMapPoints(ordered.Add(ordered[0]))
            .Select(point => new NtsCoordinate(point.X, point.Y))
            .ToArray();
        var feature = new GeometryFeature(new LineString(coordinates))
        {
            Data = snapshot
        };
        return feature;
    }

    private static ImmutableArray<CoreCoordinate> OrderFrontier(
        IEnumerable<CoreCoordinate> points)
    {
        var frontier = points.ToArray();
        var latitudeCenter = frontier.Average(point => point.Latitude);
        var longitudeSine = frontier.Sum(point =>
            Math.Sin(point.Longitude * Math.PI / 180));
        var longitudeCosine = frontier.Sum(point =>
            Math.Cos(point.Longitude * Math.PI / 180));
        var longitudeCenter =
            Math.Abs(longitudeSine) > 1e-12 || Math.Abs(longitudeCosine) > 1e-12
                ? Math.Atan2(longitudeSine, longitudeCosine) * 180 / Math.PI
                : frontier[0].Longitude;
        var longitudeScale = Math.Cos(latitudeCenter * Math.PI / 180);

        return frontier
            .Select((point, index) => new
            {
                Point = point,
                Index = index,
                Angle = Math.Atan2(
                    point.Latitude - latitudeCenter,
                    NormalizeLongitudeDelta(
                        point.Longitude,
                        longitudeCenter) * longitudeScale)
            })
            .OrderBy(item => item.Angle)
            .ThenBy(item => item.Index)
            .Select(item => item.Point)
            .ToImmutableArray();
    }

    private static double NormalizeLongitudeDelta(double longitude, double origin) =>
        (longitude - origin + 540) % 360 - 180;

    private List<IFeature> GetIsochroneFeatures(ForecastModel model) =>
        _isochroneFeatures.TryGetValue(model, out var features)
            ? features
            : throw new ArgumentOutOfRangeException(nameof(model));

    private MemoryLayer GetIsochroneLayer(ForecastModel model) => model switch
    {
        ForecastModel.NoaaGfs => _noaaIsochrones,
        ForecastModel.EcmwfIfs => _ecmwfIsochrones,
        _ => throw new ArgumentOutOfRangeException(nameof(model))
    };

    private MemoryLayer GetProvisionalRouteLayer(ForecastModel model) => model switch
    {
        ForecastModel.NoaaGfs => _noaaProvisionalRoute,
        ForecastModel.EcmwfIfs => _ecmwfProvisionalRoute,
        _ => throw new ArgumentOutOfRangeException(nameof(model))
    };

    private void ClearCalculationOverlay(ForecastModel model, bool refresh)
    {
        var features = GetIsochroneFeatures(model);
        features.Clear();
        var isochroneLayer = GetIsochroneLayer(model);
        isochroneLayer.Features = Array.Empty<IFeature>();
        isochroneLayer.FeaturesWereModified();
        var provisionalLayer = GetProvisionalRouteLayer(model);
        provisionalLayer.Features = Array.Empty<IFeature>();
        provisionalLayer.FeaturesWereModified();
        if (refresh)
        {
            Map.Refresh(ChangeType.Discrete);
        }
    }

    private static IFeature CreateWindCell(
        ViewportWindSample sample,
        double halfLatitude,
        double halfLongitude)
    {
        var center = MapProjection.ToMapPoint(sample.Location);
        var north = MapProjection.ToMapPoint(new CoreCoordinate(
            Math.Clamp(sample.Location.Latitude + halfLatitude, -85, 85),
            sample.Location.Longitude));
        var eastLongitude = NormalizeLongitude(sample.Location.Longitude + halfLongitude);
        var east = MapProjection.ToMapPoint(new CoreCoordinate(
            sample.Location.Latitude,
            eastLongitude));
        var halfHeight = Math.Max(100, Math.Abs(north.Y - center.Y));
        var halfWidth = Math.Max(100, Math.Abs(east.X - center.X));
        if (halfWidth > 10_000_000)
        {
            halfWidth = 100_000;
        }

        var polygon = new Polygon(new LinearRing(new[]
        {
            new NtsCoordinate(center.X - halfWidth, center.Y - halfHeight),
            new NtsCoordinate(center.X + halfWidth, center.Y - halfHeight),
            new NtsCoordinate(center.X + halfWidth, center.Y + halfHeight),
            new NtsCoordinate(center.X - halfWidth, center.Y + halfHeight),
            new NtsCoordinate(center.X - halfWidth, center.Y - halfHeight)
        }));
        var feature = new GeometryFeature(polygon);
        feature.Styles.Add(new VectorStyle
        {
            Fill = new Brush(MapsuiColor.Transparent),
            Outline = null,
            Opacity = 0f
        });
        return feature;
    }

    private static IFeature CreateWindArrow(
        ViewportWindSample sample,
        double halfLatitude,
        double halfLongitude)
    {
        var weather = sample.Weather!;
        var toward = NormalizeDirection(weather.WindDirectionDegrees + 180);
        var shaft = CreateDirectionalSegment(
            sample.Location,
            toward,
            halfLatitude * 0.65,
            halfLongitude * 0.65);
        var headOne = CreateArrowHead(shaft.End, toward + 150, halfLatitude, halfLongitude);
        var headTwo = CreateArrowHead(shaft.End, toward + 210, halfLatitude, halfLongitude);
        var geometry = new MultiLineString(new[]
        {
            ToLineString(shaft.Start, shaft.End),
            ToLineString(shaft.End, headOne),
            ToLineString(shaft.End, headTwo)
        });
        var feature = new GeometryFeature(geometry);
        var knots = weather.WindSpeedMetersPerSecond * 1.9438444924406;
        feature.Styles.Add(new VectorStyle
        {
            Line = new Pen(MapsuiColor.FromString(WindColorScale.GetHex(knots)), 1.8),
            Opacity = 0.95f
        });
        return feature;
    }

    private static (CoreCoordinate Start, CoreCoordinate End) CreateDirectionalSegment(
        CoreCoordinate center,
        double direction,
        double latitudeLength,
        double longitudeLength)
    {
        var radians = direction * Math.PI / 180;
        var latitudeDelta = Math.Cos(radians) * latitudeLength;
        var longitudeDelta = Math.Sin(radians) * longitudeLength;
        return (
            new CoreCoordinate(
                Math.Clamp(center.Latitude - latitudeDelta, -85, 85),
                NormalizeLongitude(center.Longitude - longitudeDelta)),
            new CoreCoordinate(
                Math.Clamp(center.Latitude + latitudeDelta, -85, 85),
                NormalizeLongitude(center.Longitude + longitudeDelta)));
    }

    private static CoreCoordinate CreateArrowHead(
        CoreCoordinate end,
        double direction,
        double halfLatitude,
        double halfLongitude)
    {
        var radians = direction * Math.PI / 180;
        return new CoreCoordinate(
            Math.Clamp(end.Latitude + Math.Cos(radians) * halfLatitude * 0.3, -85, 85),
            NormalizeLongitude(end.Longitude + Math.Sin(radians) * halfLongitude * 0.3));
    }

    private static LineString ToLineString(CoreCoordinate first, CoreCoordinate second)
    {
        var start = MapProjection.ToMapPoint(first);
        var end = MapProjection.ToMapPoint(second);
        return new LineString(new[]
        {
            new NtsCoordinate(start.X, start.Y),
            new NtsCoordinate(end.X, end.Y)
        });
    }

    private static double NormalizeLongitude(double value)
    {
        var normalized = ((value + 180) % 360 + 360) % 360 - 180;
        return normalized == -180 && value > 0 ? 180 : normalized;
    }

    private static double NormalizeDirection(double value)
    {
        var normalized = value % 360;
        return normalized < 0 ? normalized + 360 : normalized;
    }

    private static PointFeature CreateMarker(
        CoreCoordinate coordinate,
        MapsuiColor fill,
        MapsuiColor outline,
        double size = 18) =>
        CreateMarker(MapProjection.ToMapPoint(coordinate), fill, outline, size);

    private static PointFeature CreateMarker(
        MPoint point,
        MapsuiColor fill,
        MapsuiColor outline,
        double size = 18)
    {
        var feature = new PointFeature(point);
        feature.Styles.Add(new SymbolStyle
        {
            SymbolType = SymbolType.Ellipse,
            SymbolScale = size / SymbolStyle.DefaultWidth,
            Fill = new Brush(fill),
            Outline = new Pen(outline, 3)
        });
        return feature;
    }

    private static IEnumerable<PointFeature> CreateWorldCopyMarkers(
        CoreCoordinate coordinate,
        MapsuiColor fill,
        MapsuiColor outline)
    {
        var point = MapProjection.ToMapPoint(coordinate);
        return new[]
        {
            CreateMarker(
                new MPoint(point.X - MapProjection.WebMercatorWorldWidth, point.Y),
                fill,
                outline),
            CreateMarker(point, fill, outline),
            CreateMarker(
                new MPoint(point.X + MapProjection.WebMercatorWorldWidth, point.Y),
                fill,
                outline)
        };
    }

    private static MPoint GetRouteMapPoint(RouteResult route, int pointIndex)
    {
        var points = MapProjection.ToContinuousMapPoints(
            route.Points.Select(point => point.Location));
        return points[Math.Clamp(pointIndex, 0, points.Count - 1)];
    }
}
