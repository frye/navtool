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
/// longitude by the cosine of the highest absolute latitude in the corridor.
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
        if (!double.IsFinite(resolutionNauticalMiles) || resolutionNauticalMiles <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(resolutionNauticalMiles));
        }

        var grid = BuildGrid(bounds, resolutionNauticalMiles);
        var latitudeCosine = LongitudeScale(grid);
        var samples = Rasterize(
            geometry,
            grid,
            latitudeCosine,
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

    /// <summary>
    /// Lays a grid over the corridor. Longitude keeps its west anchor inside
    /// [-180, 180] and is allowed to run east past 180 for an antimeridian
    /// corridor, which is how router-lib expects a wrapping span to be
    /// expressed.
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
        // the coastline just outside it.
        var padDegrees = Math.Min(
            MaximumReportedDistanceNauticalMiles / NauticalMilesPerDegree,
            (MaximumReportedDistanceNauticalMiles / NauticalMilesPerDegree) /
                latitudeCosine);
        var window = new Envelope(
            grid.WestLongitudeDegrees - padDegrees,
            grid.EastLongitudeDegrees + padDegrees,
            grid.SouthLatitudeDegrees - padDegrees,
            grid.NorthLatitudeDegrees + padDegrees);

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
