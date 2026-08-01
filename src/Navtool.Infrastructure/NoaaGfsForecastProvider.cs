using System.Collections.Immutable;
using System.Globalization;
using System.Net;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Logging.Abstractions;
using Navtool.Core;

namespace Navtool.Infrastructure;

public sealed record NoaaGfsOptions
{
    public Uri FilterEndpoint { get; init; } =
        new("https://nomads.ncep.noaa.gov/cgi-bin/filter_gfs_0p25.pl");

    public TimeSpan PublicationDelay { get; init; } = TimeSpan.FromHours(5);

    public double CacheTileSizeDegrees { get; init; } = 10;

    public TimeSpan ForecastHorizon { get; init; } = TimeSpan.FromHours(384);

    public int MaximumRunLookbackCycles { get; init; } = 12;

    public long MaximumResponseBytes { get; init; } = 256L * 1024 * 1024;

    public int MaximumDownloadAttempts { get; init; } = 3;

    public TimeSpan BaseRetryDelay { get; init; } = TimeSpan.FromSeconds(1);

    public TimeSpan MaximumRetryDelay { get; init; } = TimeSpan.FromSeconds(30);

    public TimeSpan MinimumRequestInterval { get; init; } = TimeSpan.FromMilliseconds(250);
}

public sealed record NoaaGfsDownloadEstimate(
    DateTimeOffset RunTime,
    GeographicBounds Bounds,
    int ForecastStepCount,
    int RegionCount)
{
    public int PartCount => checked(ForecastStepCount * RegionCount);
}

public class ForecastDownloadException : IOException
{
    public ForecastDownloadException(string message)
        : base(message)
    {
    }

    public ForecastDownloadException(string message, Exception innerException)
        : base(message, innerException)
    {
    }
}

/// <summary>
/// Describes a single GRIB part in the download manifest: one (forecast hour × longitude window) pair.
/// </summary>
internal sealed record GribPartDescriptor(
    int ForecastHour,
    int RegionIndex,
    NomadsLongitudeWindow LongitudeWindow,
    GeographicBounds AlignedBounds,
    string PartKey,
    Uri RequestUri);

public sealed class NoaaGfsForecastProvider : IForecastProvider
{
    private static readonly ImmutableArray<int> AvailableForecastHours = BuildAvailableHours();
    private readonly HttpClient _httpClient;
    private readonly AtomicFileCache _cache;
    private readonly TimeProvider _timeProvider;
    private readonly NoaaGfsOptions _options;
    private readonly ILogger<NoaaGfsForecastProvider> _logger;

    // Ref-counted keyed gates: a gate exists only while one or more acquisitions target
    // its cache key. The last acquisition to release the key removes and disposes the
    // entry, so this dictionary cannot grow unbounded over a long-lived singleton session.
    private readonly Dictionary<string, AcquisitionGate> _acquisitionGates =
        new(StringComparer.Ordinal);
    private readonly object _acquisitionGatesLock = new();
    private readonly Dictionary<string, int> _activePartPaths;
    private readonly object _activePartPathsLock = new();

    public NoaaGfsForecastProvider(
        HttpClient httpClient,
        AtomicFileCache cache,
        TimeProvider? timeProvider = null,
        NoaaGfsOptions? options = null,
        ILogger<NoaaGfsForecastProvider>? logger = null)
    {
        ArgumentNullException.ThrowIfNull(httpClient);
        ArgumentNullException.ThrowIfNull(cache);
        _httpClient = httpClient;
        _cache = cache;
        _timeProvider = timeProvider ?? TimeProvider.System;
        _options = options ?? new NoaaGfsOptions();
        _logger = logger ?? NullLogger<NoaaGfsForecastProvider>.Instance;
        _activePartPaths = new Dictionary<string, int>(
            OperatingSystem.IsWindows() ? StringComparer.OrdinalIgnoreCase : StringComparer.Ordinal);
        ValidateOptions(_options);
    }

    public ForecastProvider Provider => ForecastProvider.Noaa;

    public ForecastModel Model => ForecastModel.NoaaGfs;

    // Number of live acquisition gates. Exposed for tests to assert gates are released
    // (and not leaked) once acquisitions complete.
    internal int ActiveAcquisitionGateCount
    {
        get
        {
            lock (_acquisitionGatesLock)
            {
                return _acquisitionGates.Count;
            }
        }
    }

    public NoaaGfsDownloadEstimate Estimate(ForecastRequest request)
    {
        ArgumentNullException.ThrowIfNull(request);
        if (request.Model != Model)
        {
            throw new ArgumentException("The NOAA GFS provider only estimates NoaaGfs requests.", nameof(request));
        }

        var runTime = SelectRun(request, _timeProvider.GetUtcNow());
        var steps = GetRequiredForecastHours(runTime, request.From, request.Through);
        var bounds = AlignBoundsToGrid(request.Bounds);
        var tiles = GetCacheTiles(bounds, _options.CacheTileSizeDegrees);
        return new NoaaGfsDownloadEstimate(runTime, bounds, steps.Length, tiles.Length);
    }

    public async ValueTask<ForecastAcquisition> AcquireAsync(
        ForecastRequest request,
        IProgress<ForecastProgress>? progress,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(request);
        if (request.Model != Model)
        {
            throw new ArgumentException("The NOAA GFS provider only supplies NoaaGfs requests.", nameof(request));
        }

        // Serialize only acquisitions that target the same cached artifact (run, bounds,
        // steps); unrelated requests use distinct gates and run concurrently. The plan
        // (including the definitive cache key) is computed ONCE here and threaded into the
        // core so the gate and the download/store always agree on the same key, even if
        // the clock advances across a run-publish boundary while queued behind the gate.
        var plan = await SelectAcquisitionPlanAsync(request, cancellationToken).ConfigureAwait(false);
        var gate = RentGate(plan.CacheKey);

        try
        {
            await gate.Semaphore.WaitAsync(cancellationToken).ConfigureAwait(false);
        }
        catch
        {
            ReturnGate(plan.CacheKey, gate);
            throw;
        }

        try
        {
            return await AcquireCoreAsync(request, plan, progress, cancellationToken).ConfigureAwait(false);
        }
        finally
        {
            gate.Semaphore.Release();
            ReturnGate(plan.CacheKey, gate);
        }
    }

    // A single-permit gate plus the count of acquisitions currently referencing its key.
    private sealed class AcquisitionGate
    {
        public SemaphoreSlim Semaphore { get; } = new(1, 1);

        public int RefCount { get; set; }
    }

    private AcquisitionGate RentGate(string cacheKey)
    {
        lock (_acquisitionGatesLock)
        {
            if (!_acquisitionGates.TryGetValue(cacheKey, out var gate))
            {
                gate = new AcquisitionGate();
                _acquisitionGates[cacheKey] = gate;
            }

            gate.RefCount++;
            return gate;
        }
    }

    private void ReturnGate(string cacheKey, AcquisitionGate gate)
    {
        lock (_acquisitionGatesLock)
        {
            if (--gate.RefCount == 0)
            {
                _acquisitionGates.Remove(cacheKey);
                gate.Semaphore.Dispose();
            }
        }
    }

    // Resolves the definitive run selection, step set, grid-aligned bounds, and cache key
    // for a request against a single captured "now". Computing this once (rather than
    // recomputing inside the gated core) is what keeps the acquisition gate key and the
    // stored artifact key identical.
    private AcquisitionPlan CreateAcquisitionPlan(
        ForecastRequest request,
        DateTimeOffset now,
        DateTimeOffset runTime)
    {
        var steps = GetRequiredForecastHours(runTime, request.From, request.Through);
        var downloadBounds = AlignBoundsToGrid(request.Bounds);
        var tiles = GetCacheTiles(downloadBounds, _options.CacheTileSizeDegrees);
        var manifest = BuildTiledPartManifest(runTime, steps, tiles);
        var cacheKey = CreateAssemblyCacheKey(runTime, manifest);
        var legacyCacheKey = CreateLegacyCacheKey(downloadBounds, runTime, steps);
        return new AcquisitionPlan(
            now,
            runTime,
            SelectRun(request, now),
            steps,
            downloadBounds,
            manifest,
            cacheKey,
            legacyCacheKey);
    }

    private readonly record struct AcquisitionPlan(
        DateTimeOffset Now,
        DateTimeOffset RunTime,
        DateTimeOffset LatestPublishedRun,
        ImmutableArray<int> Steps,
        GeographicBounds DownloadBounds,
        ImmutableArray<GribPartDescriptor> Manifest,
        string CacheKey,
        string LegacyCacheKey);

    private async ValueTask<AcquisitionPlan> SelectAcquisitionPlanAsync(
        ForecastRequest request,
        CancellationToken cancellationToken)
    {
        var now = _timeProvider.GetUtcNow();
        var latestRun = SelectRun(request, now);
        var latestPlan = CreateAcquisitionPlan(request, now, latestRun);
        if (request.RefreshPolicy == ForecastRefreshPolicy.LatestAvailable)
        {
            return latestPlan;
        }

        for (var index = 0; index <= _options.MaximumRunLookbackCycles; index++)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var candidate = latestRun.AddHours(-6d * index);
            if (candidate > request.From ||
                request.Through > candidate + _options.ForecastHorizon)
            {
                continue;
            }

            var plan = index == 0
                ? latestPlan
                : CreateAcquisitionPlan(request, now, candidate);
            if (await IsPlanFullyCachedAsync(plan, cancellationToken).ConfigureAwait(false))
            {
                return plan;
            }
        }

        return latestPlan;
    }

    private async ValueTask<bool> IsPlanFullyCachedAsync(
        AcquisitionPlan plan,
        CancellationToken cancellationToken)
    {
        if (await _cache.TryGetAsync(plan.CacheKey, plan.Now, cancellationToken).ConfigureAwait(false) is not null ||
            await _cache.TryGetAsync(plan.LegacyCacheKey, plan.Now, cancellationToken).ConfigureAwait(false) is not null)
        {
            return true;
        }

        var partsDirectory = GetPartsDirectory();
        return plan.Manifest.All(part => File.Exists(Path.Combine(partsDirectory, part.PartKey + ".grib2")));
    }

    private async ValueTask<ForecastAcquisition> AcquireCoreAsync(
        ForecastRequest request,
        AcquisitionPlan plan,
        IProgress<ForecastProgress>? progress,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        Report(progress, ForecastProgressStage.Queued, 0, "Selecting NOAA GFS run");
        var now = plan.Now;
        var runTime = plan.RunTime;
        var steps = plan.Steps;
        var downloadBounds = plan.DownloadBounds;
        var cacheKey = plan.CacheKey;
        var manifest = plan.Manifest;
        _logger.LogInformation(
            "Selected NOAA GFS run {RunTime} with {StepCount} steps, {PartCount} tiled parts, download bounds " +
            "south={South}, north={North}, west={West}, east={East}, and cache key {CacheKey}",
            runTime,
            steps.Length,
            manifest.Length,
            downloadBounds.South,
            downloadBounds.North,
            downloadBounds.West,
            downloadBounds.East,
            cacheKey);

        var cached = await _cache.TryGetAsync(cacheKey, now, cancellationToken)
            .ConfigureAwait(false);
        cached ??= await _cache.TryGetAsync(plan.LegacyCacheKey, now, cancellationToken)
            .ConfigureAwait(false);
        if (cached is not null)
        {
            _logger.LogInformation("Using cached NOAA GFS artifact {CacheKey}", cacheKey);
            cancellationToken.ThrowIfCancellationRequested();
            Report(progress, ForecastProgressStage.Completed, 1, "Using cached NOAA GFS forecast");
            return CreateAcquisition(
                request,
                runTime,
                cached,
                ForecastAcquisitionSource.Cache,
                new ForecastCacheUsage(
                    manifest.Length,
                    0,
                    runTime,
                    plan.LatestPublishedRun));
        }

        _logger.LogInformation("NOAA GFS cache miss for {CacheKey}", cacheKey);

        var partsDirectory = GetPartsDirectory();
        Directory.CreateDirectory(partsDirectory);
        MigrateLegacyParts(partsDirectory);
        using var partProtection = ProtectParts(partsDirectory, manifest);
        PrunePartCache(partsDirectory, manifest);

        var totalParts = manifest.Length;
        var downloadedParts = 0;

        // Acquire each part; reuse from disk if already complete.
        for (var index = 0; index < totalParts; index++)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var part = manifest[index];
            var partFile = Path.Combine(partsDirectory, part.PartKey + ".grib2");

            var partGate = RentGate(part.PartKey);
            var partGateAcquired = false;
            try
            {
                await partGate.Semaphore.WaitAsync(cancellationToken).ConfigureAwait(false);
                partGateAcquired = true;
                if (File.Exists(partFile))
                {
                    File.SetLastWriteTimeUtc(partFile, now.UtcDateTime);
                    _logger.LogInformation(
                        "Reusing cached tile {PartIndex}/{Total} f{ForecastHour:000} tile {RegionIndex}",
                        index + 1, totalParts, part.ForecastHour, part.RegionIndex);
                    Report(
                        progress,
                        ForecastProgressStage.Downloading,
                        (index + 1) / (double)totalParts,
                        $"Resumed cached f{part.ForecastHour:000} tile {index + 1}/{totalParts}");
                    continue;
                }

                if (downloadedParts > 0 && _options.MinimumRequestInterval > TimeSpan.Zero)
                {
                    await Task.Delay(_options.MinimumRequestInterval, cancellationToken).ConfigureAwait(false);
                }

                Report(
                    progress,
                    ForecastProgressStage.Downloading,
                    index / (double)totalParts,
                    $"Downloading GFS f{part.ForecastHour:000} tile {index + 1}/{totalParts}");

                await DownloadPartAsync(part, partFile, cancellationToken).ConfigureAwait(false);
                downloadedParts++;
                PrunePartCache(partsDirectory, manifest);

                Report(
                    progress,
                    ForecastProgressStage.Downloading,
                    (index + 1) / (double)totalParts,
                    $"Downloaded {index + 1}/{totalParts} GFS tiles ({downloadedParts} new this run)");
            }
            finally
            {
                if (partGateAcquired)
                {
                    partGate.Semaphore.Release();
                }

                ReturnGate(part.PartKey, partGate);
            }
        }

        // Concatenate all parts in manifest order into the final cached artifact.
        Report(progress, ForecastProgressStage.Decoding, 1, "Assembling GRIB2 artifact from parts");
        // Stamp cache freshness from the store time, not the plan's captured "now". The
        // part-download loop above can run for minutes, so recording the artifact as created
        // at plan start would shorten its effective freshness window and skew eviction, which
        // ranks entries by ExpiresAt relative to the passed "now". Run selection, steps,
        // bounds, and the cache key still come from the plan so the keyed acquisition gate and
        // the stored artifact key stay aligned across run-publish boundaries.
        var cacheNow = _timeProvider.GetUtcNow();
        var stored = await _cache.StoreAsync(
                cacheKey,
                cacheNow,
                DateTimeOffset.MaxValue,
                async (output, token) =>
                {
                    foreach (var part in manifest)
                    {
                        token.ThrowIfCancellationRequested();
                        var partFile = Path.Combine(partsDirectory, part.PartKey + ".grib2");
                        await using var partStream = new FileStream(
                            partFile,
                            FileMode.Open,
                            FileAccess.Read,
                            FileShare.Read,
                            128 * 1024,
                            FileOptions.Asynchronous | FileOptions.SequentialScan);
                        await partStream.CopyToAsync(output, token).ConfigureAwait(false);
                    }
                },
                cancellationToken)
            .ConfigureAwait(false);

        cancellationToken.ThrowIfCancellationRequested();
        Report(progress, ForecastProgressStage.Completed, 1, "NOAA GFS forecast ready");
        _logger.LogInformation(
            "Stored NOAA GFS artifact {CacheKey} with {LengthBytes} bytes",
            cacheKey,
            stored.LengthBytes);
        partProtection.Dispose();
        PrunePartCache(partsDirectory, [], includeAssemblyCache: true);
        var source = downloadedParts == 0
            ? ForecastAcquisitionSource.Cache
            : ForecastAcquisitionSource.Remote;
        return CreateAcquisition(
            request,
            runTime,
            stored,
            source,
            new ForecastCacheUsage(
                totalParts - downloadedParts,
                downloadedParts,
                runTime,
                plan.LatestPublishedRun));
    }

    public DateTimeOffset SelectRun(ForecastRequest request, DateTimeOffset now)
    {
        ArgumentNullException.ThrowIfNull(request);
        var utcNow = now.ToUniversalTime();
        var publishCutoff = utcNow - _options.PublicationDelay;
        var latestCycle = new DateTimeOffset(
            publishCutoff.Year,
            publishCutoff.Month,
            publishCutoff.Day,
            (publishCutoff.Hour / 6) * 6,
            0,
            0,
            TimeSpan.Zero);

        for (var index = 0; index <= _options.MaximumRunLookbackCycles; index++)
        {
            var candidate = latestCycle.AddHours(-6d * index);
            if (candidate <= request.From &&
                request.Through <= candidate + _options.ForecastHorizon)
            {
                return candidate;
            }
        }

        throw new InvalidOperationException(
            "No recent published 00/06/12/18 UTC GFS run covers the requested departure and route horizon.");
    }

    public static ImmutableArray<int> GetRequiredForecastHours(
        DateTimeOffset runTime,
        DateTimeOffset from,
        DateTimeOffset through)
    {
        var run = runTime.ToUniversalTime();
        var startHours = (from.ToUniversalTime() - run).TotalHours;
        var endHours = (through.ToUniversalTime() - run).TotalHours;
        if (startHours < 0 || endHours < startHours || endHours > 384)
        {
            throw new ArgumentOutOfRangeException(
                nameof(through),
                "The requested interval must be within the GFS 384-hour horizon.");
        }

        var firstIndex = -1;
        var lastIndex = -1;
        for (var index = 0; index < AvailableForecastHours.Length; index++)
        {
            if (AvailableForecastHours[index] <= startHours)
            {
                firstIndex = index;
            }

            if (lastIndex < 0 && AvailableForecastHours[index] >= endHours)
            {
                lastIndex = index;
            }
        }

        if (firstIndex < 0 || lastIndex < firstIndex)
        {
            throw new ArgumentOutOfRangeException(nameof(through), "The GFS forecast cannot bracket the requested interval.");
        }

        return AvailableForecastHours[firstIndex..(lastIndex + 1)];
    }

    public Uri BuildNomadsUri(
        DateTimeOffset runTime,
        int forecastHour,
        GeographicBounds bounds,
        NomadsLongitudeWindow longitudeWindow)
    {
        if (!AvailableForecastHours.Contains(forecastHour))
        {
            throw new ArgumentOutOfRangeException(nameof(forecastHour));
        }

        var run = runTime.ToUniversalTime();
        var query = new[]
        {
            Pair("file", $"gfs.t{run:HH}z.pgrb2.0p25.f{forecastHour:000}"),
            Pair("lev_10_m_above_ground", "on"),
            Pair("var_UGRD", "on"),
            Pair("var_VGRD", "on"),
            Pair("subregion", string.Empty),
            Pair("leftlon", Format(longitudeWindow.Left)),
            Pair("rightlon", Format(longitudeWindow.Right)),
            Pair("toplat", Format(bounds.North)),
            Pair("bottomlat", Format(bounds.South)),
            Pair("dir", $"/gfs.{run:yyyyMMdd}/{run:HH}/atmos")
        };
        var builder = new UriBuilder(_options.FilterEndpoint)
        {
            Query = string.Join("&", query)
        };
        return builder.Uri;
    }

    public static ImmutableArray<NomadsLongitudeWindow> GetNomadsLongitudeWindows(
        GeographicBounds bounds)
    {
        var width = bounds.CrossesAntimeridian
            ? (bounds.East + 360d) - bounds.West
            : bounds.East - bounds.West;
        var left = Normalize360(bounds.West);
        var right = left + width;

        if (right <= 360d)
        {
            return ImmutableArray.Create(new NomadsLongitudeWindow(left, right));
        }

        return ImmutableArray.Create(
            new NomadsLongitudeWindow(left, 360d),
            new NomadsLongitudeWindow(0d, right - 360d));
    }

    public static GeographicBounds AlignBoundsToGrid(GeographicBounds bounds)
    {
        const double gridSize = 0.25;
        var south = Math.Max(-90, Math.Floor(bounds.South / gridSize) * gridSize);
        var north = Math.Min(90, Math.Ceiling(bounds.North / gridSize) * gridSize);
        var west = Math.Max(-180, Math.Floor(bounds.West / gridSize) * gridSize);
        var east = Math.Min(180, Math.Ceiling(bounds.East / gridSize) * gridSize);

        var originalWidth = bounds.CrossesAntimeridian
            ? bounds.East + 360 - bounds.West
            : bounds.East - bounds.West;
        var alignedWidth = bounds.CrossesAntimeridian
            ? east + 360 - west
            : east - west;
        return originalWidth >= 360 - gridSize || alignedWidth >= 360
            ? new GeographicBounds(south, north, -180, 180)
            : new GeographicBounds(south, north, west, east);
    }

    /// <summary>
    /// Builds the ordered download manifest: all (forecast hour, region) pairs in
    /// ascending forecast-hour / ascending region-index order.
    /// </summary>
    internal ImmutableArray<GribPartDescriptor> BuildPartManifest(
        DateTimeOffset runTime,
        ImmutableArray<int> steps,
        ImmutableArray<NomadsLongitudeWindow> regions,
        GeographicBounds downloadBounds)
    {
        var builder = ImmutableArray.CreateBuilder<GribPartDescriptor>(steps.Length * regions.Length);
        foreach (var forecastHour in steps)
        {
            for (var regionIndex = 0; regionIndex < regions.Length; regionIndex++)
            {
                var region = regions[regionIndex];
                var partKey = CreatePartKey(downloadBounds, runTime, forecastHour, regionIndex);
                var uri = BuildNomadsUri(runTime, forecastHour, downloadBounds, region);
                builder.Add(new GribPartDescriptor(forecastHour, regionIndex, region, downloadBounds, partKey, uri));
            }
        }

        return builder.MoveToImmutable();
    }

    internal ImmutableArray<GeographicBounds> GetCacheTiles(GeographicBounds bounds) =>
        GetCacheTiles(bounds, _options.CacheTileSizeDegrees);

    internal static ImmutableArray<GeographicBounds> GetCacheTiles(
        GeographicBounds bounds,
        double tileSizeDegrees)
    {
        if (!double.IsFinite(tileSizeDegrees) ||
            tileSizeDegrees < 0.25 ||
            tileSizeDegrees > 180 ||
            tileSizeDegrees % 0.25 != 0)
        {
            throw new ArgumentOutOfRangeException(
                nameof(tileSizeDegrees),
                "The cache tile size must be a 0.25-degree multiple between 0.25 and 180.");
        }

        var south = Math.Max(-90, Math.Floor(bounds.South / tileSizeDegrees) * tileSizeDegrees);
        var north = Math.Min(90, Math.Ceiling(bounds.North / tileSizeDegrees) * tileSizeDegrees);
        if (north <= south)
        {
            north = Math.Min(90, south + tileSizeDegrees);
            if (north <= south)
            {
                south = Math.Max(-90, north - tileSizeDegrees);
            }
        }

        var longitudeSegments = bounds.CrossesAntimeridian
            ? new[] { (bounds.West, 180d), (-180d, bounds.East) }
            : new[] { (bounds.West, bounds.East) };
        var builder = ImmutableArray.CreateBuilder<GeographicBounds>();
        for (var latitude = south; latitude < north; latitude += tileSizeDegrees)
        {
            var tileNorth = Math.Min(90, latitude + tileSizeDegrees);
            foreach (var (segmentWest, segmentEast) in longitudeSegments)
            {
                if (segmentEast <= segmentWest)
                {
                    continue;
                }

                var west = Math.Max(-180, Math.Floor(segmentWest / tileSizeDegrees) * tileSizeDegrees);
                var east = Math.Min(180, Math.Ceiling(segmentEast / tileSizeDegrees) * tileSizeDegrees);
                if (east <= west)
                {
                    east = Math.Min(180, west + tileSizeDegrees);
                }

                for (var longitude = west; longitude < east; longitude += tileSizeDegrees)
                {
                    builder.Add(new GeographicBounds(
                        latitude,
                        tileNorth,
                        longitude,
                        Math.Min(180, longitude + tileSizeDegrees)));
                }
            }
        }

        return builder
            .Distinct()
            .OrderBy(tile => tile.South)
            .ThenBy(tile => Normalize360(tile.West))
            .ToImmutableArray();
    }

    private ImmutableArray<GribPartDescriptor> BuildTiledPartManifest(
        DateTimeOffset runTime,
        ImmutableArray<int> steps,
        ImmutableArray<GeographicBounds> tiles)
    {
        var builder = ImmutableArray.CreateBuilder<GribPartDescriptor>(steps.Length * tiles.Length);
        foreach (var forecastHour in steps)
        {
            for (var tileIndex = 0; tileIndex < tiles.Length; tileIndex++)
            {
                var tile = tiles[tileIndex];
                var longitudeWindow = GetNomadsLongitudeWindows(tile).Single();
                builder.Add(new GribPartDescriptor(
                    forecastHour,
                    tileIndex,
                    longitudeWindow,
                    tile,
                    CreatePartKey(tile, runTime, forecastHour, 0),
                    BuildNomadsUri(runTime, forecastHour, tile, longitudeWindow)));
            }
        }

        return builder.MoveToImmutable();
    }

    private async ValueTask DownloadPartAsync(
        GribPartDescriptor part,
        string partFile,
        CancellationToken cancellationToken)
    {
        _logger.LogInformation(
            "Downloading GFS part f{ForecastHour:000} region {RegionIndex} → {PartFile}",
            part.ForecastHour, part.RegionIndex, partFile);

        var tempFile = $"{partFile}.{Guid.NewGuid():N}.partial";

        try
        {
            await using (var tempStream = new FileStream(
                tempFile,
                FileMode.CreateNew,
                FileAccess.ReadWrite,
                FileShare.None,
                128 * 1024,
                FileOptions.Asynchronous | FileOptions.WriteThrough))
            {
                await DownloadGribWithRetryAsync(part.RequestUri, tempStream, cancellationToken)
                    .ConfigureAwait(false);
            }

            try
            {
                File.Move(tempFile, partFile);
            }
            catch (IOException) when (File.Exists(partFile))
            {
                TryDeletePart(tempFile, "redundant NOAA temporary part");
            }
        }
        catch
        {
            TryDeletePart(tempFile, "failed NOAA temporary part");
            throw;
        }
    }

    internal async ValueTask DownloadGribWithRetryAsync(
        Uri uri,
        Stream destination,
        CancellationToken cancellationToken)
    {
        EnsureRollbackDestination(destination);

        var checkpoint = destination.Position;
        Exception? lastFailure = null;
        for (var attempt = 1; attempt <= _options.MaximumDownloadAttempts; attempt++)
        {
            cancellationToken.ThrowIfCancellationRequested();
            _logger.LogInformation(
                "Requesting NOAA NOMADS subset {Uri}; attempt {Attempt} of {MaximumAttempts}",
                uri,
                attempt,
                _options.MaximumDownloadAttempts);
            try
            {
                await DownloadGribAttemptAsync(uri, destination, cancellationToken).ConfigureAwait(false);
                _logger.LogInformation(
                    "Completed NOAA NOMADS subset {Uri} on attempt {Attempt}",
                    uri,
                    attempt);
                return;
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
            {
                throw;
            }
            catch (Exception exception) when (IsTransientFailure(exception))
            {
                lastFailure = exception;
                RollBack(destination, checkpoint);
                if (attempt == _options.MaximumDownloadAttempts)
                {
                    break;
                }

                var delay = GetRetryDelay(exception, attempt);
                _logger.LogWarning(
                    exception,
                    "Transient NOAA NOMADS failure for {Uri}; retrying after {Delay} on attempt {NextAttempt}",
                    uri,
                    delay,
                    attempt + 1);
                if (delay > TimeSpan.Zero)
                {
                    await Task.Delay(delay, cancellationToken).ConfigureAwait(false);
                }
            }
            catch (Exception exception) when (
                exception is not OperationCanceledException ||
                !cancellationToken.IsCancellationRequested)
            {
                _logger.LogError(
                    exception,
                    "NOAA NOMADS returned a non-retryable response for {Uri}",
                    uri);
                throw;
            }
        }

        var exhausted = new ForecastDownloadException(
            $"NOAA NOMADS request failed after {_options.MaximumDownloadAttempts} attempts for '{uri}': " +
            $"{lastFailure!.Message}",
            lastFailure);
        _logger.LogError(exhausted, "NOAA NOMADS retries exhausted for {Uri}", uri);
        throw exhausted;
    }

    private async ValueTask DownloadGribAttemptAsync(
        Uri uri,
        Stream destination,
        CancellationToken cancellationToken)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, uri);
        using var response = await _httpClient.SendAsync(
                request,
                HttpCompletionOption.ResponseHeadersRead,
                cancellationToken)
            .ConfigureAwait(false);
        if (!response.IsSuccessStatusCode)
        {
            // Redirect behavior depends on the configured HttpClient handler chain.
            // Any 3xx response that reaches this provider is treated as transient.
            var location = response.Headers.Location is null
                ? string.Empty
                : $" Redirect location: '{response.Headers.Location}'.";
            var message =
                $"NOAA NOMADS returned {(int)response.StatusCode} ({response.ReasonPhrase}) for '{uri}'.{location}";
            if (IsTransientStatus(response.StatusCode))
            {
                throw new TransientForecastDownloadException(
                    message,
                    GetRetryAfter(response));
            }

            throw new ForecastDownloadException(message);
        }

        var contentLength = response.Content.Headers.ContentLength;
        if (contentLength is <= 0)
        {
            throw new ForecastDownloadException($"NOAA NOMADS returned an empty response for '{uri}'.");
        }

        if (contentLength > _options.MaximumResponseBytes)
        {
            throw new ForecastDownloadException($"NOAA NOMADS response for '{uri}' exceeds the configured size limit.");
        }

        var mediaType = response.Content.Headers.ContentType?.MediaType;
        if (mediaType is not null &&
            (mediaType.StartsWith("text/", StringComparison.OrdinalIgnoreCase) ||
             mediaType.Contains("html", StringComparison.OrdinalIgnoreCase) ||
             mediaType.Contains("json", StringComparison.OrdinalIgnoreCase) ||
             mediaType.Contains("xml", StringComparison.OrdinalIgnoreCase)))
        {
            throw new ForecastDownloadException(
                $"NOAA NOMADS returned unexpected content type '{mediaType}' for '{uri}'.");
        }

        await using var source = await response.Content.ReadAsStreamAsync(cancellationToken)
            .ConfigureAwait(false);
        var buffer = new byte[128 * 1024];
        var first = new byte[4];
        var tail = new Queue<byte>(4);
        long total = 0;
        while (true)
        {
            var read = await source.ReadAsync(buffer, cancellationToken).ConfigureAwait(false);
            if (read == 0)
            {
                break;
            }

            if (total + read > _options.MaximumResponseBytes)
            {
                throw new ForecastDownloadException($"NOAA NOMADS response for '{uri}' exceeds the configured size limit.");
            }

            for (var index = 0; index < read; index++)
            {
                if (total + index < 4)
                {
                    first[total + index] = buffer[index];
                }

                if (tail.Count == 4)
                {
                    tail.Dequeue();
                }

                tail.Enqueue(buffer[index]);
            }

            await destination.WriteAsync(buffer.AsMemory(0, read), cancellationToken).ConfigureAwait(false);
            total += read;
        }

        if (total < 8 ||
            !first.AsSpan().SequenceEqual("GRIB"u8) ||
            tail.Count != 4 ||
            !tail.ToArray().AsSpan().SequenceEqual("7777"u8))
        {
            throw new ForecastDownloadException(
                $"NOAA NOMADS response for '{uri}' is not a complete GRIB artifact.");
        }
    }

    private TimeSpan GetRetryDelay(Exception exception, int completedAttempts)
    {
        if (exception is TransientForecastDownloadException { RetryAfter: { } retryAfter })
        {
            return retryAfter > _options.MaximumRetryDelay
                ? _options.MaximumRetryDelay
                : retryAfter;
        }

        var multiplier = Math.Pow(2, completedAttempts - 1);
        var baseMilliseconds = _options.BaseRetryDelay.TotalMilliseconds * multiplier;
        var jitteredMilliseconds = baseMilliseconds * (1 + (Random.Shared.NextDouble() * 0.25));
        return TimeSpan.FromMilliseconds(
            Math.Min(jitteredMilliseconds, _options.MaximumRetryDelay.TotalMilliseconds));
    }

    private static TimeSpan? GetRetryAfter(HttpResponseMessage response)
    {
        var retryAfter = response.Headers.RetryAfter;
        if (retryAfter?.Delta is { } delta && delta >= TimeSpan.Zero)
        {
            return delta;
        }

        if (retryAfter?.Date is { } date)
        {
            var delay = date - DateTimeOffset.UtcNow;
            return delay > TimeSpan.Zero ? delay : TimeSpan.Zero;
        }

        return null;
    }

    private static bool IsTransientFailure(Exception exception) =>
        exception is HttpRequestException or
            HttpIOException or
            OperationCanceledException or
            TransientForecastDownloadException;

    private static bool IsTransientStatus(HttpStatusCode statusCode) =>
        statusCode is HttpStatusCode.RequestTimeout or
            HttpStatusCode.TooManyRequests ||
        (int)statusCode is 425 or >= 300 and <= 399 or >= 500 and <= 599;

    private static void EnsureRollbackDestination(Stream destination)
    {
        ArgumentNullException.ThrowIfNull(destination);

        const string message = "The NOAA download destination must support rollback (seek, write, and set-length).";
        long checkpoint;
        try
        {
            checkpoint = destination.Position;
        }
        catch (Exception exception) when (
            exception is NotSupportedException or IOException or ObjectDisposedException)
        {
            throw new ArgumentException(message, nameof(destination), exception);
        }

        if (!destination.CanSeek || !destination.CanWrite)
        {
            throw new ArgumentException(message, nameof(destination));
        }

        try
        {
            var length = destination.Length;
            destination.Position = checkpoint;
            destination.SetLength(length);
            destination.Position = checkpoint;
        }
        catch (Exception exception) when (
            exception is NotSupportedException or IOException or ObjectDisposedException)
        {
            throw new ArgumentException(message, nameof(destination), exception);
        }
    }

    private static void RollBack(Stream destination, long checkpoint)
    {
        destination.SetLength(checkpoint);
        destination.Position = checkpoint;
    }

    private static ForecastAcquisition CreateAcquisition(
        ForecastRequest request,
        DateTimeOffset runTime,
        AtomicCacheEntry entry,
        ForecastAcquisitionSource source,
        ForecastCacheUsage? cacheUsage = null)
    {
        var file = new FileInfo(entry.Path);
        return new ForecastAcquisition(
            request,
            new ForecastRun(ForecastProvider.Noaa, ForecastModel.NoaaGfs, runTime),
            new LocalGribArtifact(entry.Path, file.Length, file.LastWriteTimeUtc),
            source,
            entry.Metadata,
            cacheUsage);
    }

    private static string CreateLegacyCacheKey(
        GeographicBounds bounds,
        DateTimeOffset runTime,
        ImmutableArray<int> steps) =>
        AtomicFileCache.CreateKey(
            "noaa-gfs",
            runTime.ToUniversalTime().ToString("O", CultureInfo.InvariantCulture),
            Format(bounds.South),
            Format(bounds.North),
            Format(bounds.West),
            Format(bounds.East),
            string.Join(",", steps));

    private static string CreateAssemblyCacheKey(
        DateTimeOffset runTime,
        ImmutableArray<GribPartDescriptor> manifest) =>
        AtomicFileCache.CreateKey(
            "noaa-gfs-assembly-v2",
            runTime.ToUniversalTime().ToString("O", CultureInfo.InvariantCulture),
            string.Join(",", manifest.Select(part => part.PartKey)));

    private static string CreatePartKey(
        GeographicBounds bounds,
        DateTimeOffset runTime,
        int forecastHour,
        int regionIndex) =>
        AtomicFileCache.CreateKey(
            "noaa-gfs-part",
            runTime.ToUniversalTime().ToString("O", CultureInfo.InvariantCulture),
            Format(bounds.South),
            Format(bounds.North),
            Format(bounds.West),
            Format(bounds.East),
            forecastHour.ToString(CultureInfo.InvariantCulture),
            regionIndex.ToString(CultureInfo.InvariantCulture));

    private static ImmutableArray<int> BuildAvailableHours()
    {
        var builder = ImmutableArray.CreateBuilder<int>();
        for (var hour = 0; hour <= 120; hour++)
        {
            builder.Add(hour);
        }

        for (var hour = 123; hour <= 384; hour += 3)
        {
            builder.Add(hour);
        }

        return builder.ToImmutable();
    }

    private static string Pair(string name, string value) =>
        $"{Uri.EscapeDataString(name)}={Uri.EscapeDataString(value)}";

    private static string Format(double value) =>
        value.ToString("R", CultureInfo.InvariantCulture);

    private static double Normalize360(double longitude)
    {
        var normalized = longitude % 360d;
        return normalized < 0 ? normalized + 360d : normalized;
    }

    private void Report(
        IProgress<ForecastProgress>? progress,
        ForecastProgressStage stage,
        double fraction,
        string message) =>
        progress?.Report(new ForecastProgress(Provider, Model, stage, fraction, message));

    private string GetPartsDirectory() =>
        Path.Combine(_cache.RootDirectory, "noaa-gfs-parts");

    private void MigrateLegacyParts(string partsDirectory)
    {
        foreach (var legacyDirectory in Directory.EnumerateDirectories(
                     partsDirectory,
                     "*",
                     SearchOption.TopDirectoryOnly))
        {
            foreach (var source in Directory.EnumerateFiles(
                         legacyDirectory,
                         "*.grib2",
                         SearchOption.TopDirectoryOnly))
            {
                var destination = Path.Combine(partsDirectory, Path.GetFileName(source));
                if (File.Exists(destination))
                {
                    TryDeletePart(source, "duplicate legacy NOAA part");
                    continue;
                }

                try
                {
                    File.Move(source, destination);
                }
                catch (IOException exception)
                {
                    _logger.LogWarning(
                        exception,
                        "Could not migrate legacy NOAA part {Source} to {Destination}",
                        source,
                        destination);
                }
            }

            TryDeleteDirectoryIfEmpty(legacyDirectory);
        }
    }

    private IDisposable ProtectParts(
        string partsDirectory,
        ImmutableArray<GribPartDescriptor> manifest)
    {
        var paths = manifest
            .Select(part => Path.Combine(partsDirectory, part.PartKey + ".grib2"))
            .Distinct(OperatingSystem.IsWindows()
                ? StringComparer.OrdinalIgnoreCase
                : StringComparer.Ordinal)
            .ToArray();
        lock (_activePartPathsLock)
        {
            foreach (var path in paths)
            {
                _activePartPaths[path] = _activePartPaths.GetValueOrDefault(path) + 1;
            }
        }

        return new PartProtection(this, paths);
    }

    private void ReleasePartProtection(IEnumerable<string> paths)
    {
        lock (_activePartPathsLock)
        {
            foreach (var path in paths)
            {
                var count = _activePartPaths[path] - 1;
                if (count == 0)
                {
                    _activePartPaths.Remove(path);
                }
                else
                {
                    _activePartPaths[path] = count;
                }
            }
        }
    }

    private void PrunePartCache(
        string partsDirectory,
        ImmutableArray<GribPartDescriptor> protectedManifest,
        bool includeAssemblyCache = false)
    {
        SweepOrphanedPartials(partsDirectory);

        var comparer = OperatingSystem.IsWindows()
            ? StringComparer.OrdinalIgnoreCase
            : StringComparer.Ordinal;
        var protectedPaths = protectedManifest
            .Select(part => Path.Combine(partsDirectory, part.PartKey + ".grib2"))
            .ToHashSet(comparer);
        lock (_activePartPathsLock)
        {
            protectedPaths.UnionWith(_activePartPaths.Keys);
        }

        var files = Directory
            .EnumerateFiles(partsDirectory, "*.grib2", SearchOption.TopDirectoryOnly)
            .Select(path => new FileInfo(path))
            .ToList();
        var assemblyFiles = includeAssemblyCache
            ? Directory.EnumerateFiles(_cache.RootDirectory, "*.grib2", SearchOption.TopDirectoryOnly)
                .Select(path => new FileInfo(path))
                .ToArray()
            : [];
        var availableBytes = Math.Max(0, _cache.MaximumBytes - assemblyFiles.Sum(file => file.Length));
        var availableEntries = Math.Max(0, _cache.MaximumEntries - assemblyFiles.Length);
        var maximumEntries = Math.Max(availableEntries, protectedPaths.Count);
        var bytes = files.Sum(file => file.Length);
        var count = files.Count;

        foreach (var file in files
                     .Where(file => !protectedPaths.Contains(file.FullName))
                     .OrderBy(file => file.LastWriteTimeUtc)
                     .ThenBy(file => file.Name, StringComparer.Ordinal))
        {
            if (count <= maximumEntries && bytes <= availableBytes)
            {
                break;
            }

            var length = file.Length;
            if (TryDeletePart(file.FullName, "stale NOAA part"))
            {
                count--;
                bytes -= length;
            }
        }

        if (count > maximumEntries || bytes > availableBytes)
        {
            _logger.LogWarning(
                "Active NOAA tiles temporarily exceed the shared cache bounds: {Count} entries, {Bytes} bytes",
                count,
                bytes);
        }
    }

    // Completed downloads are atomically promoted to ".grib2", so partials encountered
    // before an acquisition starts are remnants of an interrupted process.
    private void SweepOrphanedPartials(string partsDirectory)
    {
        foreach (var path in Directory.EnumerateFiles(
            partsDirectory,
            "*.partial",
            SearchOption.TopDirectoryOnly))
        {
            TryDeletePart(path, "orphaned NOAA temporary part");
        }
    }

    private void TryDeleteDirectoryIfEmpty(string directory)
    {
        try
        {
            if (Directory.Exists(directory) && !Directory.EnumerateFileSystemEntries(directory).Any())
            {
                Directory.Delete(directory);
            }
        }
        catch (IOException exception)
        {
            _logger.LogWarning(exception, "Could not remove empty NOAA parts directory {Path}", directory);
        }
        catch (UnauthorizedAccessException exception)
        {
            _logger.LogWarning(exception, "Could not remove empty NOAA parts directory {Path}", directory);
        }
    }

    private bool TryDeletePart(string path, string purpose)
    {
        try
        {
            File.Delete(path);
            return true;
        }
        catch (DirectoryNotFoundException)
        {
            return true;
        }
        catch (IOException exception)
        {
            _logger.LogWarning(exception, "Could not delete {Purpose} {Path}", purpose, path);
            return false;
        }
        catch (UnauthorizedAccessException exception)
        {
            _logger.LogWarning(exception, "Could not delete {Purpose} {Path}", purpose, path);
            return false;
        }
    }

    private static void ValidateOptions(NoaaGfsOptions options)
    {
        if (        options.FilterEndpoint is null ||
        !options.FilterEndpoint.IsAbsoluteUri ||
        options.PublicationDelay < TimeSpan.Zero ||
        !double.IsFinite(options.CacheTileSizeDegrees) ||
        options.CacheTileSizeDegrees < 0.25 ||
        options.CacheTileSizeDegrees > 180 ||
        options.CacheTileSizeDegrees % 0.25 != 0 ||
        options.ForecastHorizon <= TimeSpan.Zero ||
            options.ForecastHorizon > TimeSpan.FromHours(384) ||
            options.MaximumRunLookbackCycles < 0 ||
            options.MaximumResponseBytes <= 0 ||
            options.MaximumDownloadAttempts <= 0 ||
            options.BaseRetryDelay < TimeSpan.Zero ||
            options.MaximumRetryDelay < options.BaseRetryDelay ||
            options.MinimumRequestInterval < TimeSpan.Zero)
        {
            throw new ArgumentException("NOAA GFS provider options are invalid.", nameof(options));
        }
    }

    private sealed class TransientForecastDownloadException(
        string message,
        TimeSpan? retryAfter)
        : ForecastDownloadException(message)
    {
        public TimeSpan? RetryAfter { get; } = retryAfter;
    }

    private sealed class PartProtection(
        NoaaGfsForecastProvider owner,
        string[] paths) : IDisposable
    {
        private int _disposed;

        public void Dispose()
        {
            if (Interlocked.Exchange(ref _disposed, 1) == 0)
            {
                owner.ReleasePartProtection(paths);
            }
        }
    }
}

public readonly record struct NomadsLongitudeWindow
{
    public NomadsLongitudeWindow(double left, double right)
    {
        if (!double.IsFinite(left) || !double.IsFinite(right) ||
            left is < 0 or > 360 || right is < 0 or > 360 || right < left)
        {
            throw new ArgumentOutOfRangeException(nameof(left));
        }

        Left = left;
        Right = right;
    }

    public double Left { get; }

    public double Right { get; }
}
