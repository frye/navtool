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
        Assert.Equal(6u, bridge.AbiVersion);
        Assert.True(bridge.LandConstraintAvailable);
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
        Assert.Equal(LandAvoidanceStatus.NotEvaluated, route.LandAvoidance.Status);
        var eligibilityCalls = 0;
        var rejected = Assert.Throws<NativeRouterException>(() =>
            bridge.CalculateRoute(
                forecast,
                request,
                ForecastModel.NoaaGfs,
                (_, _) =>
                {
                    eligibilityCalls++;
                    return false;
                }));
        Assert.Equal(NativeRouterStatus.NoRoute, rejected.Status);
        Assert.True(eligibilityCalls > 0);
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
                Assert.NotEmpty(snapshot.EnvelopeSegments);
                Assert.All(snapshot.EnvelopeSegments, segment => Assert.NotEmpty(segment.Points));
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

        var latticeRequest = new RouteRequest(
            "native-lattice-integration",
            new Coordinate(48, -123.75),
            new Coordinate(48.5, -123.25),
            forecast.Metadata.FirstValidAt,
            forecast.Metadata.FirstValidAt.AddHours(10));
        var latticeOptions = new RouteOptimizationOptions(
            solver: RouteSolver.TimeDependentLattice,
            lattice: new RouteLatticeOptions(
                subdivisionLevel: 8,
                refinementLevels: 0,
                progressEveryExpansions: 1));
        var latticeSnapshots = new List<RouteCalculationSnapshot>();
        var latticeRoute = bridge.CalculateRoute(
            forecast,
            latticeRequest,
            ForecastModel.NoaaGfs,
            latticeOptions,
            latticeSnapshots.Add,
            null);
        Assert.Equal(RouteSolver.TimeDependentLattice, latticeRoute.Solver);
        Assert.NotNull(latticeRoute.LatticeDiagnostics);
        Assert.NotEmpty(latticeSnapshots);
        Assert.All(latticeSnapshots, snapshot =>
        {
            Assert.Equal(RouteSolver.TimeDependentLattice, snapshot.Solver);
            Assert.Empty(snapshot.EnvelopeSegments);
            Assert.Empty(snapshot.FrontSegments);
            Assert.NotEmpty(snapshot.SearchPoints);
            Assert.NotNull(snapshot.LatticeSearch);
        });

        using var cancellation = new CancellationTokenSource();
        var cancellationProgressCount = 0;
        Assert.Throws<OperationCanceledException>(() =>
            bridge.CalculateRoute(
                forecast,
                latticeRequest,
                ForecastModel.NoaaGfs,
                latticeOptions,
                _ =>
                {
                    cancellationProgressCount++;
                    cancellation.Cancel();
                },
                null,
                cancellation.Token));
        Assert.Equal(1, cancellationProgressCount);

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
        Assert.Equal(
            LandAvoidanceStatus.NotEvaluated,
            limitedRoute.LandAvoidance.Status);
        Assert.NotEmpty(limitedSnapshots);
        Assert.Equal(
            limitedSnapshots[^1].ProvisionalRoute.Select(point => point.Location),
            limitedRoute.Points.Select(point => point.Location));
        Assert.Equal(
            limitedSnapshots[^1].ProvisionalRoute.Select(point => point.Timestamp),
            limitedRoute.Points.Select(point => point.Timestamp));
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
