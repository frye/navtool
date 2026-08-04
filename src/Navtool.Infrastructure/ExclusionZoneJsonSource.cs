using System.Globalization;
using System.Text.Json;
using Navtool.Core;

namespace Navtool.Infrastructure;

/// <summary>
/// Loads exclusion zone sets from JSON documents.
/// </summary>
/// <remarks>
/// Every parse failure throws. An exclusion set that cannot be read must never
/// degrade into an empty set, because an empty set is indistinguishable from
/// unrestricted water and would silently route through the very area the
/// operator asked to avoid.
/// </remarks>
public static class ExclusionZoneJsonSource
{
    /// <summary>Filename of the bundled example set, relative to the data directory.</summary>
    public const string AntarcticExclusionZoneFileName = "antarctic-exclusion-zone.json";

    private const string AntarcticExclusionZoneResourceName =
        "Navtool.Infrastructure.Assets.antarctic-exclusion-zone.json";

    /// <summary>
    /// The bundled illustrative Antarctic exclusion zone. It models a 62°S ice
    /// limit as two hemispheric polygons so the region never has to be
    /// expressed as a pole-wrapping ring. It is an example, not a navigational
    /// source: replace it with the notice of race for a real event.
    /// </summary>
    public static RouteExclusionOptions LoadAntarcticExample()
    {
        using var stream = typeof(ExclusionZoneJsonSource).Assembly
            .GetManifestResourceStream(AntarcticExclusionZoneResourceName) ??
            throw new InvalidOperationException(
                "The bundled Antarctic exclusion zone resource is missing.");
        using var reader = new StreamReader(stream);
        return Load(reader.ReadToEnd());
    }

    public static RouteExclusionOptions Load(string json)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(json);
        using var document = JsonDocument.Parse(json);
        var root = document.RootElement;
        if (root.ValueKind != JsonValueKind.Object)
        {
            throw new InvalidDataException("An exclusion zone document must be a JSON object.");
        }

        var metadata = new RouteProviderMetadata(
            RequiredString(root, "name"),
            RequiredString(root, "source"),
            OptionalString(root, "revision") ?? string.Empty);
        var boundaryPolicy = ParseBoundaryPolicy(OptionalString(root, "boundaryPolicy"));

        if (!root.TryGetProperty("zones", out var zonesElement) ||
            zonesElement.ValueKind != JsonValueKind.Array)
        {
            throw new InvalidDataException("An exclusion zone document must contain a 'zones' array.");
        }

        var zones = new List<RouteExclusionZone>();
        foreach (var element in zonesElement.EnumerateArray())
        {
            zones.Add(ParseZone(element));
        }

        if (zones.Count == 0)
        {
            throw new InvalidDataException(
                "An exclusion zone document must declare at least one zone. Remove the " +
                "document instead of shipping an empty set.");
        }

        return new RouteExclusionOptions(zones, metadata, boundaryPolicy);
    }

    public static async ValueTask<RouteExclusionOptions> LoadFileAsync(
        string path,
        CancellationToken cancellationToken = default)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(path);
        var json = await File.ReadAllTextAsync(path, cancellationToken).ConfigureAwait(false);
        try
        {
            return Load(json);
        }
        catch (Exception exception) when (
            exception is JsonException or InvalidDataException or ArgumentException)
        {
            throw new InvalidDataException(
                $"The exclusion zone document '{path}' is invalid: {exception.Message}",
                exception);
        }
    }

    private static RouteExclusionZone ParseZone(JsonElement element)
    {
        if (element.ValueKind != JsonValueKind.Object)
        {
            throw new InvalidDataException("Each exclusion zone must be a JSON object.");
        }

        var revision = 1UL;
        if (element.TryGetProperty("revision", out var revisionElement))
        {
            if (revisionElement.ValueKind != JsonValueKind.Number ||
                !revisionElement.TryGetUInt64(out revision))
            {
                throw new InvalidDataException(
                    "An exclusion zone revision must be a nonnegative integer.");
            }
        }

        if (!element.TryGetProperty("polygons", out var polygonsElement) ||
            polygonsElement.ValueKind != JsonValueKind.Array)
        {
            throw new InvalidDataException("An exclusion zone must contain a 'polygons' array.");
        }

        var polygons = new List<RouteExclusionPolygon>();
        foreach (var polygon in polygonsElement.EnumerateArray())
        {
            polygons.Add(ParsePolygon(polygon));
        }

        return new RouteExclusionZone(
            RequiredString(element, "identifier"),
            RequiredString(element, "source"),
            polygons,
            revision,
            ParseTimestamp(element, "activeFrom"),
            ParseTimestamp(element, "activeUntil"));
    }

    private static RouteExclusionPolygon ParsePolygon(JsonElement element)
    {
        if (element.ValueKind != JsonValueKind.Object)
        {
            throw new InvalidDataException("Each exclusion polygon must be a JSON object.");
        }

        if (!element.TryGetProperty("outer", out var outerElement))
        {
            throw new InvalidDataException("An exclusion polygon must declare an 'outer' ring.");
        }

        var holes = new List<RouteExclusionRing>();
        if (element.TryGetProperty("holes", out var holesElement))
        {
            if (holesElement.ValueKind != JsonValueKind.Array)
            {
                throw new InvalidDataException("Exclusion polygon 'holes' must be an array.");
            }

            foreach (var hole in holesElement.EnumerateArray())
            {
                holes.Add(ParseRing(hole));
            }
        }

        return new RouteExclusionPolygon(ParseRing(outerElement), holes);
    }

    private static RouteExclusionRing ParseRing(JsonElement element)
    {
        if (element.ValueKind != JsonValueKind.Array)
        {
            throw new InvalidDataException(
                "An exclusion ring must be an array of [longitude, latitude] pairs.");
        }

        var vertices = new List<Coordinate>();
        foreach (var vertex in element.EnumerateArray())
        {
            if (vertex.ValueKind != JsonValueKind.Array ||
                vertex.GetArrayLength() != 2)
            {
                throw new InvalidDataException(
                    "Each exclusion ring vertex must be a [longitude, latitude] pair.");
            }

            // GeoJSON axis order, so longitude comes first.
            var longitude = vertex[0].GetDouble();
            var latitude = vertex[1].GetDouble();
            vertices.Add(new Coordinate(latitude, longitude));
        }

        // A closing vertex repeating the first is idiomatic in GeoJSON but
        // router-lib closes rings implicitly, so drop the duplicate.
        if (vertices.Count > 1 &&
            vertices[0].IsSameLocation(vertices[^1]))
        {
            vertices.RemoveAt(vertices.Count - 1);
        }

        return new RouteExclusionRing(vertices);
    }

    private static RouteExclusionBoundaryPolicy ParseBoundaryPolicy(string? value) =>
        value switch
        {
            null or "boundary_excluded" => RouteExclusionBoundaryPolicy.BoundaryExcluded,
            "boundary_allowed" => RouteExclusionBoundaryPolicy.BoundaryAllowed,
            _ => throw new InvalidDataException(
                $"'{value}' is not a recognized exclusion boundary policy.")
        };

    private static DateTimeOffset? ParseTimestamp(JsonElement parent, string name)
    {
        if (!parent.TryGetProperty(name, out var value) ||
            value.ValueKind == JsonValueKind.Null)
        {
            return null;
        }

        if (value.ValueKind != JsonValueKind.String ||
            !DateTimeOffset.TryParse(
                value.GetString(),
                CultureInfo.InvariantCulture,
                DateTimeStyles.AssumeUniversal | DateTimeStyles.AdjustToUniversal,
                out var parsed))
        {
            throw new InvalidDataException(
                $"Exclusion zone field '{name}' must be an ISO 8601 timestamp.");
        }

        return parsed;
    }

    private static string RequiredString(JsonElement parent, string name)
    {
        if (!parent.TryGetProperty(name, out var value) ||
            value.ValueKind != JsonValueKind.String ||
            string.IsNullOrWhiteSpace(value.GetString()))
        {
            throw new InvalidDataException(
                $"An exclusion zone document requires a non-empty '{name}'.");
        }

        return value.GetString()!;
    }

    private static string? OptionalString(JsonElement parent, string name) =>
        parent.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.String
            ? value.GetString()
            : null;
}
