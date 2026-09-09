using System.Collections.Immutable;
using Avalonia.Controls;
using Avalonia.Headless.XUnit;
using Avalonia.Threading;
using Mapsui.Extensions;
using Mapsui.Layers;
using Mapsui.Manipulations;
using Navtool.App.Models;
using Navtool.App.Services;
using Navtool.App.ViewModels;
using Navtool.App.Views;
using Navtool.Core;
using Navtool.Infrastructure;

namespace Navtool.App.Tests;

public sealed class MainViewModelWorkflowTests
{
    private static readonly DateTimeOffset Now =
        new(2026, 7, 14, 16, 0, 0, TimeSpan.Zero);

    [Fact]
    public void Professional_routing_defaults_off_and_filters_solver_specific_controls()
    {
        var viewModel = new MainViewModel(
            null,
            null,
            new FixedTimeProvider(Now),
            TimeZoneInfo.Utc,
            new OsmTileOptions(Enabled: false));

        Assert.False(viewModel.EnableProfessionalRouting);
        Assert.Equal(RouteSolver.IsochroneBeam, viewModel.SelectedRouteSolver);
        Assert.False(viewModel.IsProfessionalBeamRouting);
        Assert.False(viewModel.IsProfessionalLatticeRouting);

        viewModel.EnableProfessionalRouting = true;
        Assert.True(viewModel.IsProfessionalBeamRouting);
        Assert.False(viewModel.IsProfessionalLatticeRouting);

        viewModel.SelectedRouteSolver = RouteSolver.TimeDependentLattice;
        Assert.False(viewModel.IsProfessionalBeamRouting);
        Assert.True(viewModel.IsProfessionalLatticeRouting);
    }

    [Fact]
    public async Task Standard_mode_always_routes_with_balanced_options()
    {
        var noaa = new DelegateForecastProvider(
            ForecastModel.NoaaGfs,
            (request, _) => ValueTask.FromResult(CreateAcquisition(request)));
        var engine = new DelegateRouteEngine((request, forecast, _) =>
            ValueTask.FromResult(CreateRoute(request, forecast.Request.Model)));
        var viewModel = CreateRoutingViewModel(noaa, engine);
        viewModel.EnableProfessionalRouting = false;
        viewModel.SelectedRouteSolver = RouteSolver.TimeDependentLattice;
        viewModel.TackPenaltySeconds = 600;

        viewModel.SetStartAt(new Coordinate(34, -64));
        viewModel.SetDestinationAt(new Coordinate(39, -52));
        await viewModel.CalculateRoutesAsync();

        Assert.Same(RouteOptimizationOptions.Balanced, engine.LastOptimization);
    }


    /// <summary>
    /// Stage 3 physics is opt-in. Turning professional routing on must not by
    /// itself configure any environmental provider, or every professional route
    /// would silently change behaviour.
    /// </summary>
    [Fact]
    public async Task Professional_mode_configures_no_environment_until_a_provider_is_enabled()
    {
        var noaa = new DelegateForecastProvider(
            ForecastModel.NoaaGfs,
            (request, _) => ValueTask.FromResult(CreateAcquisition(request)));
        var engine = new DelegateRouteEngine((request, forecast, _) =>
            ValueTask.FromResult(CreateRoute(request, forecast.Request.Model)));
        var viewModel = CreateRoutingViewModel(noaa, engine);
        viewModel.EnableProfessionalRouting = true;

        Assert.False(viewModel.IsEnvironmentConfigured);

        viewModel.SetStartAt(new Coordinate(34, -64));
        viewModel.SetDestinationAt(new Coordinate(39, -52));
        await viewModel.CalculateRoutesAsync();

        Assert.Null(engine.LastOptimization!.Environment);
    }

    [Fact]
    public async Task Enabling_a_uniform_current_flows_through_to_the_route_engine()
    {
        var noaa = new DelegateForecastProvider(
            ForecastModel.NoaaGfs,
            (request, _) => ValueTask.FromResult(CreateAcquisition(request)));
        var engine = new DelegateRouteEngine((request, forecast, _) =>
            ValueTask.FromResult(CreateRoute(request, forecast.Request.Model)));
        var viewModel = CreateRoutingViewModel(noaa, engine);
        viewModel.EnableProfessionalRouting = true;
        viewModel.EnableCurrentField = true;
        viewModel.CurrentEastKnots = 1.25;
        viewModel.CurrentNorthKnots = -0.75;

        Assert.True(viewModel.IsEnvironmentConfigured);

        viewModel.SetStartAt(new Coordinate(34, -64));
        viewModel.SetDestinationAt(new Coordinate(39, -52));
        await viewModel.CalculateRoutesAsync();

        var environment = engine.LastOptimization!.Environment;
        Assert.NotNull(environment);
        Assert.NotNull(environment!.Currents);
        Assert.Equal(1.25, environment.Currents!.UniformEastKnots);
        Assert.Equal(-0.75, environment.Currents.UniformNorthKnots);
        Assert.Null(environment.Waves);
        Assert.Null(environment.Land);
        Assert.Null(environment.Exclusions);
    }

    /// <summary>
    /// Selecting the signed-distance landmask must express intent as an
    /// unresolved request; only the engine has the corridor and coastline needed
    /// to rasterize the grid.
    /// </summary>
    [Fact]
    public async Task Selecting_the_signed_distance_landmask_emits_an_unresolved_land_request()
    {
        var noaa = new DelegateForecastProvider(
            ForecastModel.NoaaGfs,
            (request, _) => ValueTask.FromResult(CreateAcquisition(request)));
        var engine = new DelegateRouteEngine((request, forecast, _) =>
            ValueTask.FromResult(CreateRoute(request, forecast.Request.Model)));
        var viewModel = CreateRoutingViewModel(noaa, engine);
        viewModel.EnableProfessionalRouting = true;
        viewModel.LandAvoidanceMode = RouteLandAvoidanceMode.SignedDistanceLandmask;

        Assert.True(viewModel.IsSignedDistanceLandmaskSelected);

        viewModel.SetStartAt(new Coordinate(34, -64));
        viewModel.SetDestinationAt(new Coordinate(39, -52));
        await viewModel.CalculateRoutesAsync();

        var environment = engine.LastOptimization!.Environment;
        Assert.NotNull(environment);
        Assert.NotNull(environment!.LandRequest);
        Assert.Null(environment.Land);
    }

    /// <summary>
    /// Standard mode must ignore Stage 3 state entirely, so a user who
    /// configured physics and then dropped back to standard mode still gets the
    /// unmodified balanced profile.
    /// </summary>
    [Fact]
    public async Task Standard_mode_ignores_configured_environment_state()
    {
        var noaa = new DelegateForecastProvider(
            ForecastModel.NoaaGfs,
            (request, _) => ValueTask.FromResult(CreateAcquisition(request)));
        var engine = new DelegateRouteEngine((request, forecast, _) =>
            ValueTask.FromResult(CreateRoute(request, forecast.Request.Model)));
        var viewModel = CreateRoutingViewModel(noaa, engine);
        viewModel.EnableProfessionalRouting = true;
        viewModel.EnableCurrentField = true;
        viewModel.CurrentEastKnots = 2;
        viewModel.EnableProfessionalRouting = false;

        viewModel.SetStartAt(new Coordinate(34, -64));
        viewModel.SetDestinationAt(new Coordinate(39, -52));
        await viewModel.CalculateRoutesAsync();

        Assert.Same(RouteOptimizationOptions.Balanced, engine.LastOptimization);
    }

    [Fact]
    public async Task Professional_mode_routes_with_an_immutable_lattice_configuration()
    {
        var noaa = new DelegateForecastProvider(
            ForecastModel.NoaaGfs,
            (request, _) => ValueTask.FromResult(CreateAcquisition(request)));
        var engine = new DelegateRouteEngine((request, forecast, _) =>
            ValueTask.FromResult(CreateRoute(request, forecast.Request.Model)));
        var viewModel = CreateRoutingViewModel(noaa, engine);
        viewModel.EnableProfessionalRouting = true;
        viewModel.SelectedRouteSolver = RouteSolver.TimeDependentLattice;
        viewModel.TackPenaltySeconds = 120;
        viewModel.LatticeSearchAlgorithm = RouteLatticeSearchAlgorithm.Dijkstra;

        viewModel.SetStartAt(new Coordinate(34, -64));
        viewModel.SetDestinationAt(new Coordinate(39, -52));
        await viewModel.CalculateRoutesAsync();

        Assert.Equal(RouteSolver.TimeDependentLattice, engine.LastOptimization!.Solver);
        Assert.Equal(TimeSpan.FromSeconds(120), engine.LastOptimization.Maneuver.TackPenalty);
        Assert.Equal(
            RouteLatticeSearchAlgorithm.Dijkstra,
            engine.LastOptimization.Lattice.SearchAlgorithm);
    }

    [Fact]
    public void DirectContextualEndpointAssignmentPreservesInteractionWorkflow()
    {
        var viewModel = new MainViewModel(
            null,
            null,
            new FixedTimeProvider(Now),
            TimeZoneInfo.Utc,
            new OsmTileOptions(Enabled: false));
        var notifications = new HashSet<string>();
        viewModel.PropertyChanged += (_, args) =>
        {
            if (args.PropertyName is not null)
            {
                notifications.Add(args.PropertyName);
            }
        };
        var start = new Coordinate(34, -64);
        var destination = new Coordinate(39, -52);

        viewModel.SetDestinationCommand.Execute(null);
        viewModel.SetStartAt(start);

        Assert.Equal(start, viewModel.Start);
        Assert.Null(viewModel.Destination);
        Assert.Equal(MapInteractionMode.Browse, viewModel.InteractionMode);
        Assert.Equal("Endpoint placed. Set the remaining endpoint.", viewModel.StatusMessage);
        Assert.Equal("Set both endpoints to estimate the forecast download.", viewModel.ForecastAreaSummary);

        notifications.Clear();
        viewModel.SetStartCommand.Execute(null);
        viewModel.SetDestinationAt(destination);

        Assert.Equal(start, viewModel.Start);
        Assert.Equal(destination, viewModel.Destination);
        Assert.Equal(MapInteractionMode.Browse, viewModel.InteractionMode);
        Assert.Equal("Endpoints ready. Choose forecast models and calculate.", viewModel.StatusMessage);
        Assert.StartsWith("Buffered area ", viewModel.ForecastAreaSummary);
        Assert.Contains(nameof(MainViewModel.Start), notifications);
        Assert.Contains(nameof(MainViewModel.Destination), notifications);
        Assert.Contains(nameof(MainViewModel.StartDisplay), notifications);
        Assert.Contains(nameof(MainViewModel.DestinationDisplay), notifications);
        Assert.Contains(nameof(MainViewModel.InteractionMode), notifications);
        Assert.Contains(nameof(MainViewModel.MapInstruction), notifications);
    }

    [Fact]
    public async Task Placing_final_endpoint_waits_for_explicit_calculation()
    {
        var routeRequests = new List<RouteRequest>();
        var noaa = new DelegateForecastProvider(
            ForecastModel.NoaaGfs,
            (request, _) => ValueTask.FromResult(CreateAcquisition(request)));
        var engine = new DelegateRouteEngine((request, forecast, _) =>
        {
            routeRequests.Add(request);
            return ValueTask.FromResult(CreateRoute(request, forecast.Request.Model));
        });
        var viewModel = CreateRoutingViewModel(noaa, engine);
        var departure = Now.AddHours(1);
        viewModel.DepartureDate = departure;
        viewModel.DepartureTime = departure.TimeOfDay;

        viewModel.SetStartAt(new Coordinate(34, -64));
        await Task.Yield();
        Assert.Empty(routeRequests);

        viewModel.SetDestinationAt(new Coordinate(39, -52));
        await Task.Yield();
        Assert.Empty(routeRequests);
        await viewModel.CalculateRoutesAsync();

        var request = Assert.Single(routeRequests);
        Assert.Equal(new Coordinate(34, -64), request.Origin);
        Assert.Equal(new Coordinate(39, -52), request.Destination);
    }

    [Fact]
    public async Task Replacing_endpoint_cancels_stale_calculation_and_waits_for_explicit_recalculation()
    {
        var firstStarted = new TaskCompletionSource(
            TaskCreationOptions.RunContinuationsAsynchronously);
        var firstCancelled = new TaskCompletionSource(
            TaskCreationOptions.RunContinuationsAsynchronously);
        var callCount = 0;
        Coordinate? completedDestination = null;
        var noaa = new DelegateForecastProvider(
            ForecastModel.NoaaGfs,
            (request, _) => ValueTask.FromResult(CreateAcquisition(request)));
        var engine = new StreamingRouteEngine(async (request, forecast, _, cancellationToken) =>
        {
            if (Interlocked.Increment(ref callCount) == 1)
            {
                firstStarted.SetResult();
                try
                {
                    await Task.Delay(Timeout.InfiniteTimeSpan, cancellationToken);
                }
                catch (OperationCanceledException)
                {
                    firstCancelled.SetResult();
                    throw;
                }
            }

            completedDestination = request.Destination;
            return CreateRoute(request, forecast.Request.Model);
        });
        var viewModel = CreateViewModel(
            new RoutingWorkflow(new[] { noaa }, engine),
            new DelegateWeatherSampler((_, _, _, _, _, _) =>
                ValueTask.FromResult(ImmutableArray<ViewportWindSample>.Empty)));

        viewModel.SetDestinationAt(new Coordinate(40, -51));
        var firstCalculation = viewModel.CalculateRoutesAsync();
        await firstStarted.Task;

        var replacement = new Coordinate(41, -49);
        viewModel.SetDestinationAt(replacement);
        await firstCancelled.Task;
        await firstCalculation;
        Assert.Equal(1, callCount);
        await viewModel.CalculateRoutesAsync();

        Assert.Equal(2, callCount);
        Assert.Equal(replacement, completedDestination);
    }

    [Fact]
    public async Task Forced_recalculation_refreshes_only_expired_normal_departure()
    {
        var routeRequests = new List<RouteRequest>();
        var noaa = new DelegateForecastProvider(
            ForecastModel.NoaaGfs,
            (request, _) => ValueTask.FromResult(CreateAcquisition(request)));
        var engine = new DelegateRouteEngine((request, forecast, _) =>
        {
            routeRequests.Add(request);
            return ValueTask.FromResult(CreateRoute(request, forecast.Request.Model));
        });
        var viewModel = CreateViewModel(
            new RoutingWorkflow(new[] { noaa }, engine),
            new DelegateWeatherSampler((_, _, _, _, _, _) =>
                ValueTask.FromResult(ImmutableArray<ViewportWindSample>.Empty)));
        var expired = Now.AddHours(-1);
        viewModel.DepartureDate = expired;
        viewModel.DepartureTime = expired.TimeOfDay;

        await viewModel.ForceRecalculateCommand.ExecuteAsync(null);

        Assert.Equal(Now, routeRequests[0].DepartureTime);
        Assert.Equal(Now.Date, viewModel.DepartureDate!.Value.Date);
        Assert.Equal(Now.TimeOfDay, viewModel.DepartureTime);

        var future = Now.AddHours(3);
        viewModel.DepartureDate = future;
        viewModel.DepartureTime = future.TimeOfDay;

        await viewModel.ForceRecalculateCommand.ExecuteAsync(null);

        Assert.Equal(future, routeRequests[1].DepartureTime);
        Assert.Equal(future.Date, viewModel.DepartureDate!.Value.Date);
        Assert.Equal(future.TimeOfDay, viewModel.DepartureTime);
    }

    [Fact]
    public async Task Forced_recalculation_rolls_a_stale_current_position_departure_forward()
    {
        var root = Path.Combine(Path.GetTempPath(), $"navtool-stale-departure-{Guid.NewGuid():N}");
        var routeRequests = new List<RouteRequest>();
        var noaa = new DelegateForecastProvider(
            ForecastModel.NoaaGfs,
            (request, _) => ValueTask.FromResult(CreateAcquisition(request)));
        var engine = new DelegateRouteEngine((request, forecast, _) =>
        {
            routeRequests.Add(request);
            return ValueTask.FromResult(CreateRoute(request, forecast.Request.Model));
        });
        try
        {
            var viewModel = CreateViewModel(
                new RoutingWorkflow(new[] { noaa }, engine),
                new DelegateWeatherSampler((_, _, _, _, _, _) =>
                    ValueTask.FromResult(ImmutableArray<ViewportWindSample>.Empty)),
                routePlanRepository: new RoutePlanJsonRepository(root));

            // Mirrors a reopened plan: the stored current-position departure is already in the past.
            var stale = Now.AddHours(-6);
            Assert.True(
                viewModel.Itinerary.PlaceCurrentPosition(new Coordinate(35, -62), stale, out var placeError),
                placeError);
            Assert.Equal(stale, viewModel.Itinerary.CurrentPositionDepartureTimeUtc);

            await viewModel.ForceRecalculateCommand.ExecuteAsync(null);

            Assert.Equal(Now, viewModel.Itinerary.CurrentPositionDepartureTimeUtc);
            Assert.DoesNotContain(
                "rolled forward",
                viewModel.WarningMessage ?? string.Empty,
                StringComparison.Ordinal);
        }
        finally
        {
            if (Directory.Exists(root))
            {
                Directory.Delete(root, recursive: true);
            }
        }
    }

    [Fact]
    public void Departure_preview_reports_the_utc_instant_the_local_selection_resolves_to()
    {
        var zone = TimeZoneInfo.CreateCustomTimeZone(
            "Test -07",
            TimeSpan.FromHours(-7),
            "Test -07",
            "Test -07");
        var viewModel = new MainViewModel(
            null,
            null,
            new FixedTimeProvider(Now),
            zone,
            new OsmTileOptions(Enabled: false));

        viewModel.DepartureNow = false;
        viewModel.DepartureDate = new DateTimeOffset(2026, 8, 4, 0, 0, 0, TimeSpan.FromHours(-7));
        viewModel.DepartureTime = TimeSpan.FromHours(11);

        Assert.Equal("= 2026-08-04 18:00 UTC", viewModel.DepartureUtcPreview);

        viewModel.DepartureTime = null;

        Assert.Equal("Choose both a departure date and local time.", viewModel.DepartureUtcPreview);
    }

    [Fact]
    public void Forecast_area_summary_reports_selected_provider_estimates()
    {
        var viewModel = new MainViewModel(
            null,
            null,
            new FixedTimeProvider(Now),
            TimeZoneInfo.Utc,
            new OsmTileOptions(Enabled: false),
            forecastEstimators:
            [
                new StubForecastEstimator(ForecastModel.NoaaGfs, 4, 8),
                new StubForecastEstimator(ForecastModel.EcmwfIfs, 3, 6)
            ]);
        viewModel.SetEndpoints(
            new Coordinate(34, -64),
            new Coordinate(39, -52));
        viewModel.DepartureNow = false;
        viewModel.DepartureDate = Now.AddHours(1);
        viewModel.DepartureTime = Now.AddHours(1).TimeOfDay;
        viewModel.UseEcmwf = true;

        Assert.Contains("NOAA 4 times/8 parts", viewModel.ForecastAreaSummary);
        Assert.Contains("ECMWF 3 times/6 global wind ranges", viewModel.ForecastAreaSummary);
    }

    [Fact]
    public void LocalDepartureConversionHandlesUtcAndDstEdgeCases()
    {
        Assert.True(LocalDepartureConverter.TryConvertToUtc(
            new DateTimeOffset(2026, 7, 15, 0, 0, 0, TimeSpan.Zero),
            TimeSpan.FromHours(9),
            TimeZoneInfo.CreateCustomTimeZone("UTC+2", TimeSpan.FromHours(2), "UTC+2", "UTC+2"),
            out var utc,
            out var error));
        Assert.Null(error);
        Assert.Equal(new DateTimeOffset(2026, 7, 15, 7, 0, 0, TimeSpan.Zero), utc);

        var daylightZone = CreateDaylightZone();
        Assert.False(LocalDepartureConverter.TryConvertToUtc(
            new DateTimeOffset(2026, 3, 8, 0, 0, 0, TimeSpan.Zero),
            new TimeSpan(2, 30, 0),
            daylightZone,
            out _,
            out var invalidError));
        Assert.Contains("does not exist", invalidError);

        Assert.False(LocalDepartureConverter.TryConvertToUtc(
            new DateTimeOffset(2026, 11, 1, 0, 0, 0, TimeSpan.Zero),
            new TimeSpan(1, 30, 0),
            daylightZone,
            out _,
            out var ambiguousError));
        Assert.Contains("occurs twice", ambiguousError);
    }

    [Fact]
    public async Task DualModelFailurePreservesSuccessfulNoaaRoute()
    {
        var noaa = new DelegateForecastProvider(
            ForecastModel.NoaaGfs,
            (request, _) => ValueTask.FromResult(CreateAcquisition(request)));
        var ecmwf = new DelegateForecastProvider(
            ForecastModel.EcmwfIfs,
            (_, _) => ValueTask.FromException<ForecastAcquisition>(
                new NotSupportedException("indexed ranges are unavailable")));
        var engine = new DelegateRouteEngine((request, forecast, _) =>
            ValueTask.FromResult(CreateRoute(request, forecast.Request.Model)));
        var viewModel = CreateViewModel(
            new RoutingWorkflow(new IForecastProvider[] { noaa, ecmwf }, engine),
            new DelegateWeatherSampler((_, _, _, _, _, _) =>
                ValueTask.FromResult(ImmutableArray<ViewportWindSample>.Empty)));
        viewModel.UseEcmwf = true;

        await viewModel.CalculateRoutesAsync();

        Assert.Equal(1, viewModel.SuccessfulRouteCount);
        Assert.True(viewModel.HasTimeline);
        Assert.Equal(ForecastModel.NoaaGfs, viewModel.SelectedRoutePoint!.Model);
        Assert.Contains("complete", viewModel.NoaaStatus, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("ECMWF IFS failed", viewModel.ErrorMessage);
        Assert.Equal("forecast acquisition failed - see Messages", viewModel.EcmwfStatus);
        Assert.Contains("indexed ranges are unavailable",
            Assert.Single(viewModel.CurrentMessages, message => message.Model == ForecastModel.EcmwfIfs).Summary);
    }

    [Fact]
    public async Task Newest_weather_control_is_consumed_by_the_next_calculation()
    {
        ForecastRefreshPolicy? observedPolicy = null;
        var noaa = new DelegateForecastProvider(
            ForecastModel.NoaaGfs,
            (request, _) =>
            {
                observedPolicy = request.RefreshPolicy;
                return ValueTask.FromResult(CreateAcquisition(request));
            });
        var engine = new DelegateRouteEngine((request, forecast, _) =>
            ValueTask.FromResult(CreateRoute(request, forecast.Request.Model)));
        var viewModel = CreateViewModel(
            new RoutingWorkflow(new[] { noaa }, engine),
            new DelegateWeatherSampler((_, _, _, _, _, _) =>
                ValueTask.FromResult(ImmutableArray<ViewportWindSample>.Empty)));
        viewModel.UseNewestWeatherData = true;

        await viewModel.CalculateRoutesAsync();

        Assert.Equal(ForecastRefreshPolicy.LatestAvailable, observedPolicy);
        Assert.False(viewModel.UseNewestWeatherData);
    }

    [Fact]
    public async Task Covering_cached_run_warns_when_newer_weather_is_available()
    {
        var selectedRun = new DateTimeOffset(2026, 7, 14, 6, 0, 0, TimeSpan.Zero);
        var latestRun = selectedRun.AddHours(6);
        var noaa = new DelegateForecastProvider(
            ForecastModel.NoaaGfs,
            (request, _) => ValueTask.FromResult(CreateAcquisition(
                request,
                new ForecastCacheUsage(3, 0, selectedRun, latestRun))));
        var engine = new DelegateRouteEngine((request, forecast, _) =>
            ValueTask.FromResult(CreateRoute(request, forecast.Request.Model)));
        var viewModel = CreateViewModel(
            new RoutingWorkflow(new[] { noaa }, engine),
            new DelegateWeatherSampler((_, _, _, _, _, _) =>
                ValueTask.FromResult(ImmutableArray<ViewportWindSample>.Empty)));

        await viewModel.CalculateRoutesAsync();

        Assert.Contains("cached run", viewModel.WarningMessage, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("forecast freshness policy", viewModel.WarningMessage, StringComparison.Ordinal);
        var warning = Assert.Single(viewModel.CurrentMessages);
        Assert.Equal(ForecastModel.NoaaGfs, warning.Model);
        Assert.Equal(viewModel.WarningMessage, warning.Summary);
    }

    [Fact]
    public async Task ArrivalBeyondRequestedDurationSucceedsWithOverDurationNote()
    {
        var noaa = new DelegateForecastProvider(
            ForecastModel.NoaaGfs,
            (request, _) => ValueTask.FromResult(CreateAcquisition(request)));
        // Arrival lands 80h out; the default 3-day (72h) passage target is exceeded.
        var engine = new DelegateRouteEngine((request, forecast, _) =>
            ValueTask.FromResult(CreateRoute(request, forecast.Request.Model, stepHours: 40)));
        var viewModel = CreateViewModel(
            new RoutingWorkflow(new[] { noaa }, engine),
            new DelegateWeatherSampler((_, _, _, _, _, _) =>
                ValueTask.FromResult(ImmutableArray<ViewportWindSample>.Empty)));

        await viewModel.CalculateRoutesAsync();

        Assert.Equal(1, viewModel.SuccessfulRouteCount);
        Assert.Contains("complete", viewModel.NoaaStatus, StringComparison.OrdinalIgnoreCase);
        Assert.Contains(
            "beyond the expected passage duration",
            viewModel.NoaaStatus,
            StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task Legacy_router_land_warning_is_prominent_without_failing_the_route()
    {
        var noaa = new DelegateForecastProvider(
            ForecastModel.NoaaGfs,
            (request, _) => ValueTask.FromResult(CreateAcquisition(request)));
        var engine = new DelegateRouteEngine((request, forecast, _) =>
            ValueTask.FromResult(CreateRoute(
                request,
                forecast.Request.Model,
                landAvoidance: new RouteLandAvoidance(
                    LandAvoidanceStatus.RouterUnsupported,
                    "Land avoidance was not applied because the router is unsupported."))));
        var viewModel = CreateViewModel(
            new RoutingWorkflow(new[] { noaa }, engine),
            new DelegateWeatherSampler((_, _, _, _, _, _) =>
                ValueTask.FromResult(ImmutableArray<ViewportWindSample>.Empty)));

        await viewModel.CalculateRoutesAsync();

        Assert.Equal(1, viewModel.SuccessfulRouteCount);
        Assert.Contains("router is unsupported", viewModel.LandAvoidanceWarning);
        Assert.Null(viewModel.ErrorMessage);
    }

    [Fact]
    public async Task Endpoint_change_clears_route_and_its_warning_before_invalid_recalculation()
    {
        var warning = new RouteLandAvoidance(
            LandAvoidanceStatus.RouterUnsupported,
            "Displayed route was not checked for land.");
        var noaa = new DelegateForecastProvider(
            ForecastModel.NoaaGfs,
            (request, _) => ValueTask.FromResult(CreateAcquisition(request)));
        var engine = new DelegateRouteEngine((request, forecast, _) =>
            ValueTask.FromResult(CreateRoute(
                request,
                forecast.Request.Model,
                landAvoidance: warning)));
        var viewModel = CreateViewModel(
            new RoutingWorkflow(new[] { noaa }, engine),
            new DelegateWeatherSampler((_, _, _, _, _, _) =>
                ValueTask.FromResult(ImmutableArray<ViewportWindSample>.Empty)));
        await viewModel.CalculateRoutesAsync();
        viewModel.SetEndpoints(new Coordinate(34, -64), new Coordinate(34, -64));

        await viewModel.CalculateRoutesAsync();

        Assert.Equal(0, viewModel.SuccessfulRouteCount);
        Assert.Null(viewModel.SelectedLeg?.Route);
        Assert.Null(viewModel.LandAvoidanceWarning);
    }

    [Fact]
    public async Task SelectedRouteDetailsIncludeApparentWindAngle()
    {
        var noaa = new DelegateForecastProvider(
            ForecastModel.NoaaGfs,
            (request, _) => ValueTask.FromResult(CreateAcquisition(request)));
        var engine = new DelegateRouteEngine((request, forecast, _) =>
            ValueTask.FromResult(CreateRoute(request, forecast.Request.Model)));
        var viewModel = CreateViewModel(
            new RoutingWorkflow(new[] { noaa }, engine),
            new DelegateWeatherSampler((_, _, _, _, _, _) =>
                ValueTask.FromResult(ImmutableArray<ViewportWindSample>.Empty)));

        await viewModel.CalculateRoutesAsync();

        Assert.Contains("apparent wind 31° starboard", viewModel.SelectedRouteDetails);
    }

    [Fact]
    public async Task PassageDurationControlsForecastWindow()
    {
        var noaa = new DelegateForecastProvider(
            ForecastModel.NoaaGfs,
            (request, _) => ValueTask.FromResult(CreateAcquisition(request)));
        var engine = new DelegateRouteEngine((request, forecast, _) =>
            ValueTask.FromResult(CreateRoute(request, forecast.Request.Model)));
        var viewModel = CreateViewModel(
            new RoutingWorkflow(new[] { noaa }, engine),
            new DelegateWeatherSampler((_, _, _, _, _, _) =>
                ValueTask.FromResult(ImmutableArray<ViewportWindSample>.Empty)));
        viewModel.PassageDays = 2;
        viewModel.PassageHours = 5;

        await viewModel.CalculateRoutesAsync();

        Assert.Equal(TimeSpan.FromHours(53), noaa.LastRequest!.Through - noaa.LastRequest.From);
    }

    [Fact]
    public async Task InvalidPassageDurationDoesNotAcquireForecast()
    {
        var noaa = new DelegateForecastProvider(
            ForecastModel.NoaaGfs,
            (request, _) => ValueTask.FromResult(CreateAcquisition(request)));
        var engine = new DelegateRouteEngine((request, forecast, _) =>
            ValueTask.FromResult(CreateRoute(request, forecast.Request.Model)));
        var viewModel = CreateViewModel(
            new RoutingWorkflow(new[] { noaa }, engine),
            new DelegateWeatherSampler((_, _, _, _, _, _) =>
                ValueTask.FromResult(ImmutableArray<ViewportWindSample>.Empty)));
        viewModel.PassageDays = 10;
        viewModel.PassageHours = 1;

        await viewModel.CalculateRoutesAsync();

        Assert.Null(noaa.LastRequest);
        Assert.Contains("cannot exceed 10 days", viewModel.ErrorMessage);
    }

    [Fact]
    public async Task Invalid_itinerary_does_not_acquire_forecast()
    {
        var noaa = new DelegateForecastProvider(
            ForecastModel.NoaaGfs,
            (request, _) => ValueTask.FromResult(CreateAcquisition(request)));
        var engine = new DelegateRouteEngine((request, forecast, _) =>
            ValueTask.FromResult(CreateRoute(request, forecast.Request.Model)));
        var viewModel = CreateViewModel(
            new RoutingWorkflow(new[] { noaa }, engine),
            new DelegateWeatherSampler((_, _, _, _, _, _) =>
                ValueTask.FromResult(ImmutableArray<ViewportWindSample>.Empty)));
        viewModel.Itinerary.RouteName = " ";

        await viewModel.CalculateRoutesAsync();

        Assert.Null(noaa.LastRequest);
        Assert.Contains("whitespace", viewModel.ErrorMessage, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task Initial_departure_beyond_five_day_lead_does_not_acquire_forecast()
    {
        var noaa = new DelegateForecastProvider(
            ForecastModel.NoaaGfs,
            (request, _) => ValueTask.FromResult(CreateAcquisition(request)));
        var engine = new DelegateRouteEngine((request, forecast, _) =>
            ValueTask.FromResult(CreateRoute(request, forecast.Request.Model)));
        var viewModel = CreateViewModel(
            new RoutingWorkflow(new[] { noaa }, engine),
            new DelegateWeatherSampler((_, _, _, _, _, _) =>
                ValueTask.FromResult(ImmutableArray<ViewportWindSample>.Empty)));
        var departure = Now.AddDays(5).AddMinutes(1);
        viewModel.DepartureDate = departure;
        viewModel.DepartureTime = departure.TimeOfDay;

        await viewModel.CalculateRoutesAsync();

        Assert.Empty(noaa.Requests);
        Assert.Contains("forecast horizon", viewModel.ErrorMessage, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task Past_departure_rolls_forward_and_calculates_with_the_requested_duration()
    {
        var selectedRun = Now.AddHours(-6);
        var noaa = new DelegateForecastProvider(
            ForecastModel.NoaaGfs,
            (request, _) => ValueTask.FromResult(CreateAcquisition(
                request,
                new ForecastCacheUsage(3, 0, selectedRun, selectedRun.AddHours(6)))));
        RouteRequest? routed = null;
        var engine = new DelegateRouteEngine((request, forecast, _) =>
        {
            routed = request;
            return ValueTask.FromResult(CreateRoute(request, forecast.Request.Model));
        });
        var viewModel = CreateViewModel(
            new RoutingWorkflow(new[] { noaa }, engine),
            new DelegateWeatherSampler((_, _, _, _, _, _) =>
                ValueTask.FromResult(ImmutableArray<ViewportWindSample>.Empty)));
        var pastDeparture = Now.AddHours(-2);
        viewModel.DepartureDate = pastDeparture;
        viewModel.DepartureTime = pastDeparture.TimeOfDay;
        viewModel.PassageDays = 2;
        viewModel.PassageHours = 5;

        await viewModel.CalculateRoutesAsync();

        Assert.NotNull(routed);
        Assert.Equal(Now, routed.DepartureTime);
        Assert.Equal(TimeSpan.FromHours(53), routed.LatestArrivalTime - routed.DepartureTime);
        Assert.Equal(Now.Date, viewModel.DepartureDate!.Value.Date);
        Assert.Equal(Now.TimeOfDay, viewModel.DepartureTime);
        Assert.Null(viewModel.ErrorMessage);
        Assert.Contains("rolled forward", viewModel.WarningMessage, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("Calculation started anyway", viewModel.WarningMessage, StringComparison.Ordinal);
        Assert.Contains("cached run", viewModel.WarningMessage, StringComparison.OrdinalIgnoreCase);
        Assert.Single(noaa.Requests);
    }

    [Fact]
    public async Task Intermediate_waypoint_routes_sequentially_and_persists_results()
    {
        var root = Path.Combine(Path.GetTempPath(), $"navtool-multi-leg-{Guid.NewGuid():N}");
        var repository = new RoutePlanJsonRepository(root);
        var noaa = new DelegateForecastProvider(
            ForecastModel.NoaaGfs,
            (request, _) => ValueTask.FromResult(CreateAcquisition(request)));
        var engine = new DelegateRouteEngine((request, forecast, _) =>
            ValueTask.FromResult(CreateRoute(request, forecast.Request.Model)));
        ForecastAcquisition? sampledAcquisition = null;
        var viewModel = CreateViewModel(
            new RoutingWorkflow(new[] { noaa }, engine),
            new DelegateWeatherSampler((acquisition, _, _, _, _, _) =>
            {
                sampledAcquisition = acquisition;
                return ValueTask.FromResult(ImmutableArray<ViewportWindSample>.Empty);
            }),
            routePlanRepository: repository);
        viewModel.Itinerary.AddWaypointCommand.Execute(null);
        var waypoint = viewModel.Itinerary.Waypoints[1];
        waypoint.HasStopover = true;
        waypoint.StopoverHours = 2;
        waypoint.SetOnMapCommand.Execute(null);
        viewModel.HandleMapClick(
            MapProjection.ToMapPoint(new Coordinate(36, -58)),
            default);

        await viewModel.CalculateRoutesAsync();

        Assert.Equal(2, noaa.Requests.Count);
        Assert.Equal(noaa.Requests[0].Through, noaa.Requests[1].Through);
        Assert.Equal(
            noaa.Requests[0].From.AddHours(8),
            noaa.Requests[1].From);
        Assert.Equal(36, waypoint.Coordinate!.Value.Latitude, 10);
        Assert.Equal(-58, waypoint.Coordinate.Value.Longitude, 10);
        Assert.Equal(2, viewModel.SuccessfulRouteCount);
        Assert.Equal(2, viewModel.VisualizedRouteLegs.Count);
        Assert.All(
            viewModel.VisualizedRouteLegs,
            leg => Assert.Equal(viewModel.Itinerary.PlanId, leg.Key.PlanId));
        Assert.Single(viewModel.VisualizedRouteLegs.Select(leg => leg.Key.SessionId).Distinct());
        Assert.Equal(2, viewModel.VisualizedRouteLegs.Select(leg => leg.Key.LegId).Distinct().Count());
        Assert.Contains("leg 1 complete", viewModel.NoaaStatus, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("leg 2 complete", viewModel.NoaaStatus, StringComparison.OrdinalIgnoreCase);
        Assert.Equal("All itinerary legs are complete.", viewModel.StatusMessage);
        viewModel.TimelinePosition = 0.5;
        Assert.Contains("Stopover at", viewModel.TimelineDisplay);
        Assert.Contains("stationary hold", viewModel.SelectedRouteDetails);
        viewModel.Itinerary.Legs[1].SelectCommand.Execute(null);
        Assert.Equal(1, viewModel.SelectedLeg!.LegIndex);
        Assert.True(viewModel.Itinerary.Legs[1].IsSelected);
        Assert.DoesNotContain("Stopover at", viewModel.TimelineDisplay);
        await viewModel.RefreshWeatherAsync(noaa.Requests[1].Bounds, 2, 2);
        Assert.Equal(noaa.Requests[1].From, sampledAcquisition!.Request.From);

        var loaded = await repository.OpenAsync(viewModel.Itinerary.PlanId);
        Assert.Equal(2, loaded.LatestResult(ForecastModel.NoaaGfs)!.Legs.Length);
        var json = await File.ReadAllTextAsync(
            Path.Combine(repository.RootDirectory, $"{loaded.Id}.route.json"));
        Assert.DoesNotContain("fake-forecast.grib2", json, StringComparison.OrdinalIgnoreCase);

        var reopened = CreateViewModel(
            new RoutingWorkflow(new[] { noaa }, engine),
            new DelegateWeatherSampler((_, _, _, _, _, _) =>
                ValueTask.FromResult(ImmutableArray<ViewportWindSample>.Empty)),
            routePlanRepository: repository);
        await reopened.Itinerary.RefreshSavedPlansCommand.ExecuteAsync(null);
        reopened.Itinerary.SelectedSavedPlan = reopened.Itinerary.SavedPlans.Single();
        await reopened.Itinerary.OpenCommand.ExecuteAsync(null);
        Assert.Equal(2, reopened.SuccessfulRouteCount);
        Assert.True(reopened.HasTimeline);
        Assert.Null(reopened.ActiveWeatherModel);
        Assert.Contains("unavailable", reopened.WeatherLayerError, StringComparison.OrdinalIgnoreCase);
        Assert.All(reopened.Itinerary.Legs, leg => Assert.Contains("complete", leg.OutcomeStatus));
        Directory.Delete(root, recursive: true);
    }

    [Fact]
    public async Task Marking_a_leg_sailed_skips_it_during_recalculation_and_retains_history()
    {
        var root = Path.Combine(Path.GetTempPath(), $"navtool-sailed-leg-{Guid.NewGuid():N}");
        var repository = new RoutePlanJsonRepository(root);
        var routeRequests = new List<RouteRequest>();
        var noaa = new DelegateForecastProvider(
            ForecastModel.NoaaGfs,
            (request, _) => ValueTask.FromResult(CreateAcquisition(request)));
        var engine = new DelegateRouteEngine((request, forecast, _) =>
        {
            routeRequests.Add(request);
            return ValueTask.FromResult(CreateRoute(request, forecast.Request.Model));
        });
        var viewModel = CreateViewModel(
            new RoutingWorkflow(new[] { noaa }, engine),
            new DelegateWeatherSampler((_, _, _, _, _, _) =>
                ValueTask.FromResult(ImmutableArray<ViewportWindSample>.Empty)),
            routePlanRepository: repository);
        viewModel.Itinerary.AddWaypointCommand.Execute(null);
        var intermediate = viewModel.Itinerary.Waypoints[1];
        intermediate.SetOnMapCommand.Execute(null);
        viewModel.HandleMapClick(
            MapProjection.ToMapPoint(new Coordinate(36, -58)),
            default);

        await viewModel.CalculateRoutesAsync();

        Assert.Equal(2, routeRequests.Count);
        Assert.Equal(2, viewModel.Itinerary.Legs.Count);
        var firstLegId = viewModel.Itinerary.Legs[0].Id;
        var firstLegRoute = routeRequests[0];

        viewModel.Itinerary.Legs[0].MarkSailedCommand.Execute(null);
        Assert.True(viewModel.Itinerary.Legs[0].IsSailed);
        Assert.True(viewModel.Itinerary.Legs[1].IsActive);
        routeRequests.Clear();

        // Sailed leg geometry/results are history: recalculation replaces only the eligible
        // current/future leg, never the sailed one.
        await viewModel.CalculateRoutesAsync();

        var recalculated = Assert.Single(routeRequests);
        Assert.Equal(intermediate.Coordinate!.Value, recalculated.Origin);

        var reopened = await repository.OpenAsync(viewModel.Itinerary.PlanId);
        Assert.Contains(firstLegId, reopened.SailedLegIds);
        var recalculatedResult = reopened.LatestResult(ForecastModel.NoaaGfs)!;
        var retainedFirstLeg = recalculatedResult.Legs[0];
        Assert.Equal(firstLegRoute.RouteId, retainedFirstLeg.Route!.Request.RouteId);
        Assert.Equal(RouteLegOutcomeState.Succeeded, retainedFirstLeg.State);
        Assert.Equal(RouteLegOutcomeState.Succeeded, recalculatedResult.Legs[1].State);
        Assert.True(viewModel.Itinerary.PlaceCurrentPosition(
            new Coordinate(36.5, -57.5),
            firstLegRoute.DepartureTime.AddHours(10),
            out var placementError));
        Assert.Null(placementError);
        var sailedHistory = Assert.Single(viewModel.SuccessfulRoutes);
        Assert.Equal(firstLegRoute.RouteId, sailedHistory.Request.RouteId);
        Directory.Delete(root, recursive: true);
    }

    [Fact]
    public async Task Explicit_active_leg_selection_skips_the_earlier_unfinished_leg()
    {
        var noaa = new DelegateForecastProvider(
            ForecastModel.NoaaGfs,
            (request, _) => ValueTask.FromResult(CreateAcquisition(request)));
        var routeRequests = new List<RouteRequest>();
        var engine = new DelegateRouteEngine((request, forecast, _) =>
        {
            routeRequests.Add(request);
            return ValueTask.FromResult(CreateRoute(request, forecast.Request.Model));
        });
        var root = Path.Combine(Path.GetTempPath(), $"navtool-active-leg-{Guid.NewGuid():N}");
        var repository = new RoutePlanJsonRepository(root);
        var viewModel = CreateViewModel(
            new RoutingWorkflow(new[] { noaa }, engine),
            new DelegateWeatherSampler((_, _, _, _, _, _) =>
                ValueTask.FromResult(ImmutableArray<ViewportWindSample>.Empty)),
            routePlanRepository: repository);
        viewModel.Itinerary.AddWaypointCommand.Execute(null);
        var intermediate = viewModel.Itinerary.Waypoints[1];
        intermediate.SetOnMapCommand.Execute(null);
        viewModel.HandleMapClick(
            MapProjection.ToMapPoint(new Coordinate(36, -58)),
            default);

        Assert.Equal(2, viewModel.Itinerary.Legs.Count);
        // Explicitly select leg 2 as active without ever calculating (or marking sailed) leg 1.
        viewModel.Itinerary.Legs[1].MakeActiveCommand.Execute(null);
        Assert.False(viewModel.Itinerary.Legs[0].IsActive);
        Assert.True(viewModel.Itinerary.Legs[1].IsActive);

        await viewModel.CalculateRoutesAsync();

        var routed = Assert.Single(routeRequests);
        Assert.Equal(intermediate.Coordinate!.Value, routed.Origin);

        var reopened = await repository.OpenAsync(viewModel.Itinerary.PlanId);
        var result = reopened.LatestResult(ForecastModel.NoaaGfs)!;
        Assert.Equal(RouteLegOutcomeState.NotCalculated, result.Legs[0].State);
        Assert.Equal(RouteLegOutcomeReason.BeforeActiveLeg, result.Legs[0].Reason);
        Assert.Equal(RouteLegOutcomeState.Succeeded, result.Legs[1].State);
        Directory.Delete(root, recursive: true);
    }

    [Fact]
    public async Task Current_position_overrides_origin_and_departure_time_never_wall_clock()
    {
        var noaa = new DelegateForecastProvider(
            ForecastModel.NoaaGfs,
            (request, _) => ValueTask.FromResult(CreateAcquisition(request)));
        var routeRequests = new List<RouteRequest>();
        var engine = new DelegateRouteEngine((request, forecast, _) =>
        {
            routeRequests.Add(request);
            return ValueTask.FromResult(CreateRoute(request, forecast.Request.Model));
        });
        var root = Path.Combine(Path.GetTempPath(), $"navtool-current-position-{Guid.NewGuid():N}");
        var viewModel = CreateViewModel(
            new RoutingWorkflow(new[] { noaa }, engine),
            new DelegateWeatherSampler((_, _, _, _, _, _) =>
                ValueTask.FromResult(ImmutableArray<ViewportWindSample>.Empty)),
            routePlanRepository: new RoutePlanJsonRepository(root));
        var currentPosition = new Coordinate(35.5, -60);
        var explicitDeparture = Now.AddHours(9);
        viewModel.Itinerary.PlaceCurrentPosition(currentPosition, explicitDeparture, out var error);
        Assert.Null(error);

        await viewModel.CalculateRoutesAsync();

        var routed = Assert.Single(routeRequests);
        Assert.Equal(currentPosition, routed.Origin);
        Assert.Equal(explicitDeparture, routed.DepartureTime);
        Assert.NotEqual(viewModel.DepartureDate, routed.DepartureTime);
        Directory.Delete(root, recursive: true);
    }

    [Fact]
    public async Task Past_current_leg_start_rolls_forward_without_changing_sailed_history()
    {
        var root = Path.Combine(Path.GetTempPath(), $"navtool-roll-current-leg-{Guid.NewGuid():N}");
        try
        {
            var repository = new RoutePlanJsonRepository(root);
            var noaa = new DelegateForecastProvider(
                ForecastModel.NoaaGfs,
                (request, _) => ValueTask.FromResult(CreateAcquisition(request)));
            var routeRequests = new List<RouteRequest>();
            var engine = new DelegateRouteEngine((request, forecast, _) =>
            {
                routeRequests.Add(request);
                return ValueTask.FromResult(CreateRoute(request, forecast.Request.Model));
            });
            var viewModel = CreateViewModel(
                new RoutingWorkflow(new[] { noaa }, engine),
                new DelegateWeatherSampler((_, _, _, _, _, _) =>
                    ValueTask.FromResult(ImmutableArray<ViewportWindSample>.Empty)),
                routePlanRepository: repository);
            viewModel.Itinerary.AddWaypointCommand.Execute(null);
            var intermediate = viewModel.Itinerary.Waypoints[1];
            intermediate.SetOnMapCommand.Execute(null);
            viewModel.HandleMapClick(
                MapProjection.ToMapPoint(new Coordinate(36, -58)),
                default);

            await viewModel.CalculateRoutesAsync();

            var firstLeg = routeRequests[0];
            var firstLegId = viewModel.Itinerary.Legs[0].Id;
            viewModel.Itinerary.Legs[0].MarkSailedCommand.Execute(null);
            var currentPosition = new Coordinate(36.5, -57.5);
            Assert.True(viewModel.Itinerary.PlaceCurrentPosition(
                currentPosition,
                Now.AddHours(-3),
                out var placementError));
            Assert.Null(placementError);
            routeRequests.Clear();

            await viewModel.CalculateRoutesAsync();

            var activeRoute = Assert.Single(routeRequests);
            Assert.Equal(currentPosition, activeRoute.Origin);
            Assert.Equal(Now, activeRoute.DepartureTime);
            Assert.Equal(Now, viewModel.Itinerary.CurrentPositionDepartureTimeUtc);
            Assert.Equal(Now.Date, viewModel.Itinerary.CurrentPositionDepartureDate!.Value.Date);
            Assert.Equal(Now.TimeOfDay, viewModel.Itinerary.CurrentPositionDepartureTimeOfDay);
            Assert.Contains("rolled forward", viewModel.WarningMessage, StringComparison.OrdinalIgnoreCase);
            Assert.Null(viewModel.ErrorMessage);

            var reopened = await repository.OpenAsync(viewModel.Itinerary.PlanId);
            Assert.Contains(firstLegId, reopened.SailedLegIds);
            var retainedFirstLeg = reopened.LatestResult(ForecastModel.NoaaGfs)!.Legs[0];
            Assert.Equal(firstLeg.RouteId, retainedFirstLeg.Route!.Request.RouteId);
            Assert.Equal(RouteLegOutcomeState.Succeeded, retainedFirstLeg.State);
        }
        finally
        {
            Directory.Delete(root, recursive: true);
        }
    }

    [Fact]
    public async Task Cancelling_a_multi_leg_calculation_preserves_the_completed_leg()
    {
        var noaa = new DelegateForecastProvider(
            ForecastModel.NoaaGfs,
            (request, _) => ValueTask.FromResult(CreateAcquisition(request)));
        var secondLegStarted = new TaskCompletionSource(
            TaskCreationOptions.RunContinuationsAsynchronously);
        var engine = new StreamingRouteEngine(async (request, forecast, progress, cancellationToken) =>
        {
            if (request.RouteId.Contains("leg-1", StringComparison.Ordinal))
            {
                secondLegStarted.SetResult();
                await Task.Delay(Timeout.InfiniteTimeSpan, cancellationToken);
                throw new InvalidOperationException("Unreachable.");
            }

            progress?.Report(new RouteCalculationProgress(1, "fake route"));
            return CreateRoute(request, forecast.Request.Model);
        });
        var root = Path.Combine(Path.GetTempPath(), $"navtool-cancel-multi-leg-{Guid.NewGuid():N}");
        var repository = new RoutePlanJsonRepository(root);
        var viewModel = CreateViewModel(
            new RoutingWorkflow(new[] { noaa }, engine),
            new DelegateWeatherSampler((_, _, _, _, _, _) =>
                ValueTask.FromResult(ImmutableArray<ViewportWindSample>.Empty)),
            routePlanRepository: repository);
        viewModel.Itinerary.AddWaypointCommand.Execute(null);
        var intermediate = viewModel.Itinerary.Waypoints[1];
        intermediate.SetOnMapCommand.Execute(null);
        viewModel.HandleMapClick(
            MapProjection.ToMapPoint(new Coordinate(36, -58)),
            default);

        var calculation = viewModel.CalculateRoutesAsync();
        await secondLegStarted.Task;
        viewModel.CancelCommand.Execute(null);
        await calculation;

        // Manual cancellation preserves completed results; the unfinished leg is cancelled, not
        // silently dropped or reported as outside the forecast window.
        var reopened = await repository.OpenAsync(viewModel.Itinerary.PlanId);
        var result = reopened.LatestResult(ForecastModel.NoaaGfs)!;
        Assert.Equal(RouteLegOutcomeState.Succeeded, result.Legs[0].State);
        Assert.Equal(RouteLegOutcomeState.Cancelled, result.Legs[1].State);
        Assert.Equal(RouteLegOutcomeReason.CalculationCancelled, result.Legs[1].Reason);
        Directory.Delete(root, recursive: true);
    }

    [Fact]
    public async Task LocalGribSelectionRoutesWithoutCallingForecastProvider()
    {
        var noaa = new DelegateForecastProvider(
            ForecastModel.NoaaGfs,
            (request, _) => ValueTask.FromResult(CreateAcquisition(request)));
        var localPath = Path.GetFullPath("selected.grib2");
        var inspector = new DelegateLocalGribInspector((path, _) =>
        {
            Assert.Equal(localPath, path);
            return ValueTask.FromResult(new LocalForecastDescriptor(
                ForecastModel.NoaaGfs,
                new LocalGribArtifact(path),
                Now.AddHours(-6),
                Now.AddHours(-1),
                Now.AddDays(5),
                new GeographicBounds(-89, 89, -179, 179)));
        });
        var preflight = new DelegateNativeRoutingPreflight();
        var engine = new DelegateRouteEngine((request, forecast, _) =>
        {
            Assert.Equal(ForecastAcquisitionSource.LocalFile, forecast.Source);
            Assert.Equal(localPath, forecast.Artifact.Path);
            return ValueTask.FromResult(CreateRoute(request, forecast.Request.Model));
        });
        var viewModel = CreateViewModel(
            new RoutingWorkflow(new[] { noaa }, engine),
            new DelegateWeatherSampler((_, _, _, _, _, _) =>
                ValueTask.FromResult(ImmutableArray<ViewportWindSample>.Empty)),
            inspector,
            preflight);

        await viewModel.SelectLocalGribAsync(localPath);
        await viewModel.CalculateRoutesAsync();

        Assert.Equal(ForecastInputMode.LocalFile, viewModel.ForecastInputMode);
        Assert.Equal(0, noaa.CallCount);
        Assert.Equal(2, inspector.CallCount);
        Assert.Equal(1, preflight.CallCount);
        Assert.Equal(1, viewModel.SuccessfulRouteCount);
    }

    [Fact]
    public async Task MissingNativeBridgePreservesDegradedModeAndProvidesRecoveryGuidance()
    {
        var noaa = new DelegateForecastProvider(
            ForecastModel.NoaaGfs,
            (request, _) => ValueTask.FromResult(CreateAcquisition(request)));
        var engine = new DelegateRouteEngine((request, forecast, _) =>
            ValueTask.FromResult(CreateRoute(request, forecast.Request.Model)));
        var preflight = new DelegateNativeRoutingPreflight(
            new NativeBridgeUnavailableException(
                "Build the native bridge first.",
                new DllNotFoundException()));
        var viewModel = CreateViewModel(
            new RoutingWorkflow(new[] { noaa }, engine),
            new DelegateWeatherSampler((_, _, _, _, _, _) =>
                ValueTask.FromResult(ImmutableArray<ViewportWindSample>.Empty)),
            nativeRoutingPreflight: preflight);
        var pastDeparture = Now.AddHours(-2);
        viewModel.DepartureDate = pastDeparture;
        viewModel.DepartureTime = pastDeparture.TimeOfDay;

        await viewModel.CalculateRoutesAsync();

        Assert.Equal(1, preflight.CallCount);
        Assert.Equal(0, noaa.CallCount);
        Assert.False(viewModel.IsCalculating);
        Assert.Equal(0, viewModel.SuccessfulRouteCount);
        Assert.Contains("Routing engine unavailable", viewModel.ErrorMessage);
        Assert.Contains(
            OperatingSystem.IsWindows() ? @".\scripts\run.ps1" : "./scripts/run.sh",
            viewModel.ErrorMessage);
        Assert.Contains("runtimes/<RID>/native", viewModel.ErrorMessage);
        Assert.Contains("NAVTOOL_ROUTER_BRIDGE_PATH", viewModel.ErrorMessage);
        Assert.Equal("No forecast was downloaded.", viewModel.StatusMessage);
        Assert.Null(viewModel.WarningMessage);
        Assert.Equal(pastDeparture.Date, viewModel.DepartureDate!.Value.Date);
        Assert.Equal(pastDeparture.TimeOfDay, viewModel.DepartureTime);
    }

    [Fact]
    public async Task GenericNativePreflightFailureDoesNotSuggestMissingBridgeRecovery()
    {
        var noaa = new DelegateForecastProvider(
            ForecastModel.NoaaGfs,
            (request, _) => ValueTask.FromResult(CreateAcquisition(request)));
        var engine = new DelegateRouteEngine((request, forecast, _) =>
            ValueTask.FromResult(CreateRoute(request, forecast.Request.Model)));
        var preflight = new DelegateNativeRoutingPreflight(
            new InvalidOperationException("Preflight failed generically."));
        var viewModel = CreateViewModel(
            new RoutingWorkflow(new[] { noaa }, engine),
            new DelegateWeatherSampler((_, _, _, _, _, _) =>
                ValueTask.FromResult(ImmutableArray<ViewportWindSample>.Empty)),
            nativeRoutingPreflight: preflight);

        await viewModel.CalculateRoutesAsync();

        Assert.Equal(1, preflight.CallCount);
        Assert.Equal(0, noaa.CallCount);
        Assert.False(viewModel.IsCalculating);
        Assert.Equal(0, viewModel.SuccessfulRouteCount);
        Assert.Contains("Preflight failed generically.", viewModel.ErrorMessage);
        Assert.DoesNotContain("./scripts/run.sh", viewModel.ErrorMessage);
        Assert.DoesNotContain(@".\scripts\run.ps1", viewModel.ErrorMessage);
        Assert.DoesNotContain("runtimes/<RID>/native", viewModel.ErrorMessage);
        Assert.Equal("No forecast was downloaded.", viewModel.StatusMessage);
    }

    [Fact]
    public async Task MissingLandCapabilityBlocksBeforeForecastAcquisition()
    {
        var noaa = new DelegateForecastProvider(
            ForecastModel.NoaaGfs,
            (request, _) => ValueTask.FromResult(CreateAcquisition(request)));
        var engine = new DelegateRouteEngine((request, forecast, _) =>
            ValueTask.FromResult(CreateRoute(request, forecast.Request.Model)));
        var preflight = new DelegateNativeRoutingPreflight(landAvoidanceAvailable: false);
        var viewModel = CreateViewModel(
            new RoutingWorkflow(new[] { noaa }, engine),
            new DelegateWeatherSampler((_, _, _, _, _, _) =>
                ValueTask.FromResult(ImmutableArray<ViewportWindSample>.Empty)),
            nativeRoutingPreflight: preflight);

        await viewModel.CalculateRoutesAsync();

        Assert.Equal(1, preflight.CallCount);
        Assert.Equal(0, noaa.CallCount);
        Assert.Equal(0, viewModel.SuccessfulRouteCount);
        Assert.Contains("land avoidance is unavailable", viewModel.ErrorMessage);
        Assert.Equal("No forecast was downloaded.", viewModel.StatusMessage);
    }

    [Fact]
    public async Task LocalInspectorLoadsNativeImplementationOnlyWhenUsed()
    {
        var calls = 0;
        var path = Path.GetFullPath("deferred.grib2");
        var expected = new LocalForecastDescriptor(
            ForecastModel.NoaaGfs,
            new LocalGribArtifact(path),
            Now.AddHours(-6),
            Now,
            Now.AddDays(3),
            new GeographicBounds(-89, 89, -179, 179));
        var deferred = new DeferredLocalGribInspector(() =>
        {
            calls++;
            return new DelegateLocalGribInspector((_, _) => ValueTask.FromResult(expected));
        });

        Assert.Equal(0, calls);
        var actual = await deferred.InspectAsync(path);

        Assert.Equal(1, calls);
        Assert.Same(expected, actual);
    }

    [Fact]
    public async Task DeferredLocalInspectorRetriesAfterFactoryFailure()
    {
        var calls = 0;
        var path = Path.GetFullPath("retry.grib2");
        var expected = new LocalForecastDescriptor(
            ForecastModel.NoaaGfs,
            new LocalGribArtifact(path),
            Now.AddHours(-6),
            Now,
            Now.AddDays(3),
            new GeographicBounds(-89, 89, -179, 179));
        var deferred = new DeferredLocalGribInspector(() =>
        {
            if (Interlocked.Increment(ref calls) == 1)
            {
                throw new NativeBridgeUnavailableException(
                    "Bridge is not installed yet.",
                    new DllNotFoundException());
            }

            return new DelegateLocalGribInspector((_, _) => ValueTask.FromResult(expected));
        });

        await Assert.ThrowsAsync<NativeBridgeUnavailableException>(
            async () => await deferred.InspectAsync(path));
        var actual = await deferred.InspectAsync(path);

        Assert.Equal(2, calls);
        Assert.Same(expected, actual);
    }

    [Fact]
    public async Task LocalGribReinspectionCanBeCancelledBeforeRouting()
    {
        var noaa = new DelegateForecastProvider(
            ForecastModel.NoaaGfs,
            (request, _) => ValueTask.FromResult(CreateAcquisition(request)));
        var path = Path.GetFullPath("cancel-inspection.grib2");
        var descriptor = new LocalForecastDescriptor(
            ForecastModel.NoaaGfs,
            new LocalGribArtifact(path),
            Now.AddHours(-6),
            Now.AddHours(-1),
            Now.AddDays(5),
            new GeographicBounds(-89, 89, -179, 179));
        var inspectionStarted = new TaskCompletionSource(
            TaskCreationOptions.RunContinuationsAsynchronously);
        var calls = 0;
        var inspector = new DelegateLocalGribInspector(async (_, cancellationToken) =>
        {
            if (Interlocked.Increment(ref calls) == 1)
            {
                return descriptor;
            }

            inspectionStarted.SetResult();
            await Task.Delay(Timeout.InfiniteTimeSpan, cancellationToken);
            throw new InvalidOperationException("Unreachable.");
        });
        var engine = new DelegateRouteEngine((request, forecast, _) =>
            ValueTask.FromResult(CreateRoute(request, forecast.Request.Model)));
        var viewModel = CreateViewModel(
            new RoutingWorkflow(new[] { noaa }, engine),
            new DelegateWeatherSampler((_, _, _, _, _, _) =>
                ValueTask.FromResult(ImmutableArray<ViewportWindSample>.Empty)),
            inspector);
        await viewModel.SelectLocalGribAsync(path);

        var calculation = viewModel.CalculateRoutesAsync();
        await inspectionStarted.Task.WaitAsync(TimeSpan.FromSeconds(2));
        Assert.True(viewModel.CancelCommand.CanExecute(null));

        viewModel.CancelCommand.Execute(null);
        await calculation;

        Assert.Equal(0, noaa.CallCount);
        Assert.False(viewModel.IsInspectingLocalGrib);
        Assert.Equal("GRIB inspection cancelled.", viewModel.StatusMessage);
        Assert.Equal(
            "Inspection cancelled; the previous GRIB remains selected.",
            viewModel.LocalGribStatus);
    }

    [Fact]
    public async Task StreamingOverlaysRetainSuccessfulModelAndFreezeFailedModel()
    {
        var providers = new[]
        {
            new DelegateForecastProvider(
                ForecastModel.NoaaGfs,
                (request, _) => ValueTask.FromResult(CreateAcquisition(request))),
            new DelegateForecastProvider(
                ForecastModel.EcmwfIfs,
                (request, _) => ValueTask.FromResult(CreateAcquisition(request)))
        };
        var engine = new StreamingRouteEngine((request, forecast, progress, _) =>
        {
            progress?.Report(new RouteCalculationProgress(
                0.5,
                "frontier",
                CreateSnapshot(request)));
            return forecast.Request.Model == ForecastModel.EcmwfIfs
                ? ValueTask.FromException<RouteResult>(
                    new InvalidOperationException("ECMWF search failed"))
                : ValueTask.FromResult(
                    CreateRoute(request, forecast.Request.Model));
        });
        var viewModel = CreateViewModel(
            new RoutingWorkflow(providers, engine),
            new DelegateWeatherSampler((_, _, _, _, _, _) =>
                ValueTask.FromResult(ImmutableArray<ViewportWindSample>.Empty)));
        viewModel.Map.Navigator.SetSize(1280, 800);
        viewModel.UseEcmwf = true;

        await viewModel.CalculateRoutesAsync();
        await Task.Delay(20);

        Assert.Single(GetLayer(viewModel, "NOAA GFS isochrone fronts").Features);
        Assert.Single(GetLayer(viewModel, "NOAA GFS latest isochrone front").Features);
        Assert.Single(GetLayer(viewModel, "NOAA GFS provisional route").Features);
        Assert.Empty(GetLayer(viewModel, "ECMWF IFS isochrone fronts").Features);
        Assert.Empty(GetLayer(viewModel, "ECMWF IFS latest isochrone front").Features);
        Assert.Empty(GetLayer(viewModel, "ECMWF IFS provisional route").Features);
        Assert.Single(GetLayer(viewModel, "ECMWF IFS interrupted route").Features);
        Assert.True(viewModel.HasInterruptedRoute);
        Assert.Contains("ECMWF search failed", viewModel.InterruptedRouteMessage);
        Assert.Equal(1, viewModel.SuccessfulRouteCount);
        viewModel.ActivateEcmwfRouteCommand.Execute(null);
        Assert.True(viewModel.SelectedRoutePoint!.IsProvisional);
        Assert.Equal(ForecastModel.EcmwfIfs, viewModel.ActiveWeatherModel);
        viewModel.TimelinePosition = 1;
        var previewPoint = viewModel.GetProjectedRoutePoint(viewModel.SelectedRoutePoint!);
        var previewScreen = viewModel.Map.Navigator.Viewport.WorldToScreen(previewPoint);
        Assert.True(viewModel.FindRouteAt(previewPoint,
            new ScreenPoint(previewScreen.X, previewScreen.Y))!.IsProvisional);
        viewModel.ActivateNoaaRouteCommand.Execute(null);
        Assert.False(viewModel.SelectedRoutePoint!.IsProvisional);
        Assert.Equal(1, viewModel.SuccessfulRouteCount);
    }

    [Fact]
    public async Task Resource_limit_retains_immediate_snapshot_without_accepting_a_route_and_clears_on_retry()
    {
        var provider = new DelegateForecastProvider(ForecastModel.NoaaGfs,
            (request, _) => ValueTask.FromResult(CreateAcquisition(request)));
        var calls = 0;
        var engine = new StreamingRouteEngine((request, _, progress, _) =>
        {
            if (++calls == 1)
                progress?.Report(new RouteCalculationProgress(.4, "searching", CreateSnapshot(request)));
            throw new RoutingException(RoutingFailureKind.ResourceLimit, "routing search work limit reached");
        });
        var viewModel = CreateViewModel(new RoutingWorkflow([provider], engine),
            new DelegateWeatherSampler((_, _, _, _, _, _) =>
                ValueTask.FromResult(ImmutableArray<ViewportWindSample>.Empty)));
        viewModel.Map.Navigator.SetSize(1280, 800);

        await viewModel.CalculateRoutesAsync();

        Assert.Equal(1, calls);
        Assert.Empty(viewModel.SuccessfulRoutes);
        Assert.True(viewModel.HasTimeline);
        Assert.True(viewModel.HasInterruptedRoute);
        Assert.Contains("search work limit reached", viewModel.InterruptedRouteMessage);
        Assert.Contains("not a completed route", viewModel.InterruptedRouteMessage);
        Assert.Contains("interrupted", viewModel.StatusMessage);
        Assert.Equal("Stopped", viewModel.CalculationProgressDisplay);
        var message = Assert.Single(viewModel.CurrentMessages, message => message.Model == ForecastModel.NoaaGfs);
        Assert.True(message.IsInterrupted);
        Assert.Equal(0, message.LegIndex);
        Assert.DoesNotContain(viewModel.CurrentMessages, message => message.Id == "error");
        var messageGeneration = viewModel.MessageGeneration;
        Assert.Single(GetLayer(viewModel, "NOAA GFS interrupted route").Features);
        Assert.Empty(GetLayer(viewModel, "NOAA GFS provisional route").Features);
        Assert.Null(viewModel.Itinerary.CurrentPlan!.LatestResult(ForecastModel.NoaaGfs)!.Legs[0].Route);

        await viewModel.CalculateRoutesAsync();
        await Task.Delay(20);

        Assert.Equal(2, calls);
        Assert.False(viewModel.HasInterruptedRoute);
        Assert.Empty(GetLayer(viewModel, "NOAA GFS interrupted route").Features);
        Assert.Contains("search work limit reached", viewModel.ErrorMessage);
        Assert.True(viewModel.MessageGeneration > messageGeneration);
        Assert.False(Assert.Single(viewModel.CurrentMessages, message => message.Model == ForecastModel.NoaaGfs).IsInterrupted);
    }

    [Fact]
    public async Task Persistence_failure_is_not_hidden_by_a_retained_search_failure()
    {
        var provider = new DelegateForecastProvider(ForecastModel.NoaaGfs,
            (request, _) => ValueTask.FromResult(CreateAcquisition(request)));
        var engine = new StreamingRouteEngine((request, _, progress, _) =>
        {
            progress?.Report(new RouteCalculationProgress(.4, "searching", CreateSnapshot(request)));
            throw new RoutingException(RoutingFailureKind.ResourceLimit, "Search work limit reached.");
        });
        var viewModel = CreateViewModel(new RoutingWorkflow([provider], engine),
            new DelegateWeatherSampler((_, _, _, _, _, _) =>
                ValueTask.FromResult(ImmutableArray<ViewportWindSample>.Empty)),
            routePlanRepository: new FailingPlanRepository());
        viewModel.Itinerary.AddWaypointCommand.Execute(null);
        viewModel.Itinerary.Waypoints[^2].SetOnMapCommand.Execute(null);
        viewModel.HandleMapClick(MapProjection.ToMapPoint(new Coordinate(35, -60)), default);

        await viewModel.CalculateRoutesAsync();

        Assert.True(viewModel.HasInterruptedRoute);
        Assert.Contains(viewModel.CurrentMessages, message => message.IsInterrupted &&
            message.Summary.Contains("Search work limit reached.", StringComparison.Ordinal));
        Assert.Contains(viewModel.CurrentMessages, message => message.Id == "error" &&
            message.Summary.Contains("Result storage unavailable.", StringComparison.Ordinal));
    }

    [Theory]
    [InlineData(true)]
    [InlineData(false)]
    public async Task Interrupted_points_support_map_inspection_timeline_and_matching_winds(bool cancel)
    {
        ForecastAcquisition? usedForecast = null;
        RouteCalculationSnapshot? snapshot = null;
        var reported = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var provider = new DelegateForecastProvider(ForecastModel.NoaaGfs,
            (request, _) => ValueTask.FromResult(CreateAcquisition(request)));
        var engine = new StreamingRouteEngine(async (request, forecast, progress, token) =>
        {
            usedForecast = forecast;
            snapshot = CreateSnapshot(request);
            progress?.Report(new RouteCalculationProgress(.4, "searching", snapshot));
            reported.SetResult();
            if (cancel) await Task.Delay(Timeout.InfiniteTimeSpan, token);
            throw new RoutingException(RoutingFailureKind.ResourceLimit, "work limit");
        });
        ForecastAcquisition? sampledForecast = null;
        DateTimeOffset? sampledTime = null;
        var viewModel = CreateViewModel(new RoutingWorkflow([provider], engine),
            new DelegateWeatherSampler((forecast, bounds, _, _, time, _) =>
            {
                sampledForecast = forecast;
                sampledTime = time;
                return ValueTask.FromResult(ImmutableArray.Create(CreateWind(bounds, time, 15)));
            }));
        viewModel.Map.Navigator.SetSize(1280, 800);
        var calculation = viewModel.CalculateRoutesAsync();
        await reported.Task;
        if (cancel) viewModel.CancelCommand.Execute(null);
        await calculation;

        Assert.True(viewModel.HasNoaaRoutes);
        Assert.True(viewModel.HasTimeline);
        Assert.Empty(viewModel.SuccessfulRoutes);
        var endpoint = snapshot!.ProvisionalRoute[^1];
        var line = Assert.IsType<NetTopologySuite.Geometries.LineString>(
            Assert.IsType<Mapsui.Nts.GeometryFeature>(
                Assert.Single(GetLayer(viewModel, "NOAA GFS interrupted route").Features)).Geometry);
        var world = new Mapsui.MPoint(line.EndPoint.X, line.EndPoint.Y);
        var screen = viewModel.Map.Navigator.Viewport.WorldToScreen(world);
        Assert.True(viewModel.CanInspectRouteAt(world, new ScreenPoint(screen.X, screen.Y)));
        Assert.True(viewModel.InspectRouteAt(world, new ScreenPoint(screen.X, screen.Y), focus: false));

        var selection = Assert.IsType<RouteMapSelection>(viewModel.SelectedRoutePoint);
        Assert.True(selection.IsProvisional);
        Assert.Null(selection.Route);
        Assert.Same(endpoint, selection.Point);
        Assert.Equal(endpoint.Timestamp, viewModel.SelectedTimelineUtc);
        Assert.Equal(world, viewModel.GetProjectedRoutePoint(selection));
        Assert.Contains("provisional", viewModel.SelectedRouteTitle);
        Assert.Contains("interrupted / provisional endpoint", viewModel.SelectedRouteDetails);
        Assert.Equal(ForecastModel.NoaaGfs, viewModel.ActiveWeatherModel);
        await viewModel.RefreshWeatherAsync(usedForecast!.Request.Bounds, 2, 2);
        Assert.Same(usedForecast, sampledForecast);
        Assert.Equal(endpoint.Timestamp, sampledTime);
        Assert.True(viewModel.WeatherCellCount > 0);

        Assert.False(viewModel.NextTimelineCommand.CanExecute(null));
        viewModel.PreviousTimelineCommand.Execute(null);
        Assert.Equal(snapshot.ProvisionalRoute[0].Timestamp, viewModel.SelectedTimelineUtc);
        viewModel.NextTimelineCommand.Execute(null);
        Assert.Equal(endpoint.Timestamp, viewModel.SelectedTimelineUtc);
        viewModel.TimelinePosition = .75;
        Assert.True(viewModel.SelectedRoutePoint!.IsProvisional);
        Assert.Equal(snapshot.ProvisionalRoute[0].Timestamp.AddMinutes(45), viewModel.SelectedTimelineUtc);
        await viewModel.RefreshWeatherAsync(usedForecast.Request.Bounds, 2, 2);
        Assert.Equal(viewModel.SelectedTimelineUtc, sampledTime);

        viewModel.RoutingSetup.PerformancePercentage = 90;
        Assert.False(viewModel.HasInterruptedRoute);
        Assert.False(viewModel.HasTimeline);
        Assert.Null(viewModel.SelectedRoutePoint);
        Assert.Null(viewModel.ActiveWeatherModel);
        Assert.Equal(0, viewModel.WeatherCellCount);
        viewModel.SelectRoutePoint(selection, focus: false);
        Assert.Null(viewModel.SelectedRoutePoint);
    }

    [Theory]
    [InlineData(false, false)]
    [InlineData(false, true)]
    [InlineData(true, false)]
    [InlineData(true, true)]
    public async Task Interrupted_weather_requires_full_forecast_window_coverage(bool useCoverage, bool covered)
    {
        var provider = new DelegateForecastProvider(ForecastModel.NoaaGfs, (request, _) =>
        {
            var acquisition = CreateAcquisition(request);
            return ValueTask.FromResult(useCoverage
                ? new ForecastAcquisition(request, acquisition.Run, acquisition.Artifact, acquisition.Source,
                    coverage: new ForecastCoverage(request.Bounds, [request.From, request.From.AddHours(1)]))
                : acquisition);
        });
        var engine = new StreamingRouteEngine((request, forecast, progress, _) =>
        {
            var snapshot = CreateSnapshot(request);
            var endpoint = snapshot.ProvisionalRoute[^1];
            var end = (forecast.Coverage?.ValidThrough ?? forecast.Request.Through)
                .AddMinutes(covered ? 0 : 1);
            progress?.Report(new RouteCalculationProgress(.4, "searching",
                new RouteCalculationSnapshot(end, snapshot.EnvelopeSegments, snapshot.FrontSegments,
                    [
                        snapshot.ProvisionalRoute[0],
                        new RoutePoint(endpoint.Location, end, 90, 6, 15, 180, 10)
                    ], snapshot.Diagnostics)));
            throw new RoutingException(RoutingFailureKind.ResourceLimit, "work limit");
        });
        var samples = 0;
        var viewModel = CreateViewModel(new RoutingWorkflow([provider], engine),
            new DelegateWeatherSampler((_, _, _, _, _, _) =>
            {
                samples++;
                return ValueTask.FromResult(ImmutableArray<ViewportWindSample>.Empty);
            }));

        await viewModel.CalculateRoutesAsync();

        Assert.True(viewModel.HasInterruptedRoute);
        Assert.True(viewModel.HasTimeline);
        Assert.Equal(covered, viewModel.HasNoaaWeather);
        viewModel.TimelinePosition = 1;
        Assert.True(viewModel.SelectedRoutePoint!.IsProvisional);
        Assert.Equal(covered, viewModel.HasNoaaWeather);
        Assert.Equal(covered ? ForecastModel.NoaaGfs : (ForecastModel?)null, viewModel.ActiveWeatherModel);
        await viewModel.RefreshWeatherAsync(provider.LastRequest!.Bounds, 2, 2);
        Assert.Equal(covered ? 1 : 0, samples);
        if (!covered)
        {
            Assert.Contains("Weather is unavailable", viewModel.WeatherLayerError);
            Assert.Contains("weather unavailable", viewModel.SelectedRouteDetails);
        }
    }

    [Theory]
    [InlineData(true)]
    [InlineData(false)]
    public async Task Terminal_failure_preserves_visible_preview_or_fits_it_without_fitting_old_routes(bool visible)
    {
        var provider = new DelegateForecastProvider(ForecastModel.NoaaGfs,
            (request, _) => ValueTask.FromResult(CreateAcquisition(request)));
        var ecmwf = new DelegateForecastProvider(ForecastModel.EcmwfIfs,
            (request, _) => ValueTask.FromResult(CreateAcquisition(request)));
        var engine = new StreamingRouteEngine((request, forecast, progress, _) =>
        {
            if (forecast.Run.Model == ForecastModel.EcmwfIfs)
                return ValueTask.FromResult(CreateRoute(request, ForecastModel.EcmwfIfs));
            progress?.Report(new RouteCalculationProgress(.4, "searching", CreateSnapshot(request)));
            throw new RoutingException(RoutingFailureKind.ResourceLimit, "work limit");
        });
        var viewModel = CreateViewModel(new RoutingWorkflow([provider, ecmwf], engine),
            new DelegateWeatherSampler((_, _, _, _, _, _) =>
                ValueTask.FromResult(ImmutableArray<ViewportWindSample>.Empty)));
        viewModel.UseEcmwf = true;
        viewModel.Map.Navigator.SetSize(1280, 800);
        viewModel.Map.Navigator.CenterOnAndZoomTo(
            MapProjection.ToMapPoint(visible ? new Coordinate(34.125, -63.875) : new Coordinate(0, 0)),
            1000);
        var before = viewModel.Map.Navigator.Viewport;

        await viewModel.CalculateRoutesAsync();

        Assert.True(viewModel.HasInterruptedRoute);
        Assert.Single(viewModel.SuccessfulRoutes);
        var after = viewModel.Map.Navigator.Viewport;
        if (visible) Assert.Equal(before, after);
        else Assert.NotEqual(before, after);
        var extent = after.ToExtent();
        foreach (var location in new[] { new Coordinate(34, -64), new Coordinate(34.25, -63.75) })
        {
            var point = MapProjection.ToMapPoint(location);
            Assert.InRange(point.X, extent.Left, extent.Right);
            Assert.InRange(point.Y, extent.Bottom, extent.Top);
        }
    }

    [AvaloniaFact]
    public async Task Map_click_on_interrupted_path_opens_provisional_telemetry()
    {
        var provider = new DelegateForecastProvider(ForecastModel.NoaaGfs,
            (request, _) => ValueTask.FromResult(CreateAcquisition(request)));
        var engine = new StreamingRouteEngine((request, _, progress, _) =>
        {
            progress?.Report(new RouteCalculationProgress(.4, "searching", CreateSnapshot(request)));
            throw new RoutingException(RoutingFailureKind.ResourceLimit, "work limit");
        });
        var viewModel = CreateViewModel(new RoutingWorkflow([provider], engine),
            new DelegateWeatherSampler((_, _, _, _, _, _) =>
                ValueTask.FromResult(ImmutableArray<ViewportWindSample>.Empty)));
        var window = new MainWindow { DataContext = viewModel, Width = 1400, Height = 900 };
        try
        {
            window.Show();
            await viewModel.CalculateRoutesAsync();
            Dispatcher.UIThread.RunJobs();
            var line = Assert.IsType<NetTopologySuite.Geometries.LineString>(
                Assert.IsType<Mapsui.Nts.GeometryFeature>(
                    Assert.Single(GetLayer(viewModel, "NOAA GFS interrupted route").Features)).Geometry);
            var world = new Mapsui.MPoint(line.EndPoint.X, line.EndPoint.Y);
            var screen = viewModel.Map.Navigator.Viewport.WorldToScreen(world);

            viewModel.HandleMapClick(world, screen);
            Dispatcher.UIThread.RunJobs();

            Assert.True(viewModel.SelectedRoutePoint!.IsProvisional);
            Assert.True(window.FindControl<Canvas>("RouteTelemetryLayer")!.IsVisible);
            Assert.Equal(viewModel.SelectedRoutePoint.TimelineTimestamp.ToString("dd MMM · HH:mm") + " UTC",
                window.FindControl<TextBlock>("RouteTelemetryTime")!.Text);
            viewModel.RoutingSetup.PerformancePercentage = 90;
            Dispatcher.UIThread.RunJobs();
            Assert.False(window.FindControl<Canvas>("RouteTelemetryLayer")!.IsVisible);
        }
        finally
        {
            window.Close();
        }
    }

    [Fact]
    public async Task Clearing_interrupted_path_rejects_a_late_weather_response()
    {
        var provider = new DelegateForecastProvider(ForecastModel.NoaaGfs,
            (request, _) => ValueTask.FromResult(CreateAcquisition(request)));
        var engine = new StreamingRouteEngine((request, _, progress, _) =>
        {
            progress?.Report(new RouteCalculationProgress(.4, "searching", CreateSnapshot(request)));
            throw new RoutingException(RoutingFailureKind.ResourceLimit, "work limit");
        });
        var started = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var release = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var viewModel = CreateViewModel(new RoutingWorkflow([provider], engine),
            new DelegateWeatherSampler(async (_, bounds, _, _, time, _) =>
            {
                started.TrySetResult();
                await release.Task;
                return ImmutableArray.Create(CreateWind(bounds, time, 15));
            }));
        await viewModel.CalculateRoutesAsync();
        var request = viewModel.RefreshWeatherAsync(provider.LastRequest!.Bounds, 2, 2);
        await started.Task;
        viewModel.RoutingSetup.PerformancePercentage = 90;
        release.SetResult();
        await request;
        Assert.Null(viewModel.SelectedRoutePoint);
        Assert.Null(viewModel.ActiveWeatherModel);
        Assert.Equal(0, viewModel.WeatherCellCount);
    }

    [Theory]
    [InlineData(-1)]
    [InlineData(1)]
    public async Task Interrupted_dateline_hit_and_focus_use_the_rendered_world_copy(int worldCopy)
    {
        var provider = new DelegateForecastProvider(ForecastModel.NoaaGfs,
            (request, _) => ValueTask.FromResult(CreateAcquisition(request)));
        var engine = new StreamingRouteEngine((request, _, progress, _) =>
        {
            var endpoint = new Coordinate(34.25, -179.75);
            var snapshot = new RouteCalculationSnapshot(request.DepartureTime.AddHours(1),
                [new RouteCalculationEnvelopeSegment([request.Origin, endpoint], false)],
                [new RouteCalculationFrontSegment([request.Origin, endpoint])],
                [
                    new RoutePoint(request.Origin, request.DepartureTime, 90, 6, 15, 180, 0),
                    new RoutePoint(endpoint, request.DepartureTime.AddHours(1), 90, 6, 15, 180, 10)
                ], new RouteDiagnostics(1, 2, 1, 1));
            progress?.Report(new RouteCalculationProgress(.4, "searching", snapshot));
            throw new RoutingException(RoutingFailureKind.ResourceLimit, "work limit");
        });
        var viewModel = CreateViewModel(new RoutingWorkflow([provider], engine),
            new DelegateWeatherSampler((_, _, _, _, _, _) =>
                ValueTask.FromResult(ImmutableArray<ViewportWindSample>.Empty)));
        viewModel.SetEndpoints(new Coordinate(34, 179.75), new Coordinate(39, -170));
        viewModel.Map.Navigator.SetSize(1280, 800);
        viewModel.Map.Navigator.CenterOnAndZoomTo(
            new Mapsui.MPoint(worldCopy * MapProjection.WebMercatorWorldWidth / 2, 4_000_000), 10_000);
        await viewModel.CalculateRoutesAsync();
        var line = Assert.IsType<NetTopologySuite.Geometries.LineString>(
            Assert.IsType<Mapsui.Nts.GeometryFeature>(
                Assert.Single(GetLayer(viewModel, "NOAA GFS interrupted route").Features)).Geometry);
        Assert.True(line.EnvelopeInternal.Width < MapProjection.WebMercatorWorldWidth / 2);
        var world = new Mapsui.MPoint(line.EndPoint.X, line.EndPoint.Y);
        var screen = viewModel.Map.Navigator.Viewport.WorldToScreen(world);
        Assert.True(viewModel.InspectRouteAt(world, new ScreenPoint(screen.X, screen.Y)));
        Assert.Equal(world, viewModel.GetProjectedRoutePoint(viewModel.SelectedRoutePoint!));
        var focused = viewModel.Map.Navigator.Viewport.WorldToScreen(world);
        Assert.InRange(focused.X, 0, viewModel.Map.Navigator.Viewport.Width);
        Assert.InRange(focused.Y, 0, viewModel.Map.Navigator.Viewport.Height);
    }

    [Theory]
    [InlineData(RoutingFailureKind.InvalidNativeOutput)]
    [InlineData(RoutingFailureKind.InvalidForecast)]
    public async Task Invalid_output_or_forecast_never_promotes_a_preview(RoutingFailureKind kind)
    {
        var provider = new DelegateForecastProvider(ForecastModel.NoaaGfs,
            (request, _) => ValueTask.FromResult(CreateAcquisition(request)));
        var engine = new StreamingRouteEngine((request, _, progress, _) =>
        {
            progress?.Report(new RouteCalculationProgress(.4, "searching", CreateSnapshot(request)));
            throw new RoutingException(kind, "invalid native data");
        });
        var viewModel = CreateViewModel(new RoutingWorkflow([provider], engine),
            new DelegateWeatherSampler((_, _, _, _, _, _) =>
                ValueTask.FromResult(ImmutableArray<ViewportWindSample>.Empty)));

        await viewModel.CalculateRoutesAsync();

        Assert.False(viewModel.HasInterruptedRoute);
        Assert.Empty(GetLayer(viewModel, "NOAA GFS interrupted route").Features);
        Assert.Contains("invalid native data", viewModel.ErrorMessage);
    }

    [Fact]
    public async Task Changed_inputs_discard_the_retained_preview()
    {
        var provider = new DelegateForecastProvider(ForecastModel.NoaaGfs,
            (request, _) => ValueTask.FromResult(CreateAcquisition(request)));
        var engine = new StreamingRouteEngine((request, _, progress, _) =>
        {
            progress?.Report(new RouteCalculationProgress(.4, "searching", CreateSnapshot(request)));
            throw new RoutingException(RoutingFailureKind.ResourceLimit, "work limit");
        });
        var viewModel = CreateViewModel(new RoutingWorkflow([provider], engine),
            new DelegateWeatherSampler((_, _, _, _, _, _) =>
                ValueTask.FromResult(ImmutableArray<ViewportWindSample>.Empty)));
        await viewModel.CalculateRoutesAsync();
        Assert.True(viewModel.HasInterruptedRoute);

        viewModel.RoutingSetup.PerformancePercentage = 90;

        Assert.False(viewModel.HasInterruptedRoute);
        Assert.Empty(GetLayer(viewModel, "NOAA GFS interrupted route").Features);
    }

    [Fact]
    public async Task Input_change_cancellation_rejects_late_snapshots_from_old_calculation()
    {
        var provider = new DelegateForecastProvider(ForecastModel.NoaaGfs,
            (request, _) => ValueTask.FromResult(CreateAcquisition(request)));
        var started = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var release = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var engineFinished = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var engine = new StreamingRouteEngine(async (request, _, progress, _) =>
        {
            progress?.Report(new RouteCalculationProgress(.4, "searching", CreateSnapshot(request)));
            started.SetResult();
            await release.Task;
            progress?.Report(new RouteCalculationProgress(.6, "late search", CreateSnapshot(request)));
            engineFinished.SetResult();
            throw new RoutingException(RoutingFailureKind.ResourceLimit, "old work limit");
        });
        var viewModel = CreateViewModel(new RoutingWorkflow([provider], engine),
            new DelegateWeatherSampler((_, _, _, _, _, _) =>
                ValueTask.FromResult(ImmutableArray<ViewportWindSample>.Empty)));
        var calculation = viewModel.CalculateRoutesAsync();
        await started.Task;

        viewModel.RoutingSetup.PerformancePercentage = 90;
        release.SetResult();
        await calculation;
        await engineFinished.Task;
        await Task.Delay(20);

        Assert.False(viewModel.HasInterruptedRoute);
        Assert.Empty(GetLayer(viewModel, "NOAA GFS interrupted route").Features);
        Assert.Empty(GetLayer(viewModel, "NOAA GFS provisional route").Features);
        Assert.Contains("changed", viewModel.StatusMessage);
    }

    [Theory]
    [InlineData(1, false)]
    [InlineData(2, false)]
    [InlineData(1, true)]
    [InlineData(2, true)]
    public async Task Interrupted_itinerary_retains_failed_leg_preview_without_saving_it_or_running_successors(
        int failedLeg, bool cancel)
    {
        var root = Path.Combine(Path.GetTempPath(), $"navtool-interrupted-{Guid.NewGuid():N}");
        var repository = new RoutePlanJsonRepository(root);
        try
        {
            var provider = new DelegateForecastProvider(ForecastModel.NoaaGfs,
                (request, _) => ValueTask.FromResult(CreateAcquisition(request)));
            var calls = 0;
            var reported = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
            ForecastAcquisition? interruptedForecast = null;
            ForecastAcquisition? sampledForecast = null;
            var engine = new StreamingRouteEngine(async (request, forecast, progress, token) =>
            {
                if (++calls != failedLeg) return CreateRoute(request, forecast.Run.Model);
                interruptedForecast = forecast;
                progress?.Report(new RouteCalculationProgress(.4, "searching", CreateSnapshot(request)));
                reported.SetResult();
                if (cancel) await Task.Delay(Timeout.InfiniteTimeSpan, token);
                throw new RoutingException(RoutingFailureKind.ResourceLimit, "routing search work limit reached");
            });
            var viewModel = CreateViewModel(new RoutingWorkflow([provider], engine),
                new DelegateWeatherSampler((forecast, _, _, _, _, _) =>
                {
                    sampledForecast = forecast;
                    return ValueTask.FromResult(ImmutableArray<ViewportWindSample>.Empty);
                }),
                routePlanRepository: repository);
            for (var index = 0; index < 2; index++)
            {
                viewModel.Itinerary.AddWaypointCommand.Execute(null);
                viewModel.Itinerary.Waypoints[^2].SetOnMapCommand.Execute(null);
                viewModel.HandleMapClick(MapProjection.ToMapPoint(new Coordinate(35 + index, -60 + index)), default);
            }
            viewModel.Map.Navigator.SetSize(1280, 800);

            var calculation = viewModel.CalculateRoutesAsync();
            await reported.Task;
            if (cancel) viewModel.CancelCommand.Execute(null);
            await calculation;

            Assert.Equal(failedLeg, calls);
            Assert.Equal(failedLeg - 1, viewModel.SuccessfulRouteCount);
            Assert.True(viewModel.HasInterruptedRoute);
            Assert.Contains($"leg {failedLeg}", viewModel.InterruptedRouteMessage);
            var message = Assert.Single(viewModel.CurrentMessages, message => message.Model == ForecastModel.NoaaGfs);
            Assert.True(message.IsInterrupted);
            Assert.Equal(failedLeg - 1, message.LegIndex);
            Assert.DoesNotContain(viewModel.CurrentMessages, message => message.Id == "error");
            Assert.Contains(cancel ? "Cancelled by user" : "search work limit reached",
                viewModel.InterruptedRouteMessage);
            Assert.Single(GetLayer(viewModel, "NOAA GFS interrupted route").Features);
            viewModel.TimelinePosition = 1;
            Assert.True(viewModel.SelectedRoutePoint!.IsProvisional);
            Assert.Equal(failedLeg - 1, viewModel.SelectedRoutePoint.Source.Preview!.LegIndex);
            Assert.Equal(viewModel.SelectedRoutePoint.Point.Timestamp, viewModel.SelectedTimelineUtc);
            Assert.True(viewModel.HasNoaaWeather);
            await viewModel.RefreshWeatherAsync(interruptedForecast!.Request.Bounds, 2, 2);
            Assert.Same(interruptedForecast, sampledForecast);
            var loaded = await repository.OpenAsync(viewModel.Itinerary.PlanId);
            var legs = loaded.LatestResult(ForecastModel.NoaaGfs)!.Legs;
            Assert.Equal(cancel ? RouteLegOutcomeState.Cancelled : RouteLegOutcomeState.Failed,
                legs[failedLeg - 1].State);
            Assert.Null(legs[failedLeg - 1].Route);
            Assert.All(legs.Skip(failedLeg), leg =>
            {
                Assert.Equal(cancel ? RouteLegOutcomeState.Cancelled : RouteLegOutcomeState.Blocked, leg.State);
                Assert.Null(leg.Route);
            });

            await viewModel.Itinerary.RefreshSavedPlansCommand.ExecuteAsync(null);
            viewModel.Itinerary.SelectedSavedPlan = viewModel.Itinerary.SavedPlans.Single();
            await viewModel.Itinerary.OpenCommand.ExecuteAsync(null);
            Assert.False(viewModel.HasInterruptedRoute);
        }
        finally
        {
            if (Directory.Exists(root)) Directory.Delete(root, recursive: true);
        }
    }

    [Fact]
    public async Task ForecastLimitedRouteRetainsOverlaysTimelineAndShowsWarning()
    {
        var provider = new DelegateForecastProvider(
            ForecastModel.NoaaGfs,
            (request, _) => ValueTask.FromResult(CreateAcquisition(request)));
        var engine = new StreamingRouteEngine((request, forecast, progress, _) =>
        {
            var snapshot = CreateSnapshot(request);
            progress?.Report(new RouteCalculationProgress(1, "forecast ended", snapshot));
            return ValueTask.FromResult(new RouteResult(
                request,
                forecast.Request.Model,
                snapshot.ProvisionalRoute,
                snapshot.Diagnostics,
                RouteCompletion.ForecastExhausted));
        });
        var viewModel = CreateViewModel(
            new RoutingWorkflow(new[] { provider }, engine),
            new DelegateWeatherSampler((_, _, _, _, _, _) =>
                ValueTask.FromResult(ImmutableArray<ViewportWindSample>.Empty)));

        await viewModel.CalculateRoutesAsync();
        await Task.Delay(20);

        var route = Assert.Single(viewModel.SuccessfulRoutes);
        Assert.True(route.IsForecastLimited);
        Assert.True(viewModel.HasTimeline);
        Assert.Same(route, viewModel.SelectedRoutePoint!.Route);
        viewModel.SelectRoutePoint(
            new RouteMapSelection(
                route,
                route.Points.Length - 1,
                route.Points[^1],
                RouteHitKind.RoutePoint,
                0),
            focus: false);
        Assert.Equal(route.ArrivalTime, viewModel.SelectedTimelineUtc);
        Assert.Contains(
            "forecast-limited endpoint",
            viewModel.SelectedRouteDetails,
            StringComparison.OrdinalIgnoreCase);
        Assert.Contains("forecast ended", viewModel.NoaaStatus, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("no more available forecast", viewModel.WarningMessage, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("best estimate for now", viewModel.WarningMessage, StringComparison.OrdinalIgnoreCase);
        Assert.Null(viewModel.ErrorMessage);
        Assert.Single(GetLayer(viewModel, "NOAA GFS isochrone fronts").Features);
        Assert.Single(GetLayer(viewModel, "NOAA GFS latest isochrone front").Features);
        Assert.Single(GetLayer(viewModel, "NOAA GFS provisional route").Features);
        Assert.Single(GetLayer(viewModel, "NOAA GFS routes").Features);
    }

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public async Task Coastal_progress_and_final_details_distinguish_proof_counters_and_unavailable(bool available)
    {
        var coastal = available ? new RouteCoastalPruningDiagnostics(
            RouteCoastalPruningMode.ConservativeLandAware, "bound_unavailable", "Unknown coverage",
            11, 12, 13, 14, 15, 16, 17, seedStatus: "no_incumbent") : null;
        var provider = new DelegateForecastProvider(ForecastModel.NoaaGfs,
            (request, _) => ValueTask.FromResult(CreateAcquisition(request)));
        var engine = new StreamingRouteEngine((request, forecast, progress, _) =>
        {
            var snapshot = CreateSnapshot(request, coastal);
            progress?.Report(new RouteCalculationProgress(1, "forecast ended", snapshot));
            return ValueTask.FromResult(new RouteResult(request, forecast.Request.Model,
                snapshot.ProvisionalRoute, snapshot.Diagnostics, RouteCompletion.ForecastExhausted));
        });
        var vm = CreateViewModel(new RoutingWorkflow([provider], engine),
            new DelegateWeatherSampler((_, _, _, _, _, _) =>
                ValueTask.FromResult(ImmutableArray<ViewportWindSample>.Empty)));
        vm.RoutingSetup.EnableCoastalPruning = available;
        await vm.CalculateRoutesAsync();
        await Task.Delay(20);
        Assert.Null(vm.ErrorMessage);
        Assert.Single(vm.SuccessfulRoutes);
        Assert.Contains("Current coastal audit", vm.LiveSearchStatus);
        Assert.Contains("Final coastal audit", vm.SelectedRouteDetails);
        foreach (var text in new[] { vm.LiveSearchStatus, vm.SelectedRouteDetails })
        {
            if (!available)
            {
                Assert.Contains("unavailable (not zero)", text);
                continue;
            }
            Assert.Contains("state bound_unavailable", text);
            Assert.Contains("seed no_incumbent", text);
            Assert.Contains("reason Unknown coverage", text);
            Assert.Contains("Coastal skipped parents 11", text);
            Assert.Contains("disconnected candidates 12", text);
            Assert.Contains("horizon candidates 13", text);
            Assert.Contains("incumbent candidates 14", text);
            Assert.Contains("Coastal bound unavailable 15", text);
            Assert.Contains("seed evaluations 16", text);
            Assert.Contains("topology work 17", text);
            Assert.Contains("Coastal incumbent arrival unavailable", text);
        }
    }

    [Fact]
    public async Task DurationLimitedRouteRetainsTimelineAndShowsDistinctWarning()
    {
        var provider = new DelegateForecastProvider(
            ForecastModel.NoaaGfs,
            (request, _) => ValueTask.FromResult(CreateAcquisition(request)));
        var engine = new StreamingRouteEngine((request, forecast, progress, _) =>
        {
            var snapshot = CreateSnapshot(request);
            progress?.Report(new RouteCalculationProgress(1, "duration ended", snapshot));
            return ValueTask.FromResult(new RouteResult(
                request,
                forecast.Request.Model,
                snapshot.ProvisionalRoute,
                snapshot.Diagnostics,
                RouteCompletion.DurationExhausted));
        });
        var viewModel = CreateViewModel(
            new RoutingWorkflow(new[] { provider }, engine),
            new DelegateWeatherSampler((_, _, _, _, _, _) =>
                ValueTask.FromResult(ImmutableArray<ViewportWindSample>.Empty)));

        await viewModel.CalculateRoutesAsync();
        await Task.Delay(20);

        var route = Assert.Single(viewModel.SuccessfulRoutes);
        Assert.True(route.IsDurationLimited);
        Assert.True(viewModel.HasTimeline);
        Assert.Contains("partial route estimate", viewModel.StatusMessage, StringComparison.OrdinalIgnoreCase);
        viewModel.SelectRoutePoint(
            new RouteMapSelection(
                route,
                route.Points.Length - 1,
                route.Points[^1],
                RouteHitKind.RoutePoint,
                0),
            focus: false);
        Assert.Contains(
            "duration-limited endpoint",
            viewModel.SelectedRouteDetails,
            StringComparison.OrdinalIgnoreCase);
        Assert.Contains("duration limit reached", viewModel.NoaaStatus, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("maximum route duration", viewModel.WarningMessage, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("destination was not reached", viewModel.WarningMessage, StringComparison.OrdinalIgnoreCase);
        Assert.Null(viewModel.ErrorMessage);
        Assert.Single(GetLayer(viewModel, "NOAA GFS isochrone fronts").Features);
        Assert.Single(GetLayer(viewModel, "NOAA GFS latest isochrone front").Features);
        Assert.Single(GetLayer(viewModel, "NOAA GFS provisional route").Features);
        Assert.Single(GetLayer(viewModel, "NOAA GFS routes").Features);
    }

    [Fact]
    public async Task CancellingCalculationFreezesPathAndClearsLiveSearchOverlays()
    {
        var provider = new DelegateForecastProvider(
            ForecastModel.NoaaGfs,
            (request, _) => ValueTask.FromResult(CreateAcquisition(request)));
        var reported = new TaskCompletionSource(
            TaskCreationOptions.RunContinuationsAsynchronously);
        var engine = new StreamingRouteEngine(async (request, _, progress, cancellationToken) =>
        {
            progress?.Report(new RouteCalculationProgress(
                0.5,
                "frontier",
                CreateSnapshot(request)));
            reported.SetResult();
            await Task.Delay(Timeout.InfiniteTimeSpan, cancellationToken);
            throw new InvalidOperationException("Unreachable.");
        });
        var viewModel = CreateViewModel(
            new RoutingWorkflow(new[] { provider }, engine),
            new DelegateWeatherSampler((_, _, _, _, _, _) =>
                ValueTask.FromResult(ImmutableArray<ViewportWindSample>.Empty)));

        var calculation = viewModel.CalculateRoutesAsync();
        await reported.Task;
        await Task.Delay(20);
        Assert.Single(GetLayer(viewModel, "NOAA GFS isochrone fronts").Features);
        Assert.Single(GetLayer(viewModel, "NOAA GFS latest isochrone front").Features);

        viewModel.CancelCommand.Execute(null);
        await calculation;

        Assert.Empty(GetLayer(viewModel, "NOAA GFS isochrone fronts").Features);
        Assert.Empty(GetLayer(viewModel, "NOAA GFS latest isochrone front").Features);
        Assert.Empty(GetLayer(viewModel, "NOAA GFS provisional route").Features);
        Assert.Single(GetLayer(viewModel, "NOAA GFS interrupted route").Features);
        Assert.Contains("Cancelled by user", viewModel.InterruptedRouteMessage);
        Assert.Empty(viewModel.SuccessfulRoutes);
    }

    [Fact]
    public async Task CalculationProgressSummarizesForecastAndRoutingWithoutASelectedResult()
    {
        var forecastStarted = new TaskCompletionSource(
            TaskCreationOptions.RunContinuationsAsynchronously);
        var releaseForecast = new TaskCompletionSource<ForecastAcquisition>(
            TaskCreationOptions.RunContinuationsAsynchronously);
        var routingStarted = new TaskCompletionSource(
            TaskCreationOptions.RunContinuationsAsynchronously);
        var releaseRoute = new TaskCompletionSource(
            TaskCreationOptions.RunContinuationsAsynchronously);
        var provider = new DelegateForecastProvider(
            ForecastModel.NoaaGfs,
            async (_, cancellationToken) =>
            {
                forecastStarted.SetResult();
                return await releaseForecast.Task.WaitAsync(cancellationToken);
            });
        var engine = new StreamingRouteEngine(async (request, forecast, progress, cancellationToken) =>
        {
            progress?.Report(new RouteCalculationProgress(0.4, "frontier"));
            routingStarted.SetResult();
            await releaseRoute.Task.WaitAsync(cancellationToken);
            return CreateRoute(request, forecast.Request.Model);
        });
        var viewModel = CreateViewModel(
            new RoutingWorkflow([provider], engine),
            new DelegateWeatherSampler((_, _, _, _, _, _) =>
                ValueTask.FromResult(ImmutableArray<ViewportWindSample>.Empty)));
        viewModel.Itinerary.RouteName = "Atlantic delivery";

        var calculation = viewModel.CalculateRoutesAsync();
        await forecastStarted.Task.WaitAsync(TimeSpan.FromSeconds(2));
        await WaitForAsync(() =>
            viewModel.CalculationStageLabel == "Downloading weather data");

        Assert.True(viewModel.IsCalculating);
        Assert.Equal("Atlantic delivery", viewModel.CalculationRouteTitle);
        Assert.Equal("NOAA", viewModel.CalculationModelLabel);
        Assert.Equal("No route point selected", viewModel.SelectedRouteTitle);
        Assert.Equal(0.25, viewModel.ProgressFraction, 10);

        releaseForecast.SetResult(CreateAcquisition(provider.LastRequest!));
        await routingStarted.Task.WaitAsync(TimeSpan.FromSeconds(2));
        await WaitForAsync(() => viewModel.CalculationStageLabel == "Calculating routes");

        Assert.Equal(0.7, viewModel.ProgressFraction, 10);

        releaseRoute.SetResult();
        await calculation;
        Assert.False(viewModel.IsCalculating);
    }

    [AvaloniaFact]
    public async Task CalculationProgressCombinesConcurrentModelStages()
    {
        var ecmwfForecastStarted = new TaskCompletionSource(
            TaskCreationOptions.RunContinuationsAsynchronously);
        var noaaRoutingStarted = new TaskCompletionSource(
            TaskCreationOptions.RunContinuationsAsynchronously);
        var noaa = new DelegateForecastProvider(
            ForecastModel.NoaaGfs,
            (request, _) => ValueTask.FromResult(CreateAcquisition(request)));
        var ecmwf = new DelegateForecastProvider(
            ForecastModel.EcmwfIfs,
            async (_, cancellationToken) =>
            {
                ecmwfForecastStarted.SetResult();
                await Task.Delay(Timeout.InfiniteTimeSpan, cancellationToken);
                throw new InvalidOperationException("Unreachable.");
            });
        var engine = new StreamingRouteEngine(async (request, forecast, progress, cancellationToken) =>
        {
            progress?.Report(new RouteCalculationProgress(0.25, "frontier"));
            if (forecast.Request.Model == ForecastModel.NoaaGfs)
            {
                noaaRoutingStarted.SetResult();
            }

            await Task.Delay(Timeout.InfiniteTimeSpan, cancellationToken);
            throw new InvalidOperationException("Unreachable.");
        });
        var viewModel = CreateViewModel(
            new RoutingWorkflow([noaa, ecmwf], engine),
            new DelegateWeatherSampler((_, _, _, _, _, _) =>
                ValueTask.FromResult(ImmutableArray<ViewportWindSample>.Empty)));
        viewModel.UseEcmwf = true;

        var calculation = viewModel.CalculateRoutesAsync();
        await ecmwfForecastStarted.Task.WaitAsync(TimeSpan.FromSeconds(2));
        await noaaRoutingStarted.Task.WaitAsync(TimeSpan.FromSeconds(2));
        await WaitForAsync(() =>
            viewModel.CalculationStageLabel ==
            "Downloading weather and calculating routes");

        Assert.Equal("NOAA + ECMWF", viewModel.CalculationModelLabel);

        viewModel.CancelCommand.Execute(null);
        await calculation;
        Assert.False(viewModel.IsCalculating);
    }

    [Fact]
    public async Task CancelledGenerationCannotReplaceNewerCalculation()
    {
        var firstStarted = new TaskCompletionSource(
            TaskCreationOptions.RunContinuationsAsynchronously);
        var releaseFirst = new TaskCompletionSource<ForecastAcquisition>(
            TaskCreationOptions.RunContinuationsAsynchronously);
        var calls = 0;
        var provider = new DelegateForecastProvider(
            ForecastModel.NoaaGfs,
            async (request, _) =>
            {
                if (Interlocked.Increment(ref calls) == 1)
                {
                    firstStarted.SetResult();
                    return await releaseFirst.Task;
                }

                return CreateAcquisition(request);
            });
        var engine = new DelegateRouteEngine((request, forecast, _) =>
            ValueTask.FromResult(CreateRoute(request, forecast.Request.Model)));
        var viewModel = CreateViewModel(
            new RoutingWorkflow(new[] { provider }, engine),
            new DelegateWeatherSampler((_, _, _, _, _, _) =>
                ValueTask.FromResult(ImmutableArray<ViewportWindSample>.Empty)));
        viewModel.Itinerary.RouteName = "Stale route";

        var cancelledCalculation = viewModel.CalculateRoutesAsync();
        await firstStarted.Task;
        viewModel.CancelCommand.Execute(null);
        Assert.False(viewModel.IsCalculating);
        Assert.Equal("Calculation cancelled.", viewModel.StatusMessage);

        viewModel.Itinerary.RouteName = "Current route";
        await viewModel.CalculateRoutesAsync();
        var acceptedRouteId = viewModel.SelectedRoutePoint!.Source.Request.RouteId;
        releaseFirst.SetResult(CreateAcquisition(provider.LastRequest!));
        await cancelledCalculation;
        await Task.Delay(20);

        Assert.Equal(1, viewModel.SuccessfulRouteCount);
        Assert.Equal(acceptedRouteId, viewModel.SelectedRoutePoint!.Source.Request.RouteId);
        Assert.Equal("Current route", viewModel.CalculationRouteTitle);
    }

    [Fact]
    public async Task Itinerary_change_discards_late_result_and_waits_for_explicit_recalculation()
    {
        var started = new TaskCompletionSource(
            TaskCreationOptions.RunContinuationsAsynchronously);
        var release = new TaskCompletionSource<ForecastAcquisition>(
            TaskCreationOptions.RunContinuationsAsynchronously);
        var calls = 0;
        var provider = new DelegateForecastProvider(
            ForecastModel.NoaaGfs,
            async (request, _) =>
            {
                if (Interlocked.Increment(ref calls) == 1)
                {
                    started.SetResult();
                    return await release.Task;
                }

                return CreateAcquisition(request);
            });
        var engine = new DelegateRouteEngine((request, forecast, _) =>
            ValueTask.FromResult(CreateRoute(request, forecast.Request.Model)));
        var viewModel = CreateViewModel(
            new RoutingWorkflow(new[] { provider }, engine),
            new DelegateWeatherSampler((_, _, _, _, _, _) =>
                ValueTask.FromResult(ImmutableArray<ViewportWindSample>.Empty)));

        var calculation = viewModel.CalculateRoutesAsync();
        await started.Task;
        var replacement = new Coordinate(40, -50);
        viewModel.SetDestinationAt(replacement);
        release.SetResult(CreateAcquisition(provider.LastRequest!));
        await calculation;
        await WaitForAsync(() => !viewModel.IsCalculating);

        Assert.Equal(1, calls);
        Assert.Equal(0, viewModel.SuccessfulRouteCount);
        await viewModel.CalculateRoutesAsync();
        Assert.Equal(2, calls);
        Assert.Equal(1, viewModel.SuccessfulRouteCount);
        Assert.Equal(replacement, viewModel.SelectedRoutePoint!.Source.Request.Destination);
        Assert.True(viewModel.HasTimeline);
        Assert.False(viewModel.IsCalculating);
    }

    [Fact]
    public async Task TimelineCommandsAndRouteSelectionUseOneActiveModel()
    {
        var providers = new[]
        {
            new DelegateForecastProvider(
                ForecastModel.NoaaGfs,
                (request, _) => ValueTask.FromResult(CreateAcquisition(request))),
            new DelegateForecastProvider(
                ForecastModel.EcmwfIfs,
                (request, _) => ValueTask.FromResult(CreateAcquisition(request)))
        };
        var engine = new DelegateRouteEngine((request, forecast, _) =>
            ValueTask.FromResult(CreateRoute(
                request,
                forecast.Request.Model,
                forecast.Request.Model == ForecastModel.NoaaGfs ? 3 : 2)));
        var viewModel = CreateViewModel(
            new RoutingWorkflow(providers, engine),
            new DelegateWeatherSampler((_, _, _, _, _, _) =>
                ValueTask.FromResult(ImmutableArray<ViewportWindSample>.Empty)));
        viewModel.UseEcmwf = true;
        await viewModel.CalculateRoutesAsync();

        var start = viewModel.SelectedTimelineUtc;
        viewModel.NextTimelineCommand.Execute(null);
        Assert.Equal(start!.Value.AddHours(3), viewModel.SelectedTimelineUtc);

        var ecmwfLeg = viewModel.VisualizedRouteLegs.Single(
            leg => leg.Key.Model == ForecastModel.EcmwfIfs);
        var ecmwf = ecmwfLeg.Route!;
        var selection = new RouteMapSelection(
            ecmwfLeg,
            2,
            ecmwf.Points[2],
            RouteHitKind.RoutePoint,
            0);
        viewModel.SelectRoutePoint(selection, focus: false);

        Assert.Equal(ecmwf.Points[2].Timestamp, viewModel.SelectedTimelineUtc);
        Assert.Equal(ForecastModel.EcmwfIfs, viewModel.SelectedRoutePoint!.Model);
        Assert.Equal(ForecastModel.EcmwfIfs, viewModel.ActiveRouteModel);
        Assert.Equal(ForecastModel.EcmwfIfs, viewModel.ActiveWeatherModel);

        viewModel.PreviousTimelineCommand.Execute(null);
        Assert.True(viewModel.SelectedTimelineUtc < ecmwf.Points[2].Timestamp);
    }

    [Fact]
    public async Task Weather_only_inspection_keeps_acquired_forecasts_available_when_routing_fails()
    {
        var provider = new DelegateForecastProvider(ForecastModel.NoaaGfs,
            (request, _) => ValueTask.FromResult(CreateAcquisition(request)));
        var engine = new DelegateRouteEngine((_, _, _) =>
            throw new RoutingException(RoutingFailureKind.ResourceLimit, "Search budget exhausted"));
        ForecastModel? sampledModel = null;
        var vm = CreateViewModel(new RoutingWorkflow([provider], engine),
            new DelegateWeatherSampler((forecast, _, _, _, _, _) =>
            {
                sampledModel = forecast.Request.Model;
                return ValueTask.FromResult(ImmutableArray<ViewportWindSample>.Empty);
            }));
        await vm.CalculateRoutesAsync();
        Assert.Empty(vm.SuccessfulRoutes);
        Assert.False(vm.HasTimeline);
        var revision = vm.Itinerary.CalculationRevision;
        vm.WeatherOnlyMode = true;
        Assert.Equal(revision, vm.Itinerary.CalculationRevision);
        Assert.True(vm.HasNoaaWeather);
        Assert.True(vm.HasTimeline);
        Assert.Contains("Weather only", vm.TimelineDisplay);
        var first = vm.SelectedTimelineUtc;
        vm.NextTimelineCommand.Execute(null);
        Assert.Equal(first!.Value.AddHours(1), vm.SelectedTimelineUtc);
        await vm.RefreshWeatherAsync(new GeographicBounds(30, 45, -70, -45), 2, 2);
        Assert.Equal(ForecastModel.NoaaGfs, sampledModel);
        Assert.Null(vm.WeatherLayerError);
        vm.WeatherOnlyMode = false;
        Assert.False(vm.HasTimeline);
        Assert.Null(vm.ActiveWeatherModel);
    }

    [Fact]
    public async Task Model_selection_is_linked_except_during_explicit_weather_only_inspection()
    {
        var noaa = new DelegateForecastProvider(ForecastModel.NoaaGfs,
            (request, _) => ValueTask.FromResult(CreateAcquisition(request)));
        var ecmwf = new DelegateForecastProvider(ForecastModel.EcmwfIfs,
            (request, _) => ValueTask.FromResult(CreateAcquisition(request)));
        var engine = new DelegateRouteEngine((request, forecast, _) =>
            ValueTask.FromResult(CreateRoute(request, forecast.Request.Model)));
        var vm = CreateViewModel(new RoutingWorkflow([noaa, ecmwf], engine),
            new DelegateWeatherSampler((_, _, _, _, _, _) =>
                ValueTask.FromResult(ImmutableArray<ViewportWindSample>.Empty)));
        vm.UseEcmwf = true;
        await vm.CalculateRoutesAsync();
        vm.ActiveWeatherModel = ForecastModel.EcmwfIfs;
        Assert.Equal(ForecastModel.EcmwfIfs, vm.ActiveRouteModel);
        Assert.NotNull(vm.SelectedRoutePoint!.Route);
        Assert.Equal(ForecastModel.EcmwfIfs, vm.SelectedRoutePoint.Route.Model);
        vm.WeatherOnlyMode = true;
        vm.ActivateNoaaWeatherCommand.Execute(null);
        Assert.Equal(ForecastModel.NoaaGfs, vm.ActiveWeatherModel);
        Assert.Equal(ForecastModel.EcmwfIfs, vm.ActiveRouteModel);
        vm.WeatherOnlyMode = false;
        Assert.Equal(ForecastModel.EcmwfIfs, vm.ActiveWeatherModel);
        Assert.Equal(ForecastModel.EcmwfIfs, vm.SelectedRoutePoint.Route.Model);
    }

    [Fact]
    public async Task Switching_models_preserves_the_selected_stable_leg()
    {
        var root = Path.Combine(Path.GetTempPath(), $"navtool-model-leg-{Guid.NewGuid():N}");
        var repository = new RoutePlanJsonRepository(root);
        var providers = new[]
        {
            new DelegateForecastProvider(
                ForecastModel.NoaaGfs,
                (request, _) => ValueTask.FromResult(CreateAcquisition(request))),
            new DelegateForecastProvider(
                ForecastModel.EcmwfIfs,
                (request, _) => ValueTask.FromResult(CreateAcquisition(request)))
        };
        var engine = new DelegateRouteEngine((request, forecast, _) =>
            ValueTask.FromResult(CreateRoute(
                request,
                forecast.Request.Model,
                forecast.Request.Model == ForecastModel.NoaaGfs ? 3 : 2)));
        var viewModel = CreateViewModel(
            new RoutingWorkflow(providers, engine),
            new DelegateWeatherSampler((_, _, _, _, _, _) =>
                ValueTask.FromResult(ImmutableArray<ViewportWindSample>.Empty)),
            routePlanRepository: repository);
        viewModel.Itinerary.AddWaypointCommand.Execute(null);
        viewModel.Itinerary.Waypoints[1].SetOnMapCommand.Execute(null);
        viewModel.HandleMapClick(
            MapProjection.ToMapPoint(new Coordinate(36, -58)),
            default);
        viewModel.UseEcmwf = true;
        await viewModel.CalculateRoutesAsync();

        var secondLegId = viewModel.Itinerary.Legs[1].Id;
        viewModel.Itinerary.Legs[1].SelectCommand.Execute(null);
        Assert.Equal(ForecastModel.NoaaGfs, viewModel.SelectedLeg!.Key.Model);

        viewModel.ActivateEcmwfRouteCommand.Execute(null);

        Assert.Equal(secondLegId, viewModel.SelectedLeg!.Key.LegId);
        Assert.Equal(ForecastModel.EcmwfIfs, viewModel.SelectedLeg.Key.Model);
        Directory.Delete(root, recursive: true);
    }

    [Fact]
    public async Task CapturedPointRouteInspectionUsesOriginalPointAndSharedSelectionPath()
    {
        var providers = new[]
        {
            new DelegateForecastProvider(
                ForecastModel.NoaaGfs,
                (request, _) => ValueTask.FromResult(CreateAcquisition(request))),
            new DelegateForecastProvider(
                ForecastModel.EcmwfIfs,
                (request, _) => ValueTask.FromResult(CreateAcquisition(request)))
        };
        var engine = new DelegateRouteEngine((request, forecast, _) =>
            ValueTask.FromResult(CreateRoute(
                request,
                forecast.Request.Model,
                midpointLatitudeOffset: forecast.Request.Model == ForecastModel.EcmwfIfs ? 4 : 0)));
        var viewModel = CreateViewModel(
            new RoutingWorkflow(providers, engine),
            new DelegateWeatherSampler((_, _, _, _, _, _) =>
                ValueTask.FromResult(ImmutableArray<ViewportWindSample>.Empty)));
        viewModel.UseEcmwf = true;
        await viewModel.CalculateRoutesAsync();
        var ecmwf = viewModel.SuccessfulRoutes.Single(
            route => route.Model == ForecastModel.EcmwfIfs);
        var capturedWorldPoint = MapProjection.ToMapPoint(ecmwf.Points[1].Location);
        viewModel.Map.Navigator.SetViewport(new Mapsui.Viewport(
            capturedWorldPoint.X,
            capturedWorldPoint.Y,
            10_000,
            0,
            1280,
            800));
        var projected = viewModel.Map.Navigator.Viewport.WorldToScreen(capturedWorldPoint);
        var capturedScreenPoint = new ScreenPoint(projected.X, projected.Y);

        var capturedSelection = Assert.IsType<RouteMapSelection>(
            viewModel.FindRouteAt(capturedWorldPoint, capturedScreenPoint));
        Assert.True(viewModel.CanInspectRouteAt(capturedWorldPoint, capturedScreenPoint));

        viewModel.SelectRoutePoint(capturedSelection, focus: false);

        Assert.Same(ecmwf, viewModel.SelectedRoutePoint!.Route);
        Assert.Equal(capturedSelection.PointIndex, viewModel.SelectedRoutePoint.PointIndex);
        Assert.Equal(capturedSelection.TimelineTimestamp, viewModel.SelectedTimelineUtc);
        Assert.Equal(ForecastModel.EcmwfIfs, viewModel.ActiveWeatherModel);
        Assert.Contains("ECMWF", viewModel.StatusMessage);
        Assert.Equal(
            capturedSelection.Point.ApparentWindSpeedKnots,
            viewModel.SelectedRoutePoint.Point.ApparentWindSpeedKnots);

        var selectedLeg = viewModel.SelectedLeg;
        viewModel.ClearRoutePointSelection();

        Assert.Null(viewModel.SelectedRoutePoint);
        Assert.Same(selectedLeg, viewModel.SelectedLeg);
    }

    [Fact]
    public void Map_click_on_waypoint_marker_selects_waypoint_before_route_inspection()
    {
        var viewModel = new MainViewModel(
            null,
            null,
            new FixedTimeProvider(Now),
            TimeZoneInfo.Utc,
            new OsmTileOptions(Enabled: false));
        var coordinate = new Coordinate(36, -58);
        viewModel.SetEndpoints(new Coordinate(35, -59), new Coordinate(37, -57));
        var waypoint = viewModel.AddWaypointAt(coordinate)
            ? viewModel.Itinerary.Waypoints[1]
            : throw new InvalidOperationException(viewModel.ErrorMessage);
        viewModel.Itinerary.SelectedWaypoint = null;
        var worldPoint = MapProjection.ToMapPoint(coordinate);
        viewModel.Map.Navigator.SetViewport(new Mapsui.Viewport(
            worldPoint.X,
            worldPoint.Y,
            10_000,
            0,
            1280,
            800));
        var projected = viewModel.Map.Navigator.Viewport.WorldToScreen(worldPoint);

        viewModel.HandleMapClick(
            worldPoint,
            new ScreenPosition(projected.X, projected.Y));

        Assert.Same(waypoint, viewModel.Itinerary.SelectedWaypoint);
        Assert.Equal($"{waypoint.Name} selected.", viewModel.StatusMessage);
        Assert.Null(viewModel.SelectedRoutePoint);
    }

    [Fact]
    public void Contextual_add_is_disabled_while_an_existing_map_placement_is_armed()
    {
        var viewModel = new MainViewModel(
            null,
            null,
            new FixedTimeProvider(Now),
            TimeZoneInfo.Utc,
            new OsmTileOptions(Enabled: false));
        viewModel.SetEndpoints(new Coordinate(35, -59), new Coordinate(37, -57));

        Assert.True(viewModel.CanAddContextualWaypoint);

        viewModel.Itinerary.Waypoints[0].SetOnMapCommand.Execute(null);

        Assert.Equal(MapInteractionMode.SetStart, viewModel.InteractionMode);
        Assert.False(viewModel.CanAddContextualWaypoint);
    }

    [Fact]
    public async Task RouteClicksSynchronizePopupAndWindOverlayToTheSelectedForecast()
    {
        var providers = new[]
        {
            new DelegateForecastProvider(
                ForecastModel.NoaaGfs,
                (request, _) => ValueTask.FromResult(CreateAcquisition(request))),
            new DelegateForecastProvider(
                ForecastModel.EcmwfIfs,
                (request, _) => ValueTask.FromResult(CreateAcquisition(request)))
        };
        var engine = new DelegateRouteEngine((request, forecast, _) =>
            ValueTask.FromResult(CreateRoute(
                request,
                forecast.Request.Model,
                midpointLatitudeOffset: forecast.Request.Model == ForecastModel.EcmwfIfs ? 4 : -4,
                trueWindSpeedKnots: forecast.Request.Model == ForecastModel.EcmwfIfs ? 24 : 12,
                trueWindDirectionDegrees: forecast.Request.Model == ForecastModel.EcmwfIfs ? 210 : 60)));
        var weatherCalls = new List<(ForecastModel Model, DateTimeOffset ValidAt)>();
        var weatherCallsGate = new object();
        var sampler = new DelegateWeatherSampler(
            (forecast, bounds, _, _, validAt, _) =>
            {
                lock (weatherCallsGate)
                {
                    weatherCalls.Add((forecast.Request.Model, validAt));
                }

                return ValueTask.FromResult(
                    ImmutableArray.Create(CreateWind(bounds, validAt, 8)));
            });
        var viewModel = CreateViewModel(
            new RoutingWorkflow(providers, engine),
            sampler);
        var initialViewportCenter = MapProjection.ToMapPoint(new Coordinate(36.5, -56));
        viewModel.Map.Navigator.SetViewport(new Mapsui.Viewport(
            initialViewportCenter.X,
            initialViewportCenter.Y,
            10_000,
            0,
            1280,
            800));
        viewModel.UseEcmwf = true;
        await viewModel.CalculateRoutesAsync();
        await WaitForAsync(() =>
        {
            lock (weatherCallsGate)
            {
                return weatherCalls.Count > 0;
            }
        });

        foreach (var expectedModel in new[] { ForecastModel.EcmwfIfs, ForecastModel.NoaaGfs })
        {
            lock (weatherCallsGate)
            {
                weatherCalls.Clear();
            }

            var route = viewModel.SuccessfulRoutes.Single(candidate => candidate.Model == expectedModel);
            var clickedPoint = route.Points[1];
            var worldPoint = MapProjection.ToMapPoint(clickedPoint.Location);
            viewModel.Map.Navigator.SetViewport(new Mapsui.Viewport(
                worldPoint.X,
                worldPoint.Y,
                10_000,
                0,
                1280,
                800));
            var screenPoint = viewModel.Map.Navigator.Viewport.WorldToScreen(worldPoint);

            Assert.True(viewModel.InspectRouteAt(
                worldPoint,
                new ScreenPoint(screenPoint.X, screenPoint.Y),
                focus: false));
            await WaitForAsync(() =>
            {
                lock (weatherCallsGate)
                {
                    return weatherCalls.Count > 0;
                }
            });

            (ForecastModel Model, DateTimeOffset ValidAt)[] calls;
            lock (weatherCallsGate)
            {
                calls = weatherCalls.ToArray();
            }

            Assert.All(calls, call =>
            {
                Assert.Equal(expectedModel, call.Model);
                Assert.Equal(clickedPoint.Timestamp, call.ValidAt);
            });
            Assert.Same(route, viewModel.SelectedRoutePoint!.Route);
            Assert.Same(clickedPoint, viewModel.SelectedRoutePoint.Point);
            Assert.Equal(clickedPoint.Timestamp, viewModel.SelectedTimelineUtc);
            Assert.Equal(expectedModel, viewModel.ActiveRouteModel);
            Assert.Equal(expectedModel, viewModel.ActiveWeatherModel);
            Assert.Contains(
                $"{clickedPoint.TrueWindSpeedKnots:0.0} kt @ " +
                $"{clickedPoint.TrueWindDirectionDegrees:0}°",
                viewModel.SelectedRouteDetails);
        }
    }

    [Fact]
    public async Task WeatherRefreshSuppressesStaleSamples()
    {
        var provider = new DelegateForecastProvider(
            ForecastModel.NoaaGfs,
            (request, _) => ValueTask.FromResult(CreateAcquisition(request)));
        var engine = new DelegateRouteEngine((request, forecast, _) =>
            ValueTask.FromResult(CreateRoute(request, forecast.Request.Model)));
        var firstStarted = new TaskCompletionSource(
            TaskCreationOptions.RunContinuationsAsynchronously);
        var releaseFirst = new TaskCompletionSource<ImmutableArray<ViewportWindSample>>(
            TaskCreationOptions.RunContinuationsAsynchronously);
        var calls = 0;
        var sampler = new DelegateWeatherSampler(
            async (_, bounds, _, _, validAt, _) =>
            {
                if (Interlocked.Increment(ref calls) == 1)
                {
                    firstStarted.SetResult();
                    return await releaseFirst.Task;
                }

                return ImmutableArray.Create(CreateWind(bounds, validAt, 8));
            });
        var viewModel = CreateViewModel(
            new RoutingWorkflow(new[] { provider }, engine),
            sampler);
        await viewModel.CalculateRoutesAsync();
        var bounds = new GeographicBounds(30, 40, -60, -50);

        var stale = viewModel.RefreshWeatherAsync(bounds, 2, 2);
        await firstStarted.Task;
        var current = viewModel.RefreshWeatherAsync(bounds, 2, 2);
        await current;
        releaseFirst.SetResult(ImmutableArray.Create(
            CreateWind(bounds, viewModel.SelectedTimelineUtc!.Value, 20),
            CreateWind(bounds, viewModel.SelectedTimelineUtc.Value, 25)));
        await stale;

        Assert.Equal(1, viewModel.WeatherCellCount);
        Assert.Null(viewModel.WeatherLayerError);
    }

    [Fact]
    public void CorridorGridAndWindScaleHelpersAreBoundedAndAntimeridianSafe()
    {
        var corridor = ForecastCorridor.Create(
            new Coordinate(35, 179),
            new Coordinate(38, -178));
        var grid = WeatherGridSizing.FromViewport(5_000, 5_000);

        Assert.True(corridor.CrossesAntimeridian);
        Assert.True(corridor.Contains(new Coordinate(35, 179)));
        Assert.True(corridor.Contains(new Coordinate(38, -178)));
        Assert.Equal((12, 18), grid);
        Assert.Equal("#5BC0EB", WindColorScale.GetHex(0));
        Assert.Equal("#E4572E", WindColorScale.GetHex(30));
        Assert.Equal("#9B2C67", WindColorScale.GetHex(40));
    }

    [Theory]
    [InlineData(224.5, -135.5)]
    [InlineData(-212, 148)]
    [InlineData(540, 180)]
    public void MapProjectionNormalizesWrappedLongitudes(double longitude, double expected)
    {
        var point = Mapsui.Projections.SphericalMercator.FromLonLat(longitude, 20);

        var coordinate = MapProjection.ToCoordinate(new Mapsui.MPoint(point.x, point.y));

        Assert.Equal(expected, coordinate.Longitude, 6);
        Assert.Equal(20, coordinate.Latitude, 6);
    }

    private static MainViewModel CreateViewModel(
        RoutingWorkflow workflow,
        IWeatherSampler sampler,
        ILocalGribInspector? localGribInspector = null,
        INativeRoutingPreflight? nativeRoutingPreflight = null,
        IRoutePlanRepository? routePlanRepository = null)
    {
        var viewModel = new MainViewModel(
            workflow,
            sampler,
            new FixedTimeProvider(Now),
            TimeZoneInfo.Utc,
            new OsmTileOptions(Enabled: false),
            localGribInspector: localGribInspector,
            nativeRoutingPreflight: nativeRoutingPreflight,
            routePlanRepository: routePlanRepository,
            boatAssetService: new TestRoutingSetupService(),
            routingSetupService: new TestRoutingSetupService());
        viewModel.RoutingSetup.Boat = TestRoutingSetupService.Demo;
        viewModel.SetEndpoints(
            new Coordinate(34, -64),
            new Coordinate(39, -52));
        viewModel.DepartureNow = false;
        viewModel.DepartureDate = Now.AddHours(1);
        viewModel.DepartureTime = Now.AddHours(1).TimeOfDay;
        return viewModel;
    }

    private static MainViewModel CreateRoutingViewModel(
        IForecastProvider provider,
        IRouteEngine engine)
    {
        var viewModel = new MainViewModel(
            new RoutingWorkflow(new[] { provider }, engine),
            new DelegateWeatherSampler((_, _, _, _, _, _) =>
                ValueTask.FromResult(ImmutableArray<ViewportWindSample>.Empty)),
            new FixedTimeProvider(Now),
            TimeZoneInfo.Utc,
            new OsmTileOptions(Enabled: false),
            boatAssetService: new TestRoutingSetupService(),
            routingSetupService: new TestRoutingSetupService());
        viewModel.RoutingSetup.Boat = TestRoutingSetupService.Demo;
        viewModel.DepartureNow = false;
        return viewModel;
    }

    private static async Task WaitForAsync(Func<bool> predicate)
    {
        var timeout = DateTime.UtcNow.AddSeconds(2);
        while (!predicate() && DateTime.UtcNow < timeout)
        {
            await Task.Delay(10);
        }

        Assert.True(predicate());
    }

    private sealed class StubForecastEstimator(
        ForecastModel model,
        int forecastStepCount,
        int partCount) : IForecastDownloadEstimator
    {
        public ForecastModel Model { get; } = model;

        public ForecastDownloadEstimate EstimateDownload(ForecastRequest request) =>
            new(Model, forecastStepCount, partCount, null, string.Empty);
    }

    private static ForecastAcquisition CreateAcquisition(
        ForecastRequest request,
        ForecastCacheUsage? cacheUsage = null) =>
        new(
            request,
            new ForecastRun(request.Provider, request.Model, request.From.AddHours(-6)),
            new LocalGribArtifact(Path.GetFullPath("fake-forecast.grib2")),
            ForecastAcquisitionSource.Cache,
            new CacheMetadata("fake", request.From.AddHours(-1), request.Through.AddHours(1)),
            cacheUsage);

    private static RouteResult CreateRoute(
        RouteRequest request,
        ForecastModel model,
        int stepHours = 3,
        RouteLandAvoidance? landAvoidance = null,
        double midpointLatitudeOffset = 0,
        double trueWindSpeedKnots = 16,
        double trueWindDirectionDegrees = 120)
    {
        var midpoint = new Coordinate(
            ((request.Origin.Latitude + request.Destination.Latitude) / 2) +
            midpointLatitudeOffset,
            (request.Origin.Longitude + request.Destination.Longitude) / 2);
        var route = new RouteResult(
            request,
            model,
            new[]
            {
                CreatePoint(
                    request.Origin,
                    request.DepartureTime,
                    0,
                    trueWindSpeedKnots,
                    trueWindDirectionDegrees),
                CreatePoint(
                    midpoint,
                    request.DepartureTime.AddHours(stepHours),
                    50,
                    trueWindSpeedKnots,
                    trueWindDirectionDegrees),
                CreatePoint(
                    request.Destination,
                    request.DepartureTime.AddHours(stepHours * 2),
                    100,
                    trueWindSpeedKnots,
                    trueWindDirectionDegrees)
            },
            new RouteDiagnostics(1, 2, 1, 3),
            landAvoidance);
        return route;
    }

    private static RoutePoint CreatePoint(
        Coordinate coordinate,
        DateTimeOffset timestamp,
        double distance,
        double trueWindSpeedKnots = 16,
        double trueWindDirectionDegrees = 120) =>
        new(
            coordinate,
            timestamp,
            headingDegrees: 75,
            boatSpeedKnots: 7.5,
            trueWindSpeedKnots,
            trueWindDirectionDegrees,
            cumulativeDistanceNauticalMiles: distance,
            environment: null,
            polarWindSpeedKnots: trueWindSpeedKnots,
            polarWindDirectionDegrees: trueWindDirectionDegrees);

    private static ViewportWindSample CreateWind(
        GeographicBounds bounds,
        DateTimeOffset validAt,
        double eastMetersPerSecond) =>
        new(
            new Coordinate(
                (bounds.South + bounds.North) / 2,
                (bounds.West + bounds.East) / 2),
            validAt,
            true,
            eastMetersPerSecond,
            2);

    private static TimeZoneInfo CreateDaylightZone()
    {
        var daylightStart = TimeZoneInfo.TransitionTime.CreateFloatingDateRule(
            new DateTime(1, 1, 1, 2, 0, 0),
            3,
            2,
            DayOfWeek.Sunday);
        var daylightEnd = TimeZoneInfo.TransitionTime.CreateFloatingDateRule(
            new DateTime(1, 1, 1, 2, 0, 0),
            11,
            1,
            DayOfWeek.Sunday);
        var rule = TimeZoneInfo.AdjustmentRule.CreateAdjustmentRule(
            new DateTime(2020, 1, 1),
            new DateTime(2030, 12, 31),
            TimeSpan.FromHours(1),
            daylightStart,
            daylightEnd);
        return TimeZoneInfo.CreateCustomTimeZone(
            "Test Eastern",
            TimeSpan.FromHours(-5),
            "Test Eastern",
            "Test Standard",
            "Test Daylight",
            new[] { rule });
    }

    private sealed class FailingPlanRepository : IRoutePlanRepository
    {
        public ValueTask<ImmutableArray<RoutePlanSummary>> ListAsync(CancellationToken cancellationToken = default) =>
            ValueTask.FromResult(ImmutableArray<RoutePlanSummary>.Empty);
        public ValueTask SaveAsync(RoutePlan plan, CancellationToken cancellationToken = default) =>
            ValueTask.FromException(new IOException("Result storage unavailable."));
        public ValueTask<RoutePlan> OpenAsync(RoutePlanId id, CancellationToken cancellationToken = default) =>
            throw new NotSupportedException();
        public ValueTask<RoutePlan> SaveAsAsync(RoutePlan plan, string name, CancellationToken cancellationToken = default) =>
            throw new NotSupportedException();
        public ValueTask DeleteAsync(RoutePlanId id, CancellationToken cancellationToken = default) =>
            throw new NotSupportedException();
    }

    private sealed class FixedTimeProvider(DateTimeOffset now) : TimeProvider
    {
        public override DateTimeOffset GetUtcNow() => now;

        public override TimeZoneInfo LocalTimeZone => TimeZoneInfo.Utc;
    }

    private sealed class DelegateForecastProvider(
        ForecastModel model,
        Func<ForecastRequest, CancellationToken, ValueTask<ForecastAcquisition>> acquire)
        : IForecastProvider
    {
        public ForecastProvider Provider => model.Provider();

        public ForecastModel Model => model;

        public ForecastRequest? LastRequest { get; private set; }

        public List<ForecastRequest> Requests { get; } = [];

        public int CallCount { get; private set; }

        public async ValueTask<ForecastAcquisition> AcquireAsync(
            ForecastRequest request,
            IProgress<ForecastProgress>? progress,
            CancellationToken cancellationToken)
        {
            CallCount++;
            LastRequest = request;
            Requests.Add(request);
            progress?.Report(new ForecastProgress(
                Provider,
                Model,
                ForecastProgressStage.Downloading,
                0.5,
                "fake forecast"));
            return await acquire(request, cancellationToken);
        }
    }

    private sealed class DelegateLocalGribInspector(
        Func<string, CancellationToken, ValueTask<LocalForecastDescriptor>> inspect)
        : ILocalGribInspector
    {
        public int CallCount { get; private set; }

        public ValueTask<LocalForecastDescriptor> InspectAsync(
            string absolutePath,
            CancellationToken cancellationToken = default)
        {
            CallCount++;
            return inspect(absolutePath, cancellationToken);
        }
    }

    private sealed class DelegateNativeRoutingPreflight(
        Exception? exception = null,
        bool landAvoidanceAvailable = true)
        : INativeRoutingPreflight
    {
        public int CallCount { get; private set; }

        public bool LandAvoidanceAvailable { get; } = landAvoidanceAvailable;

        public void EnsureAvailable()
        {
            CallCount++;
            if (exception is not null)
            {
                throw exception;
            }
        }
    }

    [Fact]
    public async Task Lattice_solver_failure_falls_back_to_the_beam_and_warns_the_user()
    {
        var solvers = new List<RouteSolver>();
        DelegateRouteEngine? engine = null;
        engine = new DelegateRouteEngine((request, forecast, _) =>
        {
            solvers.Add(engine!.LastOptimization!.Solver);
            return engine.LastOptimization.Solver == RouteSolver.TimeDependentLattice
                ? throw new RoutingException(RoutingFailureKind.RecoverableSolver,
                    "Calculating route failed (NoRoute): time-dependent lattice search " +
                    "exhausted every reachable state")
                : ValueTask.FromResult(CreateRoute(request, forecast.Request.Model));
        });
        var noaa = new DelegateForecastProvider(
            ForecastModel.NoaaGfs,
            (request, _) => ValueTask.FromResult(CreateAcquisition(request)));
        var viewModel = CreateRoutingViewModel(noaa, engine);
        var departure = Now.AddHours(1);
        viewModel.DepartureDate = departure;
        viewModel.DepartureTime = departure.TimeOfDay;
        viewModel.EnableProfessionalRouting = true;
        viewModel.SelectedRouteSolver = RouteSolver.TimeDependentLattice;

        viewModel.SetStartAt(new Coordinate(34, -64));
        viewModel.SetDestinationAt(new Coordinate(39, -52));
        await viewModel.CalculateRoutesAsync();

        Assert.Equal(
            new[] { RouteSolver.TimeDependentLattice, RouteSolver.IsochroneBeam },
            solvers);
        Assert.True(viewModel.HasWarning);
        Assert.Contains("time-dependent lattice", viewModel.WarningMessage);
        Assert.Contains("isochrone beam", viewModel.WarningMessage);
    }

    private sealed class DelegateRouteEngine(
        Func<RouteRequest, ForecastAcquisition, CancellationToken, ValueTask<RouteResult>> calculate)
        : IConfiguredRouteEngine
    {
        public RouteOptimizationOptions? LastOptimization { get; private set; }

        public async ValueTask<RouteResult> CalculateConfiguredAsync(
            RoutingCalculationContext context, RouteRequest request, ForecastAcquisition forecast,
            RouteOptimizationOptions optimization, IProgress<RouteCalculationProgress>? progress,
            CancellationToken cancellationToken) =>
            TestRoutingSetupService.WithConfiguredAudit(
                await CalculateAsync(request, forecast, optimization, progress, cancellationToken),
                context, optimization, forecast);

        public async ValueTask<RouteResult> CalculateAsync(
            RouteRequest request,
            ForecastAcquisition forecast,
            IProgress<RouteCalculationProgress>? progress,
            CancellationToken cancellationToken)
        {
            var route = await calculate(request, forecast, cancellationToken);
            progress?.Report(new RouteCalculationProgress(1, "fake route"));
            return route;
        }

        public ValueTask<RouteResult> CalculateAsync(
            RouteRequest request,
            ForecastAcquisition forecast,
            RouteOptimizationOptions optimization,
            IProgress<RouteCalculationProgress>? progress,
            CancellationToken cancellationToken)
        {
            LastOptimization = optimization;
            return CalculateAsync(request, forecast, progress, cancellationToken);
        }
    }

    private sealed class StreamingRouteEngine(
        Func<
            RouteRequest,
            ForecastAcquisition,
            IProgress<RouteCalculationProgress>?,
            CancellationToken,
            ValueTask<RouteResult>> calculate)
        : IConfiguredRouteEngine
    {
        public async ValueTask<RouteResult> CalculateConfiguredAsync(
            RoutingCalculationContext context, RouteRequest request, ForecastAcquisition forecast,
            RouteOptimizationOptions optimization, IProgress<RouteCalculationProgress>? progress,
            CancellationToken cancellationToken) =>
            TestRoutingSetupService.WithConfiguredAudit(
                await calculate(request, forecast, progress, cancellationToken), context, optimization, forecast);

        public ValueTask<RouteResult> CalculateAsync(
            RouteRequest request, ForecastAcquisition forecast, RouteOptimizationOptions optimization,
            IProgress<RouteCalculationProgress>? progress, CancellationToken cancellationToken) =>
            calculate(request, forecast, progress, cancellationToken);

        public ValueTask<RouteResult> CalculateAsync(
            RouteRequest request,
            ForecastAcquisition forecast,
            IProgress<RouteCalculationProgress>? progress,
            CancellationToken cancellationToken) =>
            calculate(request, forecast, progress, cancellationToken);
    }

    private sealed class DelegateWeatherSampler(
        Func<
            ForecastAcquisition,
            GeographicBounds,
            int,
            int,
            DateTimeOffset,
            CancellationToken,
            ValueTask<ImmutableArray<ViewportWindSample>>> sample)
        : IWeatherSampler
    {
        public ValueTask<ImmutableArray<ViewportWindSample>> SampleViewportAsync(
            ForecastAcquisition forecast,
            GeographicBounds bounds,
            int latitudeCount,
            int longitudeCount,
            DateTimeOffset validAt,
            CancellationToken cancellationToken = default) =>
            sample(
                forecast,
                bounds,
                latitudeCount,
                longitudeCount,
                validAt,
                cancellationToken);
    }

    private static MemoryLayer GetLayer(MainViewModel viewModel, string name) =>
        Assert.IsType<MemoryLayer>(
            viewModel.Map.Layers.Single(layer => layer.Name == name));

    private static RouteCalculationSnapshot CreateSnapshot(RouteRequest request, RouteCoastalPruningDiagnostics? coastal = null)
    {
        var frontierTime = request.DepartureTime.AddHours(1);
        var frontierPoint = new Coordinate(
            request.Origin.Latitude + 0.25,
            request.Origin.Longitude + 0.25);
        return new RouteCalculationSnapshot(
            frontierTime,
            new[]
            {
                new RouteCalculationEnvelopeSegment(
                    new[]
                    {
                        frontierPoint,
                        new Coordinate(
                            request.Origin.Latitude - 0.25,
                            request.Origin.Longitude + 0.1)
                    },
                    closed: false)
            },
            new[]
            {
                new RouteCalculationFrontSegment(
                    new[]
                    {
                        frontierPoint,
                        new Coordinate(
                            request.Origin.Latitude - 0.25,
                            request.Origin.Longitude + 0.1)
                    })
            },
            new[]
            {
                new RoutePoint(request.Origin, request.DepartureTime, 90, 6, 15, 180, 0),
                new RoutePoint(frontierPoint, frontierTime, 90, 6, 15, 180, 10)
            },
            new RouteDiagnostics(10, 20, 5, 1, coastalPruning: coastal));
    }
}
