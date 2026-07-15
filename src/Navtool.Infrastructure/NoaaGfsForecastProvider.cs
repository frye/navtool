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

    public TimeSpan CacheFreshness { get; init; } = TimeSpan.FromHours(6);

    public TimeSpan ForecastHorizon { get; init; } = TimeSpan.FromHours(384);

    public int MaximumRunLookbackCycles { get; init; } = 12;

    public long MaximumResponseBytes { get; init; } = 256L * 1024 * 1024;

    public int MaximumDownloadAttempts { get; init; } = 3;

    public TimeSpan BaseRetryDelay { get; init; } = TimeSpan.FromSeconds(1);

    public TimeSpan MaximumRetryDelay { get; init; } = TimeSpan.FromSeconds(30);

    public TimeSpan MinimumRequestInterval { get; init; } = TimeSpan.FromMilliseconds(250);
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

public sealed class NoaaGfsForecastProvider : IForecastProvider
{
    private static readonly ImmutableArray<int> AvailableForecastHours = BuildAvailableHours();
    private readonly HttpClient _httpClient;
    private readonly AtomicFileCache _cache;
    private readonly TimeProvider _timeProvider;
    private readonly NoaaGfsOptions _options;
    private readonly ILogger<NoaaGfsForecastProvider> _logger;

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
        ValidateOptions(_options);
    }

    public ForecastProvider Provider => ForecastProvider.Noaa;

    public ForecastModel Model => ForecastModel.NoaaGfs;

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

        cancellationToken.ThrowIfCancellationRequested();
        Report(progress, ForecastProgressStage.Queued, 0, "Selecting NOAA GFS run");
        var now = _timeProvider.GetUtcNow();
        var runTime = SelectRun(request, now);
        var steps = GetRequiredForecastHours(runTime, request.From, request.Through);
        var downloadBounds = AlignBoundsToGrid(request.Bounds);
        var regions = GetNomadsLongitudeWindows(downloadBounds);
        var cacheKey = CreateCacheKey(downloadBounds, runTime, steps);
        _logger.LogInformation(
            "Selected NOAA GFS run {RunTime} with {StepCount} steps, {RegionCount} regions, download bounds " +
            "south={South}, north={North}, west={West}, east={East}, and cache key {CacheKey}",
            runTime,
            steps.Length,
            regions.Length,
            downloadBounds.South,
            downloadBounds.North,
            downloadBounds.West,
            downloadBounds.East,
            cacheKey);

        var cached = await _cache.TryGetFreshAsync(cacheKey, now, cancellationToken)
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
                ForecastAcquisitionSource.Cache);
        }

        _logger.LogInformation("NOAA GFS cache miss for {CacheKey}", cacheKey);

        var requestCount = checked(steps.Length * regions.Length);
        var completed = 0;
        var stored = await _cache.StoreAsync(
                cacheKey,
                now,
                now + _options.CacheFreshness,
                async (output, token) =>
                {
                    foreach (var forecastHour in steps)
                    {
                        foreach (var region in regions)
                        {
                            token.ThrowIfCancellationRequested();
                            if (completed > 0 && _options.MinimumRequestInterval > TimeSpan.Zero)
                            {
                                await Task.Delay(_options.MinimumRequestInterval, token).ConfigureAwait(false);
                            }

                            var uri = BuildNomadsUri(runTime, forecastHour, downloadBounds, region);
                            Report(
                                progress,
                                ForecastProgressStage.Downloading,
                                completed / (double)requestCount,
                                $"Downloading GFS f{forecastHour:000}");
                            await DownloadGribWithRetryAsync(uri, output, token).ConfigureAwait(false);
                            completed++;
                            Report(
                                progress,
                                ForecastProgressStage.Downloading,
                                completed / (double)requestCount,
                                $"Downloaded {completed} of {requestCount} GFS subsets");
                        }
                    }

                    Report(progress, ForecastProgressStage.Decoding, 1, "Validated concatenated GRIB2 artifact");
                },
                cancellationToken)
            .ConfigureAwait(false);

        cancellationToken.ThrowIfCancellationRequested();
        Report(progress, ForecastProgressStage.Completed, 1, "NOAA GFS forecast ready");
        _logger.LogInformation(
            "Stored NOAA GFS artifact {CacheKey} with {LengthBytes} bytes",
            cacheKey,
            stored.LengthBytes);
        return CreateAcquisition(request, runTime, stored, ForecastAcquisitionSource.Remote);
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

    private async ValueTask DownloadGribWithRetryAsync(
        Uri uri,
        Stream destination,
        CancellationToken cancellationToken)
    {
        if (!destination.CanSeek)
        {
            throw new ArgumentException("The NOAA download destination must support rollback.", nameof(destination));
        }

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

    private static void RollBack(Stream destination, long checkpoint)
    {
        destination.SetLength(checkpoint);
        destination.Position = checkpoint;
    }

    private static ForecastAcquisition CreateAcquisition(
        ForecastRequest request,
        DateTimeOffset runTime,
        AtomicCacheEntry entry,
        ForecastAcquisitionSource source)
    {
        var file = new FileInfo(entry.Path);
        return new ForecastAcquisition(
            request,
            new ForecastRun(ForecastProvider.Noaa, ForecastModel.NoaaGfs, runTime),
            new LocalGribArtifact(entry.Path, file.Length, file.LastWriteTimeUtc),
            source,
            entry.Metadata);
    }

    private static string CreateCacheKey(
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

    private static void ValidateOptions(NoaaGfsOptions options)
    {
        if (options.FilterEndpoint is null ||
            !options.FilterEndpoint.IsAbsoluteUri ||
            options.PublicationDelay < TimeSpan.Zero ||
            options.CacheFreshness <= TimeSpan.Zero ||
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
