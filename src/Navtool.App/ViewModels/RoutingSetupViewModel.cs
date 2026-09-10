using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using Navtool.App.Services;
using Navtool.Core;
using System.Security.Cryptography;

namespace Navtool.App.ViewModels;

public sealed partial class RoutingSetupViewModel : ViewModelBase
{
    private readonly IBoatAssetService? _boats;
    private readonly RoutingLandSource _defaultLandSource;
    private readonly IRegionalLandPreviewService? _regionalPreview;
    private CancellationTokenSource? _previewCancellation;
    private long _previewGeneration;
    private bool _restoring;
    private long _assetGeneration;
    private long _landGeneration;
    private ulong _regionalMaximumGridNodes = 250_000;
    private ulong _regionalMaximumSourcePoints = 10_000_000;
    private ulong _regionalMaximumGeometryTests = 100_000_000;
    private int _regionalMaximumSubdivisionDepth = 12;
    private string _regionalAttribution = "GSHHG";
    private RouteMissingDataPolicy _regionalMissingDataPolicy = RouteMissingDataPolicy.FailRoute;

    public RoutingSetupViewModel(IBoatAssetService? boats = null,
        RoutingLandSource defaultLandSource = RoutingLandSource.NaturalEarth,
        IRegionalLandPreviewService? regionalPreview = null)
    {
        _boats = boats;
        _defaultLandSource = defaultLandSource;
        _landSource = defaultLandSource;
        _regionalPreview = regionalPreview;
    }

    public event EventHandler? SetupChanged;
    public IReadOnlyList<RoutingQuality> QualityOptions { get; } = Enum.GetValues<RoutingQuality>();
    public IReadOnlyList<BoatPolarFormat> PolarFormatOptions { get; } = Enum.GetValues<BoatPolarFormat>();
    public IReadOnlyList<RoutingLandSource> LandSourceOptions { get; } =
        [RoutingLandSource.NaturalEarth, RoutingLandSource.OpenStreetMap, RoutingLandSource.RegionalGshhg];
    public IReadOnlyList<ForecastRefreshPolicy> ForecastPolicyOptions { get; } = Enum.GetValues<ForecastRefreshPolicy>();

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(BoatStatus))]
    [NotifyPropertyChangedFor(nameof(BoatSummary))]
    [NotifyPropertyChangedFor(nameof(IsDemoBoat))]
    private BoatAsset? _boat;
    [ObservableProperty]
    private BoatPolarFormat _polarFormat = BoatPolarFormat.Automatic;
    [ObservableProperty]
    private RoutingQuality _quality = RoutingQuality.NativeBalanced;
    [ObservableProperty]
    private double _performancePercentage = 100;
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(ArrivalStatus))]
    private double _arrivalRadiusNauticalMiles = 1;
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(IsRegionalGshhg))]
    [NotifyPropertyChangedFor(nameof(LandSourceStatus))]
    private RoutingLandSource _landSource = RoutingLandSource.NaturalEarth;
    [ObservableProperty]
    private ForecastRefreshPolicy _forecastPolicy = ForecastRefreshPolicy.PreferCache;
    [ObservableProperty]
    private double _localForecastMaximumGapHours = 6;
    [ObservableProperty]
    private bool _useHardDuration;
    [ObservableProperty]
    private bool _enableCoastalPruning;
    [ObservableProperty]
    private double _hardDurationHours = 240;
    [ObservableProperty]
    private string? _regionalSourcePath;
    [ObservableProperty]
    private string? _regionalSourceIdentity;
    [ObservableProperty]
    private double _regionalSouth = 47;
    [ObservableProperty]
    private double _regionalNorth = 50;
    [ObservableProperty]
    private double _regionalWest = -126;
    [ObservableProperty]
    private double _regionalEast = -122;
    [ObservableProperty]
    private double _regionalSpacingNauticalMiles = 1;
    [ObservableProperty]
    private double _regionalClearanceNauticalMiles;
    [ObservableProperty]
    private double _regionalDistanceCapNauticalMiles = 60;
    [ObservableProperty]
    private string? _errorMessage;
    [ObservableProperty]
    private bool _isLoadingBoat;
    [ObservableProperty]
    private string? _resolvedStatus;
    [ObservableProperty]
    private bool _isPreviewingRegionalLand;
    [ObservableProperty]
    private string? _regionalPreviewStatus;

    public bool IsRegionalGshhg => LandSource == RoutingLandSource.RegionalGshhg;
    public string BoatSummary => Boat?.SourceDisplayName ?? "Choose your boat: import a polar or select the demo.";
    public bool IsDemoBoat => Boat?.Kind == BoatAssetKind.Demo;
    public string BoatStatus => Boat is null
        ? "No boat selected. Import a polar or explicitly choose the demonstration boat."
        : $"{(Boat.Kind == BoatAssetKind.Demo ? "DEMO · " : string.Empty)}{Boat.SourceDisplayName}\n" +
          $"{Boat.Validation.NativeMessage}\nAsset: {Boat.ContentIdentity}";
    public string ArrivalStatus =>
        $"Arrival within {ArrivalRadiusNauticalMiles:0.###} NM of the nominal waypoint. Actual model endpoints can differ.";
    public string LandSourceStatus => LandSource switch
    {
        RoutingLandSource.NaturalEarth => "Natural Earth polygons · required default source; verified before routing.",
        RoutingLandSource.OpenStreetMap => "OpenStreetMap polygons · requires the configured land endpoint; no silent substitution.",
        RoutingLandSource.RegionalGshhg => "Regional GSHHG · requires native capability, selected data and a bounded domain.",
        _ => "No land source selected."
    };

    public bool TryBuild(out RoutingSetup? setup, out string? error)
    {
        setup = null;
        if (Boat is null)
        {
            error = "Select a boat: import a polar or explicitly choose the labeled demonstration boat.";
            return false;
        }
        try
        {
            if (UseHardDuration && (!double.IsFinite(HardDurationHours) || HardDurationHours % 1 != 0))
                throw new ArgumentException("The native hard search duration must be whole hours; it is never rounded.");
            var regional = BuildRegionalPolicy();
            setup = new RoutingSetup(Boat, Quality, PerformancePercentage / 100,
                ArrivalRadiusNauticalMiles, LandSource, ForecastPolicy,
                hardDuration: UseHardDuration ? TimeSpan.FromHours(HardDurationHours) : null,
                localForecastMaximumGap: TimeSpan.FromHours(LocalForecastMaximumGapHours),
                regionalLand: regional,
                coastalPruning: EnableCoastalPruning
                    ? RouteCoastalPruningMode.ConservativeLandAware : RouteCoastalPruningMode.Off);
            error = null;
            return true;
        }
        catch (Exception exception) when (exception is ArgumentException or OverflowException)
        {
            error = $"Routing setup is invalid: {exception.Message}";
            return false;
        }
    }

    public void Restore(RoutingSetup? setup)
    {
        Interlocked.Increment(ref _assetGeneration);
        Interlocked.Increment(ref _landGeneration);
        ClearRegionalPreview();
        _restoring = true;
        try
        {
            Boat = setup?.Boat;
            Quality = setup?.Quality ?? RoutingQuality.NativeBalanced;
            EnableCoastalPruning = false;
            PerformancePercentage = (setup?.PerformanceFactor ?? 1) * 100;
            ArrivalRadiusNauticalMiles = setup?.ArrivalRadiusNauticalMiles ?? 1;
            LandSource = setup?.LandSource ?? _defaultLandSource;
            ForecastPolicy = setup?.ForecastPolicy ?? ForecastRefreshPolicy.PreferCache;
            LocalForecastMaximumGapHours = setup?.LocalForecastMaximumGap.TotalHours ?? 6;
            UseHardDuration = false;
            HardDurationHours = setup?.HardDuration?.TotalHours ?? 240;
            RegionalSourcePath = setup?.RegionalLand?.SourcePath;
            RegionalSourceIdentity = setup?.RegionalLand?.SourceIdentity;
            RegionalSouth = setup?.RegionalLand?.StudyBounds.South ?? 47;
            RegionalNorth = setup?.RegionalLand?.StudyBounds.North ?? 50;
            RegionalWest = setup?.RegionalLand?.StudyBounds.West ?? -126;
            RegionalEast = setup?.RegionalLand?.StudyBounds.East ?? -122;
            RegionalSpacingNauticalMiles = setup?.RegionalLand?.ResolutionNauticalMiles ?? 1;
            RegionalClearanceNauticalMiles = setup?.RegionalLand?.ClearanceNauticalMiles ?? 0;
            RegionalDistanceCapNauticalMiles = setup?.RegionalLand?.DistanceCapNauticalMiles ?? 60;
            _regionalMaximumGridNodes = setup?.RegionalLand?.MaximumGridNodes ?? 250_000;
            _regionalMaximumSourcePoints = setup?.RegionalLand?.MaximumSourcePoints ?? 10_000_000;
            _regionalMaximumGeometryTests = setup?.RegionalLand?.MaximumGeometryTests ?? 100_000_000;
            _regionalMaximumSubdivisionDepth = setup?.RegionalLand?.MaximumSubdivisionDepth ?? 12;
            _regionalAttribution = setup?.RegionalLand?.Attribution ?? "GSHHG";
            _regionalMissingDataPolicy = setup?.RegionalLand?.MissingDataPolicy ?? RouteMissingDataPolicy.FailRoute;
            IsLoadingBoat = false;
            ErrorMessage = null;
            ResolvedStatus = null;
        }
        finally { _restoring = false; }
    }

    public Task ImportBoatAsync(string path) => SelectBoatAsync(
        service => service.ImportAsync(path, PolarFormat));

    public RoutingSetupPreferences CapturePreferences()
    {
        var preferences = new RoutingSetupPreferences
        {
            Boat = Boat, Quality = Quality, PerformanceFactor = PerformancePercentage / 100,
            ArrivalRadiusNauticalMiles = ArrivalRadiusNauticalMiles, LandSource = LandSource,
            ForecastPolicy = ForecastPolicy, LocalForecastMaximumGapHours = LocalForecastMaximumGapHours,
            RegionalLand = BuildRegionalPolicy(), HardDurationHours = HardDurationHours
        };
        preferences.Validate();
        return preferences;
    }

    public void RestorePreferences(RoutingSetupPreferences preferences)
    {
        preferences.Validate();
        Restore(preferences.Boat is null ? null : new RoutingSetup(preferences.Boat,
            preferences.Quality, preferences.PerformanceFactor, preferences.ArrivalRadiusNauticalMiles,
            preferences.LandSource, preferences.ForecastPolicy,
            localForecastMaximumGap: TimeSpan.FromHours(preferences.LocalForecastMaximumGapHours),
            regionalLand: preferences.RegionalLand));
        _restoring = true;
        try
        {
            Quality = preferences.Quality;
            PerformancePercentage = preferences.PerformanceFactor * 100;
            ArrivalRadiusNauticalMiles = preferences.ArrivalRadiusNauticalMiles;
            LandSource = preferences.LandSource;
            ForecastPolicy = preferences.ForecastPolicy;
            LocalForecastMaximumGapHours = preferences.LocalForecastMaximumGapHours;
            HardDurationHours = preferences.HardDurationHours;
            if (preferences.RegionalLand is { } regional)
            {
                RegionalSourcePath = regional.SourcePath;
                RegionalSourceIdentity = regional.SourceIdentity;
                RegionalSouth = regional.StudyBounds.South;
                RegionalNorth = regional.StudyBounds.North;
                RegionalWest = regional.StudyBounds.West;
                RegionalEast = regional.StudyBounds.East;
                RegionalSpacingNauticalMiles = regional.ResolutionNauticalMiles;
                RegionalClearanceNauticalMiles = regional.ClearanceNauticalMiles;
                RegionalDistanceCapNauticalMiles = regional.DistanceCapNauticalMiles;
                _regionalMaximumGridNodes = regional.MaximumGridNodes;
                _regionalMaximumSourcePoints = regional.MaximumSourcePoints;
                _regionalMaximumGeometryTests = regional.MaximumGeometryTests;
                _regionalMaximumSubdivisionDepth = regional.MaximumSubdivisionDepth;
                _regionalAttribution = regional.Attribution;
                _regionalMissingDataPolicy = regional.MissingDataPolicy;
            }
        }
        finally { _restoring = false; }
    }

    private RouteRegionalLandPolicy? BuildRegionalPolicy() =>
        string.IsNullOrWhiteSpace(RegionalSourcePath) || string.IsNullOrWhiteSpace(RegionalSourceIdentity)
            ? null
            : new RouteRegionalLandPolicy(
                RegionalSourcePath, RegionalSourceIdentity,
                new GeographicBounds(RegionalSouth, RegionalNorth, RegionalWest, RegionalEast),
                RegionalSpacingNauticalMiles, RegionalClearanceNauticalMiles, RegionalDistanceCapNauticalMiles,
                _regionalMaximumGridNodes, _regionalMaximumSourcePoints, _regionalMaximumGeometryTests,
                _regionalMaximumSubdivisionDepth, _regionalAttribution, _regionalMissingDataPolicy);

    [RelayCommand]
    private async Task PreviewRegionalLand()
    {
        ClearRegionalPreview();
        ErrorMessage = null;
        var generation = Interlocked.Increment(ref _previewGeneration);
        var cancellation = new CancellationTokenSource();
        _previewCancellation = cancellation;
        IsPreviewingRegionalLand = true;
        try
        {
            var policy = BuildRegionalPolicy() ??
                throw new InvalidOperationException("Choose a GSHHG source before previewing its study domain.");
            if (_regionalPreview is null)
                throw new NotSupportedException("Native regional source preview is unavailable.");
            var preview = await _regionalPreview.PreviewAsync(policy, cancellation.Token);
            if (generation != Volatile.Read(ref _previewGeneration) || cancellation.IsCancellationRequested) return;
            if (preview.Policy != policy)
                throw new InvalidDataException("The regional preview does not match the selected source and domain.");
            var estimate = preview.Estimate;
            RegionalPreviewStatus =
                $"Native source validated · {estimate.LatitudeCount:N0} × {estimate.LongitudeCount:N0} = {estimate.GridNodes:N0} grid nodes\n" +
                $"Effective steps {estimate.LatitudeStepDegrees:0.######}° latitude / {estimate.LongitudeStepDegrees:0.######}° longitude\n" +
                $"Native full-cell numerical allowance {estimate.NativeNumericalAllowanceNauticalMiles:0.###} NM · " +
                $"selected clearance {policy.ClearanceNauticalMiles:0.###} NM\n" +
                $"Halo latitude {estimate.HaloSouth:0.###}° to {estimate.HaloNorth:0.###}°, " +
                $"unwrapped longitude {estimate.HaloWestUnwrapped:0.###}° to {estimate.HaloEastUnwrapped:0.###}°\n" +
                "Source completeness is not certified. The explicit study domain restricts routing; forecast downloads have not started.";
        }
        catch (OperationCanceledException) when (cancellation.IsCancellationRequested) { }
        catch (Exception exception)
        {
            if (generation == Volatile.Read(ref _previewGeneration)) ErrorMessage = exception.Message;
        }
        finally
        {
            if (generation == Volatile.Read(ref _previewGeneration))
            {
                IsPreviewingRegionalLand = false;
                _previewCancellation = null;
            }
            cancellation.Dispose();
        }
    }

    private void ClearRegionalPreview()
    {
        Interlocked.Increment(ref _previewGeneration);
        Interlocked.Exchange(ref _previewCancellation, null)?.Cancel();
        IsPreviewingRegionalLand = false;
        RegionalPreviewStatus = null;
    }

    public async Task SelectRegionalSourceAsync(string path)
    {
        var generation = Interlocked.Increment(ref _landGeneration);
        ErrorMessage = null;
        try
        {
            var absolute = Path.GetFullPath(path);
            await using var stream = File.OpenRead(absolute);
            var fingerprint = Convert.ToHexString(await SHA256.HashDataAsync(stream)).ToLowerInvariant();
            if (generation != Volatile.Read(ref _landGeneration)) return;
            RegionalSourcePath = absolute;
            RegionalSourceIdentity = fingerprint;
        }
        catch (Exception exception)
        {
            if (generation == Volatile.Read(ref _landGeneration)) ErrorMessage = exception.Message;
        }
    }

    [RelayCommand]
    private Task SelectDemo() => SelectBoatAsync(service => service.GetDemoAsync());

    [RelayCommand]
    private void ClearBoat()
    {
        Interlocked.Increment(ref _assetGeneration);
        IsLoadingBoat = false;
        Boat = null;
    }

    private async Task SelectBoatAsync(Func<IBoatAssetService, ValueTask<BoatAsset>> select)
    {
        var generation = Interlocked.Increment(ref _assetGeneration);
        ErrorMessage = null;
        if (_boats is null)
        {
            ErrorMessage = "Native boat validation and asset storage are unavailable.";
            return;
        }
        IsLoadingBoat = true;
        try
        {
            var boat = await select(_boats);
            if (generation == Volatile.Read(ref _assetGeneration)) Boat = boat;
        }
        catch (Exception exception)
        {
            if (generation == Volatile.Read(ref _assetGeneration)) ErrorMessage = exception.Message;
        }
        finally
        {
            if (generation == Volatile.Read(ref _assetGeneration)) IsLoadingBoat = false;
        }
    }

    private void Changed()
    {
        if (_restoring) return;
        ClearRegionalPreview();
        ResolvedStatus = null;
        SetupChanged?.Invoke(this, EventArgs.Empty);
    }

    partial void OnBoatChanged(BoatAsset? value) => Changed();
    partial void OnQualityChanged(RoutingQuality value) => Changed();
    partial void OnEnableCoastalPruningChanged(bool value) => Changed();
    partial void OnPerformancePercentageChanged(double value) => Changed();
    partial void OnArrivalRadiusNauticalMilesChanged(double value) => Changed();
    partial void OnLandSourceChanged(RoutingLandSource value) => Changed();
    partial void OnForecastPolicyChanged(ForecastRefreshPolicy value) => Changed();
    partial void OnLocalForecastMaximumGapHoursChanged(double value) => Changed();
    partial void OnUseHardDurationChanged(bool value) => Changed();
    partial void OnHardDurationHoursChanged(double value) => Changed();
    partial void OnRegionalSourcePathChanged(string? value) => Changed();
    partial void OnRegionalSourceIdentityChanged(string? value) => Changed();
    partial void OnRegionalSouthChanged(double value) => Changed();
    partial void OnRegionalNorthChanged(double value) => Changed();
    partial void OnRegionalWestChanged(double value) => Changed();
    partial void OnRegionalEastChanged(double value) => Changed();
    partial void OnRegionalSpacingNauticalMilesChanged(double value) => Changed();
    partial void OnRegionalClearanceNauticalMilesChanged(double value) => Changed();
    partial void OnRegionalDistanceCapNauticalMilesChanged(double value) => Changed();
}
