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

    [Theory]
    [InlineData(90, 6, 15, 180, 68.19859051364824)]
    [InlineData(90, 6, 15, 0, -68.19859051364818)]
    [InlineData(90, 6, 0, 0, 0)]
    [InlineData(90, 6, 15, 270, 180)]
    [InlineData(350, 5, 20, 20, 24.133261210456055)]
    public void Route_point_derives_apparent_wind_angle(
        double headingDegrees,
        double boatSpeedKnots,
        double trueWindSpeedKnots,
        double trueWindDirectionDegrees,
        double expectedSignedAngle)
    {
        var point = new RoutePoint(
            new Coordinate(42, -60),
            new DateTimeOffset(2026, 7, 15, 3, 0, 0, TimeSpan.Zero),
            headingDegrees,
            boatSpeedKnots,
            trueWindSpeedKnots,
            trueWindDirectionDegrees,
            81.2);

        Assert.Equal(expectedSignedAngle, point.ApparentWindAngleSignedDegrees, 6);
        Assert.Equal(Math.Abs(expectedSignedAngle), point.ApparentWindAngleDegrees, 6);
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

    [Fact]
    public void Calculation_snapshot_preserves_frontier_route_and_diagnostics()
    {
        var time = new DateTimeOffset(2026, 7, 15, 3, 0, 0, TimeSpan.Zero);
        var diagnostics = new RouteDiagnostics(100, 400, 80, 3);
        var snapshot = new RouteCalculationSnapshot(
            time,
            new[]
            {
                new Coordinate(42, -60),
                new Coordinate(43, -59)
            },
            new[]
            {
                new RoutePoint(new Coordinate(41, -61), time.AddHours(-1), 90, 7, 20, 180, 0),
                new RoutePoint(new Coordinate(42, -60), time, 90, 7, 20, 180, 7)
            },
            diagnostics);

        Assert.Equal(time, snapshot.FrontierTime);
        Assert.Equal(2, snapshot.Frontier.Length);
        Assert.Equal(2, snapshot.ProvisionalRoute.Length);
        Assert.Same(diagnostics, snapshot.Diagnostics);
        Assert.Throws<NotSupportedException>(() =>
            ((IList<Coordinate>)snapshot.Frontier).Add(new Coordinate(44, -58)));
    }

    [Fact]
    public void Calculation_snapshot_rejects_empty_or_misaligned_native_data()
    {
        var time = new DateTimeOffset(2026, 7, 15, 3, 0, 0, TimeSpan.Zero);
        var point = new RoutePoint(new Coordinate(42, -60), time.AddMinutes(-1), 90, 7, 20, 180, 0);
        var diagnostics = new RouteDiagnostics(1, 2, 1, 1);

        Assert.Throws<ArgumentException>(() =>
            new RouteCalculationSnapshot(time, Array.Empty<Coordinate>(), new[] { point }, diagnostics));
        Assert.Throws<ArgumentException>(() =>
            new RouteCalculationSnapshot(time, new[] { point.Location }, Array.Empty<RoutePoint>(), diagnostics));
        Assert.Throws<ArgumentException>(() =>
            new RouteCalculationSnapshot(time, new[] { point.Location }, new[] { point }, diagnostics));
    }

    [Fact]
    public void Route_result_accepts_arrival_after_the_requested_passage_target()
    {
        var departure = new DateTimeOffset(2026, 7, 15, 0, 0, 0, TimeSpan.Zero);
        var request = new RouteRequest(
            "route-over",
            new Coordinate(40, -60),
            new Coordinate(45, -55),
            departure,
            departure.AddHours(6));
        var points = new[]
        {
            new RoutePoint(request.Origin, departure, 45, 6, 15, 200, 0),
            // Achieved arrival lands two hours past the requested target.
            new RoutePoint(request.Destination, departure.AddHours(8), 45, 6, 15, 200, 40)
        };

        var result = new RouteResult(request, ForecastModel.NoaaGfs, points, new RouteDiagnostics(1, 2, 1, 2));

        Assert.Equal(departure.AddHours(8), result.ArrivalTime);
        Assert.True(result.ExceedsRequestedArrival);
    }

    [Fact]
    public void Route_result_reports_arrival_within_the_requested_passage_target()
    {
        var departure = new DateTimeOffset(2026, 7, 15, 0, 0, 0, TimeSpan.Zero);
        var request = new RouteRequest(
            "route-under",
            new Coordinate(40, -60),
            new Coordinate(45, -55),
            departure,
            departure.AddHours(10));
        var points = new[]
        {
            new RoutePoint(request.Origin, departure, 45, 6, 15, 200, 0),
            new RoutePoint(request.Destination, departure.AddHours(10), 45, 6, 15, 200, 40)
        };

        var result = new RouteResult(request, ForecastModel.NoaaGfs, points, new RouteDiagnostics(1, 2, 1, 2));

        Assert.False(result.ExceedsRequestedArrival);
    }

    [Fact]
    public void Route_result_still_rejects_empty_and_disordered_points()
    {
        var departure = new DateTimeOffset(2026, 7, 15, 0, 0, 0, TimeSpan.Zero);
        var request = new RouteRequest(
            "route-bad",
            new Coordinate(40, -60),
            new Coordinate(45, -55),
            departure,
            departure.AddHours(10));
        var diagnostics = new RouteDiagnostics(1, 2, 1, 2);

        Assert.Throws<ArgumentException>(() =>
            new RouteResult(request, ForecastModel.NoaaGfs, Array.Empty<RoutePoint>(), diagnostics));
        // Timestamp descending.
        Assert.Throws<ArgumentException>(() => new RouteResult(
            request,
            ForecastModel.NoaaGfs,
            new[]
            {
                new RoutePoint(request.Origin, departure.AddHours(2), 45, 6, 15, 200, 0),
                new RoutePoint(request.Destination, departure.AddHours(1), 45, 6, 15, 200, 10)
            },
            diagnostics));
        // Cumulative distance descending.
        Assert.Throws<ArgumentException>(() => new RouteResult(
            request,
            ForecastModel.NoaaGfs,
            new[]
            {
                new RoutePoint(request.Origin, departure, 45, 6, 15, 200, 20),
                new RoutePoint(request.Destination, departure.AddHours(1), 45, 6, 15, 200, 10)
            },
            diagnostics));
    }

    [Fact]
    public void Route_request_normalizes_departure_to_whole_seconds()
    {
        var departure = new DateTimeOffset(2026, 7, 15, 0, 0, 0, 456, TimeSpan.Zero);
        var request = new RouteRequest(
            "route-precision",
            new Coordinate(40, -60),
            new Coordinate(45, -55),
            departure,
            departure.AddHours(10));

        var normalizedDeparture = new DateTimeOffset(2026, 7, 15, 0, 0, 0, TimeSpan.Zero);
        Assert.Equal(normalizedDeparture, request.DepartureTime);

        // A first point at the normalized departure second is accepted.
        var accepted = new RouteResult(
            request,
            ForecastModel.NoaaGfs,
            new[]
            {
                new RoutePoint(request.Origin, normalizedDeparture, 45, 6, 15, 200, 0),
                new RoutePoint(request.Destination, normalizedDeparture.AddHours(5), 45, 6, 15, 200, 20)
            },
            new RouteDiagnostics(1, 2, 1, 2));
        Assert.Equal(normalizedDeparture, accepted.Points[0].Timestamp);

        // A first point strictly before departure is still rejected.
        Assert.Throws<ArgumentException>(() => new RouteResult(
            request,
            ForecastModel.NoaaGfs,
            new[]
            {
                new RoutePoint(request.Origin, normalizedDeparture.AddSeconds(-1), 45, 6, 15, 200, 0),
                new RoutePoint(request.Destination, normalizedDeparture.AddHours(5), 45, 6, 15, 200, 20)
            },
            new RouteDiagnostics(1, 2, 1, 2)));
    }
}
