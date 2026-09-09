using System.Collections.Immutable;

namespace Navtool.Core.Tests;

public sealed class RoutingSetupTests
{
    [Fact]
    public void Unknown_seed_actions_do_not_break_public_audit_serialization()
    {
        var audit = new RouteNativeRunAudit("route_result_v2", RouteSolver.IsochroneBeam, 1);
        var json = System.Text.Json.JsonSerializer.Serialize(audit);
        Assert.DoesNotContain("CoastalSeedActions", json);
        var recorded = System.Text.Json.JsonSerializer.Serialize(audit with { CoastalSeedActions = [] });
        Assert.Contains("\"CoastalSeedActions\":[]", recorded);
    }

    internal static BoatAsset Demo() =>
        new("demo:v1", "Explicit demo", BoatAssetKind.Demo, BoatPolarFormat.NativeMatrix,
            new BoatValidationSummary("Native validated demo"));

    internal static RoutingCalculationContext Context(
        RouteOptimizationOptions? optimization = null, RouteEnvironmentOptions? environment = null)
    {
        var setup = new RoutingSetup(Demo());
        var options = optimization ?? new RouteOptimizationOptions(environment: environment);
        var resolved = new ResolvedRoutingOptions(setup.Quality, options,
            new RouteSearchSettings(TimeSpan.FromMinutes(30), TimeSpan.FromMinutes(5), 5, 5, 2, 1,
                100000, 10000, 1, true, true, true, 1, 0,
                [new RouteRoutingInterval(TimeSpan.FromMinutes(30))]),
            1, 1, TimeSpan.FromDays(30));
        return new(Guid.NewGuid(), setup, new ResolvedBoatAsset(setup.Boat),
            new NativeRoutingIdentity(8, "0.6.0-dev", "pinned-sha", "build", 1), resolved);
    }

    [Fact]
    public void Normal_setup_is_explicit_native_balanced_and_does_not_conflate_duration_and_acquisition()
    {
        Assert.Throws<ArgumentNullException>(() => new RoutingSetup(null!));
        var setup = new RoutingSetup(Demo());
        Assert.Equal(RoutingQuality.NativeBalanced, setup.Quality);
        Assert.Equal(RouteCoastalPruningMode.Off, setup.CoastalPruning);
        Assert.Equal(RouteCoastalPruningMode.Off, Context().Resolved.CoastalPruning);
        Assert.Equal(1, setup.PerformanceFactor);
        Assert.Equal(RoutingLandSource.NaturalEarth, setup.LandSource);
        Assert.Null(setup.HardDuration);
        Assert.Equal(TimeSpan.FromDays(30), Context().Resolved.HardDuration);
        Assert.Equal(TimeSpan.FromDays(10), RoutePlanRoutingRequest.MaximumForecastWindow);
    }

    [Fact]
    public void Coastal_selection_survives_native_defaults_and_professional_overrides()
    {
        var baseline = Context();
        var setup = new RoutingSetup(Demo(), coastalPruning: RouteCoastalPruningMode.ConservativeLandAware);
        var professional = new RoutingProfessionalOverrides(baseline.Resolved.Optimization);
        foreach (var overrides in new[] { null, professional })
        {
            var resolved = ResolvedRoutingOptions.FromNativeDefaults(setup, baseline.Resolved, overrides);
            var frozen = new RoutingCalculationContext(Guid.NewGuid(), setup, baseline.Boat,
                baseline.NativeIdentity with { BridgeAbiVersion = 9 }, resolved, overrides);
            Assert.Equal(setup.CoastalPruning, frozen.Resolved.CoastalPruning);
            Assert.Same(baseline.Resolved.Search, frozen.Resolved.Search);
        }
    }

    [Theory]
    [InlineData(-1)]
    [InlineData(2)]
    [InlineData(int.MaxValue)]
    public void Unknown_coastal_modes_are_rejected(int mode)
    {
        Assert.Throws<ArgumentOutOfRangeException>(() => new RoutingSetup(Demo(),
            coastalPruning: (RouteCoastalPruningMode)mode));
        var baseline = Context();
        Assert.Throws<RoutingException>(() => new RoutingCalculationContext(Guid.NewGuid(),
            baseline.Setup, baseline.Boat, baseline.NativeIdentity,
            baseline.Resolved with { CoastalPruning = (RouteCoastalPruningMode)mode }));
        Assert.Throws<ArgumentOutOfRangeException>(() => new RouteCoastalPruningDiagnostics(
            (RouteCoastalPruningMode)mode, "unavailable", null, 0, 0, 0, 0, 0, 0, 0));
    }

    [Fact]
    public void Coastal_context_rejects_silent_downgrade_and_lattice()
    {
        var baseline = Context();
        var setup = new RoutingSetup(Demo(), coastalPruning: RouteCoastalPruningMode.ConservativeLandAware);
        Assert.Throws<RoutingException>(() => new RoutingCalculationContext(Guid.NewGuid(),
            setup, baseline.Boat, baseline.NativeIdentity with { BridgeAbiVersion = 9 }, baseline.Resolved));
        var professional = new RoutingProfessionalOverrides(new RouteOptimizationOptions(solver: RouteSolver.TimeDependentLattice));
        var resolved = ResolvedRoutingOptions.FromNativeDefaults(setup, baseline.Resolved, professional);
        var error = Assert.Throws<RoutingException>(() => new RoutingCalculationContext(Guid.NewGuid(),
            setup, baseline.Boat, baseline.NativeIdentity with { BridgeAbiVersion = 9 }, resolved, professional));
        Assert.Contains("beam solver only", error.Message);
        Assert.Equal(RouteSolver.TimeDependentLattice, resolved.Optimization.Solver);
    }

    [Theory]
    [InlineData(0)]
    [InlineData(1)]
    [InlineData(2)]
    [InlineData(3)]
    [InlineData(4)]
    [InlineData(5)]
    [InlineData(6)]
    public void Coastal_audit_rejects_each_negative_counter(int index)
    {
        var counters = new long[7];
        counters[index] = -1;
        Assert.Throws<ArgumentOutOfRangeException>(() => new RouteCoastalPruningDiagnostics(
            RouteCoastalPruningMode.ConservativeLandAware, "ready", null,
            counters[0], counters[1], counters[2], counters[3], counters[4], counters[5], counters[6]));
    }

    [Fact]
    public void Coastal_audit_preserves_large_counts_and_unknown_is_absent()
    {
        Assert.Null(new RouteDiagnostics(0, 0, 0, 0).CoastalPruning);
        Assert.Null(new RouteNativeRunAudit("route_result_v2", RouteSolver.IsochroneBeam).CoastalPruning);
        Assert.Throws<ArgumentException>(() => new RouteCoastalPruningDiagnostics(
            RouteCoastalPruningMode.Off, " ", null, 0, 0, 0, 0, 0, 0, 0));
        var coastal = new RouteCoastalPruningDiagnostics(RouteCoastalPruningMode.ConservativeLandAware,
            "bound_unavailable", "Uncertain coverage", long.MaxValue, 2, 3, 4, 5, 6, 7);
        Assert.Equal(long.MaxValue, new RouteDiagnostics(0, 0, 0, 0, coastalPruning: coastal).CoastalPruning!.SkippedParents);
        Assert.Null(coastal.IncumbentArrival);
        Assert.Null(coastal.SourceIdentity);
        Assert.Null(coastal.DomainIdentity);
        Assert.Null(coastal.SeedStatus);
        Assert.Null(coastal.SpeedUpperKnots);
        Assert.Null(coastal.TopologyCaps);
        Assert.Null(coastal.NumericalMarginNauticalMiles);
        Assert.Null(coastal.ClearanceNauticalMiles);
    }

    [Theory]
    [InlineData(double.NaN)]
    [InlineData(double.PositiveInfinity)]
    [InlineData(double.NegativeInfinity)]
    [InlineData(-0.01)]
    public void Coastal_provenance_rejects_invalid_numeric_bounds(double value)
    {
        Assert.Throws<ArgumentOutOfRangeException>(() => new RouteCoastalPruningDiagnostics(
            RouteCoastalPruningMode.ConservativeLandAware, "ready", null, 0, 0, 0, 0, 0, 0, 0,
            speedUpperKnots: value));
        Assert.Throws<ArgumentOutOfRangeException>(() => new RouteCoastalPruningDiagnostics(
            RouteCoastalPruningMode.ConservativeLandAware, "ready", null, 0, 0, 0, 0, 0, 0, 0,
            numericalMarginNauticalMiles: value));
        Assert.Throws<ArgumentOutOfRangeException>(() => new RouteCoastalPruningDiagnostics(
            RouteCoastalPruningMode.ConservativeLandAware, "ready", null, 0, 0, 0, 0, 0, 0, 0,
            clearanceNauticalMiles: value));
    }

    [Fact]
    public void Coastal_provenance_allows_zero_margin_and_caps_but_requires_positive_speed()
    {
        Assert.Throws<ArgumentOutOfRangeException>(() => new RouteCoastalPruningDiagnostics(
            RouteCoastalPruningMode.ConservativeLandAware, "ready", null, 0, 0, 0, 0, 0, 0, 0,
            speedUpperKnots: 0));
        Assert.Throws<ArgumentOutOfRangeException>(() => new RouteCoastalPruningDiagnostics(
            RouteCoastalPruningMode.ConservativeLandAware, "ready", null, 0, 0, 0, 0, 0, 0, 0,
            topologyCaps: -1));
        var audit = new RouteCoastalPruningDiagnostics(RouteCoastalPruningMode.ConservativeLandAware,
            "ready", null, 0, 0, 0, 0, 0, 0, 0, sourceIdentity: "source", domainIdentity: "domain",
            seedStatus: "validated", speedUpperKnots: 25, topologyCaps: 0,
            numericalMarginNauticalMiles: 0, clearanceNauticalMiles: 0);
        Assert.Equal("source", audit.SourceIdentity);
        Assert.Equal("domain", audit.DomainIdentity);
        Assert.Equal("validated", audit.SeedStatus);
        Assert.Equal(25, audit.SpeedUpperKnots);
        Assert.Equal(0, audit.TopologyCaps);
        Assert.Equal(0, audit.NumericalMarginNauticalMiles);
        Assert.Equal(0, audit.ClearanceNauticalMiles);
    }

    [Theory]
    [InlineData(-0.001)]
    [InlineData(-1)]
    [InlineData(360)]
    [InlineData(720)]
    public void Coastal_seed_actions_reject_headings_outside_the_compass_range(double heading)
    {
        Assert.Throws<ArgumentOutOfRangeException>(() => new RouteCoastalSeedAction(heading, TimeSpan.FromSeconds(1)));
    }

    [Theory]
    [InlineData(0)]
    [InlineData(359.999)]
    public void Coastal_seed_actions_accept_canonical_heading_boundaries(double heading)
    {
        Assert.Equal(heading, new RouteCoastalSeedAction(heading, TimeSpan.FromSeconds(1)).HeadingDegrees);
    }

    [Fact]
    public void Coastal_seed_actions_are_immutable_and_preserve_unknown_versus_empty()
    {
        Assert.Throws<ArgumentOutOfRangeException>(() => new RouteCoastalSeedAction(double.NaN, TimeSpan.FromSeconds(1)));
        Assert.Throws<ArgumentOutOfRangeException>(() => new RouteCoastalSeedAction(double.PositiveInfinity, TimeSpan.FromSeconds(1)));
        Assert.Throws<ArgumentOutOfRangeException>(() => new RouteCoastalSeedAction(270, TimeSpan.Zero));
        Assert.Throws<ArgumentOutOfRangeException>(() => new RouteCoastalSeedAction(270, TimeSpan.FromTicks(1)));
        Assert.Throws<ArgumentOutOfRangeException>(() => new RouteCoastalSeedAction(270, TimeSpan.FromSeconds(-1)));
        var unknown = new RouteNativeRunAudit("route_result_v2", RouteSolver.IsochroneBeam);
        Assert.True(unknown.CoastalSeedActions.IsDefault);
        var empty = unknown with { CoastalSeedActions = [] };
        Assert.False(empty.CoastalSeedActions.IsDefault);
        Assert.Empty(empty.CoastalSeedActions);
        Assert.Throws<ArgumentException>(() => unknown with { CoastalSeedActions = [null!] });
        Assert.Throws<ArgumentException>(() => new RouteNativeRunAudit("route_result_v2", RouteSolver.IsochroneBeam,
            CoastalSeedActions: [null!]));
        var input = new[] { new RouteCoastalSeedAction(270, TimeSpan.FromSeconds(10)) };
        var audit = unknown with { CoastalSeedActions = input.ToImmutableArray() };
        input[0] = new RouteCoastalSeedAction(90, TimeSpan.FromSeconds(20));
        Assert.Equal(270, audit.CoastalSeedActions[0].HeadingDegrees);
        Assert.Equal(TimeSpan.FromSeconds(10), audit.CoastalSeedActions[0].Duration);
    }

    [Fact]
    public void Coastal_context_and_run_audit_require_new_abi_while_off_remains_compatible()
    {
        var baseline = Context();
        var setup = new RoutingSetup(Demo(), coastalPruning: RouteCoastalPruningMode.ConservativeLandAware);
        var resolved = ResolvedRoutingOptions.FromNativeDefaults(setup, baseline.Resolved);
        var error = Assert.Throws<RoutingException>(() => new RoutingCalculationContext(Guid.NewGuid(),
            setup, baseline.Boat, baseline.NativeIdentity, resolved));
        Assert.Equal(RoutingFailureKind.NativeUnavailable, error.Kind);
        Assert.Contains("ABI 9", error.Message);
        var attempts = new[] { new RouteAttemptAudit(Guid.NewGuid(), RouteSolver.IsochroneBeam,
            DateTimeOffset.UnixEpoch, DateTimeOffset.UnixEpoch) };
        Assert.Throws<ArgumentException>(() => new RouteRunAudit(Guid.NewGuid(), setup, resolved,
            baseline.NativeIdentity, RouteSolver.IsochroneBeam, attempts));
        foreach (var abi in new[] { 8, 9 })
        {
            var context = new RoutingCalculationContext(Guid.NewGuid(), baseline.Setup, baseline.Boat,
                baseline.NativeIdentity with { BridgeAbiVersion = abi }, baseline.Resolved);
            Assert.Equal(RouteCoastalPruningMode.Off, context.Resolved.CoastalPruning);
        }
    }

    [Fact]
    public void Native_defaults_are_preserved_except_explicit_cruising_overrides()
    {
        var context = Context();
        var native = context.Resolved with
        {
            Optimization = new RouteOptimizationOptions(
                headingAugmentation: RouteHeadingAugmentation.VelocityMadeGood,
                polarAngleInterpolation: RoutePolarAngleInterpolation.Linear,
                abovePolarRange: RouteAbovePolarRangePolicy.Clamp,
                lattice: new RouteLatticeOptions(subdivisionLevel: 5)),
            PerformanceFactor = 0.7
        };
        var resolved = ResolvedRoutingOptions.FromNativeDefaults(context.Setup, native);
        Assert.Same(native.Search, resolved.Search);
        Assert.Same(native.Optimization.Lattice, resolved.Optimization.Lattice);
        Assert.Equal(RouteHeadingAugmentation.VelocityMadeGood, resolved.Optimization.HeadingAugmentation);
        Assert.Equal(RoutePolarAngleInterpolation.MonotoneCubic, resolved.Optimization.PolarAngleInterpolation);
        Assert.Equal(RouteAbovePolarRangePolicy.NoSpeed, resolved.Optimization.AbovePolarRange);
        Assert.Equal(1, resolved.PerformanceFactor);
    }

    [Fact]
    public void Professional_edits_are_explicit_and_not_a_setup_property()
    {
        var context = Context();
        var edits = new RoutingProfessionalOverrides(new RouteOptimizationOptions(
            abovePolarRange: RouteAbovePolarRangePolicy.Clamp));
        var resolved = ResolvedRoutingOptions.FromNativeDefaults(context.Setup, context.Resolved, edits);
        var frozen = new RoutingCalculationContext(Guid.NewGuid(), context.Setup, context.Boat,
            context.NativeIdentity, resolved, edits);
        Assert.Same(edits, frozen.ProfessionalOverrides);
        Assert.Equal(RouteAbovePolarRangePolicy.Clamp, frozen.Resolved.Optimization.AbovePolarRange);
        Assert.Equal(context.Setup, frozen.Setup);
        Assert.Throws<RoutingException>(() => new RoutingCalculationContext(Guid.NewGuid(),
            context.Setup, context.Boat, context.NativeIdentity, resolved));
    }

    [Fact]
    public void Imported_bytes_and_environment_collections_are_deeply_immutable()
    {
        var bytes = new byte[] { 1, 2, 3 };
        var asset = new BoatAsset("hash", "import.pol", BoatAssetKind.Imported, BoatPolarFormat.Automatic,
            new BoatValidationSummary("Accepted"));
        var boat = new ResolvedBoatAsset(asset, bytes);
        bytes[0] = 200;
        Assert.Equal(1, boat.PolarBytes[0]);
        var grid = new RouteEnvironmentGrid(0, 0, 1, 1, 2, 2);
        var values = new[] { 1d, 2, 3, 4 };
        var provider = new RouteProviderMetadata("test", "test", "1");
        var currents = RouteCurrentOptions.FromGrid(grid, values, values, provider);
        var waves = RouteWaveOptions.FromGrid(grid, values, values, values, provider);
        var vertices = new List<Coordinate> { new(0, 0), new(1, 1), new(2, 0) };
        var ring = new RouteExclusionRing(vertices);
        var holes = new List<RouteExclusionRing> { ring };
        var polygon = new RouteExclusionPolygon(ring, holes);
        var polygons = new List<RouteExclusionPolygon> { polygon };
        var zones = new List<RouteExclusionZone> { new("zone", "test", polygons) };
        var exclusions = new RouteExclusionOptions(zones, provider);
        var environment = new RouteEnvironmentOptions(currents: currents, waves: waves, exclusions: exclusions);
        var context = Context(environment: environment);
        values[0] = 100;
        vertices.Clear();
        holes.Clear();
        polygons.Clear();
        zones.Clear();
        Assert.Equal(1, context.Resolved.Optimization.Environment!.Currents!.EastKnots![0]);
        Assert.Equal(1, waves.SignificantHeightMetres![0]);
        Assert.Equal(3, exclusions.Zones[0].Polygons[0].Outer.Vertices.Count);
        Assert.Single(exclusions.Zones[0].Polygons[0].Holes);
        Assert.False(currents.EastKnots is double[]);
    }

    [Fact]
    public async Task Configured_engine_support_is_checked_before_forecast_acquisition()
    {
        var context = Context();
        var now = DateTimeOffset.UtcNow;
        var workflow = new RoutingWorkflow([], new LegacyEngine());
        var request = new RoutingWorkflowRequest(new RouteRequest("r", new(0, 0), new(1, 1), now, now.AddDays(1)),
            [ForecastModel.NoaaGfs], calculationContext: context);
        var error = await Assert.ThrowsAsync<RoutingException>(() => workflow.ExecuteAsync(request));
        Assert.Equal(RoutingFailureKind.InvalidConfiguration, error.Kind);
        IRouteEngine engine = new LegacyEngine();
        Assert.Throws<RoutingException>(() => engine.CalculateAsync(request.Route, null!,
            request.Optimization, null, CancellationToken.None));
    }

    [Fact]
    public void Search_interval_inputs_are_copied_and_run_audit_does_not_repeat_bulk_environment()
    {
        var intervals = new List<RouteRoutingInterval> { new(TimeSpan.FromMinutes(30)) };
        var search = new RouteSearchSettings(TimeSpan.FromMinutes(30), TimeSpan.FromMinutes(5),
            5, 5, 2, 1, 0, 0, 1, true, true, true, 1, 0, intervals);
        intervals.Clear();
        Assert.Single(search.Intervals);
        var context = Context(environment: new RouteEnvironmentOptions(currents: RouteCurrentOptions.Uniform(
            1, 2, new RouteProviderMetadata("current", "source", "version"))));
        var attempts = new List<RouteAttemptAudit>
        {
            new(Guid.NewGuid(), RouteSolver.IsochroneBeam, DateTimeOffset.UnixEpoch, DateTimeOffset.UnixEpoch)
        };
        var audit = new RouteRunAudit(context.CalculationId, context.Setup, context.Resolved,
            context.NativeIdentity, RouteSolver.IsochroneBeam, attempts,
            professionalOverrides: new RoutingProfessionalOverrides(context.Resolved.Optimization));
        attempts.Clear();
        Assert.Single(audit.Attempts);
        Assert.Null(audit.Resolved.Optimization.Environment);
        Assert.Null(audit.ProfessionalOverrides!.Optimization!.Environment);
        Assert.NotNull(context.Resolved.Optimization.Environment);
    }

    [Fact]
    public void Legacy_telemetry_is_unknown_and_polar_or_ground_audit_uses_matching_frames()
    {
        var time = DateTimeOffset.UtcNow;
        var legacy = new RoutePoint(new(0, 0), time, 90, 6, 15, 270, 0);
        Assert.Null(legacy.ApparentWindSpeedKnots);
        Assert.Null(legacy.ApparentWindAngleDegrees);
        // Wind flows east at 15, current east at 4, through-water speed east at 6:
        // water wind 11 - boat 6 == ground wind 15 - SOG 10 == apparent 5.
        var environment = new RoutePointEnvironment(10, 90, 6, 4, 0);
        var ground = new RoutePoint(new(0, 0), time, 90, 6, 15, 270, 0, environment);
        var polar = new RoutePoint(new(0, 0), time, 90, 6, 15, 270, 0, environment, 11, 270);
        Assert.Equal(5, ground.ApparentWindSpeedKnots!.Value, 9);
        Assert.Equal(ground.ApparentWindSpeedKnots, polar.ApparentWindSpeedKnots);
        Assert.Null(legacy.PolarWindSpeedKnots);
    }

    [Theory]
    [InlineData(ForecastModel.NoaaGfs, 0, new[] { 119, 120, 123, 126 }, true)]
    [InlineData(ForecastModel.NoaaGfs, 0, new[] { 118, 120, 123 }, false)]
    [InlineData(ForecastModel.EcmwfIfs, 0, new[] { 141, 144, 150, 156 }, true)]
    [InlineData(ForecastModel.EcmwfIfs, 0, new[] { 138, 144, 150 }, false)]
    [InlineData(ForecastModel.EcmwfIfs, 6, new[] { 87, 90 }, true)]
    [InlineData(ForecastModel.EcmwfIfs, 6, new[] { 90, 93 }, false)]
    [InlineData(ForecastModel.NoaaGfs, 0, new[] { 120 }, true)]
    public void Official_forecast_cadence_handles_transitions_and_rejects_true_gaps(
        ForecastModel model, int hour, int[] offsets, bool valid)
    {
        var run = new ForecastRun(model.Provider(), model, new DateTimeOffset(2026, 8, 1, hour, 0, 0, TimeSpan.Zero));
        var times = offsets.Select(offset => run.InitializedAt.AddHours(offset));
        if (valid) ForecastTimePolicy.Validate(run, times, true);
        else Assert.Throws<RoutingException>(() => ForecastTimePolicy.Validate(run, times, true));
    }

    [Fact]
    public void Local_cadence_is_an_explicit_policy_and_metadata_single_time_is_valid()
    {
        var run = new ForecastRun(ForecastProvider.Noaa, ForecastModel.NoaaGfs, DateTimeOffset.UtcNow);
        var times = new[] { run.InitializedAt, run.InitializedAt.AddHours(4) };
        Assert.Throws<RoutingException>(() => ForecastTimePolicy.Validate(run, times, false));
        Assert.Throws<RoutingException>(() => ForecastTimePolicy.Validate(run, times, false, TimeSpan.FromHours(3)));
        ForecastTimePolicy.Validate(run, times, false, TimeSpan.FromHours(6));
        var coverage = new ForecastCoverage(new(-1, 1, -1, 1), [run.InitializedAt]);
        Assert.Equal(coverage.ValidFrom, coverage.ValidThrough);
    }

    [Fact]
    public void Regional_land_requires_explicit_durable_source_domain_and_checked_budgets()
    {
        var path = Path.Combine(Directory.GetCurrentDirectory(), "regional.b");
        var policy = new RouteRegionalLandPolicy(path, new string('a', 64), new(20, 50, -90, -40),
            1, 0.5, 20, 100000, 1000000, 10000000);
        var setup = new RoutingSetup(Demo(), landSource: RoutingLandSource.RegionalGshhg, regionalLand: policy);
        var plan = new RoutePlan("Regional", [new("A", new(30, -70)), new("B", new(35, -60))])
            .SetRoutingSetup(setup);
        Assert.Same(policy, plan.RoutingSetup!.RegionalLand);
        Assert.Equal(policy, plan.CopyAs(new RoutePlanId(), "Copy").RoutingSetup!.RegionalLand);
        Assert.Throws<ArgumentException>(() => new RoutingSetup(Demo(), landSource: RoutingLandSource.RegionalGshhg));
        Assert.Throws<ArgumentException>(() => new RouteRegionalLandPolicy(path, new string('a', 64),
            new(-90, 90, -180, 180), 1, 0, 10, 100, 100, 100));
        Assert.Throws<ArgumentOutOfRangeException>(() => new RouteRegionalLandPolicy(path, new string('a', 64),
            new(20, 50, -90, -40), 1, 5, 5, 100, 100, 100));
    }

    [Fact]
    public void Regional_selection_rejects_conflicting_native_landmask_source()
    {
        var baseline = Context(environment: new RouteEnvironmentOptions(landRequest: new RouteLandmaskRequest()));
        var policy = new RouteRegionalLandPolicy(Path.Combine(Directory.GetCurrentDirectory(), "regional.b"),
            new string('a', 64), new(20, 50, -90, -40), 1, 0, 20, 100000, 1000000, 10000000);
        var setup = new RoutingSetup(baseline.Setup.Boat, landSource: RoutingLandSource.RegionalGshhg,
            regionalLand: policy);
        var error = Assert.Throws<RoutingException>(() => new RoutingCalculationContext(Guid.NewGuid(),
            setup, baseline.Boat, baseline.NativeIdentity, baseline.Resolved));
        Assert.Equal(RoutingFailureKind.InvalidConfiguration, error.Kind);
    }

    [Fact]
    public void Regional_policy_preserves_attribution_missing_policy_and_normalized_fingerprint()
    {
        var path = Path.Combine(Directory.GetCurrentDirectory(), "regional.b");
        var policy = new RouteRegionalLandPolicy(path, "sha256:" + new string('A', 64),
            new(-10, 10, 170, -170), 0.05, 0, 600, 250000, 10000000, 100000000,
            attribution: "GSHHG publication", missingDataPolicy: RouteMissingDataPolicy.RejectTransition);
        Assert.Equal(new string('a', 64), policy.SourceIdentity);
        Assert.True(policy.StudyBounds.CrossesAntimeridian);
        Assert.Equal("GSHHG publication", policy.Attribution);
        Assert.Equal(RouteMissingDataPolicy.RejectTransition, policy.MissingDataPolicy);
        Assert.Throws<ArgumentException>(() => new RouteRegionalLandPolicy(path, "not-a-sha256",
            new(0, 10, 0, 10), 1, 0, 10, 100, 100, 100));
    }

    [Theory]
    [InlineData(0.01, 10, 250000, 10000000, 100000000)]
    [InlineData(121, 10, 250000, 10000000, 100000000)]
    [InlineData(1, 601, 250000, 10000000, 100000000)]
    [InlineData(1, 10, 250001, 10000000, 100000000)]
    [InlineData(1, 10, 250000, 10000001, 100000000)]
    [InlineData(1, 10, 250000, 10000000, 100000001)]
    public void Regional_hard_resource_caps_cannot_be_raised(double resolution, double cap,
        int nodes, int points, int tests)
    {
        Assert.Throws<ArgumentOutOfRangeException>(() => new RouteRegionalLandPolicy(
            Path.Combine(Directory.GetCurrentDirectory(), "regional.b"), new string('a', 64),
            new(0, 10, 0, 10), resolution, 0, cap, (ulong)nodes, (ulong)points, (ulong)tests));
    }

    private sealed class LegacyEngine : IRouteEngine
    {
        public ValueTask<RouteResult> CalculateAsync(RouteRequest request, ForecastAcquisition forecast,
            IProgress<RouteCalculationProgress>? progress, CancellationToken cancellationToken) =>
            throw new InvalidOperationException("This legacy engine must not be called.");
    }
}
