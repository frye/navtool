#!/usr/bin/env sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
router_source=${SAILROUTE_SOURCE_DIR:-"$root/../router-lib"}
build_dir=${NAVTOOL_NATIVE_BUILD_DIR:-"$root/native/Navtool.RouterBridge/build"}

if [ ! -f "$router_source/CMakeLists.txt" ]; then
  echo "router-lib was not found at $router_source." >&2
  echo "Set SAILROUTE_SOURCE_DIR to your router-lib checkout and try again." >&2
  exit 1
fi

cmake -S "$root/native/Navtool.RouterBridge" -B "$build_dir" \
  -DCMAKE_BUILD_TYPE=Release \
  -DSAILROUTE_SOURCE_DIR="$router_source" \
  -DNAVTOOL_ROUTER_BRIDGE_BUILD_TESTS=ON
cmake --build "$build_dir" --config Release --parallel
ctest --test-dir "$build_dir" -C Release --output-on-failure
