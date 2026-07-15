using System.Net;

namespace Navtool.Infrastructure.Tests;

internal sealed class TestDirectory : IDisposable
{
    public TestDirectory()
    {
        Path = System.IO.Path.Combine(
            AppContext.BaseDirectory,
            "test-artifacts",
            Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(Path);
    }

    public string Path { get; }

    public void Dispose()
    {
        if (Directory.Exists(Path))
        {
            Directory.Delete(Path, true);
        }
    }
}

internal sealed class FixedTimeProvider(DateTimeOffset utcNow) : TimeProvider
{
    public override DateTimeOffset GetUtcNow() => utcNow;
}

// Returns a strictly increasing "now" on every read and records how many reads
// happened. Used to prove AcquireAsync captures the clock exactly once, so its gate
// key and the stored artifact key cannot diverge across a run-publish boundary.
internal sealed class CountingTimeProvider(DateTimeOffset start, TimeSpan step) : TimeProvider
{
    private long _reads;

    public int Reads => (int)Interlocked.Read(ref _reads);

    public override DateTimeOffset GetUtcNow()
    {
        var index = Interlocked.Increment(ref _reads) - 1;
        return start + TimeSpan.FromTicks(step.Ticks * index);
    }
}

internal sealed class RecordingHttpHandler(
    Func<HttpRequestMessage, int, CancellationToken, Task<HttpResponseMessage>> respond)
    : HttpMessageHandler
{
    private int _active;
    private int _requestCount;
    private int _maximumConcurrency;
    private readonly List<Uri> _requests = [];
    private readonly object _sync = new();

    public int RequestCount => Volatile.Read(ref _requestCount);

    public int MaximumConcurrency => Volatile.Read(ref _maximumConcurrency);

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

    protected override async Task<HttpResponseMessage> SendAsync(
        HttpRequestMessage request,
        CancellationToken cancellationToken)
    {
        var count = Interlocked.Increment(ref _requestCount);
        var active = Interlocked.Increment(ref _active);
        UpdateMaximum(active);
        lock (_sync)
        {
            _requests.Add(request.RequestUri!);
        }

        try
        {
            return await respond(request, count, cancellationToken);
        }
        finally
        {
            Interlocked.Decrement(ref _active);
        }
    }

    public static HttpResponseMessage GribResponse(byte[]? bytes = null)
    {
        var response = new HttpResponseMessage(HttpStatusCode.OK)
        {
            Content = new ByteArrayContent(bytes ?? "GRIBpayload7777"u8.ToArray())
        };
        response.Content.Headers.ContentType =
            new System.Net.Http.Headers.MediaTypeHeaderValue("application/octet-stream");
        return response;
    }

    private void UpdateMaximum(int value)
    {
        while (true)
        {
            var current = Volatile.Read(ref _maximumConcurrency);
            if (value <= current ||
                Interlocked.CompareExchange(ref _maximumConcurrency, value, current) == current)
            {
                return;
            }
        }
    }
}
