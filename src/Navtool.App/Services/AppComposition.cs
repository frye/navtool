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

    public static ServiceProvider CreateServices()
    {
        var services = new ServiceCollection();
        services.AddLogging(builder =>
        {
            builder.SetMinimumLevel(LogLevel.Information);
            builder.AddProvider(new RollingFileLoggerProvider(
                new RollingFileLoggerOptions(Path.Combine(ResolveAppDataRoot(), "logs"))));
        });
        services.AddHttpClient(ForecastHttpClientName, client =>
        {
            client.DefaultRequestHeaders.UserAgent.ParseAdd("Navtool/1.0");
            client.Timeout = TimeSpan.FromMinutes(10);
        });

        services.AddSingleton(_ => new AtomicFileCache(
            new AtomicFileCacheOptions(ResolveCacheRoot())));
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
        services.AddSingleton(provider => new RoutingWorkflow(
            new IForecastProvider[]
            {
                provider.GetRequiredService<NoaaGfsForecastProvider>(),
                provider.GetRequiredService<EcmwfOpenDataForecastProvider>()
            },
            provider.GetRequiredService<IRouteEngine>()));
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
}
