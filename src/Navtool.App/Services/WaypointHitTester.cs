using Navtool.App.Models;
using Navtool.Core;

namespace Navtool.App.Services;

public static class WaypointHitTester
{
    public static WaypointMapMarker? FindNearest(
        IEnumerable<WaypointMapMarker> waypoints,
        Func<Coordinate, ScreenPoint> projectToScreen,
        ScreenPoint click,
        double tolerancePixels = 18)
    {
        ArgumentNullException.ThrowIfNull(waypoints);
        ArgumentNullException.ThrowIfNull(projectToScreen);
        if (!double.IsFinite(tolerancePixels) || tolerancePixels < 0)
        {
            throw new ArgumentOutOfRangeException(nameof(tolerancePixels));
        }

        if (!IsFinite(click))
        {
            return null;
        }

        WaypointMapMarker? nearest = null;
        var nearestDistance = double.PositiveInfinity;
        foreach (var waypoint in waypoints)
        {
            if (waypoint.Coordinate is not { } coordinate)
            {
                continue;
            }

            var projected = projectToScreen(coordinate);
            if (!IsFinite(projected))
            {
                continue;
            }

            var distance = click.DistanceTo(projected);
            if (distance <= tolerancePixels && distance < nearestDistance)
            {
                nearest = waypoint;
                nearestDistance = distance;
            }
        }

        return nearest;
    }

    private static bool IsFinite(ScreenPoint point) =>
        double.IsFinite(point.X) && double.IsFinite(point.Y);
}
