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

    private static RouteRequest RequestDepartingAt(DateTimeOffset departure) => new(
        "route-parse",
        new Coordinate(40, -60),
        new Coordinate(45, -55),
        departure,
        departure.AddHours(10));

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

    [Fact]
    public void Outside_forecast_failures_name_the_departure_and_the_coverage_they_missed()
    {
        var metadata = Metadata(Departure.AddDays(3));

        var late = NativeRouterBridge.DescribeFailure(
            NativeRouterStatus.OutsideForecast,
            RequestDepartingAt(metadata.LastValidAt.AddHours(6)),
            metadata);
        Assert.Contains("after the end of the forecast", late, StringComparison.Ordinal);
        Assert.Contains(metadata.LastValidAt.ToString("u"), late, StringComparison.Ordinal);

        var early = NativeRouterBridge.DescribeFailure(
            NativeRouterStatus.OutsideForecast,
            RequestDepartingAt(metadata.FirstValidAt.AddHours(-6)),
            metadata);
        Assert.Contains("before the start of the forecast", early, StringComparison.Ordinal);

        // A departure inside coverage means the *route* left the forecast, not the
        // departure, so the advice must not blame the departure.
        var inCoverage = NativeRouterBridge.DescribeFailure(
            NativeRouterStatus.OutsideForecast,
            CreateRequest(TimeSpan.FromHours(10)),
            metadata);
        Assert.Contains("weather outside the loaded forecast", inCoverage, StringComparison.Ordinal);
        Assert.DoesNotContain("departure is", inCoverage, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void No_route_failures_explain_the_available_coverage()
    {
        var message = NativeRouterBridge.DescribeFailure(
            NativeRouterStatus.NoRoute,
            CreateRequest(TimeSpan.FromHours(10)),
            Metadata(Departure.AddDays(3)));

        Assert.Contains("No route reached the destination", message, StringComparison.Ordinal);
        Assert.Contains(Departure.ToString("u"), message, StringComparison.Ordinal);
    }

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
