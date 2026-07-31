using Microsoft.Extensions.DependencyInjection;
using Navtool.App.Services;
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
