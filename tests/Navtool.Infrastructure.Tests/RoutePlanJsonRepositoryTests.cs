using System.Text.Json;
using Navtool.Core;
using Navtool.Infrastructure;

namespace Navtool.Infrastructure.Tests;

public sealed class RoutePlanJsonRepositoryTests
{
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
        bool environment = false)
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
                RouteCompletion.DestinationReached,
                new RouteLandAvoidance(LandAvoidanceStatus.Applied, Attribution: "Test"),
                solver,
                latticeDiagnostics,
                environmentMetadata,
                environmentDiagnostics);
            return new RouteLegResult(
                leg.Id,
                RouteLegOutcomeState.Succeeded,
                RouteLegOutcomeReason.CalculationSucceeded,
                route);
        });
        return plan.WithResult(new RoutePlanResult(session, outcomes));
    }
}
