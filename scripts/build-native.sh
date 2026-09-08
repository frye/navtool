#!/usr/bin/env sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
build_dir=${NAVTOOL_NATIVE_BUILD_DIR:-"$root/native/Navtool.RouterBridge/build"}
router_revision=${NAVTOOL_ROUTER_LIB_RELEASE_TAG:-"cd476a84ef3edea9582d77f21588a23af727e083"}
case "$build_dir" in /*) ;; *) build_dir="$root/$build_dir" ;; esac
case "$build_dir/" in
  "$root/"*) ;;
  *) echo "Native build directory must be inside this worktree: $root" >&2; exit 1 ;;
esac
case "$build_dir/" in */../*) echo "Native build directory cannot contain parent traversal." >&2; exit 1 ;; esac
if [ -d "$build_dir" ]; then
  case "$(CDPATH= cd -- "$build_dir" && pwd -P)/" in
    "$root/"*) ;;
    *) echo "Native build directory resolves outside this worktree." >&2; exit 1 ;;
  esac
fi

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
    -DNAVTOOL_ROUTER_BRIDGE_RUN_DIAGNOSTICS="${NAVTOOL_NATIVE_DIAGNOSTICS:-OFF}" \
    -DNAVTOOL_ROUTER_BRIDGE_BUILD_TESTS=ON
else
  cmake -S "$root/native/Navtool.RouterBridge" -B "$build_dir" \
    -DCMAKE_BUILD_TYPE=Release \
    -DSAILROUTE_SOURCE_DIR= \
    -DNAVTOOL_ROUTER_BRIDGE_RUN_DIAGNOSTICS="${NAVTOOL_NATIVE_DIAGNOSTICS:-OFF}" \
    -DNAVTOOL_ROUTER_LIB_RELEASE_TAG="$router_revision" \
    -DNAVTOOL_ROUTER_BRIDGE_BUILD_TESTS=ON
fi
cmake --build "$build_dir" --config Release --parallel
ctest --test-dir "$build_dir" -C Release --output-on-failure
