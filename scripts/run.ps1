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
dotnet run --project (Join-Path $repoRoot "src/Navtool.App/Navtool.App.csproj") -- @args
exit $LASTEXITCODE
