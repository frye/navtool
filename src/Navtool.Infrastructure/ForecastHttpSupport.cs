using System.Net;

namespace Navtool.Infrastructure;

internal static class ForecastHttpSupport
{
    public static bool IsTransientStatus(HttpStatusCode statusCode) =>
        statusCode is HttpStatusCode.RequestTimeout or HttpStatusCode.TooManyRequests ||
        (int)statusCode is 425 or >= 300 and <= 399 or >= 500 and <= 599;

    public static TimeSpan? GetRetryAfter(HttpResponseMessage response)
    {
        ArgumentNullException.ThrowIfNull(response);
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

    public static bool IsTextMediaType(string mediaType)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(mediaType);
        return mediaType.StartsWith("text/", StringComparison.OrdinalIgnoreCase) ||
               mediaType.Contains("html", StringComparison.OrdinalIgnoreCase) ||
               mediaType.Contains("json", StringComparison.OrdinalIgnoreCase) ||
               mediaType.Contains("xml", StringComparison.OrdinalIgnoreCase);
    }
}
