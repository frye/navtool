using Navtool.Core;

namespace Navtool.App.Models;

public enum MapInteractionMode
{
    Browse,
    SetStart,
    SetDestination
}

public sealed class MapInteractionState
{
    public MapInteractionMode Mode { get; private set; }

    public Coordinate? Start { get; private set; }

    public Coordinate? Destination { get; private set; }

    public void Activate(MapInteractionMode mode)
    {
        Mode = mode;
    }

    public bool HandleMapClick(Coordinate coordinate)
    {
        switch (Mode)
        {
            case MapInteractionMode.SetStart:
                Start = coordinate;
                break;
            case MapInteractionMode.SetDestination:
                Destination = coordinate;
                break;
            default:
                return false;
        }

        Mode = MapInteractionMode.Browse;
        return true;
    }
}

public readonly record struct ScreenPoint(double X, double Y)
{
    public double DistanceTo(ScreenPoint other)
    {
        var deltaX = X - other.X;
        var deltaY = Y - other.Y;
        return Math.Sqrt((deltaX * deltaX) + (deltaY * deltaY));
    }
}
