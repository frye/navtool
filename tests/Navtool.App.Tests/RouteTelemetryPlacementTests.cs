using Navtool.App.Models;
using Navtool.App.Services;

namespace Navtool.App.Tests;

public sealed class RouteTelemetryPlacementTests
{
    [Fact]
    public void PlacesPopupToTheRightOfTheRoutePointWhenSpaceIsAvailable()
    {
        var result = RouteTelemetryPlacement.Calculate(
            new ScreenRect(0, 0, 800, 600),
            new ScreenPoint(300, 250),
            new ScreenSize(220, 150),
            gap: 18,
            safeMargin: 12);

        Assert.Equal(RouteTelemetrySide.Right, result.Side);
        Assert.Equal(318, result.PopupBounds.X);
        Assert.Equal(175, result.PopupBounds.Y);
        Assert.Equal(result.Anchor, result.Connector.Start);
        Assert.Equal(result.PopupBounds.X, result.Connector.End.X);
        Assert.Equal(result.Anchor.Y, result.Connector.End.Y);
    }

    [Fact]
    public void FlipsPopupToTheLeftNearTheRightEdge()
    {
        var result = RouteTelemetryPlacement.Calculate(
            new ScreenRect(0, 0, 800, 600),
            new ScreenPoint(760, 250),
            new ScreenSize(220, 150),
            gap: 18,
            safeMargin: 12);

        Assert.Equal(RouteTelemetrySide.Left, result.Side);
        Assert.Equal(522, result.PopupBounds.X);
        Assert.Equal(result.PopupBounds.Right, result.Connector.End.X);
    }

    [Theory]
    [InlineData(20, 20)]
    [InlineData(400, 20)]
    [InlineData(780, 20)]
    [InlineData(20, 580)]
    [InlineData(400, 580)]
    [InlineData(780, 580)]
    public void KeepsPopupWithinSafeBoundsAtEveryEdge(double anchorX, double anchorY)
    {
        var visibleBounds = new ScreenRect(0, 0, 800, 600);
        const double margin = 12;
        var safeBounds = new ScreenRect(12, 12, 776, 576);

        var result = RouteTelemetryPlacement.Calculate(
            visibleBounds,
            new ScreenPoint(anchorX, anchorY),
            new ScreenSize(220, 150),
            gap: 18,
            safeMargin: margin);

        Assert.True(safeBounds.Contains(result.PopupBounds));
    }

    [Fact]
    public void CentersPopupWhenNeitherSideHasEnoughSpace()
    {
        var result = RouteTelemetryPlacement.Calculate(
            new ScreenRect(0, 0, 260, 300),
            new ScreenPoint(130, 150),
            new ScreenSize(220, 150),
            gap: 18,
            safeMargin: 12);

        Assert.Equal(RouteTelemetrySide.Centered, result.Side);
        Assert.Equal(20, result.PopupBounds.X);
        Assert.True(new ScreenRect(12, 12, 236, 276).Contains(result.PopupBounds));
    }
}
