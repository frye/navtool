using Navtool.Core;

namespace Navtool.App.Models;

public enum MapInteractionMode
{
    Browse,
    SetStart,
    SetDestination,
    SetWaypoint
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

    public void SetStart(Coordinate coordinate)
    {
        Start = coordinate;
        Mode = MapInteractionMode.Browse;
    }

    public void SetDestination(Coordinate coordinate)
    {
        Destination = coordinate;
        Mode = MapInteractionMode.Browse;
    }

    public bool HandleMapClick(Coordinate coordinate)
    {
        switch (Mode)
        {
            case MapInteractionMode.SetStart:
                SetStart(coordinate);
                break;
            case MapInteractionMode.SetDestination:
                SetDestination(coordinate);
                break;
            case MapInteractionMode.SetWaypoint:
                Mode = MapInteractionMode.Browse;
                break;
            default:
                return false;
        }

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
