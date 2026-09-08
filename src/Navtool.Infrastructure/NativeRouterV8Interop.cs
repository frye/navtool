using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

namespace Navtool.Infrastructure;

[StructLayout(LayoutKind.Sequential)]
internal struct NativeRoutingIntervalV8
{
    public long IntervalMinutes;
    public long UntilElapsedMinutes;
}

[StructLayout(LayoutKind.Sequential)]
internal struct NativeRoutingOptionsV8
{
    public uint StructSize;
    public int Quality;
    public ulong OverrideFlags;
    public NativeRoutingOptions Common;
    public long TimeStepMinutes;
    public long MaximumRouteDurationHours;
    public long MaximumIntegrationStepMinutes;
    public double HeadingStepDegrees;
    public double SpatialBucketNauticalMiles;
    public double ArrivalRadiusNauticalMiles;
    public double MinimumBoatSpeedKnots;
    public double BoatSpeedFactor;
    public ulong MaxNodesPerBucket;
    public ulong WorkerCount;
    public ulong MaximumGeneratedCandidates;
    public ulong MaximumRetainedNodes;
    public ulong ProgressEveryNSteps;
    public uint UseRoutingIntervals;
    public uint StrategicRetention;
    public uint CaptureIsochrones;
    public int DestinationFrontMode;
    public uint IntervalCount;
    public uint Reserved;
    [MarshalAs(UnmanagedType.ByValArray, SizeConst = 16)]
    public NativeRoutingIntervalV8[] Intervals;

    public static NativeRoutingOptionsV8 Empty() => new()
    {
        StructSize = checked((uint)Marshal.SizeOf<NativeRoutingOptionsV8>()),
        Intervals = new NativeRoutingIntervalV8[16]
    };
}

[StructLayout(LayoutKind.Sequential)]
internal struct NativePolarOptionsV8
{
    public uint StructSize;
    public int Format;
    public ulong Flags;
    public double MinimumSailingAngleDegrees;
}

[StructLayout(LayoutKind.Sequential)]
internal struct NativeForecastOptionsV8
{
    public uint StructSize;
    public uint Reserved;
    public ulong Flags;
    public double South, West, North, East;
    public long MaximumInterpolationGapSeconds;
}

[StructLayout(LayoutKind.Sequential)]
internal struct NativeForecastMetadataV8
{
    public uint StructSize;
    public uint Flags;
    public long InitializationEpochSeconds, FirstValidEpochSeconds, LastValidEpochSeconds;
    public long MinimumTimeSpacingSeconds, MaximumTimeSpacingSeconds;
    public ulong LatitudeCount, LongitudeCount;
    public double South, West, North, East;
    public ulong ValidTimeCount;
}

[StructLayout(LayoutKind.Sequential)]
internal struct NativeLandOptionsV8
{
    public uint StructSize, Reserved;
    public double South, West, North, East;
    public double ResolutionNauticalMiles, DistanceCapNauticalMiles;
    public ulong MaximumGridNodes, MaximumSourcePoints, MaximumGeometryTests;
}

[StructLayout(LayoutKind.Sequential)]
internal struct NativeLandEstimateV8
{
    public uint StructSize, Reserved;
    public ulong LatitudeCount, LongitudeCount, GridNodes;
    public double LatitudeStepDegrees, LongitudeStepDegrees, InterpolationErrorNauticalMiles;
    public double HaloSouth, HaloNorth, HaloWest, HaloEast;
}

[StructLayout(LayoutKind.Sequential)]
internal struct NativeRoutingRequestV8
{
    public uint StructSize, Flags;
    public IntPtr Forecast, Polar;
    public NativeCoordinate Start, Destination;
    public long DepartureEpochSeconds;
    public IntPtr Options, Environment, Land;
    public double LandClearanceNauticalMiles;
    public ulong LandMaximumSubdivisionDepth;
    public int LandMissingDataPolicy;
    public uint Reserved;
}

[StructLayout(LayoutKind.Sequential)]
internal struct NativeRoutePointV8
{
    public NativeRoutePoint Point;
    public ulong Flags;
    public double SpeedOverGroundKnots, CourseOverGroundDegrees;
    public double CurrentEastKnots, CurrentNorthKnots, FlatWaterSpeedKnots;
    public double SignificantWaveHeightMetres, WavePeriodSeconds, RelativeWaveAngleDegrees;
    public double PolarWindSpeedKnots, PolarWindDirectionDegrees;
}

[StructLayout(LayoutKind.Sequential)]
internal struct NativeRoutingProgressV8
{
    public uint StructSize, Reserved;
    public NativeRoutingProgress Progress;
    public IntPtr AuditedRoutePoints;
    public ulong AuditedRoutePointCount, EligibilityEvaluations, PrunedCandidates, FutureProbeMisses;
}

[StructLayout(LayoutKind.Sequential)]
internal struct NativeActionV8
{
    public double HeadingDegrees;
    public long DurationSeconds;
}

internal sealed class NativePolarSafeHandle : SafeHandleZeroOrMinusOneIsInvalid
{
    internal NativePolarSafeHandle(IntPtr value) : base(true) => SetHandle(value);
    protected override bool ReleaseHandle()
    {
        var value = handle;
        var status = NativeMethods.PolarDestroy(ref value);
        SetHandle(IntPtr.Zero);
        return status == NativeRouterStatus.Ok;
    }
}

internal sealed class NativeLandSafeHandle : SafeHandleZeroOrMinusOneIsInvalid
{
    internal NativeLandSafeHandle(IntPtr value) : base(true) => SetHandle(value);
    protected override bool ReleaseHandle()
    {
        var value = handle;
        var status = NativeMethods.LandDestroy(ref value);
        SetHandle(IntPtr.Zero);
        return status == NativeRouterStatus.Ok;
    }
}

internal sealed class NativeStructScope<T> : IDisposable where T : struct
{
    public NativeStructScope(T value)
    {
        Pointer = Marshal.AllocHGlobal(Marshal.SizeOf<T>());
        try { Marshal.StructureToPtr(value, Pointer, false); }
        catch { Marshal.FreeHGlobal(Pointer); throw; }
    }
    public IntPtr Pointer { get; }
    public void Dispose()
    {
        Marshal.DestroyStructure<T>(Pointer);
        Marshal.FreeHGlobal(Pointer);
    }
}

internal static partial class NativeMethods
{
    [DllImport(LibraryName, EntryPoint = "navtool_router_build_info_v8", CallingConvention = CallingConvention.Cdecl)]
    internal static extern NativeRouterStatus BuildInfo(out IntPtr json, out nuint length);
    [DllImport(LibraryName, EntryPoint = "navtool_router_quality_defaults_v8", CallingConvention = CallingConvention.Cdecl)]
    internal static extern NativeRouterStatus QualityDefaults(int quality, ref NativeRoutingOptionsV8 options);
    [DllImport(LibraryName, EntryPoint = "navtool_router_resolve_options_v8", CallingConvention = CallingConvention.Cdecl)]
    internal static extern NativeRouterStatus ResolveOptions(ref NativeRoutingOptionsV8 options, ref NativeRoutingOptionsV8 effective);
    [DllImport(LibraryName, EntryPoint = "navtool_router_polar_load_v8", CallingConvention = CallingConvention.Cdecl)]
    internal static extern NativeRouterStatus PolarLoad([MarshalAs(UnmanagedType.LPUTF8Str)] string path, ref NativePolarOptionsV8 options, out IntPtr polar);
    [DllImport(LibraryName, EntryPoint = "navtool_router_polar_create_demo_v8", CallingConvention = CallingConvention.Cdecl)]
    internal static extern NativeRouterStatus PolarDemo(out IntPtr polar);
    [DllImport(LibraryName, EntryPoint = "navtool_router_polar_metadata_v8", CallingConvention = CallingConvention.Cdecl)]
    internal static extern NativeRouterStatus PolarMetadata(NativePolarSafeHandle polar, out IntPtr json, out nuint length);
    [DllImport(LibraryName, EntryPoint = "navtool_router_polar_destroy_v8", CallingConvention = CallingConvention.Cdecl)]
    internal static extern NativeRouterStatus PolarDestroy(ref IntPtr polar);
    [DllImport(LibraryName, EntryPoint = "navtool_router_forecast_load_v8", CallingConvention = CallingConvention.Cdecl)]
    internal static extern NativeRouterStatus ForecastLoadV8([MarshalAs(UnmanagedType.LPUTF8Str)] string path, ref NativeForecastOptionsV8 options, out IntPtr forecast);
    [DllImport(LibraryName, EntryPoint = "navtool_router_forecast_get_metadata_v8", CallingConvention = CallingConvention.Cdecl)]
    internal static extern NativeRouterStatus ForecastMetadataV8(NativeForecastSafeHandle forecast, ref NativeForecastMetadataV8 metadata, out IntPtr source, out nuint length);
    [DllImport(LibraryName, EntryPoint = "navtool_router_forecast_valid_times_v8", CallingConvention = CallingConvention.Cdecl)]
    internal static extern NativeRouterStatus ForecastValidTimes(NativeForecastSafeHandle forecast, [Out] long[]? times, ulong capacity, out ulong required);
    [DllImport(LibraryName, EntryPoint = "navtool_router_land_estimate_v8_fn", CallingConvention = CallingConvention.Cdecl)]
    internal static extern NativeRouterStatus LandEstimate(ref NativeLandOptionsV8 options, ref NativeLandEstimateV8 estimate);
    [DllImport(LibraryName, EntryPoint = "navtool_router_land_load_gshhg_v8", CallingConvention = CallingConvention.Cdecl)]
    internal static extern NativeRouterStatus LandLoad([MarshalAs(UnmanagedType.LPUTF8Str)] string path, ref NativeLandOptionsV8 options, out IntPtr land);
    [DllImport(LibraryName, EntryPoint = "navtool_router_land_metadata_v8", CallingConvention = CallingConvention.Cdecl)]
    internal static extern NativeRouterStatus LandMetadata(NativeLandSafeHandle land, out IntPtr json, out nuint length);
    [DllImport(LibraryName, EntryPoint = "navtool_router_land_destroy_v8", CallingConvention = CallingConvention.Cdecl)]
    internal static extern NativeRouterStatus LandDestroy(ref IntPtr land);
    [DllImport(LibraryName, EntryPoint = "navtool_router_calculate_route_streaming_v8", CallingConvention = CallingConvention.Cdecl)]
    internal static extern NativeRouterStatus CalculateV8(ref NativeRoutingRequestV8 request,
        RoutingProgressCallback progress, IntPtr progressData,
        SegmentEligibilityCallback? eligibility, IntPtr eligibilityData, out IntPtr json, out nuint length);
    [DllImport(LibraryName, EntryPoint = "navtool_router_evaluate_actions_v8", CallingConvention = CallingConvention.Cdecl)]
    internal static extern NativeRouterStatus EvaluateActions(ref NativeRoutingRequestV8 request,
        [In] NativeActionV8[] actions, ulong actionCount, SegmentEligibilityCallback? eligibility,
        IntPtr eligibilityData, out IntPtr json, out nuint length);
    [DllImport(LibraryName, EntryPoint = "navtool_router_check_planned_hold_v8", CallingConvention = CallingConvention.Cdecl)]
    internal static extern NativeRouterStatus PlannedHold(ref NativeExclusionSettings exclusions, NativeCoordinate position,
        long arrival, long departure, out byte conflict, out ulong geometryTests, out IntPtr zone, out nuint zoneLength);
}
