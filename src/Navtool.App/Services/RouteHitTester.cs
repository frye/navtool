using Navtool.App.Models;
using Navtool.Core;

namespace Navtool.App.Services;

public static class RouteHitTester
{
    public static RouteMapSelection? FindNearest(
        IEnumerable<RouteResult> routes,
        Func<Coordinate, ScreenPoint> projectToScreen,
        ScreenPoint click,
        double routeTolerancePixels = 10,
        double pointTolerancePixels = 14)
    {
        ArgumentNullException.ThrowIfNull(routes);
        ArgumentNullException.ThrowIfNull(projectToScreen);
        ValidateTolerance(routeTolerancePixels, nameof(routeTolerancePixels));
        ValidateTolerance(pointTolerancePixels, nameof(pointTolerancePixels));

        return FindNearest(
            routes,
            route => route.Points
                .Select(point => projectToScreen(point.Location))
                .ToArray(),
            click,
            routeTolerancePixels,
            pointTolerancePixels);
    }

    public static RouteMapSelection? FindNearest(
        IEnumerable<RouteResult> routes,
        Func<RouteResult, IReadOnlyList<ScreenPoint>> projectToScreen,
        ScreenPoint click,
        double routeTolerancePixels = 10,
        double pointTolerancePixels = 14)
    {
        ArgumentNullException.ThrowIfNull(routes);
        ArgumentNullException.ThrowIfNull(projectToScreen);
        ValidateTolerance(routeTolerancePixels, nameof(routeTolerancePixels));
        ValidateTolerance(pointTolerancePixels, nameof(pointTolerancePixels));

        var projectedRoutes = routes
            .Select(route => new ProjectedRoute(
                route,
                ValidateProjectedPoints(route, projectToScreen(route))))
            .ToArray();

        var pointHit = FindNearestPoint(projectedRoutes, click, pointTolerancePixels);
        return pointHit ?? FindNearestSegment(projectedRoutes, click, routeTolerancePixels);
    }

    private static ScreenPoint[] ValidateProjectedPoints(
        RouteResult route,
        IReadOnlyList<ScreenPoint> projected)
    {
        ArgumentNullException.ThrowIfNull(projected);
        if (projected.Count != route.Points.Length)
        {
            throw new ArgumentException(
                "A projected route must contain one screen point per route point.",
                nameof(projected));
        }

        return projected.ToArray();
    }

    private static RouteMapSelection? FindNearestPoint(
        IEnumerable<ProjectedRoute> routes,
        ScreenPoint click,
        double tolerance)
    {
        RouteMapSelection? nearest = null;

        foreach (var route in routes)
        {
            for (var index = 0; index < route.Points.Length; index++)
            {
                var distance = click.DistanceTo(route.Points[index]);
                if (distance <= tolerance && (nearest is null || distance < nearest.DistancePixels))
                {
                    nearest = CreateSelection(route.Route, index, RouteHitKind.RoutePoint, distance);
                }
            }
        }

        return nearest;
    }

    private static RouteMapSelection? FindNearestSegment(
        IEnumerable<ProjectedRoute> routes,
        ScreenPoint click,
        double tolerance)
    {
        RouteMapSelection? nearest = null;

        foreach (var route in routes)
        {
            if (route.Points.Length == 1)
            {
                continue;
            }

            for (var index = 1; index < route.Points.Length; index++)
            {
                var distance = DistanceToSegment(click, route.Points[index - 1], route.Points[index]);
                if (distance > tolerance || (nearest is not null && distance >= nearest.DistancePixels))
                {
                    continue;
                }

                var pointIndex = click.DistanceTo(route.Points[index - 1]) <= click.DistanceTo(route.Points[index])
                    ? index - 1
                    : index;
                nearest = CreateSelection(route.Route, pointIndex, RouteHitKind.Route, distance);
            }
        }

        return nearest;
    }

    private static RouteMapSelection CreateSelection(
        RouteResult route,
        int pointIndex,
        RouteHitKind kind,
        double distance) =>
        new(route, pointIndex, route.Points[pointIndex], kind, distance);

    private static double DistanceToSegment(ScreenPoint point, ScreenPoint start, ScreenPoint end)
    {
        var segmentX = end.X - start.X;
        var segmentY = end.Y - start.Y;
        var lengthSquared = (segmentX * segmentX) + (segmentY * segmentY);
        if (lengthSquared == 0)
        {
            return point.DistanceTo(start);
        }

        var projection = (((point.X - start.X) * segmentX) + ((point.Y - start.Y) * segmentY)) /
                         lengthSquared;
        var clamped = Math.Clamp(projection, 0, 1);
        return point.DistanceTo(new ScreenPoint(
            start.X + (clamped * segmentX),
            start.Y + (clamped * segmentY)));
    }

    private static void ValidateTolerance(double tolerance, string parameterName)
    {
        if (!double.IsFinite(tolerance) || tolerance < 0)
        {
            throw new ArgumentOutOfRangeException(parameterName);
        }
    }
    private sealed record ProjectedRoute(RouteResult Route, ScreenPoint[] Points);
}
