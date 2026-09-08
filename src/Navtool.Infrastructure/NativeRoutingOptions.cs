using System.Collections.Immutable;
using Navtool.Core;

namespace Navtool.Infrastructure;

public sealed partial class NativeRouterBridge
{
    public ResolvedRoutingOptions GetQualityDefaults(RoutingQuality quality = RoutingQuality.NativeBalanced)
    {
        if (!Enum.IsDefined(quality)) throw new ArgumentOutOfRangeException(nameof(quality));
        var native = NativeRoutingOptionsV8.Empty();
        ThrowIfFailed(NativeMethods.QualityDefaults(ToNativeQuality(quality), ref native), "Resolving native quality defaults");
        return FromNativeOptions(native);
    }

    public ResolvedRoutingOptions ResolveRoutingOptions(RoutingSetup setup, RoutingProfessionalOverrides? overrides = null)
    {
        ArgumentNullException.ThrowIfNull(setup);
        var requested = ResolvedRoutingOptions.FromNativeDefaults(setup, GetQualityDefaults(setup.Quality), overrides);
        var native = ToNativeOptions(requested);
        var effective = NativeRoutingOptionsV8.Empty();
        ThrowIfFailed(NativeMethods.ResolveOptions(ref native, ref effective), "Validating configured routing options");
        return FromNativeOptions(effective) with
        {
            Optimization = FromNativeCommon(effective.Common, requested.Optimization.Environment)
        };
    }

    private static RouteOptimizationOptions FromNativeCommon(NativeRoutingOptions value, RouteEnvironmentOptions? environment = null) =>
        new((RouteSolver)value.Solver,
            new RouteManeuverOptions(TimeSpan.FromSeconds(value.TackPenaltySeconds), TimeSpan.FromSeconds(value.GybePenaltySeconds),
                value.DownwindTrueWindAngleDegrees),
            (RouteHeadingAugmentation)value.HeadingAugmentation, (RouteWindSampling)value.WindSampling,
            TimeSpan.FromMinutes(value.MidpointWindSamplingThresholdMinutes),
            (RoutePolarAngleInterpolation)value.PolarAngleInterpolation,
            (value.Flags & 1) != 0 ? value.MaximumTrueWindSpeedKnots : null,
            (RouteAbovePolarRangePolicy)value.AbovePolarRange, (RoutePruningStrategy)value.PruningStrategy,
            value.PruningSectorDegrees,
            new RouteDestinationFrontOptions(value.DestinationFrontHalfAngleDegrees,
                (RouteDestinationFrontSegmentPolicy)value.DestinationFrontSegmentPolicy,
                checked((int)value.DestinationFrontMinimumSecondarySegmentPoints)),
            new RouteLatticeOptions(checked((int)value.LatticeSubdivisionLevel),
                TimeSpan.FromMinutes(value.LatticeTimeBucketMinutes), checked((int)value.LatticeRefinementLevels),
                value.LatticeCorridorWidthNauticalMiles, checked((int)value.LatticeCorridorWideningRetries),
                checked((int)value.LatticeProgressEveryExpansions), (RouteLatticeSearchAlgorithm)value.LatticeSearchAlgorithm),
            environment);

    private static ResolvedRoutingOptions FromNativeOptions(NativeRoutingOptionsV8 native)
    {
        if (native.IntervalCount > 16 || native.UseRoutingIntervals > 1 || native.StrategicRetention > 1 ||
            native.CaptureIsochrones > 1 || native.Reserved != 0)
            throw new NativeRouteFormatException("Native preset returned invalid interval count or Boolean flags.");
        var search = new RouteSearchSettings(
            TimeStep: TimeSpan.FromMinutes(native.TimeStepMinutes),
            MaximumIntegrationStep: TimeSpan.FromMinutes(native.MaximumIntegrationStepMinutes),
            HeadingStepDegrees: native.HeadingStepDegrees,
            SpatialBucketNauticalMiles: native.SpatialBucketNauticalMiles,
            MaxNodesPerBucket: native.MaxNodesPerBucket,
            WorkerCount: native.WorkerCount,
            MaximumGeneratedCandidates: native.MaximumGeneratedCandidates,
            MaximumRetainedNodes: native.MaximumRetainedNodes,
            ProgressEveryNSteps: native.ProgressEveryNSteps,
            UseRoutingIntervals: native.UseRoutingIntervals != 0,
            StrategicRetention: native.StrategicRetention != 0,
            CaptureIsochrones: native.CaptureIsochrones != 0,
            DestinationFrontMode: native.DestinationFrontMode,
            MinimumBoatSpeedKnots: native.MinimumBoatSpeedKnots,
            Intervals: native.Intervals.Take(checked((int)native.IntervalCount))
                .Select(value => new RouteRoutingInterval(TimeSpan.FromMinutes(value.IntervalMinutes),
                    value.UntilElapsedMinutes == -1 ? null : TimeSpan.FromMinutes(value.UntilElapsedMinutes))).ToImmutableArray());
        var quality = native.Quality switch
        {
            0 => RoutingQuality.NativeFast,
            1 => RoutingQuality.NativeBalanced,
            2 => RoutingQuality.NativeAccurate,
            _ => throw new NativeRouteFormatException("Native quality metadata contains an unsupported preset.")
        };
        return new ResolvedRoutingOptions(quality, FromNativeCommon(native.Common), search,
            native.BoatSpeedFactor, native.ArrivalRadiusNauticalMiles, TimeSpan.FromHours(native.MaximumRouteDurationHours));
    }

    private static NativeRoutingOptionsV8 ToNativeOptions(ResolvedRoutingOptions options)
    {
        var native = NativeRoutingOptionsV8.Empty();
        var search = options.Search;
        native.Quality = ToNativeQuality(options.Quality);
        native.OverrideFlags = (1UL << 14) - 1;
        native.Common = NativeRoutingOptions.From(options.Optimization);
        native.TimeStepMinutes = WholeMinutes(search.TimeStep);
        native.MaximumIntegrationStepMinutes = WholeMinutes(search.MaximumIntegrationStep);
        var duration = options.HardDuration ?? throw new ArgumentException("Native resolved options require a hard duration.");
        if (duration <= TimeSpan.Zero || duration.Ticks % TimeSpan.TicksPerHour != 0)
            throw new ArgumentException("Native hard duration must be a positive whole number of hours.");
        native.MaximumRouteDurationHours = checked((long)duration.TotalHours);
        native.HeadingStepDegrees = search.HeadingStepDegrees;
        native.SpatialBucketNauticalMiles = search.SpatialBucketNauticalMiles;
        native.ArrivalRadiusNauticalMiles = options.ArrivalRadiusNauticalMiles;
        native.MinimumBoatSpeedKnots = search.MinimumBoatSpeedKnots;
        native.BoatSpeedFactor = options.PerformanceFactor;
        native.MaxNodesPerBucket = search.MaxNodesPerBucket;
        native.WorkerCount = search.WorkerCount;
        native.MaximumGeneratedCandidates = search.MaximumGeneratedCandidates;
        native.MaximumRetainedNodes = search.MaximumRetainedNodes;
        native.ProgressEveryNSteps = search.ProgressEveryNSteps;
        native.UseRoutingIntervals = search.UseRoutingIntervals ? 1U : 0U;
        native.StrategicRetention = search.StrategicRetention ? 1U : 0U;
        native.CaptureIsochrones = search.CaptureIsochrones ? 1U : 0U;
        native.DestinationFrontMode = search.DestinationFrontMode;
        if (search.Intervals.Length > 16) throw new ArgumentException("At most sixteen native routing intervals are supported.");
        native.IntervalCount = checked((uint)search.Intervals.Length);
        for (var index = 0; index < search.Intervals.Length; index++)
        {
            native.Intervals[index] = new NativeRoutingIntervalV8
            {
                IntervalMinutes = WholeMinutes(search.Intervals[index].Interval),
                UntilElapsedMinutes = search.Intervals[index].UntilElapsed is { } until ? WholeMinutes(until) : -1
            };
        }
        return native;
    }

    private static long WholeMinutes(TimeSpan value)
    {
        if (value <= TimeSpan.Zero || value.Ticks % TimeSpan.TicksPerMinute != 0)
            throw new ArgumentException("Native integration and routing intervals require positive whole minutes.");
        return checked((long)value.TotalMinutes);
    }

    private static int ToNativeQuality(RoutingQuality quality) => quality switch
    {
        RoutingQuality.NativeFast => 0,
        RoutingQuality.NativeBalanced => 1,
        RoutingQuality.NativeAccurate => 2,
        _ => throw new ArgumentOutOfRangeException(nameof(quality))
    };
}
