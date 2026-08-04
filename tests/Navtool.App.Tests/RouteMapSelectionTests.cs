using Navtool.App.Models;

namespace Navtool.App.Tests;

public sealed class RouteMapSelectionTests
{
    [Theory]
    [InlineData(68.198, "68° S")]
    [InlineData(-68.198, "68° P")]
    [InlineData(0, "0°")]
    [InlineData(180, "180°")]
    [InlineData(-180, "180°")]
    public void FormatsApparentWindAngleWithCompactSideMarker(
        double signedAngleDegrees,
        string expected)
    {
        Assert.Equal(
            expected,
            RouteMapSelection.FormatApparentWindAngle(signedAngleDegrees));
    }
}
