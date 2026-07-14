using Navtool.Core;
using Navtool.Infrastructure;

namespace Navtool.Infrastructure.Tests;

public sealed class NativeRouterBridgeIntegrationTests
{
    [Fact]
    public void Native_contract_loads_metadata_samples_and_route_when_artifacts_are_available()
    {
        var repository = FindAncestor(AppContext.BaseDirectory, "Navtool.sln");
        if (repository is null)
        {
            return;
        }

        var sample = Path.GetFullPath(
            Path.Combine(repository, "..", "router-lib", "samples", "sample.grib"));
        if (!File.Exists(sample))
        {
            return;
        }

        NativeRouterBridge bridge;
        try
        {
            bridge = new NativeRouterBridge();
        }
        catch (NativeBridgeUnavailableException)
        {
            return;
        }

        using var forecast = bridge.LoadForecast(sample);
        Assert.Equal(1u, bridge.AbiVersion);
        Assert.True(forecast.Metadata.LatitudeCount > 0);
        Assert.True(forecast.Metadata.FirstValidAt < forecast.Metadata.LastValidAt);

        var bounds = new GeographicBounds(48, 48.5, -123.75, -123.25);
        var samples = bridge.SampleViewport(
            forecast,
            bounds,
            3,
            3,
            forecast.Metadata.FirstValidAt);
        Assert.Equal(9, samples.Length);
        Assert.All(samples, samplePoint => Assert.True(samplePoint.IsValid));

        var request = new RouteRequest(
            "native-integration",
            new Coordinate(48.25, -123.65),
            new Coordinate(48.25, -123.35),
            forecast.Metadata.FirstValidAt,
            forecast.Metadata.FirstValidAt.AddHours(10));
        var route = bridge.CalculateRoute(
            forecast,
            request,
            ForecastModel.NoaaGfs);
        Assert.NotEmpty(route.Points);
        Assert.True(route.Diagnostics.GeneratedCandidates > 0);
        Assert.All(route.Points, point =>
        {
            Assert.True(point.HeadingDegrees is >= 0 and < 360);
            Assert.True(point.TrueWindDirectionDegrees is >= 0 and < 360);
        });
    }

    private static string? FindAncestor(string start, string marker)
    {
        var directory = new DirectoryInfo(start);
        while (directory is not null)
        {
            if (File.Exists(Path.Combine(directory.FullName, marker)))
            {
                return directory.FullName;
            }

            directory = directory.Parent;
        }

        return null;
    }
}
