namespace Navtool.Core;

public readonly record struct Coordinate
{
    public Coordinate(double latitude, double longitude)
    {
        if (!double.IsFinite(latitude) || latitude is < -90 or > 90)
        {
            throw new ArgumentOutOfRangeException(nameof(latitude), "Latitude must be finite and between -90 and 90 degrees.");
        }

        if (!double.IsFinite(longitude) || longitude is < -180 or > 180)
        {
            throw new ArgumentOutOfRangeException(nameof(longitude), "Longitude must be finite and between -180 and 180 degrees.");
        }

        Latitude = latitude;
        Longitude = longitude;
    }

    public double Latitude { get; }

    public double Longitude { get; }

    public bool IsSameLocation(Coordinate other) =>
        Latitude.Equals(other.Latitude) &&
        (Longitude.Equals(other.Longitude) || Math.Abs(Longitude - other.Longitude).Equals(360d));
}

public readonly record struct GeographicBounds
{
    public GeographicBounds(double south, double north, double west, double east)
    {
        if (!double.IsFinite(south) || !double.IsFinite(north) ||
            south is < -90 or > 90 || north is < -90 or > 90 || south > north)
        {
            throw new ArgumentOutOfRangeException(nameof(south), "Latitude bounds must be finite, ordered, and between -90 and 90 degrees.");
        }

        if (!double.IsFinite(west) || west is < -180 or > 180)
        {
            throw new ArgumentOutOfRangeException(nameof(west), "West longitude must be finite and between -180 and 180 degrees.");
        }

        if (!double.IsFinite(east) || east is < -180 or > 180)
        {
            throw new ArgumentOutOfRangeException(nameof(east), "East longitude must be finite and between -180 and 180 degrees.");
        }

        South = south;
        North = north;
        West = west;
        East = east;
    }

    public double South { get; }

    public double North { get; }

    public double West { get; }

    public double East { get; }

    public bool CrossesAntimeridian => West > East;

    public bool Contains(Coordinate coordinate)
    {
        if (coordinate.Latitude < South || coordinate.Latitude > North)
        {
            return false;
        }

        if ((West == 180 || West == -180) &&
            West == East &&
            (coordinate.Longitude == 180 || coordinate.Longitude == -180))
        {
            return true;
        }

        return CrossesAntimeridian
            ? coordinate.Longitude >= West || coordinate.Longitude <= East
            : coordinate.Longitude >= West && coordinate.Longitude <= East;
    }

    public bool Contains(GeographicBounds other) =>
        Contains(new Coordinate(other.South, other.West)) &&
        Contains(new Coordinate(other.South, other.East)) &&
        Contains(new Coordinate(other.North, other.West)) &&
        Contains(new Coordinate(other.North, other.East));

    public static GeographicBounds FromCoordinates(IEnumerable<Coordinate> coordinates)
    {
        ArgumentNullException.ThrowIfNull(coordinates);
        var points = coordinates.ToArray();
        if (points.Length == 0)
        {
            throw new ArgumentException("At least one coordinate is required.", nameof(coordinates));
        }

        var longitudes = points
            .Select(point => point.Longitude < 0 ? point.Longitude + 360 : point.Longitude)
            .Order()
            .ToArray();

        var largestGap = -1d;
        var gapIndex = 0;
        for (var index = 0; index < longitudes.Length; index++)
        {
            var next = index == longitudes.Length - 1 ? longitudes[0] + 360 : longitudes[index + 1];
            var gap = next - longitudes[index];
            if (gap > largestGap)
            {
                largestGap = gap;
                gapIndex = index;
            }
        }

        var west360 = longitudes[(gapIndex + 1) % longitudes.Length];
        var east360 = longitudes[gapIndex];
        return new GeographicBounds(
            points.Min(point => point.Latitude),
            points.Max(point => point.Latitude),
            ToSignedLongitude(west360),
            ToSignedLongitude(east360));
    }

    private static double ToSignedLongitude(double longitude) =>
        longitude > 180 ? longitude - 360 : longitude;
}

public sealed record ForecastCorridorPolicy
{
    public double RouteDistanceFraction { get; init; } = 0.2;

    public double MinimumBufferNauticalMiles { get; init; } = 300;

    public double MaximumBufferNauticalMiles { get; init; } = 900;
}

public sealed record ForecastCorridorResult(
    GeographicBounds Bounds,
    double RouteDistanceNauticalMiles,
    double BufferNauticalMiles);

public static class ForecastCorridor
{
    private const double EarthRadiusNauticalMiles = 3_440.065;

    public static GeographicBounds Create(
        Coordinate origin,
        Coordinate destination,
        ForecastCorridorPolicy? policy = null) =>
        Calculate(origin, destination, policy).Bounds;

    public static ForecastCorridorResult Calculate(
        Coordinate origin,
        Coordinate destination,
        ForecastCorridorPolicy? policy = null)
    {
        var effectivePolicy = policy ?? new ForecastCorridorPolicy();
        Validate(effectivePolicy);
        var routeDistance = GreatCircleDistanceNauticalMiles(origin, destination);
        var buffer = Math.Clamp(
            routeDistance * effectivePolicy.RouteDistanceFraction,
            effectivePolicy.MinimumBufferNauticalMiles,
            effectivePolicy.MaximumBufferNauticalMiles);
        var baseBounds = GeographicBounds.FromCoordinates([origin, destination]);
        var latitudePadding = buffer / 60d;
        var south = Math.Max(-90, baseBounds.South - latitudePadding);
        var north = Math.Min(90, baseBounds.North + latitudePadding);
        var polewardLatitude = Math.Max(Math.Abs(south), Math.Abs(north));
        if (polewardLatitude >= 89.5)
        {
            return new ForecastCorridorResult(
                new GeographicBounds(south, north, -180, 180),
                routeDistance,
                buffer);
        }

        var longitudePadding = buffer /
            (60d * Math.Cos(polewardLatitude * Math.PI / 180d));
        var baseWidth = LongitudeWidth(baseBounds);
        if (baseWidth + (longitudePadding * 2) >= 360)
        {
            return new ForecastCorridorResult(
                new GeographicBounds(south, north, -180, 180),
                routeDistance,
                buffer);
        }

        var eastUnwrapped = baseBounds.CrossesAntimeridian
            ? baseBounds.East + 360
            : baseBounds.East;
        return new ForecastCorridorResult(
            new GeographicBounds(
                south,
                north,
                NormalizeLongitude(baseBounds.West - longitudePadding),
                NormalizeLongitude(eastUnwrapped + longitudePadding)),
            routeDistance,
            buffer);
    }

    public static double GreatCircleDistanceNauticalMiles(
        Coordinate origin,
        Coordinate destination)
    {
        var latitude1 = origin.Latitude * Math.PI / 180d;
        var latitude2 = destination.Latitude * Math.PI / 180d;
        var latitudeDelta = latitude2 - latitude1;
        var longitudeDelta =
            (destination.Longitude - origin.Longitude) * Math.PI / 180d;
        var haversine =
            Math.Pow(Math.Sin(latitudeDelta / 2d), 2) +
            (Math.Cos(latitude1) * Math.Cos(latitude2) *
             Math.Pow(Math.Sin(longitudeDelta / 2d), 2));
        var centralAngle = 2d * Math.Atan2(
            Math.Sqrt(haversine),
            Math.Sqrt(Math.Max(0, 1d - haversine)));
        return EarthRadiusNauticalMiles * centralAngle;
    }

    private static void Validate(ForecastCorridorPolicy policy)
    {
        if (!double.IsFinite(policy.RouteDistanceFraction) ||
            policy.RouteDistanceFraction <= 0 ||
            !double.IsFinite(policy.MinimumBufferNauticalMiles) ||
            policy.MinimumBufferNauticalMiles <= 0 ||
            !double.IsFinite(policy.MaximumBufferNauticalMiles) ||
            policy.MaximumBufferNauticalMiles < policy.MinimumBufferNauticalMiles)
        {
            throw new ArgumentOutOfRangeException(nameof(policy));
        }
    }

    private static double LongitudeWidth(GeographicBounds bounds) =>
        bounds.CrossesAntimeridian
            ? bounds.East + 360 - bounds.West
            : bounds.East - bounds.West;

    private static double NormalizeLongitude(double longitude)
    {
        var normalized = ((longitude + 180) % 360 + 360) % 360 - 180;
        return normalized == -180 && longitude > 0 ? 180 : normalized;
    }
}
