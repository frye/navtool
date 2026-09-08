#!/usr/bin/env sh
set -eu

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <runtime-identifier>" >&2
  exit 2
fi

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
rid=$1
case "$(uname -s)/$(uname -m)/$rid" in
  Darwin/arm64/osx-arm64|Linux/x86_64/linux-x64) ;;
  *) echo "RID $rid does not match the supported native host; RID selection does not cross-compile." >&2; exit 2 ;;
esac
output="$root/artifacts/$rid"
native_dir="$output/runtimes/$rid/native"
build_dir=${NAVTOOL_NATIVE_BUILD_DIR:-"$root/native/Navtool.RouterBridge/build"}
case "$build_dir" in /*) ;; *) build_dir="$root/$build_dir" ;; esac
"$root/scripts/build-native.sh"

rm -rf "$output"
dotnet publish "$root/src/Navtool.App/Navtool.App.csproj" \
  --configuration Release \
  --runtime "$rid" \
  --self-contained false \
  --output "$output"

mkdir -p "$native_dir"
case "$rid" in
  win-*) pattern='navtool_router_bridge.dll' ;;
  osx-*) pattern='libnavtool_router_bridge*.dylib' ;;
  linux-*) pattern='libnavtool_router_bridge*.so*' ;;
  *)
    echo "Unsupported runtime identifier: $rid" >&2
    exit 2
    ;;
esac

found=0
for library in "$build_dir"/$pattern; do
  if [ -f "$library" ]; then
    cp "$library" "$native_dir/"
    found=1
  fi
done

if [ "$found" -ne 1 ]; then
  echo "Native bridge not found in $build_dir; run scripts/build-native.sh on the target platform first." >&2
  exit 1
fi
for library in "$native_dir"/$pattern; do
  if [ -f "$library" ]; then
    "$build_dir/navtool_router_bridge_preflight" "$library" > "$output/native-build-info.json"
    break
  fi
done
