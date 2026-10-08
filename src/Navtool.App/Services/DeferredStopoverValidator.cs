using Navtool.Core;
using Navtool.Infrastructure;

namespace Navtool.App.Services;

public sealed class DeferredStopoverValidator : IRouteStopoverValidator
{
    private readonly Lazy<NativeRouterBridge> _bridge =
        new(() => new NativeRouterBridge(), LazyThreadSafetyMode.PublicationOnly);

    public ValueTask<RoutePlannedHold> CheckAsync(Coordinate location, DateTimeOffset from, DateTimeOffset until,
        RouteExclusionOptions exclusions, CancellationToken cancellationToken = default) =>
        new(Task.Run(() => _bridge.Value.CheckPlannedHold(
            location, from, until, exclusions, cancellationToken), cancellationToken));
}
