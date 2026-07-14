using Navtool.Core;
using Navtool.Infrastructure;

namespace Navtool.Infrastructure.Tests;

public sealed class EcmwfOpenDataForecastProviderTests
{
    [Fact]
    public async Task Provider_is_disabled_by_default_and_never_fakes_success()
    {
        var provider = new EcmwfOpenDataForecastProvider();
        var request = CreateRequest();

        var estimate = provider.Estimate(request);
        Assert.Equal(ExperimentalProviderState.Disabled, provider.State);
        Assert.False(estimate.IsSupported);
        Assert.Contains("not yet implemented", estimate.Warning);
        await Assert.ThrowsAsync<ExperimentalProviderDisabledException>(async () =>
            await provider.AcquireAsync(request, null, CancellationToken.None));
    }

    [Fact]
    public async Task Opt_in_reports_explicit_unsupported_indexed_retrieval()
    {
        var provider = new EcmwfOpenDataForecastProvider(
            new EcmwfOpenDataOptions { Enabled = true });

        var exception = await Assert.ThrowsAsync<NotSupportedException>(async () =>
            await provider.AcquireAsync(CreateRequest(), null, CancellationToken.None));

        Assert.Equal(ExperimentalProviderState.EnabledButUnsupported, provider.State);
        Assert.Contains("byte-range", exception.Message);
        Assert.Contains("10u", exception.Message);
        Assert.Contains("10v", exception.Message);
    }

    private static ForecastRequest CreateRequest()
    {
        var from = new DateTimeOffset(2026, 7, 14, 18, 0, 0, TimeSpan.Zero);
        return new ForecastRequest(
            ForecastModel.EcmwfIfs,
            new GeographicBounds(40, 50, -70, -50),
            from,
            from.AddHours(18));
    }
}
