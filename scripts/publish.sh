#!/usr/bin/env sh
set -eu

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <runtime-identifier>" >&2
  exit 2
fi

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
rid=$1
output="$root/artifacts/$rid"
native_dir="$output/runtimes/$rid/native"
build_dir=${NAVTOOL_NATIVE_BUILD_DIR:-"$root/native/Navtool.RouterBridge/build"}

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
