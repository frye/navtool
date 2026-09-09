namespace Navtool.App.Services;

/// <summary>Only the latest display update for a routing unit waits on the UI queue.</summary>
internal sealed class CoalescingProgress<T, TKey>(
    Func<T, TKey> keySelector,
    Action<T> handler,
    Action<T>? onReport = null) : IProgress<T> where TKey : notnull
{
    private readonly SynchronizationContext? _context = SynchronizationContext.Current;
    private readonly object _gate = new();
    private readonly Dictionary<TKey, T> _pending = [];
    private bool _scheduled;

    public void Report(T value)
    {
        onReport?.Invoke(value);
        lock (_gate)
        {
            _pending[keySelector(value)] = value;
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

    private void Drain()
    {
        T[] values;
        lock (_gate)
        {
            values = _pending.Values.ToArray();
            _pending.Clear();
        }
        try
        {
            foreach (var value in values)
                handler(value);
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
