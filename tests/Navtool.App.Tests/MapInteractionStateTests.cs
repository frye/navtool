using Navtool.App.Models;
using Navtool.Core;

namespace Navtool.App.Tests;

public sealed class MapInteractionStateTests
{
    [Fact]
    public void ClickPlacesAndMovesOnlyTheActiveEndpoint()
    {
        var state = new MapInteractionState();
        var firstStart = new Coordinate(41.2, -70.4);
        var destination = new Coordinate(36.8, -54.1);
        var movedStart = new Coordinate(40.5, -69.8);

        state.Activate(MapInteractionMode.SetStart);
        Assert.True(state.HandleMapClick(firstStart));
        Assert.Equal(firstStart, state.Start);
        Assert.Null(state.Destination);
        Assert.Equal(MapInteractionMode.Browse, state.Mode);

        state.Activate(MapInteractionMode.SetDestination);
        Assert.True(state.HandleMapClick(destination));
        Assert.Equal(destination, state.Destination);
        Assert.Equal(firstStart, state.Start);

        state.Activate(MapInteractionMode.SetStart);
        Assert.True(state.HandleMapClick(movedStart));
        Assert.Equal(movedStart, state.Start);
        Assert.Equal(destination, state.Destination);
    }

    [Fact]
    public void BrowseClickDoesNotChangeEndpoints()
    {
        var state = new MapInteractionState();

        Assert.False(state.HandleMapClick(new Coordinate(10, 20)));
        Assert.Null(state.Start);
        Assert.Null(state.Destination);
    }
}
