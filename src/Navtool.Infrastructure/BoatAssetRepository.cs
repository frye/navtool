using System.Security.Cryptography;
using Navtool.Core;

namespace Navtool.Infrastructure;

public sealed class BoatAssetRepository : IBoatAssetService
{
    private readonly Func<string, BoatPolarFormat, CancellationToken, BoatValidationSummary> _inspect;
    private readonly Func<CancellationToken, BoatValidationSummary> _inspectDemo;
    private readonly string _demoIdentity;
    private readonly SemaphoreSlim _gate = new(1, 1);

    public BoatAssetRepository(string appDataRoot, NativeRouterBridge bridge)
        : this(
            appDataRoot,
            (path, format, token) => bridge.InspectPolar(path, format, cancellationToken: token),
            bridge is not null ? bridge.InspectDemoPolar : throw new ArgumentNullException(nameof(bridge)),
            $"demo:{bridge.BuildIdentity.SourceRevision}")
    {
    }

    internal BoatAssetRepository(
        string appDataRoot,
        Func<string, BoatPolarFormat, CancellationToken, BoatValidationSummary> inspect,
        Func<CancellationToken, BoatValidationSummary> inspectDemo,
        string demoIdentity)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(appDataRoot);
        ArgumentNullException.ThrowIfNull(inspect);
        ArgumentNullException.ThrowIfNull(inspectDemo);
        ArgumentException.ThrowIfNullOrWhiteSpace(demoIdentity);
        RootDirectory = Path.Combine(Path.GetFullPath(appDataRoot), "boats");
        _inspect = inspect;
        _inspectDemo = inspectDemo;
        _demoIdentity = demoIdentity;
    }

    public string RootDirectory { get; }

    public async ValueTask<BoatAsset> ImportAsync(
        string path,
        BoatPolarFormat format,
        CancellationToken cancellationToken = default)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(path);
        if (!Enum.IsDefined(format))
        {
            throw new ArgumentOutOfRangeException(nameof(format));
        }

        var source = Path.GetFullPath(path);
        if (!File.Exists(source))
        {
            throw new RoutingException(RoutingFailureKind.InvalidBoat, $"The selected polar file is missing: {source}");
        }

        var bytes = await File.ReadAllBytesAsync(source, cancellationToken).ConfigureAwait(false);
        if (bytes.Length == 0)
        {
            throw new RoutingException(RoutingFailureKind.InvalidBoat, "The selected polar file is empty.");
        }

        var identity = ContentIdentity(bytes);
        await _gate.WaitAsync(cancellationToken).ConfigureAwait(false);
        string? temporaryPath = null;
        try
        {
            Directory.CreateDirectory(RootDirectory);
            temporaryPath = Path.Combine(RootDirectory, $".{Guid.NewGuid():N}.tmp");
            await using (var stream = new FileStream(
                             temporaryPath, FileMode.CreateNew, FileAccess.Write, FileShare.None,
                             32 * 1024, FileOptions.Asynchronous | FileOptions.WriteThrough))
            {
                await stream.WriteAsync(bytes, cancellationToken).ConfigureAwait(false);
                await stream.FlushAsync(cancellationToken).ConfigureAwait(false);
                stream.Flush(true);
            }

            // Validate the immutable copy, not a source file that can change during parsing.
            var validation = await Task.Run(
                () => _inspect(temporaryPath, format, cancellationToken),
                cancellationToken).ConfigureAwait(false);
            cancellationToken.ThrowIfCancellationRequested();
            var destination = AssetPath(identity);
            if (File.Exists(destination))
            {
                _ = await ReadVerifiedBytesAsync(destination, identity, cancellationToken).ConfigureAwait(false);
            }
            else
            {
                File.Move(temporaryPath, destination, overwrite: false);
            }

            return new BoatAsset(identity, Path.GetFileName(source), BoatAssetKind.Imported, format, validation);
        }
        finally
        {
            if (temporaryPath is not null && File.Exists(temporaryPath))
            {
                File.Delete(temporaryPath);
            }

            _gate.Release();
        }
    }

    public async ValueTask<BoatAsset> GetDemoAsync(CancellationToken cancellationToken = default)
    {
        var validation = await Task.Run(
            () => _inspectDemo(cancellationToken), cancellationToken).ConfigureAwait(false);
        cancellationToken.ThrowIfCancellationRequested();
        return new BoatAsset(
            _demoIdentity, "Demo boat (not a calibrated vessel)", BoatAssetKind.Demo,
            BoatPolarFormat.Automatic, validation);
    }

    public async ValueTask<ResolvedBoatAsset> ResolveAsync(
        BoatAsset asset,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(asset);
        cancellationToken.ThrowIfCancellationRequested();
        if (asset.Kind == BoatAssetKind.Demo)
        {
            if (!string.Equals(asset.ContentIdentity, _demoIdentity, StringComparison.Ordinal))
            {
                throw new RoutingException(RoutingFailureKind.InvalidBoat,
                    "This plan references a different native demo boat revision. Explicitly select the current demo or import a polar.");
            }

            if (asset.MinimumTrueWindAngleDegrees is not null || asset.MaximumTrueWindAngleDegrees is not null)
            {
                throw new RoutingException(RoutingFailureKind.InvalidBoat, "The demo boat does not support angle restrictions.");
            }

            return new ResolvedBoatAsset(asset);
        }

        var path = AssetPath(asset.ContentIdentity);
        if (!File.Exists(path))
        {
            throw new RoutingException(RoutingFailureKind.InvalidBoat,
                $"The saved polar asset '{asset.SourceDisplayName}' is missing. Import the original polar again.");
        }

        var bytes = await ReadVerifiedBytesAsync(path, asset.ContentIdentity, cancellationToken).ConfigureAwait(false);
        return new ResolvedBoatAsset(asset, bytes);
    }

    private string AssetPath(string identity)
    {
        const string prefix = "sha256-";
        if (!identity.StartsWith(prefix, StringComparison.Ordinal) ||
            identity.Length != prefix.Length + 64 ||
            identity.AsSpan(prefix.Length).ContainsAnyExcept("0123456789abcdef"))
        {
            throw new RoutingException(RoutingFailureKind.InvalidBoat, "The saved polar asset has an invalid content identity.");
        }

        return Path.Combine(RootDirectory, identity + ".polar");
    }

    private static async ValueTask<byte[]> ReadVerifiedBytesAsync(
        string path, string identity, CancellationToken cancellationToken)
    {
        var bytes = await File.ReadAllBytesAsync(path, cancellationToken).ConfigureAwait(false);
        if (!string.Equals(ContentIdentity(bytes), identity, StringComparison.Ordinal))
        {
            throw new RoutingException(RoutingFailureKind.InvalidBoat,
                "The saved polar asset's contents have changed. Reimport the intended polar; demo substitution is disabled.");
        }

        return bytes;
    }

    private static string ContentIdentity(ReadOnlySpan<byte> bytes) =>
        "sha256-" + Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant();
}
