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
