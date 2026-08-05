# router-lib build patches

Patches applied to the pinned `router-lib` (`sailroute`) revision during the
native bridge build. They are applied by `PATCH_COMMAND` in
`native/Navtool.RouterBridge/CMakeLists.txt`, so the upstream `GIT_TAG` pin stays
immutable and every local modification is auditable in this directory.

Each patch must apply cleanly to the pinned tag with `git apply -p1`. The build
applies them idempotently: a patch that is already present is skipped rather
than treated as a failure. Remove a patch here once the fix lands in an upstream
release and `NAVTOOL_ROUTER_LIB_RELEASE_TAG` is bumped past it.

Patches are **not** applied when `SAILROUTE_SOURCE_DIR` points at a developer
checkout — that tree is assumed to be managed by hand.

## 0001-prune-out-of-coverage-midpoint-wind-probes.patch

Applies to: `a98d5651` · Upstream file: `src/routing/transition.cpp`

Originally written against `v0.4.1` and regenerated when the pin moved to
`a98d5651`, where the Stage 3 rewrite relocated the probe but left the defect
intact.

**Symptom.** With professional routing enabled and the time-dependent lattice
solver selected (either A\* or Dijkstra), route calculation aborts with
`OutsideForecast: requested time is after forecast coverage` whenever the
requested passage runs past the loaded forecast horizon. The isochrone beam
solver handles the identical request fine.

**Cause.** `evaluate_variable_transition` samples the *midpoint* wind for a
candidate edge before it checks whether the edge's arrival exceeds `route_end`:

```
midpoint_time = parent.time + delay + ceil(sailing_seconds / 2)
... interpolate(midpoint, midpoint_time) ...
if (parent.time + duration > route_end) return nullopt;   // too late
```

The beam solver never trips this because it advances by a step clamped to
`route_end - current_time`, so its midpoint always lands inside coverage. The
lattice solver has no such clamp: its edges span whole lattice cells, so an edge
starting near `route_end` probes well past `metadata.last_valid_time`. The probe
returns `ErrorCode::departure_outside_forecast`, and unlike
`coordinate_outside_forecast` that code is *not* pruned — it propagates out and
aborts the whole search.

Because the abort happens on the very first expansion, no progress snapshot is
ever emitted, so the failure cannot be softened on the managed side either.

**Fix.** Prune the candidate transition when the speculative midpoint probe falls
outside forecast coverage in *time*, exactly as already happens when it falls
outside coverage in *space*. The lattice solver then completes and takes its
existing `forecast_limited` path, returning the best partial route with
`RouteCompletion::forecast_exhausted` — matching the beam solver's behaviour.

Tracked upstream as [frye/router-lib#57](https://github.com/frye/router-lib/issues/57).

## Upstream defects that are *not* patched here

Four further defects were reproduced against `v0.4.1` and filed upstream, and
all four are still present at `a98d5651`. They are all structural to the lattice
solver, so patching them here would mean
rewriting the search rather than adjusting a guard. Navtool mitigates them at the
workflow layer instead — `RoutingWorkflow` retries with the isochrone beam when
the selected solver throws, and tells the user the route came from a different
solver (see `RoutingWorkflow.FallbackSolver`).

| Issue | Defect |
| --- | --- |
| [#53](https://github.com/frye/router-lib/issues/53) | The arrival shortcut accepts the goal on *generation* within `1.75 x max_neighbor_edge` — about 496 NM at the default subdivision level 4 — so any passage shorter than that returns an unoptimised great-circle leg. |
| [#54](https://github.com/frye/router-lib/issues/54) | The lattice has no sub-edge spatial move and therefore cannot tack. When the direct heading is inside the polar's no-go zone every neighbour is pruned and only `wait` survives, so the search either stalls for hours or fails with `no_route` on passages the beam completes. |
| [#55](https://github.com/frye/router-lib/issues/55) | `SolverStateKey` includes the raw arrival timestamp, so dominance never fires: labels blow up and better labels are silently discarded by the staleness check in the pop loop. |
| [#56](https://github.com/frye/router-lib/issues/56) | `no_route` discards the best partial route when `maximum_route_duration` rather than the forecast is the binding constraint. Unreachable with Navtool's settings — `maximum_route_duration` defaults to 240 h — but incorrect. |

Because of #53 and #54 the time-dependent lattice solver is currently slower and
less reliable than the isochrone beam on the passages measured here. Keep the
beam as the default until they are fixed upstream.
