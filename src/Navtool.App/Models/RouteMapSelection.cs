using Navtool.Core;

namespace Navtool.App.Models;

public enum RouteHitKind
{
    Route,
    RoutePoint
}

public sealed record RouteMapSelection
{
    public RouteMapSelection(
        RouteLegVisualization leg,
        int pointIndex,
        RoutePoint point,
        RouteHitKind hitKind,
        double distancePixels)
        : this(leg.Route!, pointIndex, point, hitKind, distancePixels)
    {
        Leg = leg;
    }

    public RouteMapSelection(
        RouteResult route,
        int pointIndex,
        RoutePoint point,
        RouteHitKind hitKind,
        double distancePixels)
    {
        ArgumentNullException.ThrowIfNull(route);
        ArgumentNullException.ThrowIfNull(point);
        Route = route;
        PointIndex = pointIndex;
        Point = point;
        HitKind = hitKind;
        DistancePixels = distancePixels;
    }

    public RouteLegVisualization? Leg { get; }

    public RouteVisualizationKey? Key => Leg?.Key;

    public RouteResult Route { get; }

    public int PointIndex { get; }

    public RoutePoint Point { get; }

    public RouteHitKind HitKind { get; }

    public double DistancePixels { get; }

    public DateTimeOffset TimelineTimestamp => Point.Timestamp;

    public Coordinate FocusCoordinate => Point.Location;
}
