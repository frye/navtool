#!/usr/bin/env sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
router_source=${SAILROUTE_SOURCE_DIR:-"$root/../router-lib"}
build_dir=${NAVTOOL_NATIVE_BUILD_DIR:-"$root/native/Navtool.RouterBridge/build"}

cmake -S "$root/native/Navtool.RouterBridge" -B "$build_dir" \
  -DCMAKE_BUILD_TYPE=Release \
  -DSAILROUTE_SOURCE_DIR="$router_source" \
  -DNAVTOOL_ROUTER_BRIDGE_BUILD_TESTS=ON
cmake --build "$build_dir" --config Release --parallel
ctest --test-dir "$build_dir" -C Release --output-on-failure
