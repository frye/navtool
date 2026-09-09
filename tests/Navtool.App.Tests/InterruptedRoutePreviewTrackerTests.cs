using Navtool.App.Services;
using Navtool.Core;

namespace Navtool.App.Tests;

public sealed class InterruptedRoutePreviewTrackerTests
{
    private static readonly DateTimeOffset Departure = new(2026, 9, 9, 3, 0, 0, TimeSpan.Zero);

    [Fact]
    public void Failure_and_blocked_successors_retain_only_the_current_leg_path()
    {
        var tracker = new InterruptedRoutePreviewTracker();
        var attempt = Guid.NewGuid();
        var snapshot = Snapshot();
        tracker.Observe(ForecastModel.NoaaGfs, 1, attempt, true, false, null, snapshot);
        tracker.Observe(ForecastModel.NoaaGfs, 1, null, false, false, "work limit", null);
        tracker.Observe(ForecastModel.NoaaGfs, 2, null, false, false, null, null);

        var preview = Assert.Single(tracker.Previews);
        Assert.Same(snapshot, preview.Snapshot);
        Assert.Equal("work limit", preview.FailureMessage);
        Assert.Equal(1, preview.LegIndex);
        Assert.Equal(attempt, preview.AttemptId);
    }

    [Fact]
    public void New_attempt_without_geometry_cannot_reuse_previous_attempt()
    {
        var tracker = new InterruptedRoutePreviewTracker();
        tracker.Observe(ForecastModel.NoaaGfs, 0, Guid.NewGuid(), true, false, null, Snapshot());
        tracker.Observe(ForecastModel.NoaaGfs, 0, null, true, false, null, null);
        tracker.Observe(ForecastModel.NoaaGfs, 0, null, false, false, "fallback failed", null);
        Assert.Empty(tracker.Previews);
    }

    [Fact]
    public void Completed_models_and_new_legs_do_not_retain_previous_geometry()
    {
        var tracker = new InterruptedRoutePreviewTracker();
        tracker.Observe(ForecastModel.NoaaGfs, 0, Guid.NewGuid(), true, false, null, Snapshot());
        tracker.Observe(ForecastModel.EcmwfIfs, 0, Guid.NewGuid(), true, false, null, Snapshot());
        tracker.Observe(ForecastModel.NoaaGfs, 0, null, false, true, null, null);
        Assert.Equal(ForecastModel.EcmwfIfs, Assert.Single(tracker.Previews).Model);
        tracker.Observe(ForecastModel.EcmwfIfs, 1, null, true, false, null, null);
        Assert.Empty(tracker.Previews);
    }

    [Fact]
    public void Snapshotless_progress_does_not_erase_current_attempt_path()
    {
        var tracker = new InterruptedRoutePreviewTracker();
        var attempt = Guid.NewGuid();
        tracker.Observe(ForecastModel.NoaaGfs, 0, attempt, true, false, null, Snapshot());
        tracker.Observe(ForecastModel.NoaaGfs, 0, attempt, true, false, null, null);
        Assert.Single(tracker.Previews);
        tracker.Clear();
        Assert.Empty(tracker.Previews);
    }

    private static RouteCalculationSnapshot Snapshot() => new(
        Departure.AddHours(1),
        [new RouteCalculationEnvelopeSegment([new(48, -123), new(48.1, -123.1)], false)],
        [new RouteCalculationFrontSegment([new(48, -123), new(48.1, -123.1)])],
        [
            new RoutePoint(new(48, -123), Departure, 90, 6, 15, 180, 0),
            new RoutePoint(new(48.1, -123.1), Departure.AddHours(1), 90, 6, 15, 180, 10)
        ],
        new RouteDiagnostics(10, 20, 5, 1));
}
