using Navtool.Core;

namespace Navtool.App.Tests;

internal sealed class TestRoutingSetupService : IBoatAssetService, IRoutingSetupService
{
    internal static BoatAsset Demo { get; } = new(
        "test-explicit-demo", "Test demonstration boat", BoatAssetKind.Demo,
        BoatPolarFormat.NativeMatrix, new BoatValidationSummary("Validated test demo"));

    public Func<RoutingSetup, RoutingProfessionalOverrides?, ValueTask<RoutingCalculationContext>>? Freeze { get; init; }
    public int FreezeCalls { get; private set; }

    public ValueTask<BoatAsset> ImportAsync(string path, BoatPolarFormat format, CancellationToken cancellationToken = default) =>
        throw new NotSupportedException("Test import must be explicitly configured.");
    public ValueTask<BoatAsset> GetDemoAsync(CancellationToken cancellationToken = default) => ValueTask.FromResult(Demo);
    public ValueTask<ResolvedBoatAsset> ResolveAsync(BoatAsset asset, CancellationToken cancellationToken = default) =>
        ValueTask.FromResult(new ResolvedBoatAsset(asset));

    public ValueTask<RoutingCalculationContext> FreezeAsync(
        RoutingSetup setup, RoutingProfessionalOverrides? professionalOverrides = null,
        CancellationToken cancellationToken = default)
    {
        FreezeCalls++;
        return Freeze?.Invoke(setup, professionalOverrides) ??
               ValueTask.FromResult(CreateContext(setup, professionalOverrides));
    }

    internal static RoutingCalculationContext CreateContext(
        RoutingSetup setup, RoutingProfessionalOverrides? professionalOverrides = null) =>
        new(Guid.NewGuid(), setup, new ResolvedBoatAsset(setup.Boat),
            new NativeRoutingIdentity(8, "test-native", "test-revision", "test-build", ulong.MaxValue),
            new ResolvedRoutingOptions(setup.Quality,
                professionalOverrides?.Optimization ?? RouteOptimizationOptions.Balanced,
                new RouteSearchSettings(TimeSpan.FromMinutes(30), TimeSpan.FromMinutes(10), 5, 1,
                    4, 1, 100000, 10000, 1, false, true, true, 0, 0, []),
                setup.PerformanceFactor, setup.ArrivalRadiusNauticalMiles, setup.HardDuration),
            professionalOverrides);

    internal static RouteResult WithConfiguredAudit(RouteResult route,
        RoutingCalculationContext context, RouteOptimizationOptions optimization, ForecastAcquisition forecast) =>
        new(route.Request, route.Model, route.Points, route.Diagnostics, route.Completion,
            route.LandAvoidance, optimization.Solver,
            optimization.Solver == RouteSolver.TimeDependentLattice ? route.LatticeDiagnostics : null,
            route.Environment, route.EnvironmentDiagnostics,
            nativeAudit: new RouteNativeRunAudit("route_result_v2", optimization.Solver,
                context.Resolved.ArrivalRadiusNauticalMiles, context.Resolved.HardDuration,
                Routing: new RouteNativeRunMetadata("earliest_arrival", "best_found", optimization.Solver,
                    route.Request.Destination, context.Resolved.ArrivalRadiusNauticalMiles,
                    ForecastCorridor.GreatCircleDistanceNauticalMiles(route.Points[^1].Location, route.Request.Destination),
                    context.Resolved.PerformanceFactor, context.Resolved.Search.HeadingStepDegrees,
                    context.Resolved.Search.SpatialBucketNauticalMiles, context.Resolved.Search.MaximumIntegrationStep,
                    context.Resolved.Search.StrategicRetention, false,
                    optimization.WindSampling, optimization.AbovePolarRange,
                    optimization.MaximumTrueWindSpeedKnots, optimization.Maneuver.TackPenalty, optimization.Maneuver.GybePenalty,
                    forecast.Run.InitializedAt, forecast.Request.From,
                    route.ArrivalTime > forecast.Request.Through ? route.ArrivalTime : forecast.Request.Through, [])));
}
