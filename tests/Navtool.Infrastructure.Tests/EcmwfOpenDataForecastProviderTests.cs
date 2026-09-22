using System.Buffers.Binary;
using System.Net;
using System.Net.Http.Headers;
using System.Text;
using Navtool.Core;
using Navtool.Infrastructure;

namespace Navtool.Infrastructure.Tests;

public sealed class EcmwfOpenDataForecastProviderTests
{
    private static readonly DateTimeOffset Now =
        new(2026, 7, 14, 20, 0, 0, TimeSpan.Zero);
    private static readonly byte[] UWind = CreateGribMessage((byte)'u');
    private static readonly byte[] VWind = CreateGribMessage((byte)'v');

    [Fact]
    public void Required_steps_follow_long_and_short_cycle_cadence()
    {
        var longRun = new DateTimeOffset(2026, 7, 14, 12, 0, 0, TimeSpan.Zero);
        var shortRun = new DateTimeOffset(2026, 7, 14, 18, 0, 0, TimeSpan.Zero);

        Assert.Equal(
            [144, 150],
            EcmwfOpenDataForecastProvider.GetRequiredForecastHours(
                longRun,
                longRun.AddHours(144),
                longRun.AddHours(145)).ToArray());
        Assert.Equal(
            [87, 90],
            EcmwfOpenDataForecastProvider.GetRequiredForecastHours(
                shortRun,
                shortRun.AddHours(88),
                shortRun.AddHours(90)).ToArray());
        Assert.Throws<ArgumentOutOfRangeException>(() =>
            EcmwfOpenDataForecastProvider.GetRequiredForecastHours(
                shortRun,
                shortRun.AddHours(89),
                shortRun.AddHours(91)));
    }

    [Fact]
    public void Product_uri_uses_current_open_data_layout()
    {
        using var directory = new TestDirectory();
        using var client = new HttpClient(new EcmwfHandler());
        var provider = CreateProvider(directory.Path, client);
        var run = new DateTimeOffset(2026, 7, 14, 12, 0, 0, TimeSpan.Zero);

        var uri = provider.BuildProductUri(run, 24, "index");

        Assert.Equal(
            "https://example.test/forecasts/20260714/12z/ifs/0p25/oper/" +
            "20260714120000-24h-oper-fc.index",
            uri.AbsoluteUri);
    }

    [Fact]
    public void Download_estimate_reports_one_wind_download_per_forecast_time()
    {
        using var directory = new TestDirectory();
        using var client = new HttpClient(new EcmwfHandler());
        var provider = CreateProvider(directory.Path, client);

        var estimate = provider.EstimateDownload(CreateRequest(
            new DateTimeOffset(2026, 7, 14, 18, 0, 0, TimeSpan.Zero),
            TimeSpan.FromHours(3)));

        Assert.Equal(2, estimate.ForecastStepCount);
        Assert.Equal(2, estimate.PartCount);
    }

    [Fact]
    public void Index_parser_selects_exact_paired_surface_wind_ranges()
    {
        var dataUri = new Uri("https://example.test/data.grib2");
        var index =
            $$"""
              {"param":"2t","levtype":"sfc","_offset":0,"_length":5}
              {"param":"10u","levtype":"sfc","_offset":5,"_length":{{UWind.Length}}}
              {"param":"10v","levtype":"sfc","_offset":{{5 + UWind.Length}},"_length":"{{VWind.Length}}"}
              """;

        var parts = EcmwfOpenDataForecastProvider.ParseIndex(index, 3, dataUri);

        Assert.Collection(
            parts,
            part =>
            {
                Assert.Equal("10u", part.Parameter);
                Assert.Equal(5, part.Offset);
                Assert.Equal(UWind.Length, part.Length);
            },
            part =>
            {
                Assert.Equal("10v", part.Parameter);
                Assert.Equal(5 + UWind.Length, part.Offset);
                Assert.Equal(VWind.Length, part.Length);
            });
    }

    [Theory]
    [InlineData("""{"param":"10u","levtype":"sfc","_offset":0,"_length":15}""")]
    [InlineData(
        """
        {"param":"10u","levtype":"sfc","_offset":0,"_length":15}
        {"param":"10u","levtype":"sfc","_offset":15,"_length":15}
        {"param":"10v","levtype":"sfc","_offset":30,"_length":15}
        """)]
    [InlineData(
        """
        {"param":"10u","levtype":"sfc","_offset":0,"_length":20}
        {"param":"10v","levtype":"sfc","_offset":10,"_length":15}
        """)]
    [InlineData(
        """
        {"param":"10u","_offset":0,"_length":20}
        {"param":"10v","levtype":"sfc","_offset":20,"_length":20}
        """)]
    public void Index_parser_rejects_incomplete_duplicate_or_overlapping_ranges(string index)
    {
        Assert.Throws<InvalidDataException>(() =>
            EcmwfOpenDataForecastProvider.ParseIndex(
                index,
                3,
                new Uri("https://example.test/data.grib2")));
    }

    [Fact]
    public void Index_parser_reports_overflowing_unrelated_range_as_invalid_data()
    {
        var index =
            $$"""
              {"param":"2t","levtype":"sfc","_offset":{{long.MaxValue}},"_length":1}
              {"param":"10u","levtype":"sfc","_offset":0,"_length":{{UWind.Length}}}
              {"param":"10v","levtype":"sfc","_offset":{{UWind.Length}},"_length":{{VWind.Length}}}
              """;

        var exception = Assert.Throws<InvalidDataException>(() =>
            EcmwfOpenDataForecastProvider.ParseIndex(
                index,
                3,
                new Uri("https://example.test/data.grib2")));

        Assert.IsType<OverflowException>(exception.InnerException);
        Assert.Contains("line 1", exception.Message);
    }

    [Fact]
    public async Task Acquire_downloads_indexed_wind_parts_and_reuses_final_cache()
    {
        using var directory = new TestDirectory();
        var handler = new EcmwfHandler();
        using var client = new HttpClient(handler);
        var provider = CreateProvider(directory.Path, client);
        var request = CreateRequest(
            new DateTimeOffset(2026, 7, 14, 18, 0, 0, TimeSpan.Zero),
            TimeSpan.FromHours(3));
        var progress = new List<ForecastProgress>();

        var acquired = await provider.AcquireAsync(
            request,
            new InlineProgress<ForecastProgress>(progress.Add),
            CancellationToken.None);
        var requestsAfterDownload = handler.RequestCount;
        var cached = await provider.AcquireAsync(request, null, CancellationToken.None);

        Assert.Equal(ForecastAcquisitionSource.Remote, acquired.Source);
        Assert.Equal(ForecastAcquisitionSource.Cache, cached.Source);
        Assert.Equal(new DateTimeOffset(2026, 7, 14, 18, 0, 0, TimeSpan.Zero), acquired.Run.InitializedAt);
        Assert.Equal(2, acquired.CacheUsage!.DownloadedPartCount);
        Assert.Equal(2, cached.CacheUsage!.ReusedPartCount);
        Assert.Equal(requestsAfterDownload, handler.RequestCount);
        Assert.Equal(4, requestsAfterDownload);
        Assert.Equal(
            2 * (UWind.Length + VWind.Length),
            new FileInfo(acquired.Artifact.Path).Length);
        Assert.Equal(ForecastProgressStage.Completed, progress[^1].Stage);
        Assert.All(
            handler.RangeHeaders,
            range => Assert.Equal(2, range!.Ranges.Count));
    }

    [Fact]
    public async Task Acquire_falls_back_when_newest_covering_cycle_is_not_published()
    {
        using var directory = new TestDirectory();
        var handler = new EcmwfHandler(unpublishedCycleHour: 18);
        using var client = new HttpClient(handler);
        var provider = CreateProvider(directory.Path, client);
        var request = CreateRequest(
            new DateTimeOffset(2026, 7, 14, 19, 0, 0, TimeSpan.Zero),
            TimeSpan.FromHours(2));

        var acquired = await provider.AcquireAsync(request, null, CancellationToken.None);

        Assert.Equal(new DateTimeOffset(2026, 7, 14, 12, 0, 0, TimeSpan.Zero), acquired.Run.InitializedAt);
        Assert.Contains(handler.Requests, uri => uri.AbsolutePath.Contains("/18z/", StringComparison.Ordinal));
        Assert.Contains(handler.Requests, uri => uri.AbsolutePath.Contains("/12z/", StringComparison.Ordinal));
    }

    [Fact]
    public async Task Acquire_rejects_server_that_ignores_byte_range()
    {
        using var directory = new TestDirectory();
        var handler = new EcmwfHandler(ignoreRanges: true);
        using var client = new HttpClient(handler);
        var provider = CreateProvider(
            directory.Path,
            client,
            new EcmwfOpenDataOptions
            {
                BaseUri = new Uri("https://example.test/forecasts/"),
                MaximumDownloadAttempts = 1,
                MinimumRequestInterval = TimeSpan.Zero
            });

        var exception = await Assert.ThrowsAsync<ForecastDownloadException>(async () =>
            await provider.AcquireAsync(
                CreateRequest(
                    new DateTimeOffset(2026, 7, 14, 18, 0, 0, TimeSpan.Zero),
                    TimeSpan.FromHours(3)),
                null,
                CancellationToken.None));

        Assert.Contains("206", exception.InnerException?.Message ?? exception.Message);
        Assert.Empty(Directory.EnumerateFiles(directory.Path, "*.partial", SearchOption.AllDirectories));
    }

    [Fact]
    public async Task Acquire_rejects_grib_with_inconsistent_declared_length()
    {
        using var directory = new TestDirectory();
        var handler = new EcmwfHandler(invalidGribLength: true);
        using var client = new HttpClient(handler);
        var provider = CreateProvider(
            directory.Path,
            client,
            new EcmwfOpenDataOptions
            {
                BaseUri = new Uri("https://example.test/forecasts/"),
                MaximumDownloadAttempts = 1,
                MinimumRequestInterval = TimeSpan.Zero
            });

        var exception = await Assert.ThrowsAsync<ForecastDownloadException>(async () =>
            await provider.AcquireAsync(
                CreateRequest(
                    new DateTimeOffset(2026, 7, 14, 18, 0, 0, TimeSpan.Zero),
                    TimeSpan.FromHours(3)),
                null,
                CancellationToken.None));

        Assert.Contains("complete GRIB", exception.Message);
        Assert.Empty(Directory.EnumerateFiles(directory.Path, "*.partial", SearchOption.AllDirectories));
    }

    [Fact]
    public async Task Acquire_resumes_valid_parts_after_a_failed_attempt()
    {
        using var directory = new TestDirectory();
        using (var failingClient = new HttpClient(new EcmwfHandler(failRangeRequest: 2)))
        {
            var failingProvider = CreateProvider(
                directory.Path,
                failingClient,
                new EcmwfOpenDataOptions
                {
                    BaseUri = new Uri("https://example.test/forecasts/"),
                    MaximumDownloadAttempts = 1,
                    MinimumRequestInterval = TimeSpan.Zero
                });
            await Assert.ThrowsAsync<ForecastDownloadException>(async () =>
                await failingProvider.AcquireAsync(
                    CreateRequest(
                        new DateTimeOffset(2026, 7, 14, 18, 0, 0, TimeSpan.Zero),
                        TimeSpan.FromHours(3)),
                    null,
                    CancellationToken.None));
        }

        var cachedPart = Assert.Single(
            Directory.EnumerateFiles(directory.Path, "*.grib2", SearchOption.AllDirectories));
        Assert.Equal(UWind.Concat(VWind).ToArray(), await File.ReadAllBytesAsync(cachedPart));

        var resumedHandler = new EcmwfHandler();
        using var resumedClient = new HttpClient(resumedHandler);
        var resumedProvider = CreateProvider(directory.Path, resumedClient);
        var acquired = await resumedProvider.AcquireAsync(
            CreateRequest(
                new DateTimeOffset(2026, 7, 14, 18, 0, 0, TimeSpan.Zero),
                TimeSpan.FromHours(3)),
            null,
            CancellationToken.None);

        Assert.Equal(1, acquired.CacheUsage!.ReusedPartCount);
        Assert.Equal(1, acquired.CacheUsage.DownloadedPartCount);
        Assert.Equal(1, resumedHandler.RangeRequestCount);
    }

    [Fact]
    public async Task Acquire_rejects_multipart_response_missing_a_wind_field()
    {
        using var directory = new TestDirectory();
        var handler = new EcmwfHandler(omitSecondMultipartRange: true);
        using var client = new HttpClient(handler);
        var provider = CreateProvider(
            directory.Path,
            client,
            new EcmwfOpenDataOptions
            {
                BaseUri = new Uri("https://example.test/forecasts/"),
                MaximumDownloadAttempts = 1,
                MinimumRequestInterval = TimeSpan.Zero
            });

        var exception = await Assert.ThrowsAsync<ForecastDownloadException>(async () =>
            await provider.AcquireAsync(
                CreateRequest(
                    new DateTimeOffset(2026, 7, 14, 18, 0, 0, TimeSpan.Zero),
                    TimeSpan.FromHours(3)),
                null,
                CancellationToken.None));

        Assert.Contains("both wind fields", exception.Message);
        Assert.Empty(Directory.EnumerateFiles(directory.Path, "*.partial", SearchOption.AllDirectories));
    }

    [Fact]
    public async Task Acquire_rejects_multipart_response_with_inconsistent_object_length()
    {
        using var directory = new TestDirectory();
        var handler = new EcmwfHandler(invalidMultipartObjectLength: true);
        using var client = new HttpClient(handler);
        var provider = CreateProvider(
            directory.Path,
            client,
            new EcmwfOpenDataOptions
            {
                BaseUri = new Uri("https://example.test/forecasts/"),
                MaximumDownloadAttempts = 1,
                MinimumRequestInterval = TimeSpan.Zero
            });

        var exception = await Assert.ThrowsAsync<ForecastDownloadException>(async () =>
            await provider.AcquireAsync(
                CreateRequest(
                    new DateTimeOffset(2026, 7, 14, 18, 0, 0, TimeSpan.Zero),
                    TimeSpan.FromHours(3)),
                null,
                CancellationToken.None));

        Assert.Contains("unexpected Content-Range", exception.Message);
        Assert.Empty(Directory.EnumerateFiles(directory.Path, "*.partial", SearchOption.AllDirectories));
    }

    [Fact]
    public async Task Acquire_retries_rate_limited_multi_range_request()
    {
        using var directory = new TestDirectory();
        var handler = new EcmwfHandler(rateLimitRangeRequest: 1);
        using var client = new HttpClient(handler);
        var provider = CreateProvider(
            directory.Path,
            client,
            new EcmwfOpenDataOptions
            {
                BaseUri = new Uri("https://example.test/forecasts/"),
                BaseRetryDelay = TimeSpan.Zero,
                MaximumRetryDelay = TimeSpan.Zero,
                RateLimitRetryDelay = TimeSpan.Zero,
                MinimumRequestInterval = TimeSpan.Zero
            });

        var acquired = await provider.AcquireAsync(
            CreateRequest(
                new DateTimeOffset(2026, 7, 14, 18, 0, 0, TimeSpan.Zero),
                TimeSpan.Zero),
            null,
            CancellationToken.None);

        Assert.Equal(ForecastAcquisitionSource.Remote, acquired.Source);
        Assert.Equal(2, handler.RangeRequestCount);
    }

    [Fact]
    public async Task Refresh_policy_reuses_covering_cache_or_selects_newest_cycle()
    {
        using var directory = new TestDirectory();
        var clock = new MutableTimeProvider(Now);
        var handler = new EcmwfHandler();
        using var client = new HttpClient(handler);
        var provider = CreateProvider(directory.Path, client, timeProvider: clock);
        var from = new DateTimeOffset(2026, 7, 15, 3, 0, 0, TimeSpan.Zero);
        var preferCache = CreateRequest(from, TimeSpan.FromHours(3));

        var initial = await provider.AcquireAsync(preferCache, null, CancellationToken.None);
        clock.UtcNow = new DateTimeOffset(2026, 7, 15, 2, 0, 0, TimeSpan.Zero);
        var reused = await provider.AcquireAsync(preferCache, null, CancellationToken.None);
        var refreshed = await provider.AcquireAsync(
            new ForecastRequest(
                preferCache.Model,
                preferCache.Bounds,
                preferCache.From,
                preferCache.Through,
                ForecastRefreshPolicy.LatestAvailable),
            null,
            CancellationToken.None);

        Assert.Equal(new DateTimeOffset(2026, 7, 14, 18, 0, 0, TimeSpan.Zero), initial.Run.InitializedAt);
        Assert.Equal(initial.Run.InitializedAt, reused.Run.InitializedAt);
        Assert.Equal(ForecastAcquisitionSource.Cache, reused.Source);
        Assert.Equal(new DateTimeOffset(2026, 7, 15, 0, 0, 0, TimeSpan.Zero), refreshed.Run.InitializedAt);
        Assert.Equal(ForecastAcquisitionSource.Remote, refreshed.Source);
    }

    [Fact]
    public async Task Cache_maximum_age_defaults_to_forever_and_can_force_refresh()
    {
        using var directory = new TestDirectory();
        var clock = new MutableTimeProvider(Now);
        var handler = new EcmwfHandler();
        using var client = new HttpClient(handler);
        var provider = CreateProvider(directory.Path, client, timeProvider: clock);
        var from = new DateTimeOffset(2026, 7, 15, 3, 0, 0, TimeSpan.Zero);
        var forever = CreateRequest(from, TimeSpan.FromHours(3));

        var initial = await provider.AcquireAsync(forever, null, CancellationToken.None);
        var requestsAfterInitial = handler.RequestCount;
        clock.UtcNow = clock.UtcNow.AddHours(5);
        var reused = await provider.AcquireAsync(forever, null, CancellationToken.None);
        var requestsAfterReuse = handler.RequestCount;
        clock.UtcNow = clock.UtcNow.AddHours(2);
        var refreshed = await provider.AcquireAsync(
            new ForecastRequest(
                forever.Model,
                forever.Bounds,
                forever.From,
                forever.Through,
                ForecastRefreshPolicy.PreferCache,
                EcmwfCacheMaximumAge.SixHours),
            null,
            CancellationToken.None);

        Assert.Equal(ForecastAcquisitionSource.Remote, initial.Source);
        Assert.Equal(ForecastAcquisitionSource.Cache, reused.Source);
        Assert.Equal(requestsAfterInitial, requestsAfterReuse);
        Assert.Equal(ForecastAcquisitionSource.Remote, refreshed.Source);
        Assert.True(handler.RequestCount > requestsAfterInitial);
    }

    [Fact]
    public async Task Latest_policy_rebuilds_assembly_when_indexed_object_identity_changes()
    {
        using var directory = new TestDirectory();
        var handler = new EcmwfHandler();
        using var client = new HttpClient(handler);
        var provider = CreateProvider(directory.Path, client);
        var basic = CreateRequest(
            new DateTimeOffset(2026, 7, 14, 18, 0, 0, TimeSpan.Zero),
            TimeSpan.Zero);
        var latest = new ForecastRequest(
            basic.Model,
            basic.Bounds,
            basic.From,
            basic.Through,
            ForecastRefreshPolicy.LatestAvailable);

        await provider.AcquireAsync(latest, null, CancellationToken.None);
        var rangesAfterInitial = handler.RangeRequestCount;
        handler.ObjectLengthAdjustment = 5;
        var refreshed = await provider.AcquireAsync(latest, null, CancellationToken.None);

        Assert.Equal(ForecastAcquisitionSource.Remote, refreshed.Source);
        Assert.True(handler.RangeRequestCount > rangesAfterInitial);
    }

    [Fact]
    public async Task Covering_cache_hit_is_not_blocked_by_remote_acquisition()
    {
        using var directory = new TestDirectory();
        var clock = new MutableTimeProvider(Now);
        var remoteEntered = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var releaseRemote = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        EcmwfHandler? handler = null;
        handler = new EcmwfHandler(async (request, token) =>
        {
            if (request.RequestUri!.AbsolutePath.Contains("/00z/", StringComparison.Ordinal) &&
                request.RequestUri.AbsolutePath.EndsWith(".index", StringComparison.Ordinal))
            {
                remoteEntered.TrySetResult();
                await releaseRemote.Task.WaitAsync(token);
            }

            return handler!.CreateStandardResponse(request);
        });
        using var client = new HttpClient(handler);
        var provider = CreateProvider(directory.Path, client, timeProvider: clock);
        var from = new DateTimeOffset(2026, 7, 15, 3, 0, 0, TimeSpan.Zero);
        var preferCache = CreateRequest(from, TimeSpan.FromHours(3));
        await provider.AcquireAsync(preferCache, null, CancellationToken.None);
        clock.UtcNow = new DateTimeOffset(2026, 7, 15, 2, 0, 0, TimeSpan.Zero);
        var latest = new ForecastRequest(
            preferCache.Model,
            preferCache.Bounds,
            preferCache.From,
            preferCache.Through,
            ForecastRefreshPolicy.LatestAvailable);

        var remote = provider.AcquireAsync(latest, null, CancellationToken.None).AsTask();
        await remoteEntered.Task;
        var cached = provider.AcquireAsync(preferCache, null, CancellationToken.None).AsTask();
        try
        {
            Assert.Same(cached, await Task.WhenAny(cached, Task.Delay(TimeSpan.FromSeconds(1))));
            Assert.Equal(ForecastAcquisitionSource.Cache, (await cached).Source);
        }
        finally
        {
            releaseRemote.TrySetResult();
        }

        Assert.Equal(ForecastAcquisitionSource.Remote, (await remote).Source);
    }

    [Fact]
    public async Task Acquire_propagates_caller_cancellation_during_index_request()
    {
        using var directory = new TestDirectory();
        var entered = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var handler = new EcmwfHandler(async (_, token) =>
        {
            entered.SetResult();
            await Task.Delay(Timeout.InfiniteTimeSpan, token);
            throw new InvalidOperationException("Unreachable.");
        });
        using var client = new HttpClient(handler);
        var provider = CreateProvider(directory.Path, client);
        using var cancellation = new CancellationTokenSource();

        var acquisition = provider.AcquireAsync(
            CreateRequest(
                new DateTimeOffset(2026, 7, 14, 18, 0, 0, TimeSpan.Zero),
                TimeSpan.FromHours(3)),
            null,
            cancellation.Token).AsTask();
        await entered.Task;
        cancellation.Cancel();

        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => acquisition);
    }

    private static ForecastRequest CreateRequest(DateTimeOffset from, TimeSpan duration) =>
        new(
            ForecastModel.EcmwfIfs,
            new GeographicBounds(40, 50, -70, -50),
            from,
            from + duration);

    private static byte[] CreateGribMessage(byte component)
    {
        var bytes = new byte[21];
        "GRIB"u8.CopyTo(bytes);
        bytes[7] = 2;
        BinaryPrimitives.WriteUInt64BigEndian(bytes.AsSpan(8, 8), (ulong)bytes.Length);
        bytes[16] = component;
        "7777"u8.CopyTo(bytes.AsSpan(bytes.Length - 4));
        return bytes;
    }

    private static EcmwfOpenDataForecastProvider CreateProvider(
        string cacheRoot,
        HttpClient client,
        EcmwfOpenDataOptions? options = null,
        TimeProvider? timeProvider = null) =>
        new(
            client,
            new AtomicFileCache(new AtomicFileCacheOptions(cacheRoot)),
            timeProvider ?? new FixedTimeProvider(Now),
            options ?? new EcmwfOpenDataOptions
            {
                BaseUri = new Uri("https://example.test/forecasts/"),
                BaseRetryDelay = TimeSpan.Zero,
                MaximumRetryDelay = TimeSpan.Zero,
                MinimumRequestInterval = TimeSpan.Zero
            });

    private sealed class InlineProgress<T>(Action<T> report) : IProgress<T>
    {
        public void Report(T value) => report(value);
    }

    private sealed class EcmwfHandler : HttpMessageHandler
    {
        private readonly int? _unpublishedCycleHour;
        private readonly bool _ignoreRanges;
        private readonly int? _failRangeRequest;
        private readonly int? _rateLimitRangeRequest;
        private readonly bool _invalidGribLength;
        private readonly bool _omitSecondMultipartRange;
        private readonly bool _invalidMultipartObjectLength;
        private readonly Func<HttpRequestMessage, CancellationToken, Task<HttpResponseMessage>>? _override;
        private readonly List<Uri> _requests = [];
        private readonly List<RangeHeaderValue?> _rangeHeaders = [];
        private readonly object _sync = new();
        private int _requestCount;
        private int _rangeRequestCount;

        public EcmwfHandler(
            int? unpublishedCycleHour = null,
            bool ignoreRanges = false,
            int? failRangeRequest = null,
            bool invalidGribLength = false,
            bool omitSecondMultipartRange = false,
            bool invalidMultipartObjectLength = false,
            int? rateLimitRangeRequest = null)
        {
            _unpublishedCycleHour = unpublishedCycleHour;
            _ignoreRanges = ignoreRanges;
            _failRangeRequest = failRangeRequest;
            _invalidGribLength = invalidGribLength;
            _omitSecondMultipartRange = omitSecondMultipartRange;
            _invalidMultipartObjectLength = invalidMultipartObjectLength;
            _rateLimitRangeRequest = rateLimitRangeRequest;
        }

        public EcmwfHandler(
            Func<HttpRequestMessage, CancellationToken, Task<HttpResponseMessage>> responseOverride)
        {
            _override = responseOverride;
        }

        public int RequestCount => Volatile.Read(ref _requestCount);

        public int RangeRequestCount => Volatile.Read(ref _rangeRequestCount);
        public int ObjectLengthAdjustment { get; set; }

        public IReadOnlyList<Uri> Requests
        {
            get
            {
                lock (_sync)
                {
                    return _requests.ToArray();
                }
            }
        }

        public IReadOnlyList<RangeHeaderValue?> RangeHeaders
        {
            get
            {
                lock (_sync)
                {
                    return _rangeHeaders.ToArray();
                }
            }
        }

        protected override Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request,
            CancellationToken cancellationToken)
        {
            Interlocked.Increment(ref _requestCount);
            lock (_sync)
            {
                _requests.Add(request.RequestUri!);
            }

            if (_override is not null)
            {
                return _override(request, cancellationToken);
            }

            return Task.FromResult(CreateStandardResponse(request));
        }

        public HttpResponseMessage CreateStandardResponse(HttpRequestMessage request)
        {
            var uri = request.RequestUri!;
            if (_unpublishedCycleHour is { } hour &&
                uri.AbsolutePath.Contains($"/{hour:00}z/", StringComparison.Ordinal))
            {
                return new HttpResponseMessage(HttpStatusCode.NotFound);
            }

            if (uri.AbsolutePath.EndsWith(".index", StringComparison.Ordinal))
            {
                var content =
                    $$"""
                      {"param":"10u","levtype":"sfc","_offset":0,"_length":{{UWind.Length}}}
                      {"param":"10v","levtype":"sfc","_offset":{{UWind.Length}},"_length":{{VWind.Length}}}
                      {{(ObjectLengthAdjustment == 0 ? string.Empty :
                          $$"""{"param":"2t","levtype":"sfc","_offset":{{UWind.Length + VWind.Length}},"_length":{{ObjectLengthAdjustment}}}""")}}
                      """;
                return new HttpResponseMessage(HttpStatusCode.OK)
                {
                    Content = new StringContent(content)
                };
            }

            var range = request.Headers.Range;
            var rangeRequest = Interlocked.Increment(ref _rangeRequestCount);
            lock (_sync)
            {
                _rangeHeaders.Add(range);
            }

            if (_failRangeRequest == rangeRequest)
            {
                return new HttpResponseMessage(HttpStatusCode.BadRequest);
            }

            if (_rateLimitRangeRequest == rangeRequest)
            {
                var limited = new HttpResponseMessage(HttpStatusCode.TooManyRequests);
                limited.Headers.RetryAfter = new RetryConditionHeaderValue(TimeSpan.Zero);
                return limited;
            }

            var ranges = range?.Ranges.ToArray() ?? [];
            var fullFile = UWind.Concat(VWind).ToArray();
            var response = new HttpResponseMessage(
                _ignoreRanges ? HttpStatusCode.OK : HttpStatusCode.PartialContent)
            {
                Content = _ignoreRanges
                    ? new ByteArrayContent(fullFile)
                    : CreateMultipartContent(ranges)
            };
            if (_ignoreRanges)
            {
                response.Content.Headers.ContentType = new MediaTypeHeaderValue("application/octet-stream");
            }

            return response;
        }

        private HttpContent CreateMultipartContent(IReadOnlyList<RangeItemHeaderValue> ranges)
        {
            const string boundary = "navtool-test-boundary";
            using var output = new MemoryStream();
            var selected = _omitSecondMultipartRange ? ranges.Take(1) : ranges;
            foreach (var range in selected)
            {
                var from = range.From!.Value;
                var bytes = (from == 0 ? UWind : VWind).ToArray();
                if (_invalidGribLength)
                {
                    BinaryPrimitives.WriteUInt64BigEndian(
                        bytes.AsSpan(8, 8),
                        (ulong)(bytes.Length + 1));
                }

                WriteAscii(output, $"--{boundary}\r\n");
                WriteAscii(output, "Content-Type: application/octet-stream\r\n");
                WriteAscii(
                    output,
                    $"Content-Range: bytes {from}-{from + bytes.Length - 1}/" +
                    $"{UWind.Length + VWind.Length + ObjectLengthAdjustment + (_invalidMultipartObjectLength ? 1 : 0)}\r\n\r\n");
                output.Write(bytes);
                WriteAscii(output, "\r\n");
            }

            WriteAscii(output, $"--{boundary}--\r\n");
            var content = new ByteArrayContent(output.ToArray());
            content.Headers.ContentType = new MediaTypeHeaderValue("multipart/byteranges");
            content.Headers.ContentType.Parameters.Add(
                new NameValueHeaderValue("boundary", boundary));
            return content;
        }

        private static void WriteAscii(Stream output, string value) =>
            output.Write(Encoding.ASCII.GetBytes(value));
    }
}
