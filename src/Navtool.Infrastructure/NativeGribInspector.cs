using Navtool.Core;

namespace Navtool.Infrastructure;

/// <summary>
/// Inspects a local GRIB file and returns a <see cref="LocalForecastDescriptor"/>
/// populated from the file's ecCodes metadata without copying or retaining the file.
/// </summary>
public interface ILocalGribInspector
{
    /// <summary>
    /// Reads model identity, initialization time, validity range, and geographic bounds
    /// from the GRIB file at <paramref name="absolutePath"/>.
    /// </summary>
    /// <param name="absolutePath">Absolute path to the GRIB file. The file is read in
    /// place and is never copied.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>A descriptor for the file-based forecast.</returns>
    /// <exception cref="ArgumentException">
    /// <paramref name="absolutePath"/> is null, empty, whitespace, or relative.
    /// </exception>
    /// <exception cref="FileNotFoundException">The file does not exist.</exception>
    /// <exception cref="NativeBridgeUnavailableException">
    /// The native router bridge library is absent or incompatible.
    /// </exception>
    /// <exception cref="NativeRouterException">
    /// The GRIB file is malformed, incomplete, model-ambiguous, or from an unsupported model.
    /// </exception>
    ValueTask<LocalForecastDescriptor> InspectAsync(
        string absolutePath,
        CancellationToken cancellationToken = default);
}

/// <summary>
/// Implementation of <see cref="ILocalGribInspector"/> backed by the native
/// router bridge and ecCodes. Model identity is determined from the GRIB
/// <c>centre</c> key (not the filename).
/// </summary>
public sealed class NativeLocalGribInspector : ILocalGribInspector
{
    private readonly NativeRouterBridge _bridge;

    public NativeLocalGribInspector(NativeRouterBridge? bridge = null)
    {
        _bridge = bridge ?? new NativeRouterBridge();
    }

    public ValueTask<LocalForecastDescriptor> InspectAsync(
        string absolutePath,
        CancellationToken cancellationToken = default)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(absolutePath);
        if (!Path.IsPathFullyQualified(absolutePath))
        {
            throw new ArgumentException(
                "The GRIB path must be absolute.",
                nameof(absolutePath));
        }

        var descriptor = _bridge.InspectGrib(absolutePath, cancellationToken);

        var model = descriptor.ModelId switch
        {
            NativeGribModelId.NoaaGfs => ForecastModel.NoaaGfs,
            NativeGribModelId.EcmwfIfs => ForecastModel.EcmwfIfs,
            _ => throw new NativeRouteFormatException(
                $"Unrecognized GRIB model identifier {(int)descriptor.ModelId} " +
                $"returned from '{absolutePath}'; " +
                $"only NOAA GFS and ECMWF IFS are supported.")
        };

        var fileInfo = new FileInfo(absolutePath);
        var artifact = fileInfo.Exists
            ? new LocalGribArtifact(absolutePath, fileInfo.Length, fileInfo.LastWriteTimeUtc)
            : new LocalGribArtifact(absolutePath);

        try
        {
            return ValueTask.FromResult(new LocalForecastDescriptor(
                model,
                artifact,
                descriptor.InitializedAt,
                descriptor.FirstValidAt,
                descriptor.LastValidAt,
                new GeographicBounds(
                    descriptor.SouthLatitudeDegrees,
                    descriptor.NorthLatitudeDegrees,
                    descriptor.WestLongitudeDegrees,
                    descriptor.EastLongitudeDegrees)));
        }
        catch (ArgumentException exception) when (exception is not ArgumentNullException)
        {
            throw new NativeRouteFormatException(
                $"The GRIB file at '{absolutePath}' returned invalid geographic bounds " +
                $"or timestamps: {exception.Message}",
                exception);
        }
    }
}
