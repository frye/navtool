using System.Collections.Immutable;
using Mapsui.Extensions;
using Mapsui.Layers;
using Navtool.App.Models;
using Navtool.App.Services;
using Navtool.App.ViewModels;
using Navtool.Core;
using Navtool.Infrastructure;

namespace Navtool.App.Tests;

public sealed class MainViewModelWorkflowTests
{
    private static readonly DateTimeOffset Now =
        new(2026, 7, 14, 16, 0, 0, TimeSpan.Zero);

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
        Assert.Equal(ForecastModel.NoaaGfs, viewModel.SelectedRoutePoint!.Route.Model);
        Assert.Contains("complete", viewModel.NoaaStatus, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("Experimental ECMWF failed", viewModel.ErrorMessage);
        Assert.Contains("indexed ranges are unavailable", viewModel.EcmwfStatus);
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
    public async Task Intermediate_waypoint_is_editable_but_sequential_calculation_is_deferred()
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
        viewModel.Itinerary.AddWaypointCommand.Execute(null);
        var waypoint = viewModel.Itinerary.Waypoints[1];
        waypoint.SetOnMapCommand.Execute(null);
        viewModel.HandleMapClick(
            MapProjection.ToMapPoint(new Coordinate(36, -58)),
            default);

        await viewModel.CalculateRoutesAsync();

        Assert.Null(noaa.LastRequest);
        Assert.Equal(36, waypoint.Coordinate!.Value.Latitude, 10);
        Assert.Equal(-58, waypoint.Coordinate.Value.Longitude, 10);
        Assert.Contains("Sequential multi-leg", viewModel.ErrorMessage);
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
    public async Task StreamingOverlaysRetainSuccessfulModelAndClearFailedModel()
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
        Assert.Equal(1, viewModel.SuccessfulRouteCount);
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

    [Fact]
    public async Task CancellingCalculationClearsStreamingOverlays()
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

        var cancelledCalculation = viewModel.CalculateRoutesAsync();
        await firstStarted.Task;
        viewModel.CancelCommand.Execute(null);
        Assert.False(viewModel.IsCalculating);
        Assert.Equal("Calculation cancelled.", viewModel.StatusMessage);

        await viewModel.CalculateRoutesAsync();
        var acceptedRouteId = viewModel.SelectedRoutePoint!.Route.Request.RouteId;
        releaseFirst.SetResult(CreateAcquisition(provider.LastRequest!));
        await cancelledCalculation;
        await Task.Delay(20);

        Assert.Equal(1, viewModel.SuccessfulRouteCount);
        Assert.Equal(acceptedRouteId, viewModel.SelectedRoutePoint!.Route.Request.RouteId);
    }

    [Fact]
    public async Task Itinerary_change_discards_late_result_and_clears_displayed_route()
    {
        var started = new TaskCompletionSource(
            TaskCreationOptions.RunContinuationsAsynchronously);
        var release = new TaskCompletionSource<ForecastAcquisition>(
            TaskCreationOptions.RunContinuationsAsynchronously);
        var provider = new DelegateForecastProvider(
            ForecastModel.NoaaGfs,
            async (_, _) =>
            {
                started.SetResult();
                return await release.Task;
            });
        var engine = new DelegateRouteEngine((request, forecast, _) =>
            ValueTask.FromResult(CreateRoute(request, forecast.Request.Model)));
        var viewModel = CreateViewModel(
            new RoutingWorkflow(new[] { provider }, engine),
            new DelegateWeatherSampler((_, _, _, _, _, _) =>
                ValueTask.FromResult(ImmutableArray<ViewportWindSample>.Empty)));

        var calculation = viewModel.CalculateRoutesAsync();
        await started.Task;
        viewModel.SetDestinationAt(new Coordinate(40, -50));
        release.SetResult(CreateAcquisition(provider.LastRequest!));
        await calculation;

        Assert.Equal(0, viewModel.SuccessfulRouteCount);
        Assert.False(viewModel.HasTimeline);
        Assert.False(viewModel.IsCalculating);
    }

    [Fact]
    public async Task TimelineCommandsAndRouteSelectionShareUtcState()
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
        Assert.Equal(start!.Value.AddHours(2), viewModel.SelectedTimelineUtc);

        var ecmwf = viewModel.SuccessfulRoutes.Single(
            route => route.Model == ForecastModel.EcmwfIfs);
        var selection = new RouteMapSelection(
            ecmwf,
            2,
            ecmwf.Points[2],
            RouteHitKind.RoutePoint,
            0);
        viewModel.SelectRoutePoint(selection, focus: false);

        Assert.Equal(ecmwf.Points[2].Timestamp, viewModel.SelectedTimelineUtc);
        Assert.Equal(ForecastModel.EcmwfIfs, viewModel.SelectedRoutePoint!.Route.Model);
        Assert.Equal(ForecastModel.EcmwfIfs, viewModel.ActiveWeatherModel);

        viewModel.PreviousTimelineCommand.Execute(null);
        Assert.True(viewModel.SelectedTimelineUtc < ecmwf.Points[2].Timestamp);
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
        INativeRoutingPreflight? nativeRoutingPreflight = null)
    {
        var viewModel = new MainViewModel(
            workflow,
            sampler,
            new FixedTimeProvider(Now),
            TimeZoneInfo.Utc,
            new OsmTileOptions(Enabled: false),
            localGribInspector: localGribInspector,
            nativeRoutingPreflight: nativeRoutingPreflight);
        viewModel.SetEndpoints(
            new Coordinate(34, -64),
            new Coordinate(39, -52));
        viewModel.DepartureDate = Now.AddHours(1);
        viewModel.DepartureTime = Now.AddHours(1).TimeOfDay;
        return viewModel;
    }

    private static ForecastAcquisition CreateAcquisition(ForecastRequest request) =>
        new(
            request,
            new ForecastRun(request.Provider, request.Model, request.From.AddHours(-6)),
            new LocalGribArtifact(Path.GetFullPath("fake-forecast.grib2")),
            ForecastAcquisitionSource.Cache,
            new CacheMetadata("fake", request.From.AddHours(-1), request.Through.AddHours(1)));

    private static RouteResult CreateRoute(
        RouteRequest request,
        ForecastModel model,
        int stepHours = 3,
        RouteLandAvoidance? landAvoidance = null,
        double midpointLatitudeOffset = 0)
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
                CreatePoint(request.Origin, request.DepartureTime, 0),
                CreatePoint(midpoint, request.DepartureTime.AddHours(stepHours), 50),
                CreatePoint(request.Destination, request.DepartureTime.AddHours(stepHours * 2), 100)
            },
            new RouteDiagnostics(1, 2, 1, 3),
            landAvoidance);
        return route;
    }

    private static RoutePoint CreatePoint(
        Coordinate coordinate,
        DateTimeOffset timestamp,
        double distance) =>
        new(
            coordinate,
            timestamp,
            headingDegrees: 75,
            boatSpeedKnots: 7.5,
            trueWindSpeedKnots: 16,
            trueWindDirectionDegrees: 120,
            cumulativeDistanceNauticalMiles: distance);

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

        public int CallCount { get; private set; }

        public async ValueTask<ForecastAcquisition> AcquireAsync(
            ForecastRequest request,
            IProgress<ForecastProgress>? progress,
            CancellationToken cancellationToken)
        {
            CallCount++;
            LastRequest = request;
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

    private sealed class DelegateRouteEngine(
        Func<RouteRequest, ForecastAcquisition, CancellationToken, ValueTask<RouteResult>> calculate)
        : IRouteEngine
    {
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
    }

    private sealed class StreamingRouteEngine(
        Func<
            RouteRequest,
            ForecastAcquisition,
            IProgress<RouteCalculationProgress>?,
            CancellationToken,
            ValueTask<RouteResult>> calculate)
        : IRouteEngine
    {
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

    private static RouteCalculationSnapshot CreateSnapshot(RouteRequest request)
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
            new RouteDiagnostics(10, 20, 5, 1));
    }
}
