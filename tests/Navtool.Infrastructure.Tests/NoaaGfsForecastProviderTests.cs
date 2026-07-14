using System.Net;
using Navtool.Core;
using Navtool.Infrastructure;

namespace Navtool.Infrastructure.Tests;

public sealed class NoaaGfsForecastProviderTests
{
    private static readonly DateTimeOffset Now =
        new(2026, 7, 14, 15, 0, 0, TimeSpan.Zero);

    [Fact]
    public void Required_steps_bracket_transition_to_three_hour_intervals()
    {
        var run = new DateTimeOffset(2026, 7, 10, 0, 0, 0, TimeSpan.Zero);

        var steps = NoaaGfsForecastProvider.GetRequiredForecastHours(
            run,
            run.AddHours(119.5),
            run.AddHours(121));

        Assert.Equal([119, 120, 123], steps.ToArray());
    }

    [Fact]
    public void Longitude_windows_are_dateline_safe_and_split_the_greenwich_seam()
    {
        var dateline = NoaaGfsForecastProvider.GetNomadsLongitudeWindows(
            new GeographicBounds(-10, 10, 170, -170));
        var greenwich = NoaaGfsForecastProvider.GetNomadsLongitudeWindows(
            new GeographicBounds(-10, 10, -10, 10));

        Assert.Collection(
            dateline,
            window => Assert.Equal(new NomadsLongitudeWindow(170, 190), window));
        Assert.Collection(
            greenwich,
            window => Assert.Equal(new NomadsLongitudeWindow(350, 360), window),
            window => Assert.Equal(new NomadsLongitudeWindow(0, 10), window));
    }

    [Fact]
    public async Task Acquire_downloads_sequential_vector_subsets_and_reuses_cache()
    {
        using var directory = new TestDirectory();
        var handler = new RecordingHttpHandler(async (_, _, token) =>
        {
            await Task.Delay(5, token);
            return RecordingHttpHandler.GribResponse();
        });
        using var client = new HttpClient(handler);
        var provider = CreateProvider(directory.Path, client);
        var request = CreateRequest(new GeographicBounds(40, 45, 170, -170));
        var progress = new List<ForecastProgress>();

        var acquired = await provider.AcquireAsync(
            request,
            new SynchronousProgress<ForecastProgress>(progress.Add),
            CancellationToken.None);
        var cached = await provider.AcquireAsync(request, null, CancellationToken.None);

        Assert.Equal(ForecastAcquisitionSource.Remote, acquired.Source);
        Assert.Equal(ForecastAcquisitionSource.Cache, cached.Source);
        Assert.Equal(new DateTimeOffset(2026, 7, 14, 6, 0, 0, TimeSpan.Zero), acquired.Run.InitializedAt);
        Assert.Equal(3, handler.RequestCount);
        Assert.Equal(1, handler.MaximumConcurrency);
        Assert.All(handler.Requests, uri =>
        {
            var query = Uri.UnescapeDataString(uri.Query);
            Assert.Contains("lev_10_m_above_ground=on", query);
            Assert.Contains("var_UGRD=on", query);
            Assert.Contains("var_VGRD=on", query);
            Assert.Contains("leftlon=170", query);
            Assert.Contains("rightlon=190", query);
        });
        Assert.Equal(3 * "GRIBpayload7777"u8.Length, new FileInfo(acquired.Artifact.Path).Length);
        Assert.Contains(progress, item => item.Stage == ForecastProgressStage.Downloading);
        Assert.Equal(ForecastProgressStage.Completed, progress[^1].Stage);
    }

    [Fact]
    public async Task Acquire_rejects_non_grib_content_without_cache_artifact()
    {
        using var directory = new TestDirectory();
        var handler = new RecordingHttpHandler((_, _, _) =>
            Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new StringContent("<html>error</html>")
            }));
        using var client = new HttpClient(handler);
        var provider = CreateProvider(directory.Path, client);

        var exception = await Assert.ThrowsAsync<ForecastDownloadException>(async () =>
            await provider.AcquireAsync(CreateRequest(), null, CancellationToken.None));

        Assert.Contains("content type", exception.Message, StringComparison.OrdinalIgnoreCase);
        Assert.Empty(Directory.EnumerateFiles(directory.Path));
    }

    [Fact]
    public async Task Acquire_honors_pre_cancelled_token_without_http()
    {
        using var directory = new TestDirectory();
        var handler = new RecordingHttpHandler((_, _, _) =>
            Task.FromResult(RecordingHttpHandler.GribResponse()));
        using var client = new HttpClient(handler);
        var provider = CreateProvider(directory.Path, client);
        using var cancellation = new CancellationTokenSource();
        cancellation.Cancel();

        await Assert.ThrowsAnyAsync<OperationCanceledException>(async () =>
            await provider.AcquireAsync(CreateRequest(), null, cancellation.Token));
        Assert.Equal(0, handler.RequestCount);
    }

    private static NoaaGfsForecastProvider CreateProvider(string path, HttpClient client) =>
        new(
            client,
            new AtomicFileCache(new AtomicFileCacheOptions(path)),
            new FixedTimeProvider(Now));

    private static ForecastRequest CreateRequest(GeographicBounds? bounds = null) =>
        new(
            ForecastModel.NoaaGfs,
            bounds ?? new GeographicBounds(40, 45, -70, -60),
            new DateTimeOffset(2026, 7, 14, 8, 0, 0, TimeSpan.Zero),
            new DateTimeOffset(2026, 7, 14, 10, 0, 0, TimeSpan.Zero));

    private sealed class SynchronousProgress<T>(Action<T> action) : IProgress<T>
    {
        public void Report(T value) => action(value);
    }
}
