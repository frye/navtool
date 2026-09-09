using System.Collections.Immutable;
using System.Runtime.InteropServices;
using System.Text.Json;
using Navtool.Core;

namespace Navtool.Infrastructure;

public sealed partial class NativeRouterBridge
{
    private RouteCalculationSnapshot? CopyCoastalProgress(IntPtr pointer, Action<string>? onPreparation)
    {
        if (pointer == IntPtr.Zero) throw new NativeRouteFormatException("Native coastal progress is null.");
        var value = Marshal.PtrToStructure<NativeRoutingProgressV9>(pointer);
        var audit = value.Coastal;
        if (value.StructSize != Marshal.SizeOf<NativeRoutingProgressV9>() || value.Reserved != 0 ||
            audit.StructSize != Marshal.SizeOf<NativeCoastalDiagnosticsV9>() || audit.Reserved != 0 ||
            audit.Mode != 1 || audit.RequestedMode != 1 || audit.HasIncumbentArrival > 1 || audit.HasSpeedUpper > 1)
            throw new NativeRouteFormatException("Native coastal progress has invalid layout, mode or flags.");
        var diagnostics = new RouteCoastalPruningDiagnostics(RouteCoastalPruningMode.ConservativeLandAware,
            Text(audit.Status), audit.UnavailableReason == IntPtr.Zero ? null : Text(audit.UnavailableReason),
            checked((long)audit.SkippedParents), checked((long)audit.DisconnectedCandidates),
            checked((long)audit.HorizonCandidates), checked((long)audit.IncumbentCandidates),
            checked((long)audit.BoundUnavailable), checked((long)audit.SeedEvaluations),
            checked((long)audit.TopologyWork),
            audit.HasIncumbentArrival == 0 ? null : DateTimeOffset.FromUnixTimeSeconds(audit.IncumbentArrivalEpochSeconds),
            Text(audit.SourceIdentity), Text(audit.DomainIdentity), Text(audit.SeedStatus),
            audit.HasSpeedUpper == 0 ? null : audit.SpeedUpperKnots, checked((long)audit.TopologyCaps),
            audit.NumericalMarginNauticalMiles, audit.ClearanceNauticalMiles);
        if (value.Base.Progress.ProvisionalRoutePointCount == 0)
        {
            onPreparation?.Invoke($"Coastal seed {diagnostics.SeedStatus}: {diagnostics.SeedEvaluations:N0} evaluations");
            return null;
        }
        return CopyProgress(IntPtr.Add(pointer, Marshal.OffsetOf<NativeRoutingProgressV9>(
            nameof(NativeRoutingProgressV9.Base)).ToInt32()), diagnostics);

        static string Text(IntPtr text)
        {
            var value = text == IntPtr.Zero ? null : Marshal.PtrToStringUTF8(text);
            if (string.IsNullOrWhiteSpace(value) || value.Length > 4096)
                throw new NativeRouteFormatException("Native coastal audit text is missing or oversized.");
            return value;
        }
    }

    internal void ValidateCoastalPruning(ResolvedRoutingOptions options)
    {
        if (!Enum.IsDefined(options.CoastalPruning))
            throw new RoutingException(RoutingFailureKind.InvalidConfiguration, "Unknown coastal pruning mode.");
        if (options.CoastalPruning == RouteCoastalPruningMode.Off) return;
        if (AbiVersion < 9 || (Capabilities & NativeRouterCapabilities.CoastalPruning) == 0)
            throw new RoutingException(RoutingFailureKind.NativeUnavailable,
                "Conservative coastal pruning requires bridge ABI 9 with coastal-pruning support. Rebuild the native bridge or disable the option.");
        if (options.Optimization.Solver != RouteSolver.IsochroneBeam)
            throw new RoutingException(RoutingFailureKind.InvalidConfiguration,
                "Conservative coastal pruning currently supports only the isochrone beam solver.");
    }

}

internal static partial class NativeRouteJsonParser
{
    private static ImmutableArray<RouteCoastalSeedAction> ParseCoastalSeedActions(JsonElement diagnostics)
    {
        if (!diagnostics.TryGetProperty("coastalPruning", out var coastal)) return default;
        return Required(coastal, "seedActions", JsonValueKind.Array).EnumerateArray()
            .Select(action => new RouteCoastalSeedAction(Nonnegative(action, "headingDegrees"),
                TimeSpan.FromSeconds(RequiredInt64(action, "durationSeconds")))).ToImmutableArray();
    }

    private static RouteCoastalPruningDiagnostics? ParseCoastalDiagnostics(JsonElement diagnostics)
    {
        if (!diagnostics.TryGetProperty("coastalPruning", out var coastal)) return null;
        RequireKind(coastal, JsonValueKind.Object, "coastalPruning");
        if (RequiredInt64(coastal, "schemaVersion") != 1 ||
            RequiredString(coastal, "requested") != "conservative" ||
            RequiredString(coastal, "effective") != "conservative" ||
            RequiredString(coastal, "topologyRepresentation") != "spherical_caps_v1")
            throw new NativeRouteFormatException("Native coastal audit has an unsupported version, representation or mode.");
        var status = RequiredString(coastal, "boundStatus");
        var speed = coastal.GetProperty("speedUpperKnots").ValueKind == JsonValueKind.Null
            ? (double?)null : Positive(coastal, "speedUpperKnots");
        var arrival = coastal.GetProperty("incumbentArrival").ValueKind == JsonValueKind.Null
            ? (DateTimeOffset?)null : RequiredTimestamp(coastal, "incumbentArrival");
        var actions = Required(coastal, "seedActions", JsonValueKind.Array);
        if (actions.GetArrayLength() > 10000)
            throw new NativeRouteFormatException("Native coastal seed exceeds the action limit.");
        foreach (var action in actions.EnumerateArray())
            if (Nonnegative(action, "headingDegrees") >= 360 || RequiredInt64(action, "durationSeconds") == 0)
                throw new NativeRouteFormatException("Native coastal seed has invalid controls.");
        return new(RouteCoastalPruningMode.ConservativeLandAware, status, speed is null ? status : null,
            RequiredInt64(coastal, "parentExpansionsSkipped"), RequiredInt64(coastal, "candidatesDisconnected"),
            RequiredInt64(coastal, "candidatesHorizon"), RequiredInt64(coastal, "candidatesIncumbent"),
            RequiredInt64(coastal, "boundUnavailable"), RequiredInt64(coastal, "seedTransitionEvaluations"),
            RequiredInt64(coastal, "topologyWork"), arrival,
            RequiredString(coastal, "sourceIdentity"), RequiredString(coastal, "domainIdentity"),
            RequiredString(coastal, "seedStatus"), speed, RequiredInt64(coastal, "topologyCaps"),
            Nonnegative(coastal, "numericalMarginNm"), Nonnegative(coastal, "clearanceNm"));
    }
}
