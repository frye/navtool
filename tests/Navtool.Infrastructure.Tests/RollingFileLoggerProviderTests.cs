using System.Text.Json;
using Microsoft.Extensions.Logging;
using Navtool.Infrastructure;

namespace Navtool.Infrastructure.Tests;

public sealed class RollingFileLoggerProviderTests
{
    [Fact]
    public void Logger_writes_structured_json_lines()
    {
        using var directory = new TestDirectory();
        using var provider = new RollingFileLoggerProvider(
            new RollingFileLoggerOptions(directory.Path));
        var logger = provider.CreateLogger("Navtool.Tests");

        logger.LogInformation(new EventId(42, "forecast-ready"), "Stored {Count} steps", 12);

        var line = Assert.Single(File.ReadAllLines(provider.CurrentPath));
        using var document = JsonDocument.Parse(line);
        Assert.Equal("Information", document.RootElement.GetProperty("Level").GetString());
        Assert.Equal("Navtool.Tests", document.RootElement.GetProperty("Category").GetString());
        Assert.Equal(42, document.RootElement.GetProperty("EventId").GetInt32());
        Assert.Contains("Stored 12 steps", document.RootElement.GetProperty("Message").GetString());
    }

    [Fact]
    public void Logger_rolls_and_retains_the_configured_number_of_files()
    {
        using var directory = new TestDirectory();
        using var provider = new RollingFileLoggerProvider(
            new RollingFileLoggerOptions(
                directory.Path,
                maximumFileBytes: 300,
                retainedFileCount: 3));
        var logger = provider.CreateLogger("Navtool.Tests");

        for (var index = 0; index < 20; index++)
        {
            logger.LogInformation("Record {Index}: {Payload}", index, new string('x', 80));
        }

        var files = Directory.EnumerateFiles(directory.Path, "navtool*.log").ToArray();
        Assert.Equal(3, files.Length);
        Assert.Contains(provider.CurrentPath, files);
        Assert.All(
            files.SelectMany(File.ReadAllLines),
            line => Assert.Equal(JsonValueKind.Object, JsonDocument.Parse(line).RootElement.ValueKind));
    }

    [Fact]
    public void Logger_removes_archives_outside_a_reduced_retention_limit()
    {
        using var directory = new TestDirectory();
        File.WriteAllText(Path.Combine(directory.Path, "navtool.3.log"), "old");
        File.WriteAllText(Path.Combine(directory.Path, "navtool.4.log"), "old");
        using var provider = new RollingFileLoggerProvider(
            new RollingFileLoggerOptions(
                directory.Path,
                maximumFileBytes: 100,
                retainedFileCount: 3));

        Assert.False(File.Exists(Path.Combine(directory.Path, "navtool.3.log")));
        Assert.False(File.Exists(Path.Combine(directory.Path, "navtool.4.log")));
        Assert.True(Directory.EnumerateFiles(directory.Path, "navtool*.log").Count() <= 3);
    }

    [Fact]
    public void Logger_serializes_concurrent_writes_without_losing_records()
    {
        using var directory = new TestDirectory();
        using var provider = new RollingFileLoggerProvider(
            new RollingFileLoggerOptions(directory.Path, maximumFileBytes: 1024 * 1024));
        var logger = provider.CreateLogger("Navtool.Tests");

        Parallel.For(0, 100, index => logger.LogInformation("Record {Index}", index));

        Assert.Equal(100, File.ReadAllLines(provider.CurrentPath).Length);
    }
}
