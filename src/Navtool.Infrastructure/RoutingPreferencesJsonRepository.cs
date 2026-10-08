using System.Text.Json;
using System.Text.Json.Serialization;
using Navtool.Core;

namespace Navtool.Infrastructure;

public sealed class RoutingPreferencesJsonRepository(string appDataRoot) : IRoutingPreferencesRepository
{
    private readonly string _path = Path.Combine(appDataRoot, "preferences", "routing.json");
    private static readonly JsonSerializerOptions Options = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        WriteIndented = true,
        Converters = { new JsonStringEnumConverter(allowIntegerValues: false), new BoundsConverter() }
    };

    public RoutingUserPreferences? Load()
    {
        try
        {
            using var stream = File.OpenRead(_path);
            var preferences = JsonSerializer.Deserialize<RoutingUserPreferences>(stream, Options) ??
                throw new InvalidDataException("Routing preferences are empty.");
            preferences.Validate();
            return preferences;
        }
        catch (FileNotFoundException) { return null; }
        catch (DirectoryNotFoundException) { return null; }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException or
            JsonException or ArgumentException or NotSupportedException or System.Security.SecurityException)
        {
            var message = $"Cannot read routing preferences at {_path}: {exception.Message}. The file is retained for recovery.";
            throw new InvalidDataException(message, exception);
        }
    }

    public void Save(RoutingUserPreferences preferences)
    {
        Load();
        preferences.Validate();
        var directory = Path.GetDirectoryName(_path)!;
        Directory.CreateDirectory(directory);
        var temporary = Path.Combine(directory, $".routing-{Guid.NewGuid():N}.tmp");
        try
        {
            using (var stream = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None))
            {
                JsonSerializer.Serialize(stream, preferences, Options);
                stream.Flush(flushToDisk: true);
            }
            File.Move(temporary, _path, overwrite: true);
        }
        finally
        {
            if (File.Exists(temporary)) File.Delete(temporary);
        }
    }

    private sealed class BoundsConverter : JsonConverter<GeographicBounds>
    {
        public override GeographicBounds Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
        {
            using var document = JsonDocument.ParseValue(ref reader);
            var root = document.RootElement;
            if (root.ValueKind != JsonValueKind.Object ||
                !root.TryGetProperty("south", out var south) || !root.TryGetProperty("north", out var north) ||
                !root.TryGetProperty("west", out var west) || !root.TryGetProperty("east", out var east))
                throw new JsonException("Regional bounds require south, north, west and east.");
            if (south.ValueKind != JsonValueKind.Number || !south.TryGetDouble(out var southValue) ||
                north.ValueKind != JsonValueKind.Number || !north.TryGetDouble(out var northValue) ||
                west.ValueKind != JsonValueKind.Number || !west.TryGetDouble(out var westValue) ||
                east.ValueKind != JsonValueKind.Number || !east.TryGetDouble(out var eastValue))
                throw new JsonException("Regional bounds must be numbers.");
            return new GeographicBounds(southValue, northValue, westValue, eastValue);
        }

        public override void Write(Utf8JsonWriter writer, GeographicBounds value, JsonSerializerOptions options)
        {
            writer.WriteStartObject();
            writer.WriteNumber("south", value.South);
            writer.WriteNumber("north", value.North);
            writer.WriteNumber("west", value.West);
            writer.WriteNumber("east", value.East);
            writer.WriteEndObject();
        }
    }
}
