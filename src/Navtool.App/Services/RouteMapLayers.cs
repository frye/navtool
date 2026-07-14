using Mapsui;
using Mapsui.Layers;
using Mapsui.Nts;
using Mapsui.Styles;
using Navtool.Core;
using Navtool.Infrastructure;
using NetTopologySuite.Geometries;
using CoreCoordinate = Navtool.Core.Coordinate;
using MapsuiColor = Mapsui.Styles.Color;
using NtsCoordinate = NetTopologySuite.Geometries.Coordinate;

namespace Navtool.App.Services;

public sealed record OsmTileOptions(
    bool Enabled = true,
    string UserAgent = "Navtool/1.0",
    string Attribution = "© OpenStreetMap contributors");

public sealed class RouteMapLayers
{
    public static readonly MapsuiColor NoaaColor = MapsuiColor.FromString("#0072B2");
    public static readonly MapsuiColor EcmwfColor = MapsuiColor.FromString("#D55E00");

    private readonly MemoryLayer _noaaRoutes = CreateRouteLayer("NOAA GFS routes", NoaaColor);
    private readonly MemoryLayer _ecmwfRoutes = CreateRouteLayer("ECMWF IFS routes", EcmwfColor);
    private readonly MemoryLayer _windCells = new("Wind speed");
    private readonly MemoryLayer _windArrows = new("Wind direction");
    private readonly MemoryLayer _endpoints = new("Route endpoints");
    private readonly MemoryLayer _timelinePoints = new("Timeline route points");
    private readonly MemoryLayer _selection = new("Selected route point");

    public RouteMapLayers(Map map)
    {
        ArgumentNullException.ThrowIfNull(map);
        Map = map;
        map.Layers.Add(_windCells);
        map.Layers.Add(_windArrows);
        map.Layers.Add(_noaaRoutes);
        map.Layers.Add(_ecmwfRoutes);
        map.Layers.Add(_endpoints);
        map.Layers.Add(_timelinePoints);
        map.Layers.Add(_selection);
    }

    public Map Map { get; }

    public IReadOnlyList<RouteResult> Routes { get; private set; } = Array.Empty<RouteResult>();

    public int WeatherCellCount { get; private set; }

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
        var points = Routes.SelectMany(route => route.Points).ToArray();
        if (points.Length == 0)
        {
            return;
        }

        var projected = points.Select(point => MapProjection.ToMapPoint(point.Location)).ToArray();
        var extent = new MRect(
            projected.Min(point => point.X),
            projected.Min(point => point.Y),
            projected.Max(point => point.X),
            projected.Max(point => point.Y));
        Map.Navigator.ZoomToBox(extent.Grow(
            Math.Max(extent.Width, extent.Height) * 0.08 + 1_000));
    }

    public void SetEndpoints(CoreCoordinate? start, CoreCoordinate? destination)
    {
        var features = new List<IFeature>();
        if (start is not null)
        {
            features.Add(CreateMarker(start.Value, MapsuiColor.FromString("#009E73"), MapsuiColor.White));
        }

        if (destination is not null)
        {
            features.Add(CreateMarker(destination.Value, MapsuiColor.FromString("#CC3311"), MapsuiColor.White));
        }

        _endpoints.Features = features;
        _endpoints.FeaturesWereModified();
        Map.Refresh(ChangeType.Discrete);
    }

    public void SetSelectedPoint(CoreCoordinate? coordinate)
    {
        _selection.Features = coordinate is null
            ? Array.Empty<IFeature>()
            : new[] { CreateMarker(coordinate.Value, MapsuiColor.FromString("#F0E442"), MapsuiColor.Black, 22) };
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
                var color = selection.Route.Model == ForecastModel.NoaaGfs
                    ? NoaaColor
                    : EcmwfColor;
                return CreateMarker(
                    selection.Point.Location,
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

    private static IEnumerable<IFeature> CreateRouteFeatures(IEnumerable<RouteResult> routes) =>
        routes.Select(CreateRouteFeature).ToArray();

    private static IFeature CreateRouteFeature(RouteResult route)
    {
        IFeature feature;
        if (route.Points.Length == 1)
        {
            feature = new PointFeature(MapProjection.ToMapPoint(route.Points[0].Location));
        }
        else
        {
            var coordinates = route.Points
                .Select(point =>
                {
                    var mapPoint = MapProjection.ToMapPoint(point.Location);
                    return new NtsCoordinate(mapPoint.X, mapPoint.Y);
                })
                .ToArray();
            feature = new GeometryFeature(new LineString(coordinates));
        }

        feature.Data = route;
        return feature;
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
        var knots = sample.Weather!.WindSpeedMetersPerSecond * 1.9438444924406;
        feature.Styles.Add(new VectorStyle
        {
            Fill = new Brush(MapsuiColor.FromString(WindColorScale.GetHex(knots))),
            Outline = new Pen(MapsuiColor.White, 0.5),
            Opacity = 0.38f
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
        feature.Styles.Add(new VectorStyle
        {
            Line = new Pen(MapsuiColor.FromString("#173440"), 1.4),
            Opacity = 0.82f
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
        double size = 18)
    {
        var feature = new PointFeature(MapProjection.ToMapPoint(coordinate));
        feature.Styles.Add(new SymbolStyle
        {
            SymbolType = SymbolType.Ellipse,
            SymbolScale = size / SymbolStyle.DefaultWidth,
            Fill = new Brush(fill),
            Outline = new Pen(outline, 3)
        });
        return feature;
    }
}
