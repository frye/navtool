using Navtool.App.Models;

namespace Navtool.App.Services;

public enum RouteTelemetrySide
{
    Right,
    Left,
    Centered
}

public readonly record struct RouteTelemetryConnector(ScreenPoint Start, ScreenPoint End);

public sealed record RouteTelemetryPlacementResult(
    ScreenPoint Anchor,
    ScreenRect PopupBounds,
    RouteTelemetrySide Side,
    RouteTelemetryConnector Connector);

public static class RouteTelemetryPlacement
{
    public static RouteTelemetryPlacementResult Calculate(
        ScreenRect visibleBounds,
        ScreenPoint anchor,
        ScreenSize popupSize,
        double gap,
        double safeMargin)
    {
        Validate(visibleBounds, anchor, popupSize, gap, safeMargin);

        var safeBounds = new ScreenRect(
            visibleBounds.X + safeMargin,
            visibleBounds.Y + safeMargin,
            visibleBounds.Width - (safeMargin * 2),
            visibleBounds.Height - (safeMargin * 2));
        if (popupSize.Width > safeBounds.Width || popupSize.Height > safeBounds.Height)
        {
            throw new ArgumentException(
                "Visible bounds cannot contain the route telemetry popup.",
                nameof(popupSize));
        }

        var rightX = anchor.X + gap;
        var leftX = anchor.X - gap - popupSize.Width;
        var side = rightX + popupSize.Width <= safeBounds.Right
            ? RouteTelemetrySide.Right
            : leftX >= safeBounds.X
                ? RouteTelemetrySide.Left
                : RouteTelemetrySide.Centered;
        var popupX = side switch
        {
            RouteTelemetrySide.Right => Math.Max(rightX, safeBounds.X),
            RouteTelemetrySide.Left => Math.Min(leftX, safeBounds.Right - popupSize.Width),
            _ => Math.Clamp(
                anchor.X - (popupSize.Width / 2),
                safeBounds.X,
                safeBounds.Right - popupSize.Width)
        };
        var popupY = Math.Clamp(
            anchor.Y - (popupSize.Height / 2),
            safeBounds.Y,
            safeBounds.Bottom - popupSize.Height);
        var popupBounds = new ScreenRect(
            popupX,
            popupY,
            popupSize.Width,
            popupSize.Height);
        var connectorEnd = side switch
        {
            RouteTelemetrySide.Right => new ScreenPoint(
                popupBounds.X,
                Math.Clamp(anchor.Y, popupBounds.Y, popupBounds.Bottom)),
            RouteTelemetrySide.Left => new ScreenPoint(
                popupBounds.Right,
                Math.Clamp(anchor.Y, popupBounds.Y, popupBounds.Bottom)),
            _ => ClosestVerticalEdge(anchor, popupBounds)
        };

        return new RouteTelemetryPlacementResult(
            anchor,
            popupBounds,
            side,
            new RouteTelemetryConnector(anchor, connectorEnd));
    }

    private static ScreenPoint ClosestVerticalEdge(ScreenPoint anchor, ScreenRect bounds)
    {
        var leftDistance = Math.Abs(anchor.X - bounds.X);
        var rightDistance = Math.Abs(anchor.X - bounds.Right);
        return new ScreenPoint(
            leftDistance <= rightDistance ? bounds.X : bounds.Right,
            Math.Clamp(anchor.Y, bounds.Y, bounds.Bottom));
    }

    private static void Validate(
        ScreenRect visibleBounds,
        ScreenPoint anchor,
        ScreenSize popupSize,
        double gap,
        double safeMargin)
    {
        if (!IsFinite(visibleBounds.X) ||
            !IsFinite(visibleBounds.Y) ||
            !IsFinite(visibleBounds.Width) ||
            !IsFinite(visibleBounds.Height) ||
            visibleBounds.Width <= 0 ||
            visibleBounds.Height <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(visibleBounds));
        }

        if (!IsFinite(anchor.X) || !IsFinite(anchor.Y))
        {
            throw new ArgumentOutOfRangeException(nameof(anchor));
        }

        if (!IsFinite(popupSize.Width) ||
            !IsFinite(popupSize.Height) ||
            popupSize.Width <= 0 ||
            popupSize.Height <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(popupSize));
        }

        if (!IsFinite(gap) || gap < 0)
        {
            throw new ArgumentOutOfRangeException(nameof(gap));
        }

        if (!IsFinite(safeMargin) ||
            safeMargin < 0 ||
            (safeMargin * 2) >= visibleBounds.Width ||
            (safeMargin * 2) >= visibleBounds.Height)
        {
            throw new ArgumentOutOfRangeException(nameof(safeMargin));
        }
    }

    private static bool IsFinite(double value) => double.IsFinite(value);
}

