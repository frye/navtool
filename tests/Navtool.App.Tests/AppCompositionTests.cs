using BruTile.Cache;
using Microsoft.Extensions.DependencyInjection;
using Navtool.App.Services;
using Navtool.App.ViewModels;
using Navtool.Core;
using Navtool.Infrastructure;

namespace Navtool.App.Tests;

public sealed class AppCompositionTests
{
    [Fact]
    public void Uses_bundled_land_data_when_endpoint_is_not_configured()
    {
        WithLandEndpoint(null, services =>
        {
            Assert.IsType<NaturalEarthLandDataProvider>(
                services.GetRequiredService<ILandDataProvider>());
        });
    }

    [Fact]
    public void Uses_osm_land_data_when_endpoint_is_configured()
    {
        WithLandEndpoint("https://land.example.test/geometry", services =>
        {
            Assert.IsType<OsmLandDataProvider>(
                services.GetRequiredService<ILandDataProvider>());
        });
    }

    [Fact]
    public void Registers_route_plan_repository_under_app_data_routes()
    {
        var previous = Environment.GetEnvironmentVariable(
            AppComposition.AppDataRootEnvironmentVariable);
        var root = Path.Combine(Path.GetTempPath(), $"navtool-composition-{Guid.NewGuid():N}");
        try
        {
            Environment.SetEnvironmentVariable(AppComposition.AppDataRootEnvironmentVariable, root);
            using var services = AppComposition.CreateServices();

            var repository = Assert.IsType<RoutePlanJsonRepository>(
                services.GetRequiredService<IRoutePlanRepository>());
            Assert.Equal(Path.Combine(root, "routes"), repository.RootDirectory);
            Assert.NotNull(services.GetRequiredService<RoutePlanRoutingWorkflow>());
            Assert.NotNull(services.GetRequiredService<EcmwfOpenDataForecastProvider>());
            Assert.Equal(
                [ForecastModel.NoaaGfs, ForecastModel.EcmwfIfs],
                services.GetServices<IForecastDownloadEstimator>()
                    .Select(estimator => estimator.Model));
            Assert.NotNull(services.GetRequiredService<MainViewModel>().Itinerary);
            var tileOptions = services.GetRequiredService<OsmTileOptions>();
            Assert.Equal(
                Path.Combine(root, "map-tile-cache"),
                tileOptions.CacheDirectory);
            Assert.Equal(TimeSpan.FromDays(7), OsmTileOptions.CacheRetention);
            Assert.IsType<FileCache>(tileOptions.CreatePersistentCache());
        }
        finally
        {
            Environment.SetEnvironmentVariable(
                AppComposition.AppDataRootEnvironmentVariable,
                previous);
            if (Directory.Exists(root))
            {
                Directory.Delete(root, recursive: true);
            }
        }
    }

    private static void WithLandEndpoint(
        string? value,
        Action<ServiceProvider> assertion)
    {
        var previous = Environment.GetEnvironmentVariable(
            AppComposition.LandDataEndpointEnvironmentVariable);
        try
        {
            Environment.SetEnvironmentVariable(
                AppComposition.LandDataEndpointEnvironmentVariable,
                value);
            using var services = AppComposition.CreateServices();
            assertion(services);
        }
        finally
        {
            Environment.SetEnvironmentVariable(
                AppComposition.LandDataEndpointEnvironmentVariable,
                previous);
        }
    }
}
