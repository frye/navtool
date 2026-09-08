using Navtool.Core;

namespace Navtool.App.Services;

public sealed class DeferredRoutingSetupService(Func<IRoutingSetupService> factory) : IRoutingSetupService
{
    private readonly Lazy<IRoutingSetupService> _service = new(factory, LazyThreadSafetyMode.PublicationOnly);

    public ValueTask<RoutingCalculationContext> FreezeAsync(
        RoutingSetup setup, RoutingProfessionalOverrides? professionalOverrides = null,
        CancellationToken cancellationToken = default) =>
        new(Task.Run(async () => await _service.Value.FreezeAsync(
            setup, professionalOverrides, cancellationToken), cancellationToken));
}
