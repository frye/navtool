using Navtool.App.Services;

namespace Navtool.App.Tests;

public sealed class CoalescingProgressTests
{
    [Fact]
    public void Flush_delivers_pending_updates_once_without_replaying_queued_callbacks()
    {
        var context = new QueuedContext();
        var previous = SynchronizationContext.Current;
        var displayed = new List<int>();
        try
        {
            SynchronizationContext.SetSynchronizationContext(context);
            var progress = new CoalescingProgress<int, int>(_ => 0, displayed.Add);
            progress.Report(1);
            progress.Report(2);
            progress.Flush();
            Assert.Equal([2], displayed);
            context.Drain();
            Assert.Equal([2], displayed);
            progress.Report(3);
            context.Drain();
            Assert.Equal([2, 3], displayed);
        }
        finally { SynchronizationContext.SetSynchronizationContext(previous); }
    }

    [Fact]
    public async Task Flush_serializes_with_an_in_flight_display_handler()
    {
        var context = new QueuedContext();
        var previous = SynchronizationContext.Current;
        var displayed = new List<int>();
        using var release = new ManualResetEventSlim();
        var entered = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var flushing = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        CoalescingProgress<int, int> progress;
        try
        {
            SynchronizationContext.SetSynchronizationContext(context);
            progress = new CoalescingProgress<int, int>(_ => 0, value =>
            {
                if (value == 1)
                {
                    entered.SetResult();
                    Assert.True(release.Wait(TimeSpan.FromSeconds(5)));
                }
                displayed.Add(value);
            });
            progress.Report(1);
        }
        finally { SynchronizationContext.SetSynchronizationContext(previous); }

        var drain = Task.Run(context.Drain);
        Task? flush = null;
        try
        {
            await entered.Task.WaitAsync(TimeSpan.FromSeconds(5));
            progress.Report(2);
            flush = Task.Run(() =>
            {
                flushing.SetResult();
                progress.Flush();
            });
            await flushing.Task.WaitAsync(TimeSpan.FromSeconds(5));
            Assert.False(flush.IsCompleted);
        }
        finally { release.Set(); }
        await Task.WhenAll(drain, flush!).WaitAsync(TimeSpan.FromSeconds(5));
        Assert.Equal([1, 2], displayed);
    }

    [Fact]
    public void Coalesced_updates_keep_their_latest_report_order()
    {
        var context = new QueuedContext();
        var previous = SynchronizationContext.Current;
        var displayed = new List<int>();
        try
        {
            SynchronizationContext.SetSynchronizationContext(context);
            var progress = new CoalescingProgress<int, int>(value => value % 2, displayed.Add);
            progress.Report(1);
            progress.Report(2);
            progress.Report(3);
            context.Drain();
            Assert.Equal([2, 3], displayed);
        }
        finally { SynchronizationContext.SetSynchronizationContext(previous); }
    }

    [Fact]
    public void Observer_receives_every_update_before_display_coalescing()
    {
        var context = new QueuedContext();
        var previous = SynchronizationContext.Current;
        var observed = new List<int>();
        var displayed = new List<int>();
        try
        {
            SynchronizationContext.SetSynchronizationContext(context);
            var progress = new CoalescingProgress<int, int>(_ => 0, displayed.Add, observed.Add);
            progress.Report(1);
            progress.Report(2);
            Assert.Equal([1, 2], observed);
            Assert.Empty(displayed);
            context.Drain();
            Assert.Equal([2], displayed);
        }
        finally { SynchronizationContext.SetSynchronizationContext(previous); }
    }

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

    internal sealed class QueuedContext : SynchronizationContext
    {
        public Queue<(SendOrPostCallback Callback, object? State)> Callbacks { get; } = new();
        public override void Post(SendOrPostCallback d, object? state) => Callbacks.Enqueue((d, state));
        public void Drain()
        {
            while (Callbacks.TryDequeue(out var item)) item.Callback(item.State);
        }
    }
}
