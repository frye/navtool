using Navtool.App.Models;
using Navtool.App.Services;
using Navtool.Core;

namespace Navtool.App.Tests;

public sealed class WaypointHitTesterTests
{
    [Fact]
    public void Finds_nearest_placed_waypoint_within_screen_tolerance()
    {
        var first = new WaypointMapMarker(
            1,
            "Start",
            new Coordinate(10, 20),
            new RouteWaypointId());
        var second = new WaypointMapMarker(
            2,
            "Lunch",
            new Coordinate(30, 40),
            new RouteWaypointId());

        var hit = WaypointHitTester.FindNearest(
            [first, second],
            coordinate => new ScreenPoint(coordinate.Longitude, coordinate.Latitude),
            new ScreenPoint(39, 31),
            tolerancePixels: 4);

        Assert.Same(second, hit);
    }

    [Fact]
    public void Ignores_unplaced_waypoints_and_points_outside_tolerance()
    {
        var unplaced = new WaypointMapMarker(1, "Pending", null, new RouteWaypointId());
        var placed = new WaypointMapMarker(
            2,
            "Finish",
            new Coordinate(30, 40),
            new RouteWaypointId());

        var hit = WaypointHitTester.FindNearest(
            [unplaced, placed],
            coordinate => new ScreenPoint(coordinate.Longitude, coordinate.Latitude),
            new ScreenPoint(50, 50),
            tolerancePixels: 5);

        Assert.Null(hit);
    }
}
