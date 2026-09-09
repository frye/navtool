using System.Runtime.InteropServices;

namespace Navtool.Infrastructure;

[StructLayout(LayoutKind.Sequential)]
internal struct NativeCoastalDiagnosticsV9
{
    public uint StructSize;
    public int Mode;
    public IntPtr Status, UnavailableReason;
    public ulong SkippedParents, DisconnectedCandidates, HorizonCandidates, IncumbentCandidates;
    public ulong BoundUnavailable, SeedEvaluations, TopologyWork;
    public long IncumbentArrivalEpochSeconds;
    public uint HasIncumbentArrival, Reserved;
    public IntPtr SourceIdentity, DomainIdentity, SeedStatus;
    public double SpeedUpperKnots;
    public ulong TopologyCaps;
    public double NumericalMarginNauticalMiles, ClearanceNauticalMiles;
    public int RequestedMode;
    public uint HasSpeedUpper;
}

[StructLayout(LayoutKind.Sequential)]
internal struct NativeRoutingProgressV9
{
    public uint StructSize, Reserved;
    public NativeRoutingProgressV8 Base;
    public NativeCoastalDiagnosticsV9 Coastal;
}

[StructLayout(LayoutKind.Sequential)]
internal struct NativeCoastalCapV9
{
    public NativeCoordinate Center;
    public double RadiusNauticalMiles;
}

[StructLayout(LayoutKind.Sequential)]
internal struct NativeCoastalTopologyV9
{
    public uint StructSize, Reserved;
    public double South, West, North, East;
    public IntPtr SourceIdentity, DomainIdentity, Caps;
    public ulong CapCount;
    public IntPtr Probes;
    public ulong ProbeCount, ApplicationGeometryWork;
}

[StructLayout(LayoutKind.Sequential)]
internal struct NativeRoutingRequestV9
{
    public uint StructSize;
    public int CoastalPruningMode;
    public NativeRoutingRequestV8 Base;
    public IntPtr Topology;
    public ulong MaximumSeedTransitions;
}

internal static partial class NativeMethods
{
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    internal delegate byte ContinueCallbackV9(IntPtr userData);

    [DllImport(LibraryName, EntryPoint = "navtool_router_calculate_route_streaming_v9", CallingConvention = CallingConvention.Cdecl)]
    internal static extern NativeRouterStatus CalculateV9(ref NativeRoutingRequestV9 request,
        RoutingProgressCallback progress, IntPtr progressData,
        SegmentEligibilityCallback? eligibility, IntPtr eligibilityData,
        ContinueCallbackV9 shouldContinue, IntPtr controlData, out IntPtr json, out nuint length);
}
