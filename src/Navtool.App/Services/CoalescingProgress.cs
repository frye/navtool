namespace Navtool.App.Services;

/// <summary>Only the latest display update for a routing unit waits on the UI queue.</summary>
internal sealed class CoalescingProgress<T, TKey>(
    Func<T, TKey> keySelector,
    Action<T> handler,
    Action<T>? onReport = null) : IProgress<T> where TKey : notnull
{
    private readonly SynchronizationContext? _context = SynchronizationContext.Current;
    private readonly object _gate = new();
    private readonly object _deliveryGate = new();
    private readonly Dictionary<TKey, (long Sequence, T Value)> _pending = [];
    private long _sequence;
    private bool _scheduled;

    public void Report(T value)
    {
        onReport?.Invoke(value);
        lock (_gate)
        {
            _pending[keySelector(value)] = (++_sequence, value);
            if (_scheduled)
            {
                return;
            }
            _scheduled = true;
        }
        QueueDrain();
    }

    private void QueueDrain()
    {
        if (_context is not null)
        {
            _context.Post(_ => Drain(), null);
        }
        else
        {
            ThreadPool.QueueUserWorkItem(_ => Drain());
        }
    }

    // Call on the display thread before closing the calculation's progress acceptance window.
    public void Flush()
    {
        lock (_deliveryGate)
        {
            DeliverPending();
        }
    }

    private void DeliverPending()
    {
        T[] values;
        lock (_gate)
        {
            values = _pending.Values.OrderBy(value => value.Sequence).Select(value => value.Value).ToArray();
            _pending.Clear();
        }
        foreach (var value in values)
            handler(value);
    }

    private void Drain()
    {
        lock (_deliveryGate)
        {
            try
            {
                DeliverPending();
            }
            finally
            {
                bool queued;
                lock (_gate)
                {
                    queued = _pending.Count > 0;
                    _scheduled = queued;
                }
                if (queued) QueueDrain();
            }
        }
    }
}
