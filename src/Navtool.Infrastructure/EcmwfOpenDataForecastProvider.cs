using System.Collections.Immutable;
using System.Buffers.Binary;
using System.Globalization;
using System.Net;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Logging.Abstractions;
using Navtool.Core;

namespace Navtool.Infrastructure;

public sealed record EcmwfOpenDataOptions
{
    public Uri BaseUri { get; init; } = new("https://data.ecmwf.int/forecasts/");

    public int MaximumRunLookbackCycles { get; init; } = 12;

    public long MaximumIndexBytes { get; init; } = 8L * 1024 * 1024;

    public long MaximumRangeBytes { get; init; } = 64L * 1024 * 1024;

    public long MaximumPartCacheBytes { get; init; } = 2L * 1024 * 1024 * 1024;

    public int MaximumDownloadAttempts { get; init; } = 3;

    public TimeSpan BaseRetryDelay { get; init; } = TimeSpan.FromSeconds(1);

    public TimeSpan MaximumRetryDelay { get; init; } = TimeSpan.FromSeconds(30);

    public TimeSpan MinimumRequestInterval { get; init; } = TimeSpan.FromMilliseconds(250);
}

public sealed record ForecastProviderEstimate(
    int EstimatedRangeRequests,
    long? EstimatedBytes,
    bool IsSupported,
    string Warning);

internal sealed record EcmwfIndexPart(
    int ForecastHour,
    string Parameter,
    long Offset,
    long Length,
    Uri DataUri,
    string PartKey);

internal sealed record EcmwfAcquisitionPlan(
    DateTimeOffset RunTime,
    ImmutableArray<int> ForecastHours,
    ImmutableArray<EcmwfIndexPart> Parts,
    string CacheKey);

public sealed class EcmwfOpenDataForecastProvider : IForecastProvider, IForecastDownloadEstimator
{
    private static readonly UTF8Encoding StrictUtf8 = new(false, true);
    private static readonly ImmutableArray<int> LongCycleHours =
        [.. Enumerable.Range(0, 49).Select(index => index * 3)
            .Concat(Enumerable.Range(25, 16).Select(index => index * 6))];
    private static readonly ImmutableArray<int> ShortCycleHours =
        [.. Enumerable.Range(0, 31).Select(index => index * 3)];

    private readonly HttpClient _httpClient;
    private readonly AtomicFileCache _cache;
    private readonly TimeProvider _timeProvider;
    private readonly EcmwfOpenDataOptions _options;
    private readonly ILogger<EcmwfOpenDataForecastProvider> _logger;
    private readonly KeyedAsyncGate _acquisitionGate = new();

    public EcmwfOpenDataForecastProvider(
        HttpClient httpClient,
        AtomicFileCache cache,
        TimeProvider? timeProvider = null,
        EcmwfOpenDataOptions? options = null,
        ILogger<EcmwfOpenDataForecastProvider>? logger = null)
    {
        ArgumentNullException.ThrowIfNull(httpClient);
        ArgumentNullException.ThrowIfNull(cache);
        _httpClient = httpClient;
        _cache = cache;
        _timeProvider = timeProvider ?? TimeProvider.System;
        _options = options ?? new EcmwfOpenDataOptions();
        _logger = logger ?? NullLogger<EcmwfOpenDataForecastProvider>.Instance;
        ValidateOptions(_options);
    }

    public ForecastProvider Provider => ForecastProvider.Ecmwf;

    public ForecastModel Model => ForecastModel.EcmwfIfs;

    public ForecastProviderEstimate Estimate(ForecastRequest request)
    {
        ValidateRequest(request);
        var run = SelectNewestCoveringRun(request, _timeProvider.GetUtcNow());
        var hours = GetRequiredForecastHours(run, request.From, request.Through);
        return new ForecastProviderEstimate(
            checked(hours.Length * 2),
            null,
            true,
            "ECMWF downloads global indexed 10 m wind fields; route bounds are applied while loading the forecast.");
    }

    public ForecastDownloadEstimate EstimateDownload(ForecastRequest request)
    {
        var estimate = Estimate(request);
        return new ForecastDownloadEstimate(
            Model,
            estimate.EstimatedRangeRequests / 2,
            estimate.EstimatedRangeRequests,
            estimate.EstimatedBytes,
            estimate.Warning);
    }

    public async ValueTask<ForecastAcquisition> AcquireAsync(
        ForecastRequest request,
        IProgress<ForecastProgress>? progress,
        CancellationToken cancellationToken)
    {
        ValidateRequest(request);
        cancellationToken.ThrowIfCancellationRequested();
        if (request.RefreshPolicy == ForecastRefreshPolicy.PreferCache)
        {
            var now = _timeProvider.GetUtcNow();
            var candidates = GetCandidateRuns(now)
                .Where(candidate => CanCover(candidate, request.From, request.Through))
                .ToImmutableArray();
            var cached = await TryAcquireCachedAsync(
                    request,
                    candidates,
                    now,
                    progress,
                    cancellationToken)
                .ConfigureAwait(false);
            if (cached is not null)
            {
                return cached;
            }
        }

        using var lease = await _acquisitionGate.EnterAsync(
                "ecmwf-open-data-service",
                cancellationToken)
            .ConfigureAwait(false);
        return await AcquireCoreAsync(request, progress, cancellationToken).ConfigureAwait(false);
    }

    public DateTimeOffset SelectNewestCoveringRun(ForecastRequest request, DateTimeOffset now)
    {
        ValidateRequest(request);
        foreach (var candidate in GetCandidateRuns(now))
        {
            if (CanCover(candidate, request.From, request.Through))
            {
                return candidate;
            }
        }

        throw new InvalidOperationException(
            "No retained ECMWF IFS run can cover the requested departure and route horizon.");
    }

    public static ImmutableArray<int> GetRequiredForecastHours(
        DateTimeOffset runTime,
        DateTimeOffset from,
        DateTimeOffset through)
    {
        var run = runTime.ToUniversalTime();
        var startHours = (from.ToUniversalTime() - run).TotalHours;
        var endHours = (through.ToUniversalTime() - run).TotalHours;
        var available = IsLongCycle(run) ? LongCycleHours : ShortCycleHours;
        if (startHours < 0 || endHours < startHours || endHours > available[^1])
        {
            throw new ArgumentOutOfRangeException(
                nameof(through),
                $"The requested interval must be within the ECMWF {available[^1]}-hour horizon for the {run:HH} UTC cycle.");
        }

        var firstIndex = -1;
        var lastIndex = -1;
        for (var index = 0; index < available.Length; index++)
        {
            if (available[index] <= startHours)
            {
                firstIndex = index;
            }

            if (lastIndex < 0 && available[index] >= endHours)
            {
                lastIndex = index;
            }
        }

        if (firstIndex < 0 || lastIndex < firstIndex)
        {
            throw new ArgumentOutOfRangeException(
                nameof(through),
                "The ECMWF forecast cannot bracket the requested interval.");
        }

        return available[firstIndex..(lastIndex + 1)];
    }

    public Uri BuildProductUri(DateTimeOffset runTime, int forecastHour, string extension)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(extension);
        if (extension is not ("index" or "grib2"))
        {
            throw new ArgumentException("ECMWF product extension must be index or grib2.", nameof(extension));
        }

        var run = runTime.ToUniversalTime();
        var available = IsLongCycle(run) ? LongCycleHours : ShortCycleHours;
        if (!available.Contains(forecastHour))
        {
            throw new ArgumentOutOfRangeException(nameof(forecastHour));
        }

        var relative =
            $"{run:yyyyMMdd}/{run:HH}z/ifs/0p25/oper/{run:yyyyMMddHHmmss}-{forecastHour}h-oper-fc.{extension}";
        return new Uri(_options.BaseUri, relative);
    }

    internal static ImmutableArray<EcmwfIndexPart> ParseIndex(
        string jsonLines,
        int forecastHour,
        Uri dataUri)
    {
        ArgumentNullException.ThrowIfNull(jsonLines);
        ArgumentNullException.ThrowIfNull(dataUri);
        var matches = new Dictionary<string, (long Offset, long Length)>(StringComparer.Ordinal);
        using var reader = new StringReader(jsonLines);
        var lineNumber = 0;
        while (reader.ReadLine() is { } line)
        {
            lineNumber++;
            if (string.IsNullOrWhiteSpace(line))
            {
                continue;
            }

            JsonDocument document;
            try
            {
                document = JsonDocument.Parse(line);
            }
            catch (JsonException exception)
            {
                throw new InvalidDataException(
                    $"ECMWF index line {lineNumber} is invalid JSON.",
                    exception);
            }

            using (document)
            {
                var root = document.RootElement;
                if (!root.TryGetProperty("param", out var parameterElement) ||
                    parameterElement.ValueKind != JsonValueKind.String)
                {
                    continue;
                }

                var parameter = parameterElement.GetString();
                if (parameter is not ("10u" or "10v"))
                {
                    continue;
                }

                if (!root.TryGetProperty("levtype", out var levelType) ||
                    levelType.ValueKind != JsonValueKind.String ||
                    !string.Equals(levelType.GetString(), "sfc", StringComparison.Ordinal))
                {
                    continue;
                }

                if (!TryReadInt64(root, "_offset", out var offset) ||
                    !TryReadInt64(root, "_length", out var length) ||
                    offset < 0 ||
                    length <= 0)
                {
                    throw new InvalidDataException(
                        $"ECMWF index line {lineNumber} has an invalid byte offset or length.");
                }

                if (!matches.TryAdd(parameter, (offset, length)))
                {
                    throw new InvalidDataException(
                        $"ECMWF index contains more than one {parameter} surface field for forecast hour {forecastHour}.");
                }
            }
        }

        if (!matches.ContainsKey("10u") || !matches.ContainsKey("10v"))
        {
            throw new InvalidDataException(
                $"ECMWF index does not contain paired 10u and 10v surface fields for forecast hour {forecastHour}.");
        }

        var ordered = new[] { "10u", "10v" }
            .Select(parameter =>
            {
                var range = matches[parameter];
                var end = checked(range.Offset + range.Length);
                return (
                    Part: new EcmwfIndexPart(
                        forecastHour,
                        parameter,
                        range.Offset,
                        range.Length,
                        dataUri,
                        AtomicFileCache.CreateKey(
                            "ecmwf-part",
                            dataUri.AbsoluteUri,
                            parameter,
                            range.Offset.ToString(CultureInfo.InvariantCulture),
                            range.Length.ToString(CultureInfo.InvariantCulture))),
                    End: end);
            })
            .OrderBy(item => item.Part.Offset)
            .ToArray();
        if (ordered[0].End > ordered[1].Part.Offset)
        {
            throw new InvalidDataException(
                $"ECMWF index byte ranges overlap for forecast hour {forecastHour}.");
        }

        return [.. ordered.Select(item => item.Part).OrderBy(part => part.Parameter, StringComparer.Ordinal)];
    }

    private async ValueTask<ForecastAcquisition> AcquireCoreAsync(
        ForecastRequest request,
        IProgress<ForecastProgress>? progress,
        CancellationToken cancellationToken)
    {
        var now = _timeProvider.GetUtcNow();
        Report(progress, ForecastProgressStage.Queued, 0, "Selecting ECMWF IFS run");
        var candidates = GetCandidateRuns(now)
            .Where(candidate => CanCover(candidate, request.From, request.Through))
            .ToImmutableArray();
        if (candidates.IsEmpty)
        {
            throw new InvalidOperationException(
                "No retained ECMWF IFS run can cover the requested departure and route horizon.");
        }

        if (request.RefreshPolicy == ForecastRefreshPolicy.PreferCache)
        {
            var cached = await TryAcquireCachedAsync(
                    request,
                    candidates,
                    now,
                    progress,
                    cancellationToken)
                .ConfigureAwait(false);
            if (cached is not null)
            {
                return cached;
            }
        }

        EcmwfAcquisitionPlan? plan = null;
        Exception? lastFailure = null;
        for (var index = 0; index < candidates.Length; index++)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var candidate = candidates[index];
            Report(
                progress,
                ForecastProgressStage.Queued,
                index / (double)candidates.Length,
                $"Checking ECMWF IFS {candidate:yyyy-MM-dd HH}:00 UTC");
            try
            {
                plan = await TryBuildPlanAsync(request, candidate, cancellationToken).ConfigureAwait(false);
                if (plan is not null)
                {
                    break;
                }
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
            {
                throw;
            }
            catch (Exception exception) when (
                exception is HttpRequestException or ForecastDownloadException or InvalidDataException)
            {
                lastFailure = exception;
                _logger.LogWarning(
                    exception,
                    "ECMWF IFS run {RunTime} is not usable; trying an older covering run",
                    candidate);
            }
        }

        if (plan is null)
        {
            throw new ForecastDownloadException(
                "No published ECMWF IFS run with complete paired 10u/10v indexes covers the requested interval.",
                lastFailure ?? new InvalidOperationException("No complete ECMWF run was found."));
        }

        var existingAssembly = await _cache.TryGetAsync(plan.CacheKey, now, cancellationToken)
            .ConfigureAwait(false);
        if (existingAssembly is not null)
        {
            Report(progress, ForecastProgressStage.Completed, 1, "Using cached ECMWF IFS forecast");
            return CreateAcquisition(
                request,
                plan.RunTime,
                existingAssembly,
                ForecastAcquisitionSource.Cache,
                new ForecastCacheUsage(
                    plan.Parts.Length,
                    0,
                    plan.RunTime,
                    plan.RunTime));
        }

        var partsDirectory = Path.Combine(_cache.RootDirectory, "ecmwf-parts");
        Directory.CreateDirectory(partsDirectory);
        SweepOrphanedPartials(partsDirectory);
        var downloadedParts = 0;
        for (var index = 0; index < plan.Parts.Length; index++)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var part = plan.Parts[index];
            var partPath = Path.Combine(partsDirectory, part.PartKey + ".grib2");
            if (IsValidPartFile(partPath, part.Length))
            {
                File.SetLastWriteTimeUtc(partPath, now.UtcDateTime);
                Report(
                    progress,
                    ForecastProgressStage.Downloading,
                    (index + 1) / (double)plan.Parts.Length,
                    $"Resumed cached ECMWF f{part.ForecastHour:000} {part.Parameter}");
                continue;
            }

            if (File.Exists(partPath))
            {
                File.Delete(partPath);
            }

            if (downloadedParts > 0 && _options.MinimumRequestInterval > TimeSpan.Zero)
            {
                await Task.Delay(_options.MinimumRequestInterval, cancellationToken).ConfigureAwait(false);
            }

            Report(
                progress,
                ForecastProgressStage.Downloading,
                index / (double)plan.Parts.Length,
                $"Downloading ECMWF f{part.ForecastHour:000} {part.Parameter} ({index + 1}/{plan.Parts.Length})");
            await DownloadPartAsync(part, partPath, cancellationToken).ConfigureAwait(false);
            downloadedParts++;
        }

        Report(progress, ForecastProgressStage.Decoding, 1, "Assembling ECMWF IFS GRIB2 artifact");
        var cacheNow = _timeProvider.GetUtcNow();
        var stored = await _cache.StoreAsync(
                plan.CacheKey,
                cacheNow,
                DateTimeOffset.MaxValue,
                async (output, token) =>
                {
                    foreach (var part in plan.Parts)
                    {
                        var partPath = Path.Combine(partsDirectory, part.PartKey + ".grib2");
                        await using var input = new FileStream(
                            partPath,
                            FileMode.Open,
                            FileAccess.Read,
                            FileShare.Read,
                            128 * 1024,
                            FileOptions.Asynchronous | FileOptions.SequentialScan);
                        await input.CopyToAsync(output, token).ConfigureAwait(false);
                    }
                },
                cancellationToken)
            .ConfigureAwait(false);
        PrunePartCache(partsDirectory, plan.Parts.Select(part => part.PartKey).ToHashSet(StringComparer.Ordinal));

        Report(progress, ForecastProgressStage.Completed, 1, "ECMWF IFS forecast ready");
        return CreateAcquisition(
            request,
            plan.RunTime,
            stored,
            downloadedParts == 0 ? ForecastAcquisitionSource.Cache : ForecastAcquisitionSource.Remote,
            new ForecastCacheUsage(
                plan.Parts.Length - downloadedParts,
                downloadedParts,
                plan.RunTime,
                plan.RunTime));
    }

    private async ValueTask<ForecastAcquisition?> TryAcquireCachedAsync(
        ForecastRequest request,
        ImmutableArray<DateTimeOffset> candidates,
        DateTimeOffset now,
        IProgress<ForecastProgress>? progress,
        CancellationToken cancellationToken)
    {
        foreach (var candidate in candidates)
        {
            var hours = GetRequiredForecastHours(candidate, request.From, request.Through);
            var cacheKey = CreateAssemblyCacheKey(candidate, hours);
            var cached = await _cache.TryGetAsync(cacheKey, now, cancellationToken).ConfigureAwait(false);
            if (cached is null)
            {
                continue;
            }

            Report(progress, ForecastProgressStage.Completed, 1, "Using cached ECMWF IFS forecast");
            return CreateAcquisition(
                request,
                candidate,
                cached,
                ForecastAcquisitionSource.Cache,
                new ForecastCacheUsage(
                    hours.Length * 2,
                    0,
                    candidate,
                    candidate));
        }

        return null;
    }

    private async ValueTask<EcmwfAcquisitionPlan?> TryBuildPlanAsync(
        ForecastRequest request,
        DateTimeOffset runTime,
        CancellationToken cancellationToken)
    {
        var hours = GetRequiredForecastHours(runTime, request.From, request.Through);
        var builder = ImmutableArray.CreateBuilder<EcmwfIndexPart>(hours.Length * 2);
        foreach (var hour in hours)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var dataUri = BuildProductUri(runTime, hour, "grib2");
            var indexUri = BuildProductUri(runTime, hour, "index");
            var index = await DownloadIndexAsync(indexUri, cancellationToken).ConfigureAwait(false);
            if (index is null)
            {
                return null;
            }

            var parts = ParseIndex(index, hour, dataUri);
            if (parts.Any(part => part.Length > _options.MaximumRangeBytes))
            {
                throw new InvalidDataException(
                    $"ECMWF index contains a wind range larger than the configured limit for forecast hour {hour}.");
            }

            builder.AddRange(parts);
        }

        return new EcmwfAcquisitionPlan(
            runTime,
            hours,
            builder.MoveToImmutable(),
            CreateAssemblyCacheKey(runTime, hours));
    }

    private async ValueTask<string?> DownloadIndexAsync(
        Uri uri,
        CancellationToken cancellationToken)
    {
        Exception? lastFailure = null;
        for (var attempt = 1; attempt <= _options.MaximumDownloadAttempts; attempt++)
        {
            cancellationToken.ThrowIfCancellationRequested();
            try
            {
                using var request = new HttpRequestMessage(HttpMethod.Get, uri);
                using var response = await _httpClient.SendAsync(
                        request,
                        HttpCompletionOption.ResponseHeadersRead,
                        cancellationToken)
                    .ConfigureAwait(false);
                if (response.StatusCode == HttpStatusCode.NotFound)
                {
                    return null;
                }

                if (!response.IsSuccessStatusCode)
                {
                    throw CreateHttpFailure("ECMWF index", uri, response);
                }

                var contentLength = response.Content.Headers.ContentLength;
                if (contentLength is > 0 && contentLength > _options.MaximumIndexBytes)
                {
                    throw new ForecastDownloadException(
                        $"ECMWF index response for '{uri}' exceeds the configured size limit.");
                }

                await using var input = await response.Content.ReadAsStreamAsync(cancellationToken)
                    .ConfigureAwait(false);
                using var output = new MemoryStream();
                await CopyBoundedAsync(
                    input,
                    output,
                    _options.MaximumIndexBytes,
                    cancellationToken).ConfigureAwait(false);
                try
                {
                    return StrictUtf8.GetString(
                        output.GetBuffer(),
                        0,
                        checked((int)output.Length));
                }
                catch (DecoderFallbackException exception)
                {
                    throw new InvalidDataException(
                        $"ECMWF index response for '{uri.GetLeftPart(UriPartial.Path)}' is not valid UTF-8.",
                        exception);
                }
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
            {
                throw;
            }
            catch (Exception exception) when (IsTransientFailure(exception))
            {
                lastFailure = exception;
                if (attempt == _options.MaximumDownloadAttempts)
                {
                    break;
                }

                await DelayForRetryAsync(exception, attempt, cancellationToken).ConfigureAwait(false);
            }
        }

        throw new ForecastDownloadException(
            $"ECMWF index request failed after {_options.MaximumDownloadAttempts} attempts for '{uri}': {lastFailure!.Message}",
            lastFailure);
    }

    private async ValueTask DownloadPartAsync(
        EcmwfIndexPart part,
        string partPath,
        CancellationToken cancellationToken)
    {
        var tempPath = $"{partPath}.{Guid.NewGuid():N}.partial";
        try
        {
            Exception? lastFailure = null;
            for (var attempt = 1; attempt <= _options.MaximumDownloadAttempts; attempt++)
            {
                cancellationToken.ThrowIfCancellationRequested();
                try
                {
                    await DownloadRangeAttemptAsync(part, tempPath, cancellationToken)
                        .ConfigureAwait(false);
                    File.Move(tempPath, partPath);
                    return;
                }
                catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
                {
                    throw;
                }
                catch (Exception exception) when (IsTransientFailure(exception))
                {
                    lastFailure = exception;
                    TryDelete(tempPath);
                    if (attempt == _options.MaximumDownloadAttempts)
                    {
                        break;
                    }

                    await DelayForRetryAsync(exception, attempt, cancellationToken).ConfigureAwait(false);
                }
            }

            throw new ForecastDownloadException(
                $"ECMWF range request failed after {_options.MaximumDownloadAttempts} attempts for " +
                $"f{part.ForecastHour:000} {part.Parameter}: {lastFailure!.Message}",
                lastFailure);
        }
        finally
        {
            TryDelete(tempPath);
        }
    }

    private async ValueTask DownloadRangeAttemptAsync(
        EcmwfIndexPart part,
        string tempPath,
        CancellationToken cancellationToken)
    {
        var end = checked(part.Offset + part.Length - 1);
        using var request = new HttpRequestMessage(HttpMethod.Get, part.DataUri);
        request.Headers.Range = new RangeHeaderValue(part.Offset, end);
        using var response = await _httpClient.SendAsync(
                request,
                HttpCompletionOption.ResponseHeadersRead,
                cancellationToken)
            .ConfigureAwait(false);
        if (response.StatusCode != HttpStatusCode.PartialContent)
        {
            if (!response.IsSuccessStatusCode ||
                ForecastHttpSupport.IsTransientStatus(response.StatusCode))
            {
                throw CreateHttpFailure("ECMWF byte range", part.DataUri, response);
            }

            throw new ForecastDownloadException(
                $"ECMWF byte-range request for '{part.DataUri}' returned {(int)response.StatusCode}; " +
                "HTTP 206 Partial Content is required.");
        }

        var range = response.Content.Headers.ContentRange;
        if (range?.From != part.Offset || range.To != end ||
            response.Content.Headers.ContentLength != part.Length)
        {
            throw new ForecastDownloadException(
                $"ECMWF returned an inconsistent Content-Range for f{part.ForecastHour:000} {part.Parameter}.");
        }

        if (part.Length > _options.MaximumRangeBytes)
        {
            throw new ForecastDownloadException(
                $"ECMWF range for f{part.ForecastHour:000} {part.Parameter} exceeds the configured size limit.");
        }

        var mediaType = response.Content.Headers.ContentType?.MediaType;
        if (mediaType is not null && ForecastHttpSupport.IsTextMediaType(mediaType))
        {
            throw new ForecastDownloadException(
                $"ECMWF returned unexpected content type '{mediaType}' for a GRIB byte range.");
        }

        await using var input = await response.Content.ReadAsStreamAsync(cancellationToken)
            .ConfigureAwait(false);
        await using (var output = new FileStream(
                         tempPath,
                         FileMode.CreateNew,
                         FileAccess.Write,
                         FileShare.None,
                         128 * 1024,
                         FileOptions.Asynchronous | FileOptions.WriteThrough))
        {
            await CopyExactAsync(input, output, part.Length, cancellationToken).ConfigureAwait(false);
            await output.FlushAsync(cancellationToken).ConfigureAwait(false);
            output.Flush(true);
        }

        if (!IsValidPartFile(tempPath, part.Length))
        {
            throw new ForecastDownloadException(
                $"ECMWF range for f{part.ForecastHour:000} {part.Parameter} is not one complete GRIB message.");
        }
    }

    private ImmutableArray<DateTimeOffset> GetCandidateRuns(DateTimeOffset now)
    {
        var utc = now.ToUniversalTime();
        var latest = new DateTimeOffset(
            utc.Year,
            utc.Month,
            utc.Day,
            (utc.Hour / 6) * 6,
            0,
            0,
            TimeSpan.Zero);
        return
        [
            .. Enumerable.Range(0, _options.MaximumRunLookbackCycles)
                .Select(index => latest.AddHours(-6d * index))
        ];
    }

    private static bool CanCover(
        DateTimeOffset run,
        DateTimeOffset from,
        DateTimeOffset through)
    {
        var horizon = IsLongCycle(run) ? 240 : 90;
        return run <= from.ToUniversalTime() && through.ToUniversalTime() <= run.AddHours(horizon);
    }

    private static bool IsLongCycle(DateTimeOffset run) => run.ToUniversalTime().Hour is 0 or 12;

    private static string CreateAssemblyCacheKey(
        DateTimeOffset runTime,
        ImmutableArray<int> hours) =>
        AtomicFileCache.CreateKey(
            "ecmwf-ifs",
            runTime.ToUniversalTime().ToString("O", CultureInfo.InvariantCulture),
            string.Join(",", hours));

    private static ForecastAcquisition CreateAcquisition(
        ForecastRequest request,
        DateTimeOffset runTime,
        AtomicCacheEntry cached,
        ForecastAcquisitionSource source,
        ForecastCacheUsage usage) =>
        new(
            request,
            new ForecastRun(ForecastProvider.Ecmwf, ForecastModel.EcmwfIfs, runTime),
            new LocalGribArtifact(cached.Path, cached.LengthBytes, cached.Metadata.CreatedAt),
            source,
            cached.Metadata,
            usage);

    private static bool TryReadInt64(JsonElement root, string name, out long value)
    {
        value = 0;
        if (!root.TryGetProperty(name, out var element))
        {
            return false;
        }

        return element.ValueKind switch
        {
            JsonValueKind.Number => element.TryGetInt64(out value),
            JsonValueKind.String => long.TryParse(
                element.GetString(),
                NumberStyles.Integer,
                CultureInfo.InvariantCulture,
                out value),
            _ => false
        };
    }

    private async ValueTask DelayForRetryAsync(
        Exception exception,
        int completedAttempts,
        CancellationToken cancellationToken)
    {
        var retryAfter = exception is TransientEcmwfException transient
            ? transient.RetryAfter
            : null;
        var exponential = TimeSpan.FromTicks(
            Math.Min(
                _options.MaximumRetryDelay.Ticks,
                _options.BaseRetryDelay.Ticks * (1L << Math.Min(completedAttempts - 1, 20))));
        var delay = retryAfter is { } serverDelay && serverDelay > exponential
            ? serverDelay
            : exponential;
        if (delay > _options.MaximumRetryDelay)
        {
            delay = _options.MaximumRetryDelay;
        }

        if (delay > TimeSpan.Zero)
        {
            await Task.Delay(delay, cancellationToken).ConfigureAwait(false);
        }
    }

    private static Exception CreateHttpFailure(
        string operation,
        Uri uri,
        HttpResponseMessage response)
    {
        var message =
            $"{operation} returned {(int)response.StatusCode} ({response.ReasonPhrase}) for '{uri}'.";
        return ForecastHttpSupport.IsTransientStatus(response.StatusCode)
            ? new TransientEcmwfException(message, ForecastHttpSupport.GetRetryAfter(response))
            : new ForecastDownloadException(message);
    }

    private static bool IsTransientFailure(Exception exception) =>
        exception is HttpRequestException or HttpIOException or TransientEcmwfException ||
        exception is OperationCanceledException;


    private static async ValueTask CopyBoundedAsync(
        Stream input,
        Stream output,
        long maximumBytes,
        CancellationToken cancellationToken)
    {
        var buffer = new byte[128 * 1024];
        long total = 0;
        while (true)
        {
            var read = await input.ReadAsync(buffer, cancellationToken).ConfigureAwait(false);
            if (read == 0)
            {
                return;
            }

            total = checked(total + read);
            if (total > maximumBytes)
            {
                throw new ForecastDownloadException("ECMWF response exceeds the configured size limit.");
            }

            await output.WriteAsync(buffer.AsMemory(0, read), cancellationToken).ConfigureAwait(false);
        }
    }

    private static async ValueTask CopyExactAsync(
        Stream input,
        Stream output,
        long expectedBytes,
        CancellationToken cancellationToken)
    {
        var buffer = new byte[128 * 1024];
        long total = 0;
        while (total < expectedBytes)
        {
            var requested = (int)Math.Min(buffer.Length, expectedBytes - total);
            var read = await input.ReadAsync(buffer.AsMemory(0, requested), cancellationToken)
                .ConfigureAwait(false);
            if (read == 0)
            {
                throw new ForecastDownloadException(
                    $"ECMWF range ended after {total} bytes; {expectedBytes} bytes were expected.");
            }

            await output.WriteAsync(buffer.AsMemory(0, read), cancellationToken).ConfigureAwait(false);
            total += read;
        }

        var extra = await input.ReadAsync(buffer.AsMemory(0, 1), cancellationToken).ConfigureAwait(false);
        if (extra != 0)
        {
            throw new ForecastDownloadException("ECMWF range returned more bytes than its index length.");
        }
    }

    private static bool IsValidPartFile(string path, long expectedLength)
    {
        if (!File.Exists(path))
        {
            return false;
        }

        var file = new FileInfo(path);
        if (file.Length != expectedLength || file.Length < 20)
        {
            return false;
        }

        Span<byte> header = stackalloc byte[16];
        using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read);
        try
        {
            stream.ReadExactly(header);
            if (!header[..4].SequenceEqual("GRIB"u8) ||
                header[7] != 2 ||
                BinaryPrimitives.ReadUInt64BigEndian(header[8..]) != (ulong)expectedLength)
            {
                return false;
            }

            Span<byte> marker = stackalloc byte[4];
            stream.Seek(-4, SeekOrigin.End);
            stream.ReadExactly(marker);
            return marker.SequenceEqual("7777"u8);
        }
        catch (EndOfStreamException)
        {
            return false;
        }
    }

    private static void SweepOrphanedPartials(string directory)
    {
        foreach (var path in Directory.EnumerateFiles(directory, "*.partial", SearchOption.TopDirectoryOnly))
        {
            TryDelete(path);
        }
    }

    private void PrunePartCache(string directory, HashSet<string> protectedKeys)
    {
        var files = Directory.EnumerateFiles(directory, "*.grib2", SearchOption.TopDirectoryOnly)
            .Select(path => new FileInfo(path))
            .OrderBy(file => file.LastWriteTimeUtc)
            .ToList();
        var total = files.Sum(file => file.Length);
        foreach (var file in files)
        {
            if (total <= _options.MaximumPartCacheBytes)
            {
                break;
            }

            var key = Path.GetFileNameWithoutExtension(file.Name);
            if (protectedKeys.Contains(key))
            {
                continue;
            }

            total -= file.Length;
            TryDelete(file.FullName);
        }
    }

    private static void TryDelete(string path)
    {
        try
        {
            File.Delete(path);
        }
        catch (FileNotFoundException)
        {
        }
        catch (DirectoryNotFoundException)
        {
        }
    }

    private static void ValidateOptions(EcmwfOpenDataOptions options)
    {
        if (!options.BaseUri.IsAbsoluteUri ||
            options.BaseUri.Scheme is not ("http" or "https"))
        {
            throw new ArgumentException("The ECMWF base URI must be an absolute HTTP or HTTPS URI.", nameof(options));
        }

        if (options.MaximumRunLookbackCycles <= 0 ||
            options.MaximumIndexBytes <= 0 ||
            options.MaximumRangeBytes <= 0 ||
            options.MaximumPartCacheBytes <= 0 ||
            options.MaximumDownloadAttempts <= 0 ||
            options.BaseRetryDelay < TimeSpan.Zero ||
            options.MaximumRetryDelay < options.BaseRetryDelay ||
            options.MinimumRequestInterval < TimeSpan.Zero)
        {
            throw new ArgumentOutOfRangeException(nameof(options), "ECMWF acquisition limits are invalid.");
        }
    }

    private void ValidateRequest(ForecastRequest request)
    {
        ArgumentNullException.ThrowIfNull(request);
        if (request.Model != Model)
        {
            throw new ArgumentException("The ECMWF provider only supplies EcmwfIfs requests.", nameof(request));
        }
    }

    private void Report(
        IProgress<ForecastProgress>? progress,
        ForecastProgressStage stage,
        double fraction,
        string message) =>
        progress?.Report(new ForecastProgress(Provider, Model, stage, fraction, message));

    private sealed class TransientEcmwfException(
        string message,
        TimeSpan? retryAfter) : IOException(message)
    {
        public TimeSpan? RetryAfter { get; } = retryAfter;
    }
}
