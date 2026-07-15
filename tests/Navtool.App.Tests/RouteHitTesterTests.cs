using Navtool.App.Models;
using Navtool.App.Services;
using Navtool.Core;

namespace Navtool.App.Tests;

public sealed class RouteHitTesterTests
{
    [Fact]
    public void FindsNearestRouteSegmentInScreenSpace()
    {
        var noaa = CreateRoute(ForecastModel.NoaaGfs, 0);
        var ecmwf = CreateRoute(ForecastModel.EcmwfIfs, 30);

        var hit = RouteHitTester.FindNearest(
            new[] { ecmwf, noaa },
            Project,
            new ScreenPoint(50, 6),
            routeTolerancePixels: 10,
            pointTolerancePixels: 12);

        Assert.NotNull(hit);
        Assert.Same(noaa, hit.Route);
        Assert.Equal(RouteHitKind.Route, hit.HitKind);
        Assert.Equal(6, hit.DistancePixels, 6);
        Assert.Equal(noaa.Points[hit.PointIndex].Timestamp, hit.TimelineTimestamp);
        Assert.Equal(noaa.Points[hit.PointIndex].Location, hit.FocusCoordinate);
    }

    [Fact]
    public void PrefersNearestRoutePointWithinPointTolerance()
    {
        var route = CreateRoute(ForecastModel.NoaaGfs, 0);

        var hit = RouteHitTester.FindNearest(
            new[] { route },
            Project,
            new ScreenPoint(97, 4),
            routeTolerancePixels: 10,
            pointTolerancePixels: 6);

        Assert.NotNull(hit);
        Assert.Equal(RouteHitKind.RoutePoint, hit.HitKind);
        Assert.Equal(1, hit.PointIndex);
        Assert.Equal(5, hit.DistancePixels, 6);
    }

    [Fact]
    public void ReturnsNullOutsidePixelTolerance()
    {
        var route = CreateRoute(ForecastModel.NoaaGfs, 0);

        var hit = RouteHitTester.FindNearest(
            new[] { route },
            Project,
            new ScreenPoint(50, 11),
            routeTolerancePixels: 10,
            pointTolerancePixels: 6);

        Assert.Null(hit);
    }

    [Fact]
    public void RouteLevelProjectionDoesNotCreateFalseDatelineSegment()
    {
        var route = CreateRoute(ForecastModel.NoaaGfs, 0);

        var miss = RouteHitTester.FindNearest(
            new[] { route },
            _ => new[]
            {
                new ScreenPoint(179, 0),
                new ScreenPoint(181, 0)
            },
            new ScreenPoint(0, 0),
            routeTolerancePixels: 10,
            pointTolerancePixels: 10);
        var hit = RouteHitTester.FindNearest(
            new[] { route },
            _ => new[]
            {
                new ScreenPoint(179, 0),
                new ScreenPoint(181, 0)
            },
            new ScreenPoint(180, 5),
            routeTolerancePixels: 10,
            pointTolerancePixels: 4);

        Assert.Null(miss);
        Assert.NotNull(hit);
        Assert.Equal(RouteHitKind.Route, hit.HitKind);
    }

    private static ScreenPoint Project(Coordinate coordinate) =>
        new(coordinate.Longitude, coordinate.Latitude);

    private static RouteResult CreateRoute(ForecastModel model, double latitude)
    {
        var departure = new DateTimeOffset(2026, 7, 14, 12, 0, 0, TimeSpan.Zero);
        var request = new RouteRequest(
            $"route-{model}",
            new Coordinate(latitude, 0),
            new Coordinate(latitude, 100),
            departure,
            departure.AddDays(2));
        var points = new[]
        {
            new RoutePoint(
                request.Origin,
                departure,
                headingDegrees: 90,
                boatSpeedKnots: 7,
                trueWindSpeedKnots: 14,
                trueWindDirectionDegrees: 120,
                cumulativeDistanceNauticalMiles: 0),
            new RoutePoint(
                request.Destination,
                departure.AddHours(12),
                headingDegrees: 90,
                boatSpeedKnots: 8,
                trueWindSpeedKnots: 16,
                trueWindDirectionDegrees: 130,
                cumulativeDistanceNauticalMiles: 100)
        };

        return new RouteResult(request, model, points, new RouteDiagnostics(1, 2, 1, 2));
    }
}
