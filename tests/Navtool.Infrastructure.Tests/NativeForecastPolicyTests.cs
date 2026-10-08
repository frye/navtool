using System.Collections.Immutable;
using Navtool.Core;

namespace Navtool.Infrastructure.Tests;

public sealed class NativeForecastPolicyTests
{
    [Theory]
    [InlineData(ForecastModel.NoaaGfs, 0, 119, 126)]
    [InlineData(ForecastModel.EcmwfIfs, 0, 141, 156)]
    [InlineData(ForecastModel.EcmwfIfs, 6, 84, 90)]
    public void Official_product_cadence_transitions_are_legal_but_missing_steps_fail(
        ForecastModel model, int cycle, int start, int end)
    {
        var initialized = new DateTimeOffset(2026, 7, 15, cycle, 0, 0, TimeSpan.Zero);
        var acquisition = new ForecastAcquisition(
            new ForecastRequest(model, new GeographicBounds(-1, 1, -1, 1), initialized.AddHours(start), initialized.AddHours(end)),
            new ForecastRun(model.Provider(), model, initialized), new LocalGribArtifact(Path.GetFullPath("unused.grib")),
            ForecastAcquisitionSource.Remote);
        var hours = model == ForecastModel.NoaaGfs
            ? NoaaGfsForecastProvider.GetRequiredForecastHours(initialized, acquisition.Request.From, acquisition.Request.Through)
            : EcmwfOpenDataForecastProvider.GetRequiredForecastHours(initialized, acquisition.Request.From, acquisition.Request.Through);
        var times = hours.Select(hour => initialized.AddHours(hour)).ToImmutableArray();
        var metadata = new NativeForecastMetadata(times[0], times[^1], 2, 2, false, "test")
        {
            InitializedAt = initialized, ValidTimes = times
        };
        NativeForecastPolicy.Validate(metadata, acquisition);
        var failure = Assert.Throws<RoutingException>(() =>
            NativeForecastPolicy.Validate(metadata with { ValidTimes = times.RemoveAt(1) }, acquisition));
        Assert.Equal(RoutingFailureKind.InvalidForecast, failure.Kind);
        Assert.Contains("expected valid field", failure.Message);
    }

    [Fact]
    public void Local_files_use_explicit_policy_and_preserve_single_time_metadata()
    {
        var initialized = DateTimeOffset.Parse("2026-07-15T00:00:00Z");
        var acquisition = new ForecastAcquisition(
            new ForecastRequest(ForecastModel.NoaaGfs, new GeographicBounds(-1, 1, -1, 1), initialized, initialized),
            new ForecastRun(ForecastProvider.Noaa, ForecastModel.NoaaGfs, initialized), new LocalGribArtifact(Path.GetFullPath("unused.grib")),
            ForecastAcquisitionSource.LocalFile);
        var metadata = new NativeForecastMetadata(initialized, initialized, 2, 2, false, "local")
        {
            InitializedAt = initialized, ValidTimes = [initialized]
        };
        NativeForecastPolicy.Validate(metadata, acquisition);
        Assert.Equal(TimeSpan.FromHours(2), NativeForecastPolicy.MaximumGap(acquisition, TimeSpan.FromHours(2)));
        Assert.Null(metadata.MinimumTimeSpacing);
        Assert.Null(metadata.MaximumTimeSpacing);
    }
}
