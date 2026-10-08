using Navtool.Core;
using Xunit.Abstractions;

namespace Navtool.Infrastructure.Tests;

public sealed class NativeStrategicIntegrationTests(ITestOutputHelper output)
{
    [Theory]
    [InlineData(false, false)]
    [InlineData(true, false)]
    [InlineData(false, true)]
    [InlineData(true, true)]
    public void Managed_v8_preserves_losing_early_progress_that_arrives_earlier(bool mirrored, bool island)
    {
        var bridge = NativeIntegration.Bridge();
        var name = $"{(island ? "island" : "corridor")}-{(mirrored ? "north" : "south")}";
        var grib = NativeIntegration.Fixture(name + ".grib");
        var polarPath = NativeIntegration.Fixture("strategic.csv");
        if (bridge is null || grib is null || polarPath is null) return;
        using var forecast = bridge.LoadForecast(grib, maximumInterpolationGap: TimeSpan.FromHours(12));
        using var polar = bridge.LoadPolar(polarPath, BoatPolarFormat.NativeMatrix);
        var native = bridge.GetQualityDefaults();
        var optimization = new RouteOptimizationOptions(headingAugmentation: RouteHeadingAugmentation.None);
        RouteExclusionOptions? exclusions = null;
        if (island)
        {
            exclusions = new RouteExclusionOptions(
                [new RouteExclusionZone("synthetic-island", "strategic regression",
                    [new RouteExclusionPolygon(new RouteExclusionRing(
                        [new Coordinate(-.04, .12), new Coordinate(-.04, .55), new Coordinate(.04, .55), new Coordinate(.04, .12)]))])],
                new RouteProviderMetadata("island", "strategic regression", "1"));
            optimization = optimization.WithEnvironment(new RouteEnvironmentOptions(exclusions: exclusions));
        }
        var options = native with
        {
            Optimization = optimization,
            ArrivalRadiusNauticalMiles = 2,
            HardDuration = TimeSpan.FromHours(18),
            Search = NativeIntegration.Search(native.Search, bucketCapacity: 3, spatialBucket: 100,
                headingStep: 45, timeStep: TimeSpan.FromHours(1), intervals: false, strategic: true)
        };
        var request = new RouteRequest(name, new Coordinate(0, 0), new Coordinate(mirrored ? -.35 : .35, 1),
            forecast.Metadata.FirstValidAt, forecast.Metadata.FirstValidAt.AddHours(18));
        static bool EastOnly(Coordinate from, Coordinate to) => to.Longitude >= from.Longitude;
        var snapshots = new List<RouteCalculationSnapshot>();
        var watch = System.Diagnostics.Stopwatch.StartNew();
        var strategic = bridge.CalculateRoute(forecast, polar, request, ForecastModel.NoaaGfs, options, snapshots.Add, EastOnly);
        var greedy = bridge.CalculateRoute(forecast, polar, request, ForecastModel.NoaaGfs,
            options with { Search = NativeIntegration.Search(options.Search, bucketCapacity: 1, strategic: false) },
            isSegmentEligible: EastOnly);
        output.WriteLine($"{name}: strategic {strategic.ArrivalTime - request.DepartureTime}, greedy {greedy.ArrivalTime - request.DepartureTime}, wall {watch.Elapsed}");
        Assert.True(strategic.IsComplete);
        Assert.True(greedy.IsComplete);
        Assert.True(strategic.ArrivalTime.AddMinutes(30) < greedy.ArrivalTime);
        var losing = 0;
        for (var hour = 1; hour <= 5; hour++)
        {
            var time = request.DepartureTime.AddHours(hour);
            var selected = Assert.Single(strategic.Points.Where(point => point.Timestamp == time));
            var local = Assert.Single(greedy.Points.Where(point => point.Timestamp == time));
            Assert.Equal(6, selected.BoatSpeedKnots, 4);
            Assert.Equal(6, local.BoatSpeedKnots, 4);
            if (ForecastCorridor.GreatCircleDistanceNauticalMiles(selected.Location, request.Destination) >
                ForecastCorridor.GreatCircleDistanceNauticalMiles(local.Location, request.Destination) + 1) losing++;
        }
        Assert.True(losing >= 3);
        Assert.NotNull(strategic.NativeAudit);
        Assert.True(strategic.Diagnostics.EligibilityEvaluations > 0);
        Assert.True(strategic.Diagnostics.PrunedCandidates > 0);
        Assert.NotEmpty(snapshots);
        if (island)
        {
            var firstHour = strategic.Points.Single(point => point.Timestamp == request.DepartureTime.AddHours(1));
            Assert.True((mirrored ? -1 : 1) * firstHour.Location.Latitude < -.04);
        }
    }

    [Fact]
    public void Explicit_timed_heading_replay_uses_the_same_managed_boundary()
    {
        var bridge = NativeIntegration.Bridge();
        var grib = NativeIntegration.Fixture("constant.grib");
        var polarPath = NativeIntegration.Fixture("fast.csv");
        if (bridge is null || grib is null || polarPath is null) return;
        using var forecast = bridge.LoadForecast(grib);
        using var polar = bridge.LoadPolar(polarPath, BoatPolarFormat.NativeMatrix);
        var request = new RouteRequest("controlled-replay", new Coordinate(0, 0), new Coordinate(.2, 0),
            forecast.Metadata.FirstValidAt, forecast.Metadata.FirstValidAt.AddHours(10));
        var options = bridge.GetQualityDefaults();
        var route = bridge.EvaluateTimedActions(forecast, polar, request, ForecastModel.NoaaGfs, options,
            [new NativeTimedHeadingAction(0, TimeSpan.FromHours(2))]);
        Assert.True(route.IsComplete);
        Assert.NotEmpty(route.Points);
        Assert.All(route.Points.Skip(1), point => Assert.InRange(point.HeadingDegrees, 0, .001));
        Assert.Throws<ArgumentException>(() => bridge.EvaluateTimedActions(forecast, polar, request,
            ForecastModel.NoaaGfs, options, [new NativeTimedHeadingAction(360, TimeSpan.FromSeconds(1))]));
    }
}
