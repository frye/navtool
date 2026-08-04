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
    public const string EcmwfOptInEnvironmentVariable = "NAVTOOL_ECMWF_EXPERIMENTAL";
    public const string LandDataEndpointEnvironmentVariable = "NAVTOOL_LAND_DATA_ENDPOINT";

    public static ServiceProvider CreateServices()
    {
        var services = new ServiceCollection();
        services.AddLogging(builder =>
        {
            builder.SetMinimumLevel(LogLevel.Information);
            builder.AddProvider(new RollingFileLoggerProvider(
                new RollingFileLoggerOptions(Path.Combine(ResolveAppDataRoot(), "logs"))));
        });
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
        services.AddSingleton(_ => new EcmwfOpenDataForecastProvider(
            new EcmwfOpenDataOptions { Enabled = IsExperimentalEcmwfEnabled() }));
        services.AddSingleton<DeferredNativeRouteEngine>();
        services.AddSingleton<IRouteEngine>(provider =>
            provider.GetRequiredService<DeferredNativeRouteEngine>());
        services.AddSingleton<IWeatherSampler>(provider =>
            provider.GetRequiredService<DeferredNativeRouteEngine>());
        services.AddSingleton<INativeRoutingPreflight>(provider =>
            provider.GetRequiredService<DeferredNativeRouteEngine>());
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
            provider.GetRequiredService<IRoutePlanRepository>()));
        services.AddSingleton<MainViewModel>();
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

    public static bool IsExperimentalEcmwfEnabled()
    {
        var value = Environment.GetEnvironmentVariable(EcmwfOptInEnvironmentVariable);
        return string.Equals(value, "1", StringComparison.Ordinal) ||
               string.Equals(value, "true", StringComparison.OrdinalIgnoreCase);
    }

    public static Uri? ResolveLandDataEndpoint()
    {
        var value = Environment.GetEnvironmentVariable(LandDataEndpointEnvironmentVariable);
        return string.IsNullOrWhiteSpace(value)
            ? null
            : new Uri(value, UriKind.Absolute);
    }
}
