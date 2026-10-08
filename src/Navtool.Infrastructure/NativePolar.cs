using System.Runtime.InteropServices;
using System.Text.Json;
using System.Text;
using Navtool.Core;

namespace Navtool.Infrastructure;

public sealed class NativePolar : IDisposable
{
    internal NativePolar(NativePolarSafeHandle handle, BoatValidationSummary metadata)
    {
        Handle = handle;
        Metadata = metadata;
    }
    internal NativePolarSafeHandle Handle { get; }
    public BoatValidationSummary Metadata { get; }
    public bool IsClosed => Handle.IsClosed;
    public void Dispose() => Handle.Dispose();
}

public sealed partial class NativeRouterBridge
{
    public BoatValidationSummary InspectPolar(
        string path,
        BoatPolarFormat format = BoatPolarFormat.Automatic,
        double? minimumTrueWindAngleDegrees = null,
        CancellationToken cancellationToken = default)
    {
        using var polar = LoadPolar(path, format, minimumTrueWindAngleDegrees, cancellationToken);
        return polar.Metadata;
    }

    public BoatValidationSummary InspectDemoPolar(CancellationToken cancellationToken = default)
    {
        using var polar = CreateDemoPolar(cancellationToken);
        return polar.Metadata;
    }

    public NativePolar CreateDemoPolar(CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var status = NativeMethods.PolarDemo(out var raw);
        return FinishPolar(status, raw, cancellationToken);
    }

    public NativePolar LoadPolar(
        string path,
        BoatPolarFormat format = BoatPolarFormat.Automatic,
        double? minimumTrueWindAngleDegrees = null,
        CancellationToken cancellationToken = default)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(path);
        if (!Enum.IsDefined(format)) throw new ArgumentOutOfRangeException(nameof(format));
        if (minimumTrueWindAngleDegrees is { } angle && (!double.IsFinite(angle) || angle is < 0 or > 180))
            throw new ArgumentOutOfRangeException(nameof(minimumTrueWindAngleDegrees));
        cancellationToken.ThrowIfCancellationRequested();
        var fullPath = Path.GetFullPath(path);
        ValidateNativeText(fullPath);
        if (!File.Exists(fullPath))
            throw new RoutingException(RoutingFailureKind.InvalidBoat, $"Selected polar file is missing: {fullPath}");
        var options = new NativePolarOptionsV8
        {
            StructSize = checked((uint)Marshal.SizeOf<NativePolarOptionsV8>()),
            Format = format switch
            {
                BoatPolarFormat.Automatic => 0,
                BoatPolarFormat.NativeMatrix => 1,
                BoatPolarFormat.Expedition => 2,
                _ => throw new ArgumentOutOfRangeException(nameof(format))
            },
            Flags = minimumTrueWindAngleDegrees.HasValue ? 1UL : 0UL,
            MinimumSailingAngleDegrees = minimumTrueWindAngleDegrees ?? 0
        };
        var status = NativeMethods.PolarLoad(fullPath, ref options, out var raw);
        return FinishPolar(status, raw, cancellationToken);
    }

    private NativePolar FinishPolar(NativeRouterStatus status, IntPtr raw, CancellationToken cancellationToken)
    {
        var handle = new NativePolarSafeHandle(raw);
        try
        {
            ThrowIfFailed(status, "Loading selected boat polar");
            if (handle.IsInvalid) throw new NativeRouteFormatException("Native polar success returned an invalid handle.");
            cancellationToken.ThrowIfCancellationRequested();
            status = NativeMethods.PolarMetadata(handle, out var json, out var length);
            using var buffer = new NativeAllocatedBufferSafeHandle(json);
            ThrowIfFailed(status, "Inspecting selected boat polar");
            var metadataJson = CopyUtf8(json, length, _options.MaximumTextBytes, "polar metadata");
            using var document = JsonDocument.Parse(metadataJson);
            var metadata = document.RootElement;
            var maximumWind = metadata.GetProperty("maximum_tabulated_wind_speed_knots").GetDouble();
            var minimumAngle = metadata.GetProperty("minimum_sailing_angle_degrees");
            if (!double.IsFinite(maximumWind) || maximumWind <= 0 ||
                metadata.GetProperty("resolved_format").ValueKind != JsonValueKind.Null)
                throw new NativeRouteFormatException("Native polar metadata returned an invalid range or unsupported resolved format.");
            var result = new BoatValidationSummary(
                metadata.GetProperty("validation").GetString()! +
                    "; automatic parsing does not report a resolved format.",
                MaximumWindSpeedKnots: maximumWind,
                MinimumAngleDegrees: minimumAngle.ValueKind == JsonValueKind.Null ? null : minimumAngle.GetDouble());
            cancellationToken.ThrowIfCancellationRequested();
            return new NativePolar(handle, result);
        }
        catch
        {
            handle.Dispose();
            throw;
        }
    }

    private NativeRoutingIdentity ReadBuildIdentity()
    {
        try
        {
            var status = NativeMethods.BuildInfo(out var json, out var length);
            using var buffer = new NativeAllocatedBufferSafeHandle(json);
            ThrowIfFailed(status, "Reading native build identity");
            var text = CopyUtf8(json, length, _options.MaximumTextBytes, "build identity");
            using var document = JsonDocument.Parse(text);
            var root = document.RootElement;
            if (root.GetProperty("abi_version").GetUInt32() != AbiVersion ||
                root.GetProperty("route_json_schema").GetString() != "route_result_v2" ||
                root.GetProperty("capabilities").GetUInt64() != (ulong)_capabilities ||
                root.GetProperty("ensemble_enabled").GetBoolean())
                throw new NativeRouteFormatException("Native build metadata contradicts the required cruising ABI/capabilities.");
            if (string.IsNullOrWhiteSpace(root.GetProperty("library_version").GetString()) ||
                string.IsNullOrWhiteSpace(root.GetProperty("library_revision").GetString()))
                throw new NativeRouteFormatException("Native build identity must name its actual version and revision.");
            return new NativeRoutingIdentity((int)AbiVersion,
                root.GetProperty("library_version").GetString()!,
                root.GetProperty("library_revision").GetString()!,
                text,
                (ulong)_capabilities);
        }
        catch (EntryPointNotFoundException exception)
        {
            throw new NativeBridgeUnavailableException("ABI 8 bridge is missing mandatory build identity.", exception);
        }

    }

    internal static void ValidateNativeText(string value)
    {
        if (value.Contains('\0')) throw new ArgumentException("Native UTF-8 text cannot contain embedded NUL characters.");
        try { _ = new UTF8Encoding(false, true).GetByteCount(value); }
        catch (EncoderFallbackException exception) { throw new ArgumentException("Native text must be valid UTF-8.", exception); }
    }
}
