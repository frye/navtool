using System.IO.Compression;
using Navtool.Core;

namespace Navtool.Infrastructure;

public sealed class NaturalEarthLandDataProvider : ILandDataProvider
{
    public const string Attribution =
        "Made with Natural Earth (1:10m land polygons, public domain)";

    private const string ResourceName =
        "Navtool.Infrastructure.Assets.ne_10m_land.geojson.gz";

    private static readonly Lazy<Task<LandDataAcquisition>> SharedAcquisition =
        new(
            () => Task.Run(Load),
            LazyThreadSafetyMode.ExecutionAndPublication);

    public async ValueTask<LandDataAcquisition> AcquireAsync(
        GeographicBounds bounds,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        return await SharedAcquisition.Value
            .WaitAsync(cancellationToken)
            .ConfigureAwait(false);
    }

    private static LandDataAcquisition Load()
    {
        using var resource = typeof(NaturalEarthLandDataProvider)
            .Assembly
            .GetManifestResourceStream(ResourceName) ??
            throw new InvalidDataException(
                $"Bundled land resource '{ResourceName}' was not found.");
        using var compressed = new GZipStream(
            resource,
            CompressionMode.Decompress);
        using var reader = new StreamReader(compressed);
        var payload = GeoJsonLandParser.Parse(reader.ReadToEnd());
        return new LandDataAcquisition(
            LandDataStatus.Available,
            new LandGeometryIndex(payload.Geometries),
            null,
            Attribution);
    }
}
