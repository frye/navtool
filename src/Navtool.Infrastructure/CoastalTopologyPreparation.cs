using System.Buffers.Binary;
using System.Collections.Immutable;
using System.Globalization;
using System.Security.Cryptography;
using Navtool.Core;
using NetTopologySuite.Geometries;
using CoreCoordinate = Navtool.Core.Coordinate;

namespace Navtool.Infrastructure;

internal sealed record CoastalLandCap(CoreCoordinate Center, double RadiusNauticalMiles);

internal sealed record CoastalTopologyPreparation(
    GeographicBounds Bounds,
    string SourceIdentity,
    string DomainIdentity,
    ImmutableArray<CoreCoordinate> Probes,
    ImmutableArray<CoastalLandCap> Caps,
    ulong GeometryWork)
{
    internal const double NumericalMarginNauticalMiles = .001;
    private const double EarthRadiusNauticalMiles = 3440.065;
    private const double Radians = Math.PI / 180;

    internal static string IdentifyLandmask(RouteLandmaskOptions mask, CancellationToken cancellationToken)
    {
        using var hash = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
        hash.AppendData("navtool-coastal-sdf-v1"u8);
        var buffer = new byte[4096];
        var used = 0;
        var grid = mask.Grid;
        foreach (var value in new double[] { grid.SouthLatitudeDegrees, grid.WestLongitudeDegrees,
            grid.LatitudeStepDegrees, grid.LongitudeStepDegrees, grid.LatitudeCount, grid.LongitudeCount,
            grid.GlobalLongitudeCoverage ? 1 : 0, mask.ResolutionNauticalMiles,
            mask.InterpolationErrorNauticalMiles, mask.ClearanceNauticalMiles,
            mask.MaximumSubdivisionDepth, (int)mask.MissingDataPolicy })
            Append(value);
        foreach (var value in mask.SignedDistanceNauticalMiles) Append(value);
        cancellationToken.ThrowIfCancellationRequested();
        hash.AppendData(buffer.AsSpan(0, used));
        return "sha256-sdf-v1:" + Convert.ToHexString(hash.GetHashAndReset()).ToLowerInvariant();

        void Append(double value)
        {
            BinaryPrimitives.WriteDoubleLittleEndian(buffer.AsSpan(used, sizeof(double)), value);
            used += sizeof(double);
            if (used != buffer.Length) return;
            cancellationToken.ThrowIfCancellationRequested();
            hash.AppendData(buffer);
            used = 0;
        }
    }

    internal static CoastalTopologyPreparation Create(GeographicBounds bounds, RouteRequest request,
        LandGeometryIndex? geometry, string sourceIdentity, CancellationToken cancellationToken)
    {
        var probes = ImmutableArray.CreateBuilder<CoreCoordinate>();
        var span = bounds.CrossesAntimeridian ? bounds.East + 360 - bounds.West : bounds.East - bounds.West;
        AddGrid(bounds.South, bounds.North, bounds.West, span, 12);
        var east = request.Destination.Longitude;
        while (east - request.Origin.Longitude > 180) east -= 360;
        while (east - request.Origin.Longitude < -180) east += 360;
        var latitude = Math.Max(Math.Abs(request.Origin.Latitude), Math.Abs(request.Destination.Latitude));
        var longitudePad = Math.Min(10, .5 / Math.Max(.1, Math.Cos(latitude * Radians)));
        var west = Math.Min(request.Origin.Longitude, east) - longitudePad;
        AddGrid(Math.Max(-80, Math.Min(request.Origin.Latitude, request.Destination.Latitude) - .5),
            Math.Min(80, Math.Max(request.Origin.Latitude, request.Destination.Latitude) + .5),
            west, Math.Max(request.Origin.Longitude, east) + longitudePad - west, 24);
        var unique = probes.Distinct().Where(bounds.Contains).ToImmutableArray();
        var caps = new List<CoastalLandCap>();
        ulong work = 0;
        if (geometry is not null)
        {
            var factory = NetTopologySuite.NtsGeometryServices.Instance.CreateGeometryFactory(srid: 4326);
            foreach (var probe in unique)
            {
                cancellationToken.ThrowIfCancellationRequested();
                if (Math.Abs(probe.Latitude) > 75 || !geometry.Contains(probe)) continue;
                var lower = 0d;
                var upper = 80d;
                for (var iteration = 0; iteration < 9; iteration++)
                {
                    var halfSize = (lower + upper) / 2;
                    var halfLatitude = halfSize / EarthRadiusNauticalMiles / Radians;
                    var halfLongitude = halfLatitude / Math.Cos(probe.Latitude * Radians);
                    var envelope = new Envelope(probe.Longitude - halfLongitude, probe.Longitude + halfLongitude,
                        probe.Latitude - halfLatitude, probe.Latitude + halfLatitude);
                    var rectangle = factory.ToGeometry(envelope);
                    var covered = false;
                    foreach (var polygon in geometry.QueryPreparedGeometries(envelope))
                    {
                        if (++work > 100_000)
                            throw new RoutingException(RoutingFailureKind.ResourceLimit,
                                "Coastal topology polygon preparation exceeded its geometry budget.");
                        if (polygon.Covers(rectangle)) { covered = true; break; }
                    }
                    if (covered) lower = halfSize;
                    else upper = halfSize;
                }
                var latAngle = lower / EarthRadiusNauticalMiles;
                var lonAngle = latAngle / Math.Cos(probe.Latitude * Radians);
                var radius = EarthRadiusNauticalMiles * Math.Min(latAngle,
                    Math.Asin(Math.Cos(probe.Latitude * Radians) * Math.Sin(lonAngle)));
                radius = Math.Min(radius, CoverageRadius(probe));
                // A callback samples each great-circle segment at <= its configured
                // spacing. Shrinking by that full spacing guarantees a land sample
                // even when lon/lat chord interpolation differs from the sphere.
                radius -= geometry.MaximumSegmentSampleNauticalMiles + NumericalMarginNauticalMiles;
                if (radius > .1) caps.Add(new CoastalLandCap(probe, radius));
            }
        }
        var selected = new List<CoastalLandCap>();
        foreach (var cap in caps.OrderByDescending(cap => cap.RadiusNauticalMiles))
        {
            if (selected.Any(existing =>
                ForecastCorridor.GreatCircleDistanceNauticalMiles(existing.Center, cap.Center) +
                    cap.RadiusNauticalMiles <= existing.RadiusNauticalMiles)) continue;
            selected.Add(cap);
            if (selected.Count == 64) break;
        }
        var enforcement = geometry is null ? "native-mask" :
            "polygon-samples:" + geometry.MaximumSegmentSampleNauticalMiles.ToString("R", CultureInfo.InvariantCulture);
        var identity = string.Create(CultureInfo.InvariantCulture,
            $"coastal-v1:{bounds.South:R},{bounds.West:R},{bounds.North:R},{bounds.East:R};{enforcement}");
        return new(bounds, sourceIdentity, identity, unique, selected.ToImmutableArray(), work);

        double CoverageRadius(CoreCoordinate point)
        {
            var limit = EarthRadiusNauticalMiles * Radians *
                Math.Min(point.Latitude - bounds.South, bounds.North - point.Latitude);
            if (span >= 360) return limit;
            var westDistance = (point.Longitude - bounds.West + 360) % 360;
            var eastDistance = span - westDistance;
            foreach (var angle in new[] { westDistance * Radians, eastDistance * Radians })
                limit = Math.Min(limit, EarthRadiusNauticalMiles *
                    Math.Asin(Math.Abs(Math.Cos(point.Latitude * Radians) * Math.Sin(angle))));
            return Math.Max(0, limit);
        }

        void AddGrid(double south, double north, double westLongitude, double longitudeSpan, int count)
        {
            for (var row = 0; row < count; row++)
            for (var column = 0; column < count; column++)
            {
                cancellationToken.ThrowIfCancellationRequested();
                var longitude = westLongitude + longitudeSpan * (column + .5) / count;
                longitude = Math.IEEERemainder(longitude, 360);
                probes.Add(new CoreCoordinate(south + (north - south) * (row + .5) / count, longitude));
            }
        }
    }
}
