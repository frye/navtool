using System.Collections.Immutable;
using Navtool.App.Models;

namespace Navtool.App.Services;

public enum RadialMenuAction
{
    SetStart,
    SetDestination,
    Inspect
}

public enum RadialMenuLayout
{
    Radial,
    Linear
}

public readonly record struct ScreenSize(double Width, double Height);

public readonly record struct ScreenRect(double X, double Y, double Width, double Height)
{
    public double Right => X + Width;

    public double Bottom => Y + Height;

    public ScreenPoint Center => new(X + (Width / 2), Y + (Height / 2));

    public bool Contains(ScreenRect other) =>
        other.X >= X &&
        other.Y >= Y &&
        other.Right <= Right &&
        other.Bottom <= Bottom;
}

public readonly record struct RadialMenuConnector(ScreenPoint Start, ScreenPoint End);

public sealed record RadialMenuActionPlacement(
    RadialMenuAction Action,
    ScreenRect Bounds)
{
    public ScreenPoint Center => Bounds.Center;
}

public sealed record RadialMenuPlacementResult(
    ScreenPoint Anchor,
    ScreenPoint Center,
    ImmutableArray<RadialMenuActionPlacement> Actions,
    RadialMenuLayout Layout,
    RadialMenuConnector? Connector)
{
    public bool NeedsConnector => Connector is not null;
}

public static class RadialMenuPlacement
{
    private const double LinearGap = 8;
    private const double ConnectorEpsilon = 0.001;
    private static readonly ImmutableArray<RadialMenuAction> ActionOrder =
    [
        RadialMenuAction.SetStart,
        RadialMenuAction.SetDestination,
        RadialMenuAction.Inspect
    ];

    public static RadialMenuPlacementResult Calculate(
        ScreenRect visibleBounds,
        ScreenPoint anchor,
        ScreenSize actionSize,
        double radius,
        double safeMargin)
    {
        Validate(visibleBounds, anchor, actionSize, radius, safeMargin);

        var safeBounds = new ScreenRect(
            visibleBounds.X + safeMargin,
            visibleBounds.Y + safeMargin,
            visibleBounds.Width - (safeMargin * 2),
            visibleBounds.Height - (safeMargin * 2));
        if (TryCreateRadial(safeBounds, anchor, actionSize, radius, out var center, out var actions))
        {
            return CreateResult(anchor, center, actions, RadialMenuLayout.Radial);
        }

        var linear = CreateLinear(safeBounds, anchor, actionSize);
        return CreateResult(anchor, linear.Center, linear.Actions, RadialMenuLayout.Linear);
    }

    private static bool TryCreateRadial(
        ScreenRect safeBounds,
        ScreenPoint anchor,
        ScreenSize actionSize,
        double radius,
        out ScreenPoint center,
        out ImmutableArray<RadialMenuActionPlacement> actions)
    {
        var offsets = CreateRadialOffsets(radius);
        var minimumOffsetX = offsets.Min(offset => offset.X - (actionSize.Width / 2));
        var maximumOffsetX = offsets.Max(offset => offset.X + (actionSize.Width / 2));
        var minimumOffsetY = offsets.Min(offset => offset.Y - (actionSize.Height / 2));
        var maximumOffsetY = offsets.Max(offset => offset.Y + (actionSize.Height / 2));
        var minimumCenterX = safeBounds.X - minimumOffsetX;
        var maximumCenterX = safeBounds.Right - maximumOffsetX;
        var minimumCenterY = safeBounds.Y - minimumOffsetY;
        var maximumCenterY = safeBounds.Bottom - maximumOffsetY;

        if (minimumCenterX > maximumCenterX || minimumCenterY > maximumCenterY)
        {
            center = default;
            actions = default;
            return false;
        }

        center = new ScreenPoint(
            Math.Clamp(anchor.X, minimumCenterX, maximumCenterX),
            Math.Clamp(anchor.Y, minimumCenterY, maximumCenterY));
        actions = CreatePlacements(center, actionSize, offsets);
        return true;
    }

    private static (ScreenPoint Center, ImmutableArray<RadialMenuActionPlacement> Actions) CreateLinear(
        ScreenRect safeBounds,
        ScreenPoint anchor,
        ScreenSize actionSize)
    {
        var horizontalGap = AvailableGap(safeBounds.Width, actionSize.Width);
        var verticalGap = AvailableGap(safeBounds.Height, actionSize.Height);
        var canUseHorizontal = horizontalGap is not null && actionSize.Height <= safeBounds.Height;
        var canUseVertical = verticalGap is not null && actionSize.Width <= safeBounds.Width;
        var useHorizontal = canUseHorizontal &&
                            (!canUseVertical || safeBounds.Width >= safeBounds.Height);
        ImmutableArray<ScreenPoint> offsets;
        double halfWidth;
        double halfHeight;

        if (useHorizontal)
        {
            var step = actionSize.Width + horizontalGap!.Value;
            offsets = [new ScreenPoint(-step, 0), new ScreenPoint(0, 0), new ScreenPoint(step, 0)];
            halfWidth = step + (actionSize.Width / 2);
            halfHeight = actionSize.Height / 2;
        }
        else if (canUseVertical)
        {
            var step = actionSize.Height + verticalGap.Value;
            offsets = [new ScreenPoint(0, -step), new ScreenPoint(0, 0), new ScreenPoint(0, step)];
            halfWidth = actionSize.Width / 2;
            halfHeight = step + (actionSize.Height / 2);
        }
        else
        {
            throw new ArgumentException(
                "Visible bounds cannot contain a non-overlapping three-action menu.",
                nameof(safeBounds));
        }

        var center = new ScreenPoint(
            Math.Clamp(anchor.X, safeBounds.X + halfWidth, safeBounds.Right - halfWidth),
            Math.Clamp(anchor.Y, safeBounds.Y + halfHeight, safeBounds.Bottom - halfHeight));
        return (center, CreatePlacements(center, actionSize, offsets));
    }

    private static double? AvailableGap(double availableLength, double actionLength)
    {
        var remaining = availableLength - (actionLength * ActionOrder.Length);
        return remaining < 0 ? null : Math.Min(LinearGap, remaining / (ActionOrder.Length - 1));
    }

    private static ImmutableArray<ScreenPoint> CreateRadialOffsets(double radius)
    {
        var lowerX = radius * Math.Sqrt(3) / 2;
        var lowerY = radius / 2;
        return
        [
            new ScreenPoint(0, -radius),
            new ScreenPoint(lowerX, lowerY),
            new ScreenPoint(-lowerX, lowerY)
        ];
    }

    private static ImmutableArray<RadialMenuActionPlacement> CreatePlacements(
        ScreenPoint center,
        ScreenSize actionSize,
        ImmutableArray<ScreenPoint> offsets)
    {
        var placements = ImmutableArray.CreateBuilder<RadialMenuActionPlacement>(ActionOrder.Length);
        for (var index = 0; index < ActionOrder.Length; index++)
        {
            var actionCenter = new ScreenPoint(
                center.X + offsets[index].X,
                center.Y + offsets[index].Y);
            placements.Add(new RadialMenuActionPlacement(
                ActionOrder[index],
                new ScreenRect(
                    actionCenter.X - (actionSize.Width / 2),
                    actionCenter.Y - (actionSize.Height / 2),
                    actionSize.Width,
                    actionSize.Height)));
        }

        return placements.MoveToImmutable();
    }

    private static RadialMenuPlacementResult CreateResult(
        ScreenPoint anchor,
        ScreenPoint center,
        ImmutableArray<RadialMenuActionPlacement> actions,
        RadialMenuLayout layout)
    {
        var connector = anchor.DistanceTo(center) > ConnectorEpsilon
            ? new RadialMenuConnector(anchor, center)
            : null;
        return new RadialMenuPlacementResult(anchor, center, actions, layout, connector);
    }

    private static void Validate(
        ScreenRect visibleBounds,
        ScreenPoint anchor,
        ScreenSize actionSize,
        double radius,
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

        if (!IsFinite(actionSize.Width) ||
            !IsFinite(actionSize.Height) ||
            actionSize.Width <= 0 ||
            actionSize.Height <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(actionSize));
        }

        if (!IsFinite(radius) || radius < 0)
        {
            throw new ArgumentOutOfRangeException(nameof(radius));
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
