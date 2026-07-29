# Navtool release notes

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
- **Live route calculation progress:** Retained isochrones and the closest
  provisional route now stream onto the map while each model calculates,
  including safe rendering across the antimeridian.
  ([#5](https://github.com/frye/navtool/pull/5))

### Added

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
- Updated native builds to use the immutable router-lib destination-front
  revision by default while preserving local-source and revision overrides.
  ([#12](https://github.com/frye/navtool/pull/12),
  [#18](https://github.com/frye/navtool/pull/18))

### Fixed

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
- Versioned the native bridge as ABI v3 for callback-scoped destination-front
  segments while preserving the v1/v2 entry points. Stale bridges now fail
  preflight instead of silently restoring alpha-shape visualization.

### Known limitations

- Navtool is planning software, not navigation-certified guidance. Routes do
  not currently account for land, currents, waves, traffic, restricted areas,
  or safety limits.
- Online ECMWF acquisition remains experimental and unavailable. Existing,
  compatible ECMWF IFS GRIB files can be used locally.
