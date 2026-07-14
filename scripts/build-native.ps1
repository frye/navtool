param(
    [string]$RouterSource = $env:SAILROUTE_SOURCE_DIR,
    [string]$BuildDirectory = $env:NAVTOOL_NATIVE_BUILD_DIR
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($RouterSource)) {
    $RouterSource = Join-Path $Root "..\router-lib"
}
if ([string]::IsNullOrWhiteSpace($BuildDirectory)) {
    $BuildDirectory = Join-Path $Root "native\Navtool.RouterBridge\build"
}

cmake -S (Join-Path $Root "native\Navtool.RouterBridge") -B $BuildDirectory `
    -DCMAKE_BUILD_TYPE=Release `
    -DSAILROUTE_SOURCE_DIR="$RouterSource" `
    -DNAVTOOL_ROUTER_BRIDGE_BUILD_TESTS=ON
cmake --build $BuildDirectory --config Release --parallel
ctest --test-dir $BuildDirectory -C Release --output-on-failure
