#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

"$SCRIPT_DIR/build-native.sh"

native_build_dir="${NAVTOOL_NATIVE_BUILD_DIR:-"$REPO_ROOT/native/Navtool.RouterBridge/build"}"
if [[ "$native_build_dir" != /* ]]; then
  native_build_dir="$REPO_ROOT/$native_build_dir"
fi
export NAVTOOL_ROUTER_BRIDGE_PATH="$native_build_dir"

if [[ "$(uname -s)" == "Darwin" ]]; then
  project="$REPO_ROOT/src/Navtool.App/Navtool.App.csproj"
  icon="$REPO_ROOT/src/Navtool.App/Assets/Navtool.icns"

  for tool in sips DeRez Rez SetFile xattr; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      echo "Required macOS icon tool is unavailable: $tool" >&2
      exit 1
    fi
  done

  dotnet build "$project"
  target_path="$(
    dotnet msbuild "$project" -getProperty:TargetPath -nologo |
      sed -E -n \
        -e 's/^[[:space:]]*Property:[[:space:]]*TargetPath=[[:space:]]*//' \
        -e 's/^[[:space:]]*TargetPath=[[:space:]]*//' \
        -e '/^[[:space:]]*$/d' \
        -e 'p' |
      tail -n 1
  )"
  apphost="${target_path%.dll}"
  if [[ ! -x "$apphost" ]]; then
    echo "Navtool apphost was not produced at $apphost" >&2
    exit 1
  fi

  # Raw macOS apphosts need Finder icon metadata for Dock branding.
  icon_work_dir="$(mktemp -d)"
  trap 'rm -rf "$icon_work_dir"' EXIT
  cp "$icon" "$icon_work_dir/Navtool.icns"
  sips -i "$icon_work_dir/Navtool.icns" >/dev/null
  DeRez -only icns "$icon_work_dir/Navtool.icns" > "$icon_work_dir/Navtool.rsrc"
  if xattr -p com.apple.ResourceFork "$apphost" >/dev/null 2>&1; then
    xattr -d com.apple.ResourceFork "$apphost"
  fi
  SetFile -a c "$apphost"
  Rez -append "$icon_work_dir/Navtool.rsrc" -o "$apphost"
  SetFile -a C "$apphost"

  if [[ -z "${DOTNET_ROOT:-}" ]]; then
    DOTNET_ROOT="$(
      dotnet --list-runtimes |
        sed -n '/^Microsoft\.NETCore\.App /s#.*\[\(.*\)/shared/Microsoft\.NETCore\.App\]#\1#p' |
        head -n 1
    )"
    export DOTNET_ROOT
  fi
  if [[ ! -d "$DOTNET_ROOT/host/fxr" ]]; then
    echo "Could not resolve a valid DOTNET_ROOT from the active dotnet installation" >&2
    exit 1
  fi

  rm -rf "$icon_work_dir"
  trap - EXIT
  exec "$apphost" "$@"
fi

exec dotnet run --project "$REPO_ROOT/src/Navtool.App/Navtool.App.csproj" -- "$@"
