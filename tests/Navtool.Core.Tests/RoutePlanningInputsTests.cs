using Navtool.Core;

namespace Navtool.Core.Tests;

public sealed class RoutePlanningInputsTests
{
    [Theory]
    [InlineData(true, false)]
    [InlineData(false, true)]
    public void Departure_mode_accepts_only_its_matching_schedule(bool departureNow, bool hasSchedule)
    {
        var inputs = new RoutePlanningInputs
        {
            DepartureNow = departureNow,
            ScheduledDepartureUtc = hasSchedule ? DateTimeOffset.Parse("2026-09-09T19:00:00Z") : null
        };

        inputs.Validate();
    }

    [Theory]
    [InlineData(true, true)]
    [InlineData(false, false)]
    public void Departure_mode_rejects_an_inconsistent_schedule(bool departureNow, bool hasSchedule)
    {
        var inputs = new RoutePlanningInputs
        {
            DepartureNow = departureNow,
            ScheduledDepartureUtc = hasSchedule ? DateTimeOffset.Parse("2026-09-09T19:00:00Z") : null
        };

        Assert.Throws<ArgumentException>(() => inputs.Validate());
    }

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
