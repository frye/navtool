using System.Collections.Immutable;
using System.Diagnostics;
using System.Globalization;
using System.Reflection;
using System.Runtime.ExceptionServices;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Win32.SafeHandles;
using Navtool.Core;

namespace Navtool.Infrastructure;

public sealed record NativeRouterBridgeOptions
{
    public const uint SupportedAbiVersion = 1;

    public int MaximumTextBytes { get; init; } = 64 * 1024 * 1024;

    public int MaximumGridSamples { get; init; } = 1_000_000;

    public int MaximumProgressPoints { get; init; } = 1_000_000;
}

public enum NativeRouterStatus
{
    Ok = 0,
    InvalidArgument = 1,
    AllocationFailure = 2,
    FileIo = 3,
    ForecastDecode = 4,
    UnsupportedForecast = 5,
    IncompleteForecast = 6,
    OutsideForecast = 7,
    NoRoute = 8,
    OutputError = 9,
    InternalError = 10
}

public sealed class NativeRouterException : Exception
{
    public NativeRouterException(NativeRouterStatus status, string operation, string nativeMessage)
        : base($"{operation} failed ({status}): {nativeMessage}")
    {
        Status = status;
        Operation = operation;
        NativeMessage = nativeMessage;
    }

    public NativeRouterStatus Status { get; }

    public string Operation { get; }

    public string NativeMessage { get; }
}

public sealed class NativeBridgeUnavailableException : Exception
{
    public NativeBridgeUnavailableException(string message, Exception innerException)
        : base(message, innerException)
    {
    }
}

public sealed class NativeRouteFormatException : IOException
{
    public NativeRouteFormatException(string message, Exception? innerException = null)
        : base(message, innerException)
    {
    }
}

public sealed record NativeForecastMetadata(
    DateTimeOffset FirstValidAt,
    DateTimeOffset LastValidAt,
    ulong LatitudeCount,
    ulong LongitudeCount,
    bool HasGlobalLongitudeCoverage,
    string Source);

public sealed record ViewportWindSample(
    Coordinate Location,
    DateTimeOffset ValidAt,
    bool IsValid,
    double EastMetersPerSecond,
    double NorthMetersPerSecond)
{
    public WeatherSample? Weather => !IsValid
        ? null
        : new WeatherSample(
            Location,
            ValidAt,
            Math.Sqrt((EastMetersPerSecond * EastMetersPerSecond) +
                      (NorthMetersPerSecond * NorthMetersPerSecond)),
            NormalizeDirection(
                Math.Atan2(-EastMetersPerSecond, -NorthMetersPerSecond) *
                (180d / Math.PI)));

    private static double NormalizeDirection(double value)
    {
        var normalized = value % 360d;
        return normalized < 0 ? normalized + 360d : normalized;
    }
}

public sealed class NativeForecast : IDisposable
{
    internal NativeForecast(NativeForecastSafeHandle handle, NativeForecastMetadata metadata)
    {
        Handle = handle;
        Metadata = metadata;
    }

    internal NativeForecastSafeHandle Handle { get; }

    public NativeForecastMetadata Metadata { get; }

    public bool IsClosed => Handle.IsClosed;

    public void Dispose() => Handle.Dispose();
}

public sealed class NativeRouterBridge
{
    private readonly NativeRouterBridgeOptions _options;
    private int _streamingProgressAvailability;

    public NativeRouterBridge(NativeRouterBridgeOptions? options = null)
    {
        _options = options ?? new NativeRouterBridgeOptions();
        if (_options.MaximumTextBytes <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(options), "Maximum text bytes must be positive.");
        }

        if (_options.MaximumGridSamples <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(options), "Maximum grid samples must be positive.");
        }

        if (_options.MaximumProgressPoints <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(options), "Maximum progress points must be positive.");
        }

        uint actualVersion;
        try
        {
            actualVersion = NativeMethods.AbiVersion();
        }
        catch (DllNotFoundException exception)
        {
            throw new NativeBridgeUnavailableException(
                "The Navtool router bridge could not be found. Set NAVTOOL_ROUTER_BRIDGE_PATH to the native library or its directory.",
                exception);
        }
        catch (EntryPointNotFoundException exception)
        {
            throw new NativeBridgeUnavailableException(
                "The Navtool router bridge does not export the versioned v1 ABI.",
                exception);
        }
        catch (BadImageFormatException exception)
        {
            throw new NativeBridgeUnavailableException(
                "The Navtool router bridge is for an incompatible platform or architecture.",
                exception);
        }

        if (actualVersion != NativeRouterBridgeOptions.SupportedAbiVersion)
        {
            throw new NotSupportedException(
                $"Navtool router bridge ABI {actualVersion} is incompatible; ABI {NativeRouterBridgeOptions.SupportedAbiVersion} is required.");
        }
    }

    public uint AbiVersion => NativeRouterBridgeOptions.SupportedAbiVersion;

    public bool? StreamingProgressAvailable => Volatile.Read(
        ref _streamingProgressAvailability) switch
    {
        > 0 => true,
        < 0 => false,
        _ => null
    };

    public NativeForecast LoadForecast(
        string gribPath,
        GeographicBounds? bounds = null,
        CancellationToken cancellationToken = default)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(gribPath);
        var fullPath = Path.GetFullPath(gribPath);
        if (!File.Exists(fullPath))
        {
            throw new FileNotFoundException("The forecast artifact does not exist.", fullPath);
        }

        cancellationToken.ThrowIfCancellationRequested();
        var status = bounds is { } requestedBounds
            ? NativeMethods.ForecastLoadBounded(
                fullPath,
                requestedBounds.South,
                requestedBounds.West,
                requestedBounds.North,
                requestedBounds.East,
                out var rawHandle)
            : NativeMethods.ForecastLoad(fullPath, out rawHandle);
        NativeForecastSafeHandle? handle =
            rawHandle == IntPtr.Zero ? null : new NativeForecastSafeHandle(rawHandle);
        try
        {
            cancellationToken.ThrowIfCancellationRequested();
            ThrowIfFailed(status, "Loading forecast");
            if (handle is null)
            {
                throw new NativeRouteFormatException("The native bridge reported success but returned a null forecast.");
            }

            var metadata = ReadMetadata(handle);
            cancellationToken.ThrowIfCancellationRequested();
            return new NativeForecast(handle, metadata);
        }
        catch
        {
            handle?.Dispose();
            throw;
        }
    }

    public RouteResult CalculateRoute(
        NativeForecast forecast,
        RouteRequest request,
        ForecastModel model,
        CancellationToken cancellationToken = default) =>
        CalculateRouteCore(forecast, request, model, null, cancellationToken);

    public RouteResult CalculateRoute(
        NativeForecast forecast,
        RouteRequest request,
        ForecastModel model,
        Action<RouteCalculationSnapshot> onProgress,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(onProgress);
        return CalculateRouteCore(
            forecast,
            request,
            model,
            onProgress,
            cancellationToken);
    }

    private RouteResult CalculateRouteCore(
        NativeForecast forecast,
        RouteRequest request,
        ForecastModel model,
        Action<RouteCalculationSnapshot>? onProgress,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(forecast);
        ArgumentNullException.ThrowIfNull(request);
        _ = model.Provider();
        ThrowIfDisposed(forecast);

        cancellationToken.ThrowIfCancellationRequested();
        var departure = request.DepartureTime.ToUnixTimeSeconds();
        var stopwatch = Stopwatch.StartNew();
        ExceptionDispatchInfo? callbackFailure = null;
        NativeMethods.RoutingProgressCallback? callback = null;
        NativeRouterStatus status;
        IntPtr routePointer;
        nuint routeLength;
        if (onProgress is null)
        {
            status = NativeMethods.CalculateRoute(
                forecast.Handle,
                request.Origin.Latitude,
                request.Origin.Longitude,
                request.Destination.Latitude,
                request.Destination.Longitude,
                ref departure,
                out routePointer,
                out routeLength);
        }
        else
        {
            callback = (progressPointer, _) =>
            {
                if (callbackFailure is not null)
                {
                    return;
                }

                try
                {
                    cancellationToken.ThrowIfCancellationRequested();
                    onProgress(CopyProgress(progressPointer));
                }
                catch (Exception exception)
                {
                    callbackFailure = ExceptionDispatchInfo.Capture(exception);
                }
            };
            if (Volatile.Read(ref _streamingProgressAvailability) < 0)
            {
                status = NativeMethods.CalculateRoute(
                    forecast.Handle,
                    request.Origin.Latitude,
                    request.Origin.Longitude,
                    request.Destination.Latitude,
                    request.Destination.Longitude,
                    ref departure,
                    out routePointer,
                    out routeLength);
            }
            else
            {
                try
                {
                    status = NativeMethods.CalculateRouteStreaming(
                        forecast.Handle,
                        request.Origin.Latitude,
                        request.Origin.Longitude,
                        request.Destination.Latitude,
                        request.Destination.Longitude,
                        ref departure,
                        callback,
                        IntPtr.Zero,
                        out routePointer,
                        out routeLength);
                    Volatile.Write(ref _streamingProgressAvailability, 1);
                }
                catch (EntryPointNotFoundException)
                {
                    Volatile.Write(ref _streamingProgressAvailability, -1);
                    status = NativeMethods.CalculateRoute(
                        forecast.Handle,
                        request.Origin.Latitude,
                        request.Origin.Longitude,
                        request.Destination.Latitude,
                        request.Destination.Longitude,
                        ref departure,
                        out routePointer,
                        out routeLength);
                }
            }

            GC.KeepAlive(callback);
        }

        stopwatch.Stop();
        using var routeBuffer = new NativeAllocatedBufferSafeHandle(routePointer);
        callbackFailure?.Throw();
        cancellationToken.ThrowIfCancellationRequested();
        ThrowIfFailed(status, "Calculating route");

        var json = CopyUtf8(routePointer, routeLength, _options.MaximumTextBytes, "route JSON");
        cancellationToken.ThrowIfCancellationRequested();
        return NativeRouteJsonParser.Parse(json, request, model, stopwatch.Elapsed);
    }

    private RouteCalculationSnapshot CopyProgress(IntPtr progressPointer)
    {
        if (progressPointer == IntPtr.Zero)
        {
            throw new NativeRouteFormatException("The native progress callback returned a null snapshot.");
        }

        var progress = Marshal.PtrToStructure<NativeRoutingProgress>(progressPointer);
        var frontier = CopyArray<NativeCoordinate>(
                progress.IsochronePoints,
                progress.IsochronePointCount,
                "isochrone points")
            .Select(point => new Coordinate(point.LatitudeDegrees, point.LongitudeDegrees));
        var provisionalRoute = CopyArray<NativeRoutePoint>(
                progress.ProvisionalRoutePoints,
                progress.ProvisionalRoutePointCount,
                "provisional route points")
            .Select(point => new RoutePoint(
                new Coordinate(
                    point.Position.LatitudeDegrees,
                    point.Position.LongitudeDegrees),
                DateTimeOffset.FromUnixTimeSeconds(point.UtcEpochSeconds),
                point.HeadingDegrees,
                point.BoatSpeedKnots,
                point.TrueWindSpeedKnots,
                point.TrueWindDirectionDegrees,
                point.CumulativeDistanceNauticalMiles));
        var diagnostics = new RouteDiagnostics(
            checked((long)progress.Diagnostics.ExpandedNodes),
            checked((long)progress.Diagnostics.GeneratedCandidates),
            checked((long)progress.Diagnostics.RetainedCandidates),
            checked((int)progress.Diagnostics.TimeSteps));
        return new RouteCalculationSnapshot(
            DateTimeOffset.FromUnixTimeSeconds(progress.IsochroneUtcEpochSeconds),
            frontier,
            provisionalRoute,
            diagnostics);
    }

    private ImmutableArray<T> CopyArray<T>(
        IntPtr pointer,
        ulong count,
        string description)
        where T : struct
    {
        if (count == 0)
        {
            throw new NativeRouteFormatException($"Native progress {description} must not be empty.");
        }

        if (count > (ulong)_options.MaximumProgressPoints || count > int.MaxValue)
        {
            throw new NativeRouteFormatException(
                $"Native progress {description} exceeded the configured limit.");
        }

        if (pointer == IntPtr.Zero)
        {
            throw new NativeRouteFormatException(
                $"Native progress {description} had a null pointer.");
        }

        var length = checked((int)count);
        var itemSize = Marshal.SizeOf<T>();
        var builder = ImmutableArray.CreateBuilder<T>(length);
        for (var index = 0; index < length; index++)
        {
            builder.Add(Marshal.PtrToStructure<T>(
                IntPtr.Add(pointer, checked(index * itemSize))));
        }

        return builder.MoveToImmutable();
    }

    public ImmutableArray<ViewportWindSample> SampleViewport(
        NativeForecast forecast,
        GeographicBounds bounds,
        int latitudeCount,
        int longitudeCount,
        DateTimeOffset validAt,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(forecast);
        ThrowIfDisposed(forecast);
        if (latitudeCount <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(latitudeCount));
        }

        if (longitudeCount <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(longitudeCount));
        }

        var sampleCount = checked(latitudeCount * longitudeCount);
        if (sampleCount > _options.MaximumGridSamples)
        {
            throw new ArgumentOutOfRangeException(
                nameof(latitudeCount),
                $"A viewport is limited to {_options.MaximumGridSamples} samples.");
        }

        cancellationToken.ThrowIfCancellationRequested();
        var nativeSamples = new NativeWindSample[sampleCount];
        var status = NativeMethods.SampleGrid(
            forecast.Handle,
            bounds.South,
            bounds.West,
            bounds.North,
            bounds.East,
            checked((uint)latitudeCount),
            checked((uint)longitudeCount),
            validAt.ToUniversalTime().ToUnixTimeSeconds(),
            nativeSamples,
            checked((nuint)sampleCount));
        cancellationToken.ThrowIfCancellationRequested();
        ThrowIfFailed(status, "Sampling forecast viewport");

        var samples = ImmutableArray.CreateBuilder<ViewportWindSample>(sampleCount);
        var unwrappedEast = bounds.East < bounds.West ? bounds.East + 360d : bounds.East;
        for (var latitudeIndex = 0; latitudeIndex < latitudeCount; latitudeIndex++)
        {
            var latitude = AxisValue(bounds.South, bounds.North, latitudeIndex, latitudeCount);
            for (var longitudeIndex = 0; longitudeIndex < longitudeCount; longitudeIndex++)
            {
                var longitude = AxisValue(bounds.West, unwrappedEast, longitudeIndex, longitudeCount);
                longitude = longitude > 180d ? longitude - 360d : longitude;
                var sample = nativeSamples[(latitudeIndex * longitudeCount) + longitudeIndex];
                if (sample.Valid > 1)
                {
                    throw new NativeRouteFormatException("The native bridge returned an invalid wind validity flag.");
                }

                if (sample.Valid != 0 &&
                    (!double.IsFinite(sample.EastMetersPerSecond) ||
                     !double.IsFinite(sample.NorthMetersPerSecond)))
                {
                    throw new NativeRouteFormatException("The native bridge returned a non-finite valid wind vector.");
                }

                samples.Add(new ViewportWindSample(
                    new Coordinate(latitude, longitude),
                    validAt.ToUniversalTime(),
                    sample.Valid != 0,
                    sample.EastMetersPerSecond,
                    sample.NorthMetersPerSecond));
            }
        }

        return samples.MoveToImmutable();
    }

    private NativeForecastMetadata ReadMetadata(NativeForecastSafeHandle handle)
    {
        var status = NativeMethods.ForecastGetMetadata(
            handle,
            out var native,
            out var sourcePointer,
            out var sourceLength);
        using var sourceBuffer = new NativeAllocatedBufferSafeHandle(sourcePointer);
        ThrowIfFailed(status, "Reading forecast metadata");
        var source = CopyUtf8(sourcePointer, sourceLength, _options.MaximumTextBytes, "forecast source");
        if (native.LastValidEpochSeconds < native.FirstValidEpochSeconds ||
            native.LatitudeCount == 0 ||
            native.LongitudeCount == 0 ||
            native.GlobalLongitudeCoverage > 1)
        {
            throw new NativeRouteFormatException("The native bridge returned inconsistent forecast metadata.");
        }

        try
        {
            return new NativeForecastMetadata(
                DateTimeOffset.FromUnixTimeSeconds(native.FirstValidEpochSeconds),
                DateTimeOffset.FromUnixTimeSeconds(native.LastValidEpochSeconds),
                native.LatitudeCount,
                native.LongitudeCount,
                native.GlobalLongitudeCoverage != 0,
                source);
        }
        catch (ArgumentOutOfRangeException exception)
        {
            throw new NativeRouteFormatException("The native forecast metadata contains an invalid timestamp.", exception);
        }
    }

    private static void ThrowIfDisposed(NativeForecast forecast)
    {
        if (forecast.Handle.IsClosed || forecast.Handle.IsInvalid)
        {
            throw new ObjectDisposedException(nameof(NativeForecast));
        }
    }

    private static void ThrowIfFailed(NativeRouterStatus status, string operation)
    {
        if (status != NativeRouterStatus.Ok)
        {
            throw new NativeRouterException(status, operation, NativeMethods.GetLastError());
        }
    }

    private static string CopyUtf8(IntPtr pointer, nuint length, int maximumBytes, string description)
    {
        if (pointer == IntPtr.Zero)
        {
            if (length == 0)
            {
                return string.Empty;
            }

            throw new NativeRouteFormatException($"The native bridge returned a null {description} pointer with a nonzero length.");
        }

        if (length > (nuint)maximumBytes || length > int.MaxValue)
        {
            throw new NativeRouteFormatException($"The native bridge returned {description} larger than the configured limit.");
        }

        var bytes = new byte[(int)length];
        Marshal.Copy(pointer, bytes, 0, bytes.Length);
        try
        {
            return new UTF8Encoding(false, true).GetString(bytes);
        }
        catch (DecoderFallbackException exception)
        {
            throw new NativeRouteFormatException($"The native bridge returned invalid UTF-8 in {description}.", exception);
        }
    }

    private static double AxisValue(double first, double last, int index, int count) =>
        count == 1 ? (first + last) / 2d : first + ((last - first) * index / (count - 1d));
}

public sealed class NativeRouteEngine : IRouteEngine
{
    private readonly NativeRouterBridge _bridge;
    private readonly ILogger<NativeRouteEngine> _logger;

    public NativeRouteEngine(
        NativeRouterBridge? bridge = null,
        ILogger<NativeRouteEngine>? logger = null)
    {
        _bridge = bridge ?? new NativeRouterBridge();
        _logger = logger ?? NullLogger<NativeRouteEngine>.Instance;
    }

    public ValueTask<RouteResult> CalculateAsync(
        RouteRequest request,
        ForecastAcquisition forecast,
        IProgress<RouteCalculationProgress>? progress,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(request);
        ArgumentNullException.ThrowIfNull(forecast);
        cancellationToken.ThrowIfCancellationRequested();
        progress?.Report(new RouteCalculationProgress(0, "Loading forecast"));

        try
        {
            var loadBounds = GetLoadBounds(forecast);
            _logger.LogInformation(
                "Loading native forecast artifact {ArtifactPath} with effective bounds {Bounds}",
                forecast.Artifact.Path,
                loadBounds);
            using var loaded = _bridge.LoadForecast(
                forecast.Artifact.Path,
                loadBounds,
                cancellationToken: cancellationToken);
            cancellationToken.ThrowIfCancellationRequested();
            progress?.Report(new RouteCalculationProgress(0.2, "Optimizing route"));
            var result = progress is null
                ? _bridge.CalculateRoute(
                    loaded,
                    request,
                    forecast.Request.Model,
                    cancellationToken)
                : _bridge.CalculateRoute(
                    loaded,
                    request,
                    forecast.Request.Model,
                    snapshot =>
                    {
                        var requestedDuration =
                            request.LatestArrivalTime - request.DepartureTime;
                        var elapsed =
                            snapshot.FrontierTime - request.DepartureTime;
                        var fraction = requestedDuration <= TimeSpan.Zero
                            ? 0
                            : Math.Clamp(
                                elapsed.TotalSeconds /
                                requestedDuration.TotalSeconds,
                                0,
                                1);
                        progress.Report(new RouteCalculationProgress(
                            0.2 + (fraction * 0.79),
                            $"Step {snapshot.Diagnostics.TimeSteps:N0} · " +
                            $"{snapshot.Diagnostics.RetainedCandidates:N0} retained",
                            snapshot));
                    },
                    cancellationToken);
            cancellationToken.ThrowIfCancellationRequested();
            progress?.Report(new RouteCalculationProgress(1, "Route complete"));
            _logger.LogInformation(
                "Completed route {RouteId} using {Model} with {PointCount} points",
                request.RouteId,
                forecast.Request.Model,
                result.Points.Length);
            return ValueTask.FromResult(result);
        }
        catch (Exception exception) when (
            exception is not OperationCanceledException ||
            !cancellationToken.IsCancellationRequested)
        {
            _logger.LogError(
                exception,
                "Native route calculation failed for route {RouteId} and artifact {ArtifactPath}",
                request.RouteId,
                forecast.Artifact.Path);
            throw;
        }
    }

    public ValueTask<ImmutableArray<ViewportWindSample>> SampleViewportAsync(
        ForecastAcquisition forecast,
        GeographicBounds bounds,
        int latitudeCount,
        int longitudeCount,
        DateTimeOffset validAt,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(forecast);
        cancellationToken.ThrowIfCancellationRequested();
        try
        {
            using var loaded = _bridge.LoadForecast(
                forecast.Artifact.Path,
                GetLoadBounds(forecast),
                cancellationToken: cancellationToken);
            var samples = _bridge.SampleViewport(
                loaded,
                bounds,
                latitudeCount,
                longitudeCount,
                validAt,
                cancellationToken);
            cancellationToken.ThrowIfCancellationRequested();
            return ValueTask.FromResult(samples);
        }
        catch (Exception exception) when (
            exception is not OperationCanceledException ||
            !cancellationToken.IsCancellationRequested)
        {
            _logger.LogError(
                exception,
                "Native weather sampling failed for artifact {ArtifactPath} at {ValidAt}",
                forecast.Artifact.Path,
                validAt);
            throw;
        }
    }

    private static GeographicBounds GetLoadBounds(ForecastAcquisition forecast) =>
        forecast.Request.Model == ForecastModel.NoaaGfs
            ? NoaaGfsForecastProvider.AlignBoundsToGrid(forecast.Request.Bounds)
            : forecast.Request.Bounds;
}

internal static class NativeRouteJsonParser
{
    public static RouteResult Parse(
        string json,
        RouteRequest request,
        ForecastModel model,
        TimeSpan calculationDuration)
    {
        try
        {
            using var document = JsonDocument.Parse(
                json,
                new JsonDocumentOptions { MaxDepth = 32 });
            var root = document.RootElement;
            RequireKind(root, JsonValueKind.Object, "root");
            var diagnosticsElement = Required(root, "diagnostics", JsonValueKind.Object);
            var diagnostics = new RouteDiagnostics(
                RequiredInt64(diagnosticsElement, "expandedNodes"),
                RequiredInt64(diagnosticsElement, "generatedCandidates"),
                RequiredInt64(diagnosticsElement, "retainedCandidates"),
                RequiredInt32(diagnosticsElement, "timeSteps"),
                calculationDuration);

            var pointsElement = Required(root, "points", JsonValueKind.Array);
            var points = ImmutableArray.CreateBuilder<RoutePoint>();
            foreach (var element in pointsElement.EnumerateArray())
            {
                RequireKind(element, JsonValueKind.Object, "point");
                var position = Required(element, "position", JsonValueKind.Object);
                points.Add(new RoutePoint(
                    new Coordinate(
                        RequiredDouble(position, "latitude"),
                        RequiredDouble(position, "longitude")),
                    RequiredTimestamp(element, "time"),
                    RequiredDouble(element, "headingDegrees"),
                    RequiredDouble(element, "boatSpeedKnots"),
                    RequiredDouble(element, "trueWindSpeedKnots"),
                    RequiredDouble(element, "trueWindDirectionDegrees"),
                    RequiredDouble(element, "cumulativeDistanceNauticalMiles")));
            }

            return new RouteResult(request, model, points, diagnostics);
        }
        catch (NativeRouteFormatException)
        {
            throw;
        }
        catch (Exception exception) when (
            exception is JsonException or
            ArgumentException or
            InvalidOperationException or
            OverflowException)
        {
            throw new NativeRouteFormatException("The native route JSON did not match the v1 contract.", exception);
        }
    }

    private static JsonElement Required(JsonElement parent, string name, JsonValueKind kind)
    {
        if (!parent.TryGetProperty(name, out var value))
        {
            throw new NativeRouteFormatException($"Native route JSON is missing '{name}'.");
        }

        RequireKind(value, kind, name);
        return value;
    }

    private static void RequireKind(JsonElement element, JsonValueKind kind, string name)
    {
        if (element.ValueKind != kind)
        {
            throw new NativeRouteFormatException($"Native route JSON field '{name}' must be {kind}.");
        }
    }

    private static long RequiredInt64(JsonElement parent, string name)
    {
        var value = Required(parent, name, JsonValueKind.Number);
        if (!value.TryGetInt64(out var result) || result < 0)
        {
            throw new NativeRouteFormatException($"Native route JSON field '{name}' must be a nonnegative 64-bit integer.");
        }

        return result;
    }

    private static int RequiredInt32(JsonElement parent, string name)
    {
        var value = RequiredInt64(parent, name);
        return checked((int)value);
    }

    private static double RequiredDouble(JsonElement parent, string name)
    {
        var value = Required(parent, name, JsonValueKind.Number);
        if (!value.TryGetDouble(out var result) || !double.IsFinite(result))
        {
            throw new NativeRouteFormatException($"Native route JSON field '{name}' must be finite.");
        }

        return result;
    }

    private static DateTimeOffset RequiredTimestamp(JsonElement parent, string name)
    {
        var value = Required(parent, name, JsonValueKind.String).GetString();
        if (!DateTimeOffset.TryParse(
                value,
                CultureInfo.InvariantCulture,
                DateTimeStyles.AssumeUniversal | DateTimeStyles.AdjustToUniversal,
                out var result))
        {
            throw new NativeRouteFormatException($"Native route JSON field '{name}' is not a valid UTC timestamp.");
        }

        return result;
    }
}

internal sealed class NativeForecastSafeHandle : SafeHandleZeroOrMinusOneIsInvalid
{
    public NativeForecastSafeHandle()
        : base(true)
    {
    }

    internal NativeForecastSafeHandle(IntPtr value)
        : base(true)
    {
        SetHandle(value);
    }

    protected override bool ReleaseHandle()
    {
        var value = handle;
        var status = NativeMethods.ForecastDestroy(ref value);
        SetHandle(IntPtr.Zero);
        return status == NativeRouterStatus.Ok;
    }
}

internal sealed class NativeAllocatedBufferSafeHandle : SafeHandleZeroOrMinusOneIsInvalid
{
    public NativeAllocatedBufferSafeHandle()
        : base(true)
    {
    }

    internal NativeAllocatedBufferSafeHandle(IntPtr value)
        : base(true)
    {
        SetHandle(value);
    }

    protected override bool ReleaseHandle()
    {
        NativeMethods.Free(handle);
        SetHandle(IntPtr.Zero);
        return true;
    }
}

[StructLayout(LayoutKind.Sequential)]
internal struct NativeForecastMetadataStruct
{
    public long FirstValidEpochSeconds;
    public long LastValidEpochSeconds;
    public ulong LatitudeCount;
    public ulong LongitudeCount;
    public byte GlobalLongitudeCoverage;
}

[StructLayout(LayoutKind.Sequential)]
internal struct NativeWindSample
{
    public double EastMetersPerSecond;
    public double NorthMetersPerSecond;
    public byte Valid;
}

[StructLayout(LayoutKind.Sequential)]
internal struct NativeCoordinate
{
    public double LatitudeDegrees;
    public double LongitudeDegrees;
}

[StructLayout(LayoutKind.Sequential)]
internal struct NativeRoutePoint
{
    public NativeCoordinate Position;
    public long UtcEpochSeconds;
    public double HeadingDegrees;
    public double BoatSpeedKnots;
    public double TrueWindSpeedKnots;
    public double TrueWindDirectionDegrees;
    public double CumulativeDistanceNauticalMiles;
}

[StructLayout(LayoutKind.Sequential)]
internal struct NativeRoutingDiagnostics
{
    public ulong ExpandedNodes;
    public ulong GeneratedCandidates;
    public ulong RetainedCandidates;
    public ulong TimeSteps;
}

[StructLayout(LayoutKind.Sequential)]
internal struct NativeRoutingProgress
{
    public long IsochroneUtcEpochSeconds;
    public IntPtr IsochronePoints;
    public ulong IsochronePointCount;
    public IntPtr ProvisionalRoutePoints;
    public ulong ProvisionalRoutePointCount;
    public NativeRoutingDiagnostics Diagnostics;
}

internal static class NativeMethods
{
    private const string LibraryName = "navtool_router_bridge";
    private const int MaximumErrorBytes = 64 * 1024;

    static NativeMethods()
    {
        NativeLibrary.SetDllImportResolver(typeof(NativeMethods).Assembly, ResolveLibrary);
    }

    [DllImport(LibraryName, EntryPoint = "navtool_router_bridge_abi_version_v1", CallingConvention = CallingConvention.Cdecl)]
    internal static extern uint AbiVersion();

    [DllImport(LibraryName, EntryPoint = "navtool_router_last_error_v1", CallingConvention = CallingConvention.Cdecl)]
    private static extern IntPtr LastError();

    [DllImport(LibraryName, EntryPoint = "navtool_router_forecast_load_v1", CallingConvention = CallingConvention.Cdecl)]
    internal static extern NativeRouterStatus ForecastLoad(
        [MarshalAs(UnmanagedType.LPUTF8Str)] string gribPath,
        out IntPtr forecast);

    [DllImport(LibraryName, EntryPoint = "navtool_router_forecast_load_bounded_v1", CallingConvention = CallingConvention.Cdecl)]
    internal static extern NativeRouterStatus ForecastLoadBounded(
        [MarshalAs(UnmanagedType.LPUTF8Str)] string gribPath,
        double south,
        double west,
        double north,
        double east,
        out IntPtr forecast);

    [DllImport(LibraryName, EntryPoint = "navtool_router_forecast_destroy_v1", CallingConvention = CallingConvention.Cdecl)]
    internal static extern NativeRouterStatus ForecastDestroy(ref IntPtr forecast);

    [DllImport(LibraryName, EntryPoint = "navtool_router_forecast_get_metadata_v1", CallingConvention = CallingConvention.Cdecl)]
    internal static extern NativeRouterStatus ForecastGetMetadata(
        NativeForecastSafeHandle forecast,
        out NativeForecastMetadataStruct metadata,
        out IntPtr source,
        out nuint sourceLength);

    [DllImport(LibraryName, EntryPoint = "navtool_router_calculate_route_v1", CallingConvention = CallingConvention.Cdecl)]
    internal static extern NativeRouterStatus CalculateRoute(
        NativeForecastSafeHandle forecast,
        double startLatitude,
        double startLongitude,
        double destinationLatitude,
        double destinationLongitude,
        ref long departureEpochSeconds,
        out IntPtr routeJson,
        out nuint routeJsonLength);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    internal delegate void RoutingProgressCallback(
        IntPtr progress,
        IntPtr userData);

    [DllImport(LibraryName, EntryPoint = "navtool_router_calculate_route_streaming_v1", CallingConvention = CallingConvention.Cdecl)]
    internal static extern NativeRouterStatus CalculateRouteStreaming(
        NativeForecastSafeHandle forecast,
        double startLatitude,
        double startLongitude,
        double destinationLatitude,
        double destinationLongitude,
        ref long departureEpochSeconds,
        RoutingProgressCallback onProgress,
        IntPtr progressUserData,
        out IntPtr routeJson,
        out nuint routeJsonLength);

    [DllImport(LibraryName, EntryPoint = "navtool_router_sample_grid_v1", CallingConvention = CallingConvention.Cdecl)]
    internal static extern NativeRouterStatus SampleGrid(
        NativeForecastSafeHandle forecast,
        double south,
        double west,
        double north,
        double east,
        uint latitudeCount,
        uint longitudeCount,
        long utcEpochSeconds,
        [Out] NativeWindSample[] samples,
        nuint sampleCount);

    [DllImport(LibraryName, EntryPoint = "navtool_router_bridge_free_v1", CallingConvention = CallingConvention.Cdecl)]
    internal static extern void Free(IntPtr memory);

    internal static string GetLastError()
    {
        var pointer = LastError();
        if (pointer == IntPtr.Zero)
        {
            return "The native bridge did not provide an error message.";
        }

        var length = 0;
        while (length < MaximumErrorBytes && Marshal.ReadByte(pointer, length) != 0)
        {
            length++;
        }

        if (length == MaximumErrorBytes)
        {
            return "The native bridge returned an unterminated error message.";
        }

        var bytes = new byte[length];
        Marshal.Copy(pointer, bytes, 0, length);
        return Encoding.UTF8.GetString(bytes);
    }

    private static IntPtr ResolveLibrary(
        string libraryName,
        Assembly assembly,
        DllImportSearchPath? searchPath)
    {
        if (!string.Equals(libraryName, LibraryName, StringComparison.Ordinal))
        {
            return IntPtr.Zero;
        }

        foreach (var candidate in NativeLibraryCandidates())
        {
            if (NativeLibrary.TryLoad(candidate, out var handle))
            {
                return handle;
            }
        }

        return IntPtr.Zero;
    }

    private static IEnumerable<string> NativeLibraryCandidates()
    {
        var names = OperatingSystem.IsWindows()
            ? new[] { "navtool_router_bridge.dll" }
            : OperatingSystem.IsMacOS()
                ? new[]
                {
                    "libnavtool_router_bridge.1.dylib",
                    "libnavtool_router_bridge.1.0.0.dylib",
                    "libnavtool_router_bridge.dylib"
                }
                : new[]
                {
                    "libnavtool_router_bridge.so.1",
                    "libnavtool_router_bridge.so.1.0.0",
                    "libnavtool_router_bridge.so"
                };

        var configured = Environment.GetEnvironmentVariable("NAVTOOL_ROUTER_BRIDGE_PATH");
        if (!string.IsNullOrWhiteSpace(configured))
        {
            if (File.Exists(configured))
            {
                yield return Path.GetFullPath(configured);
            }
            else
            {
                foreach (var name in names)
                {
                    yield return Path.Combine(Path.GetFullPath(configured), name);
                }
            }
        }

        var directories = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            AppContext.BaseDirectory,
            Path.Combine(AppContext.BaseDirectory, "native"),
            Path.Combine(AppContext.BaseDirectory, "runtimes", RuntimeInformation.RuntimeIdentifier, "native"),
            Directory.GetCurrentDirectory()
        };

        var ancestor = new DirectoryInfo(AppContext.BaseDirectory);
        for (var depth = 0; depth < 8 && ancestor is not null; depth++, ancestor = ancestor.Parent)
        {
            directories.Add(Path.Combine(ancestor.FullName, "native", "Navtool.RouterBridge", "build"));
        }

        foreach (var directory in directories)
        {
            foreach (var name in names)
            {
                yield return Path.Combine(directory, name);
            }
        }

        foreach (var name in names)
        {
            yield return name;
        }
    }
}
