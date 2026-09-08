using System.Text.Json;
using Navtool.Core;

namespace Navtool.Infrastructure;

internal static partial class NativeRouteJsonParser
{
    private static RouteNativeRunMetadata ParseNativeRunMetadata(JsonElement routing, RouteSolver solver) =>
        new(RequiredString(routing, "objective"), RequiredString(routing, "qualityClaim"), solver,
            ReadCoordinate(routing, "requestedDestination"), RequiredDouble(routing, "arrivalRadiusNm"),
            RequiredDouble(routing, "remainingDistanceNm"), RequiredDouble(routing, "boatSpeedFactor"),
            RequiredDouble(routing, "headingStepDegrees"), RequiredDouble(routing, "spatialBucketNm"),
            TimeSpan.FromMinutes(RequiredInt64(routing, "maximumIntegrationMinutes")),
            RequiredBoolean(routing, "strategicRetention"), RequiredBoolean(routing, "landAvoidance"),
            RequiredString(routing, "windSampling") == "midpoint" ? RouteWindSampling.Midpoint : RouteWindSampling.SegmentStart,
            RequiredString(routing, "abovePolarRange") == "no_speed" ? RouteAbovePolarRangePolicy.NoSpeed : RouteAbovePolarRangePolicy.Clamp,
            routing.GetProperty("maximumForecastWindKnots").ValueKind == JsonValueKind.Null ? null : RequiredDouble(routing, "maximumForecastWindKnots"),
            TimeSpan.FromSeconds(RequiredInt64(routing, "tackPenaltySeconds")),
            TimeSpan.FromSeconds(RequiredInt64(routing, "gybePenaltySeconds")),
            RequiredTimestamp(routing, "forecastInitialization"), RequiredTimestamp(routing, "forecastFirstValid"),
            RequiredTimestamp(routing, "forecastLastValid"),
            Required(routing, "warnings", JsonValueKind.Array).EnumerateArray().Select(warning => warning.GetString()!));

    internal static void RequireV2(string json)
    {
        try
        {
            using var document = JsonDocument.Parse(json);
            if (RequiredString(document.RootElement, "schema") != "route_result_v2")
                throw new NativeRouteFormatException("Configured ABI 8 routing requires route_result_v2 final output.");
        }
        catch (JsonException exception)
        {
            throw new NativeRouteFormatException("Configured native output is malformed JSON.", exception);
        }
    }

    internal static void ValidateEffectiveAudit(string json, ResolvedRoutingOptions options, NativeForecastMetadata forecast)
    {
        using var document = JsonDocument.Parse(json);
        var root = document.RootElement;
        var routing = Required(root, "routing", JsonValueKind.Object);
        if (Math.Abs(RequiredDouble(routing, "boatSpeedFactor") - options.PerformanceFactor) > 1e-9 ||
            Math.Abs(RequiredDouble(routing, "arrivalRadiusNm") - options.ArrivalRadiusNauticalMiles) > 1e-9 ||
            RequiredTimestamp(routing, "forecastInitialization") != forecast.InitializedAt ||
            RequiredTimestamp(routing, "forecastFirstValid") != forecast.FirstValidAt ||
            RequiredTimestamp(routing, "forecastLastValid") != forecast.LastValidAt ||
            RequiredInt64(routing, "maximumIntegrationMinutes") != (long)options.Search.MaximumIntegrationStep.TotalMinutes ||
            Math.Abs(RequiredDouble(routing, "headingStepDegrees") - options.Search.HeadingStepDegrees) > 1e-9 ||
            Math.Abs(RequiredDouble(routing, "spatialBucketNm") - options.Search.SpatialBucketNauticalMiles) > 1e-9 ||
            RequiredBoolean(routing, "strategicRetention") != options.Search.StrategicRetention ||
            RequiredInt64(routing, "tackPenaltySeconds") != (long)options.Optimization.Maneuver.TackPenalty.TotalSeconds ||
            RequiredInt64(routing, "gybePenaltySeconds") != (long)options.Optimization.Maneuver.GybePenalty.TotalSeconds ||
            RequiredString(routing, "abovePolarRange") != (options.Optimization.AbovePolarRange == RouteAbovePolarRangePolicy.NoSpeed ? "no_speed" : "clamp") ||
            RequiredString(routing, "windSampling") != (options.Optimization.WindSampling == RouteWindSampling.Midpoint ? "midpoint" : "segment_start"))
            throw new NativeRouteFormatException("Native run audit differs from the resolved boat, arrival, wind, or forecast settings.");
        var windLimit = routing.GetProperty("maximumForecastWindKnots");
        if ((windLimit.ValueKind == JsonValueKind.Null) != (options.Optimization.MaximumTrueWindSpeedKnots is null) ||
            windLimit.ValueKind != JsonValueKind.Null &&
            RequiredDouble(routing, "maximumForecastWindKnots") != options.Optimization.MaximumTrueWindSpeedKnots)
            throw new NativeRouteFormatException("Native forecast-wind limit differs from the configured ceiling.");
        if (options.HardDuration is { } duration &&
            RequiredTimestamp(Required(root, "arrival", JsonValueKind.Object), "time") -
            RequiredTimestamp(Required(root, "departure", JsonValueKind.Object), "time") > duration)
            throw new NativeRouteFormatException("Native route exceeds its hard search duration.");
    }

    private static void ValidateSchema(JsonElement root, RouteRequest request, RouteSolver solver)
    {
        if (!root.TryGetProperty("schema", out var schema))
        {
            // Deliberate legacy reader: historical output has no audit contract.
            return;
        }

        RequireKind(schema, JsonValueKind.String, "schema");
        if (schema.GetString() == "route_result_v1")
        {
            return;
        }
        if (schema.GetString() != "route_result_v2")
        {
            throw new NativeRouteFormatException($"Unsupported native route schema '{schema.GetString()}'.");
        }

        ValidateUniqueProperties(root);
        var completion = RequiredString(root, "completion");
        if (root.TryGetProperty("partial_reason", out _))
        {
            if (completion == "destination_reached" ||
                RequiredString(root, "partial_reason") != completion)
            {
                throw new NativeRouteFormatException("Native route completion contradicts partial_reason.");
            }
        }
        else if (completion != "destination_reached")
        {
            throw new NativeRouteFormatException("A native partial route must report partial_reason.");
        }

        var points = Required(root, "points", JsonValueKind.Array);
        if (points.GetArrayLength() == 0)
        {
            throw new NativeRouteFormatException("Native v2 route points must not be empty.");
        }
        var first = points[0];
        var last = points[points.GetArrayLength() - 1];
        var departure = Required(root, "departure", JsonValueKind.Object);
        var arrival = Required(root, "arrival", JsonValueKind.Object);
        var departureTime = RequiredTimestamp(departure, "time");
        var arrivalTime = RequiredTimestamp(arrival, "time");
        if (departureTime.ToUnixTimeSeconds() != request.DepartureTime.ToUnixTimeSeconds() ||
            departureTime != RequiredTimestamp(first, "time") ||
            arrivalTime != RequiredTimestamp(last, "time"))
        {
            throw new NativeRouteFormatException("Native route departure/arrival times do not match the request and physical endpoints.");
        }
        if (RequiredString(departure, "source") != "explicit_time")
        {
            throw new NativeRouteFormatException("Configured native routing must retain the explicit departure.");
        }
        var origin = ReadCoordinate(departure, "position");
        var endpoint = ReadCoordinate(arrival, "position");
        RequireSameCoordinate(origin, request.Origin, "requested origin");
        RequireSameCoordinate(origin, ReadCoordinate(first, "position"), "departure point");
        RequireSameCoordinate(endpoint, ReadCoordinate(last, "position"), "arrival point");
        _ = RequiredString(Required(root, "forecast", JsonValueKind.Object), "source");
        _ = RequiredString(Required(root, "polar", JsonValueKind.Object), "source");

        var run = Required(root, "routing", JsonValueKind.Object);
        if (RequiredString(run, "objective") != "earliest_arrival" ||
            RequiredString(run, "qualityClaim") != "best_found" ||
            RequiredString(run, "solver") != (solver == RouteSolver.IsochroneBeam
                ? "isochrone_beam" : "time_dependent_lattice"))
        {
            throw new NativeRouteFormatException("Native routing objective, quality claim, or solver does not match the configured request.");
        }
        RequireSameCoordinate(ReadCoordinate(run, "requestedDestination"), request.Destination, "requested destination");
        var radius = Positive(run, "arrivalRadiusNm");
        var remaining = Nonnegative(run, "remainingDistanceNm");
        var measuredRemaining = ForecastCorridor.GreatCircleDistanceNauticalMiles(endpoint, request.Destination);
        if (Math.Abs(remaining - measuredRemaining) > .01)
            throw new NativeRouteFormatException("Native remaining-distance audit contradicts the actual endpoint.");
        if (completion == "destination_reached" && remaining > radius + 1e-6)
        {
            throw new NativeRouteFormatException("Native destination completion lies outside the reported arrival area.");
        }
        _ = Positive(run, "boatSpeedFactor");
        if (Positive(run, "headingStepDegrees") > 360)
            throw new NativeRouteFormatException("Native heading step cannot exceed 360 degrees.");
        _ = Positive(run, "spatialBucketNm");
        if (RequiredInt64(run, "maximumIntegrationMinutes") == 0)
        {
            throw new NativeRouteFormatException("Native integration minutes must be positive.");
        }
        _ = RequiredBoolean(run, "strategicRetention");
        _ = RequiredBoolean(run, "landAvoidance");
        RequireEnum(run, "windSampling", "segment_start", "midpoint");
        RequireEnum(run, "abovePolarRange", "no_speed", "clamp");
        if (!run.TryGetProperty("maximumForecastWindKnots", out var maximumWind))
        {
            throw new NativeRouteFormatException("Native routing metadata lacks maximumForecastWindKnots.");
        }
        if (maximumWind.ValueKind != JsonValueKind.Null)
        {
            _ = Positive(run, "maximumForecastWindKnots");
        }
        _ = RequiredInt64(run, "tackPenaltySeconds");
        _ = RequiredInt64(run, "gybePenaltySeconds");
        var initialization = RequiredTimestamp(run, "forecastInitialization");
        var firstValid = RequiredTimestamp(run, "forecastFirstValid");
        var lastValid = RequiredTimestamp(run, "forecastLastValid");
        if (initialization > firstValid || firstValid > departureTime ||
            lastValid < firstValid || arrivalTime > lastValid)
        {
            throw new NativeRouteFormatException("Native routing forecast audit is inconsistent with physical route times.");
        }
        foreach (var warning in Required(run, "warnings", JsonValueKind.Array).EnumerateArray())
        {
            RequireKind(warning, JsonValueKind.String, "warning");
        }
        var diagnostics = Required(root, "diagnostics", JsonValueKind.Object);
        foreach (var name in new[] { "eligibilityEvaluations", "prunedCandidates", "futureProbeMisses" })
        {
            _ = RequiredInt64(diagnostics, name);
        }
        if (solver == RouteSolver.TimeDependentLattice && !root.TryGetProperty("latticeDiagnostics", out _))
        {
            throw new NativeRouteFormatException("Native lattice route is missing lattice diagnostics.");
        }
        if (root.TryGetProperty("latticeDiagnostics", out var lattice))
        {
            RequireKind(lattice, JsonValueKind.Object, "latticeDiagnostics");
            RequireEnum(lattice, "fallbackReason", "none", "disconnected", "regressed", "retry_exhausted");
        }
        ValidateEnvironmentBlocks(root, points);
    }

    private static void ValidateEnvironmentBlocks(JsonElement root, JsonElement points)
    {
        if (root.TryGetProperty("environmentDiagnostics", out var counters))
        {
            RequireKind(counters, JsonValueKind.Object, "environmentDiagnostics");
            foreach (var name in new[] { "currentSamples", "currentRejections", "waveSamples", "waveRejections",
                         "seaStateEvaluations", "landChecks", "landDistanceQueries", "landRejections",
                         "exclusionChecks", "exclusionGeometryTests", "exclusionRejections" })
            {
                _ = RequiredInt64(counters, name);
            }
        }
        if (root.TryGetProperty("environment", out var environment))
        {
            RequireKind(environment, JsonValueKind.Object, "environment");
            RequireEnum(environment, "sampling", "segment_start", "midpoint");
            var policies = Required(environment, "policies", JsonValueKind.Object);
            foreach (var name in new[] { "current", "wave", "land" })
            {
                RequireEnum(policies, name, "reject_transition", "fail_route");
            }
            foreach (var name in new[] { "currentProvider", "waveProvider", "seaStateModel", "landmask", "exclusions" })
            {
                if (!environment.TryGetProperty(name, out var provider))
                {
                    throw new NativeRouteFormatException($"Native environment lacks '{name}'.");
                }
                if (provider.ValueKind == JsonValueKind.Null) continue;
                RequireKind(provider, JsonValueKind.Object, name);
                foreach (var field in new[] { "name", "source", "revision" }) _ = RequiredString(provider, field);
            }
            foreach (var name in new[] { "landResolutionNauticalMiles", "landInterpolationErrorNauticalMiles", "landClearanceNauticalMiles" })
            {
                if (environment.TryGetProperty(name, out _)) _ = Nonnegative(environment, name);
            }
            foreach (var name in new[] { "exclusionZoneCount", "exclusionRevision" })
            {
                if (environment.TryGetProperty(name, out _)) _ = RequiredInt64(environment, name);
            }
            if (environment.TryGetProperty("exclusionBoundaryPolicy", out _))
                RequireEnum(environment, "exclusionBoundaryPolicy", "boundary_allowed", "boundary_excluded");
        }
        foreach (var point in points.EnumerateArray())
        {
            _ = ReadCoordinate(point, "position");
            if (!point.TryGetProperty("environment", out var audit)) continue;
            RequireKind(audit, JsonValueKind.Object, "point environment");
            foreach (var name in new[] { "speedOverGroundKnots", "courseOverGroundDegrees", "flatWaterSpeedKnots" })
                _ = RequiredDouble(audit, name);
            ValidateFieldGroup(audit, ["currentEastKnots", "currentNorthKnots", "polarWindSpeedKnots", "polarWindDirectionDegrees"]);
            ValidateFieldGroup(audit, ["significantWaveHeightMetres", "wavePeriodSeconds", "relativeWaveAngleDegrees"]);
        }
    }

    private static void ValidateFieldGroup(JsonElement parent, string[] fields)
    {
        if (!fields.Any(name => parent.TryGetProperty(name, out _))) return;
        foreach (var name in fields) _ = RequiredDouble(parent, name);
    }

    private static void ValidateUniqueProperties(JsonElement value)
    {
        if (value.ValueKind == JsonValueKind.Object)
        {
            var names = new HashSet<string>(StringComparer.Ordinal);
            foreach (var property in value.EnumerateObject())
            {
                if (!names.Add(property.Name))
                    throw new NativeRouteFormatException($"Duplicate native JSON field '{property.Name}'.");
                ValidateUniqueProperties(property.Value);
            }
        }
        else if (value.ValueKind == JsonValueKind.Array)
        {
            foreach (var item in value.EnumerateArray()) ValidateUniqueProperties(item);
        }
    }

    private static Coordinate ReadCoordinate(JsonElement parent, string name)
    {
        var value = Required(parent, name, JsonValueKind.Object);
        var latitude = RequiredDouble(value, "latitude");
        var longitude = RequiredDouble(value, "longitude");
        if (latitude is < -90 or > 90 || longitude is < -180 or > 180)
            throw new NativeRouteFormatException($"Native coordinate '{name}' is outside geographic limits.");
        return new Coordinate(latitude, longitude);
    }

    private static void RequireSameCoordinate(Coordinate actual, Coordinate expected, string description)
    {
        if (Math.Abs(actual.Latitude - expected.Latitude) > 1e-6 ||
            Math.Abs(Math.IEEERemainder(actual.Longitude - expected.Longitude, 360)) > 1e-6)
            throw new NativeRouteFormatException($"Native route does not match its {description}.");
    }

    private static void RequireEnum(JsonElement parent, string name, params string[] values)
    {
        if (!values.Contains(RequiredString(parent, name), StringComparer.Ordinal))
            throw new NativeRouteFormatException($"Unknown native enum '{name}'.");
    }

    private static double Nonnegative(JsonElement parent, string name)
    {
        var value = RequiredDouble(parent, name);
        if (value < 0) throw new NativeRouteFormatException($"Native field '{name}' must be nonnegative.");
        return value;
    }

    private static double Positive(JsonElement parent, string name)
    {
        var value = Nonnegative(parent, name);
        if (value == 0) throw new NativeRouteFormatException($"Native field '{name}' must be positive.");
        return value;
    }
}
