using Navtool.Core;
using Navtool.Infrastructure;

namespace Navtool.Infrastructure.Tests;

public sealed class RoutingPreferencesJsonRepositoryTests
{
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

    [Fact]
    public void Everyday_and_inactive_advanced_values_round_trip_without_asset_access()
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
                PassageDays = 5, PassageHours = 4, UseNoaa = false, UseEcmwf = true,
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
