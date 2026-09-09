using System.Text.Json.Nodes;
using Navtool.Core;
using NetTopologySuite.Geometries;

namespace Navtool.Infrastructure.Tests;

public sealed class CoastalPruningIntegrationTests
{
    [Fact]
    public void Polygon_routing_uses_certified_topology_and_preserves_effective_native_audit()
    {
        var bridge = NativeIntegration.Bridge();
        var grib = NativeIntegration.Fixture("constant.grib");
        var polarPath = NativeIntegration.Fixture("coastal.csv");
        if (bridge is null || grib is null || polarPath is null) return;
        using var forecast = bridge.LoadForecast(grib, maximumInterpolationGap: TimeSpan.FromHours(6));
        using var polar = bridge.LoadPolar(polarPath, BoatPolarFormat.NativeMatrix);
        var factory = new GeometryFactory();
        var polygon = factory.CreatePolygon(
            [new(.1, .25), new(.7, .25), new(.7, .75), new(.1, .75), new(.1, .25)]);
        var land = new LandGeometryIndex([polygon]);
        var request = new RouteRequest("coastal-boundary", new(0, 0), new(0, .8),
            forecast.Metadata.FirstValidAt, forecast.Metadata.FirstValidAt.AddHours(12));
        var options = bridge.GetQualityDefaults() with
        {
            CoastalPruning = RouteCoastalPruningMode.ConservativeLandAware,
            ArrivalRadiusNauticalMiles = .25,
            HardDuration = TimeSpan.FromHours(12)
        };
        var topology = CoastalTopologyPreparation.Create(forecast.Metadata.EffectiveBounds!.Value, request,
            land, land.GeometryIdentity, CancellationToken.None);
        var snapshots = new List<RouteCalculationSnapshot>();
        var result = bridge.CalculateWithCoastalTopology(forecast, polar, request, ForecastModel.NoaaGfs,
            options, snapshots.Add, (from, to) => !land.IntersectsSegment(from, to), CancellationToken.None, null, topology);
        Assert.True(result.IsComplete);
        var audit = Assert.IsType<RouteCoastalPruningDiagnostics>(result.Diagnostics.CoastalPruning);
        Assert.Equal(audit, result.NativeAudit!.CoastalPruning);
        Assert.Equal(land.GeometryIdentity, audit.SourceIdentity);
        Assert.Equal(topology.DomainIdentity, audit.DomainIdentity);
        Assert.NotNull(audit.IncumbentArrival);
        Assert.True(result.ArrivalTime <= audit.IncumbentArrival);
        Assert.True(audit.SkippedParents + audit.IncumbentCandidates + audit.HorizonCandidates > 0);
        Assert.NotEmpty(snapshots);
        Assert.All(snapshots, snapshot =>
        {
            Assert.Equal(audit.Mode, snapshot.Diagnostics.CoastalPruning!.Mode);
            Assert.Equal(audit.SourceIdentity, snapshot.Diagnostics.CoastalPruning.SourceIdentity);
        });
        Assert.Throws<RoutingException>(() => bridge.CalculateRoute(forecast, polar, request,
            ForecastModel.NoaaGfs, options, isSegmentEligible: (_, _) => true));
        var alreadyInside = new RouteRequest("coastal-already-arrived", new(0, 0), new(0, .001),
            request.DepartureTime, request.LatestArrivalTime);
        var immediate = bridge.CalculateWithCoastalTopology(forecast, polar, alreadyInside, ForecastModel.NoaaGfs,
            options, null, (from, to) => !land.IntersectsSegment(from, to), CancellationToken.None, null, topology);
        Assert.Single(immediate.Points);
        Assert.Equal(audit.Mode, immediate.Diagnostics.CoastalPruning!.Mode);
    }

    [Fact]
    public void Native_gshhg_pruning_reuses_the_selected_owner_and_current_bounds_remain_honest()
    {
        var bridge = NativeIntegration.Bridge();
        var grib = NativeIntegration.Fixture("constant.grib");
        var polarPath = NativeIntegration.Fixture("coastal.csv");
        var landPath = NativeIntegration.Fixture("island.b");
        if (bridge is null || grib is null || polarPath is null || landPath is null) return;
        using var forecast = bridge.LoadForecast(grib, maximumInterpolationGap: TimeSpan.FromHours(6));
        using var polar = bridge.LoadPolar(polarPath, BoatPolarFormat.NativeMatrix);
        using var land = bridge.LoadRegionalLand(landPath, new RegionalLandOptions(new(-1, 1, -.4, 1.5), 5, 60));
        var request = new RouteRequest("native-coastal", new(0, 0), new(0, .2),
            forecast.Metadata.FirstValidAt, forecast.Metadata.FirstValidAt.AddHours(12));
        var defaults = bridge.GetQualityDefaults();
        var options = defaults with
        {
            CoastalPruning = RouteCoastalPruningMode.ConservativeLandAware,
            Optimization = defaults.Optimization.WithEnvironment(new RouteEnvironmentOptions(
                currents: RouteCurrentOptions.Uniform(1, 0, new RouteProviderMetadata("current", "test", "1"))))
        };
        var result = bridge.CalculateRoute(forecast, polar, request, ForecastModel.NoaaGfs, options, land: land);
        Assert.True(result.IsComplete);
        Assert.True(result.NativeAudit!.NativeLandmaskApplied);
        Assert.Equal(land.SourceFingerprint, result.Diagnostics.CoastalPruning!.SourceIdentity);
        Assert.Null(result.Diagnostics.CoastalPruning.SpeedUpperKnots);
        Assert.False(string.IsNullOrWhiteSpace(result.Diagnostics.CoastalPruning.UnavailableReason));
        var mask = new RouteLandmaskOptions(new RouteEnvironmentGrid(-1.5, -.5, .25, .25, 13, 13),
            Enumerable.Repeat(100d, 169).ToArray(), 15, .01,
            new RouteProviderMetadata("SDF test", "same descriptive source", "1"));
        var sdfOptions = defaults with
        {
            CoastalPruning = RouteCoastalPruningMode.ConservativeLandAware,
            Optimization = defaults.Optimization.WithEnvironment(new RouteEnvironmentOptions(land: mask))
        };
        var sdfRoute = bridge.CalculateRoute(forecast, polar, request, ForecastModel.NoaaGfs, sdfOptions);
        Assert.Equal(CoastalTopologyPreparation.IdentifyLandmask(mask, CancellationToken.None),
            sdfRoute.Diagnostics.CoastalPruning!.SourceIdentity);
    }

    [Fact]
    public void Parser_preserves_coastal_provenance_in_both_diagnostic_locations()
    {
        var document = WithAudit();
        var parsed = Parse(document);
        Assert.Equal(parsed.Diagnostics.CoastalPruning, parsed.NativeAudit!.CoastalPruning);
        Assert.Equal("source-v1", parsed.Diagnostics.CoastalPruning!.SourceIdentity);
        Assert.Equal(3, parsed.Diagnostics.CoastalPruning.IncumbentCandidates);
    }

    [Theory]
    [InlineData("effective", "\"off\"")]
    [InlineData("schemaVersion", "2")]
    [InlineData("topologyRepresentation", "\"unsafe_grid\"")]
    [InlineData("candidatesIncumbent", "-1")]
    [InlineData("speedUpperKnots", "0")]
    [InlineData("sourceIdentity", "null")]
    public void Parser_rejects_invalid_coastal_audit(string key, string replacement)
    {
        var document = WithAudit();
        document["diagnostics"]!["coastalPruning"]![key] = JsonNode.Parse(replacement);
        Assert.Throws<NativeRouteFormatException>(() => Parse(document));
    }

    private static JsonObject WithAudit()
    {
        var document = NativeRouteV2ParserTests.Document();
        document["diagnostics"]!["coastalPruning"] = JsonNode.Parse(
            """
            {"schemaVersion":1,"requested":"conservative","effective":"conservative",
             "topologyRepresentation":"spherical_caps_v1","sourceIdentity":"source-v1","domainIdentity":"domain-v1",
             "boundStatus":"available","seedStatus":"validated","speedUpperKnots":10,
             "incumbentArrival":"2026-07-15T05:00:00Z","parentExpansionsSkipped":2,"candidatesDisconnected":0,
             "candidatesHorizon":1,"candidatesIncumbent":3,"boundUnavailable":0,"seedTransitionEvaluations":4,
             "topologyWork":12,"topologyCaps":2,"numericalMarginNm":0.001,"clearanceNm":0,"seedActions":[]}
            """);
        return document;
    }

    private static RouteResult Parse(JsonObject document)
    {
        var departure = DateTimeOffset.Parse("2026-07-15T00:00:00Z");
        return NativeRouteJsonParser.Parse(document.ToJsonString(),
            new RouteRequest("audit", new(40, -60), new(40, -59.5), departure, departure.AddHours(10)),
            ForecastModel.NoaaGfs, TimeSpan.Zero);
    }
}
