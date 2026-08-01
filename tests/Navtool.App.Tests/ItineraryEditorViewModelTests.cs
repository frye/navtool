using System.Collections.Immutable;
using Navtool.App.ViewModels;
using Navtool.Core;

namespace Navtool.App.Tests;

public sealed class ItineraryEditorViewModelTests
{
    [Fact]
    public void Add_place_rename_move_remove_and_stopover_preserve_fixed_boundaries()
    {
        var editor = new ItineraryEditorViewModel();
        editor.SetEndpoints(new Coordinate(0, 0), new Coordinate(0, 3));

        editor.AddWaypointCommand.Execute(null);
        var intermediate = editor.Waypoints[1];
        intermediate.Name = "Lunch";
        intermediate.HasStopover = true;
        intermediate.StopoverHours = 2;
        intermediate.SetOnMapCommand.Execute(null);
        editor.PlaceActiveWaypoint(new Coordinate(0, 1));

        Assert.Equal("Start", editor.Waypoints[0].Name);
        Assert.Equal("Finish", editor.Waypoints[^1].Name);
        Assert.Equal(new Coordinate(0, 1), intermediate.Coordinate);
        Assert.True(editor.TryBuildPlan(out var plan, out var error), error);
        Assert.Equal(TimeSpan.FromHours(2), plan!.Waypoints[1].Stopover);

        editor.AddWaypointCommand.Execute(null);
        var second = editor.Waypoints[2];
        second.SetOnMapCommand.Execute(null);
        editor.PlaceActiveWaypoint(new Coordinate(0, 2));
        second.MoveUpCommand.Execute(null);
        Assert.Same(second, editor.Waypoints[1]);

        second.RemoveCommand.Execute(null);
        Assert.Equal(3, editor.Waypoints.Count);
        Assert.False(editor.Waypoints[0].RemoveCommand.CanExecute(null));
        Assert.False(editor.Waypoints[^1].RemoveCommand.CanExecute(null));
    }

    [Fact]
    public async Task Repository_commands_surface_errors_and_track_dirty_state()
    {
        var repository = new MemoryRepository { Failure = new IOException("disk unavailable") };
        var editor = new ItineraryEditorViewModel(repository);
        editor.SetEndpoints(new Coordinate(0, 0), new Coordinate(0, 1));

        await editor.SaveCommand.ExecuteAsync(null);

        Assert.True(editor.IsDirty);
        Assert.Contains("disk unavailable", editor.StorageError);
    }

    [Fact]
    public void Open_is_disabled_when_route_plan_storage_is_unavailable()
    {
        var editor = new ItineraryEditorViewModel
        {
            SelectedSavedPlan = new RoutePlanSummary(new RoutePlanId(), "Saved", 2)
        };

        Assert.False(editor.OpenCommand.CanExecute(null));
    }

    [Fact]
    public async Task Opened_result_is_invalidated_at_field_specific_boundary()
    {
        var plan = CreatePlanWithPendingResult();
        var repository = new MemoryRepository(plan);
        var editor = new ItineraryEditorViewModel(repository);
        await editor.RefreshSavedPlansCommand.ExecuteAsync(null);
        await editor.OpenCommand.ExecuteAsync(null);

        editor.Waypoints[1].HasStopover = true;

        Assert.True(editor.ResultsInvalidated);
        Assert.True(editor.IsDirty);
    }

    [Fact]
    public async Task Rejected_sailed_boundary_edit_does_not_mutate_or_erase_history()
    {
        var plan = CreatePlanWithPendingResult();
        plan = plan.MarkSailed(plan.Legs[0].Id);
        var repository = new MemoryRepository(plan);
        var editor = new ItineraryEditorViewModel(repository);
        await editor.RefreshSavedPlansCommand.ExecuteAsync(null);
        await editor.OpenCommand.ExecuteAsync(null);
        var waypoint = editor.Waypoints[1];

        waypoint.RemoveCommand.Execute(null);
        await editor.SaveCommand.ExecuteAsync(null);

        Assert.Equal(3, editor.Waypoints.Count);
        Assert.Single(repository.Plan!.Results);
        Assert.Single(repository.Plan.SailedLegIds);
    }

    [Fact]
    public void Failed_outcome_replaces_latest_unsailed_model_result()
    {
        var editor = new ItineraryEditorViewModel();
        editor.SetEndpoints(new Coordinate(0, 0), new Coordinate(0, 1));

        editor.RecordSingleLegOutcome(
            ForecastModel.NoaaGfs,
            null,
            RouteLegOutcomeReason.RouteCalculationFailed,
            "router failed",
            DateTimeOffset.UtcNow);

        Assert.True(editor.TryBuildPlan(out var plan, out var error), error);
        var outcome = Assert.Single(Assert.Single(plan!.Results).Legs);
        Assert.Equal(RouteLegOutcomeState.Failed, outcome.State);
        Assert.Equal("router failed", outcome.Detail);
    }

    [Fact]
    public void Pending_waypoint_can_be_removed_before_map_placement()
    {
        var editor = new ItineraryEditorViewModel();
        editor.SetEndpoints(new Coordinate(0, 0), new Coordinate(0, 2));
        editor.AddWaypointCommand.Execute(null);
        editor.Waypoints[1].SetOnMapCommand.Execute(null);

        editor.Waypoints[1].RemoveCommand.Execute(null);

        Assert.Equal(2, editor.Waypoints.Count);
        Assert.False(editor.HasPendingWaypoint);
        Assert.Null(editor.ActiveWaypoint);
    }

    [Fact]
    public async Task Save_completion_does_not_mark_concurrent_edits_clean()
    {
        var repository = new MemoryRepository
        {
            SaveGate = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously)
        };
        var editor = new ItineraryEditorViewModel(repository);
        editor.SetEndpoints(new Coordinate(0, 0), new Coordinate(0, 1));

        var save = editor.SaveCommand.ExecuteAsync(null);
        await repository.SaveStarted.Task;
        editor.RouteName = "Edited while saving";
        repository.SaveGate.SetResult();
        await save;

        Assert.True(editor.IsDirty);
        Assert.Equal("Edited while saving", editor.RouteName);
    }

    [Fact]
    public void Legs_populate_from_a_fresh_itinerary_and_mark_unmark_sailed_toggles_state()
    {
        var editor = new ItineraryEditorViewModel();
        editor.SetEndpoints(new Coordinate(0, 0), new Coordinate(0, 1));

        var leg = Assert.Single(editor.Legs);
        Assert.False(leg.IsSailed);
        Assert.True(leg.IsActive);
        Assert.Equal("Active", leg.StatusLabel);

        Assert.True(leg.MarkSailedCommand.CanExecute(null));
        leg.MarkSailedCommand.Execute(null);

        Assert.True(editor.Legs[0].IsSailed);
        Assert.Equal("Sailed", editor.Legs[0].StatusLabel);
        Assert.False(editor.Legs[0].MarkSailedCommand.CanExecute(null));
        Assert.True(editor.Legs[0].UnmarkSailedCommand.CanExecute(null));

        editor.Legs[0].UnmarkSailedCommand.Execute(null);

        Assert.False(editor.Legs[0].IsSailed);
        Assert.True(editor.Legs[0].IsActive);
    }

    [Fact]
    public void Explicit_active_leg_selection_updates_legs_and_can_be_cleared()
    {
        var editor = new ItineraryEditorViewModel();
        editor.SetEndpoints(new Coordinate(0, 0), new Coordinate(0, 3));
        editor.AddWaypointCommand.Execute(null);
        var middle = editor.Waypoints[1];
        middle.SetOnMapCommand.Execute(null);
        editor.PlaceActiveWaypoint(new Coordinate(0, 1.5));

        Assert.Equal(2, editor.Legs.Count);
        Assert.True(editor.Legs[0].IsActive);
        Assert.False(editor.Legs[1].IsActive);

        Assert.True(editor.Legs[1].MakeActiveCommand.CanExecute(null));
        editor.Legs[1].MakeActiveCommand.Execute(null);

        Assert.False(editor.Legs[0].IsActive);
        Assert.True(editor.Legs[1].IsActive);

        editor.ClearActiveLeg();

        Assert.True(editor.Legs[0].IsActive);
        Assert.False(editor.Legs[1].IsActive);
    }

    [Fact]
    public void Place_current_position_records_coordinate_and_explicit_departure_time()
    {
        var editor = new ItineraryEditorViewModel();
        editor.SetEndpoints(new Coordinate(0, 0), new Coordinate(0, 1));
        var departure = new DateTimeOffset(2026, 8, 1, 12, 0, 0, TimeSpan.Zero);

        editor.BeginCurrentPositionPlacement();
        Assert.True(editor.IsAwaitingCurrentPositionPlacement);

        var placed = editor.PlaceCurrentPosition(new Coordinate(0.2, 0.4), departure, out var error);

        Assert.True(placed, error);
        Assert.False(editor.IsAwaitingCurrentPositionPlacement);
        Assert.True(editor.HasCurrentPosition);
        Assert.Equal(new Coordinate(0.2, 0.4), editor.CurrentPositionCoordinate);
        Assert.Equal(departure, editor.CurrentPositionDepartureTimeUtc);
        Assert.NotEqual("Not set", editor.CurrentPositionDisplay);

        editor.ClearCurrentPosition();

        Assert.False(editor.HasCurrentPosition);
        Assert.Null(editor.CurrentPositionCoordinate);
        Assert.Equal("Not set", editor.CurrentPositionDisplay);
    }

    [Fact]
    public void Cancel_current_position_placement_leaves_existing_current_position_untouched()
    {
        var editor = new ItineraryEditorViewModel();
        editor.SetEndpoints(new Coordinate(0, 0), new Coordinate(0, 1));
        editor.PlaceCurrentPosition(
            new Coordinate(0.2, 0.4),
            new DateTimeOffset(2026, 8, 1, 12, 0, 0, TimeSpan.Zero),
            out _);

        editor.BeginCurrentPositionPlacement();
        editor.CancelCurrentPositionPlacement();

        Assert.False(editor.IsAwaitingCurrentPositionPlacement);
        Assert.True(editor.HasCurrentPosition);
        Assert.Equal(new Coordinate(0.2, 0.4), editor.CurrentPositionCoordinate);
    }

    [Fact]
    public async Task Save_and_open_restore_sailed_active_leg_and_current_position_state()
    {
        var repository = new MemoryRepository();
        var editor = new ItineraryEditorViewModel(repository);
        editor.SetEndpoints(new Coordinate(0, 0), new Coordinate(0, 3));
        editor.AddWaypointCommand.Execute(null);
        var middle = editor.Waypoints[1];
        middle.SetOnMapCommand.Execute(null);
        editor.PlaceActiveWaypoint(new Coordinate(0, 1.5));

        var firstLegId = editor.Legs[0].Id;
        editor.Legs[0].MarkSailedCommand.Execute(null);
        var departure = new DateTimeOffset(2026, 8, 1, 9, 0, 0, TimeSpan.Zero);
        editor.PlaceCurrentPosition(new Coordinate(0.1, 0.9), departure, out var placeError);
        Assert.Null(placeError);

        await editor.SaveCommand.ExecuteAsync(null);
        var reopened = new ItineraryEditorViewModel(repository);
        await reopened.RefreshSavedPlansCommand.ExecuteAsync(null);
        reopened.SelectedSavedPlan = reopened.SavedPlans.Single();
        await reopened.OpenCommand.ExecuteAsync(null);

        Assert.Equal(2, reopened.Legs.Count);
        Assert.Equal(firstLegId, reopened.Legs[0].Id);
        Assert.True(reopened.Legs[0].IsSailed);
        Assert.True(reopened.Legs[1].IsActive);
        Assert.True(reopened.HasCurrentPosition);
        Assert.Equal(new Coordinate(0.1, 0.9), reopened.CurrentPositionCoordinate);
        Assert.Equal(departure, reopened.CurrentPositionDepartureTimeUtc);
    }

    private static RoutePlan CreatePlanWithPendingResult()
    {
        var plan = new RoutePlan(
            "Stored",
            [
                new RouteWaypoint("Start", new Coordinate(0, 0)),
                new RouteWaypoint("Middle", new Coordinate(0, 1)),
                new RouteWaypoint("Finish", new Coordinate(0, 2))
            ]);
        var session = new RouteCalculationSession(
            plan.Id,
            ForecastModel.NoaaGfs,
            DateTimeOffset.UtcNow);
        return plan.WithResult(new RoutePlanResult(
            session,
            plan.Legs.Select(leg =>
                new RouteLegResult(
                    leg.Id,
                    RouteLegOutcomeState.Pending,
                    RouteLegOutcomeReason.None))));
    }

    private sealed class MemoryRepository : IRoutePlanRepository
    {
        private RoutePlan? _plan;

        public MemoryRepository(RoutePlan? plan = null)
        {
            _plan = plan;
        }

        public Exception? Failure { get; init; }

        public RoutePlan? Plan => _plan;

        public TaskCompletionSource? SaveGate { get; init; }

        public TaskCompletionSource SaveStarted { get; } =
            new(TaskCreationOptions.RunContinuationsAsynchronously);

        public ValueTask<ImmutableArray<RoutePlanSummary>> ListAsync(
            CancellationToken cancellationToken = default)
        {
            ThrowIfFailed();
            return ValueTask.FromResult(_plan is null
                ? ImmutableArray<RoutePlanSummary>.Empty
                : [new RoutePlanSummary(_plan.Id, _plan.Name, _plan.Waypoints.Length)]);
        }

        public ValueTask<RoutePlan> OpenAsync(
            RoutePlanId id,
            CancellationToken cancellationToken = default)
        {
            ThrowIfFailed();
            return ValueTask.FromResult(_plan!);
        }

        public async ValueTask SaveAsync(RoutePlan plan, CancellationToken cancellationToken = default)
        {
            ThrowIfFailed();
            SaveStarted.TrySetResult();
            if (SaveGate is not null)
            {
                await SaveGate.Task.WaitAsync(cancellationToken);
            }

            _plan = plan;
        }

        public ValueTask<RoutePlan> SaveAsAsync(
            RoutePlan plan,
            string name,
            CancellationToken cancellationToken = default)
        {
            ThrowIfFailed();
            _plan = new RoutePlan(name, plan.Waypoints);
            return ValueTask.FromResult(_plan);
        }

        public ValueTask DeleteAsync(
            RoutePlanId id,
            CancellationToken cancellationToken = default)
        {
            ThrowIfFailed();
            _plan = null;
            return ValueTask.CompletedTask;
        }

        private void ThrowIfFailed()
        {
            if (Failure is not null)
            {
                throw Failure;
            }
        }
    }
}
