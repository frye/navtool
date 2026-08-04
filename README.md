# Navtool

Navtool is a cross-platform Avalonia desktop application for visualizing GRIB
wind forecasts and routes calculated by the sibling C++ `router-lib` project.
It targets macOS, Windows, and Linux.

## Features

- Build and save named, ordered itineraries with fixed start/finish waypoints,
  reorderable intermediate waypoints, optional stopovers, and numbered map
  markers connected by an antimeridian-safe planning guide.
- Open on a Salish Sea chart view and use resizable edge drawers plus
  right-click, long-press, or keyboard radial map actions to place endpoints,
  inspect routes, and start calculation without obscuring the chart. Placing or
  replacing the final endpoint automatically starts a fresh calculation.
- Choose a local departure date/time, converted to UTC with DST validation; when
  calculation starts with a past active-leg departure, Navtool rolls it forward
  to the current time and warns without changing sailed-leg history.
- Set the expected passage duration so only the required forecast times are
  acquired, up to the ten-day planning limit.
- Download NOAA GFS or ECMWF IFS 0.25-degree 10 m wind fields, or choose an
  existing GRIB through the operating system's native file picker.
- Calculate routes through the native `router-lib` v0.4 bridge with enhanced
  beam-routing accuracy enabled by default.
- Apply bundled Natural Earth land geometry by default, with an optional
  higher-detail OSM-derived service override.
- Watch historical destination-facing isochrone fronts, the emphasized latest
  front, and the closest provisional route stream onto the map while each model
  calculates. An always-visible instrument rail summarizes acquisition and
  routing progress across models and legs and provides a cancel action.
- Temporarily enable professional routing controls to select the deterministic
  time-dependent lattice solver and tune maneuver, wind, polar, pruning, front,
  and lattice-search behavior, or opt into current, sea-state, signed-distance
  landmask, and exclusion-zone providers.
- Compare NOAA GFS and ECMWF IFS routes with distinct map colors.
- Render every saved successful itinerary leg together on one full-route map,
  including sailed history, while retaining waypoint guides for blocked,
  uncalculated, and out-of-window legs.
- Select a leg from the ordered list or map to emphasize it without hiding the
  rest of the route, then fit the leg or inspect an individual route point in an
  anchored telemetry card showing UTC arrival, boat and wind speeds, true wind
  direction, and apparent wind angle.
- Scrub a route-wide UTC timeline for one active forecast model at a time, move
  among that model's route-point timestamps, and see waypoint stopovers as
  explicit stationary holds.
- Display time-varying wind-speed colors and directional arrows for the active
  model, synchronized to the inspected route point and forecast time. A
  one-shot radial toggle requests the newest available forecast run on the next
  calculation.
- Switch at runtime among Light, Dark, and the midnight-blue and brass
  **Kind of Blue** theme. Navtool remembers the selected theme across launches.
- Persist route plans and their latest per-model leg outcomes as
  schema-versioned JSON beneath the application data root.

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

Source checkout launches must use the platform launcher, which builds and tests
the current worktree's native bridge before starting the app:

```sh
./scripts/run.sh
```

On Windows:

```powershell
.\scripts\run.ps1
```

Raw `dotnet run`, `dotnet exec`, and direct `Navtool.App.dll` execution are not
supported for functional source checkout launches. Native build outputs are
git-ignored and local to each worktree, so a managed build alone does not provide
the bridge and a bridge from another checkout must not be reused.

In GitHub Copilot App or VS Code, select the **Navtool** run configuration and
press the play button (or press `F5`). To launch without the debugger, run the
**Navtool: Run** task. Both options build the native bridge before starting the
app.

The launcher builds and tests the bridge before starting Avalonia, preventing a
long forecast download from completing only to discover that routing is not
available. To build or test separately:

```sh
./scripts/build-native.sh
dotnet build Navtool.sln
dotnet test Navtool.sln
```

Use `scripts/build-native.sh` or `scripts/build-native.ps1` for native-only
validation, and use `scripts/publish.sh` or `scripts/publish.ps1` for
distributable artifacts. For a custom bridge location, set
`NAVTOOL_ROUTER_BRIDGE_PATH` to the shared library or its directory. Packaged
applications discover their bridge under `runtimes/<RID>/native`. Native builds
fetch and compile the immutable `router-lib` Stage 3 revision
`a98d5651d2273044c22f5fb6f54e4355af90392b` by default; it will move to the
`v0.4.2` release tag once `router-lib` publishes it. Set
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

## Routing profiles

Standard calculations use Navtool's balanced isochrone-beam profile. It augments
the normal heading set with destination-bearing and velocity-made-good headings,
samples wind at segment midpoints, and uses monotone-cubic polar-angle
interpolation. It intentionally adds no tack or gybe delay, no hard maximum-wind
cutoff, and clamps wind above the polar's tabulated range.

Enable **Professional routing features** in the planning drawer to reveal the
temporary `router-lib` Stage 2.5 controls. Professional mode can select either the
isochrone beam or deterministic time-dependent lattice solver and configure
maneuver penalties, heading augmentation, wind sampling, polar interpolation,
wind limits, pruning, and solver-specific settings. The toggle and edited values
reset when Navtool exits and are never stored as application preferences or route
plan inputs. Completed results do retain solver attribution and lattice
diagnostics.

## Multi-point routes and visualization

Each forecast model calculates itinerary legs sequentially. A successful leg's
arrival plus the destination waypoint's optional stopover determines that
model's next departure; NOAA and ECMWF may therefore reach the same leg at
different UTC times. Failure, cancellation, forecast exhaustion, or a departure
beyond the rolling forecast cutoff is recorded per model and leg. Later legs
remain visibly listed with their status, but Navtool never draws invented
optimized geometry between successful legs.

The map stores feature identity as plan, stable leg, model, calculation session,
and route-result ID. This keeps revisions and parallel model results distinct
during list selection, map hit testing, selected-leg emphasis, and timeline
navigation. The active model's timeline spans its saved successful legs in
chronological order. Stopover gaps are stationary holds at the waypoint; the
timeline does not compare unrelated nearest NOAA and ECMWF points as though they
represented the same forecast instant.

Marking a leg sailed preserves its latest model geometry as historical context.
An explicit active leg and optional current-position marker can resume a rolling
route without changing stable itinerary leg IDs. Recalculation publishes each
completed leg atomically, so cancellation retains completed work while stale
calculation generations cannot replace newer itinerary state.

## Streaming route visualization

Navtool uses router-lib's `Router::optimize_view` progress contract. The native
bridge synchronously copies callback-scoped progress into immutable managed data.
Beam progress contains reachability contours, the destination-facing front, the
provisional route, and cumulative diagnostics. Lattice progress instead contains
the provisional route, current search point, settled/queued/relaxed label counts,
and refinement state. The callback returns promptly; Mapsui updates are posted
through the application's progress pipeline to the Avalonia UI context.

For beam routing, Navtool accumulates the router-provided open,
destination-facing front as thin, translucent historical context. The front
uses a 120-degree aperture on each side of the destination bearing to preserve
useful port and starboard context without drawing the backward envelope.
Display-only corner cutting softens angular joins without changing routing
points, closing a front, or joining separate antimeridian segments. One-point
segments are omitted rather than rendered as zero-length marks. One stronger red
line shows only the latest front. Its source points are ordered port-to-starboard
and exclude internal search clusters. The model's provisional route is also
replaced by the latest snapshot. Successful and forecast-limited search overlays
remain visible with the final route. Failed model overlays and all
cancelled-calculation overlays are cleared. Fronts, routes, and map-fit bounds
are unwrapped safely at the antimeridian. Lattice routing does not synthesize
isochrones or destination fronts that router-lib does not provide; it renders the
search-point marker and latest provisional route instead.

When forecast coverage ends before the destination is reached, Navtool promotes
the final provisional route to a selectable forecast-limited estimate, retains
the solver-appropriate search overlay, and displays an amber warning. Complete
final routes remain authoritative and may differ from the last provisional route.

The ABI-v7 bridge preserves the existing final-route and v1-v6 streaming
functions. The v6 entry point adds fixed-layout routing options, solver identity,
search points, and lattice counters while retaining optional pre-retention
segment eligibility; v7 adds the optional environment payload and ground-frame
route-point telemetry. Callback array and coordinate pointers are valid only for
the duration of the synchronous callback and must be copied by consumers.
Navtool rejects stale bridges so missing configuration, environment, or
land-constraint support cannot silently degrade routing safety.

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
| `NAVTOOL_ROUTER_LIB_RELEASE_TAG` | Immutable `router-lib` revision or release tag used when `SAILROUTE_SOURCE_DIR` is unset (default is the Stage 3 revision `a98d5651d2273044c22f5fb6f54e4355af90392b`) |
| `NAVTOOL_ROUTER_LIB_RELEASE_REPOSITORY` | `router-lib` Git repository used when `SAILROUTE_SOURCE_DIR` is unset |
| `NAVTOOL_NATIVE_BUILD_DIR` | Optional native bridge build directory |
| `NAVTOOL_APP_DATA_ROOT` | Application data root |
| `NAVTOOL_CACHE_ROOT` | Forecast cache directory |
| `NAVTOOL_LAND_DATA_ENDPOINT` | Optional OSM-derived GeoJSON land service override; Navtool appends `south`, `west`, `north`, and `east` query parameters. When unset, bundled Natural Earth 1:10m land polygons are used. |

The selected display theme is stored in `preferences/theme.txt` beneath
`NAVTOOL_APP_DATA_ROOT` (or Navtool's default local application-data directory).
Route plans are stored atomically as JSON beneath `routes/` in the same root.
Schema-v3 plan files contain waypoint, stopover, calculation-session, leg-outcome,
sailed state, route-point metadata, solver attribution, and optional lattice
diagnostics, but never forecast binaries or professional input settings. Schema
v1 and v2 documents migrate forward; unknown future schemas or inconsistent
IDs/references are rejected visibly.
Opening a saved plan restores full-route geometry, sailed history, per-model leg
status, and the model-specific timeline. Weather overlays are not restored from
route JSON.

NOAA data is downloaded from the operational NOMADS GFS filter. Navtool derives
an antimeridian-safe buffered passage area, divides it into stable 10-degree
cache tiles, requests every available forecast step needed for the selected
duration, and shows the expected part count before calculation. Requests remain
sequential and include only 10 m U/V wind.

Each immutable run/hour/tile is promoted atomically beneath the persistent
forecast cache. Route-specific GRIB files are assembled locally from those
tiles, so restarting Navtool or shifting a departure by a few minutes reuses
overlapping data and downloads only newly required edge hours or tiles. Cache
entries do not expire by age; least-recently-used data is removed only when the
configured size or entry limits require space. Interrupted downloads leave
completed tiles available for the next attempt.

By default, route calculation uses the newest cached GFS run that fully covers
the requested area and time window. If NOAA has published a newer covering run,
Navtool displays a warning. Enable **Use newest weather data** before calculating
to select that newest run; tiles already cached for it are still reused rather
than downloaded again. NOMADS is not a bulk-download service and may be
unavailable or throttle excessive usage.

ECMWF data is downloaded from the official Open Data object store. Navtool reads
the per-step JSON-lines indexes, retrieves only the global 10 m U/V wind messages
with strict HTTP byte-range requests, and assembles them in an immutable GRIB2
artifact. The native loader limits in-memory decoding to the buffered passage
area. Global field downloads can be substantially larger than NOAA's geographic
subsets; completed ranges are cached and reused across routes and restarts.

Navtool considers the four deterministic IFS cycles each day. The 00/12 UTC
cycles provide 3-hour steps through 144 hours and 6-hour steps through 240 hours;
the 06/18 UTC cycles provide 3-hour steps through 90 hours. Publication is
progressive and the rolling archive is short, so Navtool verifies every required
index and falls back to an older covering cycle when a newer one is incomplete.
Online ECMWF support currently acquires wind only.

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

Weather availability is scoped to the selected leg and forecast model. Navtool
uses an in-memory acquisition only when its model, time range, and geographic
bounds cover that leg. Switching legs or models cancels stale sampling and
clears the overlay before a compatible acquisition is selected. Saved route
geometry and details remain available after restart, but the UI explicitly
reports weather unavailable until a compatible forecast is acquired again.

The default map uses standard OpenStreetMap tiles with linked attribution,
an application-specific User-Agent, and a persistent seven-day cache. Those
tiles are intended for normal interactive use, not bulk/offline prefetching.
A production distribution should configure a tile service whose policy and
capacity match its expected traffic.

## Land data and compatibility

Navtool includes public-domain Natural Earth 1:10m land polygons for offline
land avoidance without configuration. This global dataset is loaded from a
compressed embedded resource, reused across calculations, and attributed as
"Made with Natural Earth." It is generalized map data and can omit small
islands, reefs, recent shoreline changes, and other hazards.

For higher-detail geometry, configure a GeoJSON `Polygon` and `MultiPolygon`
service covering a buffered route corridor. Navtool splits antimeridian
corridors, validates bounded responses, caches them under the application data
root for seven days, and preserves OpenStreetMap attribution. The configured
service must be suitable for production use and return OSM-derived data under
the Open Database License; public Overpass endpoints are not used as a default.

Land avoidance also requires router-lib's pre-retention segment-eligibility
capability. Navtool's ABI-v7 bridge preserves the v1-v6 route entry points and
adds configured beam and lattice dispatch plus the optional environment payload
described under "Environmental physics". When land
geometry is available, every candidate segment is checked before router-lib
retains it. A configured service failure marks the route as unchecked rather
than silently falling back to less detailed geometry. Direct lower-level bridge
results are likewise marked as not evaluated unless the caller supplies a
segment constraint. The existing raster basemap is never sampled as land
geometry.

## Environmental physics (opt-in)

Navtool can enable router-lib's Stage 3 environmental providers from the
professional routing panel. **Every one of them is off by default.** With none
enabled, routing takes exactly the path it took before Stage 3 shipped, down to
byte-identical route JSON, which both the native and managed test suites assert.

| Provider | What it adds | Default |
| --- | --- | --- |
| Current field | Uniform set/drift translated into ground-frame motion | Off |
| Sea state | Significant height, period, and relative angle derating of boat speed | Off |
| Signed-distance landmask | router-lib's certified land clearance, replacing the callback | Off (callback is the default) |
| Exclusion zones | Time-varying restricted polygons with activation windows | Off |

### Units and reference frames

Getting a frame backwards silently produces a plausible but wrong route, so
Navtool states each one explicitly:

- **Current** is entered as east and north components in knots, using the
  oceanographic *set* convention: the direction the water flows **toward**. This
  is the opposite of the meteorological wind convention used elsewhere in the
  app, where wind direction is the direction the wind comes **from**.
- **Waves** use significant height in metres, period in seconds, and a
  meteorological *from* direction in degrees true. The reported relative wave
  angle is 0° for a following sea, 90° for a beam sea, and 180° for a head sea.
- **Signed land distance** is in nautical miles, positive over water and
  negative over land.
- **Route point heading and boat speed stay water relative** even when a current
  is applied. Ground-frame speed and course are reported separately as speed
  over ground and course over ground, so the two frames can never be confused
  for one another.

### Missing-data policies

Each provider decides what happens when a sample falls outside its coverage.
There is deliberately no "assume calm" option, because outside coverage is not
the same claim as zero current, flat water, or open ocean.

- **Fail route** aborts the calculation. This is the default for currents and
  waves, matching router-lib.
- **Reject transition** discards only the affected segment. This is Navtool's
  default for the landmask, because a corridor-scoped mask has finite coverage
  by construction and leaving it is expected rather than exceptional.

### Signed-distance landmask

When selected, the landmask **replaces** the NetTopologySuite segment callback
rather than layering on top of it, so the two land paths can never disagree
about the same water. Navtool rasterizes the mask from the same Natural Earth or
OSM-derived geometry described above, scoped to the route corridor.

Distances are computed in a local equirectangular frame whose longitude is
compressed by the cosine of the highest latitude in the corridor. Every row
except the extreme one is therefore compressed slightly more than is strictly
correct, which means reported distances are **lower bounds** on true distance.
Under-reporting distance only ever makes segment certification more cautious.
The sign comes from a separate point-in-polygon test against unscaled geometry,
so which side of the coastline a node is on stays exact. Declared interpolation
error is half the node diagonal.

If the landmask is selected and land geometry cannot be obtained, the route
fails rather than proceeding over what would look like open water.

### Attribution

Every configured provider carries a name, source, and revision. These, along
with the applied policies and the environment diagnostics counters, appear in
the route detail view and are persisted with the plan, so a stored route records
which data actually shaped it.

### Not included

Stage 3 in Navtool consumes data you supply; it does not acquire any. The
following are deliberately out of scope for this work and tracked separately:

- NOAA WaveWatch III wave forecast download
- RTOFS and OSCAR ocean current acquisition
- GRIB-backed gridded current and wave providers
- Exclusion zone map editing and notices-to-mariners ingestion

The bundled Antarctic exclusion zone is an example of the format, not
navigational guidance.

## Safety and current limitations

**Navtool is planning software, not navigation-certified guidance.** Land
avoidance depends on the bundled generalized dataset or configured OSM-derived
service, cached data freshness, and router-lib capability. Any degraded route
is explicitly marked as not checked for land. Even a land-aware route can omit
recent, small, generalized, or inaccurately mapped hazards and must be verified
independently. The routing engine models currents, waves, and exclusion zones only when
you explicitly enable and supply them (see "Environmental physics"); it never
models traffic, depths, or safety limits. The built-in vessel polar is an
approximate demonstration model.

The professional lattice solver reports search points and counters, not
isochrones or destination-front geometry. It is currently serial and intended
for expert comparison rather than as a faster replacement for the default beam
solver.

Multi-point results depend on the forecast available when each leg was
calculated. A sailed line is historical planning context, not a recorded vessel
track, and a stationary stopover is a schedule representation rather than
evidence that the vessel remained at that exact coordinate. Blocked or
out-of-window legs intentionally show only itinerary guides and status.

Saildocs is not used as an application API: it is an asynchronous email service
for bandwidth-constrained users rather than a reliable regional download
endpoint.

ECMWF forecast data is provided under the ECMWF Open Data terms. Users remain
responsible for complying with the applicable licence and attribution
requirements; see <https://www.ecmwf.int/en/forecasts/datasets/open-data>.

## Mapping licenses and attribution

OpenStreetMap tiles and optional OSM-derived land data remain subject to the
Open Database License and OpenStreetMap service policies. The map displays the
required contributor attribution and links to the OpenStreetMap copyright page.
The bundled Natural Earth land dataset is public domain; Navtool retains the
recommended "Made with Natural Earth" credit.

Mapping library copyright notices, license terms, data provenance, and native
renderer notices are distributed in `THIRD-PARTY-NOTICES.txt` and `licenses/`.
The application project copies these files into build and publish outputs.
