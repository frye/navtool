namespace Navtool.Core.Tests;

public sealed class RouteOptimizationOptionsTests
{
    [Fact]
    public void Balanced_profile_enables_quality_improvements_without_operational_policy()
    {
        var options = RouteOptimizationOptions.Balanced;

        Assert.Equal(RouteSolver.IsochroneBeam, options.Solver);
        Assert.Equal(RouteSolver.IsochroneBeam, new RouteOptimizationOptions().Solver);
        Assert.Equal(
            RouteHeadingAugmentation.DestinationBearingAndVelocityMadeGood,
            options.HeadingAugmentation);
        Assert.Equal(RouteWindSampling.Midpoint, options.WindSampling);
        Assert.Equal(TimeSpan.Zero, options.MidpointWindSamplingThreshold);
        Assert.Equal(RoutePolarAngleInterpolation.MonotoneCubic, options.PolarAngleInterpolation);
        Assert.Equal(TimeSpan.Zero, options.Maneuver.TackPenalty);
        Assert.Equal(TimeSpan.Zero, options.Maneuver.GybePenalty);
        Assert.Null(options.MaximumTrueWindSpeedKnots);
        Assert.Equal(RouteAbovePolarRangePolicy.Clamp, options.AbovePolarRange);
        Assert.Equal(RoutePruningStrategy.DestinationDistanceGrid, options.PruningStrategy);
        Assert.Equal(
            RouteDestinationFrontSegmentPolicy.ProvisionalComponent,
            options.DestinationFront.SegmentPolicy);
    }

    [Fact]
    public void Upstream_compatible_profile_keeps_legacy_accuracy_settings()
    {
        var options = RouteOptimizationOptions.UpstreamCompatible;

        Assert.Equal(RouteHeadingAugmentation.None, options.HeadingAugmentation);
        Assert.Equal(RouteWindSampling.SegmentStart, options.WindSampling);
        Assert.Equal(RoutePolarAngleInterpolation.Linear, options.PolarAngleInterpolation);
    }

    [Fact]
    public void Options_reject_invalid_ranges_and_lattice_combinations()
    {
        Assert.Throws<ArgumentOutOfRangeException>(() =>
            new RouteManeuverOptions(TimeSpan.FromSeconds(-1), TimeSpan.Zero));
        Assert.Throws<ArgumentOutOfRangeException>(() =>
            new RouteDestinationFrontOptions(halfAngleDegrees: 0));
        Assert.Throws<ArgumentOutOfRangeException>(() =>
            new RouteLatticeOptions(subdivisionLevel: 8, refinementLevels: 1));
        Assert.Throws<ArgumentOutOfRangeException>(() =>
            new RouteLatticeOptions(timeBucket: TimeSpan.FromSeconds(30)));
        Assert.Throws<ArgumentOutOfRangeException>(() =>
            new RouteOptimizationOptions(maximumTrueWindSpeedKnots: 0));
        Assert.Throws<ArgumentOutOfRangeException>(() =>
            new RouteOptimizationOptions(pruningSectorDegrees: 181));
    }
}
