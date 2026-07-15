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
}
