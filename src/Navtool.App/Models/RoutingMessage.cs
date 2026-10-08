using Navtool.Core;

namespace Navtool.App.Models;

public enum RoutingMessageSeverity { Information, Warning, Error }

public sealed record RoutingMessage(
    string Id,
    string Heading,
    string Summary,
    RoutingMessageSeverity Severity,
    ForecastModel? Model = null,
    int? LegIndex = null,
    Coordinate? Endpoint = null,
    string? Details = null)
{
    public bool IsInterrupted => Endpoint is not null;
}
