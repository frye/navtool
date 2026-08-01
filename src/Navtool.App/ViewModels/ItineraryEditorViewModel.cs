using System.Collections.ObjectModel;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using Navtool.App.Services;
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

/// <summary>
/// Displays a single itinerary leg's sailed/active state and exposes the mark/unmark-sailed and
/// explicit-active-leg commands. Sailed is real-world itinerary progress: it is model-independent
/// and never validates or depends on forecast data.
/// </summary>
public sealed partial class RouteLegEditorItemViewModel : ViewModelBase
{
    private readonly ItineraryEditorViewModel _owner;

    internal RouteLegEditorItemViewModel(
        ItineraryEditorViewModel owner,
        RouteLegId id,
        int index,
        string fromName,
        string toName,
        string outcomeStatus)
    {
        _owner = owner;
        Id = id;
        Index = index;
        FromName = fromName;
        ToName = toName;
        OutcomeStatus = outcomeStatus;
    }

    public RouteLegId Id { get; }

    public int Index { get; }

    public string FromName { get; }

    public string ToName { get; }

    public string Label => $"Leg {Index + 1}: {FromName} \u2192 {ToName}";

    public string OutcomeStatus { get; }

    [ObservableProperty]
    [NotifyCanExecuteChangedFor(nameof(MarkSailedCommand))]
    [NotifyCanExecuteChangedFor(nameof(UnmarkSailedCommand))]
    [NotifyCanExecuteChangedFor(nameof(MakeActiveCommand))]
    private bool _isSailed;

    [ObservableProperty]
    [NotifyCanExecuteChangedFor(nameof(MakeActiveCommand))]
    private bool _isActive;

    [ObservableProperty]
    private bool _isSelected;

    public string StatusLabel => IsSailed ? "Sailed" : IsActive ? "Active" : "Upcoming";

    [RelayCommand]
    private void Select() => _owner.SelectLeg(Id);

    [RelayCommand(CanExecute = nameof(CanMarkSailed))]
    private void MarkSailed() => _owner.MarkLegSailed(Id);

    private bool CanMarkSailed() => !IsSailed;

    [RelayCommand(CanExecute = nameof(CanUnmarkSailed))]
    private void UnmarkSailed() => _owner.UnmarkLegSailed(Id);

    private bool CanUnmarkSailed() => IsSailed;

    [RelayCommand(CanExecute = nameof(CanMakeActive))]
    private void MakeActive() => _owner.SetActiveLeg(Id);

    private bool CanMakeActive() => !IsSailed && !IsActive;
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

    [ObservableProperty]
    private bool _isAwaitingCurrentPositionPlacement;

    [ObservableProperty]
    private DateTimeOffset? _currentPositionDepartureDate = DateTimeOffset.Now.Date;

    [ObservableProperty]
    private TimeSpan? _currentPositionDepartureTimeOfDay = DateTimeOffset.Now.TimeOfDay;

    public RoutePlanId PlanId { get; private set; }

    public long CalculationRevision { get; private set; }

    public long EditRevision { get; private set; }

    public event EventHandler? ItineraryChanged;

    public event EventHandler<WaypointEditorItemViewModel>? MapPlacementStarted;

    public event EventHandler? CurrentPositionPlacementStarted;

    public event EventHandler<RouteLegId>? LegSelected;

    public ObservableCollection<RouteLegEditorItemViewModel> Legs { get; } = [];

    public RoutePlan? CurrentPlan => _plan;

    public Coordinate? Start => Waypoints.FirstOrDefault()?.Coordinate;

    public Coordinate? Finish => Waypoints.LastOrDefault()?.Coordinate;

    public bool HasPendingWaypoint => Waypoints.Any(waypoint => waypoint.Coordinate is null);

    /// <summary>
    /// The user-placed current position, distinct from any itinerary waypoint. Null when the
    /// itinerary should be routed from its start (no session in progress).
    /// </summary>
    public Coordinate? CurrentPositionCoordinate => _plan?.CurrentPosition?.Coordinate;

    public DateTimeOffset? CurrentPositionDepartureTimeUtc => _plan?.CurrentPosition?.DepartureTime;

    public bool HasCurrentPosition => _plan?.CurrentPosition is not null;

    public string CurrentPositionDisplay => CurrentPositionCoordinate is not { } coordinate
        ? "Not set"
        : $"{Math.Abs(coordinate.Latitude):0.000}\u00b0 " +
          $"{(coordinate.Latitude >= 0 ? "N" : "S")}, " +
          $"{Math.Abs(coordinate.Longitude):0.000}\u00b0 " +
          $"{(coordinate.Longitude >= 0 ? "E" : "W")}";

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

        IsAwaitingCurrentPositionPlacement = false;
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

    /// <summary>
    /// Arms the distinct current-position map placement mode. This is never confused with
    /// itinerary waypoint placement: it records a session-scoped "where the vessel is now"
    /// marker, not a permanent route point.
    /// </summary>
    public void BeginCurrentPositionPlacement()
    {
        ActiveWaypoint = null;
        IsAwaitingCurrentPositionPlacement = true;
        CurrentPositionPlacementStarted?.Invoke(this, EventArgs.Empty);
    }

    public void CancelCurrentPositionPlacement() => IsAwaitingCurrentPositionPlacement = false;

    /// <summary>
    /// Places the current position at the given coordinate with an explicit departure time (UTC).
    /// Never derived from wall-clock or GPS; always the user-supplied session values.
    /// </summary>
    public bool PlaceCurrentPosition(Coordinate coordinate, DateTimeOffset departureTimeUtc, out string? error)
    {
        IsAwaitingCurrentPositionPlacement = false;
        var applied = TryUpdatePlanEnsuringBuilt(
            plan => plan.SetCurrentPosition(coordinate, departureTimeUtc),
            out error);
        if (applied)
        {
            NotifyCurrentPositionChanged();
            CalculationRevision++;
            MarkChanged();
        }

        return applied;
    }

    /// <summary>
    /// Places the current position using the local <see cref="CurrentPositionDepartureDate"/>/
    /// <see cref="CurrentPositionDepartureTimeOfDay"/> fields, converted to UTC via
    /// <paramref name="localTimeZone"/>. This is the explicit, user-supplied departure time for
    /// the current position; it is never derived from wall clock or GPS.
    /// </summary>
    public bool TryPlaceCurrentPosition(Coordinate coordinate, TimeZoneInfo localTimeZone, out string? error)
    {
        if (!LocalDepartureConverter.TryConvertToUtc(
                CurrentPositionDepartureDate,
                CurrentPositionDepartureTimeOfDay,
                localTimeZone,
                out var departureUtc,
                out error))
        {
            IsAwaitingCurrentPositionPlacement = false;
            return false;
        }

        return PlaceCurrentPosition(coordinate, departureUtc, out error);
    }

    public void ClearCurrentPosition()
    {
        if (_plan?.CurrentPosition is null)
        {
            return;
        }

        if (TryUpdatePlan(plan => plan.ClearCurrentPosition()))
        {
            NotifyCurrentPositionChanged();
            CalculationRevision++;
            MarkChanged();
        }
    }

    internal void MarkLegSailed(RouteLegId legId)
    {
        if (TryUpdatePlanEnsuringBuilt(plan => plan.MarkSailed(legId), out _))
        {
            CalculationRevision++;
            MarkChanged();
        }
    }

    internal void UnmarkLegSailed(RouteLegId legId)
    {
        if (TryUpdatePlanEnsuringBuilt(plan => plan.UnmarkSailed(legId), out _))
        {
            CalculationRevision++;
            MarkChanged();
        }
    }

    /// <summary>
    /// Explicitly selects the active leg to resume from, overriding the default (first
    /// unfinished/unsailed leg). The leg must exist and must not already be sailed.
    /// </summary>
    internal void SetActiveLeg(RouteLegId legId)
    {
        if (TryUpdatePlanEnsuringBuilt(plan => plan.SetActiveLeg(legId), out _))
        {
            CalculationRevision++;
            MarkChanged();
        }
    }

    internal void ClearActiveLeg()
    {
        if (_plan?.ActiveLegId is null)
        {
            return;
        }

        if (TryUpdatePlan(plan => plan.ClearActiveLeg()))
        {
            CalculationRevision++;
            MarkChanged();
        }
    }

    internal void SelectLeg(RouteLegId legId) => LegSelected?.Invoke(this, legId);

    public void SetSelectedLeg(RouteLegId? legId)
    {
        foreach (var leg in Legs)
        {
            leg.IsSelected = leg.Id == legId;
        }
    }

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
        if (_repository is null)
        {
            StorageError = "Route plan storage is unavailable.";
            return;
        }

        if (SelectedSavedPlan is null)
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

    private bool CanOpen() => _repository is not null && SelectedSavedPlan is not null;

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
                RefreshLegs();
                NotifyCurrentPositionChanged();
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
                        _plan.SailedLegIds,
                        _plan.CurrentPosition,
                        _plan.ActiveLegId);
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

    public void AcceptCalculationResult(RoutePlan plan)
    {
        ArgumentNullException.ThrowIfNull(plan);
        if (!TryBuildPlan(out var current, out var error))
        {
            throw new InvalidOperationException(error);
        }

        if (plan.Id != PlanId || !plan.Waypoints.SequenceEqual(current!.Waypoints))
        {
            throw new InvalidOperationException(
                "The calculation result does not match the current itinerary.");
        }

        _plan = plan;
        ResultsInvalidated = plan.HasInvalidatedResults;
        IsDirty = false;
        StorageError = null;
        RefreshLegs();
        NotifyCurrentPositionChanged();
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
            IsAwaitingCurrentPositionPlacement = false;
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
            IsAwaitingCurrentPositionPlacement = false;
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

    /// <summary>
    /// Like <see cref="TryUpdatePlan"/>, but builds the plan from the current waypoints first if
    /// one does not exist yet. Used for state (current position, sailed legs, active leg) that
    /// the user can set even before the itinerary has ever been calculated or saved.
    /// </summary>
    private bool TryUpdatePlanEnsuringBuilt(Func<RoutePlan, RoutePlan> update, out string? error)
    {
        if (_plan is null && !TryBuildPlan(out _plan, out error))
        {
            return false;
        }

        try
        {
            _plan = update(_plan!);
            ResultsInvalidated = _plan.HasInvalidatedResults;
            ValidationMessage = null;
            error = null;
            return true;
        }
        catch (Exception exception)
        {
            error = exception.Message;
            ValidationMessage = error;
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

    /// <summary>
    /// Rebuilds the <see cref="Legs"/> collection from the current plan, reflecting each leg's
    /// sailed/active state. Called whenever the plan's legs, sailed set, or active leg changes.
    /// </summary>
    private void RefreshLegs()
    {
        Legs.Clear();
        var planForLegs = _plan;
        if (planForLegs is null)
        {
            // Sailed/active-leg state is model-independent and must be settable even before the
            // itinerary has ever been calculated or saved, so speculatively build a plan here
            // (without persisting it to `_plan`) purely to enumerate legs. Restore
            // ValidationMessage afterward so an incomplete itinerary in progress doesn't surface
            // a spurious "set every waypoint" validation error.
            var previousValidationMessage = ValidationMessage;
            if (TryBuildPlan(out var built, out _))
            {
                planForLegs = built;
            }

            ValidationMessage = previousValidationMessage;
        }

        if (planForLegs is null)
        {
            return;
        }

        var activeIndex = planForLegs.ActiveLegIndex;
        foreach (var leg in planForLegs.Legs)
        {
            var from = planForLegs.Waypoints.Single(waypoint => waypoint.Id == leg.FromWaypointId);
            var to = planForLegs.Waypoints.Single(waypoint => waypoint.Id == leg.ToWaypointId);
            var outcomes = planForLegs.Results
                .Select(result =>
                {
                    var outcome = result.Legs.Single(item => item.LegId == leg.Id);
                    return $"{ModelShortName(result.Model)} {OutcomeStatusName(outcome)}";
                })
                .ToArray();
            Legs.Add(new RouteLegEditorItemViewModel(
                this,
                leg.Id,
                leg.Index,
                from.Name,
                to.Name,
                outcomes.Length == 0 ? "not calculated" : string.Join(" · ", outcomes))
            {
                IsSailed = planForLegs.SailedLegIds.Contains(leg.Id),
                IsActive = leg.Index == activeIndex
            });
        }

    }

    private static string ModelShortName(ForecastModel model) =>
        model == ForecastModel.NoaaGfs ? "NOAA" : "ECMWF";

    private static string OutcomeStatusName(RouteLegResult outcome) => outcome.State switch
    {
        RouteLegOutcomeState.Succeeded
            when outcome.Reason == RouteLegOutcomeReason.ForecastExhausted => "forecast-limited",
        RouteLegOutcomeState.Succeeded => "complete",
        RouteLegOutcomeState.Failed => "failed",
        RouteLegOutcomeState.Cancelled => "cancelled",
        RouteLegOutcomeState.Blocked => "blocked",
        RouteLegOutcomeState.OutsideForecastWindow => "outside window",
        RouteLegOutcomeState.Invalidated => "stale",
        _ => "not calculated"
    };

    private void NotifyCurrentPositionChanged()
    {
        OnPropertyChanged(nameof(CurrentPositionCoordinate));
        OnPropertyChanged(nameof(CurrentPositionDepartureTimeUtc));
        OnPropertyChanged(nameof(HasCurrentPosition));
        OnPropertyChanged(nameof(CurrentPositionDisplay));
    }

    private void NotifyItineraryChanged()
    {
        RefreshLegs();
        NotifyCurrentPositionChanged();
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
