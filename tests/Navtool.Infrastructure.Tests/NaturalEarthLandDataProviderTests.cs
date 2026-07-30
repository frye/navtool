using Navtool.Core;
using Navtool.Infrastructure;

namespace Navtool.Infrastructure.Tests;

public sealed class NaturalEarthLandDataProviderTests
{
    [Fact]
    public async Task Bundled_provider_loads_global_land_geometry_once()
    {
        var provider = new NaturalEarthLandDataProvider();
        var bounds = new GeographicBounds(-90, 90, -180, 180);

        var first = await provider.AcquireAsync(bounds);
        var second = await new NaturalEarthLandDataProvider().AcquireAsync(bounds);

        Assert.Equal(LandDataStatus.Available, first.Status);
        Assert.NotNull(first.Geometry);
        Assert.True(first.Geometry.Contains(new Coordinate(39.7392, -104.9903)));
        Assert.False(first.Geometry.Contains(new Coordinate(0, -140)));
        Assert.Equal(NaturalEarthLandDataProvider.Attribution, first.Attribution);
        Assert.Same(first, second);
    }
}
