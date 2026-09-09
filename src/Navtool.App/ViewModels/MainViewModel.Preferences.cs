using CommunityToolkit.Mvvm.ComponentModel;
using Microsoft.Extensions.Logging;
using Navtool.App.Services;
using Navtool.Core;

namespace Navtool.App.ViewModels;

public partial class MainViewModel
{
    private IRoutingPreferencesRepository? _preferencesRepository;
    private RoutingUserPreferences _preferences = new();

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(IsScheduledDeparture))]
    private bool _departureNow = true;

    [ObservableProperty]
    private string _preferenceStatus = "Routing preferences are session-only.";

    [ObservableProperty]
    private string? _preferenceError;

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(LocalGribDisplay))]
    [NotifyCanExecuteChangedFor(nameof(CalculateCommand))]
    [NotifyCanExecuteChangedFor(nameof(ForceRecalculateCommand))]
    private string? _localGribPath;

    public bool IsScheduledDeparture => !DepartureNow;

    partial void OnDepartureNowChanged(bool value)
    {
        UpdateDepartureUtcPreview();
        UpdateForecastAreaSummary();
    }

    private void InitializePreferences(IRoutingPreferencesRepository? repository)
    {
        _preferencesRepository = repository;
        _preferences = new RoutingUserPreferences { Setup = RoutingSetup.CapturePreferences() };
        if (repository is not null)
        {
            try
            {
                var loaded = repository.Load();
                _preferences = loaded ?? _preferences;
                PreferenceStatus = loaded is null
                    ? "No saved routing preferences yet. Choose a boat; valid settings will be remembered."
                    : "Routing preferences restored. Advanced overrides are off.";
                if (loaded is null) _logger.LogInformation("No saved routing preferences; awaiting explicit boat selection");
            }
            catch (Exception exception) when (IsPreferenceFailure(exception))
            {
                PreferenceError = exception.Message;
                PreferenceStatus = "Routing preferences could not be restored.";
                _logger.LogWarning(exception, "Could not restore routing preferences");
            }
        }
        RestorePlanningState();
    }

    private static bool IsPreferenceFailure(Exception exception) =>
        exception is IOException or UnauthorizedAccessException or ArgumentException or
            System.Text.Json.JsonException or NotSupportedException or OverflowException or System.Security.SecurityException;

    private void RestorePlanningState()
    {
        _restoringRoutingInputs = true;
        try
        {
            if (Itinerary.IsNewDraft || Itinerary.RoutingSetup is null)
            {
                RoutingSetup.RestorePreferences(_preferences.Setup);
                RoutingSetup.TryBuild(out var setup, out _);
                if (Itinerary.IsNewDraft) Itinerary.SetDraftSetup(setup);
            }
            else
            {
                RoutingSetup.Restore(Itinerary.RoutingSetup);
            }
            RestoreAdvancedPreferences(_preferences.Advanced);
            EnableProfessionalRouting = false;
            EnableCurrentField = false;
            EnableSeaState = false;
            EnableAntarcticExclusionZone = false;
            UseMaximumTrueWindSpeed = false;
            UseNewestWeatherData = false;
            WeatherOnlyMode = false;
            var inputs = Itinerary.PlanningInputs ?? _preferences.Planning;
            DepartureNow = inputs.DepartureNow;
            var local = TimeZoneInfo.ConvertTime(inputs.ScheduledDepartureUtc ?? _timeProvider.GetUtcNow(), _localTimeZone);
            DepartureDate = new DateTimeOffset(local.Date, local.Offset);
            DepartureTime = local.TimeOfDay;
            PassageDays = inputs.PassageDays;
            PassageHours = inputs.PassageHours;
            ForecastInputMode = inputs.ForecastSource == PlanningForecastSource.LocalFile
                ? ForecastInputMode.LocalFile : ForecastInputMode.Download;
            UseNoaa = inputs.UseNoaa;
            UseEcmwf = inputs.UseEcmwf;
            Interlocked.Exchange(ref _inspectionCancellation, null)?.Cancel();
            IsInspectingLocalGrib = false;
            LocalForecast = null;
            LocalGribPath = inputs.LocalGribPath;
            LocalGribStatus = LocalGribPath is null ? "Choose a GRIB file to inspect."
                : "Saved GRIB selection will be inspected when you explicitly calculate.";
            if (Itinerary.IsNewDraft) Itinerary.SetPlanningInputs(inputs, restoring: true);
            Itinerary.PlanningInputError = null;
            UpdateDepartureUtcPreview();
        }
        finally { _restoringRoutingInputs = false; }
    }

    private RoutePlanningInputs CapturePlanningInputs()
    {
        DateTimeOffset? scheduled = null;
        if (!DepartureNow)
        {
            if (!LocalDepartureConverter.TryConvertToUtc(DepartureDate, DepartureTime, _localTimeZone,
                    out var utc, out var error))
                throw new ArgumentException(error);
            scheduled = utc;
        }
        var inputs = new RoutePlanningInputs
        {
            DepartureNow = DepartureNow, ScheduledDepartureUtc = scheduled,
            PassageDays = PassageDays, PassageHours = PassageHours,
            ForecastSource = ForecastInputMode == ForecastInputMode.LocalFile
                ? PlanningForecastSource.LocalFile : PlanningForecastSource.Download,
            UseNoaa = UseNoaa, UseEcmwf = UseEcmwf, LocalGribPath = LocalGribPath
        };
        inputs.Validate();
        return inputs;
    }

    private void SavePlanningEdits(bool persistDefaults = true)
    {
        if (_restoringRoutingInputs) return;
        try
        {
            var inputs = CapturePlanningInputs();
            Itinerary.PlanningInputError = null;
            Itinerary.SetPlanningInputs(inputs);
        }
        catch (Exception exception) when (exception is ArgumentException or OverflowException)
        {
            Itinerary.PlanningInputError = exception.Message;
        }
        if (!persistDefaults) return;
        try
        {
            // A route's absolute schedule never becomes a default for the next passage.
            var planning = new RoutePlanningInputs
            {
                PassageDays = PassageDays, PassageHours = PassageHours,
                ForecastSource = ForecastInputMode == ForecastInputMode.LocalFile
                    ? PlanningForecastSource.LocalFile : PlanningForecastSource.Download,
                UseNoaa = UseNoaa, UseEcmwf = UseEcmwf, LocalGribPath = LocalGribPath
            };
            var candidate = new RoutingUserPreferences
            {
                Setup = RoutingSetup.CapturePreferences(), Planning = planning,
                Advanced = CaptureAdvancedPreferences()
            };
            candidate.Validate();
            _preferencesRepository?.Save(candidate);
            _preferences = candidate;
            PreferenceError = null;
            PreferenceStatus = _preferencesRepository is null
                ? "Valid routing settings remembered for this session."
                : "Routing preferences saved.";
        }
        catch (Exception exception) when (exception is ArgumentException or OverflowException)
        {
            PreferenceStatus = "Incomplete or invalid edits are not saved; previous valid preferences retained.";
        }
        catch (Exception exception) when (IsPreferenceFailure(exception))
        {
            PreferenceError = exception.Message;
            PreferenceStatus = "Routing preferences could not be saved.";
            _logger.LogWarning(exception, "Could not save routing preferences");
        }
    }

    private AdvancedRoutingPreferences CaptureAdvancedPreferences() => new()
    {
        SelectedRouteSolver = SelectedRouteSolver,
        TackPenaltySeconds = TackPenaltySeconds, GybePenaltySeconds = GybePenaltySeconds,
        DownwindTrueWindAngleDegrees = DownwindTrueWindAngleDegrees,
        HeadingAugmentation = HeadingAugmentation, WindSampling = WindSampling,
        MidpointWindSamplingThresholdMinutes = MidpointWindSamplingThresholdMinutes,
        PolarAngleInterpolation = PolarAngleInterpolation, MaximumTrueWindSpeedKnots = MaximumTrueWindSpeedKnots,
        AbovePolarRange = AbovePolarRange, PruningStrategy = PruningStrategy, PruningSectorDegrees = PruningSectorDegrees,
        DestinationFrontHalfAngleDegrees = DestinationFrontHalfAngleDegrees,
        DestinationFrontSegmentPolicy = DestinationFrontSegmentPolicy,
        DestinationFrontMinimumSecondarySegmentPoints = DestinationFrontMinimumSecondarySegmentPoints,
        LatticeSubdivisionLevel = LatticeSubdivisionLevel, LatticeTimeBucketMinutes = LatticeTimeBucketMinutes,
        LatticeRefinementLevels = LatticeRefinementLevels, LatticeCorridorWidthNauticalMiles = LatticeCorridorWidthNauticalMiles,
        LatticeCorridorWideningRetries = LatticeCorridorWideningRetries,
        LatticeProgressEveryExpansions = LatticeProgressEveryExpansions, LatticeSearchAlgorithm = LatticeSearchAlgorithm,
        CurrentEastKnots = CurrentEastKnots, CurrentNorthKnots = CurrentNorthKnots,
        CurrentMissingDataPolicy = CurrentMissingDataPolicy, SignificantWaveHeightMetres = SignificantWaveHeightMetres,
        WavePeriodSeconds = WavePeriodSeconds, WaveFromDirectionDegrees = WaveFromDirectionDegrees,
        WaveMissingDataPolicy = WaveMissingDataPolicy, LandAvoidanceMode = LandAvoidanceMode,
        LandmaskResolutionNauticalMiles = LandmaskResolutionNauticalMiles,
        LandmaskClearanceNauticalMiles = LandmaskClearanceNauticalMiles,
        LandmaskMaximumSubdivisionDepth = LandmaskMaximumSubdivisionDepth,
        LandmaskMissingDataPolicy = LandmaskMissingDataPolicy, ExclusionBoundaryPolicy = ExclusionBoundaryPolicy,
        EnvironmentSampling = EnvironmentSampling
    };

    private void RestoreAdvancedPreferences(AdvancedRoutingPreferences p)
    {
        SelectedRouteSolver = p.SelectedRouteSolver;
        TackPenaltySeconds = p.TackPenaltySeconds;
        GybePenaltySeconds = p.GybePenaltySeconds;
        DownwindTrueWindAngleDegrees = p.DownwindTrueWindAngleDegrees;
        HeadingAugmentation = p.HeadingAugmentation;
        WindSampling = p.WindSampling;
        MidpointWindSamplingThresholdMinutes = p.MidpointWindSamplingThresholdMinutes;
        PolarAngleInterpolation = p.PolarAngleInterpolation;
        MaximumTrueWindSpeedKnots = p.MaximumTrueWindSpeedKnots;
        AbovePolarRange = p.AbovePolarRange;
        PruningStrategy = p.PruningStrategy;
        PruningSectorDegrees = p.PruningSectorDegrees;
        DestinationFrontHalfAngleDegrees = p.DestinationFrontHalfAngleDegrees;
        DestinationFrontSegmentPolicy = p.DestinationFrontSegmentPolicy;
        DestinationFrontMinimumSecondarySegmentPoints = p.DestinationFrontMinimumSecondarySegmentPoints;
        LatticeSubdivisionLevel = p.LatticeSubdivisionLevel;
        LatticeTimeBucketMinutes = p.LatticeTimeBucketMinutes;
        LatticeRefinementLevels = p.LatticeRefinementLevels;
        LatticeCorridorWidthNauticalMiles = p.LatticeCorridorWidthNauticalMiles;
        LatticeCorridorWideningRetries = p.LatticeCorridorWideningRetries;
        LatticeProgressEveryExpansions = p.LatticeProgressEveryExpansions;
        LatticeSearchAlgorithm = p.LatticeSearchAlgorithm;
        CurrentEastKnots = p.CurrentEastKnots;
        CurrentNorthKnots = p.CurrentNorthKnots;
        CurrentMissingDataPolicy = p.CurrentMissingDataPolicy;
        SignificantWaveHeightMetres = p.SignificantWaveHeightMetres;
        WavePeriodSeconds = p.WavePeriodSeconds;
        WaveFromDirectionDegrees = p.WaveFromDirectionDegrees;
        WaveMissingDataPolicy = p.WaveMissingDataPolicy;
        LandAvoidanceMode = p.LandAvoidanceMode;
        LandmaskResolutionNauticalMiles = p.LandmaskResolutionNauticalMiles;
        LandmaskClearanceNauticalMiles = p.LandmaskClearanceNauticalMiles;
        LandmaskMaximumSubdivisionDepth = p.LandmaskMaximumSubdivisionDepth;
        LandmaskMissingDataPolicy = p.LandmaskMissingDataPolicy;
        ExclusionBoundaryPolicy = p.ExclusionBoundaryPolicy;
        EnvironmentSampling = p.EnvironmentSampling;
    }
}
