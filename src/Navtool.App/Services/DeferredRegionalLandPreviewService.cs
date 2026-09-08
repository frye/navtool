using Navtool.Core;
using Navtool.Infrastructure;

namespace Navtool.App.Services;

public sealed record RegionalLandPreview(RouteRegionalLandPolicy Policy, RegionalLandEstimate Estimate);

public interface IRegionalLandPreviewService
{
    ValueTask<RegionalLandPreview> PreviewAsync(
        RouteRegionalLandPolicy policy, CancellationToken cancellationToken = default);
}

public sealed class DeferredRegionalLandPreviewService : IRegionalLandPreviewService
{
    private readonly Lazy<NativeRouterBridge> _bridge =
        new(() => new NativeRouterBridge(), LazyThreadSafetyMode.PublicationOnly);

    public ValueTask<RegionalLandPreview> PreviewAsync(
        RouteRegionalLandPolicy policy, CancellationToken cancellationToken = default) =>
        new(Task.Run(() =>
        {
            using var land = _bridge.Value.LoadRegionalLand(policy.SourcePath,
                RegionalLandOptions.FromPolicy(policy), policy.SourceIdentity, cancellationToken);
            return new RegionalLandPreview(policy, land.Estimate);
        }, cancellationToken));
}
