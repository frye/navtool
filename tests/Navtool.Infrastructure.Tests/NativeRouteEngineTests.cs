using Navtool.Core;
using Navtool.Infrastructure;

namespace Navtool.Infrastructure.Tests;

public sealed class NativeRouteEngineTests
{
    [Fact]
    public void Lattice_progress_fraction_does_not_regress_when_provisional_route_time_moves_back()
    {
        var departure = new DateTimeOffset(2026, 7, 15, 0, 0, 0, TimeSpan.Zero);
        var request = new RouteRequest(
            "lattice-progress",
            new Coordinate(41, -61),
            new Coordinate(45, -55),
            departure,
            departure.AddHours(10));
        var reportedElapsed = TimeSpan.Zero;

        var first = NativeRouteEngine.AdvanceProgressFraction(
            request,
            CreateLatticeSnapshot(departure.AddHours(5), departure.AddHours(7)),
            ref reportedElapsed);
        var second = NativeRouteEngine.AdvanceProgressFraction(
            request,
            CreateLatticeSnapshot(departure.AddHours(8), departure.AddHours(4)),
            ref reportedElapsed);

        Assert.Equal(0.7, first);
        Assert.Equal(first, second);
    }

    private static RouteCalculationSnapshot CreateLatticeSnapshot(
        DateTimeOffset progressTime,
        DateTimeOffset routeTime) =>
        new(
            progressTime,
            RouteSolver.TimeDependentLattice,
            Array.Empty<RouteCalculationEnvelopeSegment>(),
            Array.Empty<RouteCalculationFrontSegment>(),
            new[] { new Coordinate(42, -60) },
            new[]
            {
                new RoutePoint(new Coordinate(41, -61), routeTime.AddHours(-1), 90, 7, 20, 180, 0),
                new RoutePoint(new Coordinate(42, -60), routeTime, 90, 7, 20, 180, 7)
            },
            new RouteDiagnostics(100, 400, 80, 3),
            new RouteLatticeSearchProgress(50, 20, 120, 1, 5));
}
