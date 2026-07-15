namespace Navtool.Infrastructure;

/// <summary>
/// Lightweight preflight contract that can verify native bridge availability
/// and ABI compatibility before any forecast acquisition is attempted.
/// </summary>
public interface INativeRoutingPreflight
{
    /// <summary>
    /// Verifies that the native router bridge library is present, exports the
    /// required ABI version, and is compatible with the current platform.
    /// Call this once at startup or before initiating HTTP forecast acquisition
    /// to surface problems early with actionable error messages.
    /// No GRIB file is loaded.
    /// </summary>
    /// <exception cref="NativeBridgeUnavailableException">
    /// The native library could not be found, does not export the versioned ABI,
    /// or is for an incompatible platform/architecture.
    /// </exception>
    /// <exception cref="NotSupportedException">
    /// The library ABI version is present but incompatible.
    /// </exception>
    void EnsureAvailable();
}
