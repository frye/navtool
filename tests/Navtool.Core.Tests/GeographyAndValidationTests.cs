namespace Navtool.Core.Tests;

public sealed class GeographyAndValidationTests
{
    [Theory]
    [InlineData(-90, -180)]
    [InlineData(90, 180)]
    [InlineData(0, 0)]
    public void Coordinate_accepts_valid_edges(double latitude, double longitude)
    {
        var coordinate = new Coordinate(latitude, longitude);

        Assert.Equal(latitude, coordinate.Latitude);
        Assert.Equal(longitude, coordinate.Longitude);
    }

    [Fact]
    public void Coordinate_rejects_non_finite_and_out_of_range_values()
    {
        Assert.Throws<ArgumentOutOfRangeException>(() => new Coordinate(double.NaN, 0));
        Assert.Throws<ArgumentOutOfRangeException>(() => new Coordinate(91, 0));
        Assert.Throws<ArgumentOutOfRangeException>(() => new Coordinate(0, double.PositiveInfinity));
        Assert.Throws<ArgumentOutOfRangeException>(() => new Coordinate(0, -181));
    }

    [Fact]
    public void Bounds_choose_the_short_antimeridian_span()
    {
        var bounds = GeographicBounds.FromCoordinates(
            new[] { new Coordinate(10, 170), new Coordinate(20, -170) });

        Assert.True(bounds.CrossesAntimeridian);
        Assert.True(bounds.Contains(new Coordinate(15, 179)));
        Assert.True(bounds.Contains(new Coordinate(15, -179)));
        Assert.False(bounds.Contains(new Coordinate(15, 0)));
    }

    [Fact]
    public void Opposite_antimeridian_notations_are_the_same_location()
    {
        var east = new Coordinate(10, 180);
        var west = new Coordinate(10, -180);
        var bounds = GeographicBounds.FromCoordinates(new[] { east });

        Assert.True(east.IsSameLocation(west));
        Assert.True(bounds.Contains(west));
    }

    [Fact]
    public void Bounds_containment_handles_simple_and_edge_longitude_spans()
    {
        var outer = new GeographicBounds(-40, 40, -100, 100);

        Assert.True(outer.Contains(new GeographicBounds(-40, 40, -100, 100)));
        Assert.True(outer.Contains(new GeographicBounds(-10, 10, -50, 50)));
        // Latitude outside the band is rejected.
        Assert.False(outer.Contains(new GeographicBounds(-50, 10, -50, 50)));
        // Longitude spilling past the western edge is rejected.
        Assert.False(outer.Contains(new GeographicBounds(-10, 10, -150, 50)));
    }

    [Fact]
    public void Bounds_containment_rejects_inner_span_crossing_excluded_antimeridian_band()
    {
        // Outer excludes the 20-degree band around +/-180. The inner span crosses the
        // antimeridian, so all four of its corners fall inside the outer span even though
        // the arc it sweeps through 180 lies outside. Corner sampling would wrongly accept it.
        var outer = new GeographicBounds(-40, 40, -170, 170);
        var innerCrossing = new GeographicBounds(-10, 10, 160, -160);

        Assert.True(innerCrossing.CrossesAntimeridian);
        Assert.False(outer.Contains(innerCrossing));
    }

    [Fact]
    public void Bounds_containment_accepts_inner_span_within_crossing_outer()
    {
        var outer = new GeographicBounds(-40, 40, 170, -170);
        var inner = new GeographicBounds(-10, 10, 175, -175);

        Assert.True(outer.CrossesAntimeridian);
        Assert.True(outer.Contains(inner));
        // A wider inner span that overruns the crossing outer arc is rejected.
        Assert.False(outer.Contains(new GeographicBounds(-10, 10, 160, -160)));
    }


    [Fact]
    public void Validator_reports_endpoint_and_departure_problems_together()
    {
        var now = new DateTimeOffset(2026, 7, 14, 18, 0, 0, TimeSpan.Zero);
        var endpoint = new Coordinate(42, -70);
        var request = new RouteRequest(
            "route-a",
            endpoint,
            endpoint,
            now.AddHours(-1),
            now.AddHours(-2));
        var options = new RouteValidationOptions(TimeSpan.FromDays(10), TimeSpan.FromDays(5));

        var result = new RouteRequestValidator().Validate(request, now, options);

        Assert.False(result.IsValid);
        Assert.Contains(result.Errors, error => error.Code == RouteValidationErrorCode.IdenticalEndpoints);
        Assert.Contains(result.Errors, error => error.Code == RouteValidationErrorCode.DepartureInPast);
        Assert.Contains(result.Errors, error => error.Code == RouteValidationErrorCode.ArrivalNotAfterDeparture);
    }

    [Fact]
    public void Validator_accepts_a_request_within_the_forecast_window()
    {
        var now = new DateTimeOffset(2026, 7, 14, 18, 0, 0, TimeSpan.Zero);
        var request = new RouteRequest(
            "route-a",
            new Coordinate(42, -70),
            new Coordinate(45, -50),
            now.AddHours(2),
            now.AddDays(2));
        var options = new RouteValidationOptions(TimeSpan.FromDays(10), TimeSpan.FromDays(5));

        var result = new RouteRequestValidator().Validate(request, now, options);

        Assert.True(result.IsValid);
        Assert.Empty(result.Errors);
    }
}
