using System.Text.Json;
using System.Text.Json.Nodes;
using System.Collections.Immutable;
using Navtool.Core;
using Navtool.Infrastructure;

namespace Navtool.Infrastructure.Tests;

public sealed class RoutePlanJsonRepositoryTests
{
    private static RouteCoastalPruningDiagnostics CoastalAudit() =>
        new(RouteCoastalPruningMode.ConservativeLandAware, "ready", "Some coverage remains uncertain",
            long.MaxValue, 2, 3, 4, 5, 6, 7, DateTimeOffset.Parse("2026-08-01T19:00:00Z"),
            "source-fingerprint", "bounded-domain-identity", "validated", 27.25, long.MaxValue, 0.002, 0.15);

    [Fact]
    public async Task Coastal_selection_and_complete_audit_round_trip_and_copy_without_asset_access()
    {
        using var directory = new TestDirectory();
        var repository = new RoutePlanJsonRepository(directory.Path);
        var coastal = CoastalAudit();
        var plan = CreateAuditedPlan(directory.Path, coastal);
        await repository.SaveAsync(plan);
        var loaded = await repository.OpenAsync(plan.Id);
        var copy = await repository.SaveAsAsync(loaded, "Coastal copy");
        foreach (var restored in new[] { loaded, await repository.OpenAsync(copy.Id) })
        {
            Assert.Equal(RouteCoastalPruningMode.ConservativeLandAware, restored.RoutingSetup!.CoastalPruning);
            foreach (var leg in restored.Results[0].Legs)
            {
                var route = leg.Route!;
                Assert.Equal(coastal, route.Diagnostics.CoastalPruning);
                Assert.Equal(coastal, route.NativeAudit!.CoastalPruning);
                Assert.Equal(coastal, route.RunAudit!.Native!.CoastalPruning);
                Assert.Equal(
                    new[] { new RouteCoastalSeedAction(270, TimeSpan.FromMinutes(15)),
                            new RouteCoastalSeedAction(275, TimeSpan.FromSeconds(901)) },
                    route.NativeAudit.CoastalSeedActions.ToArray());
                Assert.Equal(route.NativeAudit.CoastalSeedActions.ToArray(),
                    route.RunAudit.Native.CoastalSeedActions.ToArray());
                Assert.Equal(coastal.Mode, route.RunAudit.Setup.CoastalPruning);
                Assert.Equal(coastal.Mode, route.RunAudit.Resolved.CoastalPruning);
                Assert.Equal(coastal, route.WithLandAvoidance(route.LandAvoidance).Diagnostics.CoastalPruning);
                Assert.Equal(coastal, route.WithRunAudit(route.RunAudit).NativeAudit!.CoastalPruning);
            }
        }
    }

    [Theory]
    [InlineData(1)]
    [InlineData(2)]
    [InlineData(3)]
    [InlineData(4)]
    [InlineData(5)]
    [InlineData(6)]
    public async Task Earlier_schemas_migrate_coastal_selection_to_off_and_audit_to_unknown(int version)
    {
        using var directory = new TestDirectory();
        var repository = new RoutePlanJsonRepository(directory.Path);
        var plan = version == 6 ? CreateAuditedPlan(directory.Path, CoastalAudit()) : WithResult(CreatePlan());
        await repository.SaveAsync(plan);
        var path = Path.Combine(repository.RootDirectory, $"{plan.Id}.route.json");
        var root = JsonNode.Parse(await File.ReadAllTextAsync(path))!;
        root["schemaVersion"] = version;
        if (version == 1)
        {
            root["plan"]!.AsObject().Remove("currentPosition");
            root["plan"]!.AsObject().Remove("activeLegId");
        }
        await File.WriteAllTextAsync(path, root.ToJsonString());
        var original = await File.ReadAllBytesAsync(path);
        var loaded = await repository.OpenAsync(plan.Id);
        Assert.Equal(original, await File.ReadAllBytesAsync(path));
        if (version == 6)
            Assert.Equal(RouteCoastalPruningMode.Off, loaded.RoutingSetup!.CoastalPruning);
        else
            Assert.Null(loaded.RoutingSetup);
        for (var i = 0; i < loaded.Results[0].Legs.Length; i++)
        {
            var leg = loaded.Results[0].Legs[i];
            var old = plan.Results[0].Legs[i];
            Assert.Equal(old.Route!.Points.Select(point => point.Location), leg.Route!.Points.Select(point => point.Location));
            Assert.Equal(old.Route.ArrivalTime, leg.Route.ArrivalTime);
            Assert.Null(leg.Route.Diagnostics.CoastalPruning);
            Assert.Null(leg.Route.NativeAudit?.CoastalPruning);
            Assert.True(leg.Route.NativeAudit?.CoastalSeedActions.IsDefault ?? true);
            if (version == 6)
            {
                Assert.Equal(old.Origin, leg.Origin);
                Assert.Equal(old.PlannedHold, leg.PlannedHold);
                Assert.Equal(old.ExecutionSession, leg.ExecutionSession);
                Assert.Equal(RouteCoastalPruningMode.Off, leg.Route.RunAudit!.Setup.CoastalPruning);
                Assert.Equal(RouteCoastalPruningMode.Off, leg.Route.RunAudit.Resolved.CoastalPruning);
                Assert.Null(leg.Route.RunAudit.Native!.CoastalPruning);
                Assert.True(leg.Route.RunAudit.Native.CoastalSeedActions.IsDefault);
            }
        }
        await repository.SaveAsync(loaded);
        var backup = Assert.Single(Directory.EnumerateFiles(Path.Combine(repository.RootDirectory, "backups"), "*.json"));
        Assert.Equal(original, await File.ReadAllBytesAsync(backup));
        var saved = JsonNode.Parse(await File.ReadAllTextAsync(path))!;
        Assert.Equal(7, saved["schemaVersion"]!.GetValue<int>());
        Assert.Null((await repository.OpenAsync(plan.Id)).Results[0].Legs[0].Route!.Diagnostics.CoastalPruning);
    }

    [Fact]
    public async Task Absent_optional_coastal_provenance_remains_unknown_after_round_trip()
    {
        using var directory = new TestDirectory();
        var repository = new RoutePlanJsonRepository(directory.Path);
        var plan = CreateAuditedPlan(directory.Path, CoastalAudit());
        await repository.SaveAsync(plan);
        var path = Path.Combine(repository.RootDirectory, $"{plan.Id}.route.json");
        var root = JsonNode.Parse(await File.ReadAllTextAsync(path))!;
        foreach (var leg in root["plan"]!["results"]![0]!["legs"]!.AsArray())
        {
            var route = leg!["route"]!;
            foreach (var audit in new[] { route["diagnostics"]!["coastalPruning"]!,
                         route["nativeAudit"]!["coastalPruning"]!, route["runAudit"]!["native"]!["coastalPruning"]! })
                foreach (var field in new[] { "sourceIdentity", "domainIdentity", "seedStatus", "speedUpperKnots",
                             "topologyCaps", "numericalMarginNauticalMiles", "clearanceNauticalMiles" })
                    audit.AsObject().Remove(field);
        }
        await File.WriteAllTextAsync(path, root.ToJsonString());
        var restored = await repository.OpenAsync(plan.Id);
        await repository.SaveAsync(restored);
        var coastal = (await repository.OpenAsync(plan.Id)).Results[0].Legs[0].Route!.Diagnostics.CoastalPruning!;
        Assert.Null(coastal.SourceIdentity);
        Assert.Null(coastal.DomainIdentity);
        Assert.Null(coastal.SeedStatus);
        Assert.Null(coastal.SpeedUpperKnots);
        Assert.Null(coastal.TopologyCaps);
        Assert.Null(coastal.NumericalMarginNauticalMiles);
        Assert.Null(coastal.ClearanceNauticalMiles);
    }

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public async Task Coastal_seed_audit_preserves_unknown_versus_recorded_empty(bool recorded)
    {
        using var directory = new TestDirectory();
        var repository = new RoutePlanJsonRepository(directory.Path);
        var plan = CreateAuditedPlan(directory.Path, CoastalAudit());
        await repository.SaveAsync(plan);
        var path = Path.Combine(repository.RootDirectory, $"{plan.Id}.route.json");
        var root = JsonNode.Parse(await File.ReadAllTextAsync(path))!;
        foreach (var leg in root["plan"]!["results"]![0]!["legs"]!.AsArray())
        {
            var route = leg!["route"]!;
            route["nativeAudit"]!["coastalSeedActions"] = recorded ? new JsonArray() : null;
            route["runAudit"]!["native"]!["coastalSeedActions"] = recorded ? new JsonArray() : null;
        }
        await File.WriteAllTextAsync(path, root.ToJsonString());
        await repository.SaveAsync(await repository.OpenAsync(plan.Id));
        var audit = (await repository.OpenAsync(plan.Id)).Results[0].Legs[0].Route!.NativeAudit!;
        Assert.Equal(!recorded, audit.CoastalSeedActions.IsDefault);
        Assert.True(audit.CoastalSeedActions.IsDefaultOrEmpty);
    }

    [Theory]
    [InlineData("negative")]
    [InlineData("overflow")]
    [InlineData("fractional")]
    [InlineData("missing-counter")]
    [InlineData("missing-mode")]
    [InlineData("unknown-mode")]
    [InlineData("empty-status")]
    [InlineData("conflicting-counter")]
    [InlineData("conflicting-resolved")]
    [InlineData("missing-setup-mode")]
    [InlineData("old-abi")]
    [InlineData("invalid-speed")]
    [InlineData("invalid-topology-caps")]
    [InlineData("invalid-margin")]
    [InlineData("invalid-clearance")]
    [InlineData("conflicting-source")]
    [InlineData("invalid-seed-duration")]
    [InlineData("missing-seed-heading")]
    [InlineData("null-seed-action")]
    [InlineData("conflicting-seed-action")]
    [InlineData("missing-all-coastal-audit")]
    public async Task Corrupted_coastal_audit_or_settings_cannot_silently_become_zero_or_off(string corruption)
    {
        using var directory = new TestDirectory();
        var repository = new RoutePlanJsonRepository(directory.Path);
        var plan = CreateAuditedPlan(directory.Path, CoastalAudit());
        await repository.SaveAsync(plan);
        var path = Path.Combine(repository.RootDirectory, $"{plan.Id}.route.json");
        var root = JsonNode.Parse(await File.ReadAllTextAsync(path))!;
        var route = root["plan"]!["results"]![0]!["legs"]![0]!["route"]!;
        var coastal = route["diagnostics"]!["coastalPruning"]!.AsObject();
        switch (corruption)
        {
            case "negative": coastal["seedEvaluations"] = -1; break;
            case "overflow": coastal["skippedParents"] = JsonNode.Parse("9223372036854775808"); break;
            case "fractional": coastal["topologyWork"] = 1.5; break;
            case "missing-counter": coastal.Remove("horizonCandidates"); break;
            case "missing-mode": coastal.Remove("mode"); break;
            case "unknown-mode": coastal["mode"] = 900; break;
            case "empty-status": coastal["status"] = ""; break;
            case "conflicting-counter": coastal["disconnectedCandidates"] = 99; break;
            case "conflicting-resolved": route["runAudit"]!["resolved"]!["coastalPruning"] = "Off"; break;
            case "missing-setup-mode": root["plan"]!["setup"]!.AsObject().Remove("coastalPruning"); break;
            case "old-abi": route["runAudit"]!["nativeIdentity"]!["bridgeAbiVersion"] = 8; break;
            case "invalid-speed": coastal["speedUpperKnots"] = 0; break;
            case "invalid-topology-caps": coastal["topologyCaps"] = -1; break;
            case "invalid-margin": coastal["numericalMarginNauticalMiles"] = -0.1; break;
            case "invalid-clearance": coastal["clearanceNauticalMiles"] = -0.1; break;
            case "conflicting-source": coastal["sourceIdentity"] = "different-source"; break;
            case "invalid-seed-duration": route["nativeAudit"]!["coastalSeedActions"]![0]!["durationTicks"] = -1; break;
            case "missing-seed-heading": route["nativeAudit"]!["coastalSeedActions"]![0]!.AsObject().Remove("headingDegrees"); break;
            case "null-seed-action": route["nativeAudit"]!["coastalSeedActions"]![0] = null; break;
            case "conflicting-seed-action": route["nativeAudit"]!["coastalSeedActions"]![0]!["headingDegrees"] = 12; break;
            case "missing-all-coastal-audit":
                route["diagnostics"]!["coastalPruning"] = null;
                route["nativeAudit"]!["coastalPruning"] = null;
                route["runAudit"]!["native"]!["coastalPruning"] = null;
                break;
        }
        await File.WriteAllTextAsync(path, root.ToJsonString());
        await Assert.ThrowsAsync<RoutePlanRepositoryException>(async () => await repository.OpenAsync(plan.Id));
    }

    [Fact]
    public async Task Failed_solver_attempts_round_trip_from_workflow_and_survive_copy_without_geometry()
    {
        using var directory = new TestDirectory();
        var repository = new RoutePlanJsonRepository(directory.Path);
        var plan = await CalculateFailedPlanAsync(repository, directory.Path);
        var original = plan.LatestResult(ForecastModel.NoaaGfs)!.Legs[0];
        var loaded = await repository.OpenAsync(plan.Id);
        var restored = loaded.LatestResult(ForecastModel.NoaaGfs)!.Legs[0];
        var copy = await repository.SaveAsAsync(loaded, "Copied unsuccessful calculation");
        var copied = (await repository.OpenAsync(copy.Id)).LatestResult(ForecastModel.NoaaGfs)!.Legs[0];

        Assert.Equal(RouteLegOutcomeState.Failed, original.State);
        Assert.NotNull(original.Failure);
        Assert.Equal(2, original.Failure.Attempts.Length);
        Assert.Equal(RouteSolver.TimeDependentLattice, original.Failure.Attempts[0].Solver);
        Assert.Equal(RouteSolver.IsochroneBeam, original.Failure.Attempts[1].Solver);
        Assert.Equal(RoutingFailureKind.RecoverableSolver, original.Failure.Attempts[0].FailureKind);
        Assert.Equal(RoutingFailureKind.ResourceLimit, original.Failure.Attempts[1].FailureKind);
        foreach (var leg in new[] { restored, copied })
        {
            Assert.Null(leg.Route);
            Assert.Equal(original.ExecutionSession, leg.ExecutionSession);
            Assert.Equal(original.Failure.Kind, leg.Failure!.Kind);
            Assert.Equal(original.Failure.Code, leg.Failure.Code);
            Assert.Equal(original.Failure.Message, leg.Failure.Message);
            Assert.Equal(original.Failure.Attempts.ToArray(), leg.Failure.Attempts.ToArray());
            Assert.Contains("Disconnected lattice", leg.Detail);
            Assert.Contains("Beam resource limit", leg.Detail);
        }
    }

    [Theory]
    [InlineData("missing-attempts")]
    [InlineData("duplicate-attempt")]
    [InlineData("unknown-kind")]
    [InlineData("empty-code")]
    public async Task Malformed_failed_attempt_audit_is_rejected(string corruption)
    {
        using var directory = new TestDirectory();
        var repository = new RoutePlanJsonRepository(directory.Path);
        var plan = await CalculateFailedPlanAsync(repository, directory.Path);
        var path = Path.Combine(repository.RootDirectory, $"{plan.Id}.route.json");
        var root = JsonNode.Parse(await File.ReadAllTextAsync(path))!;
        var failure = root["plan"]!["results"]![0]!["legs"]![0]!["failure"]!;
        switch (corruption)
        {
            case "missing-attempts":
                failure.AsObject().Remove("attempts");
                break;
            case "duplicate-attempt":
                failure["attempts"]![1]!["attemptId"] = failure["attempts"]![0]!["attemptId"]!.DeepClone();
                break;
            case "unknown-kind":
                failure["kind"] = "UnrecognizedFailure";
                break;
            case "empty-code":
                failure["code"] = "";
                break;
        }
        await File.WriteAllTextAsync(path, root.ToJsonString());

        await Assert.ThrowsAsync<RoutePlanRepositoryException>(async () => await repository.OpenAsync(plan.Id));
    }

    [Fact]
    public async Task Legacy_failed_legs_do_not_gain_reconstructed_attempt_audit()
    {
        using var directory = new TestDirectory();
        var repository = new RoutePlanJsonRepository(directory.Path);
        var plan = await CalculateFailedPlanAsync(repository, directory.Path);
        var path = Path.Combine(repository.RootDirectory, $"{plan.Id}.route.json");
        var root = JsonNode.Parse(await File.ReadAllTextAsync(path))!;
        root["schemaVersion"] = 5;
        root["plan"]!["results"]![0]!["legs"]![0]!["reason"] = nameof(RouteLegOutcomeReason.RouteCalculationFailed);
        await File.WriteAllTextAsync(path, root.ToJsonString());

        var restored = (await repository.OpenAsync(plan.Id)).LatestResult(ForecastModel.NoaaGfs)!.Legs[0];

        Assert.Null(restored.Failure);
        Assert.Null(restored.Route);
        Assert.Equal(RouteLegOutcomeState.Failed, restored.State);
    }

    private static async Task<RoutePlan> CalculateFailedPlanAsync(RoutePlanJsonRepository repository, string directory)
    {
        var plan = CreatePlan();
        plan = plan.UnmarkSailed(plan.Legs[0].Id);
        var departure = DateTimeOffset.UtcNow;
        var workflow = new RoutePlanRoutingWorkflow(
            new RoutingWorkflow([new FailureForecastSource(directory)], new FailedSolvers()), repository);
        var result = await workflow.ExecuteAsync(new RoutePlanRoutingRequest(
            plan, departure, departure.AddDays(1), [ForecastSelection.OfficialDownload(ForecastModel.NoaaGfs)],
            optimization: new RouteOptimizationOptions(solver: RouteSolver.TimeDependentLattice)));
        return result.Plan;
    }

    private sealed class FailureForecastSource(string directory) : IForecastProvider
    {
        public ForecastProvider Provider => ForecastProvider.Noaa;
        public ForecastModel Model => ForecastModel.NoaaGfs;
        public ValueTask<ForecastAcquisition> AcquireAsync(ForecastRequest request,
            IProgress<ForecastProgress>? progress, CancellationToken cancellationToken) =>
            ValueTask.FromResult(new ForecastAcquisition(request,
                new ForecastRun(Provider, Model, request.From.AddHours(-6)),
                new LocalGribArtifact(Path.Combine(directory, "fixture.grib")), ForecastAcquisitionSource.Remote));
    }

    private sealed class FailedSolvers : IRouteEngine
    {
        public ValueTask<RouteResult> CalculateAsync(RouteRequest request, ForecastAcquisition forecast,
            IProgress<RouteCalculationProgress>? progress, CancellationToken cancellationToken) =>
            throw new InvalidOperationException("Explicit solver settings are required.");

        public ValueTask<RouteResult> CalculateAsync(RouteRequest request, ForecastAcquisition forecast,
            RouteOptimizationOptions optimization, IProgress<RouteCalculationProgress>? progress, CancellationToken cancellationToken) =>
            throw (optimization.Solver == RouteSolver.TimeDependentLattice
                ? new RoutingException(RoutingFailureKind.RecoverableSolver, "Disconnected lattice")
                : new RoutingException(RoutingFailureKind.ResourceLimit, "Beam resource limit"));
    }

    [Fact]
    public async Task Schema_six_round_trips_setup_run_audit_causal_holds_and_all_native_fields()
    {
        using var directory = new TestDirectory();
        var repository = new RoutePlanJsonRepository(directory.Path);
        var plan = CreateAuditedPlan(directory.Path);
        await repository.SaveAsync(plan);
        var path = Path.Combine(repository.RootDirectory, $"{plan.Id}.route.json");
        var originalJson = await File.ReadAllTextAsync(path);
        var loaded = await repository.OpenAsync(plan.Id);

        Assert.Equal(plan.RoutingSetup, loaded.RoutingSetup);
        Assert.Equal(plan.RoutingSetup!.RegionalLand, loaded.RoutingSetup!.RegionalLand);
        Assert.Equal("GSHHG source attribution preserved", loaded.RoutingSetup.RegionalLand!.Attribution);
        Assert.Equal(RouteMissingDataPolicy.RejectTransition, loaded.RoutingSetup.RegionalLand.MissingDataPolicy);
        Assert.Equal(BoatAssetKind.Imported, loaded.RoutingSetup.Boat.Kind);
        Assert.False(File.Exists(loaded.RoutingSetup.RegionalLand!.SourcePath));
        Assert.Equal(plan.Results[0].Legs[0].ExecutionSession, loaded.Results[0].Legs[0].ExecutionSession);
        Assert.NotEqual(loaded.Results[0].Session.Id, loaded.Results[0].Legs[0].ExecutionSession!.Id);
        Assert.Equal(plan.Results[0].Legs[0].PlannedHold, loaded.Results[0].Legs[0].PlannedHold);
        Assert.Equal(plan.Results[0].Legs[1].Origin, loaded.Results[0].Legs[1].Origin);
        var route = loaded.Results[0].Legs[0].Route!;
        Assert.Equal(3, route.Diagnostics.EligibilityEvaluations);
        Assert.Equal(1, route.Diagnostics.PrunedCandidates);
        Assert.Equal(0, route.Diagnostics.FutureProbeMisses);
        Assert.Equal(13, route.Points[^1].PolarWindSpeedKnots);
        Assert.Equal(170, route.Points[^1].Environment!.PolarWindDirectionDegrees);
        Assert.Equal("native warning", Assert.Single(route.NativeAudit!.Routing!.Warnings));
        Assert.Equal(2, route.RunAudit!.Attempts.Length);
        Assert.Equal(RoutingFailureKind.RecoverableSolver, route.RunAudit.Attempts[0].FailureKind);
        Assert.NotNull(route.RunAudit.ProfessionalOverrides);
        Assert.Null(route.RunAudit.Resolved.Optimization.Environment);
        Assert.Null(route.RunAudit.ProfessionalOverrides!.Optimization!.Environment);
        Assert.Equal(TimeSpan.FromHours(240), route.RunAudit.Resolved.HardDuration);
        Assert.Equal(3, route.RunAudit.Resolved.Search.Intervals.Length);
        Assert.Equal(new GeographicBounds(34, 41, -66, -51), route.RunAudit.Forecast!.DeclaredBounds);
        Assert.Equal(TimeSpan.FromHours(1), route.RunAudit.Forecast.MinimumTimeSpacing);
        Assert.Equal(TimeSpan.FromHours(3), route.RunAudit.Forecast.MaximumTimeSpacing);
        Assert.Equal(20, route.RunAudit.Forecast.ValidTimes.Length);
        Assert.Equal(route.RunAudit.Forecast.ValidTimes.ToArray(), route.NativeAudit.ForecastCoverage!.ValidTimes.ToArray());
        Assert.Equal(TimeSpan.FromHours(1), route.NativeAudit.ForecastCoverage.MinimumTimeSpacing);
        Assert.Equal(TimeSpan.FromHours(3), route.NativeAudit.ForecastCoverage.MaximumTimeSpacing);
        Assert.DoesNotContain("signedDistance", originalJson, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("polarBytes", originalJson, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("\"environment\"", JsonNode.Parse(originalJson)!["plan"]!["results"]![0]!["legs"]![0]!["route"]!["runAudit"]!.ToJsonString());

        await repository.SaveAsync(loaded);
        Assert.Equal(originalJson, await File.ReadAllTextAsync(path));
    }

    [Fact]
    public async Task Save_as_remaps_plan_scoped_predecessors_without_relabeling_sailed_executions()
    {
        using var directory = new TestDirectory();
        var repository = new RoutePlanJsonRepository(directory.Path);
        var original = CreateAuditedPlan(directory.Path);
        var copied = await repository.SaveAsAsync(original, "Copied continuous voyage");
        var loaded = await repository.OpenAsync(copied.Id);
        Assert.NotEqual(original.Id, loaded.Id);
        Assert.Equal(original.Legs.Where(leg => original.SailedLegIds.Contains(leg.Id)).Select(leg => leg.Index),
            loaded.Legs.Where(leg => loaded.SailedLegIds.Contains(leg.Id)).Select(leg => leg.Index));
        Assert.Equal(original.ActiveLegIndex, loaded.ActiveLegIndex);
        Assert.NotEqual(original.ActiveLegId, loaded.ActiveLegId);
        Assert.Equal(original.RoutingSetup, loaded.RoutingSetup);
        var sailed = loaded.Results[0].Legs[0];
        var next = loaded.Results[0].Legs[1];
        Assert.Equal(original.Results[0].Legs[0].ExecutionSession, sailed.ExecutionSession);
        Assert.Equal(original.Id, sailed.ExecutionSession!.PlanId);
        Assert.Equal(original.Results[0].Legs[0].Route!.RunAudit!.CalculationId, sailed.Route!.RunAudit!.CalculationId);
        Assert.Equal(copied.Id, next.Origin!.Predecessor!.PlanId);
        Assert.Equal(sailed.LegId, next.Origin.Predecessor.LegId);
        Assert.Equal(sailed.ExecutionSession.Id, next.Origin.Predecessor.SessionId);
        Assert.Equal(sailed.Route.Request.RouteId, next.Origin.Predecessor.RouteId);
        Assert.Equal(sailed.Route.Points[^1].Location, next.Route!.Request.Origin);
        Assert.Equal(sailed.PlannedHold!.Until, next.Route.Request.DepartureTime);
        Assert.NotEqual(original.Results[0].Session.Id, loaded.Results[0].Session.Id);
        Assert.Equal(original.Results[0].Session.StartedAt, loaded.Results[0].Session.StartedAt);
        Assert.Equal(original.Results[0].Session.CompletedAt, loaded.Results[0].Session.CompletedAt);
        Assert.DoesNotContain(loaded.Legs, leg => original.Legs.Any(old => old.Id == leg.Id));
    }

    [Fact]
    public async Task Version_five_history_remains_unconfigured_with_unknown_new_audit()
    {
        using var directory = new TestDirectory();
        var repository = new RoutePlanJsonRepository(directory.Path);
        var plan = WithResult(CreatePlan(), environment: true);
        await repository.SaveAsync(plan);
        var path = Path.Combine(repository.RootDirectory, $"{plan.Id}.route.json");
        var root = JsonNode.Parse(await File.ReadAllTextAsync(path))!;
        root["schemaVersion"] = 5;
        root["plan"]!.AsObject().Remove("setup");
        foreach (var leg in root["plan"]!["results"]![0]!["legs"]!.AsArray())
        {
            leg!.AsObject().Remove("executionSession");
            leg.AsObject().Remove("origin");
            leg.AsObject().Remove("plannedHold");
            leg["route"]!.AsObject().Remove("runAudit");
            leg["route"]!.AsObject().Remove("nativeAudit");
        }
        await File.WriteAllTextAsync(path, root.ToJsonString());
        var bytes = await File.ReadAllBytesAsync(path);
        var loaded = await repository.OpenAsync(plan.Id);
        Assert.Null(loaded.RoutingSetup);
        Assert.Equal(plan.SailedLegIds, loaded.SailedLegIds);
        Assert.Equal(plan.Results[0].Session.Id, loaded.Results[0].Legs[0].ExecutionSession!.Id);
        foreach (var leg in loaded.Results[0].Legs)
        {
            Assert.Null(leg.Origin);
            Assert.Null(leg.PlannedHold);
            Assert.Null(leg.Route!.RunAudit);
            Assert.Null(leg.Route.NativeAudit);
            Assert.Null(leg.Route.Diagnostics.EligibilityEvaluations);
            Assert.All(leg.Route.Points, point =>
            {
                Assert.Null(point.PolarWindSpeedKnots);
                Assert.NotNull(point.Environment);
                Assert.Null(point.Environment!.PolarWindSpeedKnots);
            });
        }
        Assert.Equal(bytes, await File.ReadAllBytesAsync(path));
        await repository.SaveAsync(loaded);
        Assert.Equal(bytes, await File.ReadAllBytesAsync(Assert.Single(Directory.GetFiles(
            Path.Combine(repository.RootDirectory, "backups"), "*.json"))));
    }

    [Theory]
    [InlineData("unknown-native-schema")]
    [InlineData("missing-native-field")]
    [InlineData("unknown-audit-field")]
    [InlineData("negative-counter")]
    [InlineData("contradictory-native-counter")]
    [InlineData("wrong-native-destination")]
    [InlineData("wrong-attempt-solver")]
    [InlineData("missing-execution")]
    [InlineData("missing-origin")]
    [InlineData("missing-regional-source")]
    [InlineData("wrong-predecessor-plan")]
    [InlineData("wrong-predecessor-session")]
    [InlineData("wrong-predecessor-model")]
    [InlineData("wrong-predecessor-route")]
    [InlineData("partial-predecessor")]
    [InlineData("conflicting-predecessor-hold")]
    [InlineData("wrong-handoff-position")]
    [InlineData("wrong-handoff-time")]
    [InlineData("invalid-search-budget")]
    [InlineData("invalid-routing-interval")]
    [InlineData("invalid-polar-audit")]
    [InlineData("future-build-abi")]
    [InlineData("invalid-forecast-spacing")]
    [InlineData("incomplete-forecast-spacing")]
    [InlineData("excessive-forecast-gap")]
    [InlineData("contradictory-forecast-validity")]
    [InlineData("duplicate-native-valid-time")]
    [InlineData("unordered-forecast-times")]
    [InlineData("contradictory-forecast-spacing")]
    [InlineData("missing-native-coverage-times")]
    [InlineData("unknown-regional-missing-policy")]
    [InlineData("missing-regional-attribution")]
    public async Task Schema_six_rejects_malformed_audit_and_forged_handoffs(string mutation)
    {
        using var directory = new TestDirectory();
        var repository = new RoutePlanJsonRepository(directory.Path);
        var plan = CreateAuditedPlan(directory.Path);
        await repository.SaveAsync(plan);
        var path = Path.Combine(repository.RootDirectory, $"{plan.Id}.route.json");
        var root = JsonNode.Parse(await File.ReadAllTextAsync(path))!;
        var first = root["plan"]!["results"]![0]!["legs"]![0]!;
        var second = root["plan"]!["results"]![0]!["legs"]![1]!;
        var route = first["route"]!;
        switch (mutation)
        {
            case "unknown-native-schema": route["nativeAudit"]!["schema"] = "route_result_v999"; break;
            case "missing-native-field": route["nativeAudit"]!["routing"]!.AsObject().Remove("boatSpeedFactor"); break;
            case "unknown-audit-field": route["runAudit"]!["unknownFuturePolicy"] = true; break;
            case "negative-counter": route["diagnostics"]!["eligibilityEvaluations"] = -1; break;
            case "contradictory-native-counter": route["nativeAudit"]!["eligibilityEvaluations"] = 999; break;
            case "wrong-native-destination": route["nativeAudit"]!["routing"]!["destinationLatitude"] = 0; break;
            case "wrong-attempt-solver": route["runAudit"]!["attempts"]![1]!["solver"] = "TimeDependentLattice"; break;
            case "missing-execution": first["executionSession"] = null; break;
            case "missing-origin": first["origin"] = null; break;
            case "missing-regional-source": root["plan"]!["setup"]!["regionalLand"] = null; break;
            case "wrong-predecessor-plan": second["origin"]!["predecessor"]!["planId"] = Guid.NewGuid(); break;
            case "wrong-predecessor-session": second["origin"]!["predecessor"]!["sessionId"] = Guid.NewGuid(); break;
            case "wrong-predecessor-model": second["origin"]!["predecessor"]!["model"] = "EcmwfIfs"; break;
            case "wrong-predecessor-route": second["origin"]!["predecessor"]!["routeId"] = "forged-route"; break;
            case "partial-predecessor":
                first["reason"] = "ForecastExhausted";
                first["route"]!["completion"] = "ForecastExhausted";
                first["plannedHold"] = null;
                break;
            case "conflicting-predecessor-hold":
                first["plannedHold"]!["status"] = "Conflict";
                first["plannedHold"]!["conflictZoneIdentifier"] = "activated-during-hold";
                break;
            case "wrong-handoff-position": second["route"]!["request"]!["originLatitude"] = 0; break;
            case "wrong-handoff-time": second["route"]!["request"]!["departureTime"] = DateTimeOffset.Parse("2026-08-03T00:00:00Z"); break;
            case "invalid-search-budget": route["runAudit"]!["resolved"]!["search"]!["maximumRetainedNodes"] = 0; break;
            case "invalid-routing-interval": route["runAudit"]!["resolved"]!["search"]!["intervals"]![0]!["untilElapsedTicks"] = -1; break;
            case "invalid-polar-audit": route["points"]![1]!["polarWindDirectionDegrees"] = 190; break;
            case "future-build-abi": route["runAudit"]!["nativeIdentity"]!["bridgeAbiVersion"] = 999; break;
            case "invalid-forecast-spacing": route["runAudit"]!["forecast"]!["minimumTimeSpacingTicks"] = -1; break;
            case "incomplete-forecast-spacing": route["runAudit"]!["forecast"]!["minimumTimeSpacingTicks"] = null; break;
            case "excessive-forecast-gap": route["runAudit"]!["forecast"]!["maximumTimeSpacingTicks"] = TimeSpan.FromHours(6).Ticks; break;
            case "contradictory-forecast-validity": route["runAudit"]!["forecast"]!["validThrough"] = DateTimeOffset.Parse("2026-08-03T12:00:00Z"); break;
            case "duplicate-native-valid-time":
                route["nativeAudit"]!["forecastCoverage"]!["validTimes"]![1] =
                    route["nativeAudit"]!["forecastCoverage"]!["validTimes"]![0]!.DeepClone();
                break;
            case "unordered-forecast-times":
                route["runAudit"]!["forecast"]!["validTimes"]![1] = DateTimeOffset.Parse("2026-08-01T01:00:00Z");
                break;
            case "contradictory-forecast-spacing": route["runAudit"]!["forecast"]!["minimumTimeSpacingTicks"] = TimeSpan.FromHours(2).Ticks; break;
            case "missing-native-coverage-times": route["nativeAudit"]!["forecastCoverage"]!["validTimes"] = new JsonArray(); break;
            case "unknown-regional-missing-policy": root["plan"]!["setup"]!["regionalLand"]!["missingDataPolicy"] = "SilentOpenWater"; break;
            case "missing-regional-attribution": root["plan"]!["setup"]!["regionalLand"]!.AsObject().Remove("attribution"); break;
        }
        await File.WriteAllTextAsync(path, root.ToJsonString());
        await Assert.ThrowsAsync<RoutePlanRepositoryException>(async () => await repository.OpenAsync(plan.Id));
    }

    [Fact]
    public async Task Absent_historical_forecast_spacing_stays_unknown_when_reopened_and_resaved()
    {
        using var directory = new TestDirectory();
        var repository = new RoutePlanJsonRepository(directory.Path);
        var plan = CreateAuditedPlan(directory.Path);
        await repository.SaveAsync(plan);
        var path = Path.Combine(repository.RootDirectory, $"{plan.Id}.route.json");
        var root = JsonNode.Parse(await File.ReadAllTextAsync(path))!;
        foreach (var leg in root["plan"]!["results"]![0]!["legs"]!.AsArray())
        {
            var forecast = leg!["route"]!["runAudit"]!["forecast"]!.AsObject();
            forecast.Remove("minimumTimeSpacingTicks");
            forecast.Remove("maximumTimeSpacingTicks");
        }
        await File.WriteAllTextAsync(path, root.ToJsonString());
        var loaded = await repository.OpenAsync(plan.Id);
        Assert.All(loaded.Results[0].Legs, leg =>
        {
            Assert.Null(leg.Route!.RunAudit!.Forecast!.MinimumTimeSpacing);
            Assert.Null(leg.Route.RunAudit.Forecast.MaximumTimeSpacing);
            Assert.Equal(TimeSpan.FromHours(3), leg.Route.RunAudit.Forecast.MaximumInterpolationGap);
        });
        await repository.SaveAsync(loaded);
        Assert.Null((await repository.OpenAsync(plan.Id)).Results[0].Legs[0].Route!.RunAudit!.Forecast!.MinimumTimeSpacing);
    }

    [Fact]
    public async Task Duplicate_known_audit_fields_are_rejected_instead_of_last_value_winning()
    {
        using var directory = new TestDirectory();
        var repository = new RoutePlanJsonRepository(directory.Path);
        var plan = CreateAuditedPlan(directory.Path);
        await repository.SaveAsync(plan);
        var path = Path.Combine(repository.RootDirectory, $"{plan.Id}.route.json");
        var json = await File.ReadAllTextAsync(path);
        json = json.Replace("\"schema\": \"route_result_v2\"",
            "\"schema\": \"route_result_v99\", \"schema\": \"route_result_v2\"", StringComparison.Ordinal);
        await File.WriteAllTextAsync(path, json);
        await Assert.ThrowsAsync<RoutePlanRepositoryException>(async () => await repository.OpenAsync(plan.Id));
    }

    [Fact]
    public async Task Conflict_hold_and_blocked_suffix_remain_distinct_from_native_route_points()
    {
        using var directory = new TestDirectory();
        var repository = new RoutePlanJsonRepository(directory.Path);
        var original = CreateAuditedPlan(directory.Path);
        var first = original.Results[0].Legs[0];
        var hold = first.PlannedHold!;
        first = first.WithPlannedHold(new(hold.Location, hold.From, hold.Until,
            RouteHoldCheckStatus.Conflict, "timed-restriction", "Following leg blocked"));
        var result = new RoutePlanResult(original.Results[0].Session,
            [first, new(original.Legs[1].Id, RouteLegOutcomeState.Blocked, RouteLegOutcomeReason.StopoverExclusionConflict)]);
        var plan = new RoutePlan(original.Id, original.Name, original.Waypoints, [result],
            original.SailedLegIds, routingSetup: original.RoutingSetup);
        await repository.SaveAsync(plan);
        var loaded = await repository.OpenAsync(plan.Id);
        Assert.Equal(RouteHoldCheckStatus.Conflict, loaded.Results[0].Legs[0].PlannedHold!.Status);
        Assert.Equal(2, loaded.Results[0].Legs[0].Route!.Points.Length);
        Assert.Equal(first.Route!.ArrivalTime, loaded.Results[0].Legs[0].Route!.Points[^1].Timestamp);
        Assert.Null(loaded.Results[0].Legs[1].Route);
    }

    private static RoutePlan CreateAuditedPlan(string root, RouteCoastalPruningDiagnostics? coastal = null)
    {
        var boat = new BoatAsset(new string('a', 64), "Imported cruising polar.csv", BoatAssetKind.Imported,
            BoatPolarFormat.NativeMatrix, new("Native validation accepted", MaximumWindSpeedKnots: 50), 35);
        var regional = new RouteRegionalLandPolicy(Path.Combine(root, "missing-but-viewable.b"),
            new string('b', 64), new GeographicBounds(34, 41, -66, -51), 20, .25, 120,
            250000, 10000000, 100000000, attribution: "GSHHG source attribution preserved",
            missingDataPolicy: RouteMissingDataPolicy.RejectTransition);
        var setup = new RoutingSetup(boat, RoutingQuality.NativeAccurate, .85, 1,
            RoutingLandSource.RegionalGshhg, hardDuration: TimeSpan.FromHours(240),
            localForecastMaximumGap: TimeSpan.FromHours(3), regionalLand: regional,
            coastalPruning: coastal?.Mode ?? RouteCoastalPruningMode.Off);
        var basePlan = CreatePlan();
        var plan = new RoutePlan(basePlan.Id, basePlan.Name, basePlan.Waypoints, sailedLegIds: basePlan.SailedLegIds,
            activeLegId: basePlan.Legs[1].Id, routingSetup: setup);
        var date = DateTimeOffset.Parse("2026-08-01T18:00:00Z");
        var execution = new RouteCalculationSession(plan.Id, ForecastModel.NoaaGfs, date).Complete(date.AddSeconds(2));
        var outer = new RouteCalculationSession(plan.Id, ForecastModel.NoaaGfs, date.AddDays(1)).Complete(date.AddDays(1).AddSeconds(2));
        var search = new RouteSearchSettings(TimeSpan.FromMinutes(15), TimeSpan.FromMinutes(5),
            5, 1, 20, 1, 5000000, 500000, 2, true, true, false, 1, .05,
            [new(TimeSpan.FromMinutes(15), TimeSpan.FromHours(4)),
             new(TimeSpan.FromMinutes(30), TimeSpan.FromHours(24)), new(TimeSpan.FromHours(1))]);
        var optimization = new RouteOptimizationOptions(maneuver: new(TimeSpan.FromSeconds(40), TimeSpan.FromSeconds(30)),
            maximumTrueWindSpeedKnots: 40, destinationFront: new(90, RouteDestinationFrontSegmentPolicy.AllMeaningfulComponents, 4));
        var resolved = new ResolvedRoutingOptions(setup.Quality, optimization, search, .85, 1, TimeSpan.FromHours(240), setup.CoastalPruning);
        var build = new NativeRoutingIdentity(coastal is null ? 8 : 9, "0.6.0",
            "cd476a84ef3edea9582d77f21588a23af727e083", "fetched-clean", 8191);
        var validTimes = new[] { date.AddHours(-6), date.AddHours(-5) }
            .Concat(Enumerable.Range(1, 18).Select(index => date.AddHours(-6 + index * 3)))
            .ToImmutableArray();
        var coverage = new ForecastCoverage(new GeographicBounds(34, 41, -66, -51), validTimes, TimeSpan.FromHours(3));
        var legs = new List<RouteLegResult>();
        foreach (var leg in plan.Legs)
        {
            var previous = legs.LastOrDefault();
            var origin = previous?.Route?.Points[^1].Location ?? plan.Waypoints[0].Coordinate;
            var departure = previous?.PlannedHold?.Until ?? date;
            var destination = plan.Waypoints[leg.Index + 1].Coordinate;
            var endpoint = new Coordinate(destination.Latitude + .002, destination.Longitude);
            var request = new RouteRequest($"audit-leg-{leg.Index}", origin, destination, departure, departure.AddDays(1));
            var routing = new RouteNativeRunMetadata("earliest_arrival", "best_found", RouteSolver.IsochroneBeam,
                destination, 1, .12, .85, 5, 1, TimeSpan.FromMinutes(5), true, true,
                RouteWindSampling.Midpoint, RouteAbovePolarRangePolicy.NoSpeed, 40, TimeSpan.FromSeconds(40),
                TimeSpan.FromSeconds(30), date.AddHours(-6), date.AddHours(-6), date.AddDays(2), ["native warning"]);
            var native = new RouteNativeRunAudit("route_result_v2", RouteSolver.IsochroneBeam, 1, TimeSpan.FromHours(240),
                true, 3, 1, 0, routing, "forecast-source", "explicit-polar-source", "explicit_time", coverage, coastal,
                coastal is null ? default :
                    [new(270, TimeSpan.FromMinutes(15)), new(275, TimeSpan.FromSeconds(901))]);
            var audit = new RouteRunAudit(Guid.NewGuid(), setup, resolved, build,
                coastal is null ? RouteSolver.TimeDependentLattice : RouteSolver.IsochroneBeam,
                coastal is null
                ? [new(Guid.NewGuid(), RouteSolver.TimeDependentLattice, date, date.AddSeconds(1), RoutingFailureKind.RecoverableSolver, "disconnected"),
                 new(Guid.NewGuid(), RouteSolver.IsochroneBeam, date.AddSeconds(1), date.AddSeconds(2))]
                : [new(Guid.NewGuid(), RouteSolver.IsochroneBeam, date, date.AddSeconds(2))],
                new(new(ForecastProvider.Noaa, ForecastModel.NoaaGfs, date.AddHours(-6)),
                    new GeographicBounds(34, 41, -66, -51), new GeographicBounds(34, 41, -66, -51),
                    date.AddHours(-6), date.AddDays(2), TimeSpan.FromHours(3),
                    TimeSpan.FromHours(1), TimeSpan.FromHours(3), validTimes),
                native, new(optimization, search), new(LandAvoidanceStatus.Applied, Attribution: "GSHHG"));
            var environment = new RoutePointEnvironment(7, 95, 6, 1, -.4, 1.5, 8, 180, 13, 170);
            var route = new RouteResult(request, ForecastModel.NoaaGfs,
                [new(origin, departure, 90, 6, 15, 180, 0, environment, 13, 170),
                 new(endpoint, departure.AddHours(1), 90, 6, 15, 180, 50, environment, 13, 170)],
                new RouteDiagnostics(1, 2, 1, 1, TimeSpan.FromSeconds(2), 3, 1, 0, coastal),
                RouteCompletion.DestinationReached, new(LandAvoidanceStatus.Applied, Attribution: "GSHHG"),
                RouteSolver.IsochroneBeam, null, null, null, audit, native);
            var hold = leg.Index == 0 ? new RoutePlannedHold(endpoint, route.ArrivalTime,
                route.ArrivalTime.AddHours(4), RouteHoldCheckStatus.Clear, detail: "Native interval exclusions clear") : null;
            var provenance = previous is null ? new RouteLegOrigin(RouteLegOriginSource.DeclaredWaypoint) :
                new(RouteLegOriginSource.AcceptedPredecessor, new(plan.Id, previous.LegId, ForecastModel.NoaaGfs,
                    previous.ExecutionSession!.Id, previous.Route!.Request.RouteId));
            legs.Add(new(leg.Id, RouteLegOutcomeState.Succeeded, RouteLegOutcomeReason.CalculationSucceeded,
                route, executionSession: execution, origin: provenance, plannedHold: hold));
        }
        return new(plan.Id, plan.Name, plan.Waypoints, [new(outer, legs)], plan.SailedLegIds,
            activeLegId: plan.ActiveLegId, routingSetup: setup);
    }

    [Fact]
    public async Task Round_trip_list_save_as_and_delete_preserve_plan_data()
    {
        using var directory = new TestDirectory();
        var repository = new RoutePlanJsonRepository(directory.Path);
        var plan = WithResult(CreatePlan());

        await repository.SaveAsync(plan);
        var loaded = await repository.OpenAsync(plan.Id);
        var copy = await repository.SaveAsAsync(loaded, "Return passage");
        var summaries = await repository.ListAsync();

        Assert.Equal(plan.Id, loaded.Id);
        Assert.Equal(plan.Waypoints.Length, loaded.Waypoints.Length);
        for (var index = 0; index < plan.Waypoints.Length; index++)
        {
            Assert.Equal(plan.Waypoints[index].Id, loaded.Waypoints[index].Id);
            Assert.Equal(plan.Waypoints[index].Name, loaded.Waypoints[index].Name);
            Assert.Equal(plan.Waypoints[index].Coordinate, loaded.Waypoints[index].Coordinate);
            Assert.Equal(plan.Waypoints[index].Stopover, loaded.Waypoints[index].Stopover);
        }

        Assert.Equal(plan.SailedLegIds, loaded.SailedLegIds);
        Assert.Single(loaded.Results);
        var expectedRoute = plan.Results[0].Legs[0].Route!;
        var loadedRoute = loaded.Results[0].Legs[0].Route!;
        Assert.Equal(expectedRoute.Request.RouteId, loadedRoute.Request.RouteId);
        Assert.Equal(expectedRoute.Request.Origin, loadedRoute.Request.Origin);
        Assert.Equal(expectedRoute.Request.Destination, loadedRoute.Request.Destination);
        Assert.Equal(expectedRoute.Points.Length, loadedRoute.Points.Length);
        Assert.Equal(
            expectedRoute.Points.Select(point => point.Location),
            loadedRoute.Points.Select(point => point.Location));
        Assert.Equal(expectedRoute.Diagnostics.CalculationDuration, loadedRoute.Diagnostics.CalculationDuration);
        Assert.Equal(expectedRoute.Solver, loadedRoute.Solver);
        Assert.Equal(expectedRoute.LatticeDiagnostics, loadedRoute.LatticeDiagnostics);
        Assert.NotEqual(plan.Id, copy.Id);
        Assert.Equal("Return passage", copy.Name);
        Assert.Equal(expectedRoute.Solver, copy.Results[0].Legs[0].Route!.Solver);
        Assert.Equal(2, summaries.Length);
        Assert.Empty(Directory.EnumerateFiles(repository.RootDirectory, "*.tmp"));

        await repository.DeleteAsync(plan.Id);
        Assert.Single(await repository.ListAsync());
        await Assert.ThrowsAsync<RoutePlanRepositoryException>(async () =>
            await repository.OpenAsync(plan.Id));
    }

    [Fact]
    public async Task Save_as_preserves_explicit_active_leg_and_current_position()
    {
        using var directory = new TestDirectory();
        var repository = new RoutePlanJsonRepository(directory.Path);
        var plan = CreatePlan();
        plan = plan.SetActiveLeg(plan.Legs[^1].Id)
            .SetCurrentPosition(new Coordinate(14, 24), DateTimeOffset.Parse("2026-08-01T12:00:00Z"));

        var copy = await repository.SaveAsAsync(plan, "Copy with observed start");
        var loaded = await repository.OpenAsync(copy.Id);

        Assert.NotEqual(plan.Id, copy.Id);
        Assert.Equal(plan.ActiveLegIndex, loaded.ActiveLegIndex);
        Assert.NotEqual(plan.ActiveLegId, loaded.ActiveLegId);
        Assert.Equal(plan.CurrentPosition, loaded.CurrentPosition);
        Assert.Equal(plan.Waypoints.Select(point => (point.Name, point.Coordinate, point.Stopover)),
            loaded.Waypoints.Select(point => (point.Name, point.Coordinate, point.Stopover)));
        Assert.DoesNotContain(loaded.Waypoints, point => plan.Waypoints.Any(old => old.Id == point.Id));
    }

    [Fact]
    public async Task Duration_limited_completion_and_reason_round_trip()
    {
        using var directory = new TestDirectory();
        var repository = new RoutePlanJsonRepository(directory.Path);
        var plan = WithResult(CreatePlan(), completion: RouteCompletion.DurationExhausted);

        await repository.SaveAsync(plan);
        var loaded = await repository.OpenAsync(plan.Id);

        var leg = loaded.Results[0].Legs[0];
        Assert.Equal(RouteLegOutcomeReason.DurationExhausted, leg.Reason);
        Assert.Equal(RouteCompletion.DurationExhausted, leg.Route!.Completion);
        Assert.True(leg.Route.IsDurationLimited);
    }

    [Fact]
    public async Task Future_and_malformed_schemas_fail_visibly()
    {
        using var directory = new TestDirectory();
        var repository = new RoutePlanJsonRepository(directory.Path);
        var futureId = new RoutePlanId();
        var malformedId = new RoutePlanId();
        await File.WriteAllTextAsync(
            Path.Combine(repository.RootDirectory, $"{futureId}.route.json"),
            """{"schemaVersion":999,"plan":{}}""");
        await File.WriteAllTextAsync(
            Path.Combine(repository.RootDirectory, $"{malformedId}.route.json"),
            """{"schemaVersion":1,"plan":{"id":"00000000-0000-0000-0000-000000000000"}}""");

        var future = await Assert.ThrowsAsync<RoutePlanRepositoryException>(async () =>
            await repository.OpenAsync(futureId));
        Assert.Contains("future schema version", future.Message);

        var malformed = await Assert.ThrowsAsync<RoutePlanRepositoryException>(async () =>
            await repository.OpenAsync(malformedId));
        Assert.Contains("failed", malformed.Message);
        await Assert.ThrowsAsync<RoutePlanRepositoryException>(async () =>
            await repository.ListAsync());
    }

    [Fact]
    public async Task Missing_required_fields_and_numeric_enums_are_rejected()
    {
        using var directory = new TestDirectory();
        var repository = new RoutePlanJsonRepository(directory.Path);
        var missingId = new RoutePlanId();
        var numericId = new RoutePlanId();
        await File.WriteAllTextAsync(
            Path.Combine(repository.RootDirectory, $"{missingId}.route.json"),
            """{"schemaVersion":1,"plan":{"id":"11111111-1111-1111-1111-111111111111"}}""");
        await File.WriteAllTextAsync(
            Path.Combine(repository.RootDirectory, $"{numericId}.route.json"),
            """
            {"schemaVersion":1,"plan":{"id":"22222222-2222-2222-2222-222222222222","name":"bad",
            "waypoints":[],"results":[{"session":{"id":"33333333-3333-3333-3333-333333333333",
            "planId":"22222222-2222-2222-2222-222222222222","model":0,
            "startedAt":"2026-08-01T00:00:00Z","completedAt":null},"legs":[]}],"sailedLegIds":[]}}
            """);

        await Assert.ThrowsAsync<RoutePlanRepositoryException>(async () =>
            await repository.OpenAsync(missingId));
        await Assert.ThrowsAsync<RoutePlanRepositoryException>(async () =>
            await repository.OpenAsync(numericId));
    }

    [Fact]
    public async Task Duplicate_and_unknown_references_are_rejected_on_load()
    {
        using var directory = new TestDirectory();
        var repository = new RoutePlanJsonRepository(directory.Path);
        var plan = CreatePlan();
        await repository.SaveAsync(plan);
        var path = Path.Combine(repository.RootDirectory, $"{plan.Id}.route.json");
        using var document = JsonDocument.Parse(await File.ReadAllTextAsync(path));
        var json = document.RootElement.GetRawText()
            .Replace(
                plan.Waypoints[1].Id.Value.ToString(),
                plan.Waypoints[0].Id.Value.ToString(),
                StringComparison.OrdinalIgnoreCase);
        await File.WriteAllTextAsync(path, json);

        var exception = await Assert.ThrowsAsync<RoutePlanRepositoryException>(async () =>
            await repository.OpenAsync(plan.Id));
        Assert.Contains("duplicate waypoint", exception.Message, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task Open_rejects_document_id_that_disagrees_with_requested_file()
    {
        using var directory = new TestDirectory();
        var repository = new RoutePlanJsonRepository(directory.Path);
        var plan = CreatePlan();
        await repository.SaveAsync(plan);
        var otherId = new RoutePlanId();
        var originalPath = Path.Combine(repository.RootDirectory, $"{plan.Id}.route.json");
        var mismatchedPath = Path.Combine(repository.RootDirectory, $"{otherId}.route.json");
        File.Move(originalPath, mismatchedPath);

        var exception = await Assert.ThrowsAsync<RoutePlanRepositoryException>(async () =>
            await repository.OpenAsync(otherId));

        Assert.Contains("instead of", exception.Message);
        await Assert.ThrowsAsync<RoutePlanRepositoryException>(async () =>
            await repository.ListAsync());
    }

    [Fact]
    public async Task Cancelled_overwrite_keeps_previous_complete_document()
    {
        using var directory = new TestDirectory();
        var repository = new RoutePlanJsonRepository(directory.Path);
        var plan = CreatePlan();
        await repository.SaveAsync(plan);
        using var cancellation = new CancellationTokenSource();
        cancellation.Cancel();

        await Assert.ThrowsAnyAsync<OperationCanceledException>(async () =>
            await repository.SaveAsync(plan.Rename("Should not persist"), cancellation.Token));

        var loaded = await repository.OpenAsync(plan.Id);
        Assert.Equal(plan.Name, loaded.Name);
        Assert.Empty(Directory.EnumerateFiles(repository.RootDirectory, "*.tmp"));
    }

    [Fact]
    public async Task Migrated_overwrite_preserves_exact_original_once_without_listing_backup()
    {
        using var directory = new TestDirectory();
        var repository = new RoutePlanJsonRepository(directory.Path);
        var plan = WithResult(CreatePlan());
        await repository.SaveAsync(plan);
        var path = Path.Combine(repository.RootDirectory, $"{plan.Id}.route.json");
        var root = System.Text.Json.Nodes.JsonNode.Parse(await File.ReadAllTextAsync(path))!;
        root["schemaVersion"] = RoutePlanJsonRepository.CurrentSchemaVersion - 1;
        await File.WriteAllTextAsync(path, root.ToJsonString());
        var original = await File.ReadAllBytesAsync(path);

        var migrated = await repository.OpenAsync(plan.Id);
        Assert.Equal(original, await File.ReadAllBytesAsync(path));
        await repository.SaveAsync(migrated);
        var backup = Assert.Single(Directory.EnumerateFiles(
            Path.Combine(repository.RootDirectory, "backups"), "*.json"));
        Assert.Equal(original, await File.ReadAllBytesAsync(backup));
        await repository.SaveAsync(migrated.Rename("Updated"));

        Assert.Single(Directory.EnumerateFiles(Path.GetDirectoryName(backup)!, "*.json"));
        Assert.Equal(original, await File.ReadAllBytesAsync(backup));
        Assert.Single(await repository.ListAsync());
        Assert.Empty(Directory.EnumerateFiles(repository.RootDirectory, "*.tmp", SearchOption.AllDirectories));
    }

    [Fact]
    public async Task Failed_migration_backup_does_not_replace_original()
    {
        using var directory = new TestDirectory();
        var repository = new RoutePlanJsonRepository(directory.Path);
        var plan = CreatePlan();
        await repository.SaveAsync(plan);
        var path = Path.Combine(repository.RootDirectory, $"{plan.Id}.route.json");
        var root = System.Text.Json.Nodes.JsonNode.Parse(await File.ReadAllTextAsync(path))!;
        root["schemaVersion"] = RoutePlanJsonRepository.CurrentSchemaVersion - 1;
        await File.WriteAllTextAsync(path, root.ToJsonString());
        var original = await File.ReadAllBytesAsync(path);
        await File.WriteAllTextAsync(Path.Combine(repository.RootDirectory, "backups"), "not a directory");

        await Assert.ThrowsAsync<RoutePlanRepositoryException>(async () =>
            await repository.SaveAsync(plan.Rename("Must not replace")));

        Assert.Equal(original, await File.ReadAllBytesAsync(path));
        Assert.Empty(Directory.EnumerateFiles(repository.RootDirectory, "*.tmp"));
    }

    [Fact]
    public async Task Version_one_documents_are_migrated_with_null_current_position_and_active_leg()
    {
        using var directory = new TestDirectory();
        var repository = new RoutePlanJsonRepository(directory.Path);
        var id = new RoutePlanId();
        var json = """
            {"schemaVersion":1,"plan":{"id":"__ID__","name":"Legacy",
            "waypoints":[{"id":"11111111-1111-1111-1111-111111111111","name":"Start",
            "latitude":10,"longitude":20,"stopoverTicks":null},
            {"id":"22222222-2222-2222-2222-222222222222","name":"Finish",
            "latitude":11,"longitude":21,"stopoverTicks":null}],
            "results":[],"sailedLegIds":[]}}
            """.Replace("__ID__", id.Value.ToString());
        await File.WriteAllTextAsync(
            Path.Combine(repository.RootDirectory, $"{id}.route.json"),
            json);

        var loaded = await repository.OpenAsync(id);

        Assert.Equal("Legacy", loaded.Name);
        Assert.Null(loaded.CurrentPosition);
        Assert.Null(loaded.ActiveLegId);
        Assert.Equal(0, loaded.ActiveLegIndex);
    }

    [Fact]
    public async Task Version_two_results_are_migrated_to_beam_attribution()
    {
        using var directory = new TestDirectory();
        var repository = new RoutePlanJsonRepository(directory.Path);
        var plan = WithResult(CreatePlan());
        await repository.SaveAsync(plan);
        var path = Path.Combine(repository.RootDirectory, $"{plan.Id}.route.json");
        var root = System.Text.Json.Nodes.JsonNode.Parse(await File.ReadAllTextAsync(path))!;
        root["schemaVersion"] = 2;
        foreach (var result in root["plan"]!["results"]!.AsArray())
        {
            foreach (var leg in result!["legs"]!.AsArray())
            {
                leg!["route"]!.AsObject().Remove("solver");
                leg["route"]!.AsObject().Remove("latticeDiagnostics");
            }
        }

        await File.WriteAllTextAsync(path, root.ToJsonString());

        var loaded = await repository.OpenAsync(plan.Id);

        Assert.All(
            loaded.Results.SelectMany(result => result.Legs),
            leg =>
            {
                Assert.Equal(RouteSolver.IsochroneBeam, leg.Route!.Solver);
                Assert.Null(leg.Route.LatticeDiagnostics);
            });
    }

    [Fact]
    public async Task Lattice_solver_and_diagnostics_round_trip()
    {
        using var directory = new TestDirectory();
        var repository = new RoutePlanJsonRepository(directory.Path);
        var diagnostics = new RouteLatticeDiagnostics(100, 20, 300, 4, 2, 1, 3, true);
        var plan = WithResult(CreatePlan(), RouteSolver.TimeDependentLattice, diagnostics);

        await repository.SaveAsync(plan);
        var loaded = await repository.OpenAsync(plan.Id);

        Assert.All(
            loaded.Results.SelectMany(result => result.Legs),
            leg =>
            {
                Assert.Equal(RouteSolver.TimeDependentLattice, leg.Route!.Solver);
                Assert.Equal(diagnostics, leg.Route.LatticeDiagnostics);
            });
    }

    [Fact]
    public async Task Lattice_stage25_diagnostics_round_trip()
    {
        using var directory = new TestDirectory();
        var repository = new RoutePlanJsonRepository(directory.Path);
        var diagnostics = new RouteLatticeDiagnostics(
            settledLabels: 200,
            queuedLabels: 40,
            relaxedLabels: 600,
            waitTransitions: 8,
            refinementRuns: 3,
            acceptedRefinements: 2,
            subdivisionLevel: 8,
            refinementFallback: true,
            reRelaxedLabels: 15,
            staleQueueEntries: 5,
            activeCells: 12,
            activeFaces: 24,
            acceptedCorridorWidthNauticalMiles: 450.0,
            disconnectedRefinements: 1,
            regressedRefinements: 1,
            fallbackReason: LatticeRefinementFallbackReason.Disconnected);
        var plan = WithResult(CreatePlan(), RouteSolver.TimeDependentLattice, diagnostics);

        await repository.SaveAsync(plan);
        var loaded = await repository.OpenAsync(plan.Id);

        Assert.All(
            loaded.Results.SelectMany(result => result.Legs),
            leg =>
            {
                Assert.Equal(RouteSolver.TimeDependentLattice, leg.Route!.Solver);
                Assert.Equal(diagnostics, leg.Route.LatticeDiagnostics);
            });
    }

    [Fact]
    public async Task Current_position_and_active_leg_round_trip_through_save_and_open()
    {
        using var directory = new TestDirectory();
        var repository = new RoutePlanJsonRepository(directory.Path);
        var plan = CreatePlan();
        var activeLegId = plan.Legs[1].Id;
        var withActiveLeg = plan.SetActiveLeg(activeLegId);
        var departure = new DateTimeOffset(2026, 8, 2, 6, 0, 0, TimeSpan.Zero);
        var withCurrentPosition = withActiveLeg.SetCurrentPosition(new Coordinate(36, -62), departure);

        await repository.SaveAsync(withCurrentPosition);
        var loaded = await repository.OpenAsync(withCurrentPosition.Id);

        Assert.NotNull(loaded.CurrentPosition);
        Assert.Equal(new Coordinate(36, -62), loaded.CurrentPosition!.Coordinate);
        Assert.Equal(departure, loaded.CurrentPosition.DepartureTime);
        Assert.Equal(activeLegId, loaded.ActiveLegId);
    }

    [Fact]
    public async Task Unknown_active_leg_reference_is_rejected_on_load()
    {
        using var directory = new TestDirectory();
        var repository = new RoutePlanJsonRepository(directory.Path);
        var plan = CreatePlan();
        await repository.SaveAsync(plan);
        var path = Path.Combine(repository.RootDirectory, $"{plan.Id}.route.json");
        var node = System.Text.Json.Nodes.JsonNode.Parse(await File.ReadAllTextAsync(path))!;
        node["plan"]!["activeLegId"] = "99999999-9999-9999-9999-999999999999";
        await File.WriteAllTextAsync(path, node.ToJsonString());

        var exception = await Assert.ThrowsAsync<RoutePlanRepositoryException>(async () =>
            await repository.OpenAsync(plan.Id));
        Assert.Contains("active-leg", exception.Message, StringComparison.OrdinalIgnoreCase);
    }

    private static RoutePlan CreatePlan()
    {
        var plan = new RoutePlan(
            "Atlantic",
            [
                new RouteWaypoint("Start", new Coordinate(35, -65)),
                new RouteWaypoint("Stop", new Coordinate(37, -60), TimeSpan.FromHours(4)),
                new RouteWaypoint("Finish", new Coordinate(40, -52))
            ]);
        return plan.MarkSailed(plan.Legs[0].Id);
    }


    /// <summary>
    /// Version 3 predates environmental physics. Upgrading must leave every
    /// environment member null rather than synthesizing calm water, because a
    /// synthesized environment is indistinguishable from one that actually ran.
    /// </summary>
    [Fact]
    public async Task Version_three_results_are_migrated_with_null_environment()
    {
        using var directory = new TestDirectory();
        var repository = new RoutePlanJsonRepository(directory.Path);
        var plan = WithResult(CreatePlan());
        await repository.SaveAsync(plan);
        var path = Path.Combine(repository.RootDirectory, $"{plan.Id}.route.json");
        var root = System.Text.Json.Nodes.JsonNode.Parse(await File.ReadAllTextAsync(path))!;
        root["schemaVersion"] = 3;
        foreach (var result in root["plan"]!["results"]!.AsArray())
        {
            foreach (var leg in result!["legs"]!.AsArray())
            {
                var route = leg!["route"]!.AsObject();
                route.Remove("environment");
                route.Remove("environmentDiagnostics");
                foreach (var point in route["points"]!.AsArray())
                {
                    point!.AsObject().Remove("environment");
                }
            }
        }

        await File.WriteAllTextAsync(path, root.ToJsonString());

        var loaded = await repository.OpenAsync(plan.Id);

        Assert.All(
            loaded.Results.SelectMany(result => result.Legs),
            leg =>
            {
                Assert.Null(leg.Route!.Environment);
                Assert.Null(leg.Route.EnvironmentDiagnostics);
                Assert.All(leg.Route.Points, point => Assert.Null(point.Environment));
            });
    }

    [Fact]
    public async Task Version_four_documents_are_migrated_without_data_changes()
    {
        using var directory = new TestDirectory();
        var repository = new RoutePlanJsonRepository(directory.Path);
        var plan = WithResult(CreatePlan());
        await repository.SaveAsync(plan);
        var path = Path.Combine(repository.RootDirectory, $"{plan.Id}.route.json");
        var root = System.Text.Json.Nodes.JsonNode.Parse(await File.ReadAllTextAsync(path))!;
        root["schemaVersion"] = 4;
        await File.WriteAllTextAsync(path, root.ToJsonString());

        var loaded = await repository.OpenAsync(plan.Id);

        Assert.Equal(plan.Name, loaded.Name);
        Assert.Equal(
            plan.Results[0].Legs[0].Route!.Completion,
            loaded.Results[0].Legs[0].Route!.Completion);
    }

    [Fact]
    public async Task Environment_metadata_diagnostics_and_point_audit_round_trip()
    {
        using var directory = new TestDirectory();
        var repository = new RoutePlanJsonRepository(directory.Path);
        var plan = WithResult(CreatePlan(), environment: true);

        await repository.SaveAsync(plan);
        var loaded = await repository.OpenAsync(plan.Id);

        Assert.All(
            loaded.Results.SelectMany(result => result.Legs),
            leg =>
            {
                var environment = leg.Route!.Environment;
                Assert.NotNull(environment);
                Assert.Equal(RouteEnvironmentSampling.Midpoint, environment!.Sampling);
                Assert.Equal("uniform-current", environment.CurrentProvider?.Name);
                Assert.Equal("operator", environment.CurrentProvider?.Source);
                Assert.Equal("rev-1", environment.CurrentProvider?.Revision);
                Assert.Equal("navtool-signed-distance", environment.Landmask?.Name);
                Assert.Null(environment.Exclusions);
                Assert.Equal(RouteMissingDataPolicy.FailRoute, environment.CurrentPolicy);
                Assert.Equal(RouteMissingDataPolicy.RejectTransition, environment.LandPolicy);
                Assert.Equal(2.5, environment.LandResolutionNauticalMiles);
                Assert.Equal(1.75, environment.LandInterpolationErrorNauticalMiles);
                Assert.Equal(0.25, environment.LandClearanceNauticalMiles);
                Assert.Null(environment.ExclusionZoneCount);

                var diagnostics = leg.Route.EnvironmentDiagnostics;
                Assert.NotNull(diagnostics);
                Assert.Equal(11, diagnostics!.CurrentSamples);
                Assert.Equal(1, diagnostics.CurrentRejections);
                Assert.Equal(44, diagnostics.LandChecks);
                Assert.Equal(55, diagnostics.LandDistanceQueries);

                var first = leg.Route.Points[0].Environment;
                Assert.NotNull(first);
                Assert.Equal(7.25, first!.SpeedOverGroundKnots);
                Assert.Equal(95.5, first.CourseOverGroundDegrees);
                Assert.Equal(6, first.FlatWaterSpeedKnots);
                Assert.Equal(1.1, first.CurrentEastKnots);
                Assert.Equal(-0.4, first.CurrentNorthKnots);
                Assert.True(first.CurrentApplied);
                Assert.False(first.WaveApplied);
            });
    }

    /// <summary>
    /// Water-relative heading and speed must survive persistence unchanged even
    /// when the point also carries ground-frame motion, so a reloaded plan can
    /// never silently swap frames.
    /// </summary>
    [Fact]
    public async Task Persisted_points_keep_water_relative_values_alongside_ground_frame()
    {
        using var directory = new TestDirectory();
        var repository = new RoutePlanJsonRepository(directory.Path);
        var plan = WithResult(CreatePlan(), environment: true);

        await repository.SaveAsync(plan);
        var loaded = await repository.OpenAsync(plan.Id);

        var point = loaded.Results.SelectMany(result => result.Legs).First().Route!.Points[0];
        Assert.Equal(90, point.HeadingDegrees);
        Assert.Equal(6, point.BoatSpeedKnots);
        Assert.Equal(95.5, point.Environment!.CourseOverGroundDegrees);
        Assert.Equal(7.25, point.Environment.SpeedOverGroundKnots);
    }

    private static RoutePlan WithResult(
        RoutePlan plan,
        RouteSolver solver = RouteSolver.IsochroneBeam,
        RouteLatticeDiagnostics? latticeDiagnostics = null,
        bool environment = false,
        RouteCompletion completion = RouteCompletion.DestinationReached)
    {
        var pointEnvironment = environment
            ? new RoutePointEnvironment(
                speedOverGroundKnots: 7.25,
                courseOverGroundDegrees: 95.5,
                flatWaterSpeedKnots: 6,
                currentEastKnots: 1.1,
                currentNorthKnots: -0.4)
            : null;
        var environmentMetadata = environment
            ? new RouteEnvironmentMetadata(
                RouteEnvironmentSampling.Midpoint,
                currentProvider: new RouteProviderMetadata("uniform-current", "operator", "rev-1"),
                landmask: new RouteProviderMetadata("navtool-signed-distance", "osm", "rev-7"),
                currentPolicy: RouteMissingDataPolicy.FailRoute,
                wavePolicy: RouteMissingDataPolicy.FailRoute,
                landPolicy: RouteMissingDataPolicy.RejectTransition,
                landResolutionNauticalMiles: 2.5,
                landInterpolationErrorNauticalMiles: 1.75,
                landClearanceNauticalMiles: 0.25)
            : null;
        var environmentDiagnostics = environment
            ? new RouteEnvironmentDiagnostics(
                currentSamples: 11,
                currentRejections: 1,
                waveSamples: 0,
                waveRejections: 0,
                seaStateEvaluations: 0,
                landChecks: 44,
                landDistanceQueries: 55,
                landRejections: 2,
                exclusionChecks: 0,
                exclusionGeometryTests: 0,
                exclusionRejections: 0)
            : null;
        var now = new DateTimeOffset(2026, 8, 1, 18, 0, 0, TimeSpan.Zero);
        var session = new RouteCalculationSession(plan.Id, ForecastModel.NoaaGfs, now)
            .Complete(now.AddSeconds(2));
        var outcomes = plan.Legs.Select(leg =>
        {
            var from = plan.Waypoints[leg.Index];
            var to = plan.Waypoints[leg.Index + 1];
            var request = new RouteRequest(
                $"persisted-{leg.Index}",
                from.Coordinate,
                to.Coordinate,
                now,
                now.AddHours(4));
            var route = new RouteResult(
                request,
                ForecastModel.NoaaGfs,
                [
                    new RoutePoint(from.Coordinate, now, 90, 6, 15, 180, 0, pointEnvironment),
                    new RoutePoint(to.Coordinate, now.AddHours(1), 90, 6, 15, 180, 50, pointEnvironment)
                ],
                new RouteDiagnostics(1, 2, 1, 1, TimeSpan.FromSeconds(2)),
                completion,
                new RouteLandAvoidance(LandAvoidanceStatus.Applied, Attribution: "Test"),
                solver,
                latticeDiagnostics,
                environmentMetadata,
                environmentDiagnostics);
            return new RouteLegResult(
                leg.Id,
                RouteLegOutcomeState.Succeeded,
                completion.ToLegOutcomeReason(),
                route);
        });
        return plan.WithResult(new RoutePlanResult(session, outcomes));
    }
}
