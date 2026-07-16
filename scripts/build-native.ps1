param(
    [string]$RouterSource = $env:SAILROUTE_SOURCE_DIR,
    [string]$BuildDirectory = $env:NAVTOOL_NATIVE_BUILD_DIR
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($BuildDirectory)) {
    $BuildDirectory = Join-Path $Root "native\Navtool.RouterBridge\build"
}

if ([string]::IsNullOrWhiteSpace($RouterSource)) {
    cmake -S (Join-Path $Root "native\Navtool.RouterBridge") -B $BuildDirectory `
        -DCMAKE_BUILD_TYPE=Release `
        -DNAVTOOL_ROUTER_BRIDGE_BUILD_TESTS=ON
}
else {
    if (-not (Test-Path (Join-Path $RouterSource "CMakeLists.txt"))) {
        throw "router-lib was not found at '$RouterSource'. Set SAILROUTE_SOURCE_DIR to your router-lib checkout and try again."
    }

    cmake -S (Join-Path $Root "native\Navtool.RouterBridge") -B $BuildDirectory `
        -DCMAKE_BUILD_TYPE=Release `
        -DSAILROUTE_SOURCE_DIR="$RouterSource" `
        -DNAVTOOL_ROUTER_BRIDGE_BUILD_TESTS=ON
}
cmake --build $BuildDirectory --config Release --parallel
ctest --test-dir $BuildDirectory -C Release --output-on-failure
