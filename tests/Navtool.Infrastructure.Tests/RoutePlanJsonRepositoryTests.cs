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
        Assert.NotEqual(plan.Id, copy.Id);
        Assert.Equal("Return passage", copy.Name);
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

    private static RoutePlan WithResult(RoutePlan plan)
    {
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
                    new RoutePoint(from.Coordinate, now, 90, 6, 15, 180, 0),
                    new RoutePoint(to.Coordinate, now.AddHours(1), 90, 6, 15, 180, 50)
                ],
                new RouteDiagnostics(1, 2, 1, 1, TimeSpan.FromSeconds(2)),
                RouteCompletion.DestinationReached,
                new RouteLandAvoidance(LandAvoidanceStatus.Applied, Attribution: "Test"));
            return new RouteLegResult(
                leg.Id,
                RouteLegOutcomeState.Succeeded,
                RouteLegOutcomeReason.CalculationSucceeded,
                route);
        });
        return plan.WithResult(new RoutePlanResult(session, outcomes));
    }
}
