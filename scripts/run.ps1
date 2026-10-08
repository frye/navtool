$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
& (Join-Path $PSScriptRoot "build-native.ps1")
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

$env:NAVTOOL_ROUTER_BRIDGE_PATH = if (
    [string]::IsNullOrWhiteSpace($env:NAVTOOL_NATIVE_BUILD_DIR)
) {
    Join-Path $repoRoot "native/Navtool.RouterBridge/build"
} else {
    $env:NAVTOOL_NATIVE_BUILD_DIR
}
$NativeLibrary = Join-Path $env:NAVTOOL_ROUTER_BRIDGE_PATH "Release\navtool_router_bridge.dll"
if (-not (Test-Path $NativeLibrary)) {
    $NativeLibrary = Join-Path $env:NAVTOOL_ROUTER_BRIDGE_PATH "navtool_router_bridge.dll"
}
if (-not (Test-Path $NativeLibrary)) { throw "Current-worktree native bridge was not produced." }
$env:NAVTOOL_ROUTER_BRIDGE_PATH = $NativeLibrary
dotnet run --project (Join-Path $repoRoot "src/Navtool.App/Navtool.App.csproj") -- @args
exit $LASTEXITCODE
