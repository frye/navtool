using Navtool.Core;

namespace Navtool.Infrastructure;

public sealed record EcmwfOpenDataOptions
{
    public bool Enabled { get; init; }
}

public enum ExperimentalProviderState
{
    Disabled,
    EnabledButUnsupported
}

public sealed record ForecastProviderEstimate(
    int EstimatedRangeRequests,
    long? EstimatedBytes,
    bool IsSupported,
    string Warning);

public sealed class ExperimentalProviderDisabledException : InvalidOperationException
{
    public ExperimentalProviderDisabledException(string message)
        : base(message)
    {
    }
}

public sealed class EcmwfOpenDataForecastProvider : IForecastProvider
{
    private readonly EcmwfOpenDataOptions _options;

    public EcmwfOpenDataForecastProvider(EcmwfOpenDataOptions? options = null)
    {
        _options = options ?? new EcmwfOpenDataOptions();
    }

    public ForecastProvider Provider => ForecastProvider.Ecmwf;

    public ForecastModel Model => ForecastModel.EcmwfIfs;

    public bool IsExperimental => true;

    public ExperimentalProviderState State => _options.Enabled
        ? ExperimentalProviderState.EnabledButUnsupported
        : ExperimentalProviderState.Disabled;

    public ForecastProviderEstimate Estimate(ForecastRequest request)
    {
        ArgumentNullException.ThrowIfNull(request);
        if (request.Model != Model)
        {
            throw new ArgumentException("The ECMWF provider only estimates EcmwfIfs requests.", nameof(request));
        }

        var sixHourIntervals = Math.Max(
            1,
            (int)Math.Ceiling((request.Through - request.From).TotalHours / 6d) + 1);
        return new ForecastProviderEstimate(
            checked(sixHourIntervals * 2),
            null,
            false,
            "Experimental only: official ECMWF Open Data .index byte ranges for 10u/10v are not yet implemented; no forecast will be returned.");
    }

    public ValueTask<ForecastAcquisition> AcquireAsync(
        ForecastRequest request,
        IProgress<ForecastProgress>? progress,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(request);
        if (request.Model != Model)
        {
            throw new ArgumentException("The ECMWF provider only supplies EcmwfIfs requests.", nameof(request));
        }

        cancellationToken.ThrowIfCancellationRequested();
        if (!_options.Enabled)
        {
            throw new ExperimentalProviderDisabledException(
                "ECMWF Open Data support is experimental and disabled. Set EcmwfOpenDataOptions.Enabled only after accepting the experimental limitation.");
        }

        throw new NotSupportedException(
            "ECMWF Open Data acquisition is explicitly unsupported: indexed HTTP byte-range retrieval for both 10u and 10v has not been implemented. No artifact was created.");
    }
}
