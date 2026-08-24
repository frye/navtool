# router-lib build patches

Navtool currently applies **no local router-lib patches**. The native bridge pins
`router-lib` (`sailroute`) `v0.4.3`.

The reusable patch step remains in `native/Navtool.RouterBridge/CMakeLists.txt`.
Any future patch must be listed in `NAVTOOL_ROUTER_LIB_PATCHES`, apply cleanly to
the pinned tag with `git apply -p1`, and be documented here. The build applies
listed patches idempotently. Remove a patch once its fix lands upstream and the
release pin moves past it. Patches are not applied when `SAILROUTE_SOURCE_DIR`
points at a developer checkout.

## Fixes incorporated by v0.4.3

The local midpoint-probe patch was removed because its fix and the four related
lattice corrections are all upstream:

| Issue | Fix |
| --- | --- |
| [#53](https://github.com/frye/router-lib/issues/53) | [#58](https://github.com/frye/router-lib/pull/58) optimizes short passages instead of accepting the destination on neighbor generation. |
| [#54](https://github.com/frye/router-lib/issues/54) | [#59](https://github.com/frye/router-lib/pull/59) adds sub-edge movement so the lattice can tack through a polar no-go heading. |
| [#55](https://github.com/frye/router-lib/issues/55) | [#60](https://github.com/frye/router-lib/pull/60) restores effective dominance pruning without raw arrival time in the state key. |
| [#56](https://github.com/frye/router-lib/issues/56) | [#61](https://github.com/frye/router-lib/pull/61) returns the best partial route with `duration_exhausted` when maximum duration binds. |
| [#57](https://github.com/frye/router-lib/issues/57) | [#62](https://github.com/frye/router-lib/pull/62) prunes speculative midpoint probes beyond forecast coverage instead of aborting the search. |

## v0.4.3 solver check

The original 600 NM comparison was rerun from 50N 125W on the same NOAA GFS
`2026-08-04 06Z` run, using a cached 40–60N/140–110W assembly. The rerun had
valid steps 12–85, one hour more coverage than the original steps 11–84 fixture.
Both solvers used Navtool's balanced heading, midpoint sampling, and polar
interpolation controls; lattice used subdivision level 4 and normal refinement.
Wall time is one local CLI run and is directional rather than a benchmark.

| Bearing | Beam sailed / time | Lattice sailed / time | Result |
| --- | --- | --- | --- |
| 000 | 205.0 NM / 1.60 s | 75.5 NM / 4.84 s | Both forecast-limited; beam progressed farther. |
| 045 | 196.8 NM / 1.55 s | 293.6 NM / 2.79 s | Lattice now succeeds instead of returning `no_route`. |
| 135 | 258.2 NM / 1.87 s | 295.9 NM / 2.89 s | Both forecast-limited; lattice progressed farther. |
| 180 | 359.3 NM / 1.68 s | 404.3 NM / 3.07 s | Both forecast-limited; lattice progressed farther. |
| 225 | 393.8 NM / 2.25 s | 398.6 NM / 3.02 s | Comparable progress; lattice remained slower. |
| 315 | 348.2 NM / 1.70 s | 208.0 NM / 3.30 s | Both forecast-limited; beam progressed farther. |

The deterministic bundled sample was also checked over
48.01N 123.74W to 48.49N 123.26W, departing `2026-07-14 20Z`. Minimum wall time
of nine CLI runs:

| Solver | Arrival | Distance | Minimum |
| --- | --- | --- | --- |
| Beam | Jul 15 02:14:57Z | 33.417 NM | 204.0 ms |
| Lattice level 4 | Jul 15 04:59:16Z | 36.295 NM | 203.3 ms |
| Lattice level 5 | Jul 15 04:59:16Z | 36.295 NM | 208.2 ms |
| Lattice level 6 | Jul 15 04:59:16Z | 36.295 NM | 297.3 ms |
| Lattice level 7 | Jul 15 03:34:15Z | 37.470 NM | 334.8 ms |

v0.4.3 fixes the known correctness failures, but route quality and runtime remain
passage- and resolution-dependent. Navtool therefore keeps the isochrone beam as
the default and retains the explicit beam retry warning for a failed professional
lattice request.
