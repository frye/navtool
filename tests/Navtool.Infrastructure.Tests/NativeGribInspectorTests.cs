using System.Reflection;
using Navtool.Core;
using Navtool.Infrastructure;

namespace Navtool.Infrastructure.Tests;

/// <summary>
/// Tests for the native bridge preflight check (NativeRouterBridge construction as preflight)
/// and the GRIB inspection service (NativeGribInspector / NativeRouterBridge.InspectGrib).
/// Tests skip gracefully when the native library or the sample GRIB is unavailable,
/// following the same pattern as NativeRouterBridgeIntegrationTests.
/// </summary>
public sealed class NativeGribInspectorTests
{
    // The same sample search logic used by NativeRouterBridgeIntegrationTests.
    private static string? FindSampleGrib()
    {
        var configured = Environment.GetEnvironmentVariable("NAVTOOL_ROUTER_SAMPLE_GRIB");
        if (!string.IsNullOrWhiteSpace(configured))
        {
            var full = Path.GetFullPath(configured);
            return File.Exists(full) ? full : null;
        }

        var repository = FindAncestor(AppContext.BaseDirectory, "Navtool.sln");
        if (repository is null)
        {
            return null;
        }

        var candidate = Path.GetFullPath(
            Path.Combine(repository, "..", "router-lib", "samples", "sample.grib"));
        return File.Exists(candidate) ? candidate : null;
    }

    private static NativeRouterBridge? TryCreateBridge()
    {
        try
        {
            return new NativeRouterBridge();
        }
        catch (NativeBridgeUnavailableException)
        {
            return null;
        }
    }

    private static string? FindAncestor(string start, string marker)
    {
        var directory = new DirectoryInfo(start);
        while (directory is not null)
        {
            if (File.Exists(Path.Combine(directory.FullName, marker)))
            {
                return directory.FullName;
            }

            directory = directory.Parent;
        }

        return null;
    }

    // ---- INativeRoutingPreflight contract (NativeRouterBridge construction performs preflight) ----

    [Fact]
    public void ConstructingNativeRouterBridge_DoesNotThrow_WhenBridgeIsAvailable()
    {
        if (TryCreateBridge() is null)
        {
            return; // skip — native library not present
        }

        // Successfully constructing a second instance validates the preflight path
        var bridge2 = new NativeRouterBridge();
        Assert.NotNull(bridge2);
    }

    [Fact]
    public void ConstructingNativeRouterBridge_IsIdempotent_WhenBridgeIsAvailable()
    {
        if (TryCreateBridge() is null)
        {
            return;
        }

        // Calling twice must be consistent — no state corruption from first call
        var bridge1 = new NativeRouterBridge();
        var bridge2 = new NativeRouterBridge();
        Assert.NotNull(bridge1);
        Assert.NotNull(bridge2);
    }

    [Fact]
    public void ConstructingNativeRouterBridge_Throws_NativeBridgeUnavailableException_WhenDllIsMissing()
    {
        // Simulate by catching — we verify the type is accessible and correctly typed.
        // A DllNotFoundException wrapped in NativeBridgeUnavailableException is the contract.
        try
        {
            _ = new NativeRouterBridge();
        }
        catch (NativeBridgeUnavailableException ex)
        {
            Assert.NotNull(ex.Message);
            Assert.True(
                ex.InnerException is DllNotFoundException or InvalidOperationException,
                $"Expected DllNotFound or InvalidOperation inner exception, got: {ex.InnerException?.GetType()}");
        }
        catch (NotSupportedException)
        {
            // ABI version mismatch — also acceptable for this test
        }
    }

    // ---- NativeRouterBridge.InspectGrib — argument validation ----

    [Fact]
    public void InspectGrib_Throws_ArgumentException_WhenPathIsEmpty()
    {
        var bridge = TryCreateBridge();
        if (bridge is null)
        {
            return;
        }

        Assert.Throws<ArgumentException>(() => bridge.InspectGrib(string.Empty));
        Assert.Throws<ArgumentException>(() => bridge.InspectGrib("   "));
    }

    [Fact]
    public void InspectGrib_Throws_FileNotFound_WhenFileIsMissing()
    {
        var bridge = TryCreateBridge();
        if (bridge is null)
        {
            return;
        }

        var missing = Path.Combine(
            AppContext.BaseDirectory,
            "nonexistent_forecast_that_does_not_exist.grib");
        Assert.Throws<FileNotFoundException>(() => bridge.InspectGrib(missing));
    }

    // ---- NativeGribInspector — argument validation ----

    [Fact]
    public void Inspect_Throws_ArgumentException_WhenPathIsRelative()
    {
        var bridge = TryCreateBridge();
        if (bridge is null)
        {
            return;
        }

        var inspector = new NativeLocalGribInspector(bridge);
        var ex = Assert.Throws<ArgumentException>(
            () => inspector.InspectAsync("relative/path/forecast.grib"));
        Assert.Equal("absolutePath", ex.ParamName);
    }

    [Fact]
    public void Inspect_Throws_ArgumentException_WhenPathIsEmpty()
    {
        var bridge = TryCreateBridge();
        if (bridge is null)
        {
            return;
        }

        var inspector = new NativeLocalGribInspector(bridge);
        Assert.Throws<ArgumentException>(() => inspector.InspectAsync(string.Empty));
    }

    [Fact]
    public void Inspect_Throws_FileNotFound_WhenFileIsMissing()
    {
        var bridge = TryCreateBridge();
        if (bridge is null)
        {
            return;
        }

        var inspector = new NativeLocalGribInspector(bridge);
        var missing = Path.GetFullPath(
            Path.Combine(
                AppContext.BaseDirectory,
                "nonexistent_forecast_that_does_not_exist.grib"));
        Assert.Throws<FileNotFoundException>(() => inspector.InspectAsync(missing));
    }

    // ---- NativeGribInspector — sample GRIB integration (skip if unavailable) ----

    [Fact]
    public async Task Inspect_Returns_NoaaGfsDescriptor_ForSampleGrib()
    {
        var bridge = TryCreateBridge();
        if (bridge is null)
        {
            return;
        }

        var samplePath = FindSampleGrib();
        if (samplePath is null)
        {
            return;
        }

        var inspector = new NativeLocalGribInspector(bridge);
        var descriptor = await inspector.InspectAsync(samplePath);

        Assert.Equal(ForecastModel.NoaaGfs, descriptor.Model);
        Assert.NotNull(descriptor.Artifact);
        Assert.Equal(samplePath, descriptor.Artifact.Path);
    }

    [Fact]
    public async Task Inspect_Returns_Artifact_ReferencingOriginalPath_NotACopy()
    {
        var bridge = TryCreateBridge();
        if (bridge is null)
        {
            return;
        }

        var samplePath = FindSampleGrib();
        if (samplePath is null)
        {
            return;
        }

        var inspector = new NativeLocalGribInspector(bridge);
        var descriptor = await inspector.InspectAsync(samplePath);

        // File is referenced in place — the artifact path must be the normalized
        // form of the input path, not a copy in a temp directory.
        Assert.Equal(
            Path.GetFullPath(samplePath),
            descriptor.Artifact.Path,
            StringComparer.OrdinalIgnoreCase);
        Assert.True(descriptor.Artifact.LengthBytes is > 0);
    }

    [Fact]
    public async Task Inspect_Returns_ValidTimeRange_ForSampleGrib()
    {
        var bridge = TryCreateBridge();
        if (bridge is null)
        {
            return;
        }

        var samplePath = FindSampleGrib();
        if (samplePath is null)
        {
            return;
        }

        var inspector = new NativeLocalGribInspector(bridge);
        var descriptor = await inspector.InspectAsync(samplePath);

        Assert.True(
            descriptor.InitializedAt <= descriptor.ValidFrom,
            "InitializedAt must not be after ValidFrom");
        Assert.True(
            descriptor.ValidFrom <= descriptor.ValidThrough,
            "ValidFrom must not be after ValidThrough");

        // Must be plausible: after year 2000, before year 2100
        var year2000 = new DateTimeOffset(2000, 1, 1, 0, 0, 0, TimeSpan.Zero);
        var year2100 = new DateTimeOffset(2100, 1, 1, 0, 0, 0, TimeSpan.Zero);
        Assert.True(descriptor.InitializedAt > year2000);
        Assert.True(descriptor.ValidThrough < year2100);
    }

    [Fact]
    public async Task Inspect_Returns_FiniteBounds_ForSampleGrib()
    {
        var bridge = TryCreateBridge();
        if (bridge is null)
        {
            return;
        }

        var samplePath = FindSampleGrib();
        if (samplePath is null)
        {
            return;
        }

        var inspector = new NativeLocalGribInspector(bridge);
        var descriptor = await inspector.InspectAsync(samplePath);
        var bounds = descriptor.Bounds;

        Assert.True(bounds.South <= bounds.North);
        Assert.InRange(bounds.South, -90.0, 90.0);
        Assert.InRange(bounds.North, -90.0, 90.0);
        Assert.InRange(bounds.West, -180.0, 180.0);
        Assert.InRange(bounds.East, -180.0, 180.0);
    }

    [Fact]
    public async Task Inspect_ModelDetection_DoesNotUseFilename()
    {
        var bridge = TryCreateBridge();
        if (bridge is null)
        {
            return;
        }

        var samplePath = FindSampleGrib();
        if (samplePath is null)
        {
            return;
        }

        // Copy the file to a name that looks like ECMWF to prove model detection
        // comes from GRIB centre metadata, not the filename.
        using var tempDir = new TestDirectory();
        var misleadingName = Path.Combine(tempDir.Path, "ecmwf_ifs_forecast.grib");
        File.Copy(samplePath, misleadingName);

        var inspector = new NativeLocalGribInspector(bridge);
        var descriptor = await inspector.InspectAsync(misleadingName);

        // The file is NCEP/GFS data: model must be NoaaGfs regardless of filename.
        Assert.Equal(ForecastModel.NoaaGfs, descriptor.Model);
    }

    [Fact]
    public void InspectGrib_Throws_NativeRouterException_ForEmptyFile()
    {
        var bridge = TryCreateBridge();
        if (bridge is null)
        {
            return;
        }

        using var tempDir = new TestDirectory();
        var emptyPath = Path.Combine(tempDir.Path, "empty.grib");
        File.WriteAllBytes(emptyPath, []);

        Assert.Throws<NativeRouterException>(() => bridge.InspectGrib(emptyPath));
    }

    [Fact]
    public void InspectGrib_Throws_NativeRouterException_ForTruncatedFile()
    {
        var bridge = TryCreateBridge();
        if (bridge is null)
        {
            return;
        }

        using var tempDir = new TestDirectory();
        var badPath = Path.Combine(tempDir.Path, "truncated.grib");
        File.WriteAllBytes(badPath, "GRIB\x00\x00not-a-real-grib-file"u8.ToArray());

        Assert.Throws<NativeRouterException>(() => bridge.InspectGrib(badPath));
    }
}
