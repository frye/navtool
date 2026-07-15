# Navtool

Navtool is a cross-platform Avalonia desktop application for visualizing GRIB
wind forecasts and routes calculated by the sibling C++ `router-lib` project.
It targets macOS, Windows, and Linux.

## Features

- Select start and destination points on an OpenStreetMap-based map.
- Choose a local departure date/time, converted to UTC with DST validation.
- Set the expected passage duration so only the required forecast times are
  acquired, up to the ten-day planning limit.
- Download geographically subsetted NOAA GFS 0.25-degree 10 m wind fields, or
  choose an existing GRIB through the operating system's native file picker.
- Calculate routes through the native `router-lib` bridge.
- Watch retained isochrone frontiers and the closest provisional route stream
  onto the map while each model calculates.
- Compare model routes with distinct map colors. ECMWF is shown as an
  experimental option and currently fails explicitly because official indexed
  retrieval is not implemented.
- Scrub a shared UTC timeline or move among route-point timestamps.
- Click near a route to select and focus its nearest point.
- Display time-varying wind-speed colors and directional arrows for the active
  model.

## Prerequisites

- .NET 9 SDK
- CMake 3.20 or newer
- A C++20 compiler
- ECMWF ecCodes development libraries
- `router-lib` beside this directory, by default:

  ```text
  Demo/
  ├── Navtool/
  └── router-lib/
  ```

On macOS:

```sh
brew install cmake eccodes
```

Install ecCodes through the appropriate system/package manager on Linux.
Windows builds require ecCodes headers, libraries, and runtime DLLs to be
discoverable by CMake and the application.

## Build and run

Build the native bridge and run the app with one command:

```sh
./scripts/run.sh
```

On Windows:

```powershell
.\scripts\run.ps1
```

The launcher builds and tests the bridge before starting Avalonia, preventing a
long forecast download from completing only to discover that routing is not
available. To build or test separately:

```sh
./scripts/build-native.sh
dotnet build Navtool.sln
dotnet test Navtool.sln
```

The application discovers the development bridge automatically. For a custom
location, set `NAVTOOL_ROUTER_BRIDGE_PATH` to the shared library or its
directory. If `router-lib` is not beside this checkout, set
`SAILROUTE_SOURCE_DIR` before using either native script.

## Streaming route visualization

Navtool uses router-lib's `RoutingProgressCallback` contract. After each
completed search step with a retained frontier, the native bridge synchronously
copies the callback-scoped isochrone, provisional route, and cumulative
diagnostics into immutable managed data. The callback returns promptly; Mapsui
updates are posted through the application's progress pipeline to the Avalonia
UI context.

Each model uses its normal route color. Completed isochrone frontiers accumulate
as thin low-opacity lines, while the model's provisional route is replaced by
the latest snapshot. Successful search overlays remain visible with the final
route. Failed model overlays and all cancelled-calculation overlays are cleared.
Frontiers, routes, and map-fit bounds are unwrapped safely at the antimeridian.

The final route result remains authoritative and may differ from the last
provisional route. Router-lib progress is notification-only: cancelling in
Navtool prevents stale updates and results from being accepted, but it does not
interrupt an optimization already executing inside the native library.

The additive C ABI entry point
`navtool_router_calculate_route_streaming_v1` preserves the existing v1
final-route function. Progress array pointers are valid only for the duration
of the synchronous callback and must be copied by consumers. Navtool falls back
to final-only route calculation when it loads an older ABI-v1 bridge that does
not export the streaming entry point.

## Publish

Build the native bridge on the target operating system, then publish:

```sh
./scripts/publish.sh osx-arm64
./scripts/publish.sh linux-x64
```

On Windows:

```powershell
.\scripts\build-native.ps1
.\scripts\publish.ps1 win-x64
```

Output is written under `artifacts/<RID>/`. The publish scripts copy the
platform bridge into `runtimes/<RID>/native`. ecCodes runtime dependencies must
also be installed or packaged according to the target platform.

## Configuration

| Variable | Purpose |
| --- | --- |
| `NAVTOOL_ROUTER_BRIDGE_PATH` | Native bridge file or directory |
| `SAILROUTE_SOURCE_DIR` | `router-lib` checkout used by native build/run scripts |
| `NAVTOOL_NATIVE_BUILD_DIR` | Optional native bridge build directory |
| `NAVTOOL_APP_DATA_ROOT` | Application data root |
| `NAVTOOL_CACHE_ROOT` | Forecast cache directory |
| `NAVTOOL_ECMWF_EXPERIMENTAL` | `1` or `true` enables the experimental ECMWF path; acquisition still reports unsupported |

NOAA data is downloaded from the operational NOMADS GFS filter. Navtool derives
an antimeridian-safe buffered passage area, requests every available forecast
step needed for the selected duration, and shows the expected part count before
calculation. Requests remain sequential and include only 10 m U/V wind.
Completed parts are cached atomically, so cancellation or a transient NOMADS
failure can resume without downloading valid parts again. NOMADS is not a
bulk-download service and may be unavailable or throttle excessive usage.

## Existing GRIB files

Select **Existing GRIB file**, then **Choose GRIB file...** to open the native
file dialog (Finder on macOS). The picker lists `.grib`, `.grb`, `.grib2`,
`.grb2`, and `.gri`, with an all-files fallback. Navtool inspects file content
through ecCodes; the filename does not determine compatibility.

Local files are referenced in place and are not copied into Navtool's cache or
remembered after restart. A usable file must identify NOAA GFS or ECMWF IFS,
contain compatible paired 10 m U/V fields, and cover both the buffered route
area and the full departure-to-arrival interval. Choosing a local file performs
no forecast HTTP request. If inspection or routing setup fails, the app reports
that separately from online forecast acquisition.

The default map uses standard OpenStreetMap tiles with attribution. Those tiles
are intended for normal interactive use, not bulk/offline prefetching. A
production distribution should configure a tile service whose policy and
capacity match its expected traffic.

## Safety and current limitations

**Navtool is planning software, not navigation-certified guidance.** The routing
engine does not currently model land, shorelines, currents, waves, traffic,
restricted areas, or safety limits. Routes may cross land. The built-in vessel
polar is an approximate demonstration model.

ECMWF Open Data remains an explicit experimental option. Official data supports
field/step selection but not server-side geographic cropping, and indexed
10u/10v retrieval has not yet been implemented in this application. No fallback
or other model is presented as ECMWF data.

Saildocs is not used as an application API: it is an asynchronous email service
for bandwidth-constrained users rather than a reliable regional download
endpoint. ECMWF's official object store likewise does not provide server-side
geographic cropping, so online ECMWF acquisition remains separate future work.
