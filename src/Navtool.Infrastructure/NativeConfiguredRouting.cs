using System.Diagnostics;
using System.Runtime.ExceptionServices;
using System.Runtime.InteropServices;
using Navtool.Core;

namespace Navtool.Infrastructure;

public sealed record NativeTimedHeadingAction(double HeadingDegrees, TimeSpan Duration);

public sealed partial class NativeRouterBridge
{
    public RouteResult CalculateRoute(
        NativeForecast forecast,
        NativePolar polar,
        RouteRequest request,
        ForecastModel model,
        ResolvedRoutingOptions options,
        Action<RouteCalculationSnapshot>? onProgress = null,
        Func<Coordinate, Coordinate, bool>? isSegmentEligible = null,
        CancellationToken cancellationToken = default,
        NativeRegionalLand? land = null) =>
        ExecuteRoute(forecast, polar, request, model, options, onProgress, isSegmentEligible, cancellationToken, land, null);

    public RouteResult EvaluateTimedActions(NativeForecast forecast, NativePolar polar, RouteRequest request,
        ForecastModel model, ResolvedRoutingOptions options, IReadOnlyList<NativeTimedHeadingAction> actions,
        Func<Coordinate, Coordinate, bool>? isSegmentEligible = null, NativeRegionalLand? land = null,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(actions);
        if ((_capabilities & NativeRouterCapabilities.ActionReplay) == 0)
            throw new NotSupportedException("The native bridge does not support explicit timed-heading replay.");
        if (actions.Count is < 1 or > 10_000)
            throw new ArgumentOutOfRangeException(nameof(actions));
        var copy = actions.Select(action =>
        {
            if (!double.IsFinite(action.HeadingDegrees) || action.HeadingDegrees is < 0 or >= 360 ||
                action.Duration <= TimeSpan.Zero || action.Duration.Ticks % TimeSpan.TicksPerSecond != 0)
                throw new ArgumentException("Supplied actions need canonical headings and positive whole-second durations.", nameof(actions));
            return new NativeActionV8 { HeadingDegrees = action.HeadingDegrees, DurationSeconds = checked((long)action.Duration.TotalSeconds) };
        }).ToArray();
        return ExecuteRoute(forecast, polar, request, model, options, null, isSegmentEligible, cancellationToken, land, copy);
    }

    private RouteResult ExecuteRoute(NativeForecast forecast, NativePolar polar, RouteRequest request,
        ForecastModel model, ResolvedRoutingOptions options, Action<RouteCalculationSnapshot>? onProgress,
        Func<Coordinate, Coordinate, bool>? isSegmentEligible, CancellationToken cancellationToken,
        NativeRegionalLand? land, NativeActionV8[]? actions)
    {
        ArgumentNullException.ThrowIfNull(forecast);
        ArgumentNullException.ThrowIfNull(polar);
        ArgumentNullException.ThrowIfNull(request);
        ArgumentNullException.ThrowIfNull(options);
        ThrowIfDisposed(forecast);
        ObjectDisposedException.ThrowIf(polar.Handle.IsClosed || polar.Handle.IsInvalid, polar);
        if (land is not null)
            ObjectDisposedException.ThrowIf(land.Handle.IsClosed || land.Handle.IsInvalid, land);
        _ = model.Provider();
        cancellationToken.ThrowIfCancellationRequested();
        if (options.Optimization.Environment is { } configuredEnvironment &&
            DescribeMissingCapability(_capabilities, configuredEnvironment) is { } missing)
            throw new NotSupportedException($"The bridge lacks configured {missing}.");
        var nativeOptions = ToNativeOptions(options);
        using var optionScope = new NativeStructScope<NativeRoutingOptionsV8>(nativeOptions);
        using var environmentScope = options.Optimization.Environment is { } environment
            ? NativeEnvironmentScope.Create(environment) : null;
        using var environmentPointer = environmentScope is null ? null :
            new NativeStructScope<NativeEnvironment>(environmentScope.Environment);
        var forecastHeld = false;
        var polarHeld = false;
        var landHeld = false;
        try
        {
            forecast.Handle.DangerousAddRef(ref forecastHeld);
            polar.Handle.DangerousAddRef(ref polarHeld);
            land?.Handle.DangerousAddRef(ref landHeld);
            var nativeRequest = new NativeRoutingRequestV8
            {
                StructSize = checked((uint)Marshal.SizeOf<NativeRoutingRequestV8>()),
                Flags = 1,
                Forecast = forecast.Handle.DangerousGetHandle(),
                Polar = polar.Handle.DangerousGetHandle(),
                Start = CoordinateToNative(request.Origin),
                Destination = CoordinateToNative(request.Destination),
                DepartureEpochSeconds = request.DepartureTime.ToUnixTimeSeconds(),
                Options = optionScope.Pointer,
                Environment = environmentPointer?.Pointer ?? IntPtr.Zero,
                Land = land?.Handle.DangerousGetHandle() ?? IntPtr.Zero,
                LandClearanceNauticalMiles = land?.Options.ClearanceNauticalMiles ?? 0,
                LandMaximumSubdivisionDepth = checked((ulong)(land?.Options.MaximumSubdivisionDepth ?? 0)),
                LandMissingDataPolicy = land is null ? 0 : (int)land.Options.MissingDataPolicy
            };
            ExceptionDispatchInfo? callbackFailure = null;
            NativeMethods.RoutingProgressCallback progress = (pointer, _) =>
            {
                if (callbackFailure is not null) return 0;
                try
                {
                    cancellationToken.ThrowIfCancellationRequested();
                    var snapshot = CopyProgress(pointer);
                    onProgress?.Invoke(snapshot);
                    cancellationToken.ThrowIfCancellationRequested();
                    return 1;
                }
                catch (Exception exception)
                {
                    Interlocked.CompareExchange(ref callbackFailure, ExceptionDispatchInfo.Capture(exception), null);
                    return 0;
                }
            };
            NativeMethods.SegmentEligibilityCallback? eligibility = isSegmentEligible is null ? null :
                (ref NativeCoordinate parent, ref NativeCoordinate candidate, IntPtr _) =>
                {
                    if (callbackFailure is not null) return 0;
                    try
                    {
                        cancellationToken.ThrowIfCancellationRequested();
                        return isSegmentEligible(new Coordinate(parent.LatitudeDegrees, parent.LongitudeDegrees),
                            new Coordinate(candidate.LatitudeDegrees, candidate.LongitudeDegrees)) ? (byte)1 : (byte)0;
                    }
                    catch (Exception exception)
                    {
                        Interlocked.CompareExchange(ref callbackFailure, ExceptionDispatchInfo.Capture(exception), null);
                        return 0;
                    }
                };
            var watch = Stopwatch.StartNew();
            var status = actions is null
                ? NativeMethods.CalculateV8(ref nativeRequest, progress, IntPtr.Zero, eligibility, IntPtr.Zero,
                    out var json, out var length)
                : NativeMethods.EvaluateActions(ref nativeRequest, actions, checked((ulong)actions.Length), eligibility,
                    IntPtr.Zero, out json, out length);
            GC.KeepAlive(progress);
            GC.KeepAlive(eligibility);
            Volatile.Write(ref _streamingProgressAvailability, 1);
            using var buffer = new NativeAllocatedBufferSafeHandle(json);
            callbackFailure?.Throw();
            cancellationToken.ThrowIfCancellationRequested();
            if (status != NativeRouterStatus.Ok)
                throw new NativeRouterException(status, "Calculating configured route", NativeMethods.GetLastError(),
                    DescribeFailure(status, request, forecast.Metadata));
            var text = CopyUtf8(json, length, _options.MaximumTextBytes, "route JSON");
            NativeRouteJsonParser.RequireV2(text);
            var result = NativeRouteJsonParser.Parse(text, request, model, watch.Elapsed, options.Optimization.Solver);
            NativeRouteJsonParser.ValidateEffectiveAudit(text, options, forecast.Metadata);
            EnsureWithinForecastHorizon(result, forecast.Metadata);
            var coverage = new ForecastCoverage(
                forecast.Metadata.EffectiveBounds ?? throw new NativeRouteFormatException("ABI 8 forecast has no effective geographic coverage."),
                forecast.Metadata.ValidTimes, forecast.Metadata.MaximumInterpolationGap);
            return new RouteResult(result.Request, result.Model, result.Points, result.Diagnostics, result.Completion,
                result.LandAvoidance, result.Solver, result.LatticeDiagnostics, result.Environment,
                result.EnvironmentDiagnostics, result.RunAudit, result.NativeAudit! with { ForecastCoverage = coverage });
        }
        finally
        {
            if (landHeld) land!.Handle.DangerousRelease();
            if (polarHeld) polar.Handle.DangerousRelease();
            if (forecastHeld) forecast.Handle.DangerousRelease();
        }
    }

    private static NativeCoordinate CoordinateToNative(Coordinate location) => new()
    {
        LatitudeDegrees = location.Latitude, LongitudeDegrees = location.Longitude
    };

    private static RoutePoint CopyAuditedPoint(NativeRoutePointV8 value)
    {
        if ((value.Flags & ~7UL) != 0 || ((value.Flags & 6) != 0 && (value.Flags & 1) == 0))
            throw new NativeRouteFormatException("Native progress point contains invalid environment flags.");
        var current = (value.Flags & 2) != 0;
        var wave = (value.Flags & 4) != 0;
        var environment = (value.Flags & 1) == 0 ? null : new RoutePointEnvironment(
            value.SpeedOverGroundKnots, value.CourseOverGroundDegrees, value.FlatWaterSpeedKnots,
            current ? value.CurrentEastKnots : null, current ? value.CurrentNorthKnots : null,
            wave ? value.SignificantWaveHeightMetres : null, wave ? value.WavePeriodSeconds : null,
            wave ? value.RelativeWaveAngleDegrees : null,
            current ? value.PolarWindSpeedKnots : null, current ? value.PolarWindDirectionDegrees : null);
        var point = value.Point;
        return new RoutePoint(new Coordinate(point.Position.LatitudeDegrees, point.Position.LongitudeDegrees),
            DateTimeOffset.FromUnixTimeSeconds(point.UtcEpochSeconds), point.HeadingDegrees, point.BoatSpeedKnots,
            point.TrueWindSpeedKnots, point.TrueWindDirectionDegrees, point.CumulativeDistanceNauticalMiles, environment);
    }
}
