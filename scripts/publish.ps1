param(
    [Parameter(Mandatory = $true)]
    [string]$RuntimeIdentifier,
    [string]$BuildDirectory = $env:NAVTOOL_NATIVE_BUILD_DIR
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($BuildDirectory)) {
    $BuildDirectory = Join-Path $Root "native\Navtool.RouterBridge\build"
}

$Output = Join-Path $Root "artifacts\$RuntimeIdentifier"
$NativeOutput = Join-Path $Output "runtimes\$RuntimeIdentifier\native"
if (Test-Path $Output) {
    Remove-Item -Path $Output -Recurse -Force
}
dotnet publish (Join-Path $Root "src\Navtool.App\Navtool.App.csproj") `
    --configuration Release `
    --runtime $RuntimeIdentifier `
    --self-contained false `
    --output $Output

New-Item -ItemType Directory -Force -Path $NativeOutput | Out-Null
$Pattern = switch -Wildcard ($RuntimeIdentifier) {
    "win-*" { "navtool_router_bridge.dll"; break }
    "osx-*" { "libnavtool_router_bridge*.dylib"; break }
    "linux-*" { "libnavtool_router_bridge*.so*"; break }
    default { throw "Unsupported runtime identifier: $RuntimeIdentifier" }
}

$Libraries = Get-ChildItem -Path $BuildDirectory -Filter $Pattern -File
if ($Libraries.Count -eq 0) {
    throw "Native bridge not found in $BuildDirectory. Run scripts\build-native.ps1 on the target platform first."
}
$Libraries | Copy-Item -Destination $NativeOutput -Force
