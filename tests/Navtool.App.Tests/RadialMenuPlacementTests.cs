using Navtool.App.Models;
using Navtool.App.Services;

namespace Navtool.App.Tests;

public sealed class RadialMenuPlacementTests
{
    [Fact]
    public void ArrangesActionsClockwiseAroundUnchangedAnchor()
    {
        var result = RadialMenuPlacement.Calculate(
            new ScreenRect(0, 0, 500, 400),
            new ScreenPoint(250, 200),
            new ScreenSize(80, 40),
            radius: 80,
            safeMargin: 12);

        Assert.Equal(RadialMenuLayout.Radial, result.Layout);
        Assert.Equal(result.Anchor, result.Center);
        Assert.False(result.NeedsConnector);
        Assert.Equal(
            [
                RadialMenuAction.SetStart,
                RadialMenuAction.SetDestination,
                RadialMenuAction.Inspect
            ],
            result.Actions.Select(action => action.Action));
        Assert.True(result.Actions[0].Center.Y < result.Center.Y);
        Assert.True(result.Actions[1].Center.X > result.Center.X);
        Assert.True(result.Actions[1].Center.Y > result.Center.Y);
        Assert.True(result.Actions[2].Center.X < result.Center.X);
        Assert.True(result.Actions[2].Center.Y > result.Center.Y);
    }

    [Fact]
    public void ClampsCenterSoEveryActionStaysInsideSafeBounds()
    {
        var visibleBounds = new ScreenRect(100, 50, 400, 300);
        const double margin = 16;
        var safeBounds = new ScreenRect(
            visibleBounds.X + margin,
            visibleBounds.Y + margin,
            visibleBounds.Width - (margin * 2),
            visibleBounds.Height - (margin * 2));
        var anchor = new ScreenPoint(490, 55);

        var result = RadialMenuPlacement.Calculate(
            visibleBounds,
            anchor,
            new ScreenSize(88, 44),
            radius: 72,
            safeMargin: margin);

        Assert.Equal(RadialMenuLayout.Radial, result.Layout);
        Assert.NotEqual(anchor, result.Center);
        Assert.True(result.NeedsConnector);
        Assert.Equal(new RadialMenuConnector(anchor, result.Center), result.Connector);
        Assert.All(result.Actions, action => Assert.True(safeBounds.Contains(action.Bounds)));
    }

    [Fact]
    public void UsesCompactLinearFallbackWhenRadialGeometryCannotFit()
    {
        var visibleBounds = new ScreenRect(0, 0, 280, 90);
        var safeBounds = new ScreenRect(8, 8, 264, 74);

        var result = RadialMenuPlacement.Calculate(
            visibleBounds,
            new ScreenPoint(20, 45),
            new ScreenSize(80, 40),
            radius: 70,
            safeMargin: 8);

        Assert.Equal(RadialMenuLayout.Linear, result.Layout);
        Assert.True(result.NeedsConnector);
        Assert.All(result.Actions, action => Assert.True(safeBounds.Contains(action.Bounds)));
        Assert.True(result.Actions[0].Center.X < result.Actions[1].Center.X);
        Assert.True(result.Actions[1].Center.X < result.Actions[2].Center.X);
        Assert.All(
            result.Actions,
            action => Assert.Equal(result.Center.Y, action.Center.Y, 6));
    }
}
