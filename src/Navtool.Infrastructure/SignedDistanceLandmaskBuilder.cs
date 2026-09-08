using Navtool.Core;
using NetTopologySuite.Geometries;
using NetTopologySuite.Index.Strtree;
using CoreCoordinate = Navtool.Core.Coordinate;
using NtsCoordinate = NetTopologySuite.Geometries.Coordinate;

namespace Navtool.Infrastructure;

/// <summary>
/// Rasterizes the land geometry Navtool already loads into the signed distance
/// grid router-lib's <c>SignedDistanceLandmask</c> expects.
/// </summary>
/// <remarks>
/// <para>
/// The grid stores nautical miles, positive over water and negative over land,
/// row-major from the south-west corner exactly as router-lib indexes it.
/// </para>
/// <para>
/// Distances are measured in a local equirectangular frame that compresses
/// longitude by the cosine of the highest absolute latitude in the 600 nm halo.
/// Every other row is therefore compressed slightly more than it should be, so
/// reported distances are never larger than the true distance. Under-reporting
/// only makes segment certification more cautious; it can never round a
/// decision toward accepting land. The sign comes from a separate point-in-
/// polygon test on the unscaled geometry, so it stays exact everywhere.
/// </para>
/// </remarks>
public static class SignedDistanceLandmaskBuilder
{
    private const double NauticalMilesPerDegree = 60.0;

    /// <summary>Distances beyond this are clamped; open ocean needs no detail.</summary>
    private const double MaximumReportedDistanceNauticalMiles = 600.0;

    /// <summary>
    /// Guards against a coarse corridor plus a fine resolution producing a grid
    /// large enough to exhaust memory before the native call is ever made.
    /// </summary>
    private const int MaximumSampleCount = 4_000_000;

    /// <summary>Below this the longitude scale factor stops shrinking.</summary>
    private const double MinimumLatitudeCosine = 0.05;

    public static GeographicBounds RequiredGeometryBounds(GeographicBounds bounds, double resolutionNauticalMiles)
    {
        if (!double.IsFinite(resolutionNauticalMiles) || resolutionNauticalMiles is < .05 or > 120)
            throw new ArgumentOutOfRangeException(nameof(resolutionNauticalMiles));
        ValidateDomain(bounds);
        var grid = BuildGrid(bounds, resolutionNauticalMiles);
        var pad = MaximumReportedDistanceNauticalMiles / NauticalMilesPerDegree;
        var latitude = Math.Max(Math.Abs(grid.SouthLatitudeDegrees), Math.Abs(grid.NorthLatitudeDegrees)) + pad;
        if (latitude > 85)
            throw new InvalidOperationException("The optional landmask's geometry halo exceeds ±85°.");
        var longitudePad = pad / Math.Cos(latitude * Math.PI / 180);
        var west = grid.WestLongitudeDegrees - longitudePad;
        var east = grid.EastLongitudeDegrees + longitudePad;
        return new GeographicBounds(grid.SouthLatitudeDegrees - pad, grid.NorthLatitudeDegrees + pad,
            east - west >= 360 ? -180 : Math.IEEERemainder(west, 360),
            east - west >= 360 ? 180 : Math.IEEERemainder(east, 360));
    }

    public static RouteLandmaskOptions Build(
        LandGeometryIndex geometry,
        GeographicBounds bounds,
        double resolutionNauticalMiles,
        RouteProviderMetadata metadata,
        double clearanceNauticalMiles = 0,
        int maximumSubdivisionDepth = 12,
        RouteMissingDataPolicy missingDataPolicy = RouteMissingDataPolicy.RejectTransition,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(geometry);
        ArgumentNullException.ThrowIfNull(metadata);
        if (!double.IsFinite(resolutionNauticalMiles) || resolutionNauticalMiles is < .05 or > 120)
        {
            throw new ArgumentOutOfRangeException(nameof(resolutionNauticalMiles));
        }
        ValidateDomain(bounds);

        var grid = BuildGrid(bounds, resolutionNauticalMiles);
        var latitudeCosine = LongitudeScale(grid);
        var haloLatitude = Math.Max(Math.Abs(grid.SouthLatitudeDegrees), Math.Abs(grid.NorthLatitudeDegrees)) +
            MaximumReportedDistanceNauticalMiles / NauticalMilesPerDegree;
        if (haloLatitude > 85)
            throw new InvalidOperationException("The optional landmask's padded geometry domain exceeds its supported ±85° latitude limit.");
        var distanceLatitudeCosine = Math.Cos(haloLatitude * Math.PI / 180);
        var samples = Rasterize(
            geometry,
            grid,
            distanceLatitudeCosine,
            resolutionNauticalMiles,
            cancellationToken);

        // Half the node diagonal bounds how far a bilinear sample can sit from
        // the nearest node, which is the worst case for the interpolated value.
        var latitudeStepNauticalMiles = grid.LatitudeStepDegrees * NauticalMilesPerDegree;
        var longitudeStepNauticalMiles =
            grid.LongitudeStepDegrees * NauticalMilesPerDegree * latitudeCosine;
        var interpolationError = 0.5 * Math.Sqrt(
            (latitudeStepNauticalMiles * latitudeStepNauticalMiles) +
            (longitudeStepNauticalMiles * longitudeStepNauticalMiles));

        return new RouteLandmaskOptions(
            grid,
            samples,
            resolutionNauticalMiles,
            interpolationError,
            metadata,
            clearanceNauticalMiles,
            maximumSubdivisionDepth,
            missingDataPolicy);
    }

    private static void ValidateDomain(GeographicBounds bounds)
    {
        var longitudeSpan = bounds.CrossesAntimeridian ? bounds.East - bounds.West + 360 : bounds.East - bounds.West;
        if (bounds.South < -75 || bounds.North > 75 || bounds.North - bounds.South > 120 ||
            longitudeSpan > 120 || bounds.CrossesAntimeridian)
            throw new InvalidOperationException(
                "The optional managed landmask supports non-wrapping regional domains no wider than 120° within ±75° " +
                "(including room for its 600 nm geometry halo). Keep polygon enforcement or explicitly select a supported regional source.");
    }

    /// <summary>
    /// Lays a grid over a supported non-wrapping corridor. Its geometry halo
    /// may wrap, but wrapping routing domains require the native GSHHG path.
    /// </summary>
    private static RouteEnvironmentGrid BuildGrid(
        GeographicBounds bounds,
        double resolutionNauticalMiles)
    {
        var latitudeStep = resolutionNauticalMiles / NauticalMilesPerDegree;
        var latitudeSpan = bounds.North - bounds.South;
        var longitudeSpan = bounds.CrossesAntimeridian
            ? bounds.East - bounds.West + 360
            : bounds.East - bounds.West;

        // A degree of longitude is shorter away from the equator, so the corridor
        // needs more columns per degree the further from the equator it sits.
        var latitudeCosine = Math.Max(
            MinimumLatitudeCosine,
            Math.Cos(MaximumAbsoluteLatitude(bounds) * Math.PI / 180));
        var longitudeStep = resolutionNauticalMiles /
            (NauticalMilesPerDegree * latitudeCosine);

        var latitudeCount = NodeCount(latitudeSpan, latitudeStep);
        var longitudeCount = NodeCount(longitudeSpan, longitudeStep);
        if ((long)latitudeCount * longitudeCount > MaximumSampleCount)
        {
            throw new InvalidOperationException(
                $"A {resolutionNauticalMiles:0.###} nautical mile landmask over this " +
                $"corridor needs {(long)latitudeCount * longitudeCount:N0} samples, " +
                $"which exceeds the {MaximumSampleCount:N0} sample budget. Use a " +
                "coarser resolution or a smaller corridor.");
        }

        return new RouteEnvironmentGrid(
            bounds.South,
            bounds.West,
            latitudeStep,
            longitudeStep,
            latitudeCount,
            longitudeCount,
            globalLongitudeCoverage: longitudeSpan >= 360 - 1e-9);
    }

    private static int NodeCount(double spanDegrees, double stepDegrees)
    {
        // Two nodes is the floor because bilinear interpolation needs a cell.
        var cells = (int)Math.Ceiling(Math.Max(spanDegrees, 0) / stepDegrees);
        return Math.Max(2, cells + 1);
    }

    private static double MaximumAbsoluteLatitude(GeographicBounds bounds) =>
        Math.Max(Math.Abs(bounds.South), Math.Abs(bounds.North));

    private static double LongitudeScale(RouteEnvironmentGrid grid) =>
        Math.Max(
            MinimumLatitudeCosine,
            Math.Cos(
                Math.Max(
                    Math.Abs(grid.SouthLatitudeDegrees),
                    Math.Abs(grid.NorthLatitudeDegrees)) * Math.PI / 180));

    private static double[] Rasterize(
        LandGeometryIndex geometry,
        RouteEnvironmentGrid grid,
        double latitudeCosine,
        double resolutionNauticalMiles,
        CancellationToken cancellationToken)
    {
        var factory = NetTopologySuite.NtsGeometryServices.Instance
            .CreateGeometryFactory(srid: 4326);

        // Pad the candidate window so a node near the corridor edge still sees
        // the coastline just outside it. Longitude degrees shrink by cos(lat),
        // so the same distance spans a wider longitude window; padding both
        // axes by the latitude figure would drop coastline that is still within
        // reporting range and report the clamp instead, overstating sea room.
        var latitudePadDegrees =
            MaximumReportedDistanceNauticalMiles / NauticalMilesPerDegree;
        var longitudePadDegrees = latitudePadDegrees / latitudeCosine;
        var window = new Envelope(
            grid.WestLongitudeDegrees - longitudePadDegrees,
            grid.EastLongitudeDegrees + longitudePadDegrees,
            grid.SouthLatitudeDegrees - latitudePadDegrees,
            grid.NorthLatitudeDegrees + latitudePadDegrees);

        var scaled = new STRtree<Geometry>();
        var candidates = geometry.QueryGeometries(window);
        foreach (var candidate in candidates)
        {
            var compressed = ScaleLongitude(candidate, latitudeCosine);
            scaled.Insert(compressed.EnvelopeInternal, compressed);
        }

        var empty = candidates.Count == 0;
        if (!empty)
        {
            scaled.Build();
        }

        var distance = new GeometryItemDistance();
        var samples = new double[grid.SampleCount];
        for (var row = 0; row < grid.LatitudeCount; row++)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var latitude = grid.SouthLatitudeDegrees + (row * grid.LatitudeStepDegrees);
            for (var column = 0; column < grid.LongitudeCount; column++)
            {
                var longitude =
                    grid.WestLongitudeDegrees + (column * grid.LongitudeStepDegrees);
                samples[(row * grid.LongitudeCount) + column] = empty
                    ? MaximumReportedDistanceNauticalMiles
                    : SignedDistance(
                        geometry,
                        scaled,
                        distance,
                        factory,
                        latitude,
                        longitude,
                        latitudeCosine,
                        resolutionNauticalMiles);
            }
        }

        return samples;
    }

    private static double SignedDistance(
        LandGeometryIndex geometry,
        STRtree<Geometry> scaled,
        GeometryItemDistance distance,
        GeometryFactory factory,
        double latitude,
        double longitude,
        double latitudeCosine,
        double resolutionNauticalMiles)
    {
        var probe = factory.CreatePoint(
            new NtsCoordinate(longitude * latitudeCosine, latitude));
        var nearest = scaled.NearestNeighbour(
            probe.EnvelopeInternal,
            probe,
            distance);
        var magnitude = nearest is null
            ? MaximumReportedDistanceNauticalMiles
            : Math.Min(
                nearest.Distance(probe) * NauticalMilesPerDegree,
                MaximumReportedDistanceNauticalMiles);

        // A node exactly on the coastline reads zero, which would let a
        // transition graze land. Bias it inland by a fraction of a cell so the
        // interpolated field crosses zero on the water side of the coast.
        if (IsLand(geometry, latitude, longitude))
        {
            return -Math.Max(magnitude, resolutionNauticalMiles * 1e-3);
        }

        return magnitude;
    }

    private static bool IsLand(
        LandGeometryIndex geometry,
        double latitude,
        double longitude)
    {
        // The grid may run past 180 for an antimeridian corridor, but Coordinate
        // only accepts the canonical range.
        var normalized = longitude;
        while (normalized > 180)
        {
            normalized -= 360;
        }

        while (normalized < -180)
        {
            normalized += 360;
        }

        return geometry.Contains(
            new CoreCoordinate(Math.Clamp(latitude, -90, 90), normalized));
    }

    private static Geometry ScaleLongitude(Geometry geometry, double factor)
    {
        var scaled = geometry.Copy();
        scaled.Apply(new LongitudeScaleFilter(factor));
        scaled.GeometryChanged();
        return scaled;
    }

    private sealed class LongitudeScaleFilter(double factor) : ICoordinateFilter
    {
        public void Filter(NtsCoordinate coordinate) => coordinate.X *= factor;
    }

    private sealed class GeometryItemDistance : IItemDistance<Envelope, Geometry>
    {
        public double Distance(IBoundable<Envelope, Geometry> item, IBoundable<Envelope, Geometry> other) =>
            item.Item.Distance(other.Item);
    }
}
