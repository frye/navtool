namespace Navtool.Core;

/// <summary>A timed heading proposed during native incumbent seeding, not proof of a successful seed.</summary>
public sealed record RouteCoastalSeedAction
{
    public RouteCoastalSeedAction(double headingDegrees, TimeSpan duration)
    {
        if (!double.IsFinite(headingDegrees))
            throw new ArgumentOutOfRangeException(nameof(headingDegrees));
        if (duration <= TimeSpan.Zero || duration.Ticks % TimeSpan.TicksPerSecond != 0)
            throw new ArgumentOutOfRangeException(nameof(duration), "Seed action duration must be positive whole seconds.");
        HeadingDegrees = headingDegrees;
        Duration = duration;
    }

    public double HeadingDegrees { get; }
    public TimeSpan Duration { get; }
}
