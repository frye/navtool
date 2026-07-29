using Navtool.Core;
using Navtool.Infrastructure;

namespace Navtool.Infrastructure.Tests;

public sealed class NativeRouterBridgeIntegrationTests
{
    [Fact]
    public void Native_contract_loads_metadata_samples_and_route_when_artifacts_are_available()
    {
        var configuredSample = Environment.GetEnvironmentVariable(
            "NAVTOOL_ROUTER_SAMPLE_GRIB");
        var repository = FindAncestor(AppContext.BaseDirectory, "Navtool.sln");
        var sample = !string.IsNullOrWhiteSpace(configuredSample)
            ? Path.GetFullPath(configuredSample)
            : repository is null
                ? string.Empty
                : Path.GetFullPath(
                    Path.Combine(repository, "..", "router-lib", "samples", "sample.grib"));
        if (!File.Exists(sample))
        {
            return;
        }

        NativeRouterBridge bridge;
        try
        {
            bridge = new NativeRouterBridge();
        }
        catch (NativeBridgeUnavailableException)
        {
            return;
        }

        using var forecast = bridge.LoadForecast(sample);
        Assert.Equal(3u, bridge.AbiVersion);
        Assert.True(forecast.Metadata.LatitudeCount > 0);
        Assert.True(forecast.Metadata.FirstValidAt < forecast.Metadata.LastValidAt);

        var bounds = new GeographicBounds(48, 48.5, -123.75, -123.25);
        var samples = bridge.SampleViewport(
            forecast,
            bounds,
            3,
            3,
            forecast.Metadata.FirstValidAt);
        Assert.Equal(9, samples.Length);
        Assert.All(samples, samplePoint => Assert.True(samplePoint.IsValid));

        var request = new RouteRequest(
            "native-integration",
            new Coordinate(48.25, -123.65),
            new Coordinate(48.25, -123.35),
            forecast.Metadata.FirstValidAt,
            forecast.Metadata.FirstValidAt.AddHours(10));
        var snapshots = new List<RouteCalculationSnapshot>();
        var route = bridge.CalculateRoute(
            forecast,
            request,
            ForecastModel.NoaaGfs,
            snapshots.Add);
        Assert.NotEmpty(route.Points);
        Assert.True(route.Diagnostics.GeneratedCandidates > 0);
        Assert.NotNull(bridge.StreamingProgressAvailable);
        if (bridge.StreamingProgressAvailable is true)
        {
            Assert.NotEmpty(snapshots);
            Assert.Equal(
                snapshots.Select(snapshot => snapshot.FrontierTime).Order(),
                snapshots.Select(snapshot => snapshot.FrontierTime));
            Assert.Equal(
                Enumerable.Range(1, snapshots.Count),
                snapshots.Select(snapshot => snapshot.Diagnostics.TimeSteps));
            Assert.All(snapshots, snapshot =>
            {
                Assert.NotEmpty(snapshot.FrontSegments);
                Assert.All(snapshot.FrontSegments, segment => Assert.NotEmpty(segment.Points));
                Assert.Contains(
                    snapshot.FrontSegments.SelectMany(segment => segment.Points),
                    point => point == snapshot.ProvisionalRoute[^1].Location);
                Assert.Equal(
                    snapshot.FrontierTime,
                    snapshot.ProvisionalRoute[^1].Timestamp);
            });
        }
        else
        {
            Assert.Empty(snapshots);
        }

        Assert.All(route.Points, point =>
        {
            Assert.True(point.HeadingDegrees is >= 0 and < 360);
            Assert.True(point.TrueWindDirectionDegrees is >= 0 and < 360);
        });

        var limitedRequest = new RouteRequest(
            "native-forecast-limited",
            new Coordinate(48.05, -123.70),
            new Coordinate(48.45, -123.30),
            forecast.Metadata.LastValidAt.AddHours(-1),
            forecast.Metadata.LastValidAt.AddHours(10));
        var limitedSnapshots = new List<RouteCalculationSnapshot>();
        var limitedRouteWithoutProgress = bridge.CalculateRoute(
            forecast,
            limitedRequest,
            ForecastModel.NoaaGfs);
        var limitedRoute = bridge.CalculateRoute(
            forecast,
            limitedRequest,
            ForecastModel.NoaaGfs,
            limitedSnapshots.Add);

        Assert.True(limitedRouteWithoutProgress.IsForecastLimited);
        Assert.Equal(limitedRoute.ArrivalTime, limitedRouteWithoutProgress.ArrivalTime);
        Assert.Equal(limitedRoute.Points[^1].Location, limitedRouteWithoutProgress.Points[^1].Location);
        Assert.True(limitedRoute.IsForecastLimited);
        Assert.NotEmpty(limitedSnapshots);
        Assert.Equal(limitedSnapshots[^1].ProvisionalRoute, limitedRoute.Points);
        Assert.Equal(limitedSnapshots[^1].FrontierTime, limitedRoute.ArrivalTime);
        Assert.True(limitedRoute.ArrivalTime <= forecast.Metadata.LastValidAt);
    }

    private static string? FindAncestor(string start, string marker)
    {
        var directory = new DirectoryInfo(start);
        while (directory is not null)
        {
            if (File.Exists(Path.Combine(directory.FullName, marker)))
            {
                return directory.FullName;
            }

            directory = directory.Parent;
        }

        return null;
    }
}
