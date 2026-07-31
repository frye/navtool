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
- Acquire and cache OSM-derived land geometry for capability-gated land
  avoidance.
- Watch full reachability envelopes, the latest destination-facing front, and
  the closest provisional route stream onto the map while each model calculates.
- Compare model routes with distinct map colors. ECMWF is shown as an
  experimental option and currently fails explicitly because official indexed
  retrieval is not implemented.
- Scrub a shared UTC timeline or move among route-point timestamps.
- Click near a route to select and focus its nearest point.
- Display time-varying wind-speed colors and directional arrows for the active
  model.
- Switch at runtime among Light, Dark, and the midnight-blue and brass
  **Kind of Blue** theme. Navtool remembers the selected theme across launches.

## Prerequisites

- .NET 9 SDK
- CMake 3.20 or newer
- A C++20 compiler
- ECMWF ecCodes development libraries

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
directory. Native builds fetch and compile the immutable `router-lib` revision
`v0.2.0` by default. Set
`SAILROUTE_SOURCE_DIR` to a local `router-lib` checkout when testing other
revisions.

To build against a different immutable `router-lib` revision or release,
configure CMake with an override before building:

```sh
cmake -S native/Navtool.RouterBridge -B native/Navtool.RouterBridge/build \
  -DNAVTOOL_ROUTER_LIB_RELEASE_TAG=<revision-or-release>
cmake --build native/Navtool.RouterBridge/build --config Release --parallel
```

`NAVTOOL_ROUTER_LIB_RELEASE_REPOSITORY` can also be overridden if you need to
fetch releases from a different fork.

## Streaming route visualization

Navtool uses router-lib's `Router::optimize_view` progress contract. After each
completed search step, the native bridge synchronously copies the
callback-scoped reachability contours, destination-facing front, provisional
route, and cumulative diagnostics into immutable managed data. The callback
returns promptly; Mapsui updates are posted through the application's progress
pipeline to the Avalonia UI context.

At every routing time step, Navtool accumulates the complete router-provided
reachability envelope as thin, translucent historical context. Closed, open,
disconnected, and singleton contour components retain their original topology;
Navtool does not join separate components or synthesize smoothed positions. One
stronger red line shows only the latest destination-facing leading edge. Its
points are ordered port-to-starboard, exclude internal search clusters, and are
split where required at the antimeridian. The model's provisional route is also
replaced by the latest snapshot. Successful and forecast-limited search overlays
remain visible with the final route. Failed model overlays and all
cancelled-calculation overlays are cleared. Envelopes, fronts, routes, and
map-fit bounds are unwrapped safely at the antimeridian.

When forecast coverage ends before the destination is reached, Navtool promotes
the final provisional route to a selectable forecast-limited estimate, retains
the accumulated reachability envelopes and latest destination front, and
displays an amber warning. Complete final routes remain authoritative and may
differ from the last provisional route.

The ABI-v4 entry point `navtool_router_calculate_route_streaming_v4` preserves
the existing final-route and v1-v3 streaming functions while returning both
display-contour topology and open destination-front segments in one snapshot.
Progress array pointers are valid only for the duration of the synchronous
callback and must be copied by consumers. Navtool rejects stale bridges so a
partial progress contract cannot silently degrade the display.

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
| `SAILROUTE_SOURCE_DIR` | Optional `router-lib` checkout override for native build/run scripts |
| `NAVTOOL_ROUTER_LIB_RELEASE_TAG` | Immutable `router-lib` revision or release tag used when `SAILROUTE_SOURCE_DIR` is unset (default `v0.2.0`) |
| `NAVTOOL_ROUTER_LIB_RELEASE_REPOSITORY` | `router-lib` Git repository used when `SAILROUTE_SOURCE_DIR` is unset |
| `NAVTOOL_NATIVE_BUILD_DIR` | Optional native bridge build directory |
| `NAVTOOL_APP_DATA_ROOT` | Application data root |
| `NAVTOOL_CACHE_ROOT` | Forecast cache directory |
| `NAVTOOL_LAND_DATA_ENDPOINT` | Optional OSM-derived GeoJSON land service; Navtool appends `south`, `west`, `north`, and `east` query parameters |
| `NAVTOOL_ECMWF_EXPERIMENTAL` | `1` or `true` enables the experimental ECMWF path; acquisition still reports unsupported |

The selected display theme is stored in `preferences/theme.txt` beneath
`NAVTOOL_APP_DATA_ROOT` (or Navtool's default local application-data directory).

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

## Land data and compatibility

Navtool includes a land-data provider for GeoJSON `Polygon` and `MultiPolygon`
features covering a buffered route corridor. It splits antimeridian corridors,
validates bounded responses, caches them under the application data root for
seven days, and preserves OpenStreetMap attribution. The configured service
must be suitable for production use and return OSM-derived data under the Open
Database License; public Overpass endpoints are not used as a default.

Land avoidance also requires a router-lib segment-constraint capability.
Navtool's ABI-v4 bridge preserves the v1-v3 route entry points and exposes
capabilities additively. The pinned destination-front router-lib revision does
not provide segment constraints, so application preflight blocks before
forecast download rather than displaying another unchecked land-crossing
route. Direct managed bridge results are marked as unchecked for callers that
use the lower-level integration. Active segment rejection is blocked on
[`router-lib#11`](https://github.com/frye/router-lib/issues/11); until that API
is available, route calculations do not claim or apply land avoidance. The
existing raster basemap is never sampled as land geometry.

## Safety and current limitations

**Navtool is planning software, not navigation-certified guidance.** Land
avoidance depends on the configured OSM-derived service, cached data freshness,
and router-lib capability. Any degraded route is explicitly marked as not
checked for land. Even a land-aware route can omit recent, small, or inaccurately
mapped hazards and must be verified independently. The routing engine does not
model currents, waves, traffic, restricted areas, depths, or safety limits. The
built-in vessel polar is an approximate demonstration model.

ECMWF Open Data remains an explicit experimental option. Official data supports
field/step selection but not server-side geographic cropping, and indexed
10u/10v retrieval has not yet been implemented in this application. No fallback
or other model is presented as ECMWF data.

Saildocs is not used as an application API: it is an asynchronous email service
for bandwidth-constrained users rather than a reliable regional download
endpoint. ECMWF's official object store likewise does not provide server-side
geographic cropping, so online ECMWF acquisition remains separate future work.
