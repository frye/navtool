using System.Collections.Immutable;
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
        IWeatherSampler sampler)
    {
        var viewModel = new MainViewModel(
            workflow,
            sampler,
            new FixedTimeProvider(Now),
            TimeZoneInfo.Utc,
            new OsmTileOptions(Enabled: false));
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
        int stepHours = 3)
    {
        var midpoint = new Coordinate(
            (request.Origin.Latitude + request.Destination.Latitude) / 2,
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
            new RouteDiagnostics(1, 2, 1, 3));
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

        public async ValueTask<ForecastAcquisition> AcquireAsync(
            ForecastRequest request,
            IProgress<ForecastProgress>? progress,
            CancellationToken cancellationToken)
        {
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
}
