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
    Cache,
    LocalFile
}

public enum ForecastSelectionKind
{
    OfficialDownload,
    LocalFile
}

public enum ForecastRefreshPolicy
{
    PreferCache,
    LatestAvailable
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
        DateTimeOffset through,
        ForecastRefreshPolicy refreshPolicy = ForecastRefreshPolicy.PreferCache)
    {
        _ = model.Provider();
        if (!Enum.IsDefined(refreshPolicy))
        {
            throw new ArgumentOutOfRangeException(nameof(refreshPolicy));
        }

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
        RefreshPolicy = refreshPolicy;
    }

    public ForecastProvider Provider => Model.Provider();

    public ForecastModel Model { get; }

    public GeographicBounds Bounds { get; }

    public DateTimeOffset From { get; }

    public DateTimeOffset Through { get; }

    public ForecastRefreshPolicy RefreshPolicy { get; }
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

public sealed record LocalForecastDescriptor
{
    public LocalForecastDescriptor(
        ForecastModel model,
        LocalGribArtifact artifact,
        DateTimeOffset initializedAt,
        DateTimeOffset validFrom,
        DateTimeOffset validThrough,
        GeographicBounds bounds)
    {
        ArgumentNullException.ThrowIfNull(artifact);
        var utcInitializedAt = initializedAt.ToUniversalTime();
        var utcValidFrom = validFrom.ToUniversalTime();
        var utcValidThrough = validThrough.ToUniversalTime();
        if (utcValidThrough < utcValidFrom)
        {
            throw new ArgumentException("Forecast validity cannot end before it begins.", nameof(validThrough));
        }

        _ = model.Provider();
        Model = model;
        Artifact = artifact;
        InitializedAt = utcInitializedAt;
        ValidFrom = utcValidFrom;
        ValidThrough = utcValidThrough;
        Bounds = bounds;
    }

    public ForecastModel Model { get; }

    public LocalGribArtifact Artifact { get; }

    public DateTimeOffset InitializedAt { get; }

    public DateTimeOffset ValidFrom { get; }

    public DateTimeOffset ValidThrough { get; }

    public GeographicBounds Bounds { get; }
}

public sealed record ForecastSelection
{
    private ForecastSelection(
        ForecastModel model,
        ForecastSelectionKind kind,
        LocalForecastDescriptor? localForecast)
    {
        _ = model.Provider();
        if ((kind == ForecastSelectionKind.LocalFile) != (localForecast is not null))
        {
            throw new ArgumentException("Local forecast metadata is required only for local file selections.");
        }

        if (localForecast is not null && localForecast.Model != model)
        {
            throw new ArgumentException("The local forecast model does not match the selection.", nameof(localForecast));
        }

        Model = model;
        Kind = kind;
        LocalForecast = localForecast;
    }

    public ForecastModel Model { get; }

    public ForecastSelectionKind Kind { get; }

    public LocalForecastDescriptor? LocalForecast { get; }

    public static ForecastSelection OfficialDownload(ForecastModel model) =>
        new(model, ForecastSelectionKind.OfficialDownload, null);

    public static ForecastSelection LocalFile(LocalForecastDescriptor forecast)
    {
        ArgumentNullException.ThrowIfNull(forecast);
        return new ForecastSelection(forecast.Model, ForecastSelectionKind.LocalFile, forecast);
    }
}

public sealed record ForecastAcquisition
{
    public ForecastAcquisition(
        ForecastRequest request,
        ForecastRun run,
        LocalGribArtifact artifact,
        ForecastAcquisitionSource source,
        CacheMetadata? cache = null,
        ForecastCacheUsage? cacheUsage = null,
        ForecastCoverage? coverage = null)
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
        CacheUsage = cacheUsage;
        Coverage = coverage;
    }

    public ForecastRequest Request { get; }

    public ForecastProvider Provider => Run.Provider;

    public ForecastRun Run { get; }

    public LocalGribArtifact Artifact { get; }

    public ForecastAcquisitionSource Source { get; }

    public CacheMetadata? Cache { get; }

    public ForecastCacheUsage? CacheUsage { get; }

    public ForecastCoverage? Coverage { get; }
}

public sealed record ForecastCoverage
{
    public ForecastCoverage(GeographicBounds effectiveBounds, IEnumerable<DateTimeOffset> validTimes,
        TimeSpan? maximumInterpolationGap = null)
    {
        ArgumentNullException.ThrowIfNull(validTimes);
        ValidTimes = validTimes.Select(time => time.ToUniversalTime()).Distinct().Order().ToImmutableArray();
        if (ValidTimes.IsEmpty) throw new ArgumentException("Forecast coverage requires at least one valid time.", nameof(validTimes));
        if (maximumInterpolationGap <= TimeSpan.Zero) throw new ArgumentOutOfRangeException(nameof(maximumInterpolationGap));
        EffectiveBounds = effectiveBounds;
        MaximumInterpolationGap = maximumInterpolationGap;
    }
    public GeographicBounds EffectiveBounds { get; }
    public ImmutableArray<DateTimeOffset> ValidTimes { get; private init; }
    public DateTimeOffset ValidFrom => ValidTimes[0];
    public DateTimeOffset ValidThrough => ValidTimes[^1];
    public TimeSpan? MaximumInterpolationGap { get; }
    public TimeSpan? MinimumTimeSpacing => ValidTimes.Length < 2
        ? null : ValidTimes.Zip(ValidTimes.Skip(1)).Min(pair => pair.Second - pair.First);
    public TimeSpan? MaximumTimeSpacing => ValidTimes.Length < 2
        ? null : ValidTimes.Zip(ValidTimes.Skip(1)).Max(pair => pair.Second - pair.First);

    internal bool HasSameContent(ForecastCoverage? other) =>
        other is not null && ValidTimes.SequenceEqual(other.ValidTimes) &&
        this == other with { ValidTimes = ValidTimes };
}

/// <summary>Validate official product cadence, not a single gap limit that hides missing early-hour fields.</summary>
public static class ForecastTimePolicy
{
    public static void Validate(ForecastRun run, IEnumerable<DateTimeOffset> validTimes,
        bool officialProduct, TimeSpan? localMaximumGap = null)
    {
        ArgumentNullException.ThrowIfNull(run);
        ArgumentNullException.ThrowIfNull(validTimes);
        var times = validTimes.Select(time => time.ToUniversalTime()).Distinct().Order().ToArray();
        if (times.Length == 0)
            throw new RoutingException(RoutingFailureKind.InvalidForecast, "No forecast valid times were loaded.");
        if (!officialProduct)
        {
            if (localMaximumGap is not { } gap || gap <= TimeSpan.Zero)
                throw new RoutingException(RoutingFailureKind.InvalidConfiguration, "Local forecasts require an explicit interpolation gap policy.");
            if (times.Zip(times.Skip(1)).Any(pair => pair.Second - pair.First > gap))
                throw new RoutingException(RoutingFailureKind.InvalidForecast, "The local forecast contains a gap larger than the selected policy.");
            return;
        }
        for (var index = 0; index < times.Length; index++)
        {
            var hours = (times[index] - run.InitializedAt).TotalHours;
            var shortEcmwf = run.Model == ForecastModel.EcmwfIfs && run.InitializedAt.Hour is 6 or 18;
            var maximum = run.Model == ForecastModel.NoaaGfs ? 384 : shortEcmwf ? 90 : 240;
            var cadence = run.Model == ForecastModel.NoaaGfs
                ? hours <= 120 ? 1 : 3
                : hours <= 144 ? 3 : 6;
            if (hours < 0 || hours > maximum || hours % cadence != 0)
                throw new RoutingException(RoutingFailureKind.InvalidForecast, "Forecast valid time is outside the selected product schedule.");
            if (index == 0) continue;
            var previousHours = (times[index - 1] - run.InitializedAt).TotalHours;
            var nextStep = run.Model == ForecastModel.NoaaGfs
                ? previousHours < 120 ? 1 : 3
                : previousHours < 144 ? 3 : 6;
            if (hours != previousHours + nextStep)
                throw new RoutingException(RoutingFailureKind.InvalidForecast, "The official forecast is missing an expected valid time.");
        }
    }
}

public sealed record ForecastCacheUsage
{
    public ForecastCacheUsage(
        int reusedPartCount,
        int downloadedPartCount,
        DateTimeOffset selectedRun,
        DateTimeOffset latestPublishedRun)
    {
        if (reusedPartCount < 0)
        {
            throw new ArgumentOutOfRangeException(nameof(reusedPartCount));
        }

        if (downloadedPartCount < 0)
        {
            throw new ArgumentOutOfRangeException(nameof(downloadedPartCount));
        }

        ReusedPartCount = reusedPartCount;
        DownloadedPartCount = downloadedPartCount;
        SelectedRun = selectedRun.ToUniversalTime();
        LatestPublishedRun = latestPublishedRun.ToUniversalTime();
    }

    public int ReusedPartCount { get; }

    public int DownloadedPartCount { get; }

    public DateTimeOffset SelectedRun { get; }

    public DateTimeOffset LatestPublishedRun { get; }

    public bool IsNewerRunAvailable => LatestPublishedRun > SelectedRun;
}

public sealed record ForecastDownloadEstimate(
    ForecastModel Model,
    int ForecastStepCount,
    int PartCount,
    long? EstimatedBytes,
    string Warning);

public interface IForecastDownloadEstimator
{
    ForecastModel Model { get; }

    ForecastDownloadEstimate EstimateDownload(ForecastRequest request);
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
