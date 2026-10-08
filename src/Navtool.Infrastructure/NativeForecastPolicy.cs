using Navtool.Core;

namespace Navtool.Infrastructure;

internal static class NativeForecastPolicy
{
    public static TimeSpan MaximumGap(ForecastAcquisition acquisition, TimeSpan localGap) =>
        acquisition.Source == ForecastAcquisitionSource.LocalFile ? localGap :
        acquisition.Run.Model == ForecastModel.NoaaGfs ? TimeSpan.FromHours(3) :
        TimeSpan.FromHours(6);

    public static void Validate(NativeForecastMetadata metadata, ForecastAcquisition acquisition)
    {
        if (metadata.InitializedAt != acquisition.Run.InitializedAt)
            throw new RoutingException(RoutingFailureKind.InvalidForecast,
                "The loaded forecast initialization does not match the selected run.");
        if (metadata.EffectiveBounds is { } effectiveBounds && !effectiveBounds.Contains(acquisition.Request.Bounds))
            throw new RoutingException(RoutingFailureKind.InvalidForecast,
                "The loaded forecast cannot cover the complete declared search domain. Choose another forecast or explicitly change the study domain; automatic cropping is not allowed.");
        if (acquisition.Source == ForecastAcquisitionSource.LocalFile) return;
        var expected = acquisition.Run.Model == ForecastModel.NoaaGfs
            ? NoaaGfsForecastProvider.GetRequiredForecastHours(acquisition.Run.InitializedAt,
                acquisition.Request.From, acquisition.Request.Through)
            : EcmwfOpenDataForecastProvider.GetRequiredForecastHours(acquisition.Run.InitializedAt,
                acquisition.Request.From, acquisition.Request.Through);
        var actual = metadata.ValidTimes.ToHashSet();
        foreach (var hour in expected)
        {
            var validAt = acquisition.Run.InitializedAt.AddHours(hour);
            if (!actual.Contains(validAt))
                throw new RoutingException(RoutingFailureKind.InvalidForecast,
                    $"{acquisition.Run.Model} is missing the expected valid field at {validAt:u} " +
                    $"(forecast hour {hour}); a generic interpolation-gap limit cannot replace product cadence validation.");
        }
    }
}
