using System.Collections.ObjectModel;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using Navtool.Core;

namespace Navtool.App.ViewModels;

public sealed partial class WaypointEditorItemViewModel : ViewModelBase
{
    private readonly ItineraryEditorViewModel _owner;

    internal WaypointEditorItemViewModel(
        ItineraryEditorViewModel owner,
        RouteWaypointId id,
        string name,
        Coordinate? coordinate,
        TimeSpan? stopover)
    {
        _owner = owner;
        Id = id;
        _name = name;
        _coordinate = coordinate;
        _hasStopover = stopover is not null;
        _stopoverHours = stopover?.TotalHours ?? 1;
    }

    public RouteWaypointId Id { get; }

    [ObservableProperty]
    private string _name;

    [ObservableProperty]
    private Coordinate? _coordinate;

    [ObservableProperty]
    private bool _hasStopover;

    [ObservableProperty]
    private double _stopoverHours;

    public int Position => _owner.Waypoints.IndexOf(this) + 1;

    public string PositionLabel => Position.ToString();

    public bool IsStart => Position == 1;

    public bool IsFinish => Position == _owner.Waypoints.Count;

    public bool IsIntermediate => !IsStart && !IsFinish;

    public string Role => IsStart ? "START" : IsFinish ? "FINISH" : "WAYPOINT";

    public string CoordinateDisplay => Coordinate is null
        ? "Not set"
        : $"{Math.Abs(Coordinate.Value.Latitude):0.000}° " +
          $"{(Coordinate.Value.Latitude >= 0 ? "N" : "S")}, " +
          $"{Math.Abs(Coordinate.Value.Longitude):0.000}° " +
          $"{(Coordinate.Value.Longitude >= 0 ? "E" : "W")}";

    [RelayCommand]
    private void SetOnMap() => _owner.BeginMapPlacement(this);

    [RelayCommand(CanExecute = nameof(IsIntermediate))]
    private void Remove() => _owner.Remove(this);

    [RelayCommand(CanExecute = nameof(CanMoveUp))]
    private void MoveUp() => _owner.Move(this, Position - 2);

    [RelayCommand(CanExecute = nameof(CanMoveDown))]
    private void MoveDown() => _owner.Move(this, Position);

    private bool CanMoveUp() => IsIntermediate && Position > 2;

    private bool CanMoveDown() => IsIntermediate && Position < _owner.Waypoints.Count - 1;

    partial void OnNameChanged(string value) => _owner.RenameWaypoint(this, value);

    partial void OnCoordinateChanged(Coordinate? value)
    {
        OnPropertyChanged(nameof(CoordinateDisplay));
        _owner.ChangeCoordinate(this, value);
    }

    partial void OnHasStopoverChanged(bool value) => _owner.ChangeStopover(this);

    partial void OnStopoverHoursChanged(double value) => _owner.ChangeStopover(this);

    internal TimeSpan? GetStopover() =>
        IsIntermediate && HasStopover && double.IsFinite(StopoverHours) && StopoverHours > 0
            ? TimeSpan.FromHours(StopoverHours)
            : null;

    internal void RefreshPosition()
    {
        OnPropertyChanged(nameof(Position));
        OnPropertyChanged(nameof(PositionLabel));
        OnPropertyChanged(nameof(IsStart));
        OnPropertyChanged(nameof(IsFinish));
        OnPropertyChanged(nameof(IsIntermediate));
        OnPropertyChanged(nameof(Role));
        RemoveCommand.NotifyCanExecuteChanged();
        MoveUpCommand.NotifyCanExecuteChanged();
        MoveDownCommand.NotifyCanExecuteChanged();
    }
}

public sealed partial class ItineraryEditorViewModel : ViewModelBase
{
    private readonly IRoutePlanRepository? _repository;
    private RoutePlan? _plan;
    private bool _suppressChanges;

    public ItineraryEditorViewModel(IRoutePlanRepository? repository = null)
    {
        _repository = repository;
        NewDraft();
    }

    public ObservableCollection<WaypointEditorItemViewModel> Waypoints { get; } = [];

    public ObservableCollection<RoutePlanSummary> SavedPlans { get; } = [];

    [ObservableProperty]
    private string _routeName = "Untitled route";

    [ObservableProperty]
    private string _saveAsName = "Untitled route copy";

    [ObservableProperty]
    private RoutePlanSummary? _selectedSavedPlan;

    [ObservableProperty]
    private bool _isDirty;

    [ObservableProperty]
    private bool _resultsInvalidated;

    [ObservableProperty]
    private string? _storageError;

    [ObservableProperty]
    private string? _validationMessage;

    [ObservableProperty]
    private WaypointEditorItemViewModel? _activeWaypoint;

    public RoutePlanId PlanId { get; private set; }

    public long CalculationRevision { get; private set; }

    public long EditRevision { get; private set; }

    public event EventHandler? ItineraryChanged;

    public event EventHandler<WaypointEditorItemViewModel>? MapPlacementStarted;

    public Coordinate? Start => Waypoints.FirstOrDefault()?.Coordinate;

    public Coordinate? Finish => Waypoints.LastOrDefault()?.Coordinate;

    public bool HasPendingWaypoint => Waypoints.Any(waypoint => waypoint.Coordinate is null);

    public void SetEndpoints(Coordinate start, Coordinate finish)
    {
        Waypoints[0].Coordinate = start;
        Waypoints[^1].Coordinate = finish;
    }

    public void BeginMapPlacement(WaypointEditorItemViewModel waypoint)
    {
        ArgumentNullException.ThrowIfNull(waypoint);
        if (!Waypoints.Contains(waypoint))
        {
            throw new ArgumentException("The waypoint does not belong to this itinerary.", nameof(waypoint));
        }

        ActiveWaypoint = waypoint;
        MapPlacementStarted?.Invoke(this, waypoint);
    }

    public void PlaceActiveWaypoint(Coordinate coordinate)
    {
        if (ActiveWaypoint is null)
        {
            throw new InvalidOperationException("No waypoint is awaiting map placement.");
        }

        var waypoint = ActiveWaypoint;
        ActiveWaypoint = null;
        waypoint.Coordinate = coordinate;
    }

    public void CancelMapPlacement() => ActiveWaypoint = null;

    [RelayCommand]
    private void New() => NewDraft();

    [RelayCommand(CanExecute = nameof(CanAddWaypoint))]
    private void AddWaypoint()
    {
        var item = new WaypointEditorItemViewModel(
            this,
            new RouteWaypointId(),
            $"Waypoint {Waypoints.Count}",
            null,
            null);
        Waypoints.Insert(Waypoints.Count - 1, item);
        CalculationRevision++;
        MarkChanged();
        RefreshPositions();
        AddWaypointCommand.NotifyCanExecuteChanged();
    }

    private bool CanAddWaypoint() => !HasPendingWaypoint;

    [RelayCommand]
    private async Task RefreshSavedPlans()
    {
        if (_repository is null)
        {
            StorageError = "Route plan storage is unavailable.";
            return;
        }

        try
        {
            StorageError = null;
            var plans = await _repository.ListAsync();
            SavedPlans.Clear();
            foreach (var plan in plans)
            {
                SavedPlans.Add(plan);
            }

            SelectedSavedPlan = SavedPlans.FirstOrDefault(summary => summary.Id == PlanId) ??
                                SavedPlans.FirstOrDefault();
        }
        catch (Exception exception)
        {
            StorageError = exception.Message;
        }
    }

    [RelayCommand(CanExecute = nameof(CanOpen))]
    private async Task Open()
    {
        if (_repository is null || SelectedSavedPlan is null)
        {
            StorageError = "Select a saved route plan to open.";
            return;
        }

        try
        {
            StorageError = null;
            Load(await _repository.OpenAsync(SelectedSavedPlan.Id));
        }
        catch (Exception exception)
        {
            StorageError = exception.Message;
        }
    }

    private bool CanOpen() => SelectedSavedPlan is not null;

    [RelayCommand]
    private async Task Save()
    {
        if (_repository is null)
        {
            StorageError = "Route plan storage is unavailable.";
            return;
        }

        if (!TryBuildPlan(out var plan, out var error))
        {
            StorageError = error;
            return;
        }

        try
        {
            var revision = EditRevision;
            StorageError = null;
            await _repository.SaveAsync(plan!);
            if (EditRevision == revision)
            {
                _plan = plan;
                IsDirty = false;
            }

            await RefreshSavedPlans();
        }
        catch (Exception exception)
        {
            StorageError = exception.Message;
        }
    }

    [RelayCommand]
    private async Task SaveAs()
    {
        if (_repository is null)
        {
            StorageError = "Route plan storage is unavailable.";
            return;
        }

        if (!TryBuildPlan(out var plan, out var error))
        {
            StorageError = error;
            return;
        }

        try
        {
            var revision = EditRevision;
            StorageError = null;
            var copy = await _repository.SaveAsAsync(plan!, SaveAsName);
            if (EditRevision == revision)
            {
                Load(copy);
            }

            await RefreshSavedPlans();
        }
        catch (Exception exception)
        {
            StorageError = exception.Message;
        }
    }

    public bool TryBuildPlan(out RoutePlan? plan, out string? error)
    {
        plan = null;
        error = null;
        if (Waypoints.Count < 2 || Waypoints.Any(waypoint => waypoint.Coordinate is null))
        {
            error = "Set every waypoint on the map before saving.";
            return false;
        }

        try
        {
            var waypoints = Waypoints.Select(waypoint => new RouteWaypoint(
                waypoint.Id,
                waypoint.Name,
                waypoint.Coordinate!.Value,
                waypoint.GetStopover())).ToArray();
            if (_plan is not null &&
                _plan.Id == PlanId &&
                _plan.Waypoints.SequenceEqual(waypoints))
            {
                plan = _plan.Name == RouteName ? _plan : _plan.Rename(RouteName);
            }
            else
            {
                plan = _plan is null
                    ? new RoutePlan(PlanId, RouteName, waypoints)
                    : new RoutePlan(
                        PlanId,
                        RouteName,
                        waypoints,
                        _plan.Results,
                        _plan.SailedLegIds);
            }

            ValidationMessage = null;
            return true;
        }
        catch (Exception exception)
        {
            error = exception.Message;
            ValidationMessage = error;
            return false;
        }
    }

    public RouteResult? RecordSingleLegOutcome(
        ForecastModel model,
        RouteResult? route,
        RouteLegOutcomeReason reason,
        string? detail,
        DateTimeOffset completedAt)
    {
        if (!TryBuildPlan(out var plan, out var error))
        {
            throw new InvalidOperationException(error);
        }

        if (plan!.Legs.Length != 1)
        {
            throw new InvalidOperationException(
                "Only two-waypoint route results can be recorded until sequential routing is implemented.");
        }

        var completed = completedAt.ToUniversalTime();
        var session = new RouteCalculationSession(
            plan.Id,
            model,
            completed).Complete(completed);
        var state = route is null
            ? RouteLegOutcomeState.Failed
            : RouteLegOutcomeState.Succeeded;
        _plan = plan.WithResult(new RoutePlanResult(
            session,
            [
                new RouteLegResult(
                    plan.Legs[0].Id,
                    state,
                    reason,
                    route,
                    detail)
            ]));
        ResultsInvalidated = _plan.HasInvalidatedResults;
        IsDirty = true;
        EditRevision++;
        NotifyItineraryChanged();
        return _plan.LatestResult(model)!.Legs[0].Route;
    }

    internal void Remove(WaypointEditorItemViewModel waypoint)
    {
        var index = Waypoints.IndexOf(waypoint);
        if (index <= 0 || index >= Waypoints.Count - 1)
        {
            throw new InvalidOperationException("Start and finish waypoints cannot be removed.");
        }

        var belongsToPlan = _plan?.Waypoints.Any(existing => existing.Id == waypoint.Id) is true;
        if (belongsToPlan && !TryUpdatePlan(plan => plan.RemoveWaypoint(waypoint.Id)))
        {
            return;
        }

        if (ReferenceEquals(ActiveWaypoint, waypoint))
        {
            ActiveWaypoint = null;
        }

        Waypoints.RemoveAt(index);
        CalculationRevision++;
        MarkChanged();
        RefreshPositions();
        AddWaypointCommand.NotifyCanExecuteChanged();
    }

    internal void Move(WaypointEditorItemViewModel waypoint, int newIndex)
    {
        var oldIndex = Waypoints.IndexOf(waypoint);
        if (oldIndex <= 0 || oldIndex >= Waypoints.Count - 1 ||
            newIndex <= 0 || newIndex >= Waypoints.Count - 1)
        {
            throw new InvalidOperationException("Only intermediate waypoints can be reordered.");
        }

        if (!TryUpdatePlan(plan => plan.MoveWaypoint(waypoint.Id, newIndex)))
        {
            return;
        }

        Waypoints.Move(oldIndex, newIndex);
        CalculationRevision++;
        MarkChanged();
        RefreshPositions();
    }

    internal void RenameWaypoint(WaypointEditorItemViewModel waypoint, string name)
    {
        if (_suppressChanges)
        {
            return;
        }

        TryUpdatePlan(plan => plan.RenameWaypoint(waypoint.Id, name));
        MarkChanged();
    }

    internal void ChangeCoordinate(WaypointEditorItemViewModel waypoint, Coordinate? coordinate)
    {
        if (_suppressChanges)
        {
            return;
        }

        if (coordinate is not null && _plan is not null)
        {
            if (_plan.Waypoints.Any(existing => existing.Id == waypoint.Id))
            {
                TryUpdatePlan(plan => plan.ChangeWaypointCoordinate(waypoint.Id, coordinate.Value));
            }
            else
            {
                var index = Waypoints.IndexOf(waypoint);
                TryUpdatePlan(plan => plan.AddWaypoint(
                    new RouteWaypoint(
                        waypoint.Id,
                        waypoint.Name,
                        coordinate.Value,
                        waypoint.GetStopover()),
                    index));
            }
        }
        else
        {
            ValidationMessage = null;
        }

        CalculationRevision++;
        MarkChanged();
        AddWaypointCommand.NotifyCanExecuteChanged();
    }

    internal void ChangeStopover(WaypointEditorItemViewModel waypoint)
    {
        if (_suppressChanges || !waypoint.IsIntermediate)
        {
            return;
        }

        if (_plan?.Waypoints.Any(existing => existing.Id == waypoint.Id) is true)
        {
            TryUpdatePlan(plan => plan.ChangeStopover(waypoint.Id, waypoint.GetStopover()));
        }

        CalculationRevision++;
        MarkChanged();
    }

    private void NewDraft()
    {
        _suppressChanges = true;
        try
        {
            PlanId = new RoutePlanId();
            CalculationRevision++;
            EditRevision++;
            _plan = null;
            RouteName = "Untitled route";
            SaveAsName = "Untitled route copy";
            Waypoints.Clear();
            Waypoints.Add(new WaypointEditorItemViewModel(
                this,
                new RouteWaypointId(),
                "Start",
                null,
                null));
            Waypoints.Add(new WaypointEditorItemViewModel(
                this,
                new RouteWaypointId(),
                "Finish",
                null,
                null));
            IsDirty = false;
            ResultsInvalidated = false;
            StorageError = null;
            ValidationMessage = null;
            ActiveWaypoint = null;
        }
        finally
        {
            _suppressChanges = false;
        }

        RefreshPositions();
        NotifyItineraryChanged();
    }

    private void Load(RoutePlan plan)
    {
        _suppressChanges = true;
        try
        {
            _plan = plan;
            PlanId = plan.Id;
            CalculationRevision++;
            EditRevision++;
            RouteName = plan.Name;
            SaveAsName = $"{plan.Name} copy";
            Waypoints.Clear();
            foreach (var waypoint in plan.Waypoints)
            {
                Waypoints.Add(new WaypointEditorItemViewModel(
                    this,
                    waypoint.Id,
                    waypoint.Name,
                    waypoint.Coordinate,
                    waypoint.Stopover));
            }

            IsDirty = false;
            ResultsInvalidated = plan.HasInvalidatedResults;
            StorageError = null;
            ValidationMessage = null;
            ActiveWaypoint = null;
        }
        finally
        {
            _suppressChanges = false;
        }

        RefreshPositions();
        NotifyItineraryChanged();
    }

    private bool TryUpdatePlan(Func<RoutePlan, RoutePlan> update)
    {
        if (_plan is null)
        {
            return true;
        }

        try
        {
            _plan = update(_plan);
            ResultsInvalidated = _plan.HasInvalidatedResults;
            ValidationMessage = null;
            return true;
        }
        catch (Exception exception)
        {
            ValidationMessage = exception.Message;
            return false;
        }
    }

    private void MarkChanged()
    {
        if (_suppressChanges)
        {
            return;
        }

        IsDirty = true;
        EditRevision++;
        NotifyItineraryChanged();
    }

    private void RefreshPositions()
    {
        foreach (var waypoint in Waypoints)
        {
            waypoint.RefreshPosition();
        }
    }

    private void NotifyItineraryChanged()
    {
        OnPropertyChanged(nameof(Start));
        OnPropertyChanged(nameof(Finish));
        OnPropertyChanged(nameof(HasPendingWaypoint));
        ItineraryChanged?.Invoke(this, EventArgs.Empty);
    }

    partial void OnRouteNameChanged(string value)
    {
        if (_suppressChanges)
        {
            return;
        }

        TryUpdatePlan(plan => plan.Rename(value));
        MarkChanged();
    }

    partial void OnSelectedSavedPlanChanged(RoutePlanSummary? value) =>
        OpenCommand.NotifyCanExecuteChanged();
}
