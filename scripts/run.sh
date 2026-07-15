#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

"$SCRIPT_DIR/build-native.sh"

export NAVTOOL_ROUTER_BRIDGE_PATH="${NAVTOOL_NATIVE_BUILD_DIR:-"$REPO_ROOT/native/Navtool.RouterBridge/build"}"
exec dotnet run --project "$REPO_ROOT/src/Navtool.App/Navtool.App.csproj" -- "$@"
