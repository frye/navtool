using Navtool.Core;

namespace Navtool.Infrastructure.Tests;

internal static class NativeIntegration
{
    internal static bool Required =>
        Environment.GetEnvironmentVariable("NAVTOOL_REQUIRE_NATIVE_TESTS") == "1" ||
        Environment.GetEnvironmentVariable("NAVTOOL_NATIVE_REQUIRED") == "1";

    internal static string? Sample()
    {
        var configured = Environment.GetEnvironmentVariable("NAVTOOL_ROUTER_SAMPLE_GRIB");
        var repository = Repository();
        if (Required && string.IsNullOrWhiteSpace(configured))
            throw new InvalidOperationException("Required native tests need explicit NAVTOOL_ROUTER_SAMPLE_GRIB.");
        var path = string.IsNullOrWhiteSpace(configured)
            ? Path.Combine(repository, "native", "Navtool.RouterBridge", "build", "_deps", "sailroute-src", "samples", "sample.grib")
            : Path.GetFullPath(configured);
        RequireInWorktree(path, repository);
        if (File.Exists(path)) return path;
        if (Required || !string.IsNullOrWhiteSpace(configured))
            throw new FileNotFoundException("Native integration fixture is missing.", path);
        return null;
    }

    internal static string? Fixture(string name)
    {
        var configured = Environment.GetEnvironmentVariable("NAVTOOL_ROUTER_V8_FIXTURE_DIR");
        if (Required && string.IsNullOrWhiteSpace(configured))
            throw new InvalidOperationException("Required ABI8 fixture tests need explicit NAVTOOL_ROUTER_V8_FIXTURE_DIR.");
        var directory = string.IsNullOrWhiteSpace(configured)
            ? Path.Combine(Repository(), "native", "Navtool.RouterBridge", "build", "fixtures-v8") : Path.GetFullPath(configured);
        var path = Path.Combine(directory, name);
        RequireInWorktree(path, Repository());
        if (File.Exists(path)) return path;
        if (Required || !string.IsNullOrWhiteSpace(configured))
            throw new FileNotFoundException("Required ABI8 native-controlled fixture is missing.", path);
        return null;
    }

    internal static NativeRouterBridge? Bridge()
    {
        var configured = Environment.GetEnvironmentVariable("NAVTOOL_ROUTER_BRIDGE_PATH");
        if (Required && string.IsNullOrWhiteSpace(configured))
            throw new InvalidOperationException("Required native tests need explicit NAVTOOL_ROUTER_BRIDGE_PATH.");
        if (!string.IsNullOrWhiteSpace(configured))
        {
            var path = Path.GetFullPath(configured);
            RequireInWorktree(path, Repository());
            if (!File.Exists(path) && !Directory.Exists(path))
                throw new FileNotFoundException("Explicit native bridge path is missing.", path);
        }
        try { return new NativeRouterBridge(); }
        catch (NativeBridgeUnavailableException) when (!Required && string.IsNullOrWhiteSpace(configured)) { return null; }
    }

    internal static string Repository()
    {
        var directory = new DirectoryInfo(AppContext.BaseDirectory);
        while (directory is not null)
        {
            if (File.Exists(Path.Combine(directory.FullName, "Navtool.sln"))) return directory.FullName;
            directory = directory.Parent;
        }
        throw new InvalidOperationException("Native tests could not locate their current worktree.");
    }

    private static void RequireInWorktree(string path, string repository)
    {
        var comparison = OperatingSystem.IsWindows() || OperatingSystem.IsMacOS()
            ? StringComparison.OrdinalIgnoreCase : StringComparison.Ordinal;
        if (!Path.GetFullPath(path).StartsWith(Path.GetFullPath(repository) + Path.DirectorySeparatorChar, comparison))
            throw new InvalidOperationException("Native tests may only use artifacts and fixtures from their current worktree.");
    }

    internal static RouteResult CalculateDemoRoute(this NativeRouterBridge bridge, NativeForecast forecast,
        RouteRequest request, ForecastModel model, RouteOptimizationOptions? optimization = null,
        Action<RouteCalculationSnapshot>? onProgress = null,
        Func<Coordinate, Coordinate, bool>? isSegmentEligible = null,
        CancellationToken cancellationToken = default)
    {
        using var polar = bridge.CreateDemoPolar(cancellationToken);
        var options = bridge.GetQualityDefaults();
        if (optimization is not null) options = options with { Optimization = optimization };
        return bridge.CalculateRoute(forecast, polar, request, model, options, onProgress, isSegmentEligible, cancellationToken);
    }

    internal static RouteResult CalculateDemoRoute(this NativeRouterBridge bridge, NativeForecast forecast,
        RouteRequest request, ForecastModel model, Action<RouteCalculationSnapshot> onProgress) =>
        bridge.CalculateDemoRoute(forecast, request, model, onProgress: onProgress, optimization: null);

    internal static RouteResult CalculateDemoRoute(this NativeRouterBridge bridge, NativeForecast forecast,
        RouteRequest request, ForecastModel model, Func<Coordinate, Coordinate, bool> isSegmentEligible) =>
        bridge.CalculateDemoRoute(forecast, request, model, isSegmentEligible: isSegmentEligible, optimization: null);

    internal static RouteSearchSettings Search(RouteSearchSettings value, ulong? generated = null,
        ulong? bucketCapacity = null, double? spatialBucket = null, double? headingStep = null,
        TimeSpan? timeStep = null, bool? intervals = null, bool? strategic = null, double? minimumSpeed = null) =>
        new(timeStep ?? value.TimeStep, value.MaximumIntegrationStep, headingStep ?? value.HeadingStepDegrees,
            spatialBucket ?? value.SpatialBucketNauticalMiles, bucketCapacity ?? value.MaxNodesPerBucket, 1,
            generated ?? value.MaximumGeneratedCandidates, value.MaximumRetainedNodes, value.ProgressEveryNSteps,
            intervals ?? value.UseRoutingIntervals, strategic ?? value.StrategicRetention,
            value.CaptureIsochrones, value.DestinationFrontMode, minimumSpeed ?? value.MinimumBoatSpeedKnots, value.Intervals);
}
