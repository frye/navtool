using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Navtool.Core;

namespace Navtool.Infrastructure;

public sealed record AtomicFileCacheOptions
{
    public AtomicFileCacheOptions(
        string rootDirectory,
        long maximumBytes = 2L * 1024 * 1024 * 1024,
        int maximumEntries = 64)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(rootDirectory);
        if (maximumBytes <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(maximumBytes));
        }

        if (maximumEntries <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(maximumEntries));
        }

        RootDirectory = Path.GetFullPath(rootDirectory);
        MaximumBytes = maximumBytes;
        MaximumEntries = maximumEntries;
    }

    public string RootDirectory { get; }

    public long MaximumBytes { get; }

    public int MaximumEntries { get; }
}

public sealed record AtomicCacheEntry(
    string Key,
    string Path,
    long LengthBytes,
    CacheMetadata Metadata);

public sealed class AtomicFileCache
{
    private const string ArtifactExtension = ".grib2";
    private const string MetadataExtension = ".metadata.json";
    private readonly AtomicFileCacheOptions _options;
    private readonly SemaphoreSlim _gate = new(1, 1);

    public AtomicFileCache(AtomicFileCacheOptions options)
    {
        ArgumentNullException.ThrowIfNull(options);
        _options = options;
        Directory.CreateDirectory(_options.RootDirectory);
    }

    public string RootDirectory => _options.RootDirectory;

    public long MaximumBytes => _options.MaximumBytes;

    public int MaximumEntries => _options.MaximumEntries;

    public static string CreateKey(string category, params string[] components)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(category);
        ArgumentNullException.ThrowIfNull(components);
        if (components.Any(string.IsNullOrWhiteSpace))
        {
            throw new ArgumentException("Cache key components cannot be null or whitespace.", nameof(components));
        }

        var prefix = Sanitize(category);
        using var hash = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
        AddHashPart(hash, category);
        foreach (var component in components)
        {
            AddHashPart(hash, component);
        }

        return $"{prefix}-{Convert.ToHexString(hash.GetHashAndReset()).ToLowerInvariant()}";
    }

    public async ValueTask<AtomicCacheEntry?> TryGetFreshAsync(
        string key,
        DateTimeOffset now,
        CancellationToken cancellationToken = default)
    {
        ValidateKey(key);
        cancellationToken.ThrowIfCancellationRequested();
        await _gate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            var metadataPath = GetMetadataPath(key);
            var artifactPath = GetArtifactPath(key);
            if (!File.Exists(metadataPath) || !File.Exists(artifactPath))
            {
                return null;
            }

            var stored = await ReadMetadataAsync(metadataPath, cancellationToken).ConfigureAwait(false);
            ValidateStoredMetadata(stored, key, metadataPath);
            var file = new FileInfo(artifactPath);
            if (file.Length != stored.LengthBytes)
            {
                throw new InvalidDataException(
                    $"Cache artifact '{artifactPath}' length does not match its metadata.");
            }

            var metadata = new CacheMetadata(stored.Key, stored.CreatedAt, stored.ExpiresAt);
            if (!metadata.IsFreshAt(now))
            {
                return null;
            }

            return new AtomicCacheEntry(key, artifactPath, file.Length, metadata);
        }
        finally
        {
            _gate.Release();
        }
    }

    public async ValueTask<AtomicCacheEntry> StoreAsync(
        string key,
        DateTimeOffset createdAt,
        DateTimeOffset expiresAt,
        Func<Stream, CancellationToken, ValueTask> writeArtifact,
        CancellationToken cancellationToken = default)
    {
        ValidateKey(key);
        ArgumentNullException.ThrowIfNull(writeArtifact);
        var metadata = new CacheMetadata(key, createdAt, expiresAt);
        cancellationToken.ThrowIfCancellationRequested();
        await _gate.WaitAsync(cancellationToken).ConfigureAwait(false);

        var token = Guid.NewGuid().ToString("N");
        var artifactTemp = Path.Combine(_options.RootDirectory, $".{key}.{token}.partial");
        var metadataTemp = Path.Combine(_options.RootDirectory, $".{key}.{token}.metadata.partial");
        try
        {
            long length;
            await using (var output = new FileStream(
                             artifactTemp,
                             FileMode.CreateNew,
                             FileAccess.Write,
                             FileShare.None,
                             128 * 1024,
                             FileOptions.Asynchronous | FileOptions.WriteThrough))
            {
                await writeArtifact(output, cancellationToken).ConfigureAwait(false);
                await output.FlushAsync(cancellationToken).ConfigureAwait(false);
                output.Flush(true);
                length = output.Length;
            }

            if (length <= 0)
            {
                throw new InvalidDataException("A cache artifact cannot be empty.");
            }

            var stored = new StoredCacheMetadata(
                key,
                metadata.CreatedAt,
                metadata.ExpiresAt,
                length);
            await using (var output = new FileStream(
                             metadataTemp,
                             FileMode.CreateNew,
                             FileAccess.Write,
                             FileShare.None,
                             16 * 1024,
                             FileOptions.Asynchronous | FileOptions.WriteThrough))
            {
                await JsonSerializer.SerializeAsync(output, stored, cancellationToken: cancellationToken)
                    .ConfigureAwait(false);
                await output.FlushAsync(cancellationToken).ConfigureAwait(false);
                output.Flush(true);
            }

            cancellationToken.ThrowIfCancellationRequested();
            var artifactPath = GetArtifactPath(key);
            var metadataPath = GetMetadataPath(key);
            File.Move(artifactTemp, artifactPath, true);
            File.Move(metadataTemp, metadataPath, true);

            await EvictIfNeededAsync(key, createdAt, CancellationToken.None).ConfigureAwait(false);
            return new AtomicCacheEntry(key, artifactPath, length, metadata);
        }
        finally
        {
            DeleteIfPresent(artifactTemp);
            DeleteIfPresent(metadataTemp);
            _gate.Release();
        }
    }

    public ValueTask<AtomicCacheEntry> StoreAsync(
        string key,
        DateTimeOffset createdAt,
        DateTimeOffset expiresAt,
        ReadOnlyMemory<byte> artifact,
        CancellationToken cancellationToken = default) =>
        StoreAsync(
            key,
            createdAt,
            expiresAt,
            (stream, token) => stream.WriteAsync(artifact, token),
            cancellationToken);

    private async ValueTask EvictIfNeededAsync(
        string protectedKey,
        DateTimeOffset now,
        CancellationToken cancellationToken)
    {
        var entries = new List<StoredEntry>();
        foreach (var metadataPath in Directory.EnumerateFiles(
                     _options.RootDirectory,
                     $"*{MetadataExtension}",
                     SearchOption.TopDirectoryOnly))
        {
            cancellationToken.ThrowIfCancellationRequested();
            var stored = await ReadMetadataAsync(metadataPath, cancellationToken).ConfigureAwait(false);
            ValidateStoredMetadata(stored, stored.Key, metadataPath);
            var artifactPath = GetArtifactPath(stored.Key);
            if (!File.Exists(artifactPath))
            {
                File.Delete(metadataPath);
                continue;
            }

            var actualLength = new FileInfo(artifactPath).Length;
            if (actualLength != stored.LengthBytes)
            {
                throw new InvalidDataException(
                    $"Cache artifact '{artifactPath}' length does not match its metadata.");
            }

            entries.Add(new StoredEntry(stored, artifactPath, metadataPath));
        }

        var count = entries.Count;
        var bytes = entries.Sum(entry => entry.Metadata.LengthBytes);
        foreach (var entry in entries
                     .Where(entry => !string.Equals(entry.Metadata.Key, protectedKey, StringComparison.Ordinal))
                     .OrderBy(entry => entry.Metadata.ExpiresAt > now)
                     .ThenBy(entry => entry.Metadata.CreatedAt)
                     .ThenBy(entry => entry.Metadata.Key, StringComparer.Ordinal))
        {
            if (count <= _options.MaximumEntries && bytes <= _options.MaximumBytes)
            {
                break;
            }

            File.Delete(entry.ArtifactPath);
            File.Delete(entry.MetadataPath);
            count--;
            bytes -= entry.Metadata.LengthBytes;
        }

        var protectedEntry = entries.First(entry =>
            string.Equals(entry.Metadata.Key, protectedKey, StringComparison.Ordinal));
        if (count > _options.MaximumEntries || bytes > _options.MaximumBytes)
        {
            File.Delete(protectedEntry.ArtifactPath);
            File.Delete(protectedEntry.MetadataPath);
            throw new IOException(
                $"Cache artifact '{protectedKey}' exceeds the configured cache bounds.");
        }
    }

    private async ValueTask<StoredCacheMetadata> ReadMetadataAsync(
        string path,
        CancellationToken cancellationToken)
    {
        try
        {
            await using var input = new FileStream(
                path,
                FileMode.Open,
                FileAccess.Read,
                FileShare.Read,
                16 * 1024,
                FileOptions.Asynchronous | FileOptions.SequentialScan);
            return await JsonSerializer.DeserializeAsync<StoredCacheMetadata>(
                       input,
                       cancellationToken: cancellationToken)
                       .ConfigureAwait(false) ??
                   throw new InvalidDataException($"Cache metadata '{path}' is empty.");
        }
        catch (JsonException exception)
        {
            throw new InvalidDataException($"Cache metadata '{path}' is invalid JSON.", exception);
        }
    }

    private static void ValidateStoredMetadata(
        StoredCacheMetadata stored,
        string expectedKey,
        string metadataPath)
    {
        if (!string.Equals(stored.Key, expectedKey, StringComparison.Ordinal) ||
            stored.LengthBytes <= 0 ||
            stored.ExpiresAt < stored.CreatedAt)
        {
            throw new InvalidDataException($"Cache metadata '{metadataPath}' is inconsistent.");
        }
    }

    private string GetArtifactPath(string key) =>
        Path.Combine(_options.RootDirectory, key + ArtifactExtension);

    private string GetMetadataPath(string key) =>
        Path.Combine(_options.RootDirectory, key + MetadataExtension);

    private static void ValidateKey(string key)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(key);
        if (key.Length > 160 ||
            key is "." or ".." ||
            key.Any(character =>
                !(character is >= 'a' and <= 'z' or
                  >= '0' and <= '9' or
                  '-' or '_' or '.')))
        {
            throw new ArgumentException("The cache key is not a deterministic sanitized key.", nameof(key));
        }
    }

    private static string Sanitize(string value)
    {
        var builder = new StringBuilder(Math.Min(value.Length, 48));
        foreach (var character in value.ToLowerInvariant())
        {
            var sanitized = character is >= 'a' and <= 'z' or >= '0' and <= '9' or '-' or '_' or '.'
                ? character
                : '-';
            if (builder.Length == 0 || sanitized != '-' || builder[^1] != '-')
            {
                builder.Append(sanitized);
            }

            if (builder.Length == 48)
            {
                break;
            }
        }

        var result = builder.ToString().Trim('-', '.');
        return string.IsNullOrEmpty(result) ? "cache" : result;
    }

    private static void AddHashPart(IncrementalHash hash, string value)
    {
        var bytes = Encoding.UTF8.GetBytes(value);
        Span<byte> length = stackalloc byte[4];
        System.Buffers.Binary.BinaryPrimitives.WriteInt32LittleEndian(length, bytes.Length);
        hash.AppendData(length);
        hash.AppendData(bytes);
    }

    private static void DeleteIfPresent(string path)
    {
        try
        {
            File.Delete(path);
        }
        catch (DirectoryNotFoundException)
        {
        }
    }

    private sealed record StoredCacheMetadata(
        string Key,
        DateTimeOffset CreatedAt,
        DateTimeOffset ExpiresAt,
        long LengthBytes);

    private sealed record StoredEntry(
        StoredCacheMetadata Metadata,
        string ArtifactPath,
        string MetadataPath);
}
