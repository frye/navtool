using System.Runtime.InteropServices;
using Navtool.Core;
using Navtool.Infrastructure;

namespace Navtool.Infrastructure.Tests;

public sealed class NativeRouterInteropLayoutTests
{
    [Fact]
    public void Abi_v6_struct_layouts_match_native_contract()
    {
        Assert.Equal(152, Marshal.SizeOf<NativeRoutingOptions>());
        Assert.Equal(184, Marshal.SizeOf<NativeRoutingProgress>());
        Assert.Equal(40, Marshal.SizeOf<NativeLatticeSearchProgress>());
        Assert.Equal(
            144,
            Marshal.OffsetOf<NativeRoutingProgress>(nameof(NativeRoutingProgress.LatticeSearch)).ToInt32());
    }

    [Fact]
    public void Abi_v7_environment_struct_layouts_match_native_contract()
    {
        // These sizes are asserted with matching static_asserts in
        // native/Navtool.RouterBridge/tests/bridge_tests.cpp. A mismatch on
        // either side is a silent memory corruption across the boundary, so both
        // sides pin the same literals rather than deriving them from each other.
        Assert.Equal(24, Marshal.SizeOf<NativeProviderMetadata>());
        Assert.Equal(56, Marshal.SizeOf<NativeEnvironmentGridSpec>());
        Assert.Equal(120, Marshal.SizeOf<NativeCurrentSettings>());
        Assert.Equal(64, Marshal.SizeOf<NativeWaveDerating>());
        Assert.Equal(224, Marshal.SizeOf<NativeWaveSettings>());
        Assert.Equal(128, Marshal.SizeOf<NativeLandmaskSettings>());
        Assert.Equal(16, Marshal.SizeOf<NativeExclusionRing>());
        Assert.Equal(32, Marshal.SizeOf<NativeExclusionPolygon>());
        Assert.Equal(64, Marshal.SizeOf<NativeExclusionZone>());
        Assert.Equal(96, Marshal.SizeOf<NativeExclusionSettings>());
        Assert.Equal(576, Marshal.SizeOf<NativeEnvironment>());

        Assert.Equal(8, Marshal.OffsetOf<NativeEnvironment>(nameof(NativeEnvironment.Currents)).ToInt32());
        Assert.Equal(128, Marshal.OffsetOf<NativeEnvironment>(nameof(NativeEnvironment.Waves)).ToInt32());
        Assert.Equal(352, Marshal.OffsetOf<NativeEnvironment>(nameof(NativeEnvironment.Land)).ToInt32());
        Assert.Equal(480, Marshal.OffsetOf<NativeEnvironment>(nameof(NativeEnvironment.Exclusions)).ToInt32());
    }

    [Fact]
    public void Supported_abi_version_is_seven()
    {
        Assert.Equal(7u, NativeRouterBridgeOptions.SupportedAbiVersion);
    }

    [Fact]
    public void Native_options_preserve_balanced_and_optional_wind_limit_values()
    {
        var balanced = NativeRoutingOptions.From(RouteOptimizationOptions.Balanced);
        Assert.Equal((int)RouteSolver.IsochroneBeam, balanced.Solver);
        Assert.Equal(
            (int)RouteHeadingAugmentation.DestinationBearingAndVelocityMadeGood,
            balanced.HeadingAugmentation);
        Assert.Equal((int)RouteWindSampling.Midpoint, balanced.WindSampling);
        Assert.Equal((int)RoutePolarAngleInterpolation.MonotoneCubic, balanced.PolarAngleInterpolation);
        Assert.Equal(0UL, balanced.Flags);

        var limited = NativeRoutingOptions.From(new RouteOptimizationOptions(
            maximumTrueWindSpeedKnots: 35));
        Assert.Equal(1UL, limited.Flags);
        Assert.Equal(35, limited.MaximumTrueWindSpeedKnots);

        var lattice = NativeRoutingOptions.From(new RouteOptimizationOptions(
            solver: RouteSolver.TimeDependentLattice,
            lattice: new RouteLatticeOptions(
                subdivisionLevel: 5,
                timeBucket: TimeSpan.FromMinutes(45),
                refinementLevels: 2,
                corridorWidthNauticalMiles: 600,
                corridorWideningRetries: 3,
                progressEveryExpansions: 75,
                searchAlgorithm: RouteLatticeSearchAlgorithm.Dijkstra)));
        Assert.Equal((int)RouteSolver.TimeDependentLattice, lattice.Solver);
        Assert.Equal(5UL, lattice.LatticeSubdivisionLevel);
        Assert.Equal(45, lattice.LatticeTimeBucketMinutes);
        Assert.Equal(2UL, lattice.LatticeRefinementLevels);
        Assert.Equal(600, lattice.LatticeCorridorWidthNauticalMiles);
        Assert.Equal(3UL, lattice.LatticeCorridorWideningRetries);
        Assert.Equal(75UL, lattice.LatticeProgressEveryExpansions);
        Assert.Equal(
            (int)RouteLatticeSearchAlgorithm.Dijkstra,
            lattice.LatticeSearchAlgorithm);
    }

    /// <summary>
    /// The capability bits exist so a bridge can advertise partial Stage 3
    /// support. Checking only the top-level environment bit would let a
    /// configured provider reach the native call and fail there as an opaque
    /// InvalidEnvironment status, so each provider in use is checked first.
    /// </summary>
    [Fact]
    public void Missing_provider_capability_is_named_before_the_native_call()
    {
        var metadata = new RouteProviderMetadata("test", "unit test", "1");
        var all = NativeRouterCapabilities.Environment |
            NativeRouterCapabilities.CurrentProvider |
            NativeRouterCapabilities.SeaState |
            NativeRouterCapabilities.SignedDistanceLandmask |
            NativeRouterCapabilities.ExclusionZones;

        var currents = new RouteEnvironmentOptions(
            currents: RouteCurrentOptions.Uniform(1.5, -0.5, metadata));
        Assert.Equal(
            "current providers",
            NativeRouterBridge.DescribeMissingCapability(
                all & ~NativeRouterCapabilities.CurrentProvider,
                currents));
        Assert.Null(NativeRouterBridge.DescribeMissingCapability(all, currents));

        var waves = new RouteEnvironmentOptions(
            waves: RouteWaveOptions.Uniform(2, 8, 180, metadata));
        Assert.Equal(
            "sea state derating",
            NativeRouterBridge.DescribeMissingCapability(
                all & ~NativeRouterCapabilities.SeaState,
                waves));

        // The top-level bit still wins, so the original message is preserved
        // for a bridge with no Stage 3 support at all.
        Assert.Equal(
            "Stage 3 environmental physics",
            NativeRouterBridge.DescribeMissingCapability(
                NativeRouterCapabilities.None,
                currents));
    }

    /// <summary>
    /// A provider that is not configured must not be required, otherwise a
    /// bridge lacking one capability would refuse routes that never use it.
    /// </summary>
    [Fact]
    public void Unconfigured_providers_do_not_require_their_capability()
    {
        var metadata = new RouteProviderMetadata("test", "unit test", "1");
        var currentsOnly = new RouteEnvironmentOptions(
            currents: RouteCurrentOptions.Uniform(1, 0, metadata));

        Assert.Null(NativeRouterBridge.DescribeMissingCapability(
            NativeRouterCapabilities.Environment |
                NativeRouterCapabilities.CurrentProvider,
            currentsOnly));
    }
}
