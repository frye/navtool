param(
    [string]$RouterSource = $env:SAILROUTE_SOURCE_DIR,
    [string]$BuildDirectory = $env:NAVTOOL_NATIVE_BUILD_DIR,
    [string]$RouterRevision = $env:NAVTOOL_ROUTER_LIB_RELEASE_TAG,
    [switch]$Diagnostics
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($BuildDirectory)) {
    $BuildDirectory = Join-Path $Root "native\Navtool.RouterBridge\build"
}
if ([string]::IsNullOrWhiteSpace($RouterRevision)) {
    $RouterRevision = "cd476a84ef3edea9582d77f21588a23af727e083"
}
$BuildDirectory = [IO.Path]::GetFullPath($BuildDirectory)
if (-not $BuildDirectory.StartsWith($Root + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Native build directory must be inside this worktree: $Root"
}

if ([string]::IsNullOrWhiteSpace($RouterSource)) {
    cmake -S (Join-Path $Root "native\Navtool.RouterBridge") -B $BuildDirectory `
        -DCMAKE_BUILD_TYPE=Release `
        -DSAILROUTE_SOURCE_DIR= `
        -DNAVTOOL_ROUTER_BRIDGE_RUN_DIAGNOSTICS="$($Diagnostics.IsPresent)" `
        -DNAVTOOL_ROUTER_LIB_RELEASE_TAG="$RouterRevision" `
        -DNAVTOOL_ROUTER_BRIDGE_BUILD_TESTS=ON
}
else {
    if (-not (Test-Path (Join-Path $RouterSource "CMakeLists.txt"))) {
        throw "router-lib was not found at '$RouterSource'. Set SAILROUTE_SOURCE_DIR to your router-lib checkout and try again."
    }

    cmake -S (Join-Path $Root "native\Navtool.RouterBridge") -B $BuildDirectory `
        -DCMAKE_BUILD_TYPE=Release `
        -DSAILROUTE_SOURCE_DIR="$RouterSource" `
        -DNAVTOOL_ROUTER_BRIDGE_RUN_DIAGNOSTICS="$($Diagnostics.IsPresent)" `
        -DNAVTOOL_ROUTER_BRIDGE_BUILD_TESTS=ON
}
if ($LASTEXITCODE -ne 0) { throw "Native configure failed ($LASTEXITCODE)." }
cmake --build $BuildDirectory --config Release --parallel
if ($LASTEXITCODE -ne 0) { throw "Native build failed ($LASTEXITCODE)." }
ctest --test-dir $BuildDirectory -C Release --output-on-failure
if ($LASTEXITCODE -ne 0) { throw "Native tests failed ($LASTEXITCODE)." }
