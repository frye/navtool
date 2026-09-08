using Navtool.Core;
using Navtool.Infrastructure;

namespace Navtool.App.Services;

public interface IConfiguredLocalGribInspector : ILocalGribInspector
{
    ValueTask<LocalForecastDescriptor> InspectAsync(string absolutePath,
        TimeSpan maximumInterpolationGap, CancellationToken cancellationToken = default);
}

public sealed class DeferredLocalGribInspector : IConfiguredLocalGribInspector
{
    private readonly Lazy<ILocalGribInspector> _inspector;
    private readonly Func<TimeSpan, ILocalGribInspector>? _configuredFactory;

    public DeferredLocalGribInspector()
        : this(gap => new NativeLocalGribInspector(maximumInterpolationGap: gap))
    {
    }

    public DeferredLocalGribInspector(Func<TimeSpan, ILocalGribInspector> factory)
    {
        ArgumentNullException.ThrowIfNull(factory);
        _configuredFactory = factory;
        _inspector = new Lazy<ILocalGribInspector>(
            () => factory(TimeSpan.FromHours(6)), LazyThreadSafetyMode.PublicationOnly);
    }

    public ValueTask<LocalForecastDescriptor> InspectAsync(string absolutePath,
        TimeSpan maximumInterpolationGap, CancellationToken cancellationToken = default)
    {
        if (maximumInterpolationGap <= TimeSpan.Zero ||
            maximumInterpolationGap.Ticks % TimeSpan.TicksPerSecond != 0)
            throw new ArgumentOutOfRangeException(nameof(maximumInterpolationGap));
        if (maximumInterpolationGap == TimeSpan.FromHours(6))
            return InspectAsync(absolutePath, cancellationToken);
        if (_configuredFactory is null)
            throw new NotSupportedException("This inspector cannot apply a custom interpolation-gap policy.");
        return new ValueTask<LocalForecastDescriptor>(Task.Run(async () =>
            await _configuredFactory(maximumInterpolationGap).InspectAsync(absolutePath, cancellationToken)
                .ConfigureAwait(false), cancellationToken));
    }

    public DeferredLocalGribInspector(Func<ILocalGribInspector> factory)
    {
        ArgumentNullException.ThrowIfNull(factory);
        _inspector = new Lazy<ILocalGribInspector>(
            factory,
            LazyThreadSafetyMode.PublicationOnly);
    }

    public async ValueTask<LocalForecastDescriptor> InspectAsync(
        string absolutePath,
        CancellationToken cancellationToken = default) =>
        await Task.Run(
            async () => await _inspector.Value
                .InspectAsync(absolutePath, cancellationToken)
                .ConfigureAwait(false),
            cancellationToken).ConfigureAwait(false);
}
