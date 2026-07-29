using System.Net;
using System.Text;
using Navtool.Core;
using Navtool.Infrastructure;

namespace Navtool.Infrastructure.Tests;

public sealed class OsmLandDataProviderTests
{
    private const string LandGeoJson = """
        {
          "type": "FeatureCollection",
          "attribution": "Test OSM service",
          "features": [
            {
              "type": "Feature",
              "geometry": {
                "type": "Polygon",
                "coordinates": [[[-5,-5],[5,-5],[5,5],[-5,5],[-5,-5]]]
              },
              "properties": {}
            }
          ]
        }
        """;

    [Fact]
    public async Task Unconfigured_provider_returns_a_degraded_result_without_http()
    {
        using var directory = new TestDirectory();
        var handler = new RecordingHttpHandler((_, _, _) =>
            throw new InvalidOperationException("HTTP must not run."));
        var provider = new OsmLandDataProvider(
            new HttpClient(handler),
            new OsmLandDataOptions(null, directory.Path));

        var result = await provider.AcquireAsync(new GeographicBounds(-10, 10, -10, 10));

        Assert.Equal(LandDataStatus.Unconfigured, result.Status);
        Assert.Null(result.Geometry);
        Assert.Contains("NAVTOOL_LAND_DATA_ENDPOINT", result.Warning);
        Assert.Equal(0, handler.RequestCount);
    }

    [Fact]
    public async Task Provider_fetches_indexes_attributes_and_reuses_cached_geometry()
    {
        using var directory = new TestDirectory();
        var handler = new RecordingHttpHandler((_, _, _) =>
            Task.FromResult(GeoJsonResponse(LandGeoJson)));
        var provider = new OsmLandDataProvider(
            new HttpClient(handler),
            new OsmLandDataOptions(new Uri("https://land.example.test/geometry"), directory.Path));
        var bounds = new GeographicBounds(-10, 10, -10, 10);

        var first = await provider.AcquireAsync(bounds);
        var second = await provider.AcquireAsync(bounds);

        Assert.Equal(LandDataStatus.Available, first.Status);
        Assert.NotNull(first.Geometry);
        Assert.True(first.Geometry.Contains(new Coordinate(0, 0)));
        Assert.False(first.Geometry.Contains(new Coordinate(8, 8)));
        Assert.True(first.Geometry.IntersectsSegment(
            new Coordinate(0, -10),
            new Coordinate(0, 10)));
        Assert.Contains("Test OSM service", first.Attribution);
        Assert.Contains("OpenStreetMap contributors", first.Attribution);
        Assert.Same(first.Geometry, second.Geometry);
        Assert.Equal(1, handler.RequestCount);
        Assert.Contains("south=-10", handler.Requests[0].Query);
        Assert.Contains("east=10", handler.Requests[0].Query);
    }

    [Fact]
    public async Task Antimeridian_corridor_is_split_into_two_bounded_requests()
    {
        using var directory = new TestDirectory();
        var handler = new RecordingHttpHandler((_, _, _) =>
            Task.FromResult(GeoJsonResponse("""{"type":"FeatureCollection","features":[]}""")));
        var provider = new OsmLandDataProvider(
            new HttpClient(handler),
            new OsmLandDataOptions(new Uri("https://land.example.test/geometry"), directory.Path));

        var result = await provider.AcquireAsync(
            new GeographicBounds(-10, 10, 170, -170));

        Assert.Equal(LandDataStatus.Available, result.Status);
        Assert.Equal(2, handler.RequestCount);
        Assert.Contains(handler.Requests, uri =>
            uri.Query.Contains("west=170", StringComparison.Ordinal) &&
            uri.Query.Contains("east=180", StringComparison.Ordinal));
        Assert.Contains(handler.Requests, uri =>
            uri.Query.Contains("west=-180", StringComparison.Ordinal) &&
            uri.Query.Contains("east=-170", StringComparison.Ordinal));
    }

    [Fact]
    public async Task Invalid_geojson_degrades_to_an_unavailable_result()
    {
        using var directory = new TestDirectory();
        var handler = new RecordingHttpHandler((_, _, _) =>
            Task.FromResult(GeoJsonResponse("""{"type":"LineString","coordinates":[]}""")));
        var provider = new OsmLandDataProvider(
            new HttpClient(handler),
            new OsmLandDataOptions(new Uri("https://land.example.test/geometry"), directory.Path));

        var result = await provider.AcquireAsync(new GeographicBounds(-10, 10, -10, 10));

        Assert.Equal(LandDataStatus.Unavailable, result.Status);
        Assert.Null(result.Geometry);
        Assert.Contains("not supported", result.Warning, StringComparison.OrdinalIgnoreCase);
    }

    [Theory]
    [InlineData("""{"type":"FeatureCollection","features":[1]}""")]
    [InlineData("""{"type":"Polygon","coordinates":[[["east","north"],["east","north"],["east","north"],["east","north"]]]}""")]
    public async Task Malformed_geojson_shapes_degrade_to_unavailable(string json)
    {
        using var directory = new TestDirectory();
        var handler = new RecordingHttpHandler((_, _, _) =>
            Task.FromResult(GeoJsonResponse(json)));
        var provider = new OsmLandDataProvider(
            new HttpClient(handler),
            new OsmLandDataOptions(new Uri("https://land.example.test/geometry"), directory.Path));

        var result = await provider.AcquireAsync(new GeographicBounds(-10, 10, -10, 10));

        Assert.Equal(LandDataStatus.Unavailable, result.Status);
        Assert.Null(result.Geometry);
    }

    [Fact]
    public async Task Http_timeout_degrades_without_masking_caller_cancellation()
    {
        using var directory = new TestDirectory();
        var handler = new RecordingHttpHandler(async (_, _, cancellationToken) =>
        {
            await Task.Delay(TimeSpan.FromSeconds(5), cancellationToken);
            return GeoJsonResponse(LandGeoJson);
        });
        var client = new HttpClient(handler)
        {
            Timeout = TimeSpan.FromMilliseconds(20)
        };
        var provider = new OsmLandDataProvider(
            client,
            new OsmLandDataOptions(new Uri("https://land.example.test/geometry"), directory.Path));

        var result = await provider.AcquireAsync(new GeographicBounds(-10, 10, -10, 10));

        Assert.Equal(LandDataStatus.Unavailable, result.Status);
        Assert.Contains("timed out", result.Warning, StringComparison.OrdinalIgnoreCase);

        using var cancellation = new CancellationTokenSource();
        cancellation.Cancel();
        await Assert.ThrowsAnyAsync<OperationCanceledException>(async () =>
            await provider.AcquireAsync(
                new GeographicBounds(-20, 20, -20, 20),
                cancellation.Token));
    }

    [Fact]
    public async Task Disk_cache_does_not_reset_the_original_freshness_window()
    {
        using var directory = new TestDirectory();
        var createdAt = new DateTimeOffset(2026, 7, 1, 0, 0, 0, TimeSpan.Zero);
        var firstHandler = new RecordingHttpHandler((_, _, _) =>
            Task.FromResult(GeoJsonResponse(LandGeoJson)));
        var first = new OsmLandDataProvider(
            new HttpClient(firstHandler),
            new OsmLandDataOptions(new Uri("https://land.example.test/geometry"), directory.Path),
            new FixedTimeProvider(createdAt));
        var bounds = new GeographicBounds(-10, 10, -10, 10);
        Assert.Equal(LandDataStatus.Available, (await first.AcquireAsync(bounds)).Status);

        var cachePath = Assert.Single(Directory.EnumerateFiles(directory.Path, "*.geojson"));
        File.SetLastWriteTimeUtc(cachePath, createdAt.UtcDateTime);
        var clock = new MutableTimeProvider(createdAt.AddDays(6).AddHours(23));
        var secondHandler = new RecordingHttpHandler((_, _, _) =>
            Task.FromResult(new HttpResponseMessage(HttpStatusCode.ServiceUnavailable)));
        var second = new OsmLandDataProvider(
            new HttpClient(secondHandler),
            new OsmLandDataOptions(new Uri("https://land.example.test/geometry"), directory.Path),
            clock);

        Assert.Equal(LandDataStatus.Available, (await second.AcquireAsync(bounds)).Status);
        clock.UtcNow = createdAt.AddDays(7).AddHours(1);
        Assert.Equal(LandDataStatus.Unavailable, (await second.AcquireAsync(bounds)).Status);
        Assert.Equal(1, secondHandler.RequestCount);
    }

    [Fact]
    public async Task Disk_cache_evicts_oldest_corridor_within_configured_bounds()
    {
        using var directory = new TestDirectory();
        var handler = new RecordingHttpHandler((_, _, _) =>
            Task.FromResult(GeoJsonResponse(LandGeoJson)));
        var provider = new OsmLandDataProvider(
            new HttpClient(handler),
            new OsmLandDataOptions(
                new Uri("https://land.example.test/geometry"),
                directory.Path,
                maximumResponseBytes: 512 * 1_024,
                maximumCacheBytes: 1_024 * 1_024,
                maximumCacheEntries: 2));

        await provider.AcquireAsync(new GeographicBounds(-10, 10, -10, 10));
        await provider.AcquireAsync(new GeographicBounds(-20, 20, -20, 20));
        await provider.AcquireAsync(new GeographicBounds(-30, 30, -30, 30));

        Assert.Equal(2, Directory.EnumerateFiles(directory.Path, "*.geojson").Count());
        Assert.Equal(3, handler.RequestCount);
    }

    [Fact]
    public void Geometry_index_respects_polygon_holes_and_narrow_crossings()
    {
        var payload = GeoJsonLandParser.Parse("""
            {
              "type": "Polygon",
              "coordinates": [
                [[-5,-5],[5,-5],[5,5],[-5,5],[-5,-5]],
                [[-1,-1],[-1,1],[1,1],[1,-1],[-1,-1]]
              ]
            }
            """);
        var index = new LandGeometryIndex(payload.Geometries, 0.25);

        Assert.False(index.Contains(new Coordinate(0, 0)));
        Assert.True(index.Contains(new Coordinate(3, 0)));
        Assert.True(index.IntersectsSegment(
            new Coordinate(0, -10),
            new Coordinate(0, 10)));
        Assert.False(index.IntersectsSegment(
            new Coordinate(0, -0.5),
            new Coordinate(0, 0.5)));
    }

    [Fact]
    public void Equivalent_antimeridian_longitudes_do_not_divide_by_zero()
    {
        var payload = GeoJsonLandParser.Parse("""
            {
              "type": "Polygon",
              "coordinates": [[[179,-1],[180,-1],[180,1],[179,1],[179,-1]]]
            }
            """);
        var index = new LandGeometryIndex(payload.Geometries, 0.25);

        Assert.True(index.IntersectsSegment(
            new Coordinate(0, 180),
            new Coordinate(0, -180)));
    }

    [Fact]
    public void Dateline_crossing_polygon_stays_narrow_and_matches_both_longitude_aliases()
    {
        var payload = GeoJsonLandParser.Parse("""
            {
              "type": "Polygon",
              "coordinates": [[[179,-1],[-179,-1],[-179,1],[179,1],[179,-1]]]
            }
            """);
        var index = new LandGeometryIndex(payload.Geometries, 0.25);

        Assert.True(index.Contains(new Coordinate(0, 180)));
        Assert.True(index.Contains(new Coordinate(0, -180)));
        Assert.False(index.Contains(new Coordinate(0, 0)));
        Assert.True(index.IntersectsSegment(
            new Coordinate(0, 178),
            new Coordinate(0, -178)));
    }

    private static HttpResponseMessage GeoJsonResponse(string json) =>
        new(HttpStatusCode.OK)
        {
            Content = new StringContent(json, Encoding.UTF8, "application/geo+json")
        };

    private sealed class MutableTimeProvider(DateTimeOffset utcNow) : TimeProvider
    {
        public DateTimeOffset UtcNow { get; set; } = utcNow;

        public override DateTimeOffset GetUtcNow() => UtcNow;
    }
}
