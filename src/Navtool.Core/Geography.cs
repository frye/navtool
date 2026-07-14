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
