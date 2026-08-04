using System.Buffers.Binary;
using System.Net;
using System.Net.Http.Headers;
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
        Assert.Equal(4, acquired.CacheUsage!.DownloadedPartCount);
        Assert.Equal(4, cached.CacheUsage!.ReusedPartCount);
        Assert.Equal(requestsAfterDownload, handler.RequestCount);
        Assert.Equal(
            2 * (UWind.Length + VWind.Length),
            new FileInfo(acquired.Artifact.Path).Length);
        Assert.Equal(ForecastProgressStage.Completed, progress[^1].Stage);
        Assert.All(handler.RangeHeaders, range => Assert.NotNull(range));
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
        Assert.Equal(3, acquired.CacheUsage.DownloadedPartCount);
        Assert.Equal(3, resumedHandler.RangeRequestCount);
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
        private readonly bool _invalidGribLength;
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
            bool invalidGribLength = false)
        {
            _unpublishedCycleHour = unpublishedCycleHour;
            _ignoreRanges = ignoreRanges;
            _failRangeRequest = failRangeRequest;
            _invalidGribLength = invalidGribLength;
        }

        public EcmwfHandler(
            Func<HttpRequestMessage, CancellationToken, Task<HttpResponseMessage>> responseOverride)
        {
            _override = responseOverride;
        }

        public int RequestCount => Volatile.Read(ref _requestCount);

        public int RangeRequestCount => Volatile.Read(ref _rangeRequestCount);

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

            var uri = request.RequestUri!;
            if (_unpublishedCycleHour is { } hour &&
                uri.AbsolutePath.Contains($"/{hour:00}z/", StringComparison.Ordinal))
            {
                return Task.FromResult(new HttpResponseMessage(HttpStatusCode.NotFound));
            }

            if (uri.AbsolutePath.EndsWith(".index", StringComparison.Ordinal))
            {
                var content =
                    $$"""
                      {"param":"10u","levtype":"sfc","_offset":0,"_length":{{UWind.Length}}}
                      {"param":"10v","levtype":"sfc","_offset":{{UWind.Length}},"_length":{{VWind.Length}}}
                      """;
                return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK)
                {
                    Content = new StringContent(content)
                });
            }

            var range = request.Headers.Range;
            var rangeRequest = Interlocked.Increment(ref _rangeRequestCount);
            lock (_sync)
            {
                _rangeHeaders.Add(range);
            }

            if (_failRangeRequest == rangeRequest)
            {
                return Task.FromResult(new HttpResponseMessage(HttpStatusCode.BadRequest));
            }

            var from = range?.Ranges.Single().From;
            var bytes = (from == 0 ? UWind : VWind).ToArray();
            if (_invalidGribLength)
            {
                BinaryPrimitives.WriteUInt64BigEndian(
                    bytes.AsSpan(8, 8),
                    (ulong)(bytes.Length + 1));
            }
            var response = new HttpResponseMessage(
                _ignoreRanges ? HttpStatusCode.OK : HttpStatusCode.PartialContent)
            {
                Content = new ByteArrayContent(bytes)
            };
            response.Content.Headers.ContentType = new MediaTypeHeaderValue("application/octet-stream");
            if (!_ignoreRanges)
            {
                response.Content.Headers.ContentRange = new ContentRangeHeaderValue(
                    from!.Value,
                    from.Value + bytes.Length - 1,
                    UWind.Length + VWind.Length);
            }

            return Task.FromResult(response);
        }
    }
}
