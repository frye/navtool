using Navtool.Core;
using Navtool.Infrastructure;

namespace Navtool.Infrastructure.Tests;

public sealed class EcmwfLiveSmokeTests
{
    [Fact]
    public async Task Current_open_data_can_be_downloaded_inspected_sampled_and_routed()
    {
        if (!string.Equals(
                Environment.GetEnvironmentVariable("NAVTOOL_ECMWF_LIVE_SMOKE"),
                "1",
                StringComparison.Ordinal))
        {
            return;
        }

        using var directory = new TestDirectory();
        using var client = new HttpClient
        {
            Timeout = TimeSpan.FromMinutes(10)
        };
        var provider = new EcmwfOpenDataForecastProvider(
            client,
            new AtomicFileCache(new AtomicFileCacheOptions(directory.Path)));
        var now = DateTimeOffset.UtcNow;
        var bounds = new GeographicBounds(48, 49, -124, -122);
        var request = new ForecastRequest(
            ForecastModel.EcmwfIfs,
            bounds,
            now.AddHours(1),
            now.AddHours(4),
            ForecastRefreshPolicy.LatestAvailable);

        var acquisition = await provider.AcquireAsync(
            request,
            null,
            CancellationToken.None);
        var bridge = new NativeRouterBridge();
        var descriptor = bridge.InspectGrib(
            acquisition.Artifact.Path,
            CancellationToken.None);

        Assert.Equal(NativeGribModelId.EcmwfIfs, descriptor.ModelId);
        using var forecast = bridge.LoadForecast(
            acquisition.Artifact.Path,
            bounds,
            CancellationToken.None);
        var sampled = bridge.SampleViewport(
            forecast,
            bounds,
            2,
            2,
            forecast.Metadata.FirstValidAt,
            CancellationToken.None);
        Assert.All(sampled, wind => Assert.True(wind.IsValid));

        var route = bridge.CalculateRoute(
            forecast,
            new RouteRequest(
                "ecmwf-live-smoke",
                new Coordinate(48.5, -123.8),
                new Coordinate(48.5, -123.2),
                forecast.Metadata.FirstValidAt,
                forecast.Metadata.LastValidAt),
            ForecastModel.EcmwfIfs,
            cancellationToken: CancellationToken.None);
        Assert.NotEmpty(route.Points);
        Assert.Equal(ForecastModel.EcmwfIfs, route.Model);
    }
}
