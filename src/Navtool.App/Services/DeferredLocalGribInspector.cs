using Navtool.Core;
using Navtool.Infrastructure;

namespace Navtool.App.Services;

public sealed class DeferredLocalGribInspector : ILocalGribInspector
{
    private readonly Lazy<ILocalGribInspector> _inspector;

    public DeferredLocalGribInspector()
        : this(() => new NativeLocalGribInspector())
    {
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
