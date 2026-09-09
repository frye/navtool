using Navtool.Core;

namespace Navtool.Core.Tests;

public sealed class RoutePlanningInputsTests
{
    [Fact]
    public void Local_file_inputs_do_not_require_download_models()
    {
        var inputs = new RoutePlanningInputs
        {
            ForecastSource = PlanningForecastSource.LocalFile,
            LocalGribPath = Path.GetFullPath("forecast.grib"),
            UseNoaa = false,
            UseEcmwf = false
        };

        inputs.Validate();
        Assert.Throws<ArgumentException>(() => (inputs with { ForecastSource = PlanningForecastSource.Download }).Validate());
        Assert.Throws<ArgumentException>(() => (inputs with { ForecastSource = (PlanningForecastSource)99 }).Validate());
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("relative.grib")]
    public void Local_file_inputs_still_require_an_absolute_path(string? path)
    {
        var inputs = new RoutePlanningInputs
        {
            ForecastSource = PlanningForecastSource.LocalFile,
            LocalGribPath = path,
            UseNoaa = false,
            UseEcmwf = false
        };

        var exception = Assert.Throws<ArgumentException>(() => inputs.Validate());
        Assert.Equal("Choose an absolute local GRIB file path.", exception.Message);
    }
}
