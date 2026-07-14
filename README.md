# Navtool

Navtool is a cross-platform Avalonia desktop application for visualizing GRIB
wind forecasts and routes calculated by the sibling C++ `router-lib` project.
It targets macOS, Windows, and Linux.

## Features

- Select start and destination points on an OpenStreetMap-based map.
- Choose a local departure date/time, converted to UTC with DST validation.
- Download geographically subsetted NOAA GFS 0.25-degree 10 m wind fields.
- Calculate routes through the native `router-lib` bridge.
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

Build and test the native bridge:

```sh
./scripts/build-native.sh
```

Then build, test, and run the application:

```sh
dotnet build Navtool.sln
dotnet test Navtool.sln
dotnet run --project src/Navtool.App
```

The application discovers the development bridge automatically. For a custom
location, set `NAVTOOL_ROUTER_BRIDGE_PATH` to the shared library or its
directory.

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
| `NAVTOOL_APP_DATA_ROOT` | Application data root |
| `NAVTOOL_CACHE_ROOT` | Forecast cache directory |
| `NAVTOOL_ECMWF_EXPERIMENTAL` | `1` or `true` enables the experimental ECMWF path; acquisition still reports unsupported |

NOAA data is downloaded from the operational NOMADS GFS filter. Navtool keeps
requests sequential, requests only 10 m U/V wind, validates GRIB responses, and
caches artifacts. NOMADS is not a bulk-download service and may be unavailable
or throttle excessive usage.

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
