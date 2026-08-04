using Navtool.Core;
using Navtool.Infrastructure;

namespace Navtool.Infrastructure.Tests;

public sealed class ExclusionZoneJsonSourceTests
{
    private const string MinimalDocument = """
        {
          "name": "Test set",
          "source": "unit test",
          "revision": "1",
          "zones": [
            {
              "identifier": "square",
              "source": "unit test",
              "revision": 4,
              "activeFrom": "2026-01-01T00:00:00Z",
              "activeUntil": "2026-02-01T00:00:00Z",
              "polygons": [
                {
                  "outer": [[0, 0], [1, 0], [1, 1], [0, 1], [0, 0]],
                  "holes": [[[0.25, 0.25], [0.75, 0.25], [0.75, 0.75], [0.25, 0.75]]]
                }
              ]
            }
          ]
        }
        """;

    [Fact]
    public void LoadReadsZoneIdentityAndActivationWindow()
    {
        var options = ExclusionZoneJsonSource.Load(MinimalDocument);

        var zone = Assert.Single(options.Zones);
        Assert.Equal("square", zone.Identifier);
        Assert.Equal("unit test", zone.Source);
        Assert.Equal(4UL, zone.Revision);
        Assert.Equal(
            DateTimeOffset.Parse("2026-01-01T00:00:00Z"),
            zone.ActiveFrom);
        Assert.Equal(
            DateTimeOffset.Parse("2026-02-01T00:00:00Z"),
            zone.ActiveUntil);
    }

    [Fact]
    public void LoadReadsVerticesInGeoJsonAxisOrder()
    {
        var options = ExclusionZoneJsonSource.Load("""
            {
              "name": "Test set",
              "source": "unit test",
              "zones": [{
                "identifier": "z",
                "source": "s",
                "polygons": [{ "outer": [[10, 1], [11, 1], [11, 2]] }]
              }]
            }
            """);

        var vertex = options.Zones[0].Polygons[0].Outer.Vertices[0];
        Assert.Equal(1, vertex.Latitude);
        Assert.Equal(10, vertex.Longitude);
    }

    [Fact]
    public void LoadDropsTheRepeatedClosingVertex()
    {
        var options = ExclusionZoneJsonSource.Load(MinimalDocument);

        // Five vertices in, four out: router-lib closes rings implicitly.
        Assert.Equal(4, options.Zones[0].Polygons[0].Outer.Vertices.Count);
    }

    [Fact]
    public void LoadReadsHoles()
    {
        var options = ExclusionZoneJsonSource.Load(MinimalDocument);

        var hole = Assert.Single(options.Zones[0].Polygons[0].Holes);
        Assert.Equal(4, hole.Vertices.Count);
    }

    [Fact]
    public void LoadDefaultsToExcludingTheBoundary()
    {
        var options = ExclusionZoneJsonSource.Load(MinimalDocument);

        Assert.Equal(
            RouteExclusionBoundaryPolicy.BoundaryExcluded,
            options.BoundaryPolicy);
    }

    [Fact]
    public void LoadReadsAnExplicitBoundaryPolicy()
    {
        var options = ExclusionZoneJsonSource.Load(
            MinimalDocument.Replace(
                "\"revision\": \"1\",",
                "\"revision\": \"1\", \"boundaryPolicy\": \"boundary_allowed\","));

        Assert.Equal(
            RouteExclusionBoundaryPolicy.BoundaryAllowed,
            options.BoundaryPolicy);
    }

    [Fact]
    public void LoadRejectsAnUnknownBoundaryPolicy()
    {
        Assert.Throws<InvalidDataException>(() =>
            ExclusionZoneJsonSource.Load(
                MinimalDocument.Replace(
                    "\"revision\": \"1\",",
                    "\"revision\": \"1\", \"boundaryPolicy\": \"boundary_ignored\",")));
    }

    [Fact]
    public void LoadRejectsAnEmptyZoneList()
    {
        // An empty set is indistinguishable from unrestricted water, so it must
        // never parse into a usable configuration.
        Assert.Throws<InvalidDataException>(() =>
            ExclusionZoneJsonSource.Load("""
                { "name": "n", "source": "s", "zones": [] }
                """));
    }

    [Fact]
    public void LoadRejectsAMissingZonesArray()
    {
        Assert.Throws<InvalidDataException>(() =>
            ExclusionZoneJsonSource.Load("""
                { "name": "n", "source": "s" }
                """));
    }

    [Fact]
    public void LoadRejectsAMissingSource()
    {
        Assert.Throws<InvalidDataException>(() =>
            ExclusionZoneJsonSource.Load("""
                { "name": "n", "zones": [] }
                """));
    }

    [Fact]
    public void LoadRejectsAVertexThatIsNotAPair()
    {
        Assert.Throws<InvalidDataException>(() =>
            ExclusionZoneJsonSource.Load("""
                {
                  "name": "n", "source": "s",
                  "zones": [{
                    "identifier": "z", "source": "s",
                    "polygons": [{ "outer": [[1], [2], [3]] }]
                  }]
                }
                """));
    }

    [Fact]
    public void LoadRejectsAnInvertedActivationWindow()
    {
        Assert.Throws<ArgumentException>(() =>
            ExclusionZoneJsonSource.Load("""
                {
                  "name": "n", "source": "s",
                  "zones": [{
                    "identifier": "z", "source": "s",
                    "activeFrom": "2026-02-01T00:00:00Z",
                    "activeUntil": "2026-01-01T00:00:00Z",
                    "polygons": [{ "outer": [[0, 0], [1, 0], [1, 1]] }]
                  }]
                }
                """));
    }

    [Fact]
    public void LoadRejectsDuplicateZoneIdentifiers()
    {
        Assert.Throws<ArgumentException>(() =>
            ExclusionZoneJsonSource.Load("""
                {
                  "name": "n", "source": "s",
                  "zones": [
                    {
                      "identifier": "z", "source": "s",
                      "polygons": [{ "outer": [[0, 0], [1, 0], [1, 1]] }]
                    },
                    {
                      "identifier": "z", "source": "s",
                      "polygons": [{ "outer": [[2, 2], [3, 2], [3, 3]] }]
                    }
                  ]
                }
                """));
    }

    [Fact]
    public void LoadAntarcticExampleProducesTwoHemisphericPolygons()
    {
        var options = ExclusionZoneJsonSource.LoadAntarcticExample();

        var zone = Assert.Single(options.Zones);
        Assert.Equal("antarctic-exclusion-zone", zone.Identifier);
        Assert.Equal(2, zone.Polygons.Count);
        Assert.All(
            zone.Polygons.SelectMany(polygon => polygon.Outer.Vertices),
            vertex => Assert.True(
                vertex.Latitude <= -62,
                $"Vertex at {vertex.Latitude} sits north of the 62S limit."));
    }

    [Fact]
    public void LoadAntarcticExampleIsAlwaysActive()
    {
        var zone = ExclusionZoneJsonSource.LoadAntarcticExample().Zones[0];

        Assert.Null(zone.ActiveFrom);
        Assert.Null(zone.ActiveUntil);
    }

    [Fact]
    public async Task LoadFileAsyncWrapsAnInvalidDocument()
    {
        var path = Path.Combine(Path.GetTempPath(), $"{Guid.NewGuid():N}.json");
        await File.WriteAllTextAsync(path, "{ \"name\": \"n\" }");
        try
        {
            var exception = await Assert.ThrowsAsync<InvalidDataException>(
                async () => await ExclusionZoneJsonSource.LoadFileAsync(path));
            Assert.Contains(path, exception.Message, StringComparison.Ordinal);
        }
        finally
        {
            File.Delete(path);
        }
    }
}
