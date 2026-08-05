# Navtool release notes

## Week of August 3-7, 2026 (Draft)

This week adds production ECMWF routing, automatic route calculation, anchored
route-point telemetry, advanced beam and lattice controls, and opt-in Stage 3
environmental physics. It also improves departure-time handling, forecast
selection, mapping compliance, and native bridge diagnostics.

> **Release status:** Unreleased draft for editorial review.

### Highlights

- **Opt-in environmental physics:** The professional routing panel can enable a
  uniform current field, sea-state speed derating, router-lib's certified
  signed-distance landmask, and time-varying exclusion zones. Providers are off
  by default; enabled providers record their source, revision, missing-data
  policy, diagnostics, and ground-frame telemetry with the saved route.
  Navtool consumes environmental data supplied by the user and does not yet
  acquire current or wave forecasts.
  ([#69](https://github.com/frye/navtool/pull/69))
- **Production ECMWF routing:** Navtool can acquire ECMWF IFS 0.25-degree wind
  from indexed Open Data byte ranges, resume and reuse cached downloads, decode
  only the route corridor, and use the result for normal routing and overlays.
  ([#56](https://github.com/frye/navtool/pull/56))
- **Router-lib v0.4 routing:** The balanced isochrone beam remains the default
  with destination/VMG heading augmentation, midpoint wind sampling, and
  monotone-cubic polar interpolation. Professional controls can explicitly
  select the time-dependent lattice solver and expose its progress and
  diagnostics.
  ([#57](https://github.com/frye/navtool/pull/57),
  [#59](https://github.com/frye/navtool/pull/59),
  [#64](https://github.com/frye/navtool/pull/64))

### Added

- Automatically starts routing when both endpoints are placed and safely
  restarts after an endpoint changes. The progress rail now provides a direct
  cancellation action; the radial Calculate action remains available for forced
  recalculation.
  ([#54](https://github.com/frye/navtool/pull/54))
- Added an anchored route-point telemetry card with arrival time, boat speed,
  true and apparent wind, heading, and apparent wind angle. Route selection,
  timeline state, the active forecast model, and wind overlays update together.
  ([#55](https://github.com/frye/navtool/pull/55),
  [#60](https://github.com/frye/navtool/pull/60),
  [#68](https://github.com/frye/navtool/pull/68))
- Added a one-shot **Refresh weather** radial toggle that requests the newest
  available forecast for the next calculation.
  ([#61](https://github.com/frye/navtool/pull/61))

### Improved

- Local departure inputs now stay synchronized with route plans, display their
  resolved UTC instant, validate daylight-saving transitions, and roll expired
  active-leg departures forward without changing sailed history.
  ([#52](https://github.com/frye/navtool/pull/52),
  [#71](https://github.com/frye/navtool/pull/71))
- Added ABI-v7 configured beam/lattice dispatch, solver-aware progress, schema-v3
  result attribution, lattice diagnostics, and the optional Stage 3 environment
  payload while preserving older bridge entry points and plan migration.
  ([#62](https://github.com/frye/navtool/pull/62),
  [#69](https://github.com/frye/navtool/pull/69))

### Fixed

- Fixed route calculation for NOAA forecasts assembled from multiple spatial
  cache tiles, including corridors crossing tile boundaries.
  ([#49](https://github.com/frye/navtool/pull/49))
- Fixed themed control contrast, compact date/time picker clipping, picker-label
  alignment, and radial-control interaction.
  ([#58](https://github.com/frye/navtool/pull/58),
  [#61](https://github.com/frye/navtool/pull/61))
- Pruned lattice transitions that probe beyond forecast coverage and fall back
  once to the default beam with a visible warning when the selected professional
  solver fails.
  ([#71](https://github.com/frye/navtool/pull/71))

### Maintenance

- Added the mapping stack's required notices, persistent OpenStreetMap tile
  caching, and application-specific request identification.
  ([#48](https://github.com/frye/navtool/pull/48))

### Known limitations

- Navtool is planning software, not navigation-certified guidance. Land data is
  generalized, and traffic, depths, and safety limits are not modeled. Currents,
  waves, and exclusions affect routing only when explicitly enabled and supplied.
- Online ECMWF support is wind-only, and global field downloads can be larger
  than NOAA subsets.
- The professional lattice solver is serial, does not expose beam-style
  isochrones, and currently falls back to the beam for known failure modes.

## Week of July 27-August 1, 2026 (Draft)

This week adds land-aware routing, persistent multi-point voyage plans,
sequential per-model calculation, rolling route resume, full-route
visualization, and reusable NOAA forecast caching. It also modernizes the chart
controls and strengthens native bridge launch guidance and automated
validation.

> **Release status:** Unreleased draft for editorial review.

### Highlights

- **Land-aware routing by default:** Candidate route segments are checked
  against bundled Natural Earth coastline data before retention. An optional
  OSM-derived GeoJSON service can provide higher-detail geometry, and degraded
  results are identified rather than silently presented as checked.
  ([#23](https://github.com/frye/navtool/pull/23),
  [#24](https://github.com/frye/navtool/pull/24))
- **Persistent multi-point voyages:** Named itineraries now support ordered
  intermediate waypoints, stopovers, sequential per-model leg calculation,
  partial outcomes, sailed history, rolling resume from an explicit current
  position, and schema-versioned persistence.
  ([#38](https://github.com/frye/navtool/pull/38),
  [#39](https://github.com/frye/navtool/pull/39),
  [#41](https://github.com/frye/navtool/pull/41))
- **Full-route visualization:** Every saved successful leg can be shown
  together, selected from the list or map, and inspected on a route-wide
  active-model timeline with explicit stopover holds.
  ([#43](https://github.com/frye/navtool/pull/43))
### Added

- Added persistent Light, Dark, and **Kind of Blue** themes with a compact
  runtime selector and distinct interactive states.
  ([#22](https://github.com/frye/navtool/pull/22))
- Added resizable planning and route/weather edge drawers plus right-click,
  touch long-press, and keyboard radial map actions for endpoint placement,
  route inspection, and calculation.
  ([#34](https://github.com/frye/navtool/pull/34),
  [#36](https://github.com/frye/navtool/pull/36),
  [#40](https://github.com/frye/navtool/pull/40))
- Added editor play-button and task-based launch configurations that build the
  worktree-local native bridge before starting the managed application.
  ([#25](https://github.com/frye/navtool/pull/25))

### Improved

- Restored one open, destination-facing isochrone front per routing step,
  retained forecast-limited estimates, softened display-only corners, widened
  the useful destination aperture, and suppressed misleading singleton marks.
  ([#21](https://github.com/frye/navtool/pull/21),
  [#26](https://github.com/frye/navtool/pull/26),
  [#27](https://github.com/frye/navtool/pull/27),
  [#29](https://github.com/frye/navtool/pull/29))
- Changed the initial chart extent from the North Atlantic to a buffered Salish
  Sea view covering Port Townsend, Friday Harbor, Anacortes, and Ucluelet.
  ([#33](https://github.com/frye/navtool/pull/33))
- Reused immutable NOAA forecast tiles across restarts and overlapping route
  windows, with persistent bounded cache metadata and an explicit option to
  refresh from the newest published run.
  ([#45](https://github.com/frye/navtool/pull/45))

### Fixed

- Fixed historical isochrone styles inheriting an opaque fill in CI and
  restored .NET 9 compatibility for radial-action placement.
  ([#35](https://github.com/frye/navtool/pull/35),
  [#37](https://github.com/frye/navtool/pull/37))
- Added actionable recovery guidance when the native routing bridge is missing
  and documented the mandatory worktree-safe launch path.
  ([#44](https://github.com/frye/navtool/pull/44))

### Maintenance

- Added GitHub Actions coverage that builds and tests the native bridge and
  runs every managed test project for pushes and pull requests.
  ([#28](https://github.com/frye/navtool/pull/28))

### Known limitations

- Navtool is planning software, not navigation-certified guidance. Bundled
  coastline data is generalized and can omit small or recent hazards; routing
  still does not model currents, waves, traffic, restricted areas, depths, or
  safety limits.

## Week of July 13-17, 2026 (Draft)

This week establishes Navtool as a cross-platform desktop application for
weather-aware route planning and adds major improvements to forecast
acquisition, live routing feedback, map clarity, and route inspection.

> **Release status:** Unreleased draft for editorial review.

### Highlights

- **Cross-platform weather routing:** Navtool now runs on macOS, Windows, and
  Linux with NOAA GFS forecast downloads, native C++ route calculation,
  synchronized route navigation, and time-aware wind visualization.
  ([#1](https://github.com/frye/navtool/pull/1))
- **Resumable forecast acquisition:** NOAA downloads are cached as atomic parts
  and can resume after cancellation or transient failures. Forecast requests
  are limited to an antimeridian-safe passage corridor and the selected trip
  duration. ([#7](https://github.com/frye/navtool/pull/7))
- **Bring-your-own GRIB support:** Existing NOAA GFS and ECMWF IFS GRIB files
  can be selected with the native file picker. Navtool validates model
  metadata, wind fields, time coverage, and geographic coverage before
  routing. ([#7](https://github.com/frye/navtool/pull/7))
- **Live route calculation progress:** Open destination-facing isochrone fronts
  and the closest provisional route stream onto the map while each model
  calculates, including safe rendering across the antimeridian.
  ([#5](https://github.com/frye/navtool/pull/5))

### Added

- Added persistent Light, Dark, and **Kind of Blue** display themes with a
  compact runtime selector and distinct active, hover, pressed, focus, and
  disabled control states.
- Added a required passage duration, defaulting to three days with a ten-day
  planning limit, so forecast acquisition matches the intended voyage.
  ([#7](https://github.com/frye/navtool/pull/7))
- Added native-routing preflight checks and clearer separation between runtime,
  forecast-acquisition, and route-calculation errors.
  ([#7](https://github.com/frye/navtool/pull/7))
- Added apparent wind angle to selected route-point details, including
  port/starboard, ahead, and astern labels for easier sail-trim interpretation.
  ([#15](https://github.com/frye/navtool/pull/15))
- Added cross-platform build, run, test, and publish scripts for the managed
  application and native routing bridge.
  ([#1](https://github.com/frye/navtool/pull/1),
  [#7](https://github.com/frye/navtool/pull/7))

### Improved

- Refined streamed isochrones into one router-provided, destination-facing
  reachable front per time step. Front points are ordered port-to-starboard,
  exclude internal search-cloud boundaries, and split only at map
  discontinuities.
  ([#13](https://github.com/frye/navtool/pull/13),
  [#14](https://github.com/frye/navtool/pull/14),
  [router-lib#12](https://github.com/frye/router-lib/issues/12),
  [router-lib#14](https://github.com/frye/router-lib/pull/14))
- Improved NOAA reliability with grid-aligned geographic bounds, request
  pacing, bounded retries, `Retry-After` support, cancellation handling, and
  structured rolling logs. ([#3](https://github.com/frye/navtool/pull/3))
- Strengthened NOAA retry stream validation so unsupported destinations fail
  before network activity begins.
  ([#11](https://github.com/frye/navtool/pull/11))
- Updated native builds to use router-lib `v0.2.0` by default while preserving
  local-source and revision overrides.
  ([#12](https://github.com/frye/navtool/pull/12),
  [#18](https://github.com/frye/navtool/pull/18))
- Smoothed streamed isochrone fronts with bounded display-only corner cutting,
  retaining subtle historical fronts while emphasizing the latest front.

### Fixed

- Restored solid open isochrone fronts after filled alpha-shape contours caused
  fragmented triangular reachability overlays.
- Restored live isochrones after the router-lib v0.1.1 progress API change.
  Routes that outlast available weather now remain selectable through the final
  forecast-supported point, keep their route and isochrone overlays, and show
  an amber best-estimate warning instead of failing.
- Fixed the Avalonia map surface being hidden by an opaque background and
  removed duplicate OpenStreetMap attribution.
  ([#2](https://github.com/frye/navtool/pull/2))
- Fixed unreliable trackpad and mouse-wheel zoom behavior.
  ([#3](https://github.com/frye/navtool/pull/3))
- Fixed wind overlays obscuring the basemap. Wind-speed cells are now fully
  transparent, while direction arrows retain speed-based coloring without a
  default layer fill or outline.
  ([#8](https://github.com/frye/navtool/pull/8),
  [#10](https://github.com/frye/navtool/pull/10))

### Maintenance

- Fixed an ambiguous Avalonia color type in map-rendering tests to keep the
  application test suite compiling consistently.
  ([#17](https://github.com/frye/navtool/pull/17))
- Versioned the native bridge as ABI v5 to combine callback-scoped reachability
  contours, destination-front segments, and optional land-segment eligibility
  while preserving the v1-v4 entry points. Stale bridges now fail preflight
  instead of silently degrading display or routing safety.

### Known limitations

- Navtool is planning software, not navigation-certified guidance. Routes do
  not currently account for land, currents, waves, traffic, restricted areas,
  or safety limits.
- Online ECMWF acquisition remains experimental and unavailable. Existing,
  compatible ECMWF IFS GRIB files can be used locally.
