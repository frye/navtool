using System.Text;
using Navtool.Infrastructure;

namespace Navtool.Infrastructure.Tests;

public sealed class AtomicFileCacheTests
{
    [Fact]
    public void CreateKey_is_deterministic_sanitized_and_collision_resistant()
    {
        var first = AtomicFileCache.CreateKey("NOAA GFS / wind", "run=00", "west=-70");
        var repeated = AtomicFileCache.CreateKey("NOAA GFS / wind", "run=00", "west=-70");
        var changed = AtomicFileCache.CreateKey("NOAA GFS / wind", "run=06", "west=-70");

        Assert.Equal(first, repeated);
        Assert.NotEqual(first, changed);
        Assert.Matches("^[a-z0-9._-]+$", first);
        Assert.DoesNotContain("/", first);
    }

    [Fact]
    public async Task Store_promotes_complete_artifact_and_observes_freshness()
    {
        using var directory = new TestDirectory();
        var cache = new AtomicFileCache(new AtomicFileCacheOptions(directory.Path));
        var now = new DateTimeOffset(2026, 7, 14, 12, 0, 0, TimeSpan.Zero);
        var key = AtomicFileCache.CreateKey("test", "artifact");

        var stored = await cache.StoreAsync(
            key,
            now,
            now.AddHours(1),
            Encoding.ASCII.GetBytes("GRIBcomplete7777"));

        Assert.True(File.Exists(stored.Path));
        Assert.Equal("GRIBcomplete7777", await File.ReadAllTextAsync(stored.Path));
        Assert.Empty(Directory.EnumerateFiles(directory.Path, "*.partial"));

        var fresh = await cache.TryGetFreshAsync(key, now.AddMinutes(59));
        var stale = await cache.TryGetFreshAsync(key, now.AddHours(1));
        Assert.NotNull(fresh);
        Assert.Null(stale);
        Assert.Equal(stored.LengthBytes, fresh!.LengthBytes);
    }

    [Fact]
    public async Task Store_failure_leaves_no_promoted_or_partial_artifact()
    {
        using var directory = new TestDirectory();
        var cache = new AtomicFileCache(new AtomicFileCacheOptions(directory.Path));
        var now = DateTimeOffset.UtcNow;
        var key = AtomicFileCache.CreateKey("test", "failure");

        await Assert.ThrowsAsync<InvalidDataException>(async () =>
            await cache.StoreAsync(
                key,
                now,
                now.AddHours(1),
                async (stream, token) =>
                {
                    await stream.WriteAsync("partial"u8.ToArray(), token);
                    throw new InvalidDataException("injected");
                }));

        Assert.Empty(Directory.EnumerateFiles(directory.Path));
    }

    [Fact]
    public async Task Eviction_is_bounded_and_removes_oldest_entry()
    {
        using var directory = new TestDirectory();
        var cache = new AtomicFileCache(
            new AtomicFileCacheOptions(directory.Path, maximumBytes: 20, maximumEntries: 2));
        var now = new DateTimeOffset(2026, 7, 14, 12, 0, 0, TimeSpan.Zero);
        var first = AtomicFileCache.CreateKey("test", "one");
        var second = AtomicFileCache.CreateKey("test", "two");
        var third = AtomicFileCache.CreateKey("test", "three");

        await cache.StoreAsync(first, now, now.AddHours(1), "12345678"u8.ToArray());
        await cache.StoreAsync(second, now.AddMinutes(1), now.AddHours(1), "12345678"u8.ToArray());
        await cache.StoreAsync(third, now.AddMinutes(2), now.AddHours(1), "12345678"u8.ToArray());

        Assert.Null(await cache.TryGetFreshAsync(first, now.AddMinutes(3)));
        Assert.NotNull(await cache.TryGetFreshAsync(second, now.AddMinutes(3)));
        Assert.NotNull(await cache.TryGetFreshAsync(third, now.AddMinutes(3)));
        Assert.Equal(2, Directory.EnumerateFiles(directory.Path, "*.grib2").Count());
    }

    [Fact]
    public async Task Nonexpiring_lookup_survives_restart_and_touches_entry_for_lru()
    {
        using var directory = new TestDirectory();
        var now = new DateTimeOffset(2026, 7, 14, 12, 0, 0, TimeSpan.Zero);
        var first = AtomicFileCache.CreateKey("test", "first");
        var second = AtomicFileCache.CreateKey("test", "second");
        var third = AtomicFileCache.CreateKey("test", "third");
        var options = new AtomicFileCacheOptions(directory.Path, maximumBytes: 32, maximumEntries: 2);

        var writer = new AtomicFileCache(options);
        await writer.StoreAsync(first, now, now.AddMinutes(1), "first"u8.ToArray());
        await writer.StoreAsync(second, now.AddMinutes(1), now.AddMinutes(2), "second"u8.ToArray());

        var restarted = new AtomicFileCache(options);
        Assert.NotNull(await restarted.TryGetAsync(first, now.AddHours(2)));
        await restarted.StoreAsync(third, now.AddHours(2), DateTimeOffset.MaxValue, "third"u8.ToArray());

        Assert.NotNull(await restarted.TryGetAsync(first, now.AddHours(2)));
        Assert.Null(await restarted.TryGetAsync(second, now.AddHours(2)));
        Assert.NotNull(await restarted.TryGetAsync(third, now.AddHours(2)));
    }

    [Fact]
    public void Startup_sweep_does_not_delete_partial_owned_by_another_writer()
    {
        using var directory = new TestDirectory();
        var partial = Path.Combine(directory.Path, ".cache.inflight.partial");
        using (var writer = new FileStream(
                   partial,
                   FileMode.CreateNew,
                   FileAccess.ReadWrite,
                   FileShare.None))
        {
            writer.WriteByte(1);
            _ = new AtomicFileCache(new AtomicFileCacheOptions(directory.Path));
            Assert.True(File.Exists(partial));
        }

        _ = new AtomicFileCache(new AtomicFileCacheOptions(directory.Path));
        Assert.False(File.Exists(partial));
    }
}
