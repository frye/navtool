using Navtool.Core;
using Navtool.Infrastructure;
using NetTopologySuite.Geometries;
using NtsCoordinate = NetTopologySuite.Geometries.Coordinate;

namespace Navtool.Infrastructure.Tests;

public sealed class SignedDistanceLandmaskBuilderTests
{
    private static readonly GeometryFactory Factory =
        NetTopologySuite.NtsGeometryServices.Instance.CreateGeometryFactory(srid: 4326);

    private static readonly RouteProviderMetadata Metadata =
        new("test landmask", "unit test", "1");

    /// <summary>A one-degree square island centred on the equator at 10E.</summary>
    private static LandGeometryIndex Island() =>
        new([
            Factory.CreatePolygon(
            [
                new NtsCoordinate(9.5, -0.5),
                new NtsCoordinate(10.5, -0.5),
                new NtsCoordinate(10.5, 0.5),
                new NtsCoordinate(9.5, 0.5),
                new NtsCoordinate(9.5, -0.5)
            ])
        ]);

    [Fact]
    public void BuildReportsNegativeDistanceInsideLand()
    {
        var mask = SignedDistanceLandmaskBuilder.Build(
            Island(),
            new GeographicBounds(-1, 1, 9, 11),
            resolutionNauticalMiles: 6,
            Metadata);

        var centre = SampleAt(mask, 0, 10);
        Assert.True(centre < 0, $"The island centre should be land but read {centre}.");
    }

    [Fact]
    public void BuildReportsPositiveDistanceOverWater()
    {
        var mask = SignedDistanceLandmaskBuilder.Build(
            Island(),
            new GeographicBounds(-3, 3, 7, 13),
            resolutionNauticalMiles: 12,
            Metadata);

        var offshore = SampleAt(mask, 2.5, 12.5);
        Assert.True(offshore > 0, $"Open water should be positive but read {offshore}.");
    }

    [Fact]
    public void BuildNeverOverstatesTheDistanceToLand()
    {
        // A node two degrees north of the island's north edge is 120 nautical
        // miles from land. The mask must not claim more than that, because an
        // overstated distance is what would let a transition graze the coast.
        var mask = SignedDistanceLandmaskBuilder.Build(
            Island(),
            new GeographicBounds(-1, 3, 9, 11),
            resolutionNauticalMiles: 6,
            Metadata);

        var sample = SampleAt(mask, 2.5, 10);
        Assert.True(sample <= 120.5, $"Distance {sample} overstates the 120nm separation.");
        Assert.True(sample > 100, $"Distance {sample} is implausibly small.");
    }

    [Fact]
    public void BuildDeclaresAnInterpolationErrorCoveringHalfTheNodeDiagonal()
    {
        var mask = SignedDistanceLandmaskBuilder.Build(
            Island(),
            new GeographicBounds(-1, 1, 9, 11),
            resolutionNauticalMiles: 6,
            Metadata);

        // Half of a 6nm square cell's diagonal.
        var expected = 0.5 * Math.Sqrt((6.0 * 6.0) + (6.0 * 6.0));
        Assert.Equal(expected, mask.InterpolationErrorNauticalMiles, 3);
    }

    [Fact]
    public void BuildProducesAGridWhoseSampleCountMatchesItsExtent()
    {
        var mask = SignedDistanceLandmaskBuilder.Build(
            Island(),
            new GeographicBounds(-1, 1, 9, 11),
            resolutionNauticalMiles: 6,
            Metadata);

        Assert.Equal(mask.Grid.SampleCount, mask.SignedDistanceNauticalMiles.Count);
        Assert.True(mask.Grid.LatitudeCount >= 2);
        Assert.True(mask.Grid.LongitudeCount >= 2);
        Assert.All(mask.SignedDistanceNauticalMiles, value => Assert.True(double.IsFinite(value)));
    }

    [Fact]
    public void BuildCarriesTheRequestedClearanceAndPolicy()
    {
        var mask = SignedDistanceLandmaskBuilder.Build(
            Island(),
            new GeographicBounds(-1, 1, 9, 11),
            resolutionNauticalMiles: 6,
            Metadata,
            clearanceNauticalMiles: 2.5,
            maximumSubdivisionDepth: 9,
            missingDataPolicy: RouteMissingDataPolicy.FailRoute);

        Assert.Equal(2.5, mask.ClearanceNauticalMiles);
        Assert.Equal(9, mask.MaximumSubdivisionDepth);
        Assert.Equal(RouteMissingDataPolicy.FailRoute, mask.MissingDataPolicy);
        Assert.Same(Metadata, mask.Metadata);
    }

    [Fact]
    public void BuildRejectsAGridLargerThanTheSampleBudget()
    {
        Assert.Throws<InvalidOperationException>(() =>
            SignedDistanceLandmaskBuilder.Build(
                Island(),
                new GeographicBounds(-80, 80, -180, 180),
                resolutionNauticalMiles: 0.5,
                Metadata));
    }

    [Fact]
    public void BuildRejectsANonPositiveResolution()
    {
        Assert.Throws<ArgumentOutOfRangeException>(() =>
            SignedDistanceLandmaskBuilder.Build(
                Island(),
                new GeographicBounds(-1, 1, 9, 11),
                resolutionNauticalMiles: 0,
                Metadata));
    }

    [Fact]
    public void BuildReportsOpenOceanWhenNoLandIsNearby()
    {
        var mask = SignedDistanceLandmaskBuilder.Build(
            new LandGeometryIndex([]),
            new GeographicBounds(-1, 1, 9, 11),
            resolutionNauticalMiles: 30,
            Metadata);

        Assert.All(
            mask.SignedDistanceNauticalMiles,
            value => Assert.True(value > 0, "Empty geometry must read as open water."));
    }

    [Fact]
    public void BuildSeesLandBeyondTheLatitudePadAtHighLatitude()
    {
        // Longitude degrees shrink by cos(lat), so at 70N a 13 degree gap is
        // only ~267nm - well inside the 600nm reporting range. Padding the
        // candidate query by the latitude figure on both axes would drop this
        // island and report the 600nm clamp instead, telling the router there
        // is far more sea room to the east than there really is.
        var island = new LandGeometryIndex([
            Factory.CreatePolygon(
            [
                new NtsCoordinate(15, 69.5),
                new NtsCoordinate(16, 69.5),
                new NtsCoordinate(16, 70.5),
                new NtsCoordinate(15, 70.5),
                new NtsCoordinate(15, 69.5)
            ])
        ]);

        var mask = SignedDistanceLandmaskBuilder.Build(
            island,
            new GeographicBounds(69, 71, 0, 2),
            resolutionNauticalMiles: 30,
            Metadata);

        var eastEdge = SampleAt(mask, 70, 2);
        Assert.True(
            eastEdge < 600,
            $"Distance {eastEdge} is the open-ocean clamp, so the island was " +
            "excluded from the candidate query.");
        Assert.True(
            eastEdge > 100,
            $"Distance {eastEdge} is implausibly small for a 13 degree gap.");
    }

    /// <summary>Nearest-node lookup, which is enough to assert sign and scale.</summary>
    private static double SampleAt(
        RouteLandmaskOptions mask,
        double latitude,
        double longitude)
    {
        var row = (int)Math.Round(
            (latitude - mask.Grid.SouthLatitudeDegrees) / mask.Grid.LatitudeStepDegrees);
        var column = (int)Math.Round(
            (longitude - mask.Grid.WestLongitudeDegrees) / mask.Grid.LongitudeStepDegrees);
        row = Math.Clamp(row, 0, mask.Grid.LatitudeCount - 1);
        column = Math.Clamp(column, 0, mask.Grid.LongitudeCount - 1);
        return mask.SignedDistanceNauticalMiles[(row * mask.Grid.LongitudeCount) + column];
    }
}
