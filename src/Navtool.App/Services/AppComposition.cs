using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Navtool.App.ViewModels;
using Navtool.Core;
using Navtool.Infrastructure;

namespace Navtool.App.Services;

public static class AppComposition
{
    public const string ForecastHttpClientName = "Navtool.Forecasts";
    public const string AppDataRootEnvironmentVariable = "NAVTOOL_APP_DATA_ROOT";
    public const string CacheRootEnvironmentVariable = "NAVTOOL_CACHE_ROOT";
    public const string LandDataEndpointEnvironmentVariable = "NAVTOOL_LAND_DATA_ENDPOINT";

    public static ServiceProvider CreateServices()
    {
        var services = new ServiceCollection();
        services.AddLogging(builder =>
        {
            builder.SetMinimumLevel(LogLevel.Information);
        });
        services.AddSingleton<ILoggerProvider>(_ => new RollingFileLoggerProvider(
            new RollingFileLoggerOptions(Path.Combine(ResolveAppDataRoot(), "logs"))));
        services.AddSingleton(provider => new AppThemeService(
            ResolveAppDataRoot(),
            provider.GetRequiredService<ILogger<AppThemeService>>()));
        services.AddHttpClient(ForecastHttpClientName, client =>
        {
            client.DefaultRequestHeaders.UserAgent.ParseAdd(OsmTileOptions.DefaultUserAgent);
            client.Timeout = TimeSpan.FromMinutes(10);
        });
        services.AddSingleton(new OsmTileOptions(
            CacheDirectory: Path.Combine(ResolveAppDataRoot(), "map-tile-cache")));

        services.AddSingleton(provider => new AtomicFileCache(
            new AtomicFileCacheOptions(ResolveCacheRoot()),
            provider.GetRequiredService<ILogger<AtomicFileCache>>()));
        services.AddSingleton<IRoutePlanSchemaMigrator, RoutePlanSchemaMigrator>();
        services.AddSingleton<IRoutingPreferencesRepository>(_ =>
            new RoutingPreferencesJsonRepository(ResolveAppDataRoot()));
        services.AddSingleton<IRoutePlanRepository>(provider => new RoutePlanJsonRepository(
            ResolveAppDataRoot(),
            provider.GetRequiredService<IRoutePlanSchemaMigrator>()));
        services.AddSingleton<ILandDataProvider>(provider =>
        {
            var endpoint = ResolveLandDataEndpoint();
            if (endpoint is null)
            {
                return new NaturalEarthLandDataProvider();
            }

            return new OsmLandDataProvider(
                provider.GetRequiredService<IHttpClientFactory>()
                    .CreateClient(ForecastHttpClientName),
                new OsmLandDataOptions(
                    endpoint,
                    Path.Combine(ResolveAppDataRoot(), "land-cache")),
                logger: provider.GetRequiredService<ILogger<OsmLandDataProvider>>());
        });
        services.AddSingleton<NoaaGfsForecastProvider>(provider =>
            new NoaaGfsForecastProvider(
                provider.GetRequiredService<IHttpClientFactory>().CreateClient(ForecastHttpClientName),
                provider.GetRequiredService<AtomicFileCache>(),
                logger: provider.GetRequiredService<ILogger<NoaaGfsForecastProvider>>()));
        services.AddSingleton<EcmwfOpenDataForecastProvider>(provider =>
            new EcmwfOpenDataForecastProvider(
                provider.GetRequiredService<IHttpClientFactory>().CreateClient(ForecastHttpClientName),
                provider.GetRequiredService<AtomicFileCache>(),
                logger: provider.GetRequiredService<ILogger<EcmwfOpenDataForecastProvider>>()));
        services.AddSingleton<IForecastDownloadEstimator>(provider =>
            provider.GetRequiredService<NoaaGfsForecastProvider>());
        services.AddSingleton<IForecastDownloadEstimator>(provider =>
            provider.GetRequiredService<EcmwfOpenDataForecastProvider>());
        services.AddSingleton(provider => new DeferredNativeRouteEngine(
            () => new NativeRouteEngine(
                new NativeRouterBridge(),
                provider.GetRequiredService<ILogger<NativeRouteEngine>>(),
                provider.GetRequiredService<ILandDataProvider>(),
                Path.Combine(ResolveAppDataRoot(), "native-executions"))));
        services.AddSingleton<IRouteEngine>(provider =>
            provider.GetRequiredService<DeferredNativeRouteEngine>());
        services.AddSingleton<IWeatherSampler>(provider =>
            provider.GetRequiredService<DeferredNativeRouteEngine>());
        services.AddSingleton<INativeRoutingPreflight>(provider =>
            provider.GetRequiredService<DeferredNativeRouteEngine>());
        services.AddSingleton<IBoatAssetService>(_ => new DeferredBoatAssetService(
            () => new BoatAssetRepository(ResolveAppDataRoot(), new NativeRouterBridge())));
        services.AddSingleton<IRoutingSetupService>(provider => new DeferredRoutingSetupService(
            () => new NativeRoutingSetupService(
                new NativeRouterBridge(),
                provider.GetRequiredService<IBoatAssetService>(),
                provider.GetRequiredService<ILandDataProvider>(),
                Path.Combine(ResolveAppDataRoot(), "native-executions"))));
        services.AddSingleton<IRouteStopoverValidator, DeferredStopoverValidator>();
        services.AddSingleton<IRegionalLandPreviewService, DeferredRegionalLandPreviewService>();
        services.AddSingleton<ILocalGribInspector, DeferredLocalGribInspector>();
        services.AddSingleton(provider => new RoutingWorkflow(
            new IForecastProvider[]
            {
                provider.GetRequiredService<NoaaGfsForecastProvider>(),
                provider.GetRequiredService<EcmwfOpenDataForecastProvider>()
            },
            provider.GetRequiredService<IRouteEngine>()));
        services.AddSingleton(provider => new RoutePlanRoutingWorkflow(
            provider.GetRequiredService<RoutingWorkflow>(),
            provider.GetRequiredService<IRoutePlanRepository>(),
            stopoverValidator: provider.GetRequiredService<IRouteStopoverValidator>(),
            setupService: provider.GetRequiredService<IRoutingSetupService>()));
        services.AddSingleton(provider => new MainViewModel(
            provider.GetRequiredService<RoutingWorkflow>(),
            provider.GetRequiredService<IWeatherSampler>(),
            TimeProvider.System,
            TimeZoneInfo.Local,
            provider.GetRequiredService<OsmTileOptions>(),
            provider.GetRequiredService<ILogger<MainViewModel>>(),
            provider.GetRequiredService<ILocalGribInspector>(),
            provider.GetRequiredService<INativeRoutingPreflight>(),
            provider.GetRequiredService<IRoutePlanRepository>(),
            provider.GetRequiredService<RoutePlanRoutingWorkflow>(),
            provider.GetServices<IForecastDownloadEstimator>(),
            provider.GetRequiredService<IBoatAssetService>(),
            provider.GetRequiredService<IRoutingSetupService>(),
            ResolveLandDataEndpoint() is null ? RoutingLandSource.NaturalEarth : RoutingLandSource.OpenStreetMap,
            provider.GetRequiredService<IRegionalLandPreviewService>(),
            provider.GetRequiredService<IRoutingPreferencesRepository>()));
        return services.BuildServiceProvider();
    }

    public static string ResolveAppDataRoot()
    {
        var configured = Environment.GetEnvironmentVariable(AppDataRootEnvironmentVariable);
        if (!string.IsNullOrWhiteSpace(configured))
        {
            return Path.GetFullPath(configured);
        }

        var local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        if (string.IsNullOrWhiteSpace(local))
        {
            local = AppContext.BaseDirectory;
        }

        return Path.Combine(local, "Navtool");
    }

    public static string ResolveCacheRoot()
    {
        var configured = Environment.GetEnvironmentVariable(CacheRootEnvironmentVariable);
        return !string.IsNullOrWhiteSpace(configured)
            ? Path.GetFullPath(configured)
            : Path.Combine(ResolveAppDataRoot(), "forecast-cache");
    }

    public static Uri? ResolveLandDataEndpoint()
    {
        var value = Environment.GetEnvironmentVariable(LandDataEndpointEnvironmentVariable);
        return string.IsNullOrWhiteSpace(value)
            ? null
            : new Uri(value, UriKind.Absolute);
    }
}
