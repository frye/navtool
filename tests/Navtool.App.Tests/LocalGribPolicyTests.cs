using Navtool.App.Services;
using Navtool.App.ViewModels;
using Navtool.Core;
using Navtool.Infrastructure;

namespace Navtool.App.Tests;

public sealed class LocalGribPolicyTests
{
    [Theory]
    [InlineData(false, false)]
    [InlineData(false, true)]
    [InlineData(true, false)]
    [InlineData(true, true)]
    public async Task Selection_and_inspection_use_the_same_normalized_path(bool configured, bool absolute)
    {
        var path = Path.Combine("charts", "..", "selected.grib2");
        if (absolute) path = Path.Combine(Path.GetFullPath("."), path);
        var expected = Path.GetFullPath(path);
        string? inspectedPath = null;
        var inspector = new Inspector((selected, _) =>
        {
            inspectedPath = selected;
            return ValueTask.FromResult(Descriptor(selected));
        });
        ILocalGribInspector effectiveInspector = configured
            ? new DeferredLocalGribInspector(_ => inspector)
            : inspector;
        var vm = CreateViewModel(effectiveInspector);

        await vm.SelectLocalGribAsync(path);

        Assert.Equal(expected, vm.LocalGribPath);
        Assert.Equal(expected, inspectedPath);
        Assert.Equal(expected, vm.LocalForecast?.Artifact.Path);
        Assert.Null(vm.ErrorMessage);
    }

    [Fact]
    public async Task Selected_gap_is_passed_to_the_deferred_native_inspector_factory()
    {
        var requestedGaps = new List<TimeSpan>();
        var deferred = new DeferredLocalGribInspector(gap =>
        {
            requestedGaps.Add(gap);
            return new Inspector((path, _) => ValueTask.FromResult(Descriptor(path)));
        });
        var vm = CreateViewModel(deferred);
        vm.RoutingSetup.LocalForecastMaximumGapHours = 12;
        Assert.Empty(requestedGaps);

        await vm.SelectLocalGribAsync(Path.GetFullPath("custom-gap.grib2"));

        Assert.Equal(TimeSpan.FromHours(12), Assert.Single(requestedGaps));
        Assert.NotNull(vm.LocalForecast);
        Assert.Null(vm.ErrorMessage);
    }

    [Fact]
    public async Task Changing_gap_during_inspection_discards_the_old_validation()
    {
        var started = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var release = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var deferred = new DeferredLocalGribInspector(_ => new Inspector(async (path, _) =>
        {
            started.SetResult();
            await release.Task;
            return Descriptor(path);
        }));
        var vm = CreateViewModel(deferred);
        vm.RoutingSetup.LocalForecastMaximumGapHours = 12;
        var inspection = vm.SelectLocalGribAsync(Path.GetFullPath("stale-gap.grib2"));
        await started.Task;
        vm.RoutingSetup.LocalForecastMaximumGapHours = 3;
        release.SetResult();
        await inspection;

        Assert.Null(vm.LocalForecast);
        Assert.Contains("gap policy changed", vm.LocalGribStatus);
        Assert.False(vm.IsInspectingLocalGrib);
    }

    [Fact]
    public async Task Legacy_factory_cannot_silently_discard_a_custom_gap()
    {
        var calls = 0;
        var deferred = new DeferredLocalGribInspector(() =>
        {
            calls++;
            return new Inspector((path, _) => ValueTask.FromResult(Descriptor(path)));
        });
        await Assert.ThrowsAsync<NotSupportedException>(async () =>
            await deferred.InspectAsync(Path.GetFullPath("unsupported-gap.grib2"), TimeSpan.FromHours(12)));
        Assert.Equal(0, calls);
    }

    private static MainViewModel CreateViewModel(ILocalGribInspector inspector) =>
        new(null, null, TimeProvider.System, TimeZoneInfo.Utc, new OsmTileOptions(Enabled: false),
            localGribInspector: inspector);

    private static LocalForecastDescriptor Descriptor(string path)
    {
        var now = DateTimeOffset.UtcNow;
        return new LocalForecastDescriptor(ForecastModel.NoaaGfs, new LocalGribArtifact(path),
            now.AddHours(-6), now, now.AddDays(3), new GeographicBounds(-89, 89, -179, 179));
    }

    private sealed class Inspector(Func<string, CancellationToken, ValueTask<LocalForecastDescriptor>> inspect)
        : ILocalGribInspector
    {
        public ValueTask<LocalForecastDescriptor> InspectAsync(string absolutePath,
            CancellationToken cancellationToken = default) => inspect(absolutePath, cancellationToken);
    }
}
