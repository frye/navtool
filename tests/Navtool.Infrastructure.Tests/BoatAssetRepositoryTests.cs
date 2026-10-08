using Navtool.Core;

namespace Navtool.Infrastructure.Tests;

public sealed class BoatAssetRepositoryTests
{
    [Theory]
    [InlineData("fast.csv", BoatPolarFormat.NativeMatrix)]
    [InlineData("expedition.pol", BoatPolarFormat.Expedition)]
    public async Task Native_parser_validates_imported_assets_and_reloads_managed_copy(
        string fileName, BoatPolarFormat format)
    {
        var bridge = NativeIntegration.Bridge();
        var fixture = NativeIntegration.Fixture(fileName);
        if (bridge is null || fixture is null) return;
        using var directory = new TestDirectory();
        var repository = new BoatAssetRepository(directory.Path, bridge);

        var asset = await repository.ImportAsync(fixture, format);
        var resolved = await new BoatAssetRepository(directory.Path, bridge).ResolveAsync(asset);
        var frozen = Path.Combine(directory.Path, "frozen.polar");
        await File.WriteAllBytesAsync(frozen, resolved.PolarBytes.ToArray());
        using var native = bridge.LoadPolar(frozen, asset.RequestedFormat);

        Assert.False(native.IsClosed);
        Assert.Equal(format, asset.RequestedFormat);
        Assert.True(asset.Validation.MaximumWindSpeedKnots > 0);
        Assert.Null(asset.Validation.ResolvedFormat);
    }

    [Fact]
    public async Task Native_invalid_polar_never_publishes_imported_or_demo_asset()
    {
        var bridge = NativeIntegration.Bridge();
        var fixture = NativeIntegration.Fixture("invalid.pol");
        if (bridge is null || fixture is null) return;
        using var directory = new TestDirectory();
        var repository = new BoatAssetRepository(directory.Path, bridge);

        var failure = await Assert.ThrowsAsync<NativeRouterException>(async () =>
            await repository.ImportAsync(fixture, BoatPolarFormat.Automatic));

        Assert.Equal(RoutingFailureKind.InvalidBoat, failure.Kind);
        Assert.Empty(Directory.EnumerateFiles(repository.RootDirectory));
    }

    [Fact]
    public async Task Imported_asset_survives_source_deletion_and_repository_restart()
    {
        using var directory = new TestDirectory();
        var path = Path.Combine(directory.Path, "My boat.pol");
        var content = "native parser test input"u8.ToArray();
        await File.WriteAllBytesAsync(path, content);
        var formats = new List<BoatPolarFormat>();
        var repository = Create(directory.Path, (copy, format, token) =>
        {
            Assert.NotEqual(path, copy);
            Assert.Equal(content, File.ReadAllBytes(copy));
            formats.Add(format);
            return new BoatValidationSummary("Native validation");
        });

        var asset = await repository.ImportAsync(path, BoatPolarFormat.Expedition);
        File.Delete(path);
        var restored = await Create(directory.Path).ResolveAsync(asset);

        Assert.Equal(BoatAssetKind.Imported, asset.Kind);
        Assert.Equal("My boat.pol", asset.SourceDisplayName);
        Assert.Equal(new[] { BoatPolarFormat.Expedition }, formats);
        Assert.Equal(content, restored.PolarBytes.ToArray());
        Assert.Single(Directory.EnumerateFiles(repository.RootDirectory, "*.polar"));
        Assert.Empty(Directory.EnumerateFiles(repository.RootDirectory, "*.tmp"));
    }

    [Fact]
    public async Task Source_changes_during_validation_do_not_change_the_imported_asset()
    {
        using var directory = new TestDirectory();
        var path = Path.Combine(directory.Path, "boat.pol");
        var original = "validated immutable polar"u8.ToArray();
        await File.WriteAllBytesAsync(path, original);
        var repository = Create(directory.Path, (copy, _, _) =>
        {
            File.WriteAllText(path, "source changed");
            Assert.Equal(original, File.ReadAllBytes(copy));
            return new BoatValidationSummary("Validated copied bytes");
        });

        var asset = await repository.ImportAsync(path, BoatPolarFormat.NativeMatrix);
        var resolved = await repository.ResolveAsync(asset);

        Assert.Equal(original, resolved.PolarBytes.ToArray());
    }

    [Fact]
    public async Task Cancellation_after_native_validation_does_not_publish_an_asset()
    {
        using var directory = new TestDirectory();
        var path = Path.Combine(directory.Path, "boat.pol");
        await File.WriteAllTextAsync(path, "polar");
        using var cancellation = new CancellationTokenSource();
        var repository = Create(directory.Path, (_, _, _) =>
        {
            cancellation.Cancel();
            return new BoatValidationSummary("Valid");
        });

        await Assert.ThrowsAnyAsync<OperationCanceledException>(async () =>
            await repository.ImportAsync(path, BoatPolarFormat.NativeMatrix, cancellation.Token));

        Assert.Empty(Directory.EnumerateFiles(repository.RootDirectory));
    }

    [Fact]
    public async Task Identical_imports_share_bytes_but_preserve_requested_format()
    {
        using var directory = new TestDirectory();
        var path = Path.Combine(directory.Path, "boat.pol");
        await File.WriteAllTextAsync(path, "same bytes");
        var repository = Create(directory.Path);

        var first = await repository.ImportAsync(path, BoatPolarFormat.Automatic);
        var second = await repository.ImportAsync(path, BoatPolarFormat.NativeMatrix);

        Assert.Equal(first.ContentIdentity, second.ContentIdentity);
        Assert.Equal(BoatPolarFormat.NativeMatrix, second.RequestedFormat);
        Assert.Single(Directory.EnumerateFiles(repository.RootDirectory, "*.polar"));
    }

    [Fact]
    public async Task Invalid_or_cancelled_import_does_not_publish_an_asset()
    {
        using var directory = new TestDirectory();
        var path = Path.Combine(directory.Path, "invalid.pol");
        await File.WriteAllTextAsync(path, "invalid bytes");
        var repository = Create(directory.Path, (_, _, _) =>
            throw new RoutingException(RoutingFailureKind.InvalidBoat, "Native parser rejected the polar."));

        await Assert.ThrowsAsync<RoutingException>(async () =>
            await repository.ImportAsync(path, BoatPolarFormat.Automatic));
        Assert.Empty(Directory.EnumerateFiles(repository.RootDirectory));

        using var cancellation = new CancellationTokenSource();
        cancellation.Cancel();
        await Assert.ThrowsAnyAsync<OperationCanceledException>(async () =>
            await repository.ImportAsync(path, BoatPolarFormat.Automatic, cancellation.Token));
        Assert.Empty(Directory.EnumerateFiles(repository.RootDirectory));
    }

    [Fact]
    public async Task Missing_or_changed_assets_are_not_replaced_by_demo()
    {
        using var directory = new TestDirectory();
        var path = Path.Combine(directory.Path, "boat.pol");
        await File.WriteAllTextAsync(path, "intended polar");
        var repository = Create(directory.Path);
        var asset = await repository.ImportAsync(path, BoatPolarFormat.NativeMatrix);
        var stored = Assert.Single(Directory.EnumerateFiles(repository.RootDirectory, "*.polar"));
        await File.WriteAllTextAsync(stored, "replacement polar");

        var changed = await Assert.ThrowsAsync<RoutingException>(async () => await repository.ResolveAsync(asset));
        Assert.Equal(RoutingFailureKind.InvalidBoat, changed.Kind);
        File.Delete(stored);
        var missing = await Assert.ThrowsAsync<RoutingException>(async () => await repository.ResolveAsync(asset));
        Assert.Equal(RoutingFailureKind.InvalidBoat, missing.Kind);
    }

    [Fact]
    public async Task Asset_identity_cannot_escape_the_managed_directory()
    {
        using var directory = new TestDirectory();
        var asset = new BoatAsset("../outside", "boat", BoatAssetKind.Imported,
            BoatPolarFormat.Automatic, new BoatValidationSummary("old metadata"));

        await Assert.ThrowsAsync<RoutingException>(async () => await Create(directory.Path).ResolveAsync(asset));
    }

    [Fact]
    public async Task Demo_is_explicit_and_bound_to_native_revision()
    {
        using var directory = new TestDirectory();
        var repository = Create(directory.Path);
        var demo = await repository.GetDemoAsync();
        var resolved = await repository.ResolveAsync(demo);

        Assert.Equal(BoatAssetKind.Demo, demo.Kind);
        Assert.Contains("Demo", demo.SourceDisplayName);
        Assert.Empty(resolved.PolarBytes);
        var older = new BoatAsset("demo:old", demo.SourceDisplayName, BoatAssetKind.Demo,
            demo.RequestedFormat, demo.Validation);
        await Assert.ThrowsAsync<RoutingException>(async () => await repository.ResolveAsync(older));
    }

    private static BoatAssetRepository Create(string root,
        Func<string, BoatPolarFormat, CancellationToken, BoatValidationSummary>? inspect = null) =>
        new(root, inspect ?? ((_, _, _) => new BoatValidationSummary("Native validation")),
            _ => new BoatValidationSummary("Demonstration data"), "demo:test-revision");
}
