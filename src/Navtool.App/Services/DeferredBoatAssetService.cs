using Navtool.Core;

namespace Navtool.App.Services;

public sealed class DeferredBoatAssetService(Func<IBoatAssetService> factory) : IBoatAssetService
{
    private readonly Lazy<IBoatAssetService> _service = new(factory, LazyThreadSafetyMode.PublicationOnly);

    public ValueTask<BoatAsset> ImportAsync(string path, BoatPolarFormat format,
        CancellationToken cancellationToken = default) =>
        new(Task.Run(async () => await _service.Value.ImportAsync(path, format, cancellationToken), cancellationToken));

    public ValueTask<BoatAsset> GetDemoAsync(CancellationToken cancellationToken = default) =>
        new(Task.Run(async () => await _service.Value.GetDemoAsync(cancellationToken), cancellationToken));

    public ValueTask<ResolvedBoatAsset> ResolveAsync(BoatAsset asset, CancellationToken cancellationToken = default) =>
        new(Task.Run(async () => await _service.Value.ResolveAsync(asset, cancellationToken), cancellationToken));
}
