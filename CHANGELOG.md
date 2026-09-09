# Navtool release notes

## Week of August 3-7, 2026 (Draft)

This week adds production ECMWF wind acquisition, router-lib v0.4 routing and
professional solver controls, opt-in environmental physics, local-time departure
entry, automatic recalculation, and richer route-point inspection. It also
closes NOAA tile-boundary and lattice correctness gaps and brings mapping
distribution and service usage into license-policy compliance.

> **Release status:** Unreleased draft for editorial review.

### Highlights

- **Production ECMWF routing:** Navtool can acquire deterministic IFS
  0.25-degree 10 m wind from ECMWF Open Data, discover a complete rolling cycle,
  resume indexed byte-range downloads, cache completed ranges, and use the data
  for normal routing and weather overlays.
  ([#56](https://github.com/frye/navtool/pull/56))
- **Router-lib v0.4.3 routing:** The standard beam profile now uses
  destination/VMG heading augmentation, midpoint wind sampling, and
  monotone-cubic polar interpolation. An explicit professional mode exposes the
  deterministic time-dependent lattice solver and advanced controls while
  retaining the beam as the default and fallback.
  ([#57](https://github.com/frye/navtool/pull/57),
  [#59](https://github.com/frye/navtool/pull/59),
  [#64](https://github.com/frye/navtool/pull/64),
  [#71](https://github.com/frye/navtool/pull/71),
  [#74](https://github.com/frye/navtool/pull/74))
- **Opt-in environmental physics:** The professional panel can supply uniform
  current and sea-state fields, a signed-distance landmask, and time-varying
  exclusion zones through the ABI-v7 bridge. All providers are off by default;
  route details and saved plans retain their provenance, policies, diagnostics,
  and water- and ground-relative telemetry.
  ([#69](https://github.com/frye/navtool/pull/69))

### Added

- Added local departure date and time entry with daylight-saving validation and
  explicit UTC conversion.
  ([#71](https://github.com/frye/navtool/pull/71))
- Added automatic route calculation after endpoint changes and a one-shot
  **Use newest weather data** option that still reuses matching cached tiles.
  ([#54](https://github.com/frye/navtool/pull/54),
  [#61](https://github.com/frye/navtool/pull/61))
- Added route-point popups positioned from map clicks, synchronized wind
  sampling, and apparent wind angle with port/starboard and ahead/astern labels.
  ([#55](https://github.com/frye/navtool/pull/55),
  [#60](https://github.com/frye/navtool/pull/60),
  [#68](https://github.com/frye/navtool/pull/68))

### Improved

- Past active-leg departure times now roll forward when calculation starts,
  without changing sailed-leg history.
  ([#52](https://github.com/frye/navtool/pull/52))
- Added solver-aware progress, lattice search diagnostics, configured
  beam/lattice dispatch, and schema-v3 result attribution while preserving
  legacy bridge exports and saved-plan migration.
  ([#59](https://github.com/frye/navtool/pull/59),
  [#62](https://github.com/frye/navtool/pull/62))
- Added a policy-compliant OpenStreetMap User-Agent and persistent tile cache,
  complete mapping dependency notices, and packaging of those notices in build
  and publish outputs.
  ([#48](https://github.com/frye/navtool/pull/48))

### Fixed

- Fixed route calculation for NOAA forecasts assembled from multiple spatial
  cache tiles, including corridors that cross tile latitude or longitude
  boundaries.
  ([#49](https://github.com/frye/navtool/pull/49),
  [#53](https://github.com/frye/navtool/pull/53))
- Fixed professional lattice short-passage arrival, tacking, dominance,
  duration-limited partial-route, and forecast-horizon probe behavior, then
  removed the temporary local patch after all fixes shipped in router-lib
  `v0.4.3`.
  ([#71](https://github.com/frye/navtool/pull/71),
  [#74](https://github.com/frye/navtool/pull/74))
- Fixed themed control visibility, file-picker clipping and alignment, and
  weather refresh-toggle behavior.
  ([#58](https://github.com/frye/navtool/pull/58),
  [#61](https://github.com/frye/navtool/pull/61))

### Maintenance

- Tightened workflow nullability and added focused regression coverage for
  default routing, lattice diagnostics, and lattice JSON parsing.
  ([#50](https://github.com/frye/navtool/pull/50),
  [#63](https://github.com/frye/navtool/pull/63),
  [#65](https://github.com/frye/navtool/pull/65),
  [#67](https://github.com/frye/navtool/pull/67))

### Known limitations

- Navtool is planning software, not navigation-certified guidance. Bundled
  coastline data is generalized and can omit small or recent hazards.
- Environmental providers consume values supplied by the user; Navtool does not
  yet acquire wave or current forecasts. Traffic, depths, and safety limits are
  not modeled.
- Online ECMWF support is wind-only, and its global field downloads can be
  larger than NOAA subsets.
- Professional lattice routing is serial and does not produce beam-style
  isochrones or destination fronts; Navtool displays its search point and
  provisional route instead.

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
- Online ECMWF acquisition remains experimental and unavailable. Compatible
  existing ECMWF IFS GRIB files can still be selected locally.

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
