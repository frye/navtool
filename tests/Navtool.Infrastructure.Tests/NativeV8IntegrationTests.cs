using System.Buffers.Binary;
using Navtool.Core;

namespace Navtool.Infrastructure.Tests;

public sealed class NativeV8IntegrationTests
{
    [Theory]
    [InlineData(RoutingQuality.NativeFast)]
    [InlineData(RoutingQuality.NativeBalanced)]
    [InlineData(RoutingQuality.NativeAccurate)]
    public void Quality_names_map_explicitly_to_native_presets(RoutingQuality quality)
    {
        var bridge = NativeIntegration.Bridge();
        if (bridge is null) return;
        var defaults = bridge.GetQualityDefaults(quality);
        Assert.Equal(quality, defaults.Quality);
        var asset = new BoatAsset("demo", "Explicit demo", BoatAssetKind.Demo, BoatPolarFormat.Automatic,
            bridge.InspectDemoPolar());
        var resolved = bridge.ResolveRoutingOptions(new RoutingSetup(asset, quality, landSource: RoutingLandSource.None));
        Assert.Equal(quality, resolved.Quality);
        Assert.Equal(RoutePolarAngleInterpolation.MonotoneCubic, resolved.Optimization.PolarAngleInterpolation);
        Assert.Equal(RouteAbovePolarRangePolicy.NoSpeed, resolved.Optimization.AbovePolarRange);
    }

    [Fact]
    public void Expedition_format_uses_the_native_parser_without_fabricating_resolved_format()
    {
        var bridge = NativeIntegration.Bridge();
        if (bridge is null) return;
        using var directory = new TestDirectory();
        var path = Path.Combine(directory.Path, "expedition.pol");
        File.WriteAllText(path, "8 45 6 90 8 135 6\n16 45 7 90 10 135 7\n");
        var metadata = bridge.InspectPolar(path, BoatPolarFormat.Expedition);
        Assert.Equal(16, metadata.MaximumWindSpeedKnots);
        Assert.Null(metadata.ResolvedFormat);
    }

    [Fact]
    public void NoSpeed_policy_does_not_invent_boat_speed_above_polar_range()
    {
        var bridge = NativeIntegration.Bridge();
        var grib = NativeIntegration.Fixture("constant.grib");
        if (bridge is null || grib is null) return;
        using var directory = new TestDirectory();
        var path = Path.Combine(directory.Path, "low-range.csv");
        File.WriteAllText(path, "TWA/TWS,0,8\n0,0,1\n45,0,1\n90,0,1\n135,0,1\n180,0,1\n");
        using var polar = bridge.LoadPolar(path, BoatPolarFormat.NativeMatrix);
        using var forecast = bridge.LoadForecast(grib);
        var defaults = bridge.GetQualityDefaults();
        var options = defaults with
        {
            ArrivalRadiusNauticalMiles = .2,
            Search = NativeIntegration.Search(defaults.Search, minimumSpeed: 0),
            Optimization = defaults.Optimization.WithEnvironment(new RouteEnvironmentOptions(
                currents: RouteCurrentOptions.Uniform(0, 2, new RouteProviderMetadata("drift-current", "test", "1"))))
        };
        var request = new RouteRequest("native-drift", new Coordinate(0, 0), new Coordinate(.02, 0),
            forecast.Metadata.FirstValidAt, forecast.Metadata.FirstValidAt.AddHours(2));
        var failure = Assert.Throws<NativeRouterException>(() =>
            bridge.CalculateRoute(forecast, polar, request, ForecastModel.NoaaGfs, options));
        Assert.Equal(NativeRouterStatus.NoRoute, failure.Status);
    }

    [Fact]
    public void Native_maneuver_delay_preserves_zero_stw_current_drift_as_physical_points()
    {
        var bridge = NativeIntegration.Bridge();
        var grib = NativeIntegration.Fixture("constant.grib");
        var polarPath = NativeIntegration.Fixture("fast.csv");
        if (bridge is null || grib is null || polarPath is null) return;
        using var forecast = bridge.LoadForecast(grib);
        using var polar = bridge.LoadPolar(polarPath, BoatPolarFormat.NativeMatrix);
        var options = bridge.GetQualityDefaults() with
        {
            ArrivalRadiusNauticalMiles = 3,
            Optimization = new RouteOptimizationOptions(
                maneuver: new RouteManeuverOptions(TimeSpan.FromMinutes(10), TimeSpan.FromMinutes(10)),
                environment: new RouteEnvironmentOptions(
                    currents: RouteCurrentOptions.Uniform(1, 0, new RouteProviderMetadata("drift", "test", "1"))))
        };
        var request = new RouteRequest("maneuver-drift", new Coordinate(0, 0), new Coordinate(.2, .04),
            forecast.Metadata.FirstValidAt, forecast.Metadata.FirstValidAt.AddHours(4));
        var route = bridge.EvaluateTimedActions(forecast, polar, request, ForecastModel.NoaaGfs, options,
            [new NativeTimedHeadingAction(0, TimeSpan.FromMinutes(10)),
                new NativeTimedHeadingAction(180, TimeSpan.FromMinutes(20)),
                new NativeTimedHeadingAction(0, TimeSpan.FromHours(2))]);
        Assert.True(route.IsComplete);
        Assert.Contains(route.Points.Zip(route.Points.Skip(1)), pair =>
            pair.Second.BoatSpeedKnots == 0 && pair.Second.Environment?.SpeedOverGroundKnots > 0 &&
            pair.First.Location != pair.Second.Location);
    }

    [Fact]
    public void Native_forecast_policy_checks_real_gaps_and_preserves_single_time_audit()
    {
        var bridge = NativeIntegration.Bridge();
        var constant = NativeIntegration.Fixture("constant.grib");
        var single = NativeIntegration.Fixture("single.grib");
        if (bridge is null || constant is null || single is null) return;
        using var legal = bridge.LoadForecast(constant, maximumInterpolationGap: TimeSpan.FromHours(6));
        Assert.Equal(TimeSpan.FromHours(1), legal.Metadata.MinimumTimeSpacing);
        Assert.Equal(TimeSpan.FromHours(6), legal.Metadata.MaximumTimeSpacing);
        Assert.Equal(8, legal.Metadata.ValidTimes.Length);
        Assert.Equal(legal.Metadata.InitializedAt, legal.Metadata.FirstValidAt);
        var gap = Assert.Throws<NativeRouterException>(() =>
            bridge.LoadForecast(constant, maximumInterpolationGap: TimeSpan.FromHours(3)));
        Assert.Equal(RoutingFailureKind.InvalidForecast, gap.Kind);
        using var one = bridge.LoadForecast(single);
        Assert.Single(one.Metadata.ValidTimes);
        Assert.Null(one.Metadata.MinimumTimeSpacing);
        Assert.Null(one.Metadata.MaximumTimeSpacing);
        Assert.Equal(one.Metadata.FirstValidAt, one.Metadata.LastValidAt);
        using var demo = bridge.CreateDemoPolar();
        var request = new RouteRequest("one-time-arrival", new Coordinate(0, 0), new Coordinate(0, .001),
            one.Metadata.FirstValidAt, one.Metadata.FirstValidAt.AddHours(1));
        Assert.Single(bridge.CalculateRoute(one, demo, request, ForecastModel.NoaaGfs, bridge.GetQualityDefaults()).Points);
    }

    [Fact]
    public void Native_presets_demo_import_factor_arrival_and_current_are_applied_through_v8()
    {
        var bridge = NativeIntegration.Bridge();
        var sample = NativeIntegration.Sample();
        if (bridge is null || sample is null) return;
        using var directory = new TestDirectory();
        using var forecast = bridge.LoadForecast(sample);
        using var demo = bridge.CreateDemoPolar();
        var defaults = bridge.GetQualityDefaults();
        Assert.Equal(RouteAbovePolarRangePolicy.NoSpeed, defaults.Optimization.AbovePolarRange);
        Assert.Equal(1, defaults.PerformanceFactor);
        Assert.False(string.IsNullOrWhiteSpace(bridge.BuildIdentity.SourceRevision));
        var setup = new RoutingSetup(new BoatAsset("demo", "Explicit demonstration boat", BoatAssetKind.Demo,
            BoatPolarFormat.Automatic, demo.Metadata), landSource: RoutingLandSource.None);
        var standard = bridge.ResolveRoutingOptions(setup);
        Assert.Equal(RoutePolarAngleInterpolation.MonotoneCubic, standard.Optimization.PolarAngleInterpolation);
        Assert.Equal(System.Text.Json.JsonSerializer.Serialize(defaults.Search), System.Text.Json.JsonSerializer.Serialize(standard.Search));
        var path = Path.Combine(directory.Path, "slow.polar");
        File.WriteAllText(path, "TWA/TWS,0,6,12,20,50\n0,0,0,0,0,0\n45,0,2,2,2,2\n90,0,2,2,2,2\n135,0,2,2,2,2\n180,0,2,2,2,2\n");
        using var slow = bridge.LoadPolar(path, BoatPolarFormat.NativeMatrix);
        var request = new RouteRequest("v8-boat", new Coordinate(48.25, -123.65), new Coordinate(48.25, -123.35),
            forecast.Metadata.FirstValidAt, forecast.Metadata.FirstValidAt.AddHours(10));
        var options = standard with { HardDuration = TimeSpan.FromHours(12) };
        var slowRoute = bridge.CalculateRoute(forecast, slow, request, ForecastModel.NoaaGfs, options);
        var fastRoute = bridge.CalculateRoute(forecast, slow, request, ForecastModel.NoaaGfs, options with { PerformanceFactor = 2 });
        Assert.True(slowRoute.IsComplete);
        Assert.True(fastRoute.IsComplete);
        Assert.True(fastRoute.ArrivalTime < slowRoute.ArrivalTime);
        Assert.Contains(slowRoute.Points.Skip(1), point => Math.Abs(point.BoatSpeedKnots - 2) < .01);
        Assert.Contains(fastRoute.Points.Skip(1), point => Math.Abs(point.BoatSpeedKnots - 4) < .01);
        var snapshots = new List<RouteCalculationSnapshot>();
        var withCurrent = options with
        {
            Optimization = options.Optimization.WithEnvironment(new RouteEnvironmentOptions(
                currents: RouteCurrentOptions.Uniform(1, 0, new RouteProviderMetadata("uniform", "test", "1"))))
        };
        var currentRoute = bridge.CalculateRoute(forecast, slow, request, ForecastModel.NoaaGfs, withCurrent, snapshots.Add);
        Assert.True(currentRoute.IsComplete);
        Assert.Contains(snapshots.SelectMany(snapshot => snapshot.ProvisionalRoute), point =>
            point.Environment?.CurrentEastKnots == 1 && point.Environment.PolarWindSpeedKnots.HasValue);
        Assert.All(snapshots, snapshot => Assert.NotNull(snapshot.Diagnostics.FutureProbeMisses));
        Assert.NotNull(currentRoute.NativeAudit);
        var alreadyThere = new RouteRequest("arrival-area", request.Origin, new Coordinate(48.25, -123.649),
            request.DepartureTime, request.LatestArrivalTime);
        var arrival = bridge.CalculateRoute(forecast, demo, alreadyThere, ForecastModel.NoaaGfs, options);
        Assert.Single(arrival.Points);
        Assert.Equal(request.Origin, arrival.Points[0].Location);
    }

    [Fact]
    public void Native_invalid_polar_resource_exhaustion_and_cancel_never_promote_candidates()
    {
        var bridge = NativeIntegration.Bridge();
        var sample = NativeIntegration.Sample();
        if (bridge is null || sample is null) return;
        using var directory = new TestDirectory();
        var invalid = Path.Combine(directory.Path, "invalid.pol");
        File.WriteAllText(invalid, "not a polar");
        Assert.Equal(RoutingFailureKind.InvalidBoat,
            Assert.Throws<NativeRouterException>(() => bridge.LoadPolar(invalid)).Kind);
        using var forecast = bridge.LoadForecast(sample);
        using var polar = bridge.CreateDemoPolar();
        var request = new RouteRequest("limited", new Coordinate(48.25, -123.65), new Coordinate(48.25, -123.35),
            forecast.Metadata.FirstValidAt, forecast.Metadata.FirstValidAt.AddHours(10));
        var options = bridge.GetQualityDefaults();
        var limited = options with { Search = NativeIntegration.Search(options.Search, generated: 1) };
        var exhausted = Assert.Throws<NativeRouterException>(() =>
            bridge.CalculateRoute(forecast, polar, request, ForecastModel.NoaaGfs, limited));
        Assert.True(exhausted.Kind == RoutingFailureKind.ResourceLimit, exhausted.ToString());
        using var cancellation = new CancellationTokenSource();
        var snapshots = 0;
        Assert.Throws<OperationCanceledException>(() => bridge.CalculateRoute(forecast, polar, request, ForecastModel.NoaaGfs,
            options, _ => { snapshots++; cancellation.Cancel(); }, cancellationToken: cancellation.Token));
        Assert.Equal(1, snapshots);
        polar.Dispose();
        Assert.Throws<ObjectDisposedException>(() => bridge.CalculateRoute(forecast, polar, request, ForecastModel.NoaaGfs, options));
    }

    [Fact]
    public void Native_gshhg_estimate_source_fingerprint_and_route_are_real()
    {
        var bridge = NativeIntegration.Bridge();
        var sample = NativeIntegration.Sample();
        if (bridge is null || sample is null) return;
        using var directory = new TestDirectory();
        var source = Path.Combine(directory.Path, "regional.b");
        WriteGshhgIsland(source);
        var options = new RegionalLandOptions(new GeographicBounds(48, 48.5, -124, -123), 5, 10);
        var estimate = bridge.EstimateRegionalLand(options);
        Assert.InRange(estimate.GridNodes, 4UL, options.MaximumGridNodes);
        Assert.True(estimate.NativeNumericalAllowanceNauticalMiles > options.ResolutionNauticalMiles);
        Assert.True(estimate.HaloSouth < options.Bounds.South);
        Assert.True(estimate.HaloWestUnwrapped < options.Bounds.West);
        using var land = bridge.LoadRegionalLand(source, options);
        Assert.Equal(NativeRouterBridge.FingerprintFile(source), land.SourceFingerprint);
        Assert.False(string.IsNullOrWhiteSpace(land.NativeMetadataJson));
        using var forecast = bridge.LoadForecast(sample);
        using var polar = bridge.CreateDemoPolar();
        var request = new RouteRequest("gshhg", new Coordinate(48.25, -123.65), new Coordinate(48.25, -123.35),
            forecast.Metadata.FirstValidAt, forecast.Metadata.FirstValidAt.AddHours(10));
        var route = bridge.CalculateRoute(forecast, polar, request, ForecastModel.NoaaGfs,
            bridge.GetQualityDefaults(), land: land);
        Assert.True(route.IsComplete);
        Assert.True(route.NativeAudit!.NativeLandmaskApplied);
        File.AppendAllText(source, "changed");
        var failure = Assert.Throws<RoutingException>(() => bridge.LoadRegionalLand(source, options, land.SourceFingerprint));
        Assert.Equal(RoutingFailureKind.MissingRequiredSource, failure.Kind);
    }

    [Theory]
    [InlineData(-86, -84, 0, 1)]
    [InlineData(0, 1, -100, 100)]
    public void Gshhg_invalid_domains_are_rejected_before_native_work(double south, double north, double west, double east)
    {
        var options = new RegionalLandOptions(new GeographicBounds(south, north, west, east), 5);
        Assert.Throws<ArgumentOutOfRangeException>(() => options.ToNative());
    }

    [Fact]
    public void Gshhg_preview_preserves_unwrapped_dateline_halo_and_rejects_unsupported_polar_halo()
    {
        var bridge = NativeIntegration.Bridge();
        if (bridge is null) return;
        var options = new RegionalLandOptions(new GeographicBounds(-1, 1, 179, -179), 10, 30);
        var estimate = bridge.EstimateRegionalLand(options);
        Assert.True(estimate.HaloEastUnwrapped > 181);
        Assert.True(estimate.HaloWestUnwrapped < 179);
        var polar = new RegionalLandOptions(new GeographicBounds(84, 85, 0, 1), 10, 600);
        Assert.Equal(RoutingFailureKind.InvalidConfiguration,
            Assert.Throws<NativeRouterException>(() => bridge.EstimateRegionalLand(polar)).Kind);
        Assert.Throws<ArgumentOutOfRangeException>(() =>
            (options with { MaximumGridNodes = 250_001 }).ToNative());
    }

    internal static void WriteGshhgIsland(string path)
    {
        // Native GSHHG binary format: 11 big-endian int32 header words followed by lon/lat microdegrees.
        var vertices = new (int Longitude, int Latitude)[]
        {
            (236_050_000, 48_050_000), (236_100_000, 48_050_000), (236_100_000, 48_100_000),
            (236_050_000, 48_100_000), (236_050_000, 48_050_000)
        };
        int[] header = [1, vertices.Length, 1 | (12 << 8), 236_050_000, 236_100_000, 48_050_000, 48_100_000, 100, 100, -1, -1];
        using var stream = File.Create(path);
        Span<byte> bytes = stackalloc byte[4];
        foreach (var value in header)
        {
            BinaryPrimitives.WriteInt32BigEndian(bytes, value);
            stream.Write(bytes);
        }
        foreach (var vertex in vertices)
        {
            BinaryPrimitives.WriteInt32BigEndian(bytes, vertex.Longitude); stream.Write(bytes);
            BinaryPrimitives.WriteInt32BigEndian(bytes, vertex.Latitude); stream.Write(bytes);
        }
    }
}
