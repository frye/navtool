namespace Navtool.Core.Tests;

public sealed class RouteEnvironmentOptionsTests
{
    private static readonly RouteProviderMetadata Metadata =
        new("test-provider", "test-source", "rev-1");

    private static RouteEnvironmentGrid Grid() => new(
        southLatitudeDegrees: 40,
        westLongitudeDegrees: -60,
        latitudeStepDegrees: 1,
        longitudeStepDegrees: 1,
        latitudeCount: 2,
        longitudeCount: 2);

    [Fact]
    public void Default_options_leave_every_provider_unconfigured()
    {
        var options = new RouteEnvironmentOptions();

        Assert.False(options.IsActive);
        Assert.Null(options.Currents);
        Assert.Null(options.Waves);
        Assert.Null(options.Land);
        Assert.Null(options.LandRequest);
        Assert.Null(options.Exclusions);
    }

    [Fact]
    public void Balanced_profile_configures_no_environment()
    {
        Assert.Null(RouteOptimizationOptions.Balanced.Environment);
        Assert.Null(RouteOptimizationOptions.UpstreamCompatible.Environment);
        Assert.Null(new RouteOptimizationOptions().Environment);
    }

    [Fact]
    public void Uniform_current_defaults_to_fail_route_like_router_lib()
    {
        var current = RouteCurrentOptions.Uniform(1.5, -0.5, Metadata);

        Assert.Equal(RouteMissingDataPolicy.FailRoute, current.MissingDataPolicy);
        Assert.Equal(1.5, current.UniformEastKnots);
        Assert.Equal(-0.5, current.UniformNorthKnots);
    }

    [Theory]
    [InlineData(double.NaN, 0)]
    [InlineData(0, double.PositiveInfinity)]
    public void Uniform_current_rejects_non_finite_components(double east, double north)
    {
        Assert.Throws<ArgumentOutOfRangeException>(() => RouteCurrentOptions.Uniform(east, north, Metadata));
    }

    [Fact]
    public void Grid_requires_at_least_two_nodes_per_axis_for_bilinear_interpolation()
    {
        Assert.Throws<ArgumentOutOfRangeException>(() => new RouteEnvironmentGrid(
            southLatitudeDegrees: 40,
            westLongitudeDegrees: -60,
            latitudeStepDegrees: 1,
            longitudeStepDegrees: 1,
            latitudeCount: 1,
            longitudeCount: 4));
    }

    [Fact]
    public void Grid_rejects_a_sample_array_whose_length_does_not_match_the_node_count()
    {
        Assert.Throws<ArgumentException>(() => new RouteLandmaskOptions(
            Grid(),
            [1, 2, 3],
            resolutionNauticalMiles: 1,
            interpolationErrorNauticalMiles: 0.5,
            Metadata));
    }

    /// <summary>
    /// A non-finite sample must be refused rather than coerced. Silently treating
    /// NaN as open water is exactly the kind of fallback Stage 3 forbids.
    /// </summary>
    [Fact]
    public void Grid_rejects_non_finite_samples()
    {
        Assert.Throws<ArgumentException>(() => new RouteLandmaskOptions(
            Grid(),
            [1, 2, 3, double.NaN],
            resolutionNauticalMiles: 1,
            interpolationErrorNauticalMiles: 0.5,
            Metadata));
    }

    [Fact]
    public void Wave_options_reject_a_negative_significant_height()
    {
        Assert.Throws<ArgumentOutOfRangeException>(() => RouteWaveOptions.Uniform(-0.1, 8, 180, Metadata));
    }

    [Fact]
    public void Wave_options_reject_a_non_positive_period()
    {
        Assert.Throws<ArgumentOutOfRangeException>(() => RouteWaveOptions.Uniform(2, 0, 180, Metadata));
    }

    [Fact]
    public void Landmask_rejects_a_subdivision_depth_router_lib_would_refuse()
    {
        var grid = Grid();
        double[] distances = [1, 1, 1, 1];

        Assert.Throws<ArgumentOutOfRangeException>(() => new RouteLandmaskOptions(
            grid,
            distances,
            resolutionNauticalMiles: 1,
            interpolationErrorNauticalMiles: 0.5,
            Metadata,
            maximumSubdivisionDepth: 0));
        Assert.Throws<ArgumentOutOfRangeException>(() => new RouteLandmaskOptions(
            grid,
            distances,
            resolutionNauticalMiles: 1,
            interpolationErrorNauticalMiles: 0.5,
            Metadata,
            maximumSubdivisionDepth: 33));
    }

    /// <summary>
    /// A corridor-scoped mask has finite coverage, so leaving it must reject the
    /// transition rather than fail the whole route. This differs deliberately
    /// from the current and wave defaults, which match router-lib.
    /// </summary>
    [Fact]
    public void Landmask_defaults_to_reject_transition_because_coverage_is_corridor_scoped()
    {
        var landmask = new RouteLandmaskOptions(
            Grid(),
            [1, 1, 1, 1],
            resolutionNauticalMiles: 1,
            interpolationErrorNauticalMiles: 0.5,
            Metadata);

        Assert.Equal(RouteMissingDataPolicy.RejectTransition, landmask.MissingDataPolicy);
    }

    [Fact]
    public void Supplying_both_a_built_mask_and_a_land_request_is_rejected_as_contradictory()
    {
        var landmask = new RouteLandmaskOptions(
            Grid(),
            [1, 1, 1, 1],
            resolutionNauticalMiles: 1,
            interpolationErrorNauticalMiles: 0.5,
            Metadata);
        var request = new RouteLandmaskRequest();

        Assert.Throws<ArgumentException>(() => new RouteEnvironmentOptions(
            land: landmask,
            landRequest: request));
    }

    [Fact]
    public void A_land_request_alone_counts_as_configured_so_the_engine_resolves_it()
    {
        var options = new RouteEnvironmentOptions(landRequest: new RouteLandmaskRequest());

        Assert.True(options.IsActive);
        Assert.Null(options.Land);
        Assert.NotNull(options.LandRequest);
    }

    [Fact]
    public void Resolving_a_land_request_swaps_it_for_the_built_mask()
    {
        var options = new RouteEnvironmentOptions(landRequest: new RouteLandmaskRequest());
        var landmask = new RouteLandmaskOptions(
            Grid(),
            [1, 1, 1, 1],
            resolutionNauticalMiles: 1,
            interpolationErrorNauticalMiles: 0.5,
            Metadata);

        var resolved = options.WithResolvedLand(landmask);

        Assert.Same(landmask, resolved.Land);
        Assert.Null(resolved.LandRequest);
    }

    [Fact]
    public void Exclusion_ring_rejects_fewer_than_three_vertices()
    {
        Assert.Throws<ArgumentException>(() => new RouteExclusionRing(
        [
            new Coordinate(40, -60),
            new Coordinate(41, -60)
        ]));
    }

    [Fact]
    public void Exclusion_zone_rejects_an_activation_window_that_ends_before_it_starts()
    {
        var ring = new RouteExclusionRing(
        [
            new Coordinate(40, -60),
            new Coordinate(41, -60),
            new Coordinate(41, -59)
        ]);
        var polygon = new RouteExclusionPolygon(ring);
        var start = new DateTimeOffset(2026, 1, 2, 0, 0, 0, TimeSpan.Zero);

        Assert.Throws<ArgumentException>(() => new RouteExclusionZone(
            "zone",
            "source",
            revision: 1,
            polygons: [polygon],
            activeFrom: start,
            activeUntil: start.AddDays(-1)));
    }

    [Fact]
    public void Exclusion_options_reject_an_empty_zone_set()
    {
        Assert.Throws<ArgumentException>(() => new RouteExclusionOptions([], Metadata));
    }

    [Fact]
    public void With_environment_leaves_every_other_option_untouched()
    {
        var baseline = new RouteOptimizationOptions(maximumTrueWindSpeedKnots: 35);
        var environment = new RouteEnvironmentOptions(currents: RouteCurrentOptions.Uniform(1, 0, Metadata));

        var updated = baseline.WithEnvironment(environment);

        Assert.Same(environment, updated.Environment);
        Assert.Equal(35, updated.MaximumTrueWindSpeedKnots);
        Assert.Equal(baseline.Solver, updated.Solver);
        Assert.Equal(baseline.WindSampling, updated.WindSampling);
        Assert.Equal(baseline.PolarAngleInterpolation, updated.PolarAngleInterpolation);
        Assert.Equal(baseline.HeadingAugmentation, updated.HeadingAugmentation);
        Assert.Null(baseline.Environment);
    }
}
