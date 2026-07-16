using System.Text;
using System.Text.Json;
using Microsoft.Extensions.Logging;

namespace Navtool.Infrastructure;

public sealed record RollingFileLoggerOptions
{
    public RollingFileLoggerOptions(
        string directory,
        long maximumFileBytes = 5L * 1024 * 1024,
        int retainedFileCount = 5)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(directory);
        if (maximumFileBytes <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(maximumFileBytes));
        }

        if (retainedFileCount <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(retainedFileCount));
        }

        Directory = Path.GetFullPath(directory);
        MaximumFileBytes = maximumFileBytes;
        RetainedFileCount = retainedFileCount;
    }

    public string Directory { get; }

    public long MaximumFileBytes { get; }

    public int RetainedFileCount { get; }
}

public sealed class RollingFileLoggerProvider : ILoggerProvider
{
    private const string CurrentFileName = "navtool.log";
    private readonly RollingFileLoggerOptions _options;
    private readonly object _gate = new();
    private StreamWriter? _writer;
    private bool _disposed;

    public RollingFileLoggerProvider(RollingFileLoggerOptions options)
    {
        ArgumentNullException.ThrowIfNull(options);
        _options = options;
        Directory.CreateDirectory(options.Directory);
        DeleteArchivesOutsideRetention(options.RetainedFileCount - 1);
    }

    public string CurrentPath => Path.Combine(_options.Directory, CurrentFileName);

    public ILogger CreateLogger(string categoryName)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        return new RollingFileLogger(this, categoryName);
    }

    public void Dispose()
    {
        lock (_gate)
        {
            if (_disposed)
            {
                return;
            }

            _writer?.Dispose();
            _writer = null;
            _disposed = true;
        }
    }

    private void Write(
        string category,
        LogLevel level,
        EventId eventId,
        string message,
        Exception? exception)
    {
        var record = new FileLogRecord(
            DateTimeOffset.UtcNow,
            level.ToString(),
            category,
            eventId.Id,
            eventId.Name,
            message,
            exception?.ToString());
        var line = JsonSerializer.Serialize(record);
        var encodedLength = Encoding.UTF8.GetByteCount(line) + Environment.NewLine.Length;

        lock (_gate)
        {
            ObjectDisposedException.ThrowIf(_disposed, this);
            try
            {
                EnsureWriter();
                if (_writer!.BaseStream.Length > 0 &&
                    _writer.BaseStream.Length + encodedLength > _options.MaximumFileBytes)
                {
                    RollFiles();
                    EnsureWriter();
                }

                _writer!.WriteLine(line);
            }
            catch (IOException ioException)
            {
                WriteFallback(line, ioException);
            }
            catch (UnauthorizedAccessException accessException)
            {
                WriteFallback(line, accessException);
            }
        }
    }

    private void EnsureWriter()
    {
        if (_writer is not null)
        {
            return;
        }

        Directory.CreateDirectory(_options.Directory);
        var stream = new FileStream(
            CurrentPath,
            FileMode.Append,
            FileAccess.Write,
            FileShare.Read,
            16 * 1024,
            FileOptions.SequentialScan);
        _writer = new StreamWriter(stream, new UTF8Encoding(false))
        {
            AutoFlush = true
        };
    }

    private void RollFiles()
    {
        _writer?.Dispose();
        _writer = null;

        var oldestIndex = _options.RetainedFileCount - 1;
        DeleteArchivesOutsideRetention(oldestIndex);
        if (oldestIndex > 0)
        {
            File.Delete(ArchivePath(oldestIndex));
            for (var index = oldestIndex - 1; index >= 1; index--)
            {
                var source = ArchivePath(index);
                if (File.Exists(source))
                {
                    File.Move(source, ArchivePath(index + 1), true);
                }
            }

            if (File.Exists(CurrentPath))
            {
                File.Move(CurrentPath, ArchivePath(1), true);
            }
        }
        else
        {
            File.Delete(CurrentPath);
        }
    }

    private string ArchivePath(int index) =>
        Path.Combine(_options.Directory, $"navtool.{index}.log");

    private void DeleteArchivesOutsideRetention(int oldestRetainedIndex)
    {
        foreach (var path in Directory.EnumerateFiles(
                     _options.Directory,
                     "navtool.*.log",
                     SearchOption.TopDirectoryOnly))
        {
            var fileName = Path.GetFileNameWithoutExtension(path);
            var suffix = fileName["navtool.".Length..];
            if (int.TryParse(suffix, out var index) && index > oldestRetainedIndex)
            {
                File.Delete(path);
            }
        }
    }

    private static void WriteFallback(string line, Exception exception)
    {
        Console.Error.WriteLine(
            $"Navtool file logging failed: {exception.GetType().Name}: {exception.Message}");
        Console.Error.WriteLine(line);
    }

    private sealed record FileLogRecord(
        DateTimeOffset Timestamp,
        string Level,
        string Category,
        int EventId,
        string? EventName,
        string Message,
        string? Exception);

    private sealed class RollingFileLogger(
        RollingFileLoggerProvider provider,
        string category) : ILogger
    {
        public IDisposable? BeginScope<TState>(TState state) where TState : notnull => null;

        public bool IsEnabled(LogLevel logLevel) => logLevel != LogLevel.None;

        public void Log<TState>(
            LogLevel logLevel,
            EventId eventId,
            TState state,
            Exception? exception,
            Func<TState, Exception?, string> formatter)
        {
            ArgumentNullException.ThrowIfNull(formatter);
            if (IsEnabled(logLevel))
            {
                provider.Write(category, logLevel, eventId, formatter(state, exception), exception);
            }
        }
    }
}
