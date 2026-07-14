using Navtool.Core;

namespace Navtool.App.Models;

public enum RouteHitKind
{
    Route,
    RoutePoint
}

public sealed record RouteMapSelection(
    RouteResult Route,
    int PointIndex,
    RoutePoint Point,
    RouteHitKind HitKind,
    double DistancePixels)
{
    public DateTimeOffset TimelineTimestamp => Point.Timestamp;
    public Coordinate FocusCoordinate => Point.Location;
}
