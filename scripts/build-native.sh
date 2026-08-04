#!/usr/bin/env sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
build_dir=${NAVTOOL_NATIVE_BUILD_DIR:-"$root/native/Navtool.RouterBridge/build"}
router_revision=${NAVTOOL_ROUTER_LIB_RELEASE_TAG:-"a98d5651d2273044c22f5fb6f54e4355af90392b"}

if [ -n "${SAILROUTE_SOURCE_DIR:-}" ]; then
  router_source=$SAILROUTE_SOURCE_DIR
  if [ ! -f "$router_source/CMakeLists.txt" ]; then
    echo "router-lib was not found at $router_source." >&2
    echo "Set SAILROUTE_SOURCE_DIR to your router-lib checkout and try again." >&2
    exit 1
  fi
  cmake -S "$root/native/Navtool.RouterBridge" -B "$build_dir" \
    -DCMAKE_BUILD_TYPE=Release \
    -DSAILROUTE_SOURCE_DIR="$router_source" \
    -DNAVTOOL_ROUTER_BRIDGE_BUILD_TESTS=ON
else
  cmake -S "$root/native/Navtool.RouterBridge" -B "$build_dir" \
    -DCMAKE_BUILD_TYPE=Release \
    -DNAVTOOL_ROUTER_LIB_RELEASE_TAG="$router_revision" \
    -DNAVTOOL_ROUTER_BRIDGE_BUILD_TESTS=ON
fi
cmake --build "$build_dir" --config Release --parallel
ctest --test-dir "$build_dir" -C Release --output-on-failure
