using Mapsui;
using Mapsui.Projections;
using Navtool.Core;

namespace Navtool.App.Services;

public static class MapProjection
{
    public const double WebMercatorWorldWidth = 40_075_016.68557849;

    public static MPoint ToMapPoint(Coordinate coordinate)
    {
        var (x, y) = SphericalMercator.FromLonLat(coordinate.Longitude, coordinate.Latitude);
        return new MPoint(x, y);
    }

    public static MPoint ToMapPointNear(Coordinate coordinate, double referenceX)
    {
        var point = ToMapPoint(coordinate);
        var x = point.X;
        while (x - referenceX > WebMercatorWorldWidth / 2)
        {
            x -= WebMercatorWorldWidth;
        }

        while (referenceX - x > WebMercatorWorldWidth / 2)
        {
            x += WebMercatorWorldWidth;
        }

        return new MPoint(x, point.Y);
    }

    public static IReadOnlyList<MPoint> ToContinuousMapPoints(
        IEnumerable<Coordinate> coordinates)
    {
        ArgumentNullException.ThrowIfNull(coordinates);
        var projected = new List<MPoint>();
        foreach (var coordinate in coordinates)
        {
            projected.Add(projected.Count == 0
                ? ToMapPoint(coordinate)
                : ToMapPointNear(coordinate, projected[^1].X));
        }

        return projected;
    }

    public static IReadOnlyList<MPoint> ToContinuousMapPointsNear(
        IEnumerable<Coordinate> coordinates,
        double referenceX)
    {
        var projected = ToContinuousMapPoints(coordinates);
        if (projected.Count == 0)
        {
            return projected;
        }

        var centerX = (projected.Min(point => point.X) +
                       projected.Max(point => point.X)) / 2;
        var worldOffset = Math.Round(
            (referenceX - centerX) / WebMercatorWorldWidth) *
            WebMercatorWorldWidth;
        return projected
            .Select(point => new MPoint(point.X + worldOffset, point.Y))
            .ToArray();
    }

    public static Coordinate ToCoordinate(MPoint point)
    {
        var (longitude, latitude) = SphericalMercator.ToLonLat(point.X, point.Y);
        return new Coordinate(
            Math.Clamp(latitude, -90, 90),
            NormalizeLongitude(longitude));
    }

    private static double NormalizeLongitude(double longitude)
    {
        var normalized = ((longitude + 180) % 360 + 360) % 360 - 180;
        return normalized == -180 && longitude > 0 ? 180 : normalized;
    }
}
