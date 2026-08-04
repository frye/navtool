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
                RadialMenuAction.CalculateRoute,
                RadialMenuAction.SetDestination,
                RadialMenuAction.RefreshWeather
            ],
            result.Actions.Select(action => action.Action));
        Assert.True(result.Actions[0].Center.Y < result.Center.Y);
        Assert.True(result.Actions[1].Center.X > result.Center.X);
        Assert.Equal(result.Center.Y, result.Actions[1].Center.Y, 6);
        Assert.True(result.Actions[2].Center.Y > result.Center.Y);
        Assert.True(result.Actions[3].Center.X < result.Center.X);
        Assert.Equal(result.Center.Y, result.Actions[3].Center.Y, 6);
    }

    [Theory]
    [InlineData(100, 50)]
    [InlineData(300, 50)]
    [InlineData(500, 50)]
    [InlineData(100, 200)]
    [InlineData(500, 200)]
    [InlineData(100, 350)]
    [InlineData(300, 350)]
    [InlineData(500, 350)]
    public void ClampsEveryEdgeAndCornerInsideSafeBounds(double anchorX, double anchorY)
    {
        var visibleBounds = new ScreenRect(100, 50, 400, 300);
        const double margin = 16;
        var safeBounds = new ScreenRect(
            visibleBounds.X + margin,
            visibleBounds.Y + margin,
            visibleBounds.Width - (margin * 2),
            visibleBounds.Height - (margin * 2));
        var anchor = new ScreenPoint(anchorX, anchorY);

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
    public void UsesFourActionHorizontalFallbackWhenRadialGeometryCannotFit()
    {
        var visibleBounds = new ScreenRect(0, 0, 380, 90);
        var safeBounds = new ScreenRect(8, 8, 364, 74);

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
        Assert.True(result.Actions[2].Center.X < result.Actions[3].Center.X);
        Assert.All(
            result.Actions,
            action => Assert.Equal(result.Center.Y, action.Center.Y, 6));
    }

    [Fact]
    public void UsesFourActionVerticalFallbackWhenHorizontalCannotFit()
    {
        var visibleBounds = new ScreenRect(0, 0, 110, 260);
        var safeBounds = new ScreenRect(8, 8, 94, 244);

        var result = RadialMenuPlacement.Calculate(
            visibleBounds,
            new ScreenPoint(55, 20),
            new ScreenSize(80, 40),
            radius: 70,
            safeMargin: 8);

        Assert.Equal(RadialMenuLayout.Linear, result.Layout);
        Assert.True(result.NeedsConnector);
        Assert.All(result.Actions, action => Assert.True(safeBounds.Contains(action.Bounds)));
        Assert.True(result.Actions[0].Center.Y < result.Actions[1].Center.Y);
        Assert.True(result.Actions[1].Center.Y < result.Actions[2].Center.Y);
        Assert.True(result.Actions[2].Center.Y < result.Actions[3].Center.Y);
        Assert.All(
            result.Actions,
            action => Assert.Equal(result.Center.X, action.Center.X, 6));
    }
}
