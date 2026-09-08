using Navtool.Core;
using Navtool.Infrastructure;

namespace Navtool.App.Services;

public sealed class DeferredStopoverValidator : IRouteStopoverValidator
{
    private readonly Lazy<NativeStopoverValidator> _validator =
        new(() => new NativeStopoverValidator(new NativeRouterBridge()), LazyThreadSafetyMode.PublicationOnly);

    public ValueTask<RoutePlannedHold> CheckAsync(Coordinate location, DateTimeOffset from, DateTimeOffset until,
        RouteExclusionOptions exclusions, CancellationToken cancellationToken = default) =>
        new(Task.Run(async () => await _validator.Value.CheckAsync(
            location, from, until, exclusions, cancellationToken), cancellationToken));
}
