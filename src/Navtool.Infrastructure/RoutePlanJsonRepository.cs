using System.Collections.Immutable;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.Json.Serialization;
using Navtool.Core;

namespace Navtool.Infrastructure;

public interface IRoutePlanSchemaMigrator
{
    JsonDocument MigrateToCurrent(JsonDocument document, int fromVersion, int currentVersion);
}

public sealed class RoutePlanSchemaMigrator : IRoutePlanSchemaMigrator
{
    public JsonDocument MigrateToCurrent(JsonDocument document, int fromVersion, int currentVersion)
    {
        if (currentVersion != RoutePlanJsonRepository.CurrentSchemaVersion)
        {
            throw new InvalidDataException(
                $"Route plan schema version {fromVersion} is not supported by this application version.");
        }

        if (fromVersion == 2)
        {
            return MigrateV2ToV3(document);
        }

        if (fromVersion == 1)
        {
            using var versionTwo = MigrateV1ToV2(document);
            return MigrateV2ToV3(versionTwo);
        }

        throw new InvalidDataException(
            $"Route plan schema version {fromVersion} is not supported by this application version.");
    }

    /// <summary>
    /// Rewrites a version-1 route plan document to version 2 by adding the new
    /// <c>currentPosition</c> and <c>activeLegId</c> fields (both absent/null for plans that
    /// predate Slice 3's current-position/active-leg feature) and bumping <c>schemaVersion</c>.
    /// The plan's own <c>sailedLegIds</c> collection already existed pre-migration and is
    /// preserved as-is.
    /// </summary>
    private static JsonDocument MigrateV1ToV2(JsonDocument document)
    {
        using var stream = new MemoryStream();
        using (var writer = new Utf8JsonWriter(stream))
        {
            WriteMigratedEnvelope(writer, document.RootElement);
        }

        stream.Position = 0;
        return JsonDocument.Parse(stream.ToArray());
    }

    private static JsonDocument MigrateV2ToV3(JsonDocument document)
    {
        var root = JsonNode.Parse(document.RootElement.GetRawText()) as JsonObject ??
                   throw new InvalidDataException("A route plan document must be a JSON object.");
        root["schemaVersion"] = 3;
        if (root["plan"]?["results"] is JsonArray results)
        {
            foreach (var result in results.OfType<JsonObject>())
            {
                if (result["legs"] is not JsonArray legs)
                {
                    continue;
                }

                foreach (var leg in legs.OfType<JsonObject>())
                {
                    if (leg["route"] is not JsonObject route)
                    {
                        continue;
                    }

                    route["solver"] = nameof(RouteSolver.IsochroneBeam);
                    route["latticeDiagnostics"] = null;
                }
            }
        }

        return JsonDocument.Parse(root.ToJsonString());
    }

    private static void WriteMigratedEnvelope(Utf8JsonWriter writer, JsonElement root)
    {
        writer.WriteStartObject();
        foreach (var property in root.EnumerateObject())
        {
            if (property.NameEquals("schemaVersion"))
            {
                writer.WriteNumber("schemaVersion", 2);
                continue;
            }

            if (property.NameEquals("plan"))
            {
                WriteMigratedPlan(writer, "plan", property.Value);
                continue;
            }

            property.WriteTo(writer);
        }

        writer.WriteEndObject();
    }

    private static void WriteMigratedPlan(Utf8JsonWriter writer, string propertyName, JsonElement plan)
    {
        writer.WritePropertyName(propertyName);
        if (plan.ValueKind != JsonValueKind.Object)
        {
            plan.WriteTo(writer);
            return;
        }

        writer.WriteStartObject();
        foreach (var property in plan.EnumerateObject())
        {
            property.WriteTo(writer);
        }

        writer.WriteNull("currentPosition");
        writer.WriteNull("activeLegId");
        writer.WriteEndObject();
    }
}

public sealed class RoutePlanJsonRepository : IRoutePlanRepository
{
    public const int CurrentSchemaVersion = 3;
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web)
    {
        WriteIndented = true,
        RespectRequiredConstructorParameters = true,
        Converters = { new JsonStringEnumConverter(allowIntegerValues: false) }
    };

    private readonly string _rootDirectory;
    private readonly IRoutePlanSchemaMigrator _migrator;
    private readonly SemaphoreSlim _gate = new(1, 1);

    public RoutePlanJsonRepository(
        string appDataRoot,
        IRoutePlanSchemaMigrator? migrator = null)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(appDataRoot);
        _rootDirectory = Path.Combine(Path.GetFullPath(appDataRoot), "routes");
        _migrator = migrator ?? new RoutePlanSchemaMigrator();
        Directory.CreateDirectory(_rootDirectory);
    }

    public string RootDirectory => _rootDirectory;

    public async ValueTask<ImmutableArray<RoutePlanSummary>> ListAsync(
        CancellationToken cancellationToken = default)
    {
        await _gate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            var plans = new List<RoutePlanSummary>();
            foreach (var path in Directory.EnumerateFiles(_rootDirectory, "*.route.json")
                         .Order(StringComparer.Ordinal))
            {
                cancellationToken.ThrowIfCancellationRequested();
                var plan = await ReadAsync(path, cancellationToken).ConfigureAwait(false);
                var fileName = Path.GetFileName(path);
                var idText = fileName[..^".route.json".Length];
                if (!Guid.TryParseExact(idText, "N", out var fileId) ||
                    plan.Id != new RoutePlanId(fileId))
                {
                    throw new InvalidDataException(
                        $"Route plan file '{path}' does not match its stored plan ID '{plan.Id}'.");
                }

                plans.Add(new RoutePlanSummary(plan.Id, plan.Name, plan.Waypoints.Length));
            }

            return plans
                .OrderBy(plan => plan.Name, StringComparer.OrdinalIgnoreCase)
                .ThenBy(plan => plan.Id.Value)
                .ToImmutableArray();
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch (Exception exception) when (exception is not RoutePlanRepositoryException)
        {
            throw new RoutePlanRepositoryException(
                $"Listing saved route plans in '{_rootDirectory}' failed: {exception.Message}",
                exception);
        }
        finally
        {
            _gate.Release();
        }
    }

    public async ValueTask<RoutePlan> OpenAsync(
        RoutePlanId id,
        CancellationToken cancellationToken = default)
    {
        ValidateId(id);
        await _gate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            var path = GetPath(id);
            if (!File.Exists(path))
            {
                throw new FileNotFoundException($"Route plan '{id}' was not found.", path);
            }

            var plan = await ReadAsync(path, cancellationToken).ConfigureAwait(false);
            if (plan.Id != id)
            {
                throw new InvalidDataException(
                    $"Route plan file '{path}' contains plan ID '{plan.Id}' instead of '{id}'.");
            }

            return plan;
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch (Exception exception) when (exception is not RoutePlanRepositoryException)
        {
            throw new RoutePlanRepositoryException(
                $"Opening route plan '{id}' failed: {exception.Message}",
                exception);
        }
        finally
        {
            _gate.Release();
        }
    }

    public async ValueTask SaveAsync(
        RoutePlan plan,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(plan);
        await _gate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            await WriteAsync(plan, cancellationToken).ConfigureAwait(false);
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch (Exception exception) when (exception is not RoutePlanRepositoryException)
        {
            throw new RoutePlanRepositoryException(
                $"Saving route plan '{plan.Name}' failed: {exception.Message}",
                exception);
        }
        finally
        {
            _gate.Release();
        }
    }

    public async ValueTask<RoutePlan> SaveAsAsync(
        RoutePlan plan,
        string name,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(plan);
        ArgumentException.ThrowIfNullOrWhiteSpace(name);
        var newPlanId = new RoutePlanId();
        var copiedResults = plan.Results.Select(result =>
        {
            var session = new RouteCalculationSession(
                new RouteCalculationSessionId(),
                newPlanId,
                result.Model,
                result.Session.StartedAt,
                result.Session.CompletedAt);
            return new RoutePlanResult(session, result.Legs);
        });
        var copy = new RoutePlan(
            newPlanId,
            name,
            plan.Waypoints,
            copiedResults,
            plan.SailedLegIds);
        await SaveAsync(copy, cancellationToken).ConfigureAwait(false);
        return copy;
    }

    public async ValueTask DeleteAsync(
        RoutePlanId id,
        CancellationToken cancellationToken = default)
    {
        ValidateId(id);
        await _gate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            cancellationToken.ThrowIfCancellationRequested();
            var path = GetPath(id);
            if (!File.Exists(path))
            {
                throw new FileNotFoundException($"Route plan '{id}' was not found.", path);
            }

            File.Delete(path);
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch (Exception exception) when (exception is not RoutePlanRepositoryException)
        {
            throw new RoutePlanRepositoryException(
                $"Deleting route plan '{id}' failed: {exception.Message}",
                exception);
        }
        finally
        {
            _gate.Release();
        }
    }

    private async ValueTask<RoutePlan> ReadAsync(string path, CancellationToken cancellationToken)
    {
        await using var stream = new FileStream(
            path,
            FileMode.Open,
            FileAccess.Read,
            FileShare.Read,
            32 * 1024,
            FileOptions.Asynchronous | FileOptions.SequentialScan);
        using var original = await JsonDocument.ParseAsync(stream, cancellationToken: cancellationToken)
            .ConfigureAwait(false);
        if (!original.RootElement.TryGetProperty("schemaVersion", out var versionElement) ||
            !versionElement.TryGetInt32(out var version) ||
            version <= 0)
        {
            throw new InvalidDataException($"Route plan file '{path}' has no valid schemaVersion.");
        }

        if (version > CurrentSchemaVersion)
        {
            throw new InvalidDataException(
                $"Route plan file '{path}' uses future schema version {version}; " +
                $"this app supports through version {CurrentSchemaVersion}.");
        }

        if (version == CurrentSchemaVersion)
        {
            return DeserializeCurrent(original, path);
        }

        using var migrated = _migrator.MigrateToCurrent(
            original,
            version,
            CurrentSchemaVersion);
        return DeserializeCurrent(migrated, path);
    }

    private static RoutePlan DeserializeCurrent(JsonDocument document, string path)
    {
        var envelope = document.Deserialize<RoutePlanEnvelope>(JsonOptions) ??
                       throw new InvalidDataException($"Route plan file '{path}' is empty.");
        if (envelope.SchemaVersion != CurrentSchemaVersion || envelope.Plan is null)
        {
            throw new InvalidDataException($"Route plan file '{path}' has an invalid document envelope.");
        }

        return FromDto(envelope.Plan);
    }

    private async ValueTask WriteAsync(RoutePlan plan, CancellationToken cancellationToken)
    {
        var path = GetPath(plan.Id);
        var temporaryPath = Path.Combine(
            _rootDirectory,
            $".{plan.Id}.{Guid.NewGuid():N}.tmp");
        try
        {
            var envelope = new RoutePlanEnvelope(CurrentSchemaVersion, ToDto(plan));
            await using (var stream = new FileStream(
                             temporaryPath,
                             FileMode.CreateNew,
                             FileAccess.Write,
                             FileShare.None,
                             32 * 1024,
                             FileOptions.Asynchronous | FileOptions.WriteThrough))
            {
                await JsonSerializer.SerializeAsync(
                        stream,
                        envelope,
                        JsonOptions,
                        cancellationToken)
                    .ConfigureAwait(false);
                await stream.FlushAsync(cancellationToken).ConfigureAwait(false);
                stream.Flush(true);
            }

            cancellationToken.ThrowIfCancellationRequested();
            File.Move(temporaryPath, path, overwrite: true);
        }
        finally
        {
            if (File.Exists(temporaryPath))
            {
                File.Delete(temporaryPath);
            }
        }
    }

    private string GetPath(RoutePlanId id) => Path.Combine(_rootDirectory, $"{id}.route.json");

    private static void ValidateId(RoutePlanId id)
    {
        if (id.Value == Guid.Empty)
        {
            throw new ArgumentException("A route plan ID cannot be empty.", nameof(id));
        }
    }

    private static RoutePlanDto ToDto(RoutePlan plan) =>
        new(
            plan.Id.Value,
            plan.Name,
            plan.Waypoints.Select(waypoint => new RouteWaypointDto(
                waypoint.Id.Value,
                waypoint.Name,
                waypoint.Coordinate.Latitude,
                waypoint.Coordinate.Longitude,
                waypoint.Stopover?.Ticks)).ToArray(),
            plan.Results.Select(ToDto).ToArray(),
            plan.SailedLegIds.Select(id => id.Value).ToArray(),
            plan.CurrentPosition is null
                ? null
                : new RouteCurrentPositionDto(
                    plan.CurrentPosition.Coordinate.Latitude,
                    plan.CurrentPosition.Coordinate.Longitude,
                    plan.CurrentPosition.DepartureTime),
            plan.ActiveLegId?.Value);

    private static RoutePlanResultDto ToDto(RoutePlanResult result) =>
        new(
            new RouteCalculationSessionDto(
                result.Session.Id.Value,
                result.Session.PlanId.Value,
                result.Model,
                result.Session.StartedAt,
                result.Session.CompletedAt),
            result.Legs.Select(leg => new RouteLegResultDto(
                leg.LegId.Value,
                leg.State,
                leg.Reason,
                leg.Route is null ? null : ToDto(leg.Route),
                leg.Detail,
                leg.DeferredInvalidationReason)).ToArray());

    private static RouteResultDto ToDto(RouteResult route) =>
        new(
            new RouteRequestDto(
                route.Request.RouteId,
                route.Request.Origin.Latitude,
                route.Request.Origin.Longitude,
                route.Request.Destination.Latitude,
                route.Request.Destination.Longitude,
                route.Request.DepartureTime,
                route.Request.LatestArrivalTime),
            route.Model,
            route.Points.Select(point => new RoutePointDto(
                point.Location.Latitude,
                point.Location.Longitude,
                point.Timestamp,
                point.HeadingDegrees,
                point.BoatSpeedKnots,
                point.TrueWindSpeedKnots,
                point.TrueWindDirectionDegrees,
                point.CumulativeDistanceNauticalMiles)).ToArray(),
            new RouteDiagnosticsDto(
                route.Diagnostics.ExpandedNodes,
                route.Diagnostics.GeneratedCandidates,
                route.Diagnostics.RetainedCandidates,
                route.Diagnostics.TimeSteps,
                route.Diagnostics.CalculationDuration?.Ticks),
            route.Completion,
            new RouteLandAvoidanceDto(
                route.LandAvoidance.Status,
                route.LandAvoidance.Warning,
                route.LandAvoidance.Attribution),
            route.Solver,
            route.LatticeDiagnostics is null
                ? null
                : new RouteLatticeDiagnosticsDto(
                    route.LatticeDiagnostics.SettledLabels,
                    route.LatticeDiagnostics.QueuedLabels,
                    route.LatticeDiagnostics.RelaxedLabels,
                    route.LatticeDiagnostics.WaitTransitions,
                    route.LatticeDiagnostics.RefinementRuns,
                    route.LatticeDiagnostics.AcceptedRefinements,
                    route.LatticeDiagnostics.SubdivisionLevel,
                    route.LatticeDiagnostics.RefinementFallback));

    private static RoutePlan FromDto(RoutePlanDto dto)
    {
        if (dto.Id == Guid.Empty)
        {
            throw new InvalidDataException("A stored route plan ID cannot be empty.");
        }

        if (dto.Waypoints is null || dto.Results is null || dto.SailedLegIds is null)
        {
            throw new InvalidDataException("A stored route plan is missing required collections.");
        }

        if (dto.Waypoints.Any(waypoint => waypoint.Id == Guid.Empty) ||
            dto.Waypoints.Select(waypoint => waypoint.Id).Distinct().Count() != dto.Waypoints.Length)
        {
            throw new InvalidDataException("A stored route plan contains empty or duplicate waypoint IDs.");
        }

        var waypoints = dto.Waypoints.Select(waypoint => new RouteWaypoint(
            new RouteWaypointId(waypoint.Id),
            waypoint.Name,
            new Coordinate(waypoint.Latitude, waypoint.Longitude),
            waypoint.StopoverTicks is null
                ? null
                : TimeSpan.FromTicks(waypoint.StopoverTicks.Value))).ToArray();
        var legs = waypoints.Zip(waypoints.Skip(1), (from, to) => RouteLegId.FromEndpoints(from.Id, to.Id))
            .ToImmutableHashSet();
        var results = dto.Results.Select(result => FromDto(result, dto.Id, legs)).ToArray();
        var sailedIds = dto.SailedLegIds.Select(id => new RouteLegId(id)).ToArray();
        if (dto.SailedLegIds.Any(id => id == Guid.Empty) ||
            dto.SailedLegIds.Distinct().Count() != dto.SailedLegIds.Length)
        {
            throw new InvalidDataException("A stored route plan contains empty or duplicate sailed-leg IDs.");
        }

        var currentPosition = dto.CurrentPosition is null
            ? null
            : new RouteCurrentPosition(
                new Coordinate(dto.CurrentPosition.Latitude, dto.CurrentPosition.Longitude),
                dto.CurrentPosition.DepartureTime);
        if (dto.ActiveLegId is Guid activeLegGuid && activeLegGuid == Guid.Empty)
        {
            throw new InvalidDataException("A stored route plan has an empty active-leg ID.");
        }

        var activeLegId = dto.ActiveLegId is Guid guid ? new RouteLegId(guid) : (RouteLegId?)null;

        return new RoutePlan(
            new RoutePlanId(dto.Id),
            dto.Name,
            waypoints,
            results,
            sailedIds,
            currentPosition,
            activeLegId);
    }

    private static RoutePlanResult FromDto(
        RoutePlanResultDto dto,
        Guid planId,
        ImmutableHashSet<RouteLegId> validLegIds)
    {
        if (dto.Session is null || dto.Legs is null)
        {
            throw new InvalidDataException("A stored route plan result is incomplete.");
        }

        if (dto.Session.PlanId != planId)
        {
            throw new InvalidDataException("A calculation session references a different route plan.");
        }

        if (dto.Legs.Any(leg => leg.LegId == Guid.Empty) ||
            dto.Legs.Select(leg => leg.LegId).Distinct().Count() != dto.Legs.Length)
        {
            throw new InvalidDataException("A route plan result contains empty or duplicate leg IDs.");
        }

        var legs = dto.Legs.Select(leg =>
        {
            var legId = new RouteLegId(leg.LegId);
            if (!validLegIds.Contains(legId))
            {
                throw new InvalidDataException($"A route plan result references unknown leg '{legId}'.");
            }

            return new RouteLegResult(
                legId,
                leg.State,
                leg.Reason,
                leg.Route is null ? null : FromDto(leg.Route),
                leg.Detail,
                leg.DeferredInvalidationReason);
        });
        return new RoutePlanResult(
            new RouteCalculationSession(
                new RouteCalculationSessionId(dto.Session.Id),
                new RoutePlanId(dto.Session.PlanId),
                dto.Session.Model,
                dto.Session.StartedAt,
                dto.Session.CompletedAt),
            legs);
    }

    private static RouteResult FromDto(RouteResultDto dto)
    {
        if (dto.Request is null || dto.Points is null || dto.Diagnostics is null ||
            dto.LandAvoidance is null)
        {
            throw new InvalidDataException("A stored route result is incomplete.");
        }

        var request = new RouteRequest(
            dto.Request.RouteId,
            new Coordinate(dto.Request.OriginLatitude, dto.Request.OriginLongitude),
            new Coordinate(dto.Request.DestinationLatitude, dto.Request.DestinationLongitude),
            dto.Request.DepartureTime,
            dto.Request.LatestArrivalTime);
        if (!Enum.IsDefined(dto.Model) ||
            !Enum.IsDefined(dto.Completion) ||
            !Enum.IsDefined(dto.LandAvoidance.Status) ||
            !Enum.IsDefined(dto.Solver))
        {
            throw new InvalidDataException("A stored route result contains an unknown enum value.");
        }

        var latticeDiagnostics = dto.LatticeDiagnostics is null
            ? null
            : new RouteLatticeDiagnostics(
                dto.LatticeDiagnostics.SettledLabels,
                dto.LatticeDiagnostics.QueuedLabels,
                dto.LatticeDiagnostics.RelaxedLabels,
                dto.LatticeDiagnostics.WaitTransitions,
                dto.LatticeDiagnostics.RefinementRuns,
                dto.LatticeDiagnostics.AcceptedRefinements,
                dto.LatticeDiagnostics.SubdivisionLevel,
                dto.LatticeDiagnostics.RefinementFallback);

        return new RouteResult(
            request,
            dto.Model,
            dto.Points.Select(point => new RoutePoint(
                new Coordinate(point.Latitude, point.Longitude),
                point.Timestamp,
                point.HeadingDegrees,
                point.BoatSpeedKnots,
                point.TrueWindSpeedKnots,
                point.TrueWindDirectionDegrees,
                point.CumulativeDistanceNauticalMiles)),
            new RouteDiagnostics(
                dto.Diagnostics.ExpandedNodes,
                dto.Diagnostics.GeneratedCandidates,
                dto.Diagnostics.RetainedCandidates,
                dto.Diagnostics.TimeSteps,
                dto.Diagnostics.CalculationDurationTicks is null
                    ? null
                    : TimeSpan.FromTicks(dto.Diagnostics.CalculationDurationTicks.Value)),
            dto.Completion,
            new RouteLandAvoidance(
                dto.LandAvoidance.Status,
                dto.LandAvoidance.Warning,
                dto.LandAvoidance.Attribution),
            dto.Solver,
            latticeDiagnostics);
    }

    private sealed record RoutePlanEnvelope(int SchemaVersion, RoutePlanDto? Plan);

    private sealed record RoutePlanDto(
        Guid Id,
        string Name,
        RouteWaypointDto[] Waypoints,
        RoutePlanResultDto[] Results,
        Guid[] SailedLegIds,
        RouteCurrentPositionDto? CurrentPosition = null,
        Guid? ActiveLegId = null);

    private sealed record RouteCurrentPositionDto(
        double Latitude,
        double Longitude,
        DateTimeOffset DepartureTime);

    private sealed record RouteWaypointDto(
        Guid Id,
        string Name,
        double Latitude,
        double Longitude,
        long? StopoverTicks);

    private sealed record RoutePlanResultDto(
        RouteCalculationSessionDto Session,
        RouteLegResultDto[] Legs);

    private sealed record RouteCalculationSessionDto(
        Guid Id,
        Guid PlanId,
        ForecastModel Model,
        DateTimeOffset StartedAt,
        DateTimeOffset? CompletedAt);

    private sealed record RouteLegResultDto(
        Guid LegId,
        RouteLegOutcomeState State,
        RouteLegOutcomeReason Reason,
        RouteResultDto? Route,
        string? Detail,
        RouteLegOutcomeReason? DeferredInvalidationReason);

    private sealed record RouteResultDto(
        RouteRequestDto Request,
        ForecastModel Model,
        RoutePointDto[] Points,
        RouteDiagnosticsDto Diagnostics,
        RouteCompletion Completion,
        RouteLandAvoidanceDto LandAvoidance,
        RouteSolver Solver,
        RouteLatticeDiagnosticsDto? LatticeDiagnostics);

    private sealed record RouteRequestDto(
        string RouteId,
        double OriginLatitude,
        double OriginLongitude,
        double DestinationLatitude,
        double DestinationLongitude,
        DateTimeOffset DepartureTime,
        DateTimeOffset LatestArrivalTime);

    private sealed record RoutePointDto(
        double Latitude,
        double Longitude,
        DateTimeOffset Timestamp,
        double HeadingDegrees,
        double BoatSpeedKnots,
        double TrueWindSpeedKnots,
        double TrueWindDirectionDegrees,
        double CumulativeDistanceNauticalMiles);

    private sealed record RouteDiagnosticsDto(
        long ExpandedNodes,
        long GeneratedCandidates,
        long RetainedCandidates,
        int TimeSteps,
        long? CalculationDurationTicks);

    private sealed record RouteLandAvoidanceDto(
        LandAvoidanceStatus Status,
        string? Warning,
        string? Attribution);

    private sealed record RouteLatticeDiagnosticsDto(
        long SettledLabels,
        long QueuedLabels,
        long RelaxedLabels,
        long WaitTransitions,
        int RefinementRuns,
        int AcceptedRefinements,
        int SubdivisionLevel,
        bool RefinementFallback);
}
