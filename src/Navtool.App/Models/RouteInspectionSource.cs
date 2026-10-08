using System.Collections.Immutable;
using Navtool.Core;

namespace Navtool.App.Models;

public sealed record InterruptedRouteInspection(
    RoutePlanId PlanId,
    long Revision,
    long Generation,
    RouteLegId LegId,
    int LegIndex,
    Guid? AttemptId,
    ForecastModel Model,
    RouteRequest Request,
    RouteCalculationSnapshot Snapshot,
    ForecastAcquisition? Acquisition,
    string Reason);

public sealed record RouteInspectionSource
{
    public RouteInspectionSource(RouteResult route, RouteLegVisualization? leg = null)
    {
        ArgumentNullException.ThrowIfNull(route);
        Route = route;
        Leg = leg;
        Model = route.Model;
        Request = route.Request;
        Points = route.Points;
    }

    public RouteInspectionSource(InterruptedRouteInspection preview)
    {
        ArgumentNullException.ThrowIfNull(preview);
        Preview = preview;
        Model = preview.Model;
        Request = preview.Request;
        Points = preview.Snapshot.ProvisionalRoute;
    }

    public RouteResult? Route { get; }
    public RouteLegVisualization? Leg { get; }
    public InterruptedRouteInspection? Preview { get; }
    public ForecastModel Model { get; }
    public RouteRequest Request { get; }
    public ImmutableArray<RoutePoint> Points { get; }
    public bool IsProvisional => Preview is not null;
}
