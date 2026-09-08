using Navtool.Core;

namespace Navtool.Infrastructure.Tests;

public sealed class NativeConfiguredEngineIntegrationTests
{
    [Fact]
    public async Task Workflow_preserves_observed_native_forecast_audit_through_final_publication()
    {
        var bridge = NativeIntegration.Bridge();
        var sample = NativeIntegration.Sample();
        if (bridge is null || sample is null) return;
        using var directory = new TestDirectory();
        var boats = new DemoBoats(bridge.InspectDemoPolar());
        var setup = new RoutingSetup(await boats.GetDemoAsync(), landSource: RoutingLandSource.None);
        var context = await new NativeRoutingSetupService(bridge, boats, executionDirectory: directory.Path).FreezeAsync(setup);
        using var loaded = bridge.LoadForecast(sample);
        var request = new RouteRequest("workflow-native-audit", new Coordinate(48.25, -123.65), new Coordinate(48.25, -123.35),
            loaded.Metadata.FirstValidAt, loaded.Metadata.FirstValidAt.AddHours(10));
        var run = new ForecastRun(ForecastProvider.Noaa, ForecastModel.NoaaGfs, loaded.Metadata.InitializedAt);
        var workflow = new RoutingWorkflow([new FixtureForecastProvider(run, new LocalGribArtifact(sample))],
            new NativeRouteEngine(bridge, executionDirectory: directory.Path));
        var result = await workflow.ExecuteAsync(new RoutingWorkflowRequest(request, new[] { ForecastModel.NoaaGfs },
            new GeographicBounds(48, 48.5, -123.75, -123.25), calculationContext: context));
        var outcome = Assert.Single(result.Outcomes);
        Assert.True(outcome.Route is not null, outcome.Failure?.Message);
        var audit = outcome.Route!.RunAudit!.Forecast!;
        Assert.Equal(loaded.Metadata.FirstValidAt, audit.ValidFrom);
        Assert.Equal(loaded.Metadata.LastValidAt, audit.ValidThrough);
        Assert.Equal(loaded.Metadata.MinimumTimeSpacing, audit.MinimumTimeSpacing);
        Assert.Equal(loaded.Metadata.MaximumTimeSpacing, audit.MaximumTimeSpacing);
        Assert.Equal(loaded.Metadata.ValidTimes.ToArray(), audit.ValidTimes.ToArray());
    }

    [Fact]
    public async Task Gshhg_source_is_validated_before_acquisition_and_flows_through_configured_engine_without_substitution()
    {
        var bridge = NativeIntegration.Bridge();
        var sample = NativeIntegration.Sample();
        if (bridge is null || sample is null) return;
        using var directory = new TestDirectory();
        var source = Path.Combine(directory.Path, "selected-gshhg.b");
        NativeV8IntegrationTests.WriteGshhgIsland(source);
        var sourceService = new NativeRegionalLandSourceService(bridge);
        var options = new RegionalLandOptions(new GeographicBounds(48.1, 48.4, -123.7, -123.3), 5, 10);
        var estimate = sourceService.Estimate(options);
        var policy = await sourceService.ValidateSourceAsync(source, options);
        var boats = new DemoBoats(bridge.InspectDemoPolar());
        var setup = new RoutingSetup(await boats.GetDemoAsync(), landSource: RoutingLandSource.RegionalGshhg, regionalLand: policy);
        var polygons = new MissingLand();
        var setupService = new NativeRoutingSetupService(bridge, boats, polygons, directory.Path);
        var context = await setupService.FreezeAsync(setup);
        var engine = new NativeRouteEngine(bridge, landDataProvider: polygons, executionDirectory: directory.Path);
        using var loaded = bridge.LoadForecast(sample);
        var request = new RouteRequest("gshhg-configured", new Coordinate(48.25, -123.65), new Coordinate(48.25, -123.35),
            loaded.Metadata.FirstValidAt, loaded.Metadata.FirstValidAt.AddHours(10));
        var forecastBounds = new GeographicBounds(48, 48.5, -123.75, -123.25);
        var acquisition = new ForecastAcquisition(new ForecastRequest(ForecastModel.NoaaGfs, forecastBounds,
            request.DepartureTime, request.LatestArrivalTime),
            new ForecastRun(ForecastProvider.Noaa, ForecastModel.NoaaGfs, loaded.Metadata.InitializedAt),
            new LocalGribArtifact(sample), ForecastAcquisitionSource.LocalFile);
        var result = await engine.CalculateConfiguredAsync(context, request, acquisition, context.Resolved.Optimization, null, default);
        Assert.True(result.IsComplete);
        Assert.True(result.NativeAudit!.NativeLandmaskApplied);
        Assert.True(result.LandAvoidance.IsApplied);
        Assert.Equal(policy.SourceIdentity, result.RunAudit!.Setup.RegionalLand!.SourceIdentity);
        Assert.Equal(forecastBounds, result.RunAudit.Forecast!.DeclaredBounds);
        Assert.Equal(options.Bounds, result.RunAudit.Setup.RegionalLand.StudyBounds);
        Assert.Equal(estimate.NativeNumericalAllowanceNauticalMiles, result.Environment!.LandInterpolationErrorNauticalMiles!.Value, 6);
        Assert.Equal(0, polygons.Calls);
        var workflow = new RoutingWorkflow([new FixtureForecastProvider(acquisition.Run, acquisition.Artifact)], engine);
        var published = await workflow.ExecuteAsync(new RoutingWorkflowRequest(request, new[] { ForecastModel.NoaaGfs },
            options.Bounds, calculationContext: context));
        var outcome = Assert.Single(published.Outcomes);
        Assert.True(outcome.Route is { IsComplete: true }, outcome.Failure?.Message);
        Assert.True(outcome.Route!.NativeAudit!.NativeLandmaskApplied);
        Assert.Equal(policy.SourceIdentity, outcome.Route.RunAudit!.Setup.RegionalLand!.SourceIdentity);
        File.AppendAllText(source, "changed");
        var changed = await Assert.ThrowsAsync<RoutingException>(async () => await setupService.FreezeAsync(setup));
        Assert.Equal(RoutingFailureKind.MissingRequiredSource, changed.Kind);
        Assert.Equal(0, polygons.Calls);
        var tooFine = options with { Bounds = new GeographicBounds(48, 48.5, -124, -123), ResolutionNauticalMiles = .05 };
        var budget = Assert.Throws<NativeRouterException>(() => bridge.LoadRegionalLand(Path.Combine(directory.Path, "absent.b"), tooFine));
        Assert.Equal(RoutingFailureKind.ResourceLimit, budget.Kind);
    }

    [Fact]
    public async Task Configured_engine_loads_frozen_imported_bytes_and_cleans_execution_materialization()
    {
        var bridge = NativeIntegration.Bridge();
        var sample = NativeIntegration.Sample();
        var polarPath = NativeIntegration.Fixture("slow.csv");
        if (bridge is null || sample is null || polarPath is null) return;
        using var directory = new TestDirectory();
        var bytes = File.ReadAllBytes(polarPath);
        var metadata = bridge.InspectPolar(polarPath, BoatPolarFormat.NativeMatrix);
        var asset = new BoatAsset("selected-slow-polar", "Imported cruising boat", BoatAssetKind.Imported,
            BoatPolarFormat.NativeMatrix, metadata);
        var boat = new ResolvedBoatAsset(asset, bytes);
        Array.Fill(bytes, (byte)0);
        var setup = new RoutingSetup(asset, landSource: RoutingLandSource.None);
        var resolved = bridge.ResolveRoutingOptions(setup);
        var context = new RoutingCalculationContext(Guid.NewGuid(), setup, boat, bridge.BuildIdentity, resolved);
        var engine = new NativeRouteEngine(bridge, executionDirectory: directory.Path);
        using var loaded = bridge.LoadForecast(sample);
        var request = new RouteRequest("imported-context", new Coordinate(48.25, -123.65), new Coordinate(48.25, -123.35),
            loaded.Metadata.FirstValidAt, loaded.Metadata.FirstValidAt.AddHours(10));
        var acquisition = new ForecastAcquisition(new ForecastRequest(ForecastModel.NoaaGfs,
            new GeographicBounds(48, 48.5, -123.75, -123.25), request.DepartureTime, request.LatestArrivalTime),
            new ForecastRun(ForecastProvider.Noaa, ForecastModel.NoaaGfs, loaded.Metadata.InitializedAt),
            new LocalGribArtifact(sample), ForecastAcquisitionSource.LocalFile);
        var result = await engine.CalculateConfiguredAsync(context, request, acquisition, resolved.Optimization, null, default);
        Assert.True(result.IsComplete);
        Assert.Equal(asset.ContentIdentity, result.RunAudit!.Setup.Boat.ContentIdentity);
        Assert.Contains(result.Points.Skip(1), point => point.BoatSpeedKnots > 0 && point.BoatSpeedKnots <= 5);
        Assert.Empty(Directory.GetFiles(directory.Path));
    }

    [Fact]
    public async Task Setup_freezes_explicit_boat_and_engine_preserves_actual_forecast_and_polygon_ownership()
    {
        var bridge = NativeIntegration.Bridge();
        var sample = NativeIntegration.Sample();
        if (bridge is null || sample is null) return;
        using var directory = new TestDirectory();
        var boats = new DemoBoats(bridge.InspectDemoPolar());
        var setup = new RoutingSetup(await boats.GetDemoAsync(), landSource: RoutingLandSource.NaturalEarth);
        var provider = new NaturalEarthLandDataProvider();
        var service = new NativeRoutingSetupService(bridge, boats, provider, directory.Path);
        var context = await service.FreezeAsync(setup);
        var engine = new NativeRouteEngine(bridge, landDataProvider: provider);
        using var loaded = bridge.LoadForecast(sample);
        var bounds = new GeographicBounds(48, 48.5, -123.75, -123.25);
        var request = new RouteRequest("configured", new Coordinate(48.25, -123.65), new Coordinate(48.25, -123.35),
            loaded.Metadata.FirstValidAt, loaded.Metadata.FirstValidAt.AddHours(10));
        var forecast = new ForecastAcquisition(
            new ForecastRequest(ForecastModel.NoaaGfs, bounds, request.DepartureTime, request.LatestArrivalTime),
            new ForecastRun(ForecastProvider.Noaa, ForecastModel.NoaaGfs, loaded.Metadata.InitializedAt),
            new LocalGribArtifact(sample), ForecastAcquisitionSource.LocalFile);
        var result = await engine.CalculateConfiguredAsync(context, request, forecast, context.Resolved.Optimization, null, default);
        Assert.True(result.IsComplete);
        Assert.True(result.LandAvoidance.IsApplied);
        Assert.Contains("Natural Earth", result.LandAvoidance.Attribution);
        Assert.False(result.NativeAudit!.NativeLandmaskApplied);
        Assert.Equal(context.CalculationId, result.RunAudit!.CalculationId);
        Assert.Equal(loaded.Metadata.InitializedAt, result.RunAudit.Forecast!.Run.InitializedAt);
        Assert.NotNull(result.RunAudit.Forecast.EffectiveBounds);
        Assert.NotNull(result.RunAudit.Forecast.ValidThrough);
        Assert.Equal(loaded.Metadata.MinimumTimeSpacing, result.RunAudit.Forecast.MinimumTimeSpacing);
        Assert.Equal(loaded.Metadata.MaximumTimeSpacing, result.RunAudit.Forecast.MaximumTimeSpacing);
        Assert.Equal(loaded.Metadata.ValidTimes.ToArray(), result.RunAudit.Forecast.ValidTimes.ToArray());
        Assert.Equal(1, result.RunAudit.Resolved.PerformanceFactor);
        Assert.Empty(Directory.GetFiles(directory.Path));
    }

    [Fact]
    public async Task Required_land_missing_geometry_blocks_setup_and_configured_search()
    {
        var bridge = NativeIntegration.Bridge();
        if (bridge is null) return;
        using var directory = new TestDirectory();
        var boats = new DemoBoats(bridge.InspectDemoPolar());
        var setup = new RoutingSetup(await boats.GetDemoAsync());
        var provider = new MissingLand();
        var service = new NativeRoutingSetupService(bridge, boats, provider, directory.Path);
        var failure = await Assert.ThrowsAsync<RoutingException>(async () => await service.FreezeAsync(setup));
        Assert.Equal(RoutingFailureKind.MissingRequiredSource, failure.Kind);
        var resolved = bridge.ResolveRoutingOptions(setup);
        var context = new RoutingCalculationContext(Guid.NewGuid(), setup, await boats.ResolveAsync(setup.Boat), bridge.BuildIdentity, resolved);
        var now = DateTimeOffset.Parse("2026-07-15T00:00:00Z");
        var request = new RouteRequest("missing-land", new Coordinate(0, 0), new Coordinate(1, 1), now, now.AddHours(10));
        var forecast = new ForecastAcquisition(new ForecastRequest(ForecastModel.NoaaGfs, new GeographicBounds(-1, 2, -1, 2), now, now.AddHours(10)),
            new ForecastRun(ForecastProvider.Noaa, ForecastModel.NoaaGfs, now),
            new LocalGribArtifact(Path.Combine(directory.Path, "does-not-exist.grib")), ForecastAcquisitionSource.LocalFile);
        var engine = new NativeRouteEngine(bridge, landDataProvider: provider);
        failure = await Assert.ThrowsAsync<RoutingException>(async () =>
            await engine.CalculateConfiguredAsync(context, request, forecast, resolved.Optimization, null, default));
        Assert.Equal(RoutingFailureKind.MissingRequiredSource, failure.Kind);
        Assert.Equal(2, provider.Calls);
    }

    private sealed class MissingLand : ILandDataProvider
    {
        public int Calls { get; private set; }
        public ValueTask<LandDataAcquisition> AcquireAsync(GeographicBounds bounds, CancellationToken cancellationToken = default)
        {
            Calls++;
            return ValueTask.FromResult(new LandDataAcquisition(LandDataStatus.Available, null, null, "required source"));
        }

    }

    private sealed class FixtureForecastProvider(ForecastRun run, LocalGribArtifact artifact) : IForecastProvider
    {
        public ForecastProvider Provider => run.Provider;
        public ForecastModel Model => run.Model;
        public ValueTask<ForecastAcquisition> AcquireAsync(ForecastRequest request, IProgress<ForecastProgress>? progress,
            CancellationToken cancellationToken) =>
            ValueTask.FromResult(new ForecastAcquisition(request, run, artifact, ForecastAcquisitionSource.Remote));
    }

    private sealed class DemoBoats(BoatValidationSummary validation) : IBoatAssetService
    {
        public ValueTask<BoatAsset> GetDemoAsync(CancellationToken cancellationToken = default) =>
            ValueTask.FromResult(new BoatAsset("explicit-demo", "Demonstration boat", BoatAssetKind.Demo, BoatPolarFormat.Automatic, validation));
        public ValueTask<ResolvedBoatAsset> ResolveAsync(BoatAsset asset, CancellationToken cancellationToken = default) =>
            ValueTask.FromResult(new ResolvedBoatAsset(asset));
        public ValueTask<BoatAsset> ImportAsync(string path, BoatPolarFormat format, CancellationToken cancellationToken = default) =>
            throw new NotSupportedException();
    }
}
