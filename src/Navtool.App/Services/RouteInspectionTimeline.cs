using System.Collections.Immutable;
using Navtool.App.Models;
using Navtool.Core;

namespace Navtool.App.Services;

internal sealed class RouteInspectionTimeline
{
    private readonly SharedRouteTimeline? _accepted;
    private readonly RouteInspectionSource[] _previews;
    private readonly ImmutableArray<DateTimeOffset> _timestamps;

    public RouteInspectionTimeline(ForecastModel model, IEnumerable<RouteInspectionSource> sources)
    {
        var matching = sources.Where(source => source.Model == model).ToArray();
        var legs = matching.Where(source => source.Leg is not null).Select(source => source.Leg!).ToArray();
        _accepted = legs.Length == 0 ? null : SharedRouteTimeline.Create(model, legs);
        _previews = matching.Where(source => source.IsProvisional).ToArray();
        _timestamps = (_accepted?.Timestamps ?? [])
            .Concat(_previews.SelectMany(source => source.Points.Select(point => point.Timestamp)))
            .Select(timestamp => timestamp.ToUniversalTime())
            .Distinct().Order().ToImmutableArray();
        if (_timestamps.IsEmpty)
            throw new ArgumentException("At least one inspectable path is required.", nameof(sources));

        Model = model;
        Start = _timestamps[0];
        End = _timestamps[^1];
    }

    public ForecastModel Model { get; }
    public DateTimeOffset Start { get; }
    public DateTimeOffset End { get; }

    public DateTimeOffset Clamp(DateTimeOffset timestamp) =>
        timestamp < Start ? Start : timestamp > End ? End : timestamp.ToUniversalTime();

    public (RouteMapSelection Selection, string? StopoverLabel) Select(DateTimeOffset timestamp)
    {
        var selected = Clamp(timestamp);
        var preview = _previews.FirstOrDefault(source =>
            selected >= source.Points[0].Timestamp && selected <= source.Points[^1].Timestamp);
        if (preview is not null)
            return (SelectPreview(preview, selected), null);

        RouteMapSelection? accepted = null;
        string? stopover = null;
        if (_accepted is not null)
        {
            var candidate = _accepted.Select(selected);
            var route = candidate.Leg.Route!;
            accepted = new RouteMapSelection(candidate.Leg, route.Points.IndexOf(candidate.Point),
                candidate.Point, RouteHitKind.RoutePoint, 0)
            {
                IsPlannedHold = candidate.IsStopover,
                HoldTimestamp = candidate.IsStopover ? _accepted.Clamp(selected) : null
            };
            stopover = candidate.StopoverLabel;
            if (selected >= _accepted.Start && selected <= _accepted.End)
                return (accepted, stopover);
        }

        var nearestPreview = _previews
            .Select(source => SelectPreview(source, selected))
            .OrderBy(selection => (selection.TimelineTimestamp - selected).Duration())
            .FirstOrDefault();
        if (accepted is not null && (nearestPreview is null ||
            (accepted.TimelineTimestamp - selected).Duration() <=
            (nearestPreview.TimelineTimestamp - selected).Duration()))
            return (accepted, stopover);
        return (nearestPreview!, null);
    }

    public bool TryGetPreviousTimestamp(DateTimeOffset timestamp, out DateTimeOffset previous)
    {
        var index = _timestamps.BinarySearch(timestamp);
        index = (index >= 0 ? index : ~index) - 1;
        if (index >= 0)
        {
            previous = _timestamps[index];
            return true;
        }
        previous = default;
        return false;
    }

    public bool TryGetNextTimestamp(DateTimeOffset timestamp, out DateTimeOffset next)
    {
        var index = _timestamps.BinarySearch(timestamp);
        index = index >= 0 ? index + 1 : ~index;
        if (index < _timestamps.Length)
        {
            next = _timestamps[index];
            return true;
        }
        next = default;
        return false;
    }

    private static RouteMapSelection SelectPreview(RouteInspectionSource source, DateTimeOffset timestamp)
    {
        var index = Enumerable.Range(0, source.Points.Length)
            .MinBy(index => (source.Points[index].Timestamp - timestamp).Duration());
        return new RouteMapSelection(source, index, source.Points[index], RouteHitKind.RoutePoint, 0);
    }
}
