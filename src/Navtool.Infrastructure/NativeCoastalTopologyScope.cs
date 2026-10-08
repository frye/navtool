using System.Runtime.InteropServices;

namespace Navtool.Infrastructure;

internal sealed class NativeCoastalTopologyScope : IDisposable
{
    private readonly List<GCHandle> _handles = [];
    private readonly List<IntPtr> _strings = [];
    private NativeStructScope<NativeCoastalTopologyV9>? _topology;

    internal NativeCoastalTopologyScope(CoastalTopologyPreparation preparation)
    {
        try
        {
            var caps = preparation.Caps.Select(cap => new NativeCoastalCapV9
            {
                Center = new NativeCoordinate { LatitudeDegrees = cap.Center.Latitude, LongitudeDegrees = cap.Center.Longitude },
                RadiusNauticalMiles = cap.RadiusNauticalMiles
            }).ToArray();
            var probes = preparation.Probes.Select(point => new NativeCoordinate
            {
                LatitudeDegrees = point.Latitude, LongitudeDegrees = point.Longitude
            }).ToArray();
            _topology = new NativeStructScope<NativeCoastalTopologyV9>(new()
            {
                StructSize = checked((uint)Marshal.SizeOf<NativeCoastalTopologyV9>()),
                South = preparation.Bounds.South, West = preparation.Bounds.West,
                North = preparation.Bounds.North, East = preparation.Bounds.East,
                SourceIdentity = Text(preparation.SourceIdentity), DomainIdentity = Text(preparation.DomainIdentity),
                Caps = Pin(caps), CapCount = checked((ulong)caps.Length),
                Probes = Pin(probes), ProbeCount = checked((ulong)probes.Length),
                ApplicationGeometryWork = preparation.GeometryWork
            });
        }
        catch
        {
            Dispose();
            throw;
        }
    }

    internal IntPtr Pointer => _topology?.Pointer ?? throw new ObjectDisposedException(nameof(NativeCoastalTopologyScope));

    private IntPtr Text(string value)
    {
        NativeRouterBridge.ValidateNativeText(value);
        var pointer = Marshal.StringToCoTaskMemUTF8(value);
        _strings.Add(pointer);
        return pointer;
    }

    private IntPtr Pin(Array values)
    {
        if (values.Length == 0) return IntPtr.Zero;
        var handle = GCHandle.Alloc(values, GCHandleType.Pinned);
        _handles.Add(handle);
        return handle.AddrOfPinnedObject();
    }

    public void Dispose()
    {
        _topology?.Dispose();
        _topology = null;
        foreach (var handle in _handles) handle.Free();
        _handles.Clear();
        foreach (var pointer in _strings) Marshal.FreeCoTaskMem(pointer);
        _strings.Clear();
    }
}
