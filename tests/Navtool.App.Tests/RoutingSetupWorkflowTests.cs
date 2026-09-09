using Avalonia.Controls;
using Avalonia.Headless.XUnit;
using Navtool.App.Models;
using Navtool.App.Services;
using Navtool.App.ViewModels;
using Navtool.App.Views;
using Navtool.Core;
using Navtool.Infrastructure;

namespace Navtool.App.Tests;

public sealed class RoutingSetupWorkflowTests
{
    private static readonly DateTimeOffset Now = new(2026, 9, 7, 12, 0, 0, TimeSpan.Zero);

    [Fact]
    public async Task Valid_preferences_survive_restart_and_new_draft_without_silent_boat_or_advanced_activation()
    {
        var root = Path.Combine(Path.GetTempPath(), $"navtool-user-preferences-{Guid.NewGuid():N}");
        try
        {
            var repository = new RoutingPreferencesJsonRepository(root);
            var vm = Create(new CountingProvider(), new TestRoutingSetupService(), chooseBoat: false,
                preferences: repository);
            Assert.Null(vm.RoutingSetup.Boat);
            Assert.Contains("No saved", vm.PreferenceStatus);
            await vm.RoutingSetup.SelectDemoCommand.ExecuteAsync(null);
            vm.RoutingSetup.Quality = RoutingQuality.NativeAccurate;
            vm.RoutingSetup.PerformancePercentage = 87;
            vm.RoutingSetup.ArrivalRadiusNauticalMiles = 0.5;
            vm.RoutingSetup.ForecastPolicy = ForecastRefreshPolicy.LatestAvailable;
            vm.RoutingSetup.LandSource = RoutingLandSource.OpenStreetMap;
            vm.PassageDays = 4;
            vm.PassageHours = 6;
            vm.UseEcmwf = true;
            vm.EnableProfessionalRouting = true;
            vm.TackPenaltySeconds = 95;
            vm.CurrentEastKnots = 1.5;
            vm.EnableCurrentField = true;
            vm.RoutingSetup.HardDurationHours = 192;
            vm.RoutingSetup.UseHardDuration = true;
            vm.RoutingSetup.EnableCoastalPruning = true;
            vm.DepartureNow = false;
            vm.DepartureDate = Now.AddDays(1);
            vm.DepartureTime = TimeSpan.FromHours(18);
            Assert.Null(vm.PreferenceError);
            Assert.Equal("Routing preferences saved.", vm.PreferenceStatus);

            var restarted = Create(new CountingProvider(), new TestRoutingSetupService(), chooseBoat: false,
                preferences: new RoutingPreferencesJsonRepository(root));
            foreach (var restored in new[] { restarted, vm })
            {
                restored.Itinerary.NewCommand.Execute(null);
                Assert.Equal(TestRoutingSetupService.Demo, restored.RoutingSetup.Boat);
                Assert.Equal(87, restored.RoutingSetup.PerformancePercentage);
                Assert.Equal(RoutingQuality.NativeAccurate, restored.RoutingSetup.Quality);
                Assert.Equal(0.5, restored.RoutingSetup.ArrivalRadiusNauticalMiles);
                Assert.Equal(ForecastRefreshPolicy.LatestAvailable, restored.RoutingSetup.ForecastPolicy);
                Assert.Equal(RoutingLandSource.OpenStreetMap, restored.RoutingSetup.LandSource);
                Assert.Equal(4, restored.PassageDays);
                Assert.Equal(6, restored.PassageHours);
                Assert.True(restored.UseEcmwf);
                Assert.True(restored.DepartureNow);
                Assert.False(restored.EnableProfessionalRouting);
                Assert.False(restored.EnableCurrentField);
                Assert.False(restored.RoutingSetup.UseHardDuration);
                Assert.False(restored.RoutingSetup.EnableCoastalPruning);
                Assert.Equal(192, restored.RoutingSetup.HardDurationHours);
                Assert.Equal(95, restored.TackPenaltySeconds);
                Assert.Equal(1.5, restored.CurrentEastKnots);
                Assert.False(restored.Itinerary.IsDirty);
            }
        }
        finally { if (Directory.Exists(root)) Directory.Delete(root, true); }
    }

    [Fact]
    public async Task Opening_route_restores_its_inputs_without_writing_preferences_or_reactivating_experiments()
    {
        var root = Path.Combine(Path.GetTempPath(), $"navtool-route-inputs-{Guid.NewGuid():N}");
        try
        {
            var preferences = new CountingPreferences();
            var plans = new RoutePlanJsonRepository(root);
            var provider = new CountingProvider();
            var vm = Create(provider, new TestRoutingSetupService(), repository: plans, preferences: preferences);
            vm.PassageDays = 6;
            vm.UseEcmwf = true;
            vm.UseNoaa = false;
            vm.DepartureNow = false;
            vm.DepartureDate = Now.AddDays(1);
            vm.DepartureTime = TimeSpan.FromHours(15);
            vm.RoutingSetup.PerformancePercentage = 81;
            vm.RoutingSetup.EnableCoastalPruning = true;
            await vm.Itinerary.SaveCommand.ExecuteAsync(null);
            Assert.Null(vm.Itinerary.StorageError);
            vm.RoutingSetup.PerformancePercentage = 98;
            vm.PassageDays = 2;
            vm.UseNoaa = true;
            vm.UseEcmwf = false;
            var defaults = preferences.Value;
            var writes = preferences.Writes;
            await vm.Itinerary.OpenCommand.ExecuteAsync(null);
            Assert.Null(vm.Itinerary.StorageError);
            Assert.Equal(writes, preferences.Writes);
            Assert.Equal(defaults, preferences.Value);
            Assert.Equal(81, vm.RoutingSetup.PerformancePercentage);
            Assert.Equal(6, vm.PassageDays);
            Assert.False(vm.UseNoaa);
            Assert.True(vm.UseEcmwf);
            Assert.False(vm.DepartureNow);
            Assert.Equal(TimeSpan.FromHours(15), vm.DepartureTime);
            Assert.False(vm.RoutingSetup.EnableCoastalPruning);
            Assert.False(vm.Itinerary.IsDirty);
            Assert.Equal(0, provider.Calls);
            vm.Itinerary.NewCommand.Execute(null);
            Assert.Equal(98, vm.RoutingSetup.PerformancePercentage);
            Assert.Equal(2, vm.PassageDays);
            Assert.True(vm.DepartureNow);
        }
        finally { if (Directory.Exists(root)) Directory.Delete(root, true); }
    }

    [Fact]
    public async Task Now_ignores_picker_values_and_resolves_clock_only_for_explicit_calculation()
    {
        var clock = new MutableClock { Now = Now };
        var provider = new CountingProvider();
        var vm = Create(provider, new TestRoutingSetupService(), clock: clock);
        Assert.True(vm.DepartureNow);
        vm.DepartureDate = null;
        vm.DepartureTime = null;
        clock.Now = Now.AddHours(2);
        vm.SetDestinationAt(new Coordinate(0, 2));
        await Task.Yield();
        Assert.Equal(0, provider.Calls);
        await vm.CalculateRoutesAsync();
        Assert.Null(vm.ErrorMessage);
        Assert.Equal(clock.Now, provider.LastRequest!.From);
        clock.Now = clock.Now.AddHours(1);
        await vm.CalculateRoutesAsync();
        Assert.Equal(clock.Now, provider.LastRequest.From);
    }

    [Fact]
    public void Invalid_edits_and_failed_writes_keep_last_valid_defaults_and_report_status()
    {
        var preferences = new CountingPreferences();
        var vm = Create(new CountingProvider(), new TestRoutingSetupService(), preferences: preferences);
        vm.RoutingSetup.PerformancePercentage = 85;
        var valid = preferences.Value;
        vm.RoutingSetup.PerformancePercentage = -1;
        Assert.Equal(valid, preferences.Value);
        Assert.Contains("previous valid preferences retained", vm.PreferenceStatus);
        vm.Itinerary.NewCommand.Execute(null);
        Assert.Equal(85, vm.RoutingSetup.PerformancePercentage);
        preferences.FailWrites = true;
        vm.RoutingSetup.PerformancePercentage = 90;
        Assert.Contains("disk full", vm.PreferenceError);
        Assert.Equal("Routing preferences could not be saved.", vm.PreferenceStatus);
        vm.Itinerary.NewCommand.Execute(null);
        Assert.Equal(85, vm.RoutingSetup.PerformancePercentage);
    }

    [Fact]
    public void Saved_local_source_remains_local_and_retains_missing_path_without_inspection()
    {
        var path = Path.GetFullPath("missing-forecast.grib");
        var preferences = new CountingPreferences
        {
            Value = new RoutingUserPreferences
            {
                Planning = new RoutePlanningInputs
                {
                    ForecastSource = PlanningForecastSource.LocalFile, LocalGribPath = path
                }
            }
        };
        var vm = Create(new CountingProvider(), new TestRoutingSetupService(), chooseBoat: false, preferences: preferences);
        Assert.Equal(ForecastInputMode.LocalFile, vm.ForecastInputMode);
        Assert.Equal(path, vm.LocalGribPath);
        Assert.Null(vm.LocalForecast);
        Assert.Equal(0, preferences.Writes);
        Assert.True(vm.CalculateCommand.CanExecute(null));
    }

    [Fact]
    public void Coastal_toggle_defaults_off_restores_without_events_and_invalidates_setup_on_edit()
    {
        var vm = new RoutingSetupViewModel();
        Assert.False(vm.EnableCoastalPruning);
        var changes = 0;
        vm.SetupChanged += (_, _) => changes++;
        vm.Restore(new RoutingSetup(TestRoutingSetupService.Demo,
            coastalPruning: RouteCoastalPruningMode.ConservativeLandAware));
        Assert.False(vm.EnableCoastalPruning);
        Assert.Equal(0, changes);
        Assert.True(vm.TryBuild(out var restored, out var error), error);
        Assert.Equal(RouteCoastalPruningMode.Off, restored!.CoastalPruning);
        vm.ResolvedStatus = "Previous run";
        vm.EnableCoastalPruning = true;
        Assert.Equal(1, changes);
        Assert.Null(vm.ResolvedStatus);
        Assert.True(vm.TryBuild(out var changed, out error), error);
        Assert.Equal(RouteCoastalPruningMode.ConservativeLandAware, changed!.CoastalPruning);
        vm.Restore(null);
        Assert.False(vm.EnableCoastalPruning);
        Assert.Equal(1, changes);
    }

    [Fact]
    public async Task Missing_boat_blocks_manual_and_automatic_calculation_before_forecast()
    {
        var provider = new CountingProvider();
        var setup = new TestRoutingSetupService();
        var vm = Create(provider, setup, chooseBoat: false);
        await vm.CalculateRoutesAsync();
        Assert.Contains("Select a boat", vm.ErrorMessage);
        Assert.Equal(0, provider.Calls);
        Assert.Equal(0, setup.FreezeCalls);
        vm.SetDestinationAt(new Coordinate(0, 3));
        await Task.Delay(30);
        Assert.Equal(0, provider.Calls);
        Assert.Null(vm.RoutingSetup.Boat);
    }

    [Theory]
    [InlineData(RoutingFailureKind.InvalidBoat, "Selected polar asset is missing")]
    [InlineData(RoutingFailureKind.MissingRequiredSource, "GSHHG region source is missing")]
    [InlineData(RoutingFailureKind.NativeUnavailable, "ABI 8 GSHHG capability unavailable")]
    [InlineData(RoutingFailureKind.ResourceLimit, "Regional GSHHG exceeds the cell budget")]
    public async Task Setup_failures_never_download_or_substitute_defaults(RoutingFailureKind kind, string message)
    {
        var provider = new CountingProvider();
        var service = new TestRoutingSetupService { Freeze = (_, _) => throw new RoutingException(kind, message) };
        var vm = Create(provider, service);
        await vm.CalculateRoutesAsync();
        Assert.Equal(0, provider.Calls);
        Assert.Contains(message, vm.ErrorMessage);
        Assert.Equal("No forecast was downloaded.", vm.StatusMessage);
        Assert.Equal(0, vm.SuccessfulRouteCount);
    }

    [Fact]
    public async Task Missing_configured_service_cannot_downgrade_to_unconfigured_engine()
    {
        var provider = new CountingProvider();
        var vm = Create(provider, null);
        await vm.CalculateRoutesAsync();
        Assert.Contains("No unconfigured routing fallback", vm.ErrorMessage);
        Assert.Equal(0, provider.Calls);
    }

    [Fact]
    public void Regional_policy_round_trips_through_normal_setup_without_losing_resource_limits()
    {
        var policy = new RouteRegionalLandPolicy(Path.GetFullPath("shoreline.b"), new string('a', 64),
            new GeographicBounds(-10, 10, 170, -170), 2, 0.4, 30, 4000, 20000, 50000, 7,
            "Explicit regional attribution", RouteMissingDataPolicy.RejectTransition);
        var setup = new RoutingSetup(TestRoutingSetupService.Demo,
            landSource: RoutingLandSource.RegionalGshhg, regionalLand: policy);
        var vm = new RoutingSetupViewModel(new TestRoutingSetupService());
        vm.Restore(setup);
        Assert.True(vm.IsRegionalGshhg);
        Assert.Equal(170, vm.RegionalWest);
        Assert.Equal(-170, vm.RegionalEast);
        Assert.True(vm.TryBuild(out var restored, out var error), error);
        Assert.Equal(policy, restored!.RegionalLand);
        vm.PerformancePercentage = 95;
        Assert.True(vm.TryBuild(out var changed, out error), error);
        Assert.Equal(policy, changed!.RegionalLand);
    }

    [Fact]
    public async Task Regional_domain_must_contain_active_itinerary_endpoints()
    {
        var provider = new CountingProvider();
        var service = new TestRoutingSetupService();
        var vm = Create(provider, service);
        vm.RoutingSetup.RegionalSourcePath = Path.GetFullPath("shoreline.b");
        vm.RoutingSetup.RegionalSourceIdentity = new string('a', 64);
        vm.RoutingSetup.LandSource = RoutingLandSource.RegionalGshhg;
        await vm.CalculateRoutesAsync();
        Assert.Equal(0, provider.Calls);
        Assert.Equal(0, service.FreezeCalls);
        Assert.Contains("must contain all active itinerary endpoints", vm.ErrorMessage);
    }

    [Fact]
    public async Task Explicit_regional_domain_is_used_instead_of_the_default_broad_corridor()
    {
        var provider = new CountingProvider();
        var vm = Create(provider, new TestRoutingSetupService());
        var policy = CreateRegionalPolicy();
        vm.RoutingSetup.Restore(new RoutingSetup(TestRoutingSetupService.Demo,
            landSource: RoutingLandSource.RegionalGshhg, regionalLand: policy));
        vm.Itinerary.SetRoutingSetup(new RoutingSetup(TestRoutingSetupService.Demo,
            landSource: RoutingLandSource.RegionalGshhg, regionalLand: policy));
        await vm.CalculateRoutesAsync();
        Assert.True(vm.ErrorMessage is null, vm.ErrorMessage);
        Assert.Equal(policy.StudyBounds, provider.LastRequest!.Bounds);
        Assert.NotEqual(ForecastCorridor.Create(vm.Start!.Value, vm.Destination!.Value), provider.LastRequest.Bounds);
        Assert.Contains("Explicit GSHHG study area", vm.ForecastAreaSummary);
        Assert.Single(vm.SuccessfulRoutes);
    }

    [Fact]
    public async Task Native_regional_preview_reports_grid_allowance_without_selecting_a_boat()
    {
        var service = new TestRegionalPreviewService((policy, _) => ValueTask.FromResult(CreatePreview(policy)));
        var vm = new RoutingSetupViewModel(regionalPreview: service);
        ConfigureRegionalPreview(vm);
        await vm.PreviewRegionalLandCommand.ExecuteAsync(null);
        Assert.Null(vm.Boat);
        Assert.Null(vm.ErrorMessage);
        Assert.Equal(1, service.Calls);
        Assert.Contains("200 grid nodes", vm.RegionalPreviewStatus);
        Assert.Contains("full-cell numerical allowance 0.4 NM", vm.RegionalPreviewStatus);
        Assert.Contains("Source completeness is not certified", vm.RegionalPreviewStatus);
    }

    [Fact]
    public async Task Regional_preview_capability_failure_never_changes_selected_source()
    {
        var service = new TestRegionalPreviewService((_, _) => throw new NotSupportedException("GSHHG capability unavailable"));
        var vm = new RoutingSetupViewModel(regionalPreview: service);
        ConfigureRegionalPreview(vm);
        await vm.PreviewRegionalLandCommand.ExecuteAsync(null);
        Assert.Contains("GSHHG capability unavailable", vm.ErrorMessage);
        Assert.Equal(RoutingLandSource.RegionalGshhg, vm.LandSource);
        Assert.Null(vm.RegionalPreviewStatus);
    }

    [Fact]
    public async Task Regional_preview_for_old_source_settings_is_discarded()
    {
        var started = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var release = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var service = new TestRegionalPreviewService(async (policy, _) =>
        {
            started.SetResult();
            await release.Task;
            return CreatePreview(policy);
        });
        var vm = new RoutingSetupViewModel(regionalPreview: service);
        ConfigureRegionalPreview(vm);
        var preview = vm.PreviewRegionalLandCommand.ExecuteAsync(null);
        await started.Task;
        vm.RegionalSpacingNauticalMiles = 2;
        release.SetResult();
        await preview;
        Assert.Null(vm.RegionalPreviewStatus);
        Assert.False(vm.IsPreviewingRegionalLand);
    }

    [Fact]
    public async Task Native_resource_failure_never_falls_back_or_displays_arrival()
    {
        var engine = new DenseEngine
        {
            Failure = new RoutingException(RoutingFailureKind.ResourceLimit, "Native search memory limit")
        };
        var vm = Create(new CountingProvider(), new TestRoutingSetupService(), engine: engine);
        vm.EnableProfessionalRouting = true;
        vm.SelectedRouteSolver = RouteSolver.TimeDependentLattice;
        await vm.CalculateRoutesAsync();
        Assert.Equal(1, engine.Calls);
        Assert.Empty(vm.SuccessfulRoutes);
        Assert.Contains("Native search memory limit", vm.ErrorMessage);
        Assert.DoesNotContain("arrival", vm.NoaaStatus, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task Setup_mutation_during_freeze_discards_old_setup_before_download()
    {
        var started = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var release = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var provider = new CountingProvider();
        var service = new TestRoutingSetupService
        {
            Freeze = async (setup, overrides) =>
            {
                started.SetResult();
                await release.Task;
                return TestRoutingSetupService.CreateContext(setup, overrides);
            }
        };
        var vm = Create(provider, service);
        var calculation = vm.CalculateRoutesAsync();
        await started.Task;
        vm.RoutingSetup.PerformancePercentage = 85;
        release.SetResult();
        await calculation;
        Assert.Equal(0, provider.Calls);
        Assert.Equal(0.85, vm.Itinerary.RoutingSetup!.PerformanceFactor);
        Assert.Equal(0, vm.SuccessfulRouteCount);
    }

    [Fact]
    public async Task Setup_mutation_cancels_running_engine_and_prevents_stale_publication()
    {
        var release = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var started = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var engine = new DenseEngine { Release = release, Started = started };
        var vm = Create(new CountingProvider(), new TestRoutingSetupService(), engine: engine);
        var calculation = vm.CalculateRoutesAsync();
        await started.Task;
        vm.RoutingSetup.ArrivalRadiusNauticalMiles = 0.5;
        Assert.False(vm.IsCalculating);
        release.SetResult();
        await calculation;
        Assert.Equal(0, vm.SuccessfulRouteCount);
        Assert.Equal(0.5, vm.Itinerary.RoutingSetup!.ArrivalRadiusNauticalMiles);
        Assert.Contains("changed", vm.StatusMessage);
    }

    [Fact]
    public async Task Cancellation_during_native_preparation_prevents_later_download()
    {
        var started = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var release = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var provider = new CountingProvider();
        var vm = Create(provider, new TestRoutingSetupService
        {
            Freeze = async (setup, overrides) =>
            {
                started.SetResult();
                await release.Task;
                return TestRoutingSetupService.CreateContext(setup, overrides);
            }
        });
        var calculation = vm.CalculateRoutesAsync();
        await started.Task;
        Assert.True(vm.CancelCommand.CanExecute(null));
        vm.CancelCommand.Execute(null);
        release.SetResult();
        await calculation;
        Assert.Equal(0, provider.Calls);
        Assert.False(vm.IsCalculating);
        Assert.Equal("Calculation cancelled.", vm.StatusMessage);
    }

    [Fact]
    public async Task Normal_setup_survives_save_reopen_and_professional_mode_does_not()
    {
        var root = Path.Combine(Environment.CurrentDirectory, ".test-work", $"setup-{Guid.NewGuid():N}");
        try
        {
            var repository = new RoutePlanJsonRepository(root);
            var vm = Create(new CountingProvider(), new TestRoutingSetupService(), repository: repository);
            vm.RoutingSetup.Quality = RoutingQuality.NativeAccurate;
            vm.RoutingSetup.PerformancePercentage = 92;
            vm.RoutingSetup.ArrivalRadiusNauticalMiles = 0.35;
            vm.RoutingSetup.LocalForecastMaximumGapHours = 3;
            vm.RoutingSetup.EnableCoastalPruning = true;
            vm.EnableProfessionalRouting = true;
            vm.TackPenaltySeconds = 75;
            await vm.Itinerary.SaveCommand.ExecuteAsync(null);
            Assert.Null(vm.Itinerary.StorageError);
            vm.Itinerary.SaveAsName = "Cruising copy";
            await vm.Itinerary.SaveAsCommand.ExecuteAsync(null);
            Assert.Null(vm.Itinerary.StorageError);
            Assert.Equal(92, vm.RoutingSetup.PerformancePercentage);
            vm.Itinerary.NewCommand.Execute(null);
            Assert.Equal(TestRoutingSetupService.Demo, vm.RoutingSetup.Boat);
            await vm.Itinerary.RefreshSavedPlansCommand.ExecuteAsync(null);
            await vm.Itinerary.OpenCommand.ExecuteAsync(null);
            Assert.Null(vm.Itinerary.StorageError);
            Assert.False(vm.EnableProfessionalRouting);
            Assert.False(vm.RoutingSetup.EnableCoastalPruning);
            Assert.Equal(TestRoutingSetupService.Demo, vm.RoutingSetup.Boat);
            Assert.Equal(RoutingQuality.NativeAccurate, vm.RoutingSetup.Quality);
            Assert.Equal(92, vm.RoutingSetup.PerformancePercentage);
            Assert.Equal(0.35, vm.RoutingSetup.ArrivalRadiusNauticalMiles);
            Assert.Equal(3, vm.RoutingSetup.LocalForecastMaximumGapHours);
            vm.Itinerary.AddWaypointAt(new Coordinate(0, 1));
            Assert.True(vm.Itinerary.TryBuildPlan(out var rebuilt, out var error), error);
            Assert.Equal(vm.Itinerary.RoutingSetup, rebuilt!.RoutingSetup);
        }
        finally { if (Directory.Exists(root)) Directory.Delete(root, true); }
    }

    [Fact]
    public async Task Setup_change_invalidates_unsailed_result_and_keeps_complete_recorded_geometry()
    {
        var engine = new DenseEngine();
        var vm = Create(new CountingProvider(), new TestRoutingSetupService(), engine: engine);
        await vm.CalculateRoutesAsync();
        Assert.NotNull(engine.Result?.NativeAudit);
        Assert.Equal("route_result_v2", engine.Result.NativeAudit.Schema);
        Assert.Equal(engine.Result.Solver, engine.Result.NativeAudit.Solver);
        Assert.True(vm.ErrorMessage is null, vm.ErrorMessage);
        var route = Assert.Single(vm.SuccessfulRoutes);
        Assert.Equal(1500, route.Points.Length);
        Assert.True(route.Points[750].Location.Latitude < -0.24);
        var original = route.Points.ToArray();
        vm.RoutingSetup.PerformancePercentage = 80;
        Assert.True(vm.Itinerary.ResultsInvalidated);
        Assert.Empty(vm.SuccessfulRoutes);
        Assert.Equal(original, route.Points);
        Assert.True(vm.Itinerary.TryBuildPlan(out var plan, out _));
        Assert.Equal(0.8, plan!.RoutingSetup!.PerformanceFactor);
    }

    [Fact]
    public async Task Delayed_progress_geometry_actual_endpoint_and_audit_survive_saved_visualization()
    {
        var root = Path.Combine(Environment.CurrentDirectory, ".test-work", $"geometry-{Guid.NewGuid():N}");
        try
        {
            var repository = new RoutePlanJsonRepository(root);
            var vm = Create(new CountingProvider(), new TestRoutingSetupService(), repository: repository);
            await vm.CalculateRoutesAsync();
            Assert.True(vm.ErrorMessage is null, vm.ErrorMessage);
            var original = Assert.Single(vm.SuccessfulRoutes);
            await vm.Itinerary.SaveCommand.ExecuteAsync(null);
            Assert.True(vm.Itinerary.StorageError is null, vm.Itinerary.StorageError);
            var reopened = Create(new CountingProvider(), new TestRoutingSetupService(), chooseBoat: false, repository: repository);
            await reopened.Itinerary.RefreshSavedPlansCommand.ExecuteAsync(null);
            await reopened.Itinerary.OpenCommand.ExecuteAsync(null);
            Assert.True(reopened.Itinerary.StorageError is null, reopened.Itinerary.StorageError);
            var restored = Assert.Single(reopened.SuccessfulRoutes);
            Assert.Equal(1500, restored.Points.Length);
            Assert.Equal(original.Points.ToArray(), restored.Points.ToArray());
            Assert.Equal(1.99, restored.Points[^1].Location.Longitude, 12);
            Assert.Equal(2, restored.Request.Destination.Longitude);
            Assert.True(restored.Points[750].Location.Latitude < -0.24);
            Assert.Equal(original.RunAudit!.CalculationId, restored.RunAudit!.CalculationId);
            Assert.Equal(original.NativeAudit, restored.NativeAudit);
        }
        finally { if (Directory.Exists(root)) Directory.Delete(root, true); }
    }

    [AvaloniaFact]
    public void Cruising_controls_are_visible_without_professional_mode()
    {
        var vm = Create(new CountingProvider(), new TestRoutingSetupService(), chooseBoat: false);
        var window = new MainWindow { DataContext = vm };
        try
        {
            window.Show();
            window.SelectPanel(MainWindow.WorkingPanel.Settings);
            var panel = Assert.IsType<RoutingSetupView>(window.FindControl<RoutingSetupView>("CruisingSetupPanel"));
            panel.FindControl<Expander>("BoatSettingsExpander")!.IsExpanded = true;
            panel.FindControl<Expander>("CoastSettingsExpander")!.IsExpanded = true;
            Avalonia.Threading.Dispatcher.UIThread.RunJobs();
            Assert.True(panel.IsEffectivelyVisible);
            Assert.True(panel.FindControl<Button>("ImportBoatButton")!.IsEffectivelyVisible);
            Assert.True(panel.FindControl<Button>("DemoBoatButton")!.IsEffectivelyVisible);
            Assert.NotNull(panel.FindControl<ComboBox>("RoutingQualitySelector"));
            var pruning = window.FindControl<CheckBox>("CoastalPruningToggle")!;
            var advanced = window.FindControl<Expander>("AdvancedSettingsExpander")!;
            Assert.False(advanced.IsExpanded);
            advanced.IsExpanded = true;
            Avalonia.Threading.Dispatcher.UIThread.RunJobs();
            Assert.True(advanced.IsExpanded);
            Assert.True(pruning.IsEffectivelyVisible);
            Assert.Equal(vm.RoutingSetup.EnableCoastalPruning, pruning.IsChecked);
            Assert.NotNull(panel.FindControl<NumericUpDown>("BoatPerformanceInput"));
            Assert.NotNull(panel.FindControl<NumericUpDown>("ArrivalRadiusInput"));
            Assert.NotNull(panel.FindControl<Button>("PreviewGshhgButton"));
            Assert.False(vm.EnableProfessionalRouting);
            Assert.Equal(100, vm.RoutingSetup.PerformancePercentage);
        }
        finally { window.Close(); }
    }

    [Fact]
    public void Planned_hold_never_claims_a_fresh_wind_sample_and_zero_STW_drift_is_not_hold()
    {
        var request = new RouteRequest("drift", new Coordinate(0, 0), new Coordinate(0, 2), Now, Now.AddDays(1));
        var first = new RoutePoint(request.Origin, Now, 90, 0, 15, 180, 0,
            new RoutePointEnvironment(2, 90, 0, 2, 0, polarWindSpeedKnots: 15, polarWindDirectionDegrees: 180));
        var last = new RoutePoint(new Coordinate(0, 0.03), Now.AddHours(1), 90, 0, 15, 180, 2,
            new RoutePointEnvironment(2, 90, 0, 2, 0, polarWindSpeedKnots: 15, polarWindDirectionDegrees: 180));
        var route = new RouteResult(request, ForecastModel.NoaaGfs, [first, last], new RouteDiagnostics(1, 2, 1, 1),
            RouteCompletion.DurationExhausted);
        var drift = new RouteMapSelection(route, 1, last, RouteHitKind.RoutePoint, 0);
        Assert.False(drift.IsPlannedHold);
        Assert.True(drift.HasEnvironmentTelemetry);
        Assert.NotEqual(first.Location, drift.FocusCoordinate);
        var hold = drift with { IsPlannedHold = true, HoldTimestamp = Now.AddHours(2) };
        Assert.False(hold.HasEnvironmentTelemetry);
        Assert.False(hold.HasBasicTelemetry);
        Assert.Equal("unavailable", hold.ApparentWindSpeedText);
        Assert.Equal(Now.AddHours(1), hold.Point.Timestamp);
        Assert.Equal(Now.AddHours(2), hold.TimelineTimestamp);
    }

    [Theory]
    [InlineData(0, "following seas")]
    [InlineData(90, "beam seas")]
    [InlineData(180, "head seas")]
    public void Telemetry_distinguishes_wind_frames_and_wave_semantics(double waveAngle, string expectedSea)
    {
        var request = new RouteRequest("wind-frames", new Coordinate(0, 0), new Coordinate(0, 2), Now, Now.AddDays(1));
        var point = new RoutePoint(request.Origin, Now, 90, 6, 15, 180, 0,
            new RoutePointEnvironment(8, 90, 6, 2, 0, 2, 8, waveAngle, 13, 170));
        var route = new RouteResult(request, ForecastModel.NoaaGfs,
            [point, new RoutePoint(request.Destination, Now.AddHours(5), 90, 6, 15, 180, 120)],
            new RouteDiagnostics(1, 2, 1, 1));
        var vm = Create(new CountingProvider(), new TestRoutingSetupService());
        vm.SelectRoutePoint(new RouteMapSelection(route, 0, point, RouteHitKind.RoutePoint, 0), focus: false);
        Assert.Contains("STW 6.0", vm.SelectedRouteDetails);
        Assert.Contains("SOG 8.0", vm.SelectedRouteDetails);
        Assert.Contains("ground-relative forecast wind 15.0", vm.SelectedRouteDetails);
        Assert.Contains("water-relative polar wind 13.0", vm.SelectedRouteDetails);
        Assert.Contains(expectedSea, vm.SelectedRouteDetails);
        Assert.DoesNotContain("off the bow", vm.SelectedRouteDetails);
    }

    private static MainViewModel Create(CountingProvider provider, IRoutingSetupService? service,
        bool chooseBoat = true, IRoutePlanRepository? repository = null, IRouteEngine? engine = null,
        IRoutingPreferencesRepository? preferences = null, TimeProvider? clock = null)
    {
        var vm = new MainViewModel(new RoutingWorkflow([provider], engine ?? new DenseEngine()), null,
            clock ?? new FixedClock(), TimeZoneInfo.Utc, new OsmTileOptions(Enabled: false),
            routePlanRepository: repository, boatAssetService: new TestRoutingSetupService(), routingSetupService: service,
            preferencesRepository: preferences);
        vm.SetEndpoints(new Coordinate(0, 0), new Coordinate(0, 2));
        vm.DepartureDate = Now;
        vm.DepartureTime = Now.TimeOfDay;
        if (chooseBoat) vm.RoutingSetup.Boat = TestRoutingSetupService.Demo;
        return vm;
    }

    private sealed class FixedClock : TimeProvider
    {
        public override DateTimeOffset GetUtcNow() => Now;
    }

    private sealed class MutableClock : TimeProvider
    {
        public DateTimeOffset Now { get; set; }
        public override DateTimeOffset GetUtcNow() => Now;
    }

    private sealed class CountingPreferences : IRoutingPreferencesRepository
    {
        public RoutingUserPreferences? Value { get; set; }
        public int Writes { get; private set; }
        public bool FailWrites { get; set; }
        public RoutingUserPreferences? Load() => Value;
        public void Save(RoutingUserPreferences preferences)
        {
            if (FailWrites) throw new IOException("disk full");
            preferences.Validate();
            Writes++;
            Value = preferences;
        }
    }

    private sealed class CountingProvider : IForecastProvider
    {
        public int Calls { get; private set; }
        public ForecastRequest? LastRequest { get; private set; }
        public ForecastProvider Provider => ForecastProvider.Noaa;
        public ForecastModel Model => ForecastModel.NoaaGfs;
        public ValueTask<ForecastAcquisition> AcquireAsync(ForecastRequest request,
            IProgress<ForecastProgress>? progress, CancellationToken cancellationToken)
        {
            Calls++;
            LastRequest = request;
            return ValueTask.FromResult(new ForecastAcquisition(request,
                new ForecastRun(request.Provider, request.Model, request.From.AddHours(-6)),
                new LocalGribArtifact(Path.GetFullPath("test-boundary.grib2")), ForecastAcquisitionSource.Cache,
                new CacheMetadata("boundary", request.From, request.Through.AddDays(1))));
        }
    }

    private static RouteRegionalLandPolicy CreateRegionalPolicy() =>
        new(Path.GetFullPath("shoreline.b"), new string('a', 64),
            new GeographicBounds(-1, 1, -1, 3), 1, 0, 60, 250000, 10000000, 100000000);

    private static void ConfigureRegionalPreview(RoutingSetupViewModel vm)
    {
        vm.RegionalSourcePath = Path.GetFullPath("shoreline.b");
        vm.RegionalSourceIdentity = new string('a', 64);
        vm.LandSource = RoutingLandSource.RegionalGshhg;
    }

    private static RegionalLandPreview CreatePreview(RouteRegionalLandPolicy policy) =>
        new(policy, new RegionalLandEstimate(10, 20, 200, 0.01, 0.01, 0.4,
            policy.StudyBounds.South - 0.1, policy.StudyBounds.North + 0.1,
            policy.StudyBounds.West - 0.1, policy.StudyBounds.East + 0.1));

    private sealed class TestRegionalPreviewService(
        Func<RouteRegionalLandPolicy, CancellationToken, ValueTask<RegionalLandPreview>> preview)
        : IRegionalLandPreviewService
    {
        public int Calls { get; private set; }
        public ValueTask<RegionalLandPreview> PreviewAsync(RouteRegionalLandPolicy policy,
            CancellationToken cancellationToken = default)
        {
            Calls++;
            return preview(policy, cancellationToken);
        }
    }

    private sealed class DenseEngine : IConfiguredRouteEngine
    {
        public TaskCompletionSource? Release { get; init; }
        public TaskCompletionSource? Started { get; init; }
        public Exception? Failure { get; init; }
        public int Calls { get; private set; }
        public RouteResult? Result { get; private set; }
        public async ValueTask<RouteResult> CalculateConfiguredAsync(RoutingCalculationContext context, RouteRequest request,
            ForecastAcquisition forecast, RouteOptimizationOptions optimization,
            IProgress<RouteCalculationProgress>? progress, CancellationToken cancellationToken)
        {
            Calls++;
            Started?.SetResult();
            if (Release is not null) await Release.Task;
            if (Failure is not null) throw Failure;
            Result = TestRoutingSetupService.WithConfiguredAudit(new RouteResult(request, forecast.Request.Model,
                Enumerable.Range(0, 1500).Select(index => new RoutePoint(
                    new Coordinate(-0.25 * Math.Sin(index * Math.PI / 1499), 1.99 * index / 1499),
                    request.DepartureTime.AddSeconds(index * 10), 90, 5, 15, 180, index * 0.08)),
                new RouteDiagnostics(1, 2, 1, 1)), context, optimization, forecast);
            return Result;
        }
        public ValueTask<RouteResult> CalculateAsync(RouteRequest request, ForecastAcquisition forecast,
            IProgress<RouteCalculationProgress>? progress, CancellationToken cancellationToken) =>
            throw new InvalidOperationException("An unconfigured request was attempted.");
        public ValueTask<RouteResult> CalculateAsync(RouteRequest request, ForecastAcquisition forecast,
            RouteOptimizationOptions optimization, IProgress<RouteCalculationProgress>? progress,
            CancellationToken cancellationToken) => throw new InvalidOperationException("Context was discarded.");
    }
}
