using System.Collections.Immutable;
using System.Globalization;
using System.Net;
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
}

public sealed class ForecastDownloadException : IOException
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

    public NoaaGfsForecastProvider(
        HttpClient httpClient,
        AtomicFileCache cache,
        TimeProvider? timeProvider = null,
        NoaaGfsOptions? options = null)
    {
        ArgumentNullException.ThrowIfNull(httpClient);
        ArgumentNullException.ThrowIfNull(cache);
        _httpClient = httpClient;
        _cache = cache;
        _timeProvider = timeProvider ?? TimeProvider.System;
        _options = options ?? new NoaaGfsOptions();
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
        var regions = GetNomadsLongitudeWindows(request.Bounds);
        var cacheKey = CreateCacheKey(request, runTime, steps);

        var cached = await _cache.TryGetFreshAsync(cacheKey, now, cancellationToken)
            .ConfigureAwait(false);
        if (cached is not null)
        {
            cancellationToken.ThrowIfCancellationRequested();
            Report(progress, ForecastProgressStage.Completed, 1, "Using cached NOAA GFS forecast");
            return CreateAcquisition(
                request,
                runTime,
                cached,
                ForecastAcquisitionSource.Cache);
        }

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
                            var uri = BuildNomadsUri(runTime, forecastHour, request.Bounds, region);
                            Report(
                                progress,
                                ForecastProgressStage.Downloading,
                                completed / (double)requestCount,
                                $"Downloading GFS f{forecastHour:000}");
                            await DownloadGribAsync(uri, output, token).ConfigureAwait(false);
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

    private async ValueTask DownloadGribAsync(
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
            throw new ForecastDownloadException(
                $"NOAA NOMADS returned {(int)response.StatusCode} ({response.ReasonPhrase}) for '{uri}'.");
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
        ForecastRequest request,
        DateTimeOffset runTime,
        ImmutableArray<int> steps) =>
        AtomicFileCache.CreateKey(
            "noaa-gfs",
            runTime.ToUniversalTime().ToString("O", CultureInfo.InvariantCulture),
            Format(request.Bounds.South),
            Format(request.Bounds.North),
            Format(request.Bounds.West),
            Format(request.Bounds.East),
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
            options.MaximumResponseBytes <= 0)
        {
            throw new ArgumentException("NOAA GFS provider options are invalid.", nameof(options));
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
