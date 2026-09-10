using System.Text.Json.Nodes;
using Navtool.Core;
using Navtool.Infrastructure;

namespace Navtool.Infrastructure.Tests;

public sealed class RoutingPreferencesJsonRepositoryTests
{
    [Theory]
    [InlineData(false, "{broken")]
    [InlineData(true, "{broken")]
    [InlineData(false, "{\"schemaVersion\":999,\"setup\":{},\"planning\":{},\"advanced\":{}}")]
    [InlineData(true, "{\"schemaVersion\":999,\"setup\":{},\"planning\":{},\"advanced\":{}}")]
    [InlineData(false, "{\"schemaVersion\":1,\"setup\":{},\"planning\":{\"passageDays\":12},\"advanced\":{}}")]
    [InlineData(true, "{\"schemaVersion\":1,\"setup\":{},\"planning\":{\"passageDays\":12},\"advanced\":{}}")]
    public void Save_rechecks_files_changed_after_a_successful_load(bool existed, string invalid)
    {
        using var directory = new TestDirectory();
        var repository = new RoutingPreferencesJsonRepository(directory.Path);
        if (existed)
        {
            repository.Save(new());
            Assert.NotNull(repository.Load());
        }
        else
        {
            Assert.Null(repository.Load());
        }
        var path = Path.Combine(directory.Path, "preferences", "routing.json");
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, invalid);
        var original = File.ReadAllBytes(path);

        var exception = Assert.Throws<InvalidDataException>(() => repository.Save(new()));

        Assert.Contains("retained for recovery", exception.Message);
        Assert.Equal(original, File.ReadAllBytes(path));
        Assert.Empty(Directory.EnumerateFiles(Path.GetDirectoryName(path)!, "*.tmp"));
    }

    [Fact]
    public void Save_can_resume_after_the_retained_file_is_repaired()
    {
        using var directory = new TestDirectory();
        var repository = new RoutingPreferencesJsonRepository(directory.Path);
        repository.Save(new());
        var path = Path.Combine(directory.Path, "preferences", "routing.json");
        var valid = File.ReadAllText(path);
        File.WriteAllText(path, "{broken");
        Assert.Throws<InvalidDataException>(() => repository.Load());
        Assert.Throws<InvalidDataException>(() => repository.Save(new()));
        File.WriteAllText(path, valid);
        var updated = new RoutingUserPreferences
        {
            Planning = new RoutePlanningInputs { PassageDays = 4 }
        };

        repository.Save(updated);

        Assert.Equal(updated, new RoutingPreferencesJsonRepository(directory.Path).Load());
    }

    [Theory]
    [InlineData("planning", "forecastSource", (int)PlanningForecastSource.Download)]
    [InlineData("setup", "quality", (int)RoutingQuality.NativeBalanced)]
    [InlineData("advanced", "selectedRouteSolver", (int)RouteSolver.IsochroneBeam)]
    public void Numeric_enums_are_rejected_and_retained_for_recovery(string section, string property, int value)
    {
        using var directory = new TestDirectory();
        new RoutingPreferencesJsonRepository(directory.Path).Save(new());
        var path = Path.Combine(directory.Path, "preferences", "routing.json");
        var document = JsonNode.Parse(File.ReadAllText(path))!;
        document[section]![property] = value;
        var invalid = document.ToJsonString();
        File.WriteAllText(path, invalid);

        var repository = new RoutingPreferencesJsonRepository(directory.Path);
        Assert.Throws<InvalidDataException>(() => repository.Load());
        Assert.Throws<InvalidDataException>(() => repository.Save(new()));
        Assert.Throws<InvalidDataException>(() => new RoutingPreferencesJsonRepository(directory.Path).Save(new()));
        Assert.Equal(invalid, File.ReadAllText(path));
    }

    [Fact]
    public void Missing_preferences_are_distinct_from_corrupt_preferences()
    {
        using var directory = new TestDirectory();
        var repository = new RoutingPreferencesJsonRepository(directory.Path);
        Assert.Null(repository.Load());
        var path = Path.Combine(directory.Path, "preferences", "routing.json");
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, "{broken");
        Assert.Throws<InvalidDataException>(() => repository.Load());
        Assert.Throws<InvalidDataException>(() => repository.Save(new()));
        Assert.Equal("{broken", File.ReadAllText(path));
    }

    [Theory]
    [InlineData(true)]
    [InlineData(false)]
    public void Everyday_and_inactive_advanced_values_round_trip_without_asset_access(bool selectDownloadModel)
    {
        using var directory = new TestDirectory();
        var repository = new RoutingPreferencesJsonRepository(directory.Path);
        var boat = new BoatAsset("sha256:missing", "Explicit imported boat", BoatAssetKind.Imported,
            BoatPolarFormat.Expedition, new BoatValidationSummary("Validated when imported"));
        var preferences = new RoutingUserPreferences
        {
            Setup = new RoutingSetupPreferences
            {
                Boat = boat, Quality = RoutingQuality.NativeAccurate, PerformanceFactor = 0.9,
                ArrivalRadiusNauticalMiles = 2, ForecastPolicy = ForecastRefreshPolicy.LatestAvailable,
                LandSource = RoutingLandSource.RegionalGshhg,
                RegionalLand = new RouteRegionalLandPolicy(Path.Combine(directory.Path, "missing.b"),
                    new string('a', 64), new GeographicBounds(47, 50, -126, -122), 1, 0.2, 60,
                    250_000, 10_000_000, 100_000_000),
                HardDurationHours = 168
            },
            Planning = new RoutePlanningInputs
            {
                PassageDays = 5, PassageHours = 4, UseNoaa = false, UseEcmwf = selectDownloadModel,
                ForecastSource = PlanningForecastSource.LocalFile,
                LocalGribPath = Path.Combine(directory.Path, "missing.grib")
            },
            Advanced = new AdvancedRoutingPreferences { TackPenaltySeconds = 25, CurrentEastKnots = 2 }
        };
        repository.Save(preferences);
        var loaded = new RoutingPreferencesJsonRepository(directory.Path).Load();
        Assert.Equal(preferences, loaded);
        Assert.Empty(Directory.EnumerateFiles(Path.Combine(directory.Path, "preferences"), "*.tmp"));
    }

    [Fact]
    public void Unsupported_schema_is_retained_and_invalid_edits_do_not_replace_last_valid_preferences()
    {
        using var directory = new TestDirectory();
        var repository = new RoutingPreferencesJsonRepository(directory.Path);
        repository.Save(new());
        Assert.Throws<ArgumentException>(() => repository.Save(new()
        {
            Planning = new RoutePlanningInputs { PassageDays = 12 }
        }));
        Assert.Equal(3, repository.Load()!.Planning.PassageDays);
        var path = Path.Combine(directory.Path, "preferences", "routing.json");
        var future = File.ReadAllText(path).Replace("\"schemaVersion\": 1", "\"schemaVersion\": 999");
        File.WriteAllText(path, future);
        Assert.Throws<InvalidDataException>(() => repository.Load());
        Assert.Throws<InvalidDataException>(() => repository.Save(new()));
        Assert.Equal(future, File.ReadAllText(path));
    }

    [Fact]
    public void Write_failure_is_reported()
    {
        using var directory = new TestDirectory();
        File.WriteAllText(Path.Combine(directory.Path, "preferences"), "Not a directory");
        Assert.Throws<IOException>(() => new RoutingPreferencesJsonRepository(directory.Path).Save(new()));
    }

    [Theory]
    [InlineData("{}")]
    [InlineData("null")]
    [InlineData("{\"schemaVersion\":1,\"setup\":null,\"planning\":{},\"advanced\":{}}")]
    public void Incomplete_documents_are_retained_even_when_save_is_called_without_load(string json)
    {
        using var directory = new TestDirectory();
        var path = Path.Combine(directory.Path, "preferences", "routing.json");
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, json);
        var repository = new RoutingPreferencesJsonRepository(directory.Path);
        Assert.Throws<InvalidDataException>(() => repository.Save(new()));
        Assert.Equal(json, File.ReadAllText(path));
    }

    private sealed class TestDirectory : IDisposable
    {
        public string Path { get; } = System.IO.Path.Combine(System.IO.Path.GetTempPath(), $"navtool-preferences-{Guid.NewGuid():N}");
        public TestDirectory() => Directory.CreateDirectory(Path);
        public void Dispose() => Directory.Delete(Path, recursive: true);
    }
}
