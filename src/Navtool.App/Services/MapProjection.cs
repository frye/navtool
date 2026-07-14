using Mapsui;
using Mapsui.Projections;
using Navtool.Core;

namespace Navtool.App.Services;

public static class MapProjection
{
    public static MPoint ToMapPoint(Coordinate coordinate)
    {
        var (x, y) = SphericalMercator.FromLonLat(coordinate.Longitude, coordinate.Latitude);
        return new MPoint(x, y);
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
