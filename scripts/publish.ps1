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
$Architecture = [Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString().ToLowerInvariant()
$Platform = if ([Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([Runtime.InteropServices.OSPlatform]::Windows)) {
    "win"
} elseif ([Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([Runtime.InteropServices.OSPlatform]::OSX)) {
    "osx"
} else { "linux" }
if ($RuntimeIdentifier -ne "$Platform-$Architecture" -or $RuntimeIdentifier -notin @("win-x64", "osx-arm64", "linux-x64")) {
    throw "RID $RuntimeIdentifier does not match the supported native host; RID selection does not cross-compile."
}
& (Join-Path $PSScriptRoot "build-native.ps1") -BuildDirectory $BuildDirectory

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
if ($LASTEXITCODE -ne 0) { throw "Managed publish failed ($LASTEXITCODE)." }

New-Item -ItemType Directory -Force -Path $NativeOutput | Out-Null
$Pattern = switch -Wildcard ($RuntimeIdentifier) {
    "win-*" { "navtool_router_bridge.dll"; break }
    "osx-*" { "libnavtool_router_bridge*.dylib"; break }
    "linux-*" { "libnavtool_router_bridge*.so*"; break }
    default { throw "Unsupported runtime identifier: $RuntimeIdentifier" }
}

$ConfigurationDirectory = Join-Path $BuildDirectory "Release"
$NativeBuildDirectory = if (Test-Path (Join-Path $ConfigurationDirectory $Pattern)) { $ConfigurationDirectory } else { $BuildDirectory }
$Libraries = @(Get-ChildItem -Path $NativeBuildDirectory -Filter $Pattern -File)
if ($Libraries.Count -eq 0) {
    throw "Native bridge not found in $BuildDirectory. Run scripts\build-native.ps1 on the target platform first."
}
$Libraries | Copy-Item -Destination $NativeOutput -Force
$PreflightName = if ($Platform -eq "win") { "navtool_router_bridge_preflight.exe" } else { "navtool_router_bridge_preflight" }
$Preflight = Join-Path $NativeBuildDirectory $PreflightName
& $Preflight (Join-Path $NativeOutput $Libraries[0].Name) | Set-Content (Join-Path $Output "native-build-info.json")
if ($LASTEXITCODE -ne 0) { throw "Packaged native bridge preflight failed ($LASTEXITCODE)." }
