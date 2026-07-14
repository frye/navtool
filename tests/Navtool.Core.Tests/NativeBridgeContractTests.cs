namespace Navtool.Core.Tests;

public sealed class NativeBridgeContractTests
{
    [Fact]
    public void Acquisition_exposes_local_artifact_run_provider_and_cache_without_weather_grid()
    {
        var from = new DateTimeOffset(2026, 7, 15, 0, 0, 0, TimeSpan.Zero);
        var request = new ForecastRequest(
            ForecastModel.NoaaGfs,
            new GeographicBounds(30, 50, -80, -40),
            from,
            from.AddDays(2));
        var run = new ForecastRun(ForecastProvider.Noaa, ForecastModel.NoaaGfs, from.AddHours(-6));
        var artifact = new LocalGribArtifact(
            "/var/lib/navtool/gfs-20260715-00.grib2",
            4_096,
            from.AddMinutes(-5));
        var cache = new CacheMetadata("gfs/run-00", from.AddMinutes(-10), from.AddHours(1));

        var acquisition = new ForecastAcquisition(
            request,
            run,
            artifact,
            ForecastAcquisitionSource.Cache,
            cache);

        Assert.Equal(ForecastProvider.Noaa, acquisition.Provider);
        Assert.Equal(run, acquisition.Run);
        Assert.Equal("/var/lib/navtool/gfs-20260715-00.grib2", acquisition.Artifact.Path);
        Assert.Equal(4_096, acquisition.Artifact.LengthBytes);
        Assert.Equal(cache, acquisition.Cache);
        Assert.Equal(ForecastAcquisitionSource.Cache, acquisition.Source);
    }

    [Fact]
    public void Local_artifact_requires_an_absolute_path_and_valid_length()
    {
        Assert.Throws<ArgumentException>(() => new LocalGribArtifact("relative/file.grib2"));
        Assert.Throws<ArgumentOutOfRangeException>(() =>
            new LocalGribArtifact("/var/lib/navtool/file.grib2", -1));
    }

    [Fact]
    public void Route_point_carries_native_detail_values()
    {
        var point = new RoutePoint(
            new Coordinate(42, -60),
            new DateTimeOffset(2026, 7, 15, 3, 0, 0, TimeSpan.Zero),
            123.5,
            7.25,
            19.75,
            245.5,
            81.2);

        Assert.Equal(123.5, point.HeadingDegrees);
        Assert.Equal(7.25, point.BoatSpeedKnots);
        Assert.Equal(19.75, point.TrueWindSpeedKnots);
        Assert.Equal(245.5, point.TrueWindDirectionDegrees);
        Assert.Equal(81.2, point.CumulativeDistanceNauticalMiles);
    }

    [Fact]
    public void Route_point_rejects_invalid_native_detail_values()
    {
        var location = new Coordinate(42, -60);
        var timestamp = new DateTimeOffset(2026, 7, 15, 3, 0, 0, TimeSpan.Zero);

        Assert.Throws<ArgumentOutOfRangeException>(() =>
            new RoutePoint(location, timestamp, 360, 7, 20, 180, 10));
        Assert.Throws<ArgumentOutOfRangeException>(() =>
            new RoutePoint(location, timestamp, 90, -1, 20, 180, 10));
        Assert.Throws<ArgumentOutOfRangeException>(() =>
            new RoutePoint(location, timestamp, 90, 7, double.NaN, 180, 10));
        Assert.Throws<ArgumentOutOfRangeException>(() =>
            new RoutePoint(location, timestamp, 90, 7, 20, -1, 10));
        Assert.Throws<ArgumentOutOfRangeException>(() =>
            new RoutePoint(location, timestamp, 90, 7, 20, 180, -1));
    }

    [Fact]
    public void Diagnostics_expose_native_search_counters()
    {
        var diagnostics = new RouteDiagnostics(1_000, 4_000, 800, 48, TimeSpan.FromSeconds(2));

        Assert.Equal(1_000, diagnostics.ExpandedNodes);
        Assert.Equal(4_000, diagnostics.GeneratedCandidates);
        Assert.Equal(800, diagnostics.RetainedCandidates);
        Assert.Equal(48, diagnostics.TimeSteps);
        Assert.Equal(TimeSpan.FromSeconds(2), diagnostics.CalculationDuration);
    }
}
