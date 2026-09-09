using System.Text.Json;
using Navtool.Core;

namespace Navtool.Infrastructure.Tests;

public sealed class RoutingMigrationEndToEndTests
{
    [Fact]
    public async Task Default_polygon_source_runs_coastal_pruning_through_the_saved_plan_workflow()
    {
        var bridge = NativeIntegration.Bridge();
        var sample = NativeIntegration.Fixture("coastal-region.grib");
        var polar = NativeIntegration.Fixture("coastal.csv");
        if (bridge is null || sample is null || polar is null) return;
        using var directory = new TestDirectory();
        var boats = new BoatAssetRepository(directory.Path, bridge);
        var boat = await boats.ImportAsync(polar, BoatPolarFormat.NativeMatrix);
        var setup = new RoutingSetup(boat, coastalPruning: RouteCoastalPruningMode.ConservativeLandAware);
        var plan = new RoutePlan("Coastal default source",
            [new("Start", new(48.25, -123.65)), new("Finish", new(48.25, -123.35))]).WithRoutingSetup(setup);
        var descriptor = await new NativeLocalGribInspector(bridge).InspectAsync(sample);
        var repository = new RoutePlanJsonRepository(directory.Path);
        var engine = new NativeRouteEngine(bridge, executionDirectory: Path.Combine(directory.Path, "execution"));
        var setupService = new NativeRoutingSetupService(bridge, boats,
            executionDirectory: Path.Combine(directory.Path, "execution"));
        var workflow = new RoutePlanRoutingWorkflow(new RoutingWorkflow([], engine), repository,
            setupService: setupService);
        var result = await workflow.ExecuteAsync(new RoutePlanRoutingRequest(
            plan, descriptor.ValidFrom, descriptor.ValidFrom.AddHours(12), [ForecastSelection.LocalFile(descriptor)]));
        Assert.True(result.Status == RoutePlanRoutingStatus.Succeeded,
            string.Join("; ", result.Models.SelectMany(model => model.Legs).Select(leg => leg.Detail)));
        var route = Assert.Single(Assert.Single(result.Models).Legs).Route!;
        Assert.True(route.LandAvoidance.IsApplied);
        Assert.False(route.NativeAudit!.NativeLandmaskApplied);
        Assert.StartsWith("sha256:", route.Diagnostics.CoastalPruning!.SourceIdentity);
        Assert.Equal(RouteCoastalPruningMode.ConservativeLandAware, route.RunAudit!.Resolved.CoastalPruning);
        var restored = (await repository.OpenAsync(plan.Id)).LatestResult(descriptor.Model)!.Legs[0].Route!;
        Assert.Equal(route.Diagnostics.CoastalPruning, restored.Diagnostics.CoastalPruning);
        Assert.Equal(route.NativeAudit.CoastalSeedActions.ToArray(), restored.NativeAudit!.CoastalSeedActions.ToArray());
    }

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public async Task Imported_boat_regional_itinerary_preserves_native_handoffs_and_audit_after_restart_and_copy(bool coastal)
    {
        var bridge = NativeIntegration.Bridge();
        var sample = NativeIntegration.Sample();
        var polar = NativeIntegration.Fixture("fast.csv");
        if (bridge is null || sample is null || polar is null) return;
        using var directory = new TestDirectory();
        var source = Path.Combine(directory.Path, "regional.b");
        NativeV8IntegrationTests.WriteGshhgIsland(source);
        var regionalService = new NativeRegionalLandSourceService(bridge);
        var regional = await regionalService.ValidateSourceAsync(source,
            new RegionalLandOptions(new GeographicBounds(48.1, 48.4, -123.7, -123.3), 5, 10));
        var boats = new BoatAssetRepository(directory.Path, bridge);
        var boat = await boats.ImportAsync(polar, BoatPolarFormat.NativeMatrix);
        var setup = new RoutingSetup(boat, landSource: RoutingLandSource.RegionalGshhg, regionalLand: regional,
            coastalPruning: coastal ? RouteCoastalPruningMode.ConservativeLandAware : RouteCoastalPruningMode.Off);
        var plan = new RoutePlan("Native cruising handoff",
        [
            new RouteWaypoint("Start", new Coordinate(48.25, -123.65)),
            new RouteWaypoint("Hold", new Coordinate(48.25, -123.50), TimeSpan.FromMinutes(5)),
            new RouteWaypoint("Finish", new Coordinate(48.25, -123.35))
        ]).WithRoutingSetup(setup);
        var descriptor = await new NativeLocalGribInspector(bridge).InspectAsync(sample);
        var repository = new RoutePlanJsonRepository(directory.Path);
        var engine = new NativeRouteEngine(bridge, executionDirectory: Path.Combine(directory.Path, "execution"));
        var setupService = new NativeRoutingSetupService(bridge, boats, executionDirectory: Path.Combine(directory.Path, "execution"));
        var workflow = new RoutePlanRoutingWorkflow(
            new RoutingWorkflow([], engine), repository,
            stopoverValidator: new NativeStopoverValidator(bridge), setupService: setupService);
        var result = await workflow.ExecuteAsync(new RoutePlanRoutingRequest(
            plan, descriptor.ValidFrom, descriptor.ValidFrom.AddHours(10), [ForecastSelection.LocalFile(descriptor)]));

        Assert.True(result.Status == RoutePlanRoutingStatus.Succeeded,
            string.Join("; ", result.Models.SelectMany(model => model.Legs)
                .Select(leg => $"{leg.State}/{leg.Reason}: {leg.Detail}")));
        var before = result.Plan.LatestResult(descriptor.Model)!;
        Assert.Equal(2, before.Legs.Length);
        var inbound = before.Legs[0];
        var outbound = before.Legs[1];
        Assert.True(inbound.Route!.IsComplete);
        Assert.True(outbound.Route!.IsComplete);
        Assert.Equal(inbound.Route.Points[^1].Location, outbound.Route.Request.Origin);
        Assert.Equal(inbound.Route.ArrivalTime.AddMinutes(5), outbound.Route.Request.DepartureTime);
        Assert.Equal(RouteLegOriginSource.AcceptedPredecessor, outbound.Origin!.Source);
        Assert.Equal(inbound.Route.Request.RouteId, outbound.Origin.Predecessor!.RouteId);
        Assert.Equal(RouteHoldCheckStatus.NoExclusionsConfigured, inbound.PlannedHold!.Status);
        Assert.True(outbound.Route.LandAvoidance.IsApplied);
        Assert.True(outbound.Route.NativeAudit!.NativeLandmaskApplied);
        Assert.Equal(boat.ContentIdentity, outbound.Route.RunAudit!.Setup.Boat.ContentIdentity);
        Assert.Equal(coastal, outbound.Route.Diagnostics.CoastalPruning is not null);

        var loaded = await new RoutePlanJsonRepository(directory.Path).OpenAsync(plan.Id);
        var after = loaded.LatestResult(descriptor.Model)!;
        Assert.Equal(setup, loaded.RoutingSetup);
        for (var index = 0; index < before.Legs.Length; index++)
        {
            Assert.Equal(before.Legs[index].Route!.Points.ToArray(), after.Legs[index].Route!.Points.ToArray());
            Assert.Equal(before.Legs[index].ExecutionSession, after.Legs[index].ExecutionSession);
            Assert.Equal(before.Legs[index].Origin, after.Legs[index].Origin);
            Assert.Equal(before.Legs[index].PlannedHold, after.Legs[index].PlannedHold);
            Assert.Equal(JsonSerializer.Serialize(before.Legs[index].Route!.RunAudit),
                JsonSerializer.Serialize(after.Legs[index].Route!.RunAudit));
            Assert.Equal(JsonSerializer.Serialize(before.Legs[index].Route!.NativeAudit),
                JsonSerializer.Serialize(after.Legs[index].Route!.NativeAudit));
        }
        var copy = await repository.SaveAsAsync(loaded, "Copied native itinerary");
        var copied = copy.LatestResult(descriptor.Model)!;
        Assert.Equal(copy.Id, copied.Legs[1].Origin!.Predecessor!.PlanId);
        Assert.Equal(inbound.Route.RunAudit!.CalculationId, copied.Legs[0].Route!.RunAudit!.CalculationId);
        Assert.Equal(inbound.ExecutionSession!.Id, copied.Legs[0].ExecutionSession!.Id);

        var exclusions = new RouteExclusionOptions(
            [new RouteExclusionZone("closed-during-hold", "native integration fixture",
                [new RouteExclusionPolygon(new RouteExclusionRing(
                    [new(48.1, -123.7), new(48.4, -123.7), new(48.4, -123.3), new(48.1, -123.3)]))],
                activeFrom: inbound.Route.ArrivalTime.AddMinutes(30))],
            new RouteProviderMetadata("timed hold", "native fixture", "1"));
        var protectedPlan = loaded.ChangeStopover(loaded.Waypoints[1].Id, TimeSpan.FromHours(2));
        var protectedResult = await workflow.ExecuteAsync(new RoutePlanRoutingRequest(
            protectedPlan, descriptor.ValidFrom, descriptor.ValidFrom.AddHours(10),
            [ForecastSelection.LocalFile(descriptor)],
            optimization: new RouteOptimizationOptions(maximumTrueWindSpeedKnots: 45,
                environment: new RouteEnvironmentOptions(exclusions: exclusions))));
        var protectedLegs = Assert.Single(protectedResult.Models).Legs;
        Assert.True(protectedLegs[0].State == RouteLegOutcomeState.Succeeded, protectedLegs[0].Detail);
        Assert.Equal(45, protectedLegs[0].Route!.NativeAudit!.Routing!.MaximumForecastWindKnots);
        Assert.Equal(RouteHoldCheckStatus.Conflict, protectedLegs[0].PlannedHold!.Status);
        Assert.Equal("closed-during-hold", protectedLegs[0].PlannedHold!.ConflictZoneIdentifier);
        Assert.Equal(RouteLegOutcomeState.Blocked, protectedLegs[1].State);
        Assert.Equal(RouteLegOutcomeReason.StopoverExclusionConflict, protectedLegs[1].Reason);

        File.Delete(source);
        File.Delete(Assert.Single(Directory.EnumerateFiles(boats.RootDirectory, "*.polar")));
        var history = await repository.OpenAsync(copy.Id);
        Assert.All(history.LatestResult(descriptor.Model)!.Legs, leg => Assert.NotNull(leg.Route));
        Assert.Empty(Directory.EnumerateFiles(Path.Combine(directory.Path, "execution")));
    }
}
