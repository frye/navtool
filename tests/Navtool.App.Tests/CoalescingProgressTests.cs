using Navtool.App.Services;

namespace Navtool.App.Tests;

public sealed class CoalescingProgressTests
{
    [Fact]
    public void Queues_one_dispatch_and_latest_value_per_model_leg_attempt()
    {
        var context = new QueuedContext();
        var previous = SynchronizationContext.Current;
        var accepted = new List<(int Model, int Leg, int Attempt, int Value)>();
        try
        {
            SynchronizationContext.SetSynchronizationContext(context);
            var progress = new CoalescingProgress<(int Model, int Leg, int Attempt, int Value), (int, int, int)>(
                update => (update.Model, update.Leg, update.Attempt), accepted.Add);
            for (var index = 0; index < 1000; index++)
                progress.Report((0, 1, 0, index));
            progress.Report((0, 1, 1, 1));
            progress.Report((1, 2, 0, 2));
            Assert.Single(context.Callbacks);
            context.Drain();
            Assert.Equal([(0, 1, 0, 999), (0, 1, 1, 1), (1, 2, 0, 2)],
                accepted.OrderBy(update => (update.Model, update.Leg, update.Attempt)));
            progress.Report((0, 1, 1, 3));
            Assert.Single(context.Callbacks);
            context.Drain();
            Assert.Equal(4, accepted.Count);
            Assert.Equal((0, 1, 1, 3), accepted[^1]);
        }
        finally { SynchronizationContext.SetSynchronizationContext(previous); }
    }

    private sealed class QueuedContext : SynchronizationContext
    {
        public Queue<(SendOrPostCallback Callback, object? State)> Callbacks { get; } = new();
        public override void Post(SendOrPostCallback d, object? state) => Callbacks.Enqueue((d, state));
        public void Drain()
        {
            while (Callbacks.TryDequeue(out var item)) item.Callback(item.State);
        }
    }
}
