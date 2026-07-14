using System.Collections.Immutable;

namespace Navtool.Core;

public enum ForecastProvider
{
    Noaa,
    Ecmwf
}

public enum ForecastModel
{
    NoaaGfs,
    EcmwfIfs
}

public enum ForecastAcquisitionSource
{
    Remote,
    Cache
}

public enum ForecastProgressStage
{
    Queued,
    Downloading,
    Decoding,
    Completed
}

public static class ForecastModelExtensions
{
    public static ForecastProvider Provider(this ForecastModel model) => model switch
    {
        ForecastModel.NoaaGfs => ForecastProvider.Noaa,
        ForecastModel.EcmwfIfs => ForecastProvider.Ecmwf,
        _ => throw new ArgumentOutOfRangeException(nameof(model))
    };
}

public sealed record ForecastRun
{
    public ForecastRun(ForecastProvider provider, ForecastModel model, DateTimeOffset initializedAt)
    {
        if (!Enum.IsDefined(provider))
        {
            throw new ArgumentOutOfRangeException(nameof(provider));
        }

        if (model.Provider() != provider)
        {
            throw new ArgumentException($"{model} is not supplied by {provider}.", nameof(provider));
        }

        Provider = provider;
        Model = model;
        InitializedAt = initializedAt.ToUniversalTime();
    }

    public ForecastProvider Provider { get; }

    public ForecastModel Model { get; }

    public DateTimeOffset InitializedAt { get; }
}

public sealed record ForecastRequest
{
    public ForecastRequest(
        ForecastModel model,
        GeographicBounds bounds,
        DateTimeOffset from,
        DateTimeOffset through)
    {
        _ = model.Provider();
        var utcFrom = from.ToUniversalTime();
        var utcThrough = through.ToUniversalTime();
        if (utcThrough < utcFrom)
        {
            throw new ArgumentException("Forecast end time cannot precede its start time.", nameof(through));
        }

        Model = model;
        Bounds = bounds;
        From = utcFrom;
        Through = utcThrough;
    }

    public ForecastProvider Provider => Model.Provider();

    public ForecastModel Model { get; }

    public GeographicBounds Bounds { get; }

    public DateTimeOffset From { get; }

    public DateTimeOffset Through { get; }
}

public sealed record ForecastProgress
{
    public ForecastProgress(
        ForecastProvider provider,
        ForecastModel model,
        ForecastProgressStage stage,
        double fraction,
        string? message = null)
    {
        if (model.Provider() != provider)
        {
            throw new ArgumentException($"{model} is not supplied by {provider}.", nameof(provider));
        }

        if (!double.IsFinite(fraction) || fraction is < 0 or > 1)
        {
            throw new ArgumentOutOfRangeException(nameof(fraction), "Progress must be between zero and one.");
        }

        Provider = provider;
        Model = model;
        Stage = stage;
        Fraction = fraction;
        Message = message;
    }

    public ForecastProvider Provider { get; }

    public ForecastModel Model { get; }

    public ForecastProgressStage Stage { get; }

    public double Fraction { get; }

    public string? Message { get; }
}

public sealed record CacheMetadata
{
    public CacheMetadata(string key, DateTimeOffset createdAt, DateTimeOffset expiresAt)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(key);
        var utcCreatedAt = createdAt.ToUniversalTime();
        var utcExpiresAt = expiresAt.ToUniversalTime();
        if (utcExpiresAt < utcCreatedAt)
        {
            throw new ArgumentException("Cache expiry cannot precede creation.", nameof(expiresAt));
        }

        Key = key;
        CreatedAt = utcCreatedAt;
        ExpiresAt = utcExpiresAt;
    }

    public string Key { get; }

    public DateTimeOffset CreatedAt { get; }

    public DateTimeOffset ExpiresAt { get; }

    public bool IsFreshAt(DateTimeOffset instant) => instant.ToUniversalTime() < ExpiresAt;
}

public sealed record WeatherSample
{
    public WeatherSample(
        Coordinate location,
        DateTimeOffset validAt,
        double windSpeedMetersPerSecond,
        double windDirectionDegrees,
        double? waveHeightMeters = null)
    {
        if (!double.IsFinite(windSpeedMetersPerSecond) || windSpeedMetersPerSecond < 0)
        {
            throw new ArgumentOutOfRangeException(nameof(windSpeedMetersPerSecond));
        }

        if (!double.IsFinite(windDirectionDegrees) || windDirectionDegrees is < 0 or >= 360)
        {
            throw new ArgumentOutOfRangeException(nameof(windDirectionDegrees));
        }

        if (waveHeightMeters is { } waveHeight && (!double.IsFinite(waveHeight) || waveHeight < 0))
        {
            throw new ArgumentOutOfRangeException(nameof(waveHeightMeters));
        }

        Location = location;
        ValidAt = validAt.ToUniversalTime();
        WindSpeedMetersPerSecond = windSpeedMetersPerSecond;
        WindDirectionDegrees = windDirectionDegrees;
        WaveHeightMeters = waveHeightMeters;
    }

    public Coordinate Location { get; }

    public DateTimeOffset ValidAt { get; }

    public double WindSpeedMetersPerSecond { get; }

    public double WindDirectionDegrees { get; }

    public double? WaveHeightMeters { get; }
}

public sealed record WeatherSampleGrid
{
    public WeatherSampleGrid(
        ForecastRun run,
        GeographicBounds bounds,
        IEnumerable<WeatherSample> samples)
    {
        ArgumentNullException.ThrowIfNull(run);
        ArgumentNullException.ThrowIfNull(samples);
        var immutableSamples = samples.ToImmutableArray();
        if (immutableSamples.IsEmpty)
        {
            throw new ArgumentException("A weather grid must contain at least one sample.", nameof(samples));
        }

        Run = run;
        Bounds = bounds;
        Samples = immutableSamples;
        ValidFrom = immutableSamples.Min(sample => sample.ValidAt);
        ValidThrough = immutableSamples.Max(sample => sample.ValidAt);
    }

    public ForecastRun Run { get; }

    public GeographicBounds Bounds { get; }

    public ImmutableArray<WeatherSample> Samples { get; }

    public DateTimeOffset ValidFrom { get; }

    public DateTimeOffset ValidThrough { get; }
}

public sealed record LocalGribArtifact
{
    public LocalGribArtifact(
        string path,
        long? lengthBytes = null,
        DateTimeOffset? lastModifiedAt = null)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(path);
        if (!System.IO.Path.IsPathFullyQualified(path))
        {
            throw new ArgumentException("A GRIB artifact path must be absolute.", nameof(path));
        }

        if (lengthBytes < 0)
        {
            throw new ArgumentOutOfRangeException(nameof(lengthBytes));
        }

        Path = System.IO.Path.GetFullPath(path);
        LengthBytes = lengthBytes;
        LastModifiedAt = lastModifiedAt?.ToUniversalTime();
    }

    public string Path { get; }

    public long? LengthBytes { get; }

    public DateTimeOffset? LastModifiedAt { get; }
}

public sealed record ForecastAcquisition
{
    public ForecastAcquisition(
        ForecastRequest request,
        ForecastRun run,
        LocalGribArtifact artifact,
        ForecastAcquisitionSource source,
        CacheMetadata? cache = null)
    {
        ArgumentNullException.ThrowIfNull(request);
        ArgumentNullException.ThrowIfNull(run);
        ArgumentNullException.ThrowIfNull(artifact);
        if (request.Model != run.Model)
        {
            throw new ArgumentException("The acquired forecast run does not match the request.", nameof(run));
        }

        Request = request;
        Run = run;
        Artifact = artifact;
        Source = source;
        Cache = cache;
    }

    public ForecastRequest Request { get; }

    public ForecastProvider Provider => Run.Provider;

    public ForecastRun Run { get; }

    public LocalGribArtifact Artifact { get; }

    public ForecastAcquisitionSource Source { get; }

    public CacheMetadata? Cache { get; }
}

public interface IForecastProvider
{
    ForecastProvider Provider { get; }

    ForecastModel Model { get; }

    ValueTask<ForecastAcquisition> AcquireAsync(
        ForecastRequest request,
        IProgress<ForecastProgress>? progress,
        CancellationToken cancellationToken);
}
