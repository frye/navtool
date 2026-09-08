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
exec dotnet run --project "$REPO_ROOT/src/Navtool.App/Navtool.App.csproj" -- "$@"
