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
    [InlineData(90, 6, 15, 180, 68.19859051364824, 16.15549442140351)]
    [InlineData(90, 6, 15, 0, -68.19859051364818, 16.15549442140351)]
    [InlineData(90, 6, 0, 0, 0, 6)]
    [InlineData(90, 6, 15, 270, 180, 9)]
    [InlineData(90, 6, 6, 270, 0, 0)]
    [InlineData(350, 5, 20, 20, 24.133261210456055, 24.458231349729438)]
    public void Route_point_derives_apparent_wind(
        double headingDegrees,
        double boatSpeedKnots,
        double trueWindSpeedKnots,
        double trueWindDirectionDegrees,
        double expectedSignedAngle,
        double expectedSpeed)
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
        Assert.Equal(expectedSpeed, point.ApparentWindSpeedKnots, 6);
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
        var envelope = new[]
        {
            new RouteCalculationEnvelopeSegment(
                new[]
                {
                    new Coordinate(41.5, -60.5),
                    new Coordinate(42, -60),
                    new Coordinate(43, -59)
                },
                closed: false)
        };
        var snapshot = new RouteCalculationSnapshot(
            time,
            envelope,
            new[]
            {
                new RouteCalculationFrontSegment(
                    new[]
                    {
                        new Coordinate(42, -60),
                        new Coordinate(43, -59)
                    })
            },
            new[]
            {
                new RoutePoint(new Coordinate(41, -61), time.AddHours(-1), 90, 7, 20, 180, 0),
                new RoutePoint(new Coordinate(42, -60), time, 90, 7, 20, 180, 7)
            },
            diagnostics);

        Assert.Equal(time, snapshot.FrontierTime);
        Assert.Single(snapshot.EnvelopeSegments);
        Assert.False(snapshot.EnvelopeSegments[0].Closed);
        Assert.Single(snapshot.FrontSegments);
        Assert.Equal(2, snapshot.FrontSegments[0].Points.Length);
        Assert.Equal(2, snapshot.ProvisionalRoute.Length);
        Assert.Same(diagnostics, snapshot.Diagnostics);
        Assert.Throws<NotSupportedException>(() =>
            ((IList<Coordinate>)snapshot.FrontSegments[0].Points).Add(new Coordinate(44, -58)));
        Assert.Throws<NotSupportedException>(() =>
            ((IList<Coordinate>)snapshot.EnvelopeSegments[0].Points).Add(new Coordinate(44, -58)));
    }

    [Fact]
    public void Calculation_snapshot_rejects_empty_or_misaligned_native_data()
    {
        var time = new DateTimeOffset(2026, 7, 15, 3, 0, 0, TimeSpan.Zero);
        var point = new RoutePoint(new Coordinate(42, -60), time.AddMinutes(-1), 90, 7, 20, 180, 0);
        var diagnostics = new RouteDiagnostics(1, 2, 1, 1);
        var envelope = new[]
        {
            new RouteCalculationEnvelopeSegment(new[] { point.Location }, closed: false)
        };
        var front = new[]
        {
            new RouteCalculationFrontSegment(new[] { point.Location })
        };

        Assert.Throws<ArgumentException>(() =>
            new RouteCalculationSnapshot(
                time,
                Array.Empty<RouteCalculationEnvelopeSegment>(),
                front,
                new[] { point },
                diagnostics));
        Assert.Throws<ArgumentException>(() =>
            new RouteCalculationSnapshot(
                time,
                envelope,
                Array.Empty<RouteCalculationFrontSegment>(),
                new[] { point },
                diagnostics));
        Assert.Throws<ArgumentException>(() =>
            new RouteCalculationSnapshot(
                time,
                envelope,
                front,
                Array.Empty<RoutePoint>(),
                diagnostics));
        Assert.Throws<ArgumentException>(() =>
            new RouteCalculationSnapshot(
                time,
                envelope,
                front,
                new[] { point },
                diagnostics));
    }

    [Fact]
    public void Lattice_snapshot_accepts_search_progress_ahead_of_provisional_route()
    {
        var progressTime = new DateTimeOffset(2026, 7, 15, 3, 0, 0, TimeSpan.Zero);
        var routeTime = progressTime.AddMinutes(-30);
        var search = new Coordinate(42.5, -59.5);
        var snapshot = new RouteCalculationSnapshot(
            progressTime,
            RouteSolver.TimeDependentLattice,
            Array.Empty<RouteCalculationEnvelopeSegment>(),
            Array.Empty<RouteCalculationFrontSegment>(),
            new[] { search },
            new[]
            {
                new RoutePoint(new Coordinate(41, -61), routeTime.AddHours(-1), 90, 7, 20, 180, 0),
                new RoutePoint(new Coordinate(42, -60), routeTime, 90, 7, 20, 180, 7)
            },
            new RouteDiagnostics(100, 400, 80, 3),
            new RouteLatticeSearchProgress(50, 20, 120, 1, 5));

        Assert.Equal(RouteSolver.TimeDependentLattice, snapshot.Solver);
        Assert.Equal(search, Assert.Single(snapshot.SearchPoints));
        Assert.Empty(snapshot.EnvelopeSegments);
        Assert.Empty(snapshot.FrontSegments);
        Assert.Equal(routeTime, snapshot.ProvisionalRoute[^1].Timestamp);
        Assert.NotNull(snapshot.LatticeSearch);
    }

    [Fact]
    public void Lattice_snapshot_accepts_provisional_route_ahead_of_search_progress()
    {
        var progressTime = new DateTimeOffset(2026, 7, 15, 3, 0, 0, TimeSpan.Zero);
        var routeTime = progressTime.AddMinutes(30);
        var snapshot = new RouteCalculationSnapshot(
            progressTime,
            RouteSolver.TimeDependentLattice,
            Array.Empty<RouteCalculationEnvelopeSegment>(),
            Array.Empty<RouteCalculationFrontSegment>(),
            new[] { new Coordinate(42.5, -59.5) },
            new[]
            {
                new RoutePoint(new Coordinate(41, -61), progressTime.AddHours(-1), 90, 7, 20, 180, 0),
                new RoutePoint(new Coordinate(42, -60), routeTime, 90, 7, 20, 180, 7)
            },
            new RouteDiagnostics(100, 400, 80, 3),
            new RouteLatticeSearchProgress(50, 20, 120, 1, 5));

        Assert.Equal(routeTime, snapshot.ProvisionalRoute[^1].Timestamp);
        Assert.Equal(progressTime, snapshot.FrontierTime);
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
    public void Route_result_preserves_land_avoidance_status()
    {
        var departure = new DateTimeOffset(2026, 7, 15, 0, 0, 0, TimeSpan.Zero);
        var request = new RouteRequest(
            "route-land-status",
            new Coordinate(40, -60),
            new Coordinate(45, -55),
            departure,
            departure.AddHours(10));
        var warning = new RouteLandAvoidance(
            LandAvoidanceStatus.RouterUnsupported,
            "Land avoidance was not applied.");
        var result = new RouteResult(
            request,
            ForecastModel.NoaaGfs,
            new[]
            {
                new RoutePoint(request.Origin, departure, 45, 6, 15, 200, 0),
                new RoutePoint(request.Destination, departure.AddHours(8), 45, 6, 15, 200, 40)
            },
            new RouteDiagnostics(1, 2, 1, 2),
            warning);

        Assert.Same(warning, result.LandAvoidance);
        Assert.True(result.LandAvoidance.HasWarning);
        Assert.False(result.LandAvoidance.IsApplied);
    }

    [Fact]
    public void Adding_land_avoidance_preserves_forecast_limited_completion()
    {
        var departure = new DateTimeOffset(2026, 7, 15, 0, 0, 0, TimeSpan.Zero);
        var request = new RouteRequest(
            "route-partial-land-status",
            new Coordinate(40, -60),
            new Coordinate(45, -55),
            departure,
            departure.AddHours(10));
        var result = new RouteResult(
            request,
            ForecastModel.NoaaGfs,
            new[]
            {
                new RoutePoint(request.Origin, departure, 45, 6, 15, 200, 0),
                new RoutePoint(new Coordinate(42, -58), departure.AddHours(8), 45, 6, 15, 200, 20)
            },
            new RouteDiagnostics(1, 2, 1, 2),
            RouteCompletion.ForecastExhausted);

        var updated = result.WithLandAvoidance(new RouteLandAvoidance(
            LandAvoidanceStatus.RouterUnsupported,
            "Land avoidance was not applied."));

        Assert.True(updated.IsForecastLimited);
        Assert.Equal(LandAvoidanceStatus.RouterUnsupported, updated.LandAvoidance.Status);
    }

    [Fact]
    public void Duration_limited_route_is_partial_but_not_forecast_limited()
    {
        var departure = new DateTimeOffset(2026, 7, 15, 0, 0, 0, TimeSpan.Zero);
        var request = new RouteRequest(
            "route-duration-limited",
            new Coordinate(40, -60),
            new Coordinate(45, -55),
            departure,
            departure.AddHours(10));
        var result = new RouteResult(
            request,
            ForecastModel.NoaaGfs,
            new[]
            {
                new RoutePoint(request.Origin, departure, 45, 6, 15, 200, 0),
                new RoutePoint(new Coordinate(42, -58), departure.AddHours(8), 45, 6, 15, 200, 20)
            },
            new RouteDiagnostics(1, 2, 1, 2),
            RouteCompletion.DurationExhausted);

        Assert.True(result.IsPartial);
        Assert.True(result.IsDurationLimited);
        Assert.False(result.IsForecastLimited);
        Assert.False(result.IsComplete);
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

    [Fact]
    public void Lattice_diagnostics_stage25_fields_default_to_zero_and_none()
    {
        var d = new RouteLatticeDiagnostics(10, 2, 8, 1, 3, 2, 4, false);

        Assert.Equal(0L, d.ReRelaxedLabels);
        Assert.Equal(0L, d.StaleQueueEntries);
        Assert.Equal(0L, d.ActiveCells);
        Assert.Equal(0L, d.ActiveFaces);
        Assert.Equal(0.0, d.AcceptedCorridorWidthNauticalMiles);
        Assert.Equal(0, d.DisconnectedRefinements);
        Assert.Equal(0, d.RegressedRefinements);
        Assert.Equal(LatticeRefinementFallbackReason.None, d.FallbackReason);
    }

    [Fact]
    public void Lattice_diagnostics_stage25_fields_are_stored_and_exposed()
    {
        var d = new RouteLatticeDiagnostics(
            settledLabels: 100,
            queuedLabels: 20,
            relaxedLabels: 300,
            waitTransitions: 4,
            refinementRuns: 2,
            acceptedRefinements: 1,
            subdivisionLevel: 4,
            refinementFallback: true,
            reRelaxedLabels: 50,
            staleQueueEntries: 10,
            activeCells: 7,
            activeFaces: 14,
            acceptedCorridorWidthNauticalMiles: 225.5,
            disconnectedRefinements: 1,
            regressedRefinements: 2,
            fallbackReason: LatticeRefinementFallbackReason.Regressed);

        Assert.Equal(50L, d.ReRelaxedLabels);
        Assert.Equal(10L, d.StaleQueueEntries);
        Assert.Equal(7L, d.ActiveCells);
        Assert.Equal(14L, d.ActiveFaces);
        Assert.Equal(225.5, d.AcceptedCorridorWidthNauticalMiles);
        Assert.Equal(1, d.DisconnectedRefinements);
        Assert.Equal(2, d.RegressedRefinements);
        Assert.Equal(LatticeRefinementFallbackReason.Regressed, d.FallbackReason);
    }

    [Fact]
    public void Lattice_refinement_fallback_reason_covers_all_candidate_values()
    {
        Assert.Equal(4, Enum.GetValues<LatticeRefinementFallbackReason>().Length);
        Assert.Contains(LatticeRefinementFallbackReason.None,
            Enum.GetValues<LatticeRefinementFallbackReason>());
        Assert.Contains(LatticeRefinementFallbackReason.Disconnected,
            Enum.GetValues<LatticeRefinementFallbackReason>());
        Assert.Contains(LatticeRefinementFallbackReason.Regressed,
            Enum.GetValues<LatticeRefinementFallbackReason>());
        Assert.Contains(LatticeRefinementFallbackReason.RetryExhausted,
            Enum.GetValues<LatticeRefinementFallbackReason>());
    }
}
