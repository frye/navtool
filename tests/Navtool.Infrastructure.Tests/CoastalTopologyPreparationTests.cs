using Navtool.Core;
using NetTopologySuite.Geometries;
using CoreCoordinate = Navtool.Core.Coordinate;
using NtsCoordinate = NetTopologySuite.Geometries.Coordinate;

namespace Navtool.Infrastructure.Tests;

public sealed class CoastalTopologyPreparationTests
{
    private static readonly GeometryFactory Factory = new();
    private static readonly DateTimeOffset Departure = DateTimeOffset.UnixEpoch;

    [Fact]
    public void Sdf_identity_covers_actual_samples_grid_and_enforcement_parameters()
    {
        var original = Mask();
        var identity = CoastalTopologyPreparation.IdentifyLandmask(original, CancellationToken.None);
        Assert.Equal(identity, CoastalTopologyPreparation.IdentifyLandmask(Mask(), CancellationToken.None));
        foreach (var changed in new[] { Mask(sample: 49), Mask(step: 2), Mask(error: .2),
                     Mask(clearance: 1), Mask(depth: 10), Mask(policy: RouteMissingDataPolicy.FailRoute) })
            Assert.NotEqual(identity, CoastalTopologyPreparation.IdentifyLandmask(changed, CancellationToken.None));
        Assert.Throws<OperationCanceledException>(() =>
            CoastalTopologyPreparation.IdentifyLandmask(original, new CancellationToken(true)));

        static RouteLandmaskOptions Mask(double sample = 50, double step = 1, double error = .1,
            double clearance = 0, int depth = 12, RouteMissingDataPolicy policy = RouteMissingDataPolicy.RejectTransition) =>
            new(new RouteEnvironmentGrid(0, 0, step, 1, 2, 2), [sample, 50, 50, 50], 1, error,
                new RouteProviderMetadata("same name", "same attribution", "same revision"), clearance, depth, policy);
    }

    [Fact]
    public void Polygon_caps_preserve_a_full_callback_sampling_halo_and_holes()
    {
        var shell = Factory.CreateLinearRing(
            [new(-2, -2), new(2, -2), new(2, 2), new(-2, 2), new(-2, -2)]);
        var hole = Factory.CreateLinearRing(
            [new(-.2, -.2), new(.2, -.2), new(.2, .2), new(-.2, .2), new(-.2, -.2)]);
        var land = new LandGeometryIndex([Factory.CreatePolygon(shell, [hole])], maximumSampleNauticalMiles: 2);
        var request = new RouteRequest("caps", new(0, -3), new(0, 3), Departure, Departure.AddDays(1));
        var topology = CoastalTopologyPreparation.Create(new(-5, 5, -5, 5), request, land,
            land.GeometryIdentity, CancellationToken.None);
        Assert.NotEmpty(topology.Caps);
        Assert.InRange(topology.Caps.Length, 1, 64);
        Assert.True(topology.GeometryWork > 0);
        Assert.False(land.Contains(new(0, 0)));
        foreach (var cap in topology.Caps)
        {
            Assert.True(land.Contains(cap.Center));
            for (var heading = 0; heading < 360; heading += 10)
                Assert.True(land.Contains(Offset(cap.Center, heading,
                    cap.RadiusNauticalMiles + land.MaximumSegmentSampleNauticalMiles)),
                    $"Cap at {cap.Center} lost its sampling halo near heading {heading}.");
        }
    }

    [Fact]
    public void Certified_caps_are_clipped_to_declared_preparation_coverage()
    {
        var land = new LandGeometryIndex([Factory.CreatePolygon(
            [new NtsCoordinate(-2, -2), new(2, -2), new(2, 2), new(-2, 2), new(-2, -2)])]);
        var bounds = new GeographicBounds(-.1, .1, -.1, .1);
        var request = new RouteRequest("bounded", new(0, 0), new(0, .05), Departure, Departure.AddDays(1));
        var topology = CoastalTopologyPreparation.Create(bounds, request, land, land.GeometryIdentity, CancellationToken.None);
        Assert.NotEmpty(topology.Caps);
        foreach (var cap in topology.Caps)
        for (var heading = 0; heading < 360; heading += 10)
            Assert.True(bounds.Contains(Offset(cap.Center, heading, cap.RadiusNauticalMiles)));
    }

    [Fact]
    public void Small_land_features_are_not_inflated_into_false_barriers()
    {
        var land = new LandGeometryIndex([Factory.CreatePolygon(
            [new NtsCoordinate(-.005, -.005), new(.005, -.005), new(.005, .005),
                new(-.005, .005), new(-.005, -.005)])]);
        var request = new RouteRequest("tiny", new(0, -.1), new(0, .1), Departure, Departure.AddDays(1));
        var topology = CoastalTopologyPreparation.Create(new(-.01, .01, -.01, .01), request, land,
            land.GeometryIdentity, CancellationToken.None);
        Assert.Empty(topology.Caps);
        Assert.NotEmpty(topology.Probes);
    }

    [Fact]
    public void Antimeridian_probe_domain_is_preserved_without_clipping_search()
    {
        var bounds = new GeographicBounds(47, 50, 179, -177);
        var request = new RouteRequest("wrap", new(48, 179.5), new(48, -178), Departure, Departure.AddDays(1));
        var topology = CoastalTopologyPreparation.Create(bounds, request, null, "native-mask", CancellationToken.None);
        Assert.Equal(bounds, topology.Bounds);
        Assert.Empty(topology.Caps);
        Assert.All(topology.Probes, p => Assert.True(bounds.Contains(p)));
        Assert.Contains(topology.Probes, p => p.Longitude > 179);
        Assert.Contains(topology.Probes, p => p.Longitude < -177);
    }

    [Fact]
    public void Preparation_is_cancellable_and_geometry_identity_is_content_based()
    {
        var polygon = Factory.CreatePolygon(
            [new NtsCoordinate(-2, -2), new(2, -2), new(2, 2), new(-2, 2), new(-2, -2)]);
        var land = new LandGeometryIndex([polygon]);
        Assert.Equal(land.GeometryIdentity, new LandGeometryIndex([polygon.Copy()]).GeometryIdentity);
        var request = new RouteRequest("cancel", new(0, -3), new(0, 3), Departure, Departure.AddDays(1));
        Assert.Throws<OperationCanceledException>(() => CoastalTopologyPreparation.Create(
            new(-5, 5, -5, 5), request, land, land.GeometryIdentity, new CancellationToken(true)));
    }

    private static CoreCoordinate Offset(CoreCoordinate start, double heading, double distance)
    {
        const double radians = Math.PI / 180;
        var angular = distance / 3440.065;
        var bearing = heading * radians;
        var latitude = start.Latitude * radians;
        var resultLatitude = Math.Asin(Math.Sin(latitude) * Math.Cos(angular) +
            Math.Cos(latitude) * Math.Sin(angular) * Math.Cos(bearing));
        var longitude = start.Longitude * radians + Math.Atan2(
            Math.Sin(bearing) * Math.Sin(angular) * Math.Cos(latitude),
            Math.Cos(angular) - Math.Sin(latitude) * Math.Sin(resultLatitude));
        return new(resultLatitude / radians, Math.IEEERemainder(longitude / radians, 360));
    }
}
