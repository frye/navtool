namespace Navtool.Core;

/// <summary>Cumulative proof-based coastal work, separate from ordinary beam pruning.
/// An absent audit means unavailable telemetry, not zero work.</summary>
public sealed record RouteCoastalPruningDiagnostics
{
    public RouteCoastalPruningDiagnostics(
        RouteCoastalPruningMode mode,
        string status,
        string? unavailableReason,
        long skippedParents,
        long disconnectedCandidates,
        long horizonCandidates,
        long incumbentCandidates,
        long boundUnavailable,
        long seedEvaluations,
        long topologyWork,
        DateTimeOffset? incumbentArrival = null,
        string? sourceIdentity = null,
        string? domainIdentity = null,
        string? seedStatus = null,
        double? speedUpperKnots = null,
        long? topologyCaps = null,
        double? numericalMarginNauticalMiles = null,
        double? clearanceNauticalMiles = null)
    {
        if (!Enum.IsDefined(mode))
            throw new ArgumentOutOfRangeException(nameof(mode));
        ArgumentException.ThrowIfNullOrWhiteSpace(status);
        if (skippedParents < 0 || disconnectedCandidates < 0 || horizonCandidates < 0 ||
            incumbentCandidates < 0 || boundUnavailable < 0 || seedEvaluations < 0 || topologyWork < 0)
            throw new ArgumentOutOfRangeException(nameof(skippedParents), "Coastal audit counters must be nonnegative.");
        if (speedUpperKnots is { } speed && (!double.IsFinite(speed) || speed <= 0))
            throw new ArgumentOutOfRangeException(nameof(speedUpperKnots));
        if (topologyCaps < 0)
            throw new ArgumentOutOfRangeException(nameof(topologyCaps));
        if (numericalMarginNauticalMiles is { } margin && (!double.IsFinite(margin) || margin < 0))
            throw new ArgumentOutOfRangeException(nameof(numericalMarginNauticalMiles));
        if (clearanceNauticalMiles is { } clearance && (!double.IsFinite(clearance) || clearance < 0))
            throw new ArgumentOutOfRangeException(nameof(clearanceNauticalMiles));
        Mode = mode;
        Status = status;
        UnavailableReason = unavailableReason;
        SkippedParents = skippedParents;
        DisconnectedCandidates = disconnectedCandidates;
        HorizonCandidates = horizonCandidates;
        IncumbentCandidates = incumbentCandidates;
        BoundUnavailable = boundUnavailable;
        SeedEvaluations = seedEvaluations;
        TopologyWork = topologyWork;
        IncumbentArrival = incumbentArrival?.ToUniversalTime();
        SourceIdentity = sourceIdentity;
        DomainIdentity = domainIdentity;
        SeedStatus = seedStatus;
        SpeedUpperKnots = speedUpperKnots;
        TopologyCaps = topologyCaps;
        NumericalMarginNauticalMiles = numericalMarginNauticalMiles;
        ClearanceNauticalMiles = clearanceNauticalMiles;
    }

    public RouteCoastalPruningMode Mode { get; }
    public string Status { get; }
    public string? UnavailableReason { get; }
    public long SkippedParents { get; }
    public long DisconnectedCandidates { get; }
    public long HorizonCandidates { get; }
    public long IncumbentCandidates { get; }
    public long BoundUnavailable { get; }
    public long SeedEvaluations { get; }
    public long TopologyWork { get; }
    public DateTimeOffset? IncumbentArrival { get; }
    public string? SourceIdentity { get; }
    public string? DomainIdentity { get; }
    public string? SeedStatus { get; }
    public double? SpeedUpperKnots { get; }
    public long? TopologyCaps { get; }
    public double? NumericalMarginNauticalMiles { get; }
    public double? ClearanceNauticalMiles { get; }
}
