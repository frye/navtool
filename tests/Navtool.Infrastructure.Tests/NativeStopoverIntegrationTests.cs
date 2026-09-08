using Navtool.Core;

namespace Navtool.Infrastructure.Tests;

public sealed class NativeStopoverIntegrationTests
{
    private static readonly DateTimeOffset Epoch = DateTimeOffset.FromUnixTimeSeconds(0);

    [Theory]
    [InlineData(50, 150, true)]
    [InlineData(150, 250, true)]
    [InlineData(50, 250, true)]
    [InlineData(200, 250, false)]
    [InlineData(50, 99, false)]
    public void Whole_hold_interval_respects_native_half_open_activation(long from, long until, bool conflict)
    {
        var bridge = NativeIntegration.Bridge();
        if (bridge is null) return;
        var result = bridge.CheckPlannedHold(new Coordinate(0, 0), Epoch.AddSeconds(from), Epoch.AddSeconds(until),
            Zones());
        Assert.Equal(conflict ? RouteHoldCheckStatus.Conflict : RouteHoldCheckStatus.Clear, result.Status);
        Assert.Equal(conflict ? "timed-zone" : null, result.ConflictZoneIdentifier);
    }

    [Fact]
    public void Native_hold_checker_preserves_holes_boundary_policy_and_antimeridian()
    {
        var bridge = NativeIntegration.Bridge();
        if (bridge is null) return;
        var from = Epoch.AddSeconds(50);
        var until = Epoch.AddSeconds(250);
        Assert.True(bridge.CheckPlannedHold(new Coordinate(0, 0), from, until, Zones(hole: true)).AllowsHandoff);
        Assert.False(bridge.CheckPlannedHold(new Coordinate(-1, -1), from, until, Zones()).AllowsHandoff);
        Assert.True(bridge.CheckPlannedHold(new Coordinate(-1, -1), from, until,
            Zones(policy: RouteExclusionBoundaryPolicy.BoundaryAllowed)).AllowsHandoff);
        Assert.False(bridge.CheckPlannedHold(new Coordinate(0, 180), from, until, Zones(dateline: true)).AllowsHandoff);
        Assert.True(bridge.CheckPlannedHold(new Coordinate(0, 0), from, until, Zones(dateline: true)).AllowsHandoff);
        Assert.Throws<ArgumentException>(() => bridge.CheckPlannedHold(new Coordinate(0, 0), until, from, Zones()));
    }

    private static RouteExclusionOptions Zones(bool hole = false, bool dateline = false,
        RouteExclusionBoundaryPolicy policy = RouteExclusionBoundaryPolicy.BoundaryExcluded)
    {
        var outer = new RouteExclusionRing(dateline
            ? [new Coordinate(-1, 179), new Coordinate(-1, -179), new Coordinate(1, -179), new Coordinate(1, 179)]
            : [new Coordinate(-1, -1), new Coordinate(-1, 1), new Coordinate(1, 1), new Coordinate(1, -1)]);
        var holes = hole ? new[]
        {
            new RouteExclusionRing([new Coordinate(-.2, -.2), new Coordinate(-.2, .2), new Coordinate(.2, .2), new Coordinate(.2, -.2)])
        } : null;
        return new RouteExclusionOptions(
            [new RouteExclusionZone("timed-zone", "test", [new RouteExclusionPolygon(outer, holes)],
                activeFrom: Epoch.AddSeconds(100), activeUntil: Epoch.AddSeconds(200))],
            new RouteProviderMetadata("hold-test", "test", "1"), policy);
    }
}
