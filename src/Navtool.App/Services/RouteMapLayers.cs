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
    public static readonly MapsuiColor ReachabilityColor = MapsuiColor.FromString("#D32F2F");
    public const double HistoricalFrontLineWidth = 0.75;
    public const float HistoricalFrontOpacity = 0.18f;
    public const double DestinationFrontLineWidth = 2.0;
    public const float DestinationFrontOpacity = 0.92f;
    private const int IsochroneSmoothingIterations = 2;

    private readonly MemoryLayer _noaaRoutes = CreateRouteLayer("NOAA GFS routes", NoaaColor);
    private readonly MemoryLayer _ecmwfRoutes = CreateRouteLayer("ECMWF IFS routes", EcmwfColor);
    private readonly MemoryLayer _noaaHistoricalFronts = CreateHistoricalFrontLayer("NOAA GFS isochrone fronts");
    private readonly MemoryLayer _ecmwfHistoricalFronts = CreateHistoricalFrontLayer("ECMWF IFS isochrone fronts");
    private readonly MemoryLayer _noaaDestinationFront = CreateDestinationFrontLayer("NOAA GFS latest isochrone front");
    private readonly MemoryLayer _ecmwfDestinationFront = CreateDestinationFrontLayer("ECMWF IFS latest isochrone front");
    private readonly MemoryLayer _noaaProvisionalRoute = CreateProvisionalRouteLayer(
        "NOAA GFS provisional route",
        NoaaColor);
    private readonly MemoryLayer _ecmwfProvisionalRoute = CreateProvisionalRouteLayer(
        "ECMWF IFS provisional route",
        EcmwfColor);
    private readonly Dictionary<ForecastModel, List<IFeature>> _historicalFrontFeatures = new()
    {
        [ForecastModel.NoaaGfs] = new List<IFeature>(),
        [ForecastModel.EcmwfIfs] = new List<IFeature>()
    };
    private readonly MemoryLayer _windCells = new("Wind speed") { Style = null };
    private readonly MemoryLayer _windArrows = new("Wind direction") { Style = null };

    public RouteMapLayers(Map map)
    {
        ArgumentNullException.ThrowIfNull(map);
        Map = map;
        map.Layers.Add(_windCells);
        map.Layers.Add(_windArrows);
        map.Layers.Add(_noaaHistoricalFronts);
        map.Layers.Add(_ecmwfHistoricalFronts);
        map.Layers.Add(_noaaDestinationFront);
        map.Layers.Add(_ecmwfDestinationFront);
        map.Layers.Add(_noaaProvisionalRoute);
        map.Layers.Add(_ecmwfProvisionalRoute);
        map.Layers.Add(_noaaRoutes);
        map.Layers.Add(_ecmwfRoutes);
    }

    public Map Map { get; }

    public IReadOnlyList<RouteResult> Routes { get; private set; } = Array.Empty<RouteResult>();

    public int WeatherCellCount { get; private set; }

    public int GetIsochroneFrontCount(ForecastModel model) =>
        GetHistoricalFrontFeatures(model).Count;

    public bool HasLatestIsochroneFront(ForecastModel model) =>
        GetDestinationFrontLayer(model).Features.Any();

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
        var frontFeatures = CreateIsochroneFrontFeatures(snapshot).ToArray();
        var historicalFronts = GetHistoricalFrontFeatures(model);
        historicalFronts.AddRange(frontFeatures);
        var historicalFrontLayer = GetHistoricalFrontLayer(model);
        historicalFrontLayer.Features = historicalFronts.ToArray();
        historicalFrontLayer.FeaturesWereModified();

        var destinationFrontLayer = GetDestinationFrontLayer(model);
        destinationFrontLayer.Features = frontFeatures;
        destinationFrontLayer.FeaturesWereModified();

        var provisionalLayer = GetProvisionalRouteLayer(model);
        var provisionalRoute = CreateRouteFeature(snapshot.ProvisionalRoute, snapshot);
        provisionalLayer.Features = provisionalRoute is null
            ? Array.Empty<IFeature>()
            : new[] { provisionalRoute };
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

    private static MemoryLayer CreateHistoricalFrontLayer(string name) =>
        new(name)
        {
            Style = new VectorStyle
            {
                Fill = null,
                Line = new Pen(ReachabilityColor, HistoricalFrontLineWidth)
                {
                    PenStrokeCap = PenStrokeCap.Round
                },
                Opacity = HistoricalFrontOpacity
            }
        };

    private static MemoryLayer CreateDestinationFrontLayer(string name) =>
        new(name)
        {
            Style = new VectorStyle
            {
                Fill = null,
                Line = new Pen(ReachabilityColor, DestinationFrontLineWidth)
                {
                    PenStrokeCap = PenStrokeCap.Round
                },
                Opacity = DestinationFrontOpacity
            }
        };

    private static MemoryLayer CreateProvisionalRouteLayer(string name, MapsuiColor color) =>
        new(name)
        {
            Style = new VectorStyle
            {
                Fill = null,
                Line = new Pen(color, 2.5)
                {
                    PenStrokeCap = PenStrokeCap.Round
                },
                Opacity = 0.72f
            }
        };

    private static IEnumerable<IFeature> CreateRouteFeatures(IEnumerable<RouteResult> routes) =>
        routes
            .Select(CreateRouteFeature)
            .OfType<IFeature>()
            .ToArray();

    private static IFeature? CreateRouteFeature(RouteResult route) =>
        CreateRouteFeature(route.Points, route);

    private static IFeature? CreateRouteFeature(
        IEnumerable<RoutePoint> points,
        object data)
    {
        var routePoints = points.ToArray();
        if (routePoints.Length < 2)
        {
            return null;
        }

        var coordinates = MapProjection.ToContinuousMapPoints(
                routePoints.Select(point => point.Location))
            .Select(point => new NtsCoordinate(point.X, point.Y))
            .ToArray();
        var feature = new GeometryFeature(new LineString(coordinates));
        feature.Data = data;
        return feature;
    }

    private static IEnumerable<IFeature> CreateIsochroneFrontFeatures(
        RouteCalculationSnapshot snapshot)
    {
        var referenceX = MapProjection.ToContinuousMapPoints(
            snapshot.ProvisionalRoute.Select(point => point.Location))[^1].X;
        foreach (var segment in snapshot.FrontSegments)
        {
            if (segment.Points.Length < 2)
            {
                continue;
            }

            var coordinates = MapProjection.ToContinuousMapPointsNear(
                    segment.Points,
                    referenceX)
                .Select(point => new NtsCoordinate(point.X, point.Y))
                .ToArray();
            coordinates = SmoothOpenLine(coordinates, IsochroneSmoothingIterations);

            yield return new GeometryFeature(new LineString(coordinates))
            {
                Data = snapshot
            };
        }
    }

    private static NtsCoordinate[] SmoothOpenLine(
        IReadOnlyList<NtsCoordinate> source,
        int iterations)
    {
        var current = source
            .Select(point => new NtsCoordinate(point.X, point.Y))
            .ToArray();
        if (current.Length < 3 || iterations <= 0)
        {
            return current;
        }

        for (var iteration = 0; iteration < iterations; iteration++)
        {
            var smoothed = new List<NtsCoordinate>(current.Length * 2)
            {
                current[0]
            };
            for (var index = 0; index < current.Length - 1; index++)
            {
                var start = current[index];
                var end = current[index + 1];
                smoothed.Add(new NtsCoordinate(
                    (0.75 * start.X) + (0.25 * end.X),
                    (0.75 * start.Y) + (0.25 * end.Y)));
                smoothed.Add(new NtsCoordinate(
                    (0.25 * start.X) + (0.75 * end.X),
                    (0.25 * start.Y) + (0.75 * end.Y)));
            }
            smoothed.Add(current[^1]);
            current = smoothed.ToArray();
        }

        return current;
    }

    private List<IFeature> GetHistoricalFrontFeatures(ForecastModel model) =>
        _historicalFrontFeatures.TryGetValue(model, out var features)
            ? features
            : throw new ArgumentOutOfRangeException(nameof(model));

    private MemoryLayer GetHistoricalFrontLayer(ForecastModel model) => model switch
    {
        ForecastModel.NoaaGfs => _noaaHistoricalFronts,
        ForecastModel.EcmwfIfs => _ecmwfHistoricalFronts,
        _ => throw new ArgumentOutOfRangeException(nameof(model))
    };

    private MemoryLayer GetDestinationFrontLayer(ForecastModel model) => model switch
    {
        ForecastModel.NoaaGfs => _noaaDestinationFront,
        ForecastModel.EcmwfIfs => _ecmwfDestinationFront,
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
        var features = GetHistoricalFrontFeatures(model);
        features.Clear();
        var historicalFrontLayer = GetHistoricalFrontLayer(model);
        historicalFrontLayer.Features = Array.Empty<IFeature>();
        historicalFrontLayer.FeaturesWereModified();
        var destinationFrontLayer = GetDestinationFrontLayer(model);
        destinationFrontLayer.Features = Array.Empty<IFeature>();
        destinationFrontLayer.FeaturesWereModified();
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

}
