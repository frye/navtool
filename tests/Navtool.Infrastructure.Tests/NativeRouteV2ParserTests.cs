using System.Text.Json.Nodes;
using Navtool.Core;

namespace Navtool.Infrastructure.Tests;

public sealed class NativeRouteV2ParserTests
{
    [Theory]
    [InlineData("arrived.json", RouteCompletion.DestinationReached)]
    [InlineData("current.json", RouteCompletion.DestinationReached)]
    [InlineData("maneuver.json", RouteCompletion.DestinationReached)]
    [InlineData("gshhg-route.json", RouteCompletion.DestinationReached)]
    [InlineData("forecast-partial.json", RouteCompletion.ForecastExhausted)]
    [InlineData("duration-partial.json", RouteCompletion.DurationExhausted)]
    public void Strict_reader_accepts_actual_approved_library_fixtures_without_losing_completion_or_audit(
        string filename, RouteCompletion completion)
    {
        var path = NativeIntegration.Fixture(filename);
        if (path is null) return;
        var json = File.ReadAllText(path);
        using var document = System.Text.Json.JsonDocument.Parse(json);
        var root = document.RootElement;
        var origin = root.GetProperty("departure").GetProperty("position");
        var destination = root.GetProperty("routing").GetProperty("requestedDestination");
        var departure = root.GetProperty("departure").GetProperty("time").GetDateTimeOffset();
        var request = new RouteRequest("actual-fixture",
            new Coordinate(origin.GetProperty("latitude").GetDouble(), origin.GetProperty("longitude").GetDouble()),
            new Coordinate(destination.GetProperty("latitude").GetDouble(), destination.GetProperty("longitude").GetDouble()),
            departure, departure.AddHours(48));
        var route = NativeRouteJsonParser.Parse(json, request, ForecastModel.NoaaGfs, TimeSpan.Zero);
        Assert.Equal(completion, route.Completion);
        Assert.NotNull(route.NativeAudit!.Routing);
        Assert.Equal("best_found", route.NativeAudit.Routing.QualityClaim);
        Assert.NotNull(route.Diagnostics.FutureProbeMisses);
        Assert.Equal("explicit_time", route.NativeAudit.DepartureSource);
    }

    private static readonly DateTimeOffset Departure = DateTimeOffset.Parse("2026-07-15T00:00:00Z");
    private static RouteRequest Request => new("v2", new Coordinate(40, -60), new Coordinate(40, -59.5),
        Departure, Departure.AddHours(10));

    internal static JsonObject Document() => JsonNode.Parse(
        """
        {
          "schema":"route_result_v2",
          "completion":"destination_reached",
          "departure":{"time":"2026-07-15T00:00:00Z","source":"explicit_time","position":{"latitude":40,"longitude":-60}},
          "arrival":{"time":"2026-07-15T04:00:00Z","position":{"latitude":40,"longitude":-59.5}},
          "forecast":{"source":"controlled"},
          "polar":{"source":"explicit-demo"},
          "diagnostics":{"expandedNodes":10,"generatedCandidates":20,"retainedCandidates":5,"timeSteps":4,
            "eligibilityEvaluations":20,"prunedCandidates":15,"futureProbeMisses":2},
          "routing":{"objective":"earliest_arrival","qualityClaim":"best_found","solver":"isochrone_beam",
            "requestedDestination":{"latitude":40,"longitude":-59.5},"arrivalRadiusNm":1,"remainingDistanceNm":0,
            "boatSpeedFactor":1,"headingStepDegrees":5,"spatialBucketNm":2,"maximumIntegrationMinutes":5,
            "strategicRetention":true,"landAvoidance":false,"windSampling":"midpoint","abovePolarRange":"no_speed",
            "maximumForecastWindKnots":null,"tackPenaltySeconds":0,"gybePenaltySeconds":0,
            "forecastInitialization":"2026-07-15T00:00:00Z","forecastFirstValid":"2026-07-15T00:00:00Z",
            "forecastLastValid":"2026-07-16T00:00:00Z","warnings":["native landmask disabled"]},
          "points":[
            {"position":{"latitude":40,"longitude":-60},"time":"2026-07-15T00:00:00Z","headingDegrees":90,
             "boatSpeedKnots":6,"trueWindSpeedKnots":15,"trueWindDirectionDegrees":0,"cumulativeDistanceNauticalMiles":0},
            {"position":{"latitude":40,"longitude":-59.5},"time":"2026-07-15T04:00:00Z","headingDegrees":90,
             "boatSpeedKnots":6,"trueWindSpeedKnots":15,"trueWindDirectionDegrees":0,"cumulativeDistanceNauticalMiles":23}
          ]
        }
        """)!.AsObject();

    private static RouteResult Parse(JsonObject value) =>
        NativeRouteJsonParser.Parse(value.ToJsonString(), Request, ForecastModel.NoaaGfs, TimeSpan.FromSeconds(1));

    [Fact]
    public void V2_retains_actual_native_audit_and_new_counters()
    {
        var route = Parse(Document());
        Assert.Equal("route_result_v2", route.NativeAudit!.Schema);
        Assert.Equal(1, route.NativeAudit.EffectiveArrivalRadiusNauticalMiles);
        Assert.False(route.NativeAudit.NativeLandmaskApplied);
        Assert.Equal(20, route.Diagnostics.EligibilityEvaluations);
        Assert.Equal(15, route.Diagnostics.PrunedCandidates);
        Assert.Equal(2, route.Diagnostics.FutureProbeMisses);
        Assert.Equal("best_found", route.NativeAudit.Routing!.QualityClaim);
        Assert.Equal(1, route.NativeAudit.Routing.BoatSpeedFactor);
        Assert.Equal(Departure, route.NativeAudit.Routing.ForecastInitialization);
        Assert.Equal(new[] { "native landmask disabled" }, route.NativeAudit.Routing.Warnings);
        Assert.Equal("explicit-demo", route.NativeAudit.PolarSource);
        Assert.Equal(LandAvoidanceStatus.NotEvaluated, route.LandAvoidance.Status);
    }

    [Fact]
    public void V2_copies_current_and_effective_polar_wind_without_changing_forecast_wind()
    {
        var document = Document();
        document["points"]![1]!["environment"] = JsonNode.Parse(
            """{"speedOverGroundKnots":7,"courseOverGroundDegrees":90,"flatWaterSpeedKnots":6,"currentEastKnots":1,"currentNorthKnots":0,"polarWindSpeedKnots":16,"polarWindDirectionDegrees":2}""");
        var point = Parse(document).Points[1];
        Assert.Equal(15, point.TrueWindSpeedKnots);
        Assert.Equal(16, point.Environment!.PolarWindSpeedKnots);
        Assert.Equal(1, point.Environment.CurrentEastKnots);
    }

    [Theory]
    [InlineData("route_result_v3")]
    [InlineData("")]
    public void Rejects_unknown_schema(string schema)
    {
        var document = Document();
        document["schema"] = schema;
        Assert.Throws<NativeRouteFormatException>(() => Parse(document));
    }

    [Theory]
    [InlineData("solver", "different")]
    [InlineData("qualityClaim", "optimal")]
    [InlineData("windSampling", "unknown")]
    [InlineData("abovePolarRange", "unknown")]
    public void Rejects_unknown_known_audit_values(string key, string value)
    {
        var document = Document();
        document["routing"]![key] = value;
        Assert.Throws<NativeRouteFormatException>(() => Parse(document));
    }

    [Theory]
    [InlineData("arrivalRadiusNm", -1)]
    [InlineData("boatSpeedFactor", 0)]
    [InlineData("remainingDistanceNm", 2)]
    [InlineData("maximumIntegrationMinutes", 0)]
    public void Rejects_invalid_numeric_run_audit(string key, double value)
    {
        var document = Document();
        document["routing"]![key] = value;
        Assert.Throws<NativeRouteFormatException>(() => Parse(document));
    }

    [Theory]
    [InlineData("environment")]
    [InlineData("environmentDiagnostics")]
    [InlineData("latticeDiagnostics")]
    public void Rejects_malformed_known_optional_blocks(string block)
    {
        var document = Document();
        document[block] = "not an object";
        Assert.Throws<NativeRouteFormatException>(() => Parse(document));
    }

    [Fact]
    public void Rejects_partial_or_malformed_point_current_audit()
    {
        var document = Document();
        document["points"]![1]!["environment"] = JsonNode.Parse(
            """{"speedOverGroundKnots":7,"courseOverGroundDegrees":90,"flatWaterSpeedKnots":6,"currentEastKnots":"bad"}""");
        Assert.Throws<NativeRouteFormatException>(() => Parse(document));
    }

    [Fact]
    public void Rejects_request_endpoint_departure_and_destination_mismatches()
    {
        foreach (var mutation in new Action<JsonObject>[]
        {
            json => json["arrival"]!["position"]!["longitude"] = -59.6,
            json => json["departure"]!["position"]!["latitude"] = 41,
            json => json["departure"]!["time"] = "2026-07-15T01:00:00Z",
            json => json["routing"]!["requestedDestination"]!["longitude"] = -59.6,
            json => json["routing"]!["forecastLastValid"] = "2026-07-15T03:00:00Z",
            json => json["points"]![1]!["position"]!["longitude"] = 181,
            json => json["diagnostics"]!["futureProbeMisses"] = -1
        })
        {
            var document = Document();
            mutation(document);
            Assert.Throws<NativeRouteFormatException>(() => Parse(document));
        }
    }

    [Fact]
    public void Contradictory_completion_reasons_and_duplicate_fields_fail()
    {
        var document = Document();
        document["partial_reason"] = "forecast_exhausted";
        Assert.Throws<NativeRouteFormatException>(() => Parse(document));
        var json = Document().ToJsonString().Replace("\"schema\":", "\"completion\":\"forecast_exhausted\",\"schema\":");
        Assert.Throws<NativeRouteFormatException>(() =>
            NativeRouteJsonParser.Parse(json, Request, ForecastModel.NoaaGfs, TimeSpan.Zero));
    }

    [Fact]
    public void Additive_unknown_fields_are_accepted_but_v8_never_accepts_legacy_final_output()
    {
        var document = Document();
        document["futureMetadata"] = new JsonObject { ["futureBoolean"] = true };
        Assert.NotNull(Parse(document));
        document.Remove("schema");
        Assert.Null(Parse(document).NativeAudit);
        Assert.Throws<NativeRouteFormatException>(() => NativeRouteJsonParser.RequireV2(document.ToJsonString()));
    }
}
