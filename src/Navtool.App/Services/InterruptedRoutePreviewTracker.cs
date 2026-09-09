using Navtool.Core;

namespace Navtool.App.Services;

internal sealed record InterruptedRoutePreview(
    ForecastModel Model,
    int LegIndex,
    Guid? AttemptId,
    RouteCalculationSnapshot Snapshot,
    string? FailureMessage);

/// <summary>Caller synchronizes access; holds at most one current search path per model.</summary>
internal sealed class InterruptedRoutePreviewTracker
{
    private readonly Dictionary<ForecastModel, (int Leg, Guid? Attempt)> _units = [];
    private readonly Dictionary<ForecastModel, InterruptedRoutePreview> _previews = [];

    public IReadOnlyCollection<InterruptedRoutePreview> Previews => _previews.Values;

    public void Observe(ForecastModel model, int leg, Guid? attempt,
        bool calculating, bool succeeded, string? failureMessage, RouteCalculationSnapshot? snapshot)
    {
        if (succeeded)
        {
            Remove(model);
            return;
        }

        if (calculating)
        {
            var unit = (leg, attempt);
            if (!_units.TryGetValue(model, out var previous) || previous != unit)
            {
                _previews.Remove(model);
                _units[model] = unit;
            }
            if (snapshot is { ProvisionalRoute.Length: >= 2 } &&
                snapshot.ProvisionalRoute[^1].Timestamp > snapshot.ProvisionalRoute[0].Timestamp)
                _previews[model] = new(model, leg, attempt, snapshot, null);
        }
        else if (failureMessage is not null &&
                 _previews.TryGetValue(model, out var preview) && preview.LegIndex == leg)
        {
            _previews[model] = preview with { FailureMessage = failureMessage };
        }
    }

    public void Remove(ForecastModel model)
    {
        _units.Remove(model);
        _previews.Remove(model);
    }

    public void Clear()
    {
        _units.Clear();
        _previews.Clear();
    }
}
