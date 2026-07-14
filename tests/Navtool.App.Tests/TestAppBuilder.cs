using Avalonia;
using Avalonia.Headless;
using Navtool.App;

[assembly: AvaloniaTestApplication(typeof(Navtool.App.Tests.TestAppBuilder))]

namespace Navtool.App.Tests;

public static class TestAppBuilder
{
    public static AppBuilder BuildAvaloniaApp() => AppBuilder.Configure<App>()
        .UseHeadless(new AvaloniaHeadlessPlatformOptions());
}
