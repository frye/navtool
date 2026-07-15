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

public sealed class DeferredNativeRouteEngine : IRouteEngine, IWeatherSampler
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
            LazyThreadSafetyMode.ExecutionAndPublication);
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
