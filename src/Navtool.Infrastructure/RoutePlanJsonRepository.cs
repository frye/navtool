using System.Collections.Immutable;
using System.Security.Cryptography;
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
                $"Route plan schema version {currentVersion} is not supported by this application version.");
        }

        if (fromVersion is < 1 or > 7)
            throw new InvalidDataException(
                $"Route plan schema version {fromVersion} is not supported by this application version.");
        var current = JsonDocument.Parse(document.RootElement.GetRawText());
        try
        {
            for (var version = fromVersion; version < currentVersion; version++)
            {
                var next = version switch
                {
                    1 => MigrateV1ToV2(current),
                    2 => MigrateV2ToV3(current),
                    3 => MigrateV3ToV4(current),
                    4 => MigrateV4ToV5(current),
                    5 => MigrateV5ToV6(current),
                    6 => MigrateV6ToV7(current),
                    7 => MigrateV7ToV8(current),
                    _ => throw new InvalidDataException("Unsupported migration step.")
                };
                current.Dispose();
                current = next;
            }
            return current;
        }
        catch
        {
            current.Dispose();
            throw;
        }
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

    /// <summary>
    /// Rewrites a version-3 route plan document to version 4. Version 4 adds the
    /// Stage 3 environment audit: a per-result <c>environment</c> and
    /// <c>environmentDiagnostics</c>, and a per-point <c>environment</c>. A
    /// version-3 plan predates environmental physics, so every one of those is
    /// left null rather than synthesized. A null environment is what "no
    /// environment ran" means everywhere else in the pipeline, so an upgraded
    /// plan reads back exactly as it was written.
    /// </summary>
    private static JsonDocument MigrateV3ToV4(JsonDocument document)
    {
        var root = JsonNode.Parse(document.RootElement.GetRawText()) as JsonObject ??
                   throw new InvalidDataException("A route plan document must be a JSON object.");
        root["schemaVersion"] = 4;
        foreach (var route in EnumerateRoutes(root))
        {
            route["environment"] = null;
            route["environmentDiagnostics"] = null;
            if (route["points"] is not JsonArray points)
            {
                continue;
            }

            foreach (var point in points.OfType<JsonObject>())
            {
                point["environment"] = null;
            }
        }

        return JsonDocument.Parse(root.ToJsonString());
    }

    private static JsonDocument MigrateV4ToV5(JsonDocument document)
    {
        var root = JsonNode.Parse(document.RootElement.GetRawText()) as JsonObject ??
                   throw new InvalidDataException("A route plan document must be a JSON object.");
        root["schemaVersion"] = 5;
        return JsonDocument.Parse(root.ToJsonString());
    }

    private static JsonDocument MigrateV5ToV6(JsonDocument document)
    {
        var root = JsonNode.Parse(document.RootElement.GetRawText()) as JsonObject ??
                   throw new InvalidDataException("A route plan document must be a JSON object.");
        root["schemaVersion"] = 6;
        if (root["plan"] is JsonObject plan)
        {
            plan["setup"] = null;
            if (plan["results"] is JsonArray results)
            {
                foreach (var leg in results.OfType<JsonObject>()
                             .SelectMany(result => (result["legs"] as JsonArray)?.OfType<JsonObject>() ?? []))
                {
                    leg["executionSession"] = null;
                    leg["origin"] = null;
                    leg["plannedHold"] = null;
                    leg["failure"] = null;
                }
            }
        }
        foreach (var route in EnumerateRoutes(root))
        {
            route["runAudit"] = null;
            route["nativeAudit"] = null;
            if (route["diagnostics"] is JsonObject diagnostics)
            {
                diagnostics["eligibilityEvaluations"] = null;
                diagnostics["prunedCandidates"] = null;
                diagnostics["futureProbeMisses"] = null;
            }
            if (route["points"] is JsonArray points)
            {
                foreach (var point in points.OfType<JsonObject>())
                {
                    point["polarWindSpeedKnots"] = null;
                    point["polarWindDirectionDegrees"] = null;
                    if (point["environment"] is JsonObject environment)
                    {
                        environment["polarWindSpeedKnots"] = null;
                        environment["polarWindDirectionDegrees"] = null;
                    }
                }
            }
        }

        return JsonDocument.Parse(root.ToJsonString());
    }

    private static JsonDocument MigrateV6ToV7(JsonDocument document)
    {
        var root = JsonNode.Parse(document.RootElement.GetRawText()) as JsonObject ??
                   throw new InvalidDataException("A route plan document must be a JSON object.");
        root["schemaVersion"] = 7;
        if (root["plan"]?["setup"] is JsonObject setup)
            setup["coastalPruning"] = nameof(RouteCoastalPruningMode.Off);
        foreach (var route in EnumerateRoutes(root))
        {
            if (route["diagnostics"] is JsonObject diagnostics)
                diagnostics["coastalPruning"] = null;
            if (route["nativeAudit"] is JsonObject native)
            {
                native["coastalPruning"] = null;
                native["coastalSeedActions"] = null;
            }
            if (route["runAudit"] is not JsonObject audit) continue;
            if (audit["setup"] is JsonObject requested)
                requested["coastalPruning"] = nameof(RouteCoastalPruningMode.Off);
            if (audit["resolved"] is JsonObject resolved)
                resolved["coastalPruning"] = nameof(RouteCoastalPruningMode.Off);
            if (audit["native"] is JsonObject observed)
            {
                observed["coastalPruning"] = null;
                observed["coastalSeedActions"] = null;
            }
        }
        return JsonDocument.Parse(root.ToJsonString());
    }

    private static JsonDocument MigrateV7ToV8(JsonDocument document)
    {
        var root = JsonNode.Parse(document.RootElement.GetRawText()) as JsonObject ??
                   throw new InvalidDataException("A route plan document must be a JSON object.");
        root["schemaVersion"] = 8;
        // Legacy plans have no planning intent. Never infer mutable inputs from run audit.
        if (root["plan"] is JsonObject plan) plan["planningInputs"] = null;
        return JsonDocument.Parse(root.ToJsonString());
    }

    private static IEnumerable<JsonObject> EnumerateRoutes(JsonObject root)
    {
        if (root["plan"]?["results"] is not JsonArray results)
        {
            yield break;
        }

        foreach (var result in results.OfType<JsonObject>())
        {
            if (result["legs"] is not JsonArray legs)
            {
                continue;
            }

            foreach (var leg in legs.OfType<JsonObject>())
            {
                if (leg["route"] is JsonObject route)
                {
                    yield return route;
                }
            }
        }
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
    public const int CurrentSchemaVersion = 8;
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web)
    {
        WriteIndented = true,
        RespectRequiredConstructorParameters = true,
        RespectNullableAnnotations = true,
        UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow,
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
        var copy = plan.CopyAs(new RoutePlanId(), name);
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
        ValidateObjectKeys(document.RootElement);
        var envelope = document.Deserialize<RoutePlanEnvelope>(JsonOptions) ??
                       throw new InvalidDataException($"Route plan file '{path}' is empty.");
        if (envelope.SchemaVersion != CurrentSchemaVersion || envelope.Plan is null)
        {
            throw new InvalidDataException($"Route plan file '{path}' has an invalid document envelope.");
        }

        return FromDto(envelope.Plan);
    }

    private static void ValidateObjectKeys(JsonElement element)
    {
        if (element.ValueKind == JsonValueKind.Object)
        {
            var names = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (var property in element.EnumerateObject())
            {
                if (!names.Add(property.Name))
                    throw new InvalidDataException($"A stored object repeats field '{property.Name}'.");
                ValidateObjectKeys(property.Value);
            }
        }
        else if (element.ValueKind == JsonValueKind.Array)
        {
            foreach (var item in element.EnumerateArray()) ValidateObjectKeys(item);
        }
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
            _ = FromDto(envelope.Plan!);
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
            await PreserveMigrationBackupAsync(path, cancellationToken).ConfigureAwait(false);
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

    private async ValueTask PreserveMigrationBackupAsync(
        string path,
        CancellationToken cancellationToken)
    {
        if (!File.Exists(path))
        {
            return;
        }

        var original = await File.ReadAllBytesAsync(path, cancellationToken).ConfigureAwait(false);
        using var document = JsonDocument.Parse(original);
        if (!document.RootElement.TryGetProperty("schemaVersion", out var versionElement) ||
            !versionElement.TryGetInt32(out var version) ||
            version <= 0 || version > CurrentSchemaVersion)
        {
            throw new InvalidDataException(
                $"Cannot replace route plan '{path}' with an invalid or unsupported schema.");
        }

        if (version == CurrentSchemaVersion)
        {
            return;
        }

        var hash = Convert.ToHexString(SHA256.HashData(original)).ToLowerInvariant();
        var backupDirectory = Path.Combine(_rootDirectory, "backups");
        Directory.CreateDirectory(backupDirectory);
        var backupPath = Path.Combine(
            backupDirectory,
            $"{Path.GetFileNameWithoutExtension(path)}.schema-{version}.{hash}.json");
        if (File.Exists(backupPath))
        {
            var saved = await File.ReadAllBytesAsync(backupPath, cancellationToken).ConfigureAwait(false);
            if (!original.AsSpan().SequenceEqual(saved))
            {
                throw new InvalidDataException(
                    $"Migration backup '{backupPath}' does not match the original route plan.");
            }

            return;
        }

        var temporaryPath = Path.Combine(backupDirectory, $".{Guid.NewGuid():N}.tmp");
        try
        {
            await using (var stream = new FileStream(
                             temporaryPath,
                             FileMode.CreateNew,
                             FileAccess.Write,
                             FileShare.None,
                             32 * 1024,
                             FileOptions.Asynchronous | FileOptions.WriteThrough))
            {
                await stream.WriteAsync(original, cancellationToken).ConfigureAwait(false);
                await stream.FlushAsync(cancellationToken).ConfigureAwait(false);
                stream.Flush(true);
            }

            cancellationToken.ThrowIfCancellationRequested();
            File.Move(temporaryPath, backupPath, overwrite: false);
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
            plan.ActiveLegId?.Value,
            plan.RoutingSetup is null ? null : ToDto(plan.RoutingSetup),
            plan.PlanningInputs);

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
                leg.DeferredInvalidationReason,
                leg.ExecutionSession is null ? null : ToDto(leg.ExecutionSession),
                leg.Origin is null ? null : ToDto(leg.Origin),
                leg.PlannedHold is null ? null : ToDto(leg.PlannedHold),
                leg.Failure is null ? null : ToDto(leg.Failure))).ToArray());

    private static RouteFailureDto ToDto(ModelRouteFailure failure) =>
        new(failure.Stage, failure.Code, failure.Message, failure.Kind,
            (failure.Attempts.IsDefault ? ImmutableArray<RouteAttemptAudit>.Empty : failure.Attempts)
                .Select(attempt => new RouteAttemptAuditDto(attempt.AttemptId, attempt.Solver,
                    attempt.StartedAt, attempt.CompletedAt, attempt.FailureKind, attempt.FailureMessage)).ToArray());

    private static ModelRouteFailure FromDto(RouteFailureDto dto)
    {
        if (dto.Attempts is null || dto.Attempts.Any(attempt => attempt is null))
            throw new InvalidDataException("Stored failure audit must contain a valid attempt collection.");
        return new ModelRouteFailure(dto.Stage, dto.Code, dto.Message, dto.Kind,
            dto.Attempts.Select(attempt => new RouteAttemptAudit(attempt.AttemptId, attempt.Solver,
                attempt.StartedAt, attempt.CompletedAt, attempt.FailureKind, attempt.FailureMessage)).ToImmutableArray());
    }

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
                point.CumulativeDistanceNauticalMiles,
                point.Environment is null
                    ? null
                    : new RoutePointEnvironmentDto(
                        point.Environment.SpeedOverGroundKnots,
                        point.Environment.CourseOverGroundDegrees,
                        point.Environment.FlatWaterSpeedKnots,
                        point.Environment.CurrentEastKnots,
                        point.Environment.CurrentNorthKnots,
                        point.Environment.SignificantWaveHeightMetres,
                        point.Environment.WavePeriodSeconds,
                        point.Environment.RelativeWaveAngleDegrees,
                        point.Environment.PolarWindSpeedKnots,
                        point.Environment.PolarWindDirectionDegrees),
                point.PolarWindSpeedKnots,
                point.PolarWindDirectionDegrees)).ToArray(),
            new RouteDiagnosticsDto(
                route.Diagnostics.ExpandedNodes,
                route.Diagnostics.GeneratedCandidates,
                route.Diagnostics.RetainedCandidates,
                route.Diagnostics.TimeSteps,
                route.Diagnostics.CalculationDuration?.Ticks,
                route.Diagnostics.EligibilityEvaluations,
                route.Diagnostics.PrunedCandidates,
                route.Diagnostics.FutureProbeMisses,
                route.Diagnostics.CoastalPruning is { } coastal ? ToDto(coastal) : null),
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
                    route.LatticeDiagnostics.RefinementFallback,
                    route.LatticeDiagnostics.ReRelaxedLabels,
                    route.LatticeDiagnostics.StaleQueueEntries,
                    route.LatticeDiagnostics.ActiveCells,
                    route.LatticeDiagnostics.ActiveFaces,
                    route.LatticeDiagnostics.AcceptedCorridorWidthNauticalMiles,
                    route.LatticeDiagnostics.DisconnectedRefinements,
                    route.LatticeDiagnostics.RegressedRefinements,
                    route.LatticeDiagnostics.FallbackReason),
            route.Environment is null
                ? null
                : new RouteEnvironmentMetadataDto(
                    route.Environment.Sampling,
                    ToDto(route.Environment.CurrentProvider),
                    ToDto(route.Environment.WaveProvider),
                    ToDto(route.Environment.SeaStateModel),
                    ToDto(route.Environment.Landmask),
                    ToDto(route.Environment.Exclusions),
                    route.Environment.CurrentPolicy,
                    route.Environment.WavePolicy,
                    route.Environment.LandPolicy,
                    route.Environment.LandResolutionNauticalMiles,
                    route.Environment.LandInterpolationErrorNauticalMiles,
                    route.Environment.LandClearanceNauticalMiles,
                    route.Environment.ExclusionBoundaryPolicy,
                    route.Environment.ExclusionZoneCount,
                    route.Environment.ExclusionRevision),
            route.EnvironmentDiagnostics is null
                ? null
                : new RouteEnvironmentDiagnosticsDto(
                    route.EnvironmentDiagnostics.CurrentSamples,
                    route.EnvironmentDiagnostics.CurrentRejections,
                    route.EnvironmentDiagnostics.WaveSamples,
                    route.EnvironmentDiagnostics.WaveRejections,
                    route.EnvironmentDiagnostics.SeaStateEvaluations,
                    route.EnvironmentDiagnostics.LandChecks,
                    route.EnvironmentDiagnostics.LandDistanceQueries,
                    route.EnvironmentDiagnostics.LandRejections,
                    route.EnvironmentDiagnostics.ExclusionChecks,
                    route.EnvironmentDiagnostics.ExclusionGeometryTests,
                    route.EnvironmentDiagnostics.ExclusionRejections),
            route.RunAudit is null ? null : ToDto(route.RunAudit),
            route.NativeAudit is null ? null : ToDto(route.NativeAudit));

    private static RouteProviderMetadataDto? ToDto(RouteProviderMetadata? metadata) =>
        metadata is null
            ? null
            : new RouteProviderMetadataDto(
                metadata.Name,
                metadata.Source,
                metadata.Revision);

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
            activeLegId,
            dto.Setup is null ? null : FromDto(dto.Setup),
            dto.PlanningInputs);
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
            if (leg.Route?.RunAudit is not null && (leg.ExecutionSession is null || leg.Origin is null))
                throw new InvalidDataException("A configured stored route must retain its execution session and origin.");

            return new RouteLegResult(
                legId,
                leg.State,
                leg.Reason,
                leg.Route is null ? null : FromDto(leg.Route),
                leg.Detail,
                leg.DeferredInvalidationReason,
                leg.ExecutionSession is null ? null : FromDto(leg.ExecutionSession),
                leg.Origin is null ? null : FromDto(leg.Origin),
                leg.PlannedHold is null ? null : FromDto(leg.PlannedHold),
                leg.Failure is null ? null : FromDto(leg.Failure));
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
                dto.LatticeDiagnostics.RefinementFallback,
                dto.LatticeDiagnostics.ReRelaxedLabels ?? 0L,
                dto.LatticeDiagnostics.StaleQueueEntries ?? 0L,
                dto.LatticeDiagnostics.ActiveCells ?? 0L,
                dto.LatticeDiagnostics.ActiveFaces ?? 0L,
                dto.LatticeDiagnostics.AcceptedCorridorWidthNauticalMiles ?? 0.0,
                dto.LatticeDiagnostics.DisconnectedRefinements ?? 0,
                dto.LatticeDiagnostics.RegressedRefinements ?? 0,
                dto.LatticeDiagnostics.FallbackReason ?? LatticeRefinementFallbackReason.None);

        var runAudit = dto.RunAudit is null ? null : FromDto(dto.RunAudit);
        var nativeAudit = dto.NativeAudit is null ? null : FromDto(dto.NativeAudit);
        if (nativeAudit is not null && runAudit?.Native is { } runNative)
        {
            if (JsonSerializer.Serialize(ToDto(nativeAudit), JsonOptions) !=
                JsonSerializer.Serialize(ToDto(runNative), JsonOptions))
                throw new InvalidDataException("Stored duplicate native audits disagree.");
            nativeAudit = runNative;
        }
        var result = new RouteResult(
            request,
            dto.Model,
            dto.Points.Select(point => new RoutePoint(
                new Coordinate(point.Latitude, point.Longitude),
                point.Timestamp,
                point.HeadingDegrees,
                point.BoatSpeedKnots,
                point.TrueWindSpeedKnots,
                point.TrueWindDirectionDegrees,
                point.CumulativeDistanceNauticalMiles,
                point.Environment is null
                    ? null
                    : new RoutePointEnvironment(
                        point.Environment.SpeedOverGroundKnots,
                        point.Environment.CourseOverGroundDegrees,
                        point.Environment.FlatWaterSpeedKnots,
                        point.Environment.CurrentEastKnots,
                        point.Environment.CurrentNorthKnots,
                        point.Environment.SignificantWaveHeightMetres,
                        point.Environment.WavePeriodSeconds,
                        point.Environment.RelativeWaveAngleDegrees,
                        point.Environment.PolarWindSpeedKnots,
                        point.Environment.PolarWindDirectionDegrees),
                point.PolarWindSpeedKnots,
                point.PolarWindDirectionDegrees)),
            new RouteDiagnostics(
                dto.Diagnostics.ExpandedNodes,
                dto.Diagnostics.GeneratedCandidates,
                dto.Diagnostics.RetainedCandidates,
                dto.Diagnostics.TimeSteps,
                dto.Diagnostics.CalculationDurationTicks is null
                    ? null
                    : TimeSpan.FromTicks(dto.Diagnostics.CalculationDurationTicks.Value),
                dto.Diagnostics.EligibilityEvaluations,
                dto.Diagnostics.PrunedCandidates,
                dto.Diagnostics.FutureProbeMisses,
                dto.Diagnostics.CoastalPruning is { } coastal ? FromDto(coastal) : null),
            dto.Completion,
            new RouteLandAvoidance(
                dto.LandAvoidance.Status,
                dto.LandAvoidance.Warning,
                dto.LandAvoidance.Attribution),
            dto.Solver,
            latticeDiagnostics,
            dto.Environment is null
                ? null
                : new RouteEnvironmentMetadata(
                    dto.Environment.Sampling,
                    FromDto(dto.Environment.CurrentProvider),
                    FromDto(dto.Environment.WaveProvider),
                    FromDto(dto.Environment.SeaStateModel),
                    FromDto(dto.Environment.Landmask),
                    FromDto(dto.Environment.Exclusions),
                    dto.Environment.CurrentPolicy,
                    dto.Environment.WavePolicy,
                    dto.Environment.LandPolicy,
                    dto.Environment.LandResolutionNauticalMiles,
                    dto.Environment.LandInterpolationErrorNauticalMiles,
                    dto.Environment.LandClearanceNauticalMiles,
                    dto.Environment.ExclusionBoundaryPolicy,
                    dto.Environment.ExclusionZoneCount,
                    dto.Environment.ExclusionRevision),
            dto.EnvironmentDiagnostics is null
                ? null
                : new RouteEnvironmentDiagnostics(
                    dto.EnvironmentDiagnostics.CurrentSamples,
                    dto.EnvironmentDiagnostics.CurrentRejections,
                    dto.EnvironmentDiagnostics.WaveSamples,
                    dto.EnvironmentDiagnostics.WaveRejections,
                    dto.EnvironmentDiagnostics.SeaStateEvaluations,
                    dto.EnvironmentDiagnostics.LandChecks,
                    dto.EnvironmentDiagnostics.LandDistanceQueries,
                    dto.EnvironmentDiagnostics.LandRejections,
                    dto.EnvironmentDiagnostics.ExclusionChecks,
                    dto.EnvironmentDiagnostics.ExclusionGeometryTests,
                    dto.EnvironmentDiagnostics.ExclusionRejections),
            runAudit,
            nativeAudit);
        ValidateStoredAudit(result);
        return result;
    }

    private static RouteProviderMetadata? FromDto(RouteProviderMetadataDto? dto) =>
        dto is null
            ? null
            : new RouteProviderMetadata(dto.Name, dto.Source, dto.Revision);

    private static RouteCalculationSessionDto ToDto(RouteCalculationSession value) =>
        new(value.Id.Value, value.PlanId.Value, value.Model, value.StartedAt, value.CompletedAt);

    private static RouteCalculationSession FromDto(RouteCalculationSessionDto dto) =>
        new(new RouteCalculationSessionId(dto.Id), new RoutePlanId(dto.PlanId), dto.Model,
            dto.StartedAt, dto.CompletedAt);

    private static RouteLegOriginDto ToDto(RouteLegOrigin value) =>
        new(value.Source, value.Predecessor is not { } predecessor ? null :
            new(predecessor.PlanId.Value, predecessor.LegId.Value, predecessor.Model,
                predecessor.SessionId.Value, predecessor.RouteId));

    private static RouteLegOrigin FromDto(RouteLegOriginDto dto)
    {
        if (!Enum.IsDefined(dto.Source) ||
            (dto.Source == RouteLegOriginSource.AcceptedPredecessor) != (dto.Predecessor is not null))
            throw new InvalidDataException("Stored leg origin and predecessor are inconsistent.");
        if (dto.Predecessor is not { } p) return new(dto.Source);
        if (p.PlanId == Guid.Empty || p.LegId == Guid.Empty || p.SessionId == Guid.Empty ||
            !Enum.IsDefined(p.Model) || string.IsNullOrWhiteSpace(p.RouteId))
            throw new InvalidDataException("A stored predecessor has invalid identities.");
        return new(dto.Source, new(new(p.PlanId), new(p.LegId), p.Model, new(p.SessionId), p.RouteId));
    }

    private static RoutePlannedHoldDto ToDto(RoutePlannedHold value) =>
        new(value.Location.Latitude, value.Location.Longitude, value.From, value.Until,
            value.Status, value.ConflictZoneIdentifier, value.Detail);

    private static RoutePlannedHold FromDto(RoutePlannedHoldDto dto)
    {
        if (dto.Status != RouteHoldCheckStatus.Conflict && dto.ConflictZoneIdentifier is not null)
            throw new InvalidDataException("A non-conflicting hold cannot name a conflict zone.");
        return new(new(dto.Latitude, dto.Longitude), dto.From, dto.Until, dto.Status,
            dto.ConflictZoneIdentifier, dto.Detail);
    }

    private static RoutingSetupDto ToDto(RoutingSetup value) =>
        new(new(value.Boat.ContentIdentity, value.Boat.SourceDisplayName, value.Boat.Kind,
                value.Boat.RequestedFormat,
                new(value.Boat.Validation.NativeMessage, value.Boat.Validation.MinimumWindSpeedKnots,
                    value.Boat.Validation.MaximumWindSpeedKnots, value.Boat.Validation.MinimumAngleDegrees,
                    value.Boat.Validation.MaximumAngleDegrees, value.Boat.Validation.ResolvedFormat),
                value.Boat.MinimumTrueWindAngleDegrees, value.Boat.MaximumTrueWindAngleDegrees),
            value.Quality, value.PerformanceFactor, value.ArrivalRadiusNauticalMiles, value.LandSource,
            value.ForecastPolicy, value.HardDuration?.Ticks, value.LocalForecastMaximumGap.Ticks,
            value.RegionalLand is not { } land ? null :
                new(land.SourcePath, land.SourceIdentity, ToDto(land.StudyBounds),
                    land.ResolutionNauticalMiles, land.ClearanceNauticalMiles, land.DistanceCapNauticalMiles,
                    land.MaximumGridNodes, land.MaximumSourcePoints, land.MaximumGeometryTests,
                    land.MaximumSubdivisionDepth, land.Attribution, land.MissingDataPolicy),
            value.CoastalPruning);

    private static RoutingSetup FromDto(RoutingSetupDto dto)
    {
        var b = dto.Boat;
        var v = b.Validation;
        if (string.IsNullOrWhiteSpace(v.NativeMessage) ||
            !OptionalNonnegative(v.MinimumWindSpeedKnots) || !OptionalNonnegative(v.MaximumWindSpeedKnots) ||
            !OptionalAngle(v.MinimumAngleDegrees) || !OptionalAngle(v.MaximumAngleDegrees) ||
            v.MinimumWindSpeedKnots > v.MaximumWindSpeedKnots || v.MinimumAngleDegrees > v.MaximumAngleDegrees ||
            (v.ResolvedFormat is { } format && !Enum.IsDefined(format)))
            throw new InvalidDataException("Stored boat validation metadata is invalid.");
        ValidateHardDuration(dto.HardDurationTicks);
        if (dto.LocalForecastMaximumGapTicks <= 0 ||
            dto.LocalForecastMaximumGapTicks % TimeSpan.TicksPerSecond != 0)
            throw new InvalidDataException("Stored local forecast gap must be positive whole seconds.");
        return new(new(b.ContentIdentity, b.SourceDisplayName, b.Kind, b.RequestedFormat,
                new(v.NativeMessage, v.MinimumWindSpeedKnots, v.MaximumWindSpeedKnots,
                    v.MinimumAngleDegrees, v.MaximumAngleDegrees, v.ResolvedFormat),
                b.MinimumTrueWindAngleDegrees, b.MaximumTrueWindAngleDegrees),
            dto.Quality, dto.PerformanceFactor, dto.ArrivalRadiusNauticalMiles, dto.LandSource,
            dto.ForecastPolicy, Ticks(dto.HardDurationTicks), TimeSpan.FromTicks(dto.LocalForecastMaximumGapTicks),
            dto.RegionalLand is not { } land ? null :
                new(land.SourcePath, land.SourceIdentity, FromDto(land.StudyBounds),
                    land.ResolutionNauticalMiles, land.ClearanceNauticalMiles, land.DistanceCapNauticalMiles,
                    land.MaximumGridNodes, land.MaximumSourcePoints, land.MaximumGeometryTests,
                    land.MaximumSubdivisionDepth, land.Attribution, land.MissingDataPolicy),
            dto.CoastalPruning);
    }

    private static bool OptionalNonnegative(double? value) =>
        value is null || double.IsFinite(value.Value) && value >= 0;
    private static bool OptionalAngle(double? value) => OptionalNonnegative(value) && (value is null || value <= 180);
    private static TimeSpan? Ticks(long? value) => value is { } ticks ? TimeSpan.FromTicks(ticks) : null;
    private static void ValidateHardDuration(long? ticks)
    {
        if (ticks is { } value && (value <= 0 || value % TimeSpan.TicksPerHour != 0 ||
                                  value > TimeSpan.FromDays(366).Ticks))
            throw new InvalidDataException("Stored native hard duration must be positive integral hours, at most 366 days.");
    }

    private static RouteOptimizationDto ToDto(RouteOptimizationOptions value) =>
        new(value.Solver, value.Maneuver.TackPenalty.Ticks, value.Maneuver.GybePenalty.Ticks,
            value.Maneuver.DownwindTrueWindAngleDegrees, value.HeadingAugmentation, value.WindSampling,
            value.MidpointWindSamplingThreshold.Ticks, value.PolarAngleInterpolation,
            value.MaximumTrueWindSpeedKnots, value.AbovePolarRange, value.PruningStrategy,
            value.PruningSectorDegrees, value.DestinationFront.HalfAngleDegrees,
            value.DestinationFront.SegmentPolicy, value.DestinationFront.MinimumSecondarySegmentPoints,
            value.Lattice.SubdivisionLevel, value.Lattice.TimeBucket.Ticks, value.Lattice.RefinementLevels,
            value.Lattice.CorridorWidthNauticalMiles, value.Lattice.CorridorWideningRetries,
            value.Lattice.ProgressEveryExpansions, value.Lattice.SearchAlgorithm);

    private static RouteOptimizationOptions FromDto(RouteOptimizationDto dto) =>
        new(dto.Solver, new(TimeSpan.FromTicks(dto.TackPenaltyTicks), TimeSpan.FromTicks(dto.GybePenaltyTicks),
                dto.DownwindTrueWindAngleDegrees),
            dto.HeadingAugmentation, dto.WindSampling, TimeSpan.FromTicks(dto.MidpointWindSamplingThresholdTicks),
            dto.PolarAngleInterpolation, dto.MaximumTrueWindSpeedKnots, dto.AbovePolarRange,
            dto.PruningStrategy, dto.PruningSectorDegrees,
            new(dto.FrontHalfAngleDegrees, dto.FrontSegmentPolicy, dto.FrontMinimumSecondarySegmentPoints),
            new(dto.LatticeSubdivisionLevel, TimeSpan.FromTicks(dto.LatticeTimeBucketTicks), dto.LatticeRefinementLevels,
                dto.LatticeCorridorWidthNauticalMiles, dto.LatticeCorridorWideningRetries,
                dto.LatticeProgressEveryExpansions, dto.LatticeSearchAlgorithm));

    private static RouteSearchSettingsDto ToDto(RouteSearchSettings value) =>
        new(value.TimeStep.Ticks, value.MaximumIntegrationStep.Ticks, value.HeadingStepDegrees,
            value.SpatialBucketNauticalMiles, value.MaxNodesPerBucket, value.WorkerCount,
            value.MaximumGeneratedCandidates, value.MaximumRetainedNodes, value.ProgressEveryNSteps,
            value.UseRoutingIntervals, value.StrategicRetention, value.CaptureIsochrones,
            value.DestinationFrontMode, value.MinimumBoatSpeedKnots,
            value.Intervals.Select(interval => new RouteRoutingIntervalDto(interval.Interval.Ticks,
                interval.UntilElapsed?.Ticks)).ToArray());

    private static RouteSearchSettings FromDto(RouteSearchSettingsDto dto)
    {
        if (dto.TimeStepTicks < TimeSpan.FromMinutes(5).Ticks || dto.TimeStepTicks > TimeSpan.FromDays(1).Ticks ||
            dto.TimeStepTicks % TimeSpan.TicksPerMinute != 0 || dto.MaximumIntegrationStepTicks <= 0 ||
            dto.MaximumIntegrationStepTicks > TimeSpan.FromDays(1).Ticks ||
            dto.MaximumIntegrationStepTicks % TimeSpan.TicksPerMinute != 0 ||
            !double.IsFinite(dto.HeadingStepDegrees) || dto.HeadingStepDegrees is <= 0 or > 180 ||
            !double.IsFinite(dto.SpatialBucketNauticalMiles) || dto.SpatialBucketNauticalMiles <= 0 ||
            !OptionalNonnegative(dto.MinimumBoatSpeedKnots) || dto.MaxNodesPerBucket == 0 ||
            dto.WorkerCount > 1024 || dto.MaximumGeneratedCandidates == 0 || dto.MaximumRetainedNodes == 0 ||
            dto.ProgressEveryNSteps == 0 || dto.DestinationFrontMode is < 0 or > 1 ||
            dto.Intervals.Length > 16 || (dto.UseRoutingIntervals && dto.Intervals.Length == 0))
            throw new InvalidDataException("Stored native search settings are invalid.");
        long previous = 0;
        for (var i = 0; i < dto.Intervals.Length; ++i)
        {
            var interval = dto.Intervals[i] ?? throw new InvalidDataException("A stored routing interval is null.");
            if (interval.IntervalTicks < TimeSpan.FromMinutes(5).Ticks ||
                interval.IntervalTicks > TimeSpan.FromDays(1).Ticks ||
                interval.IntervalTicks % TimeSpan.TicksPerMinute != 0 ||
                (interval.UntilElapsedTicks is { } until
                    ? until <= previous || until % TimeSpan.TicksPerMinute != 0 || i == dto.Intervals.Length - 1
                    : i != dto.Intervals.Length - 1))
                throw new InvalidDataException("Stored routing interval policy is inconsistent.");
            previous = interval.UntilElapsedTicks ?? previous;
        }
        return new(TimeSpan.FromTicks(dto.TimeStepTicks), TimeSpan.FromTicks(dto.MaximumIntegrationStepTicks),
            dto.HeadingStepDegrees, dto.SpatialBucketNauticalMiles, dto.MaxNodesPerBucket, dto.WorkerCount,
            dto.MaximumGeneratedCandidates, dto.MaximumRetainedNodes, dto.ProgressEveryNSteps,
            dto.UseRoutingIntervals, dto.StrategicRetention, dto.CaptureIsochrones, dto.DestinationFrontMode,
            dto.MinimumBoatSpeedKnots, dto.Intervals.Select(interval =>
                new RouteRoutingInterval(TimeSpan.FromTicks(interval.IntervalTicks), Ticks(interval.UntilElapsedTicks))));
    }

    private static ResolvedRoutingOptionsDto ToDto(ResolvedRoutingOptions value) =>
        new(value.Quality, ToDto(value.Optimization), ToDto(value.Search), value.PerformanceFactor,
            value.ArrivalRadiusNauticalMiles, value.HardDuration?.Ticks, value.CoastalPruning);

    private static ResolvedRoutingOptions FromDto(ResolvedRoutingOptionsDto dto)
    {
        ValidateHardDuration(dto.HardDurationTicks);
        if (!Enum.IsDefined(dto.Quality) || !Enum.IsDefined(dto.CoastalPruning) ||
            dto.CoastalPruning != RouteCoastalPruningMode.Off && dto.Optimization.Solver != RouteSolver.IsochroneBeam ||
            !double.IsFinite(dto.PerformanceFactor) || dto.PerformanceFactor <= 0 ||
            !double.IsFinite(dto.ArrivalRadiusNauticalMiles) || dto.ArrivalRadiusNauticalMiles <= 0)
            throw new InvalidDataException("Stored resolved routing settings are invalid.");
        return new(dto.Quality, FromDto(dto.Optimization), FromDto(dto.Search), dto.PerformanceFactor,
            dto.ArrivalRadiusNauticalMiles, Ticks(dto.HardDurationTicks), dto.CoastalPruning);
    }

    private static RouteRunAuditDto ToDto(RouteRunAudit value) =>
        new(value.CalculationId, ToDto(value.Setup), ToDto(value.Resolved),
            new(value.NativeIdentity.BridgeAbiVersion, value.NativeIdentity.LibraryVersion,
                value.NativeIdentity.SourceRevision, value.NativeIdentity.BuildIdentity, value.NativeIdentity.Capabilities),
            value.RequestedSolver,
            value.Attempts.Select(attempt => new RouteAttemptAuditDto(attempt.AttemptId, attempt.Solver,
                attempt.StartedAt, attempt.CompletedAt, attempt.FailureKind, attempt.FailureMessage)).ToArray(),
            value.Forecast is not { } forecast ? null : new(new(forecast.Run.Provider, forecast.Run.Model,
                    forecast.Run.InitializedAt), ToDto(forecast.DeclaredBounds),
                forecast.EffectiveBounds is { } bounds ? ToDto(bounds) : null,
                forecast.ValidFrom, forecast.ValidThrough, forecast.MaximumInterpolationGap?.Ticks,
                forecast.MinimumTimeSpacing?.Ticks, forecast.MaximumTimeSpacing?.Ticks,
                forecast.ValidTimes.IsDefault ? null : forecast.ValidTimes.ToArray()),
            value.Native is null ? null : ToDto(value.Native),
            value.ProfessionalOverrides is not { } professional ? null :
                new(professional.Optimization is null ? null : ToDto(professional.Optimization),
                    professional.Search is null ? null : ToDto(professional.Search)),
            value.ApplicationLand is not { } land ? null : new(land.Status, land.Warning, land.Attribution));

    private static RouteRunAudit FromDto(RouteRunAuditDto dto)
    {
        var identity = dto.NativeIdentity;
        if (identity.BridgeAbiVersion is not (8 or 9) || string.IsNullOrWhiteSpace(identity.LibraryVersion) ||
            string.IsNullOrWhiteSpace(identity.SourceRevision) || string.IsNullOrWhiteSpace(identity.BuildIdentity))
            throw new InvalidDataException("Stored native build identity is invalid or unsupported.");
        var setup = FromDto(dto.Setup);
        var resolved = FromDto(dto.Resolved);
        if (setup.Quality != resolved.Quality || setup.PerformanceFactor != resolved.PerformanceFactor ||
            setup.CoastalPruning != resolved.CoastalPruning ||
            setup.ArrivalRadiusNauticalMiles != resolved.ArrivalRadiusNauticalMiles ||
            (setup.HardDuration is { } hard && hard != resolved.HardDuration))
            throw new InvalidDataException("Stored requested and effective cruising settings disagree.");
        RouteForecastAudit? forecast = null;
        if (dto.Forecast is { } f)
        {
            if (f.ValidFrom > f.ValidThrough ||
                f.ValidFrom < f.Run.InitializedAt || (f.ValidFrom is null) != (f.ValidThrough is null) ||
                f.MaximumInterpolationGapTicks <= 0 ||
                (f.MinimumTimeSpacingTicks is null) != (f.MaximumTimeSpacingTicks is null) ||
                f.MinimumTimeSpacingTicks <= 0 || f.MaximumTimeSpacingTicks <= 0 ||
                f.MinimumTimeSpacingTicks > f.MaximumTimeSpacingTicks ||
                (f.MinimumTimeSpacingTicks is { } minimum && minimum % TimeSpan.TicksPerSecond != 0) ||
                (f.MaximumTimeSpacingTicks is { } maximum && maximum % TimeSpan.TicksPerSecond != 0) ||
                (f.MaximumTimeSpacingTicks is not null && f.ValidFrom == f.ValidThrough) ||
                f.MaximumTimeSpacingTicks > f.MaximumInterpolationGapTicks)
                throw new InvalidDataException("Stored forecast audit is inconsistent.");
            var times = f.ValidTimes ?? [];
            ValidateForecastTimes(times, allowEmpty: true);
            if (times.Length != 0 &&
                (times[0] != f.ValidFrom || times[^1] != f.ValidThrough ||
                 (f.MinimumTimeSpacingTicks is { } minSpacing &&
                  (times.Length < 2 || AdjacentSpacings(times).Min().Ticks != minSpacing)) ||
                 (f.MaximumTimeSpacingTicks is { } maxSpacing &&
                  (times.Length < 2 || AdjacentSpacings(times).Max().Ticks != maxSpacing))))
                throw new InvalidDataException("Stored valid times contradict forecast bounds or spacing.");
            forecast = new(new(f.Run.Provider, f.Run.Model, f.Run.InitializedAt),
                FromDto(f.DeclaredBounds), f.EffectiveBounds is null ? null : FromDto(f.EffectiveBounds),
                f.ValidFrom, f.ValidThrough, Ticks(f.MaximumInterpolationGapTicks),
                Ticks(f.MinimumTimeSpacingTicks), Ticks(f.MaximumTimeSpacingTicks), times.ToImmutableArray());
        }
        if (dto.ApplicationLand is { } land && !Enum.IsDefined(land.Status))
            throw new InvalidDataException("Stored application land status is unknown.");
        return new(dto.CalculationId, setup, resolved,
            new(identity.BridgeAbiVersion, identity.LibraryVersion, identity.SourceRevision,
                identity.BuildIdentity, identity.Capabilities), dto.RequestedSolver,
            dto.Attempts.Select(attempt => new RouteAttemptAudit(attempt.AttemptId, attempt.Solver,
                attempt.StartedAt, attempt.CompletedAt, attempt.FailureKind, attempt.FailureMessage)),
            forecast, dto.Native is null ? null : FromDto(dto.Native),
            dto.ProfessionalOverrides is not { } p ? null :
                new(p.Optimization is null ? null : FromDto(p.Optimization), p.Search is null ? null : FromDto(p.Search)),
            dto.ApplicationLand is not { } a ? null : new(a.Status, a.Warning, a.Attribution));
    }

    private static BoundsDto ToDto(GeographicBounds value) => new(value.South, value.North, value.West, value.East);
    private static GeographicBounds FromDto(BoundsDto dto) => new(dto.South, dto.North, dto.West, dto.East);

    private static IEnumerable<TimeSpan> AdjacentSpacings(DateTimeOffset[] times) =>
        times.Zip(times.Skip(1), (from, until) => until - from);

    private static void ValidateForecastTimes(DateTimeOffset[] times, bool allowEmpty)
    {
        if ((!allowEmpty && times.Length == 0) ||
            times.Any(time => time.Ticks % TimeSpan.TicksPerSecond != 0) ||
            AdjacentSpacings(times).Any(spacing => spacing <= TimeSpan.Zero))
            throw new InvalidDataException("Stored forecast times must be present, strictly increasing whole UTC seconds.");
    }

    private static ForecastCoverageDto ToDto(ForecastCoverage value) =>
        new(ToDto(value.EffectiveBounds), value.ValidTimes.ToArray(), value.MaximumInterpolationGap?.Ticks);

    private static ForecastCoverage FromDto(ForecastCoverageDto dto)
    {
        ValidateForecastTimes(dto.ValidTimes, allowEmpty: false);
        if (dto.MaximumInterpolationGapTicks <= 0 ||
            (dto.MaximumInterpolationGapTicks is { } gap &&
             (gap % TimeSpan.TicksPerSecond != 0 || AdjacentSpacings(dto.ValidTimes).Any(spacing => spacing.Ticks > gap))))
            throw new InvalidDataException("Stored native forecast coverage violates its gap policy.");
        return new(FromDto(dto.EffectiveBounds), dto.ValidTimes, Ticks(dto.MaximumInterpolationGapTicks));
    }

    private static RouteNativeRunAuditDto ToDto(RouteNativeRunAudit value) =>
        new(value.Schema, value.Solver, value.EffectiveArrivalRadiusNauticalMiles, value.HardDuration?.Ticks,
            value.NativeLandmaskApplied, value.EligibilityEvaluations, value.PrunedCandidates,
            value.FutureProbeMisses, value.Routing is null ? null : ToDto(value.Routing),
            value.ForecastSource, value.PolarSource, value.DepartureSource,
            value.ForecastCoverage is null ? null : ToDto(value.ForecastCoverage),
            value.CoastalPruning is null ? null : ToDto(value.CoastalPruning),
            value.CoastalSeedActions.IsDefault ? null : value.CoastalSeedActions.Select(
                action => new RouteCoastalSeedActionDto(action.HeadingDegrees, action.Duration.Ticks)).ToArray());

    private static RouteNativeRunAudit FromDto(RouteNativeRunAuditDto dto)
    {
        if (dto.Schema != "route_result_v2" || !Enum.IsDefined(dto.Solver) ||
            dto.EligibilityEvaluations < 0 || dto.PrunedCandidates < 0 || dto.FutureProbeMisses < 0 ||
            (dto.EffectiveArrivalRadiusNauticalMiles is { } radius && (!double.IsFinite(radius) || radius <= 0)) ||
            (dto.DepartureSource is not null && dto.DepartureSource is not
                ("explicit_time" or "current_time" or "forecast_start_fallback")))
            throw new InvalidDataException("Stored native audit schema or known field is invalid.");
        ValidateHardDuration(dto.HardDurationTicks);
        var routing = dto.Routing is null ? null : FromDto(dto.Routing);
        var coverage = dto.ForecastCoverage is null ? null : FromDto(dto.ForecastCoverage);
        if (routing is not null && (routing.Solver != dto.Solver ||
            (dto.EffectiveArrivalRadiusNauticalMiles is { } arrival && arrival != routing.ArrivalRadiusNauticalMiles) ||
            (dto.NativeLandmaskApplied is { } applied && applied != routing.LandAvoidance)))
            throw new InvalidDataException("Stored native audit fields contradict one another.");
        if (routing is not null && coverage is not null &&
            (routing.ForecastFirstValid != coverage.ValidFrom || routing.ForecastLastValid != coverage.ValidThrough))
            throw new InvalidDataException("Stored native coverage contradicts native routing forecast validity.");
        return new(dto.Schema, dto.Solver, dto.EffectiveArrivalRadiusNauticalMiles, Ticks(dto.HardDurationTicks),
            dto.NativeLandmaskApplied, dto.EligibilityEvaluations, dto.PrunedCandidates,
            dto.FutureProbeMisses, routing, dto.ForecastSource, dto.PolarSource, dto.DepartureSource, coverage,
            dto.CoastalPruning is null ? null : FromDto(dto.CoastalPruning),
            dto.CoastalSeedActions is null ? default : dto.CoastalSeedActions.Select(action =>
                action is null ? throw new InvalidDataException("A stored coastal seed action is null.") :
                    new RouteCoastalSeedAction(action.HeadingDegrees, TimeSpan.FromTicks(action.DurationTicks))).ToImmutableArray());
    }

    private static RouteCoastalPruningDiagnosticsDto ToDto(RouteCoastalPruningDiagnostics value) =>
        new(value.Mode, value.Status, value.UnavailableReason, value.SkippedParents,
            value.DisconnectedCandidates, value.HorizonCandidates, value.IncumbentCandidates,
            value.BoundUnavailable, value.SeedEvaluations, value.TopologyWork, value.IncumbentArrival,
            value.SourceIdentity, value.DomainIdentity, value.SeedStatus, value.SpeedUpperKnots,
            value.TopologyCaps, value.NumericalMarginNauticalMiles, value.ClearanceNauticalMiles);

    private static RouteCoastalPruningDiagnostics FromDto(RouteCoastalPruningDiagnosticsDto dto) =>
        new(dto.Mode, dto.Status, dto.UnavailableReason, dto.SkippedParents,
            dto.DisconnectedCandidates, dto.HorizonCandidates, dto.IncumbentCandidates,
            dto.BoundUnavailable, dto.SeedEvaluations, dto.TopologyWork, dto.IncumbentArrival,
            dto.SourceIdentity, dto.DomainIdentity, dto.SeedStatus, dto.SpeedUpperKnots,
            dto.TopologyCaps, dto.NumericalMarginNauticalMiles, dto.ClearanceNauticalMiles);

    private static RouteNativeRunMetadataDto ToDto(RouteNativeRunMetadata value) =>
        new(value.Objective, value.QualityClaim, value.Solver,
            value.RequestedDestination.Latitude, value.RequestedDestination.Longitude,
            value.ArrivalRadiusNauticalMiles, value.RemainingDistanceNauticalMiles, value.BoatSpeedFactor,
            value.HeadingStepDegrees, value.SpatialBucketNauticalMiles, value.MaximumIntegrationStep.Ticks,
            value.StrategicRetention, value.LandAvoidance, value.WindSampling, value.AbovePolarRange,
            value.MaximumForecastWindKnots, value.TackPenalty.Ticks, value.GybePenalty.Ticks,
            value.ForecastInitialization, value.ForecastFirstValid, value.ForecastLastValid, value.Warnings.ToArray());

    private static RouteNativeRunMetadata FromDto(RouteNativeRunMetadataDto dto) =>
        new(dto.Objective, dto.QualityClaim, dto.Solver, new(dto.DestinationLatitude, dto.DestinationLongitude),
            dto.ArrivalRadiusNauticalMiles, dto.RemainingDistanceNauticalMiles, dto.BoatSpeedFactor,
            dto.HeadingStepDegrees, dto.SpatialBucketNauticalMiles, TimeSpan.FromTicks(dto.MaximumIntegrationStepTicks),
            dto.StrategicRetention, dto.LandAvoidance, dto.WindSampling, dto.AbovePolarRange,
            dto.MaximumForecastWindKnots, TimeSpan.FromTicks(dto.TackPenaltyTicks), TimeSpan.FromTicks(dto.GybePenaltyTicks),
            dto.ForecastInitialization, dto.ForecastFirstValid, dto.ForecastLastValid, dto.Warnings);

    private static void ValidateStoredAudit(RouteResult route)
    {
        foreach (var point in route.Points)
        {
            if ((point.PolarWindSpeedKnots is null) != (point.PolarWindDirectionDegrees is null) ||
                (point.Environment is { } e &&
                 ((e.PolarWindSpeedKnots is null) != (e.PolarWindDirectionDegrees is null) ||
                  (e.PolarWindSpeedKnots is { } speed && speed != point.PolarWindSpeedKnots) ||
                  (e.PolarWindDirectionDegrees is { } direction && direction != point.PolarWindDirectionDegrees))))
                throw new InvalidDataException("Stored polar-wind audit is incomplete or contradictory.");
        }
        var native = route.NativeAudit;
        if (route.RunAudit is { } audit)
        {
            if (audit.Attempts[^1].Solver != route.Solver || audit.Attempts[^1].FailureKind is not null ||
                audit.Resolved.Optimization.Solver != route.Solver ||
                (audit.Forecast is { } forecast && forecast.Run.Model != route.Model))
                throw new InvalidDataException("Stored run attempts or forecast disagree with the accepted route.");
            if (native is not null && audit.Native is not null &&
                JsonSerializer.Serialize(ToDto(native), JsonOptions) != JsonSerializer.Serialize(ToDto(audit.Native), JsonOptions))
                throw new InvalidDataException("Stored duplicate native audits disagree.");
            native ??= audit.Native;
        }
        if (native is null) return;
        if (native.Routing is { } observed && route.RunAudit?.Forecast is { } loadedForecast &&
            (loadedForecast.Run.InitializedAt != observed.ForecastInitialization ||
             (loadedForecast.ValidFrom is { } validFrom && validFrom != observed.ForecastFirstValid) ||
             (loadedForecast.ValidThrough is { } validThrough && validThrough != observed.ForecastLastValid)))
            throw new InvalidDataException("Stored forecast snapshot disagrees with the observed native forecast metadata.");
        if (native.ForecastCoverage is { } nativeCoverage && route.RunAudit?.Forecast is { } forecastAudit &&
            ((forecastAudit.EffectiveBounds is { } effective && effective != nativeCoverage.EffectiveBounds) ||
             (!forecastAudit.ValidTimes.IsDefaultOrEmpty && !forecastAudit.ValidTimes.SequenceEqual(nativeCoverage.ValidTimes))))
            throw new InvalidDataException("Stored loaded forecast audit contradicts native coverage.");
        if (native.Solver != route.Solver ||
            (native.EligibilityEvaluations is { } evaluations && route.Diagnostics.EligibilityEvaluations is { } actual && evaluations != actual) ||
            (native.PrunedCandidates is { } pruned && route.Diagnostics.PrunedCandidates is { } actualPruned && pruned != actualPruned) ||
            (native.FutureProbeMisses is { } misses && route.Diagnostics.FutureProbeMisses is { } actualMisses && misses != actualMisses) ||
            (native.Routing is { } routing &&
             (!routing.RequestedDestination.IsSameLocation(route.Request.Destination) ||
              route.Points[0].Timestamp < routing.ForecastFirstValid || route.ArrivalTime > routing.ForecastLastValid)))
            throw new InvalidDataException("Stored native audit disagrees with the route request, solver, counters, or forecast.");
    }

    private sealed record RoutingSetupDto(
        BoatAssetDto Boat, RoutingQuality Quality, double PerformanceFactor, double ArrivalRadiusNauticalMiles,
        RoutingLandSource LandSource, ForecastRefreshPolicy ForecastPolicy, long? HardDurationTicks,
        long LocalForecastMaximumGapTicks, RouteRegionalLandPolicyDto? RegionalLand,
        [property: JsonRequired] RouteCoastalPruningMode CoastalPruning);
    private sealed record RouteRegionalLandPolicyDto(
        string SourcePath, string SourceIdentity, BoundsDto StudyBounds,
        double ResolutionNauticalMiles, double ClearanceNauticalMiles, double DistanceCapNauticalMiles,
        ulong MaximumGridNodes, ulong MaximumSourcePoints, ulong MaximumGeometryTests, int MaximumSubdivisionDepth,
        string Attribution, RouteMissingDataPolicy MissingDataPolicy);
    private sealed record BoatAssetDto(
        string ContentIdentity, string SourceDisplayName, BoatAssetKind Kind, BoatPolarFormat RequestedFormat,
        BoatValidationDto Validation, double? MinimumTrueWindAngleDegrees, double? MaximumTrueWindAngleDegrees);
    private sealed record BoatValidationDto(
        string NativeMessage, double? MinimumWindSpeedKnots, double? MaximumWindSpeedKnots,
        double? MinimumAngleDegrees, double? MaximumAngleDegrees, BoatPolarFormat? ResolvedFormat);
    private sealed record RouteLegOriginDto(RouteLegOriginSource Source, RoutePredecessorDto? Predecessor);
    private sealed record RoutePredecessorDto(Guid PlanId, Guid LegId, ForecastModel Model, Guid SessionId, string RouteId);
    private sealed record RoutePlannedHoldDto(
        double Latitude, double Longitude, DateTimeOffset From, DateTimeOffset Until,
        RouteHoldCheckStatus Status, string? ConflictZoneIdentifier, string? Detail);
    private sealed record RouteOptimizationDto(
        RouteSolver Solver, long TackPenaltyTicks, long GybePenaltyTicks, double DownwindTrueWindAngleDegrees,
        RouteHeadingAugmentation HeadingAugmentation, RouteWindSampling WindSampling,
        long MidpointWindSamplingThresholdTicks, RoutePolarAngleInterpolation PolarAngleInterpolation,
        double? MaximumTrueWindSpeedKnots, RouteAbovePolarRangePolicy AbovePolarRange,
        RoutePruningStrategy PruningStrategy, double PruningSectorDegrees, double FrontHalfAngleDegrees,
        RouteDestinationFrontSegmentPolicy FrontSegmentPolicy, int FrontMinimumSecondarySegmentPoints,
        int LatticeSubdivisionLevel, long LatticeTimeBucketTicks, int LatticeRefinementLevels,
        double LatticeCorridorWidthNauticalMiles, int LatticeCorridorWideningRetries,
        int LatticeProgressEveryExpansions, RouteLatticeSearchAlgorithm LatticeSearchAlgorithm);
    private sealed record RouteSearchSettingsDto(
        long TimeStepTicks, long MaximumIntegrationStepTicks, double HeadingStepDegrees,
        double SpatialBucketNauticalMiles, ulong MaxNodesPerBucket, ulong WorkerCount,
        ulong MaximumGeneratedCandidates, ulong MaximumRetainedNodes, ulong ProgressEveryNSteps,
        bool UseRoutingIntervals, bool StrategicRetention, bool CaptureIsochrones,
        int DestinationFrontMode, double MinimumBoatSpeedKnots, RouteRoutingIntervalDto[] Intervals);
    private sealed record RouteRoutingIntervalDto(long IntervalTicks, long? UntilElapsedTicks);
    private sealed record ResolvedRoutingOptionsDto(
        RoutingQuality Quality, RouteOptimizationDto Optimization, RouteSearchSettingsDto Search,
        double PerformanceFactor, double ArrivalRadiusNauticalMiles, long? HardDurationTicks,
        [property: JsonRequired] RouteCoastalPruningMode CoastalPruning);
    private sealed record RouteProfessionalOverridesDto(RouteOptimizationDto? Optimization, RouteSearchSettingsDto? Search);
    private sealed record NativeRoutingIdentityDto(
        int BridgeAbiVersion, string LibraryVersion, string SourceRevision, string BuildIdentity, ulong Capabilities);
    private sealed record RouteRunAuditDto(
        Guid CalculationId, RoutingSetupDto Setup, ResolvedRoutingOptionsDto Resolved,
        NativeRoutingIdentityDto NativeIdentity, RouteSolver RequestedSolver, RouteAttemptAuditDto[] Attempts,
        RouteForecastAuditDto? Forecast, RouteNativeRunAuditDto? Native,
        RouteProfessionalOverridesDto? ProfessionalOverrides, RouteLandAvoidanceDto? ApplicationLand);
    private sealed record RouteAttemptAuditDto(
        Guid AttemptId, RouteSolver Solver, DateTimeOffset StartedAt, DateTimeOffset CompletedAt,
        RoutingFailureKind? FailureKind, string? FailureMessage);
    private sealed record ForecastRunDto(ForecastProvider Provider, ForecastModel Model, DateTimeOffset InitializedAt);
    private sealed record BoundsDto(double South, double North, double West, double East);
    private sealed record RouteForecastAuditDto(
        ForecastRunDto Run, BoundsDto DeclaredBounds, BoundsDto? EffectiveBounds,
        DateTimeOffset? ValidFrom, DateTimeOffset? ValidThrough, long? MaximumInterpolationGapTicks,
        long? MinimumTimeSpacingTicks = null, long? MaximumTimeSpacingTicks = null,
        DateTimeOffset[]? ValidTimes = null);
    private sealed record ForecastCoverageDto(
        BoundsDto EffectiveBounds, DateTimeOffset[] ValidTimes, long? MaximumInterpolationGapTicks);
    private sealed record RouteNativeRunAuditDto(
        string Schema, RouteSolver Solver, double? EffectiveArrivalRadiusNauticalMiles, long? HardDurationTicks,
        bool? NativeLandmaskApplied, long? EligibilityEvaluations, long? PrunedCandidates,
        long? FutureProbeMisses, RouteNativeRunMetadataDto? Routing,
        string? ForecastSource, string? PolarSource, string? DepartureSource,
        ForecastCoverageDto? ForecastCoverage = null,
        RouteCoastalPruningDiagnosticsDto? CoastalPruning = null,
        RouteCoastalSeedActionDto[]? CoastalSeedActions = null);
    private sealed record RouteCoastalSeedActionDto(
        [property: JsonRequired] double HeadingDegrees,
        [property: JsonRequired] long DurationTicks);
    private sealed record RouteCoastalPruningDiagnosticsDto(
        [property: JsonRequired] RouteCoastalPruningMode Mode,
        [property: JsonRequired] string Status,
        string? UnavailableReason,
        [property: JsonRequired] long SkippedParents,
        [property: JsonRequired] long DisconnectedCandidates,
        [property: JsonRequired] long HorizonCandidates,
        [property: JsonRequired] long IncumbentCandidates,
        [property: JsonRequired] long BoundUnavailable,
        [property: JsonRequired] long SeedEvaluations,
        [property: JsonRequired] long TopologyWork,
        DateTimeOffset? IncumbentArrival,
        string? SourceIdentity = null,
        string? DomainIdentity = null,
        string? SeedStatus = null,
        double? SpeedUpperKnots = null,
        long? TopologyCaps = null,
        double? NumericalMarginNauticalMiles = null,
        double? ClearanceNauticalMiles = null);
    private sealed record RouteNativeRunMetadataDto(
        string Objective, string QualityClaim, RouteSolver Solver, double DestinationLatitude, double DestinationLongitude,
        double ArrivalRadiusNauticalMiles, double RemainingDistanceNauticalMiles, double BoatSpeedFactor,
        double HeadingStepDegrees, double SpatialBucketNauticalMiles, long MaximumIntegrationStepTicks,
        bool StrategicRetention, bool LandAvoidance, RouteWindSampling WindSampling,
        RouteAbovePolarRangePolicy AbovePolarRange, double? MaximumForecastWindKnots,
        long TackPenaltyTicks, long GybePenaltyTicks, DateTimeOffset ForecastInitialization,
        DateTimeOffset ForecastFirstValid, DateTimeOffset ForecastLastValid, string[] Warnings);

    private sealed record RoutePlanEnvelope(int SchemaVersion, RoutePlanDto? Plan);

    private sealed record RoutePlanDto(
        Guid Id,
        string Name,
        RouteWaypointDto[] Waypoints,
        RoutePlanResultDto[] Results,
        Guid[] SailedLegIds,
        RouteCurrentPositionDto? CurrentPosition = null,
        Guid? ActiveLegId = null,
        RoutingSetupDto? Setup = null,
        RoutePlanningInputs? PlanningInputs = null);

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
        RouteLegOutcomeReason? DeferredInvalidationReason,
        RouteCalculationSessionDto? ExecutionSession = null,
        RouteLegOriginDto? Origin = null,
        RoutePlannedHoldDto? PlannedHold = null,
        RouteFailureDto? Failure = null);

    private sealed record RouteFailureDto(
        ModelRouteFailureStage Stage,
        string Code,
        string Message,
        RoutingFailureKind Kind,
        RouteAttemptAuditDto[] Attempts);

    private sealed record RouteResultDto(
        RouteRequestDto Request,
        ForecastModel Model,
        RoutePointDto[] Points,
        RouteDiagnosticsDto Diagnostics,
        RouteCompletion Completion,
        RouteLandAvoidanceDto LandAvoidance,
        RouteSolver Solver,
        RouteLatticeDiagnosticsDto? LatticeDiagnostics,
        RouteEnvironmentMetadataDto? Environment = null,
        RouteEnvironmentDiagnosticsDto? EnvironmentDiagnostics = null,
        RouteRunAuditDto? RunAudit = null,
        RouteNativeRunAuditDto? NativeAudit = null);

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
        double CumulativeDistanceNauticalMiles,
        RoutePointEnvironmentDto? Environment = null,
        double? PolarWindSpeedKnots = null,
        double? PolarWindDirectionDegrees = null);

    /// <summary>
    /// Ground-frame motion and sea state for one point. Absent when no
    /// environment ran, which is exactly how router-lib emits it.
    /// </summary>
    private sealed record RoutePointEnvironmentDto(
        double SpeedOverGroundKnots,
        double CourseOverGroundDegrees,
        double FlatWaterSpeedKnots,
        double? CurrentEastKnots = null,
        double? CurrentNorthKnots = null,
        double? SignificantWaveHeightMetres = null,
        double? WavePeriodSeconds = null,
        double? RelativeWaveAngleDegrees = null,
        double? PolarWindSpeedKnots = null,
        double? PolarWindDirectionDegrees = null);

    private sealed record RouteProviderMetadataDto(
        string Name,
        string Source,
        string Revision);

    private sealed record RouteEnvironmentMetadataDto(
        RouteEnvironmentSampling Sampling,
        RouteProviderMetadataDto? CurrentProvider,
        RouteProviderMetadataDto? WaveProvider,
        RouteProviderMetadataDto? SeaStateModel,
        RouteProviderMetadataDto? Landmask,
        RouteProviderMetadataDto? Exclusions,
        RouteMissingDataPolicy CurrentPolicy,
        RouteMissingDataPolicy WavePolicy,
        RouteMissingDataPolicy LandPolicy,
        double? LandResolutionNauticalMiles = null,
        double? LandInterpolationErrorNauticalMiles = null,
        double? LandClearanceNauticalMiles = null,
        RouteExclusionBoundaryPolicy? ExclusionBoundaryPolicy = null,
        int? ExclusionZoneCount = null,
        ulong? ExclusionRevision = null);

    private sealed record RouteEnvironmentDiagnosticsDto(
        long CurrentSamples,
        long CurrentRejections,
        long WaveSamples,
        long WaveRejections,
        long SeaStateEvaluations,
        long LandChecks,
        long LandDistanceQueries,
        long LandRejections,
        long ExclusionChecks,
        long ExclusionGeometryTests,
        long ExclusionRejections);

    private sealed record RouteDiagnosticsDto(
        long ExpandedNodes,
        long GeneratedCandidates,
        long RetainedCandidates,
        int TimeSteps,
        long? CalculationDurationTicks,
        long? EligibilityEvaluations = null,
        long? PrunedCandidates = null,
        long? FutureProbeMisses = null,
        RouteCoastalPruningDiagnosticsDto? CoastalPruning = null);

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
        bool RefinementFallback,
        long? ReRelaxedLabels = null,
        long? StaleQueueEntries = null,
        long? ActiveCells = null,
        long? ActiveFaces = null,
        double? AcceptedCorridorWidthNauticalMiles = null,
        int? DisconnectedRefinements = null,
        int? RegressedRefinements = null,
        LatticeRefinementFallbackReason? FallbackReason = null);
}
