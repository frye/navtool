using System.Collections.Concurrent;
using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Logging.Abstractions;
using Navtool.Core;
using NetTopologySuite.Geometries;
using NetTopologySuite.Geometries.Prepared;
using NetTopologySuite.Index.Strtree;
using CoreCoordinate = Navtool.Core.Coordinate;
using NtsCoordinate = NetTopologySuite.Geometries.Coordinate;

namespace Navtool.Infrastructure;

public enum LandDataStatus
{
    Available,
    Unconfigured,
    Unavailable
}

public sealed record LandDataAcquisition(
    LandDataStatus Status,
    LandGeometryIndex? Geometry,
    string? Warning,
    string? Attribution)
{
    public static LandDataAcquisition Unconfigured() =>
        new(
            LandDataStatus.Unconfigured,
            null,
            "Land avoidance was not applied because NAVTOOL_LAND_DATA_ENDPOINT is not configured.",
            null);

    public static LandDataAcquisition Unavailable(string reason) =>
        new(
            LandDataStatus.Unavailable,
            null,
            $"Land avoidance was not applied because land data is unavailable: {reason}",
            null);
}

public interface ILandDataProvider
{
    ValueTask<LandDataAcquisition> AcquireAsync(
        GeographicBounds bounds,
        CancellationToken cancellationToken = default);
}

public sealed record OsmLandDataOptions
{
    public OsmLandDataOptions(
        Uri? endpoint,
        string cacheDirectory,
        TimeSpan? cacheDuration = null,
        long maximumResponseBytes = 32L * 1024 * 1024,
        double maximumSegmentSampleNauticalMiles = 1,
        int maximumMemoryEntries = 16,
        long maximumCacheBytes = 512L * 1024 * 1024,
        int maximumCacheEntries = 64)
    {
        if (endpoint is not null && !endpoint.IsAbsoluteUri)
        {
            throw new ArgumentException("The land data endpoint must be an absolute URI.", nameof(endpoint));
        }

        ArgumentException.ThrowIfNullOrWhiteSpace(cacheDirectory);
        if (cacheDuration <= TimeSpan.Zero)
        {
            throw new ArgumentOutOfRangeException(nameof(cacheDuration));
        }

        if (maximumResponseBytes <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(maximumResponseBytes));
        }

        if (!double.IsFinite(maximumSegmentSampleNauticalMiles) ||
            maximumSegmentSampleNauticalMiles <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(maximumSegmentSampleNauticalMiles));
        }

        if (maximumMemoryEntries <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(maximumMemoryEntries));
        }

        if (maximumCacheBytes < maximumResponseBytes)
        {
            throw new ArgumentOutOfRangeException(
                nameof(maximumCacheBytes),
                "The land cache must be large enough for one maximum-sized response.");
        }

        if (maximumCacheEntries <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(maximumCacheEntries));
        }

        Endpoint = endpoint;
        CacheDirectory = Path.GetFullPath(cacheDirectory);
        CacheDuration = cacheDuration ?? TimeSpan.FromDays(7);
        MaximumResponseBytes = maximumResponseBytes;
        MaximumSegmentSampleNauticalMiles = maximumSegmentSampleNauticalMiles;
        MaximumMemoryEntries = maximumMemoryEntries;
        MaximumCacheBytes = maximumCacheBytes;
        MaximumCacheEntries = maximumCacheEntries;
    }

    public Uri? Endpoint { get; }

    public string CacheDirectory { get; }

    public TimeSpan CacheDuration { get; }

    public long MaximumResponseBytes { get; }

    public double MaximumSegmentSampleNauticalMiles { get; }

    public int MaximumMemoryEntries { get; }

    public long MaximumCacheBytes { get; }

    public int MaximumCacheEntries { get; }
}

public sealed class OsmLandDataProvider : ILandDataProvider
{
    public const string OpenStreetMapAttribution =
        "© OpenStreetMap contributors (https://www.openstreetmap.org/copyright)";

    private readonly HttpClient _httpClient;
    private readonly OsmLandDataOptions _options;
    private readonly TimeProvider _timeProvider;
    private readonly ILogger<OsmLandDataProvider> _logger;
    private readonly SemaphoreSlim _cacheGate = new(1, 1);
    private readonly SemaphoreSlim _acquisitionGate = new(1, 1);
    private readonly ConcurrentDictionary<string, CachedPayload> _memoryCache = new();
    private readonly ConcurrentDictionary<string, CachedAcquisition> _acquisitionCache = new();

    public OsmLandDataProvider(
        HttpClient httpClient,
        OsmLandDataOptions options,
        TimeProvider? timeProvider = null,
        ILogger<OsmLandDataProvider>? logger = null)
    {
        ArgumentNullException.ThrowIfNull(httpClient);
        ArgumentNullException.ThrowIfNull(options);
        _httpClient = httpClient;
        _options = options;
        _timeProvider = timeProvider ?? TimeProvider.System;
        _logger = logger ?? NullLogger<OsmLandDataProvider>.Instance;
        Directory.CreateDirectory(_options.CacheDirectory);
    }

    public async ValueTask<LandDataAcquisition> AcquireAsync(
        GeographicBounds bounds,
        CancellationToken cancellationToken = default)
    {
        if (_options.Endpoint is null)
        {
            return LandDataAcquisition.Unconfigured();
        }

        var acquisitionKey = CreateCacheKey(_options.Endpoint, bounds) + "-index";
        var now = _timeProvider.GetUtcNow();
        RemoveExpiredEntries(now);
        if (_acquisitionCache.TryGetValue(acquisitionKey, out var cached) &&
            cached.ExpiresAt > now)
        {
            return cached.Acquisition;
        }

        await _acquisitionGate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            now = _timeProvider.GetUtcNow();
            if (_acquisitionCache.TryGetValue(acquisitionKey, out cached) &&
                cached.ExpiresAt > now)
            {
                return cached.Acquisition;
            }

            var geometries = new List<Geometry>();
            var attributions = new HashSet<string>(StringComparer.Ordinal);
            var expiresAt = DateTimeOffset.MaxValue;
            foreach (var requestBounds in SplitAtAntimeridian(bounds))
            {
                var cachedPayload = await GetPayloadAsync(requestBounds, cancellationToken)
                    .ConfigureAwait(false);
                var payload = cachedPayload.Payload;
                geometries.AddRange(payload.Geometries);
                expiresAt = expiresAt < cachedPayload.ExpiresAt
                    ? expiresAt
                    : cachedPayload.ExpiresAt;
                if (!string.IsNullOrWhiteSpace(payload.Attribution))
                {
                    attributions.Add(payload.Attribution);
                }
            }

            attributions.Add(OpenStreetMapAttribution);
            var attribution = string.Join(" · ", attributions);
            var acquisition = new LandDataAcquisition(
                LandDataStatus.Available,
                new LandGeometryIndex(
                    geometries,
                    _options.MaximumSegmentSampleNauticalMiles),
                null,
                attribution);
            _acquisitionCache[acquisitionKey] = new CachedAcquisition(
                acquisition,
                expiresAt);
            EnforceMemoryLimit(_acquisitionCache);
            return acquisition;
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch (OperationCanceledException exception)
        {
            _logger.LogWarning(exception, "OSM-derived land geometry request timed out");
            return LandDataAcquisition.Unavailable("the land data request timed out");
        }
        catch (Exception exception) when (
            exception is HttpRequestException or IOException or JsonException or
            InvalidDataException or NotSupportedException or ArgumentException)
        {
            _logger.LogWarning(exception, "Could not acquire OSM-derived land geometry");
            return LandDataAcquisition.Unavailable(exception.Message);
        }
        finally
        {
            _acquisitionGate.Release();
        }
    }

    private async Task<CachedPayload> GetPayloadAsync(
        GeographicBounds bounds,
        CancellationToken cancellationToken)
    {
        var key = CreateCacheKey(_options.Endpoint!, bounds);
        var now = _timeProvider.GetUtcNow();
        if (_memoryCache.TryGetValue(key, out var memory) && memory.ExpiresAt > now)
        {
            return memory;
        }

        await _cacheGate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            now = _timeProvider.GetUtcNow();
            if (_memoryCache.TryGetValue(key, out memory) && memory.ExpiresAt > now)
            {
                return memory;
            }

            var cachePath = Path.Combine(_options.CacheDirectory, key + ".geojson");
            PruneDiskCache(now, cachePath);
            var diskExpiresAt = File.Exists(cachePath)
                ? new DateTimeOffset(File.GetLastWriteTimeUtc(cachePath), TimeSpan.Zero) +
                  _options.CacheDuration
                : DateTimeOffset.MinValue;
            if (diskExpiresAt > now)
            {
                if (new FileInfo(cachePath).Length > _options.MaximumResponseBytes)
                {
                    File.Delete(cachePath);
                    throw new InvalidDataException(
                        $"Cached land response exceeds {_options.MaximumResponseBytes:N0} bytes.");
                }

                var cachedJson = await File.ReadAllTextAsync(cachePath, cancellationToken)
                    .ConfigureAwait(false);
                var cachedPayload = GeoJsonLandParser.Parse(cachedJson);
                var cached = new CachedPayload(
                    cachedPayload,
                    diskExpiresAt);
                _memoryCache[key] = cached;
                EnforceMemoryLimit(_memoryCache);
                return cached;
            }

            var requestUri = BuildRequestUri(_options.Endpoint!, bounds);
            using var response = await _httpClient.GetAsync(
                    requestUri,
                    HttpCompletionOption.ResponseHeadersRead,
                    cancellationToken)
                .ConfigureAwait(false);
            response.EnsureSuccessStatusCode();
            if (response.Content.Headers.ContentLength is > 0 &&
                response.Content.Headers.ContentLength > _options.MaximumResponseBytes)
            {
                throw new InvalidDataException(
                    $"Land response exceeds {_options.MaximumResponseBytes:N0} bytes.");
            }

            await using var input = await response.Content.ReadAsStreamAsync(cancellationToken)
                .ConfigureAwait(false);
            var json = await ReadBoundedAsync(
                    input,
                    _options.MaximumResponseBytes,
                    cancellationToken)
                .ConfigureAwait(false);
            var payload = GeoJsonLandParser.Parse(json);
            await StoreAtomicallyAsync(cachePath, json, cancellationToken).ConfigureAwait(false);
            PruneDiskCache(now, cachePath);
            var downloaded = new CachedPayload(payload, now + _options.CacheDuration);
            _memoryCache[key] = downloaded;
            EnforceMemoryLimit(_memoryCache);
            return downloaded;
        }
        finally
        {
            _cacheGate.Release();
        }
    }

    private static IEnumerable<GeographicBounds> SplitAtAntimeridian(
        GeographicBounds bounds)
    {
        if (!bounds.CrossesAntimeridian)
        {
            yield return bounds;
            yield break;
        }

        yield return new GeographicBounds(bounds.South, bounds.North, bounds.West, 180);
        yield return new GeographicBounds(bounds.South, bounds.North, -180, bounds.East);
    }

    private static Uri BuildRequestUri(Uri endpoint, GeographicBounds bounds)
    {
        var separator = string.IsNullOrEmpty(endpoint.Query) ? "?" : "&";
        var parameters = new[]
        {
            ("south", bounds.South),
            ("west", bounds.West),
            ("north", bounds.North),
            ("east", bounds.East)
        };
        var query = string.Join(
            "&",
            parameters.Select(item =>
                $"{item.Item1}={Uri.EscapeDataString(item.Item2.ToString("R", CultureInfo.InvariantCulture))}"));
        return new Uri(endpoint + separator + query, UriKind.Absolute);
    }

    private static string CreateCacheKey(Uri endpoint, GeographicBounds bounds)
    {
        var input = string.Create(
            CultureInfo.InvariantCulture,
            $"{endpoint.AbsoluteUri}|{bounds.South:R}|{bounds.West:R}|{bounds.North:R}|{bounds.East:R}");
        return "osm-land-" +
               Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(input)))
                   .ToLowerInvariant();
    }

    private static async Task<string> ReadBoundedAsync(
        Stream input,
        long maximumBytes,
        CancellationToken cancellationToken)
    {
        using var output = new MemoryStream();
        var buffer = new byte[64 * 1024];
        while (true)
        {
            var read = await input.ReadAsync(buffer, cancellationToken).ConfigureAwait(false);
            if (read == 0)
            {
                break;
            }

            if (output.Length + read > maximumBytes)
            {
                throw new InvalidDataException(
                    $"Land response exceeds {maximumBytes:N0} bytes.");
            }

            output.Write(buffer, 0, read);
        }

        return Encoding.UTF8.GetString(output.GetBuffer(), 0, checked((int)output.Length));
    }

    private static async Task StoreAtomicallyAsync(
        string path,
        string content,
        CancellationToken cancellationToken)
    {
        var temporary = path + "." + Guid.NewGuid().ToString("N") + ".partial";
        try
        {
            await File.WriteAllTextAsync(temporary, content, Encoding.UTF8, cancellationToken)
                .ConfigureAwait(false);
            File.Move(temporary, path, true);
        }
        finally
        {
            File.Delete(temporary);
        }
    }

    private void RemoveExpiredEntries(DateTimeOffset now)
    {
        foreach (var entry in _memoryCache.Where(entry => entry.Value.ExpiresAt <= now))
        {
            _memoryCache.TryRemove(entry.Key, out _);
        }

        foreach (var entry in _acquisitionCache.Where(entry => entry.Value.ExpiresAt <= now))
        {
            _acquisitionCache.TryRemove(entry.Key, out _);
        }
    }

    private void PruneDiskCache(DateTimeOffset now, string protectedPath)
    {
        var entries = Directory
            .EnumerateFiles(_options.CacheDirectory, "*.geojson", SearchOption.TopDirectoryOnly)
            .Select(path => new FileInfo(path))
            .ToList();
        foreach (var entry in entries.Where(entry =>
                     new DateTimeOffset(entry.LastWriteTimeUtc, TimeSpan.Zero) +
                         _options.CacheDuration <= now &&
                     !string.Equals(entry.FullName, protectedPath, StringComparison.Ordinal)))
        {
            entry.Delete();
        }

        entries = entries.Where(entry => entry.Exists).ToList();
        var bytes = entries.Sum(entry => entry.Length);
        var count = entries.Count;
        foreach (var entry in entries
                     .Where(entry =>
                         !string.Equals(entry.FullName, protectedPath, StringComparison.Ordinal))
                     .OrderBy(entry => entry.LastWriteTimeUtc)
                     .ThenBy(entry => entry.Name, StringComparer.Ordinal))
        {
            if (count <= _options.MaximumCacheEntries &&
                bytes <= _options.MaximumCacheBytes)
            {
                break;
            }

            entry.Delete();
            count--;
            bytes -= entry.Length;
        }

        if (count > _options.MaximumCacheEntries || bytes > _options.MaximumCacheBytes)
        {
            File.Delete(protectedPath);
            throw new IOException("The land response exceeds the configured cache bounds.");
        }
    }

    private void EnforceMemoryLimit<T>(ConcurrentDictionary<string, T> cache)
        where T : IExpiringCacheEntry
    {
        foreach (var entry in cache
                     .OrderBy(item => item.Value.ExpiresAt)
                     .Take(Math.Max(0, cache.Count - _options.MaximumMemoryEntries)))
        {
            cache.TryRemove(entry.Key, out _);
        }
    }

    private interface IExpiringCacheEntry
    {
        DateTimeOffset ExpiresAt { get; }
    }

    private sealed record CachedPayload(LandPayload Payload, DateTimeOffset ExpiresAt)
        : IExpiringCacheEntry;

    private sealed record CachedAcquisition(
        LandDataAcquisition Acquisition,
        DateTimeOffset ExpiresAt)
        : IExpiringCacheEntry;
}

public sealed class LandGeometryIndex
{
    private const double EarthRadiusNauticalMiles = 3_440.065;
    private readonly GeometryFactory _geometryFactory =
        NetTopologySuite.NtsGeometryServices.Instance.CreateGeometryFactory(srid: 4326);
    private readonly STRtree<IndexedGeometry> _index = new();
    private readonly double _maximumSampleNauticalMiles;

    public LandGeometryIndex(
        IEnumerable<Geometry> geometries,
        double maximumSampleNauticalMiles = 1)
    {
        ArgumentNullException.ThrowIfNull(geometries);
        if (!double.IsFinite(maximumSampleNauticalMiles) ||
            maximumSampleNauticalMiles <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(maximumSampleNauticalMiles));
        }

        _maximumSampleNauticalMiles = maximumSampleNauticalMiles;
        foreach (var geometry in geometries)
        {
            ArgumentNullException.ThrowIfNull(geometry);
            var immutableGeometry = geometry.Copy();
            if (!immutableGeometry.IsValid || immutableGeometry.IsEmpty)
            {
                throw new InvalidDataException("Land geometry must be non-empty and valid.");
            }

            Insert(immutableGeometry);
            Insert(ShiftLongitude(immutableGeometry, -360));
            Insert(ShiftLongitude(immutableGeometry, 360));
        }

        _index.Build();
    }

    public bool Contains(CoreCoordinate coordinate)
    {
        var point = _geometryFactory.CreatePoint(
            new NtsCoordinate(coordinate.Longitude, coordinate.Latitude));
        return _index.Query(point.EnvelopeInternal)
            .Any(item => item.Prepared.Covers(point));
    }

    private void Insert(Geometry geometry)
    {
        var indexed = new IndexedGeometry(
            geometry,
            PreparedGeometryFactory.Prepare(geometry));
        _index.Insert(geometry.EnvelopeInternal, indexed);
    }

    private static Geometry ShiftLongitude(Geometry geometry, double offset)
    {
        var shifted = geometry.Copy();
        shifted.Apply(new LongitudeShiftFilter(offset));
        shifted.GeometryChanged();
        return shifted;
    }

    public bool IntersectsSegment(CoreCoordinate start, CoreCoordinate end)
    {
        var points = DensifyGreatCircle(start, end, _maximumSampleNauticalMiles);
        if (points.Any(Contains))
        {
            return true;
        }

        for (var index = 1; index < points.Count; index++)
        {
            if (IntersectsShortSegment(points[index - 1], points[index]))
            {
                return true;
            }
        }

        return false;
    }

    private bool IntersectsShortSegment(CoreCoordinate start, CoreCoordinate end)
    {
        if (Math.Abs(Math.Abs(end.Longitude - start.Longitude) - 360) < 1e-9)
        {
            return IntersectsLine(
                       start,
                       new CoreCoordinate(end.Latitude, start.Longitude)) ||
                   IntersectsLine(
                       new CoreCoordinate(start.Latitude, end.Longitude),
                       end);
        }

        if (Math.Abs(end.Longitude - start.Longitude) <= 180)
        {
            return IntersectsLine(start, end);
        }

        var adjustedEnd = end.Longitude > start.Longitude
            ? end.Longitude - 360
            : end.Longitude + 360;
        var boundary = adjustedEnd > start.Longitude ? 180d : -180d;
        var fraction = (boundary - start.Longitude) / (adjustedEnd - start.Longitude);
        var latitude = start.Latitude + ((end.Latitude - start.Latitude) * fraction);
        var oppositeBoundary = boundary == 180 ? -180d : 180d;
        return IntersectsLine(start, new CoreCoordinate(latitude, boundary)) ||
               IntersectsLine(new CoreCoordinate(latitude, oppositeBoundary), end);
    }

    private bool IntersectsLine(CoreCoordinate start, CoreCoordinate end)
    {
        var line = _geometryFactory.CreateLineString(
        [
            new NtsCoordinate(start.Longitude, start.Latitude),
            new NtsCoordinate(end.Longitude, end.Latitude)
        ]);
        return _index.Query(line.EnvelopeInternal)
            .Any(item => item.Prepared.Intersects(line));
    }

    private static IReadOnlyList<CoreCoordinate> DensifyGreatCircle(
        CoreCoordinate start,
        CoreCoordinate end,
        double maximumSampleNauticalMiles)
    {
        var startVector = ToUnitVector(start);
        var endVector = ToUnitVector(end);
        var dot = Math.Clamp(
            (startVector.X * endVector.X) +
            (startVector.Y * endVector.Y) +
            (startVector.Z * endVector.Z),
            -1,
            1);
        var angle = Math.Acos(dot);
        var distance = angle * EarthRadiusNauticalMiles;
        var segments = Math.Max(1, checked((int)Math.Ceiling(distance / maximumSampleNauticalMiles)));
        if (angle < 1e-12)
        {
            return [start, end];
        }

        var sinAngle = Math.Sin(angle);
        var points = new CoreCoordinate[segments + 1];
        for (var index = 0; index <= segments; index++)
        {
            var fraction = (double)index / segments;
            var startWeight = Math.Sin((1 - fraction) * angle) / sinAngle;
            var endWeight = Math.Sin(fraction * angle) / sinAngle;
            var x = (startWeight * startVector.X) + (endWeight * endVector.X);
            var y = (startWeight * startVector.Y) + (endWeight * endVector.Y);
            var z = (startWeight * startVector.Z) + (endWeight * endVector.Z);
            var latitude = Math.Atan2(z, Math.Sqrt((x * x) + (y * y))) * 180 / Math.PI;
            var longitude = Math.Atan2(y, x) * 180 / Math.PI;
            points[index] = new CoreCoordinate(latitude, longitude);
        }

        return points;
    }

    private static (double X, double Y, double Z) ToUnitVector(CoreCoordinate coordinate)
    {
        var latitude = coordinate.Latitude * Math.PI / 180;
        var longitude = coordinate.Longitude * Math.PI / 180;
        var latitudeCosine = Math.Cos(latitude);
        return (
            latitudeCosine * Math.Cos(longitude),
            latitudeCosine * Math.Sin(longitude),
            Math.Sin(latitude));
    }

    private sealed record IndexedGeometry(Geometry Geometry, IPreparedGeometry Prepared);

    private sealed class LongitudeShiftFilter(double offset) : ICoordinateFilter
    {
        public void Filter(NtsCoordinate coordinate) => coordinate.X += offset;
    }
}

internal sealed record LandPayload(IReadOnlyList<Geometry> Geometries, string? Attribution);

internal static class GeoJsonLandParser
{
    private static readonly GeometryFactory GeometryFactory =
        NetTopologySuite.NtsGeometryServices.Instance.CreateGeometryFactory(srid: 4326);

    public static LandPayload Parse(string json)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(json);
        using var document = JsonDocument.Parse(json);
        var root = document.RootElement;
        var attribution = root.TryGetProperty("attribution", out var attributionElement) &&
                          attributionElement.ValueKind == JsonValueKind.String
            ? attributionElement.GetString()
            : null;
        var geometries = new List<Geometry>();
        ReadObject(root, geometries);
        return new LandPayload(geometries, attribution);
    }

    private static void ReadObject(JsonElement element, ICollection<Geometry> geometries)
    {
        if (element.ValueKind != JsonValueKind.Object)
        {
            throw new InvalidDataException("A GeoJSON object was expected.");
        }

        var type = RequiredString(element, "type");
        switch (type)
        {
            case "FeatureCollection":
                foreach (var feature in RequiredArray(element, "features").EnumerateArray())
                {
                    ReadObject(feature, geometries);
                }

                break;
            case "Feature":
                if (!element.TryGetProperty("geometry", out var geometry) ||
                    geometry.ValueKind == JsonValueKind.Null)
                {
                    throw new InvalidDataException("A land feature is missing geometry.");
                }

                ReadObject(geometry, geometries);
                break;
            case "Polygon":
                geometries.Add(ReadPolygon(RequiredArray(element, "coordinates")));
                break;
            case "MultiPolygon":
                foreach (var polygon in RequiredArray(element, "coordinates").EnumerateArray())
                {
                    geometries.Add(ReadPolygon(polygon));
                }

                break;
            default:
                throw new NotSupportedException(
                    $"Land GeoJSON geometry type '{type}' is not supported.");
        }
    }

    private static Polygon ReadPolygon(JsonElement coordinates)
    {
        if (coordinates.ValueKind != JsonValueKind.Array ||
            coordinates.GetArrayLength() == 0)
        {
            throw new InvalidDataException("A land polygon must contain an exterior ring.");
        }

        using var enumerator = coordinates.EnumerateArray();
        enumerator.MoveNext();
        var shell = ReadRing(enumerator.Current, null);
        var shellCenter = shell.EnvelopeInternal.Centre.X;
        var holes = new List<LinearRing>();
        while (enumerator.MoveNext())
        {
            holes.Add(ReadRing(enumerator.Current, shellCenter));
        }

        var polygon = GeometryFactory.CreatePolygon(shell, holes.ToArray());
        if (!polygon.IsValid || polygon.IsEmpty)
        {
            throw new InvalidDataException("A land polygon is empty or topologically invalid.");
        }

        return polygon;
    }

    private static LinearRing ReadRing(JsonElement ring, double? referenceLongitude)
    {
        if (ring.ValueKind != JsonValueKind.Array || ring.GetArrayLength() < 4)
        {
            throw new InvalidDataException("A land polygon ring requires at least four positions.");
        }

        var rawCoordinates = ring.EnumerateArray().Select(ReadPosition).ToList();
        if (!rawCoordinates[0].Equals2D(rawCoordinates[^1]))
        {
            throw new InvalidDataException("A GeoJSON polygon ring must be closed.");
        }

        rawCoordinates.RemoveAt(rawCoordinates.Count - 1);
        var coordinates = new List<NtsCoordinate>(rawCoordinates.Count + 1);
        var previousLongitude = rawCoordinates[0].X;
        coordinates.Add(rawCoordinates[0].Copy());
        foreach (var raw in rawCoordinates.Skip(1))
        {
            var longitude = raw.X;
            while (longitude - previousLongitude > 180)
            {
                longitude -= 360;
            }

            while (longitude - previousLongitude < -180)
            {
                longitude += 360;
            }

            coordinates.Add(new NtsCoordinate(longitude, raw.Y));
            previousLongitude = longitude;
        }

        if (referenceLongitude is { } reference)
        {
            var center = coordinates.Average(coordinate => coordinate.X);
            var offset = Math.Round((reference - center) / 360) * 360;
            foreach (var coordinate in coordinates)
            {
                coordinate.X += offset;
            }
        }

        coordinates.Add(coordinates[0].Copy());
        return GeometryFactory.CreateLinearRing(coordinates.ToArray());
    }

    private static NtsCoordinate ReadPosition(JsonElement position)
    {
        if (position.ValueKind != JsonValueKind.Array || position.GetArrayLength() < 2)
        {
            throw new InvalidDataException("A GeoJSON position requires longitude and latitude.");
        }

        if (position[0].ValueKind != JsonValueKind.Number ||
            position[1].ValueKind != JsonValueKind.Number ||
            !position[0].TryGetDouble(out var longitude) ||
            !position[1].TryGetDouble(out var latitude))
        {
            throw new InvalidDataException(
                "A GeoJSON position must contain finite numeric longitude and latitude.");
        }

        _ = new CoreCoordinate(latitude, longitude);
        return new NtsCoordinate(longitude, latitude);
    }

    private static string RequiredString(JsonElement element, string propertyName)
    {
        if (element.ValueKind != JsonValueKind.Object ||
            !element.TryGetProperty(propertyName, out var value) ||
            value.ValueKind != JsonValueKind.String)
        {
            throw new InvalidDataException($"GeoJSON property '{propertyName}' is required.");
        }

        return value.GetString()!;
    }

    private static JsonElement RequiredArray(JsonElement element, string propertyName)
    {
        if (element.ValueKind != JsonValueKind.Object ||
            !element.TryGetProperty(propertyName, out var value) ||
            value.ValueKind != JsonValueKind.Array)
        {
            throw new InvalidDataException($"GeoJSON property '{propertyName}' must be an array.");
        }

        return value;
    }
}
