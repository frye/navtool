using Navtool.Core;

namespace Navtool.App.Services;

public static class LocalDepartureConverter
{
    public static bool TryConvertToUtc(
        DateTimeOffset? localDate,
        TimeSpan? localTime,
        TimeZoneInfo timeZone,
        out DateTimeOffset utc,
        out string? error)
    {
        ArgumentNullException.ThrowIfNull(timeZone);
        utc = default;
        if (localDate is null || localTime is null)
        {
            error = "Choose both a departure date and local time.";
            return false;
        }

        if (localTime < TimeSpan.Zero || localTime >= TimeSpan.FromDays(1))
        {
            error = "Departure time must be within the selected local day.";
            return false;
        }

        var local = DateTime.SpecifyKind(localDate.Value.Date + localTime.Value, DateTimeKind.Unspecified);
        if (timeZone.IsInvalidTime(local))
        {
            error = "The selected local departure time does not exist because of a daylight-saving transition.";
            return false;
        }

        if (timeZone.IsAmbiguousTime(local))
        {
            error = "The selected local departure time occurs twice because of a daylight-saving transition. Choose another time.";
            return false;
        }

        utc = new DateTimeOffset(TimeZoneInfo.ConvertTimeToUtc(local, timeZone), TimeSpan.Zero);
        error = null;
        return true;
    }
}

public static class ForecastCorridor
{
    public static GeographicBounds Create(
        Coordinate origin,
        Coordinate destination,
        double paddingDegrees = 5)
    {
        if (!double.IsFinite(paddingDegrees) || paddingDegrees <= 0 || paddingDegrees >= 90)
        {
            throw new ArgumentOutOfRangeException(nameof(paddingDegrees));
        }

        var bounds = GeographicBounds.FromCoordinates(new[] { origin, destination });
        var south = Math.Max(-90, bounds.South - paddingDegrees);
        var north = Math.Min(90, bounds.North + paddingDegrees);
        var eastUnwrapped = bounds.CrossesAntimeridian ? bounds.East + 360 : bounds.East;
        if (eastUnwrapped - bounds.West + (paddingDegrees * 2) >= 360)
        {
            return new GeographicBounds(south, north, -180, 180);
        }

        return new GeographicBounds(
            south,
            north,
            NormalizeLongitude(bounds.West - paddingDegrees),
            NormalizeLongitude(eastUnwrapped + paddingDegrees));
    }

    private static double NormalizeLongitude(double longitude)
    {
        var normalized = ((longitude + 180) % 360 + 360) % 360 - 180;
        return normalized == -180 && longitude > 0 ? 180 : normalized;
    }
}

public static class WeatherGridSizing
{
    public static (int LatitudeCount, int LongitudeCount) FromViewport(
        double width,
        double height)
    {
        var columns = double.IsFinite(width)
            ? Math.Clamp((int)Math.Ceiling(width / 80), 2, 18)
            : 18;
        var rows = double.IsFinite(height)
            ? Math.Clamp((int)Math.Ceiling(height / 80), 2, 12)
            : 12;
        return (rows, columns);
    }
}

public static class WindColorScale
{
    public static string GetHex(double knots)
    {
        if (!double.IsFinite(knots) || knots < 0)
        {
            throw new ArgumentOutOfRangeException(nameof(knots));
        }

        return knots switch
        {
            < 5 => "#5BC0EB",
            < 10 => "#00A6A6",
            < 15 => "#7FB800",
            < 20 => "#F4D35E",
            < 25 => "#F19C79",
            < 35 => "#E4572E",
            _ => "#9B2C67"
        };
    }
}
