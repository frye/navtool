using System.Collections.Immutable;
using Microsoft.Extensions.Logging;
using Navtool.Core;
using Navtool.Infrastructure;

namespace Navtool.App.Services;

public interface IWeatherSampler
{
    ValueTask<ImmutableArray<ViewportWindSample>> SampleViewportAsync(
        ForecastAcquisition forecast,
        GeographicBounds bounds,
        int latitudeCount,
        int longitudeCount,
        DateTimeOffset validAt,
        CancellationToken cancellationToken = default);
}

public sealed class DeferredNativeRouteEngine : IRouteEngine, IWeatherSampler, INativeRoutingPreflight
{
    private readonly Lazy<NativeRouteEngine> _engine;

    public DeferredNativeRouteEngine()
        : this(() => new NativeRouteEngine(new NativeRouterBridge()))
    {
    }

    public DeferredNativeRouteEngine(ILogger<NativeRouteEngine> logger)
        : this(() => new NativeRouteEngine(new NativeRouterBridge(), logger))
    {
    }

    public DeferredNativeRouteEngine(Func<NativeRouteEngine> factory)
    {
        ArgumentNullException.ThrowIfNull(factory);
        _engine = new Lazy<NativeRouteEngine>(
            factory,
            LazyThreadSafetyMode.PublicationOnly);
    }

    /// <summary>
    /// Performs a lightweight preflight check to verify that the native router
    /// bridge library is present and exposes the expected ABI version. Call this
    /// before initiating any HTTP forecast acquisition to surface problems early
    /// with actionable error messages.
    /// </summary>
    /// <exception cref="NativeBridgeUnavailableException">
    /// The native library could not be found, does not export the versioned ABI,
    /// or is for an incompatible platform.
    /// </exception>
    /// <exception cref="NotSupportedException">
    /// The library ABI version does not match the required version.
    /// </exception>
    public void EnsureAvailable()
    {
        // Materializing the engine constructs NativeRouterBridge, which calls
        // navtool_router_bridge_abi_version_v1() and validates the version.
        // No GRIB file is loaded. PublicationOnly does not cache factory
        // exceptions, so a corrected bridge installation can be retried.
        _ = _engine.Value;
    }

    public ValueTask<RouteResult> CalculateAsync(
        RouteRequest request,
        ForecastAcquisition forecast,
        IProgress<RouteCalculationProgress>? progress,
        CancellationToken cancellationToken) =>
        _engine.Value.CalculateAsync(request, forecast, progress, cancellationToken);

    public ValueTask<ImmutableArray<ViewportWindSample>> SampleViewportAsync(
        ForecastAcquisition forecast,
        GeographicBounds bounds,
        int latitudeCount,
        int longitudeCount,
        DateTimeOffset validAt,
        CancellationToken cancellationToken = default) =>
        _engine.Value.SampleViewportAsync(
            forecast,
            bounds,
            latitudeCount,
            longitudeCount,
            validAt,
            cancellationToken);
}
