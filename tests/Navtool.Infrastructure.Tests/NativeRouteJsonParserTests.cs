using System.Globalization;
using Navtool.Core;
using Navtool.Infrastructure;

namespace Navtool.Infrastructure.Tests;

/// <summary>
/// Unit tests for <see cref="NativeRouteJsonParser.Parse"/> with no file or network I/O.
/// These lock in the fix that stops mislabeling domain/native-output defects as the
/// generic "v1 contract" JSON error, and that lets an arrival exceed the requested
/// passage target without failing.
/// </summary>
public sealed class NativeRouteJsonParserTests
{
    private static readonly DateTimeOffset Departure =
        new(2026, 7, 15, 0, 0, 0, TimeSpan.Zero);

    private static RouteRequest CreateRequest(TimeSpan window) => new(
        "route-parse",
        new Coordinate(40, -60),
        new Coordinate(45, -55),
        Departure,
        Departure + window);

    private static string Iso(DateTimeOffset value) =>
        value.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", CultureInfo.InvariantCulture);

    private static string BuildJson(params (DateTimeOffset Time, double Lat, double Lon, double Distance)[] points)
    {
        var pointJson = points.Select(point =>
            $$"""
            {
              "position": { "latitude": {{point.Lat.ToString(CultureInfo.InvariantCulture)}}, "longitude": {{point.Lon.ToString(CultureInfo.InvariantCulture)}} },
              "time": "{{Iso(point.Time)}}",
              "headingDegrees": 45,
              "boatSpeedKnots": 6,
              "trueWindSpeedKnots": 15,
              "trueWindDirectionDegrees": 200,
              "cumulativeDistanceNauticalMiles": {{point.Distance.ToString(CultureInfo.InvariantCulture)}}
            }
            """);

        return $$"""
        {
          "completion": "destination_reached",
          "diagnostics": {
            "expandedNodes": 10,
            "generatedCandidates": 20,
            "retainedCandidates": 5,
            "timeSteps": 2
          },
          "points": [ {{string.Join(",", pointJson)}} ]
        }
        """;
    }

    [Fact]
    public void Parse_accepts_arrival_beyond_requested_target()
    {
        var request = CreateRequest(TimeSpan.FromHours(6));
        var json = BuildJson(
            (Departure, 40, -60, 0),
            (Departure.AddHours(8), 45, -55, 40));

        var result = NativeRouteJsonParser.Parse(json, request, ForecastModel.NoaaGfs, TimeSpan.FromSeconds(1));

        Assert.Equal(2, result.Points.Length);
        Assert.True(result.ExceedsRequestedArrival);
    }

    [Fact]
    public void Parse_preserves_forecast_exhausted_completion()
    {
        var request = CreateRequest(TimeSpan.FromHours(10));
        var json = BuildJson(
                (Departure, 40, -60, 0),
                (Departure.AddHours(8), 44, -56, 35))
            .Replace(
                "\"completion\": \"destination_reached\"",
                "\"completion\": \"forecast_exhausted\"");

        var result = NativeRouteJsonParser.Parse(
            json,
            request,
            ForecastModel.NoaaGfs,
            TimeSpan.FromSeconds(1));

        Assert.True(result.IsForecastLimited);
    }

    [Fact]
    public void Parse_preserves_lattice_solver_and_diagnostics()
    {
        var request = CreateRequest(TimeSpan.FromHours(10));
        var json = AddLatticeDiagnostics(BuildJson(
            (Departure, 40, -60, 0),
            (Departure.AddHours(8), 44, -56, 35)));

        var result = NativeRouteJsonParser.Parse(
            json,
            request,
            ForecastModel.NoaaGfs,
            TimeSpan.FromSeconds(1),
            RouteSolver.TimeDependentLattice);

        Assert.Equal(RouteSolver.TimeDependentLattice, result.Solver);
        Assert.Equal(100, result.LatticeDiagnostics!.SettledLabels);
        Assert.Equal(4, result.LatticeDiagnostics.WaitTransitions);
        Assert.True(result.LatticeDiagnostics.RefinementFallback);
        // Stage 2.5 fields absent from v0.4.0 JSON → default to zero/None.
        Assert.Equal(0L, result.LatticeDiagnostics.ReRelaxedLabels);
        Assert.Equal(LatticeRefinementFallbackReason.None, result.LatticeDiagnostics.FallbackReason);
    }

    [Fact]
    public void Parse_preserves_stage25_lattice_diagnostics_from_candidate_json()
    {
        var request = CreateRequest(TimeSpan.FromHours(10));
        var json = AddStage25LatticeDiagnostics(BuildJson(
            (Departure, 40, -60, 0),
            (Departure.AddHours(8), 44, -56, 35)));

        var result = NativeRouteJsonParser.Parse(
            json,
            request,
            ForecastModel.NoaaGfs,
            TimeSpan.FromSeconds(1),
            RouteSolver.TimeDependentLattice);

        Assert.Equal(RouteSolver.TimeDependentLattice, result.Solver);
        var d = result.LatticeDiagnostics!;
        Assert.Equal(100, d.SettledLabels);
        Assert.True(d.RefinementFallback);
        Assert.Equal(15L, d.ReRelaxedLabels);
        Assert.Equal(5L, d.StaleQueueEntries);
        Assert.Equal(12L, d.ActiveCells);
        Assert.Equal(24L, d.ActiveFaces);
        Assert.Equal(450.0, d.AcceptedCorridorWidthNauticalMiles);
        Assert.Equal(1, d.DisconnectedRefinements);
        Assert.Equal(2, d.RegressedRefinements);
        Assert.Equal(LatticeRefinementFallbackReason.Disconnected, d.FallbackReason);
    }

    [Fact]
    public void Parse_rejects_partial_or_solver_incompatible_lattice_diagnostics()
    {
        var request = CreateRequest(TimeSpan.FromHours(10));
        var json = AddLatticeDiagnostics(BuildJson(
            (Departure, 40, -60, 0),
            (Departure.AddHours(8), 44, -56, 35)));

        Assert.Throws<NativeRouteFormatException>(() => NativeRouteJsonParser.Parse(
            json.Replace("\"waitTransitions\": 4,", string.Empty),
            request,
            ForecastModel.NoaaGfs,
            TimeSpan.FromSeconds(1),
            RouteSolver.TimeDependentLattice));
        Assert.Throws<NativeRouteFormatException>(() => NativeRouteJsonParser.Parse(
            json,
            request,
            ForecastModel.NoaaGfs,
            TimeSpan.FromSeconds(1),
            RouteSolver.IsochroneBeam));
    }

    [Fact]
    public void Parse_throws_format_error_for_malformed_json()
    {
        var request = CreateRequest(TimeSpan.FromHours(10));

        // Missing required field ("points").
        Assert.Throws<NativeRouteFormatException>(() => NativeRouteJsonParser.Parse(
            """{ "diagnostics": { "expandedNodes": 1, "generatedCandidates": 2, "retainedCandidates": 1, "timeSteps": 1 } }""",
            request,
            ForecastModel.NoaaGfs,
            TimeSpan.FromSeconds(1)));

        // Syntactically broken JSON.
        Assert.Throws<NativeRouteFormatException>(() => NativeRouteJsonParser.Parse(
            "{ not json",
            request,
            ForecastModel.NoaaGfs,
            TimeSpan.FromSeconds(1)));

        // Non-finite numeric field.
        var nonFinite = BuildJson(
            (Departure, 40, -60, 0),
            (Departure.AddHours(5), 45, -55, 20)).Replace("\"boatSpeedKnots\": 6", "\"boatSpeedKnots\": 1e400");
        Assert.Throws<NativeRouteFormatException>(() => NativeRouteJsonParser.Parse(
            nonFinite,
            request,
            ForecastModel.NoaaGfs,
            TimeSpan.FromSeconds(1)));
    }

    [Fact]
    public void Parse_reports_native_output_defect_for_out_of_range_point()
    {
        var request = CreateRequest(TimeSpan.FromHours(10));
        // Latitude 91 is valid JSON but an impossible coordinate.
        var json = BuildJson(
            (Departure, 91, -60, 0),
            (Departure.AddHours(5), 45, -55, 20));

        var exception = Assert.Throws<NativeRouteFormatException>(() => NativeRouteJsonParser.Parse(
            json,
            request,
            ForecastModel.NoaaGfs,
            TimeSpan.FromSeconds(1)));

        Assert.Contains("invalid route point", exception.Message, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void Parse_reports_native_output_defect_for_time_descending_points()
    {
        var request = CreateRequest(TimeSpan.FromHours(10));
        var json = BuildJson(
            (Departure.AddHours(3), 40, -60, 0),
            (Departure.AddHours(1), 45, -55, 20));

        var exception = Assert.Throws<NativeRouteFormatException>(() => NativeRouteJsonParser.Parse(
            json,
            request,
            ForecastModel.NoaaGfs,
            TimeSpan.FromSeconds(1)));

        Assert.Contains("structurally invalid route", exception.Message, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void Parse_reports_native_output_defect_for_empty_points()
    {
        var request = CreateRequest(TimeSpan.FromHours(10));
        var json = """
        {
          "completion": "destination_reached",
          "diagnostics": { "expandedNodes": 1, "generatedCandidates": 2, "retainedCandidates": 1, "timeSteps": 1 },
          "points": []
        }
        """;

        var exception = Assert.Throws<NativeRouteFormatException>(() => NativeRouteJsonParser.Parse(
            json,
            request,
            ForecastModel.NoaaGfs,
            TimeSpan.FromSeconds(1)));

        Assert.Contains("structurally invalid route", exception.Message, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void Horizon_guard_accepts_arrival_at_or_within_tolerance_of_last_valid()
    {
        var request = CreateRequest(TimeSpan.FromHours(10));
        var arrival = Departure.AddHours(8);
        var result = NativeRouteJsonParser.Parse(
            BuildJson((Departure, 40, -60, 0), (arrival, 45, -55, 40)),
            request,
            ForecastModel.NoaaGfs,
            TimeSpan.FromSeconds(1));

        // Arrival exactly at the forecast horizon.
        NativeRouterBridge.EnsureWithinForecastHorizon(result, Metadata(arrival));
        // Arrival one second past the horizon (absorbed by the epoch-second tolerance).
        NativeRouterBridge.EnsureWithinForecastHorizon(result, Metadata(arrival.AddSeconds(-1)));
    }

    [Fact]
    public void Horizon_guard_rejects_arrival_beyond_last_valid()
    {
        var request = CreateRequest(TimeSpan.FromHours(10));
        var arrival = Departure.AddHours(8);
        var result = NativeRouteJsonParser.Parse(
            BuildJson((Departure, 40, -60, 0), (arrival, 45, -55, 40)),
            request,
            ForecastModel.NoaaGfs,
            TimeSpan.FromSeconds(1));

        var exception = Assert.Throws<NativeRouteFormatException>(() =>
            NativeRouterBridge.EnsureWithinForecastHorizon(result, Metadata(arrival.AddHours(-2))));

        Assert.Contains("weather horizon", exception.Message, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void Horizon_guard_reports_sub_minute_overruns_in_seconds()
    {
        var request = CreateRequest(TimeSpan.FromHours(10));
        var arrival = Departure.AddHours(8);
        var result = NativeRouteJsonParser.Parse(
            BuildJson((Departure, 40, -60, 0), (arrival, 45, -55, 40)),
            request,
            ForecastModel.NoaaGfs,
            TimeSpan.FromSeconds(1));

        // A 30-second overrun must not collapse to a misleading "0m".
        var exception = Assert.Throws<NativeRouteFormatException>(() =>
            NativeRouterBridge.EnsureWithinForecastHorizon(result, Metadata(arrival.AddSeconds(-30))));

        Assert.Contains("30s", exception.Message, StringComparison.Ordinal);
        Assert.DoesNotContain("0m", exception.Message, StringComparison.Ordinal);
    }

    private static NativeForecastMetadata Metadata(DateTimeOffset lastValidAt) => new(
        Departure,
        lastValidAt,
        180,
        360,
        false,
        "test-forecast");

    private static string AddLatticeDiagnostics(string json) =>
        json.Replace(
            "\"points\":",
            """
            "latticeDiagnostics": {
              "settledLabels": 100,
              "queuedLabels": 20,
              "relaxedLabels": 250,
              "waitTransitions": 4,
              "refinementRuns": 2,
              "acceptedRefinements": 1,
              "subdivisionLevel": 5,
              "refinementFallback": true
            },
            "points":
            """,
            StringComparison.Ordinal);

    private static string AddStage25LatticeDiagnostics(string json) =>
        json.Replace(
            "\"points\":",
            """
            "latticeDiagnostics": {
              "settledLabels": 100,
              "queuedLabels": 20,
              "relaxedLabels": 250,
              "waitTransitions": 4,
              "refinementRuns": 2,
              "acceptedRefinements": 1,
              "subdivisionLevel": 5,
              "refinementFallback": true,
              "reRelaxedLabels": 15,
              "staleQueueEntries": 5,
              "activeCells": 12,
              "activeFaces": 24,
              "acceptedCorridorWidthNauticalMiles": 450.0,
              "disconnectedRefinements": 1,
              "regressedRefinements": 2,
              "fallbackReason": "disconnected"
            },
            "points":
            """,
            StringComparison.Ordinal);
}

public sealed class NativeRouteJsonParserEnvironmentTests
{
    private static readonly DateTimeOffset Departure =
        new(2026, 7, 15, 0, 0, 0, TimeSpan.Zero);

    private static RouteRequest CreateRequest() => new(
        "route-environment",
        new Coordinate(40, -60),
        new Coordinate(45, -55),
        Departure,
        Departure.AddHours(12));

    private static string Iso(DateTimeOffset value) =>
        value.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", CultureInfo.InvariantCulture);

    /// <summary>
    /// Mirrors the shape router-lib emits when no environment is configured:
    /// the three environment blocks are absent entirely, not null and not empty.
    /// </summary>
    private static string BaselineJson(string extraPointKeys = "", string extraRootKeys = "") =>
        $$"""
        {
          "completion": "destination_reached",
          "diagnostics": {
            "expandedNodes": 10,
            "generatedCandidates": 20,
            "retainedCandidates": 5,
            "timeSteps": 2
          }{{extraRootKeys}},
          "points": [
            {
              "position": { "latitude": 40, "longitude": -60 },
              "time": "{{Iso(Departure)}}",
              "headingDegrees": 45,
              "boatSpeedKnots": 6,
              "trueWindSpeedKnots": 15,
              "trueWindDirectionDegrees": 200,
              "cumulativeDistanceNauticalMiles": 0{{extraPointKeys}}
            },
            {
              "position": { "latitude": 45, "longitude": -55 },
              "time": "{{Iso(Departure.AddHours(8))}}",
              "headingDegrees": 50,
              "boatSpeedKnots": 6.5,
              "trueWindSpeedKnots": 16,
              "trueWindDirectionDegrees": 205,
              "cumulativeDistanceNauticalMiles": 40{{extraPointKeys}}
            }
          ]
        }
        """;

    private static RouteResult Parse(string json) =>
        NativeRouteJsonParser.Parse(json, CreateRequest(), ForecastModel.NoaaGfs, TimeSpan.FromSeconds(1));

    [Fact]
    public void Parse_leaves_environment_null_when_router_emits_no_environment_blocks()
    {
        var result = Parse(BaselineJson());

        Assert.Null(result.Environment);
        Assert.Null(result.EnvironmentDiagnostics);
        Assert.All(result.Points, point => Assert.Null(point.Environment));
    }

    [Fact]
    public void Parse_reads_environment_metadata_with_router_lib_key_spellings()
    {
        var json = BaselineJson(extraRootKeys: """
            ,
            "environment": {
              "sampling": "midpoint",
              "currentProvider": { "name": "uniform", "source": "operator", "revision": "1" },
              "waveProvider": { "name": "uniform-wave", "source": "operator", "revision": "2" },
              "seaStateModel": { "name": "wave-height-derating", "source": "sailroute", "revision": "3" },
              "landmask": null,
              "exclusions": null,
              "policies": {
                "current": "fail_route",
                "wave": "reject_transition",
                "land": "fail_route"
              }
            }
            """);

        var environment = Parse(json).Environment;

        Assert.NotNull(environment);
        Assert.Equal(RouteEnvironmentSampling.Midpoint, environment!.Sampling);
        Assert.Equal("uniform", environment.CurrentProvider?.Name);
        Assert.Equal("operator", environment.CurrentProvider?.Source);
        Assert.Equal("1", environment.CurrentProvider?.Revision);
        Assert.Equal("wave-height-derating", environment.SeaStateModel?.Name);
        Assert.Null(environment.Landmask);
        Assert.Null(environment.Exclusions);
        Assert.Equal(RouteMissingDataPolicy.FailRoute, environment.CurrentPolicy);
        Assert.Equal(RouteMissingDataPolicy.RejectTransition, environment.WavePolicy);
        Assert.Equal(RouteMissingDataPolicy.FailRoute, environment.LandPolicy);
        Assert.Null(environment.LandClearanceNauticalMiles);
        Assert.Null(environment.ExclusionZoneCount);
    }

    [Fact]
    public void Parse_reads_landmask_and_exclusion_fields_only_when_router_emits_them()
    {
        var json = BaselineJson(extraRootKeys: """
            ,
            "environment": {
              "sampling": "segment_start",
              "currentProvider": null,
              "waveProvider": null,
              "seaStateModel": null,
              "landmask": { "name": "navtool-signed-distance", "source": "osm", "revision": "7" },
              "exclusions": { "name": "antarctic", "source": "navtool", "revision": "1" },
              "policies": { "current": "fail_route", "wave": "fail_route", "land": "reject_transition" },
              "landResolutionNauticalMiles": 2.5,
              "landInterpolationErrorNauticalMiles": 1.75,
              "landClearanceNauticalMiles": 0.5,
              "exclusionBoundaryPolicy": "boundary_allowed",
              "exclusionZoneCount": 2,
              "exclusionRevision": 11
            }
            """);

        var environment = Parse(json).Environment;

        Assert.NotNull(environment);
        Assert.Equal(RouteEnvironmentSampling.SegmentStart, environment!.Sampling);
        Assert.Equal(2.5, environment.LandResolutionNauticalMiles);
        Assert.Equal(1.75, environment.LandInterpolationErrorNauticalMiles);
        Assert.Equal(0.5, environment.LandClearanceNauticalMiles);
        Assert.Equal(RouteExclusionBoundaryPolicy.BoundaryAllowed, environment.ExclusionBoundaryPolicy);
        Assert.Equal(2, environment.ExclusionZoneCount);
        Assert.Equal(11UL, environment.ExclusionRevision);
    }

    /// <summary>
    /// Optional provider fields follow the same wrong-kind-is-absent rule as
    /// every other optional field here, so a numeric source falls back to
    /// "unattributed" instead of failing the whole route parse over a field
    /// that already has a defined fallback.
    /// </summary>
    [Fact]
    public void Parse_treats_a_wrong_kind_provider_source_as_absent()
    {
        var json = BaselineJson(extraRootKeys: """
            ,
            "environment": {
              "sampling": "segment_start",
              "currentProvider": { "name": "uniform", "source": 7, "revision": 3 },
              "policies": { "current": "fail_route", "wave": "fail_route", "land": "fail_route" }
            }
            """);

        var environment = Parse(json).Environment;

        Assert.NotNull(environment);
        Assert.Equal("uniform", environment!.CurrentProvider!.Name);
        Assert.Equal("unattributed", environment.CurrentProvider.Source);
        Assert.Equal(string.Empty, environment.CurrentProvider.Revision);
    }

    /// <summary>
    /// A non-string name must still report the specific missing-name error
    /// rather than being rebranded as a generic v1 contract failure.
    /// </summary>
    [Fact]
    public void Parse_reports_a_wrong_kind_provider_name_as_a_missing_name()
    {
        var json = BaselineJson(extraRootKeys: """
            ,
            "environment": {
              "sampling": "segment_start",
              "currentProvider": { "name": 42, "source": "operator" },
              "policies": { "current": "fail_route", "wave": "fail_route", "land": "fail_route" }
            }
            """);

        var error = Assert.Throws<NativeRouteFormatException>(() => Parse(json));

        Assert.Contains("missing a name", error.Message);
        Assert.Contains("currentProvider", error.Message);
    }

    [Fact]
    public void Parse_reads_every_environment_diagnostics_counter()
    {
        var json = BaselineJson(extraRootKeys: """
            ,
            "environmentDiagnostics": {
              "currentSamples": 11,
              "currentRejections": 1,
              "waveSamples": 22,
              "waveRejections": 2,
              "seaStateEvaluations": 33,
              "landChecks": 44,
              "landDistanceQueries": 55,
              "landRejections": 5,
              "exclusionChecks": 66,
              "exclusionGeometryTests": 77,
              "exclusionRejections": 7
            }
            """);

        var diagnostics = Parse(json).EnvironmentDiagnostics;

        Assert.NotNull(diagnostics);
        Assert.Equal(11, diagnostics!.CurrentSamples);
        Assert.Equal(1, diagnostics.CurrentRejections);
        Assert.Equal(22, diagnostics.WaveSamples);
        Assert.Equal(2, diagnostics.WaveRejections);
        Assert.Equal(33, diagnostics.SeaStateEvaluations);
        Assert.Equal(44, diagnostics.LandChecks);
        Assert.Equal(55, diagnostics.LandDistanceQueries);
        Assert.Equal(5, diagnostics.LandRejections);
        Assert.Equal(66, diagnostics.ExclusionChecks);
        Assert.Equal(77, diagnostics.ExclusionGeometryTests);
        Assert.Equal(7, diagnostics.ExclusionRejections);
    }

    [Fact]
    public void Parse_reads_point_environment_with_current_and_wave_applied()
    {
        var json = BaselineJson(extraPointKeys: """
            ,
            "environment": {
              "speedOverGroundKnots": 7.25,
              "courseOverGroundDegrees": 52.5,
              "currentEastKnots": 1.1,
              "currentNorthKnots": -0.4,
              "flatWaterSpeedKnots": 6.8,
              "significantWaveHeightMetres": 2.4,
              "wavePeriodSeconds": 8.5,
              "relativeWaveAngleDegrees": 135
            }
            """);

        var point = Parse(json).Points[0].Environment;

        Assert.NotNull(point);
        Assert.Equal(7.25, point!.SpeedOverGroundKnots);
        Assert.Equal(52.5, point.CourseOverGroundDegrees);
        Assert.Equal(6.8, point.FlatWaterSpeedKnots);
        Assert.Equal(1.1, point.CurrentEastKnots);
        Assert.Equal(-0.4, point.CurrentNorthKnots);
        Assert.Equal(2.4, point.SignificantWaveHeightMetres);
        Assert.Equal(8.5, point.WavePeriodSeconds);
        Assert.Equal(135, point.RelativeWaveAngleDegrees);
        Assert.True(point.CurrentApplied);
        Assert.True(point.WaveApplied);
    }

    /// <summary>
    /// router-lib does not emit <c>currentApplied</c> or <c>waveApplied</c> as JSON
    /// keys even though they exist as C++ bools. The only signal that a provider
    /// ran is the presence of its value keys, so a point with sea state but no
    /// current must report the current as not applied rather than as zero drift.
    /// </summary>
    [Fact]
    public void Parse_treats_absent_current_keys_as_current_not_applied()
    {
        var json = BaselineJson(extraPointKeys: """
            ,
            "environment": {
              "speedOverGroundKnots": 6.1,
              "courseOverGroundDegrees": 45,
              "flatWaterSpeedKnots": 6.8,
              "significantWaveHeightMetres": 3.1,
              "wavePeriodSeconds": 9,
              "relativeWaveAngleDegrees": 170
            }
            """);

        var point = Parse(json).Points[0].Environment;

        Assert.NotNull(point);
        Assert.False(point!.CurrentApplied);
        Assert.Null(point.CurrentEastKnots);
        Assert.Null(point.CurrentNorthKnots);
        Assert.True(point.WaveApplied);
    }

    /// <summary>
    /// router-lib writes the current components as a pair, so a payload holding
    /// only one of them is truncated rather than a real current. Reporting it as
    /// applied would claim a set and drift vector the data cannot supply.
    /// </summary>
    [Fact]
    public void Parse_treats_a_half_populated_current_vector_as_not_applied()
    {
        var json = BaselineJson(extraPointKeys: """
            ,
            "environment": {
              "speedOverGroundKnots": 7,
              "courseOverGroundDegrees": 48,
              "currentEastKnots": 0.9,
              "flatWaterSpeedKnots": 6.4
            }
            """);

        var point = Parse(json).Points[0].Environment;

        Assert.NotNull(point);
        Assert.False(
            point!.CurrentApplied,
            "A current missing its north component is incomplete, not applied.");
        Assert.Equal(0.9, point.CurrentEastKnots);
        Assert.Null(point.CurrentNorthKnots);
    }

    /// <summary>
    /// The sea state trio is emitted together for the same reason, so a payload
    /// missing the relative angle cannot describe a derating.
    /// </summary>
    [Fact]
    public void Parse_treats_a_partial_wave_triple_as_not_applied()
    {
        var json = BaselineJson(extraPointKeys: """
            ,
            "environment": {
              "speedOverGroundKnots": 6.1,
              "courseOverGroundDegrees": 45,
              "flatWaterSpeedKnots": 6.8,
              "significantWaveHeightMetres": 3.1,
              "wavePeriodSeconds": 9
            }
            """);

        var point = Parse(json).Points[0].Environment;

        Assert.NotNull(point);
        Assert.False(
            point!.WaveApplied,
            "A sea state missing its relative angle is incomplete, not applied.");
        Assert.Equal(3.1, point.SignificantWaveHeightMetres);
        Assert.Null(point.RelativeWaveAngleDegrees);
    }

    [Fact]
    public void Parse_treats_absent_wave_keys_as_wave_not_applied()
    {
        var json = BaselineJson(extraPointKeys: """
            ,
            "environment": {
              "speedOverGroundKnots": 7,
              "courseOverGroundDegrees": 48,
              "currentEastKnots": 0.9,
              "currentNorthKnots": 0.2,
              "flatWaterSpeedKnots": 6.4
            }
            """);

        var point = Parse(json).Points[0].Environment;

        Assert.NotNull(point);
        Assert.True(point!.CurrentApplied);
        Assert.False(point.WaveApplied);
        Assert.Null(point.SignificantWaveHeightMetres);
        Assert.Null(point.WavePeriodSeconds);
        Assert.Null(point.RelativeWaveAngleDegrees);
    }

    /// <summary>
    /// Water-relative heading and speed must stay water relative even when a
    /// current is applied. Ground motion is only ever reported through the
    /// environment block, so a consumer can never confuse the two frames.
    /// </summary>
    [Fact]
    public void Parse_keeps_point_heading_and_speed_water_relative_under_current()
    {
        var json = BaselineJson(extraPointKeys: """
            ,
            "environment": {
              "speedOverGroundKnots": 7.25,
              "courseOverGroundDegrees": 52.5,
              "currentEastKnots": 1.1,
              "currentNorthKnots": -0.4,
              "flatWaterSpeedKnots": 6.8
            }
            """);

        var point = Parse(json).Points[0];

        Assert.Equal(45, point.HeadingDegrees);
        Assert.Equal(6, point.BoatSpeedKnots);
        Assert.Equal(52.5, point.Environment!.CourseOverGroundDegrees);
        Assert.Equal(7.25, point.Environment.SpeedOverGroundKnots);
    }
}
