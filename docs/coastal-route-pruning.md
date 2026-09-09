# Land-aware coastal route pruning

Status: implemented with native and managed integration coverage. The original
[router-lib requirements](router-lib-land-aware-pruning.md) remain the design
reference; supported behavior and conservative limitations are described below.

## Using the feature

Select **Experimental conservative coastal pruning** in **CRUISING SETUP**.
It defaults to Off, including migrated plans. It requires the isochrone beam
solver, an explicit land source and bridge ABI 9 with coastal-pruning support.
Unsupported configurations fail before routing; they never silently switch
solver or turn the feature off.

The implementation uses certified forbidden spherical caps to obtain optimistic
remaining-travel bounds. A bounded, exactly evaluated destination-bearing seed
may establish a feasible arrival for comparison. Northern branches stop being
expanded only when their optimistic arrival is later than that incumbent or
the search horizon. Geographic direction by itself never rejects a branch.

Natural Earth/OSM retain their existing polygon callback. Navtool proves
rectangles are wholly covered by the selected polygons, derives contained
spherical caps, and erodes them by the callback's full sampling distance plus
a numerical allowance. Holes and unresolved small features add no false land.
This avoids equating linear longitude/latitude edges with great-circle edges.
Native SDF/GSHHG uses the exact native mask owner instead.
SDF source identities hash the grid, distance samples, uncertainty and
enforcement parameters rather than relying on descriptive attribution.

Preparation uses bounded probes over the forecast domain and a denser area
around the requested leg. This affects where proof data is collected, **not**
where routes may search. Unrepresented water/land remains unconstrained in
the optimistic bound; the original segment-enforcement rules still apply.
At most 64 application caps and 100,000 polygon-coverage tests are retained/
performed. Topology is request-scoped, not a persistent global cache.

The current implementation intentionally does not prove disconnected basins,
construct a general land-guided seed, or guess speed bounds for current
providers. A failed seed leaves horizon pruning available; an uncertified
speed bound is reported as unavailable and retains states. No aggressive
corridor fallback is used. Existing strategic retention still applies.

Live/final diagnostics distinguish ordinary beam pruning from coastal parent,
horizon and incumbent rejection, with source/domain identity, seed state and
work. The live front is post-proof/post-beam retained search. Seed progress has
no route geometry; historical fronts may remain visible north of the live
front. This is not evidence of continued expansion.

Saved-plan schema 7 persists the opt-in, observed diagnostics and final seed
controls. Schema 1-6 migration leaves pruning Off and historical telemetry
unknown; opening does not rewrite the file, and the existing first-overwrite
backup remains in force. ABI 8 is readable with pruning Off; ABI 8 C layouts
are unchanged.

## Original design and rollout plan

## Goal and scope

Reduce actual search expansion into coastal branches that cannot improve arrival
at the active leg's destination, including the northern alternatives in the Juan
de Fuca example. Use general, proof-based pruning rather than a geographic cutoff.
Preserve viable detours, tacking and routes that benefit from later weather.

Initially offer an explicit opt-in, defaulting to Off. Existing plans retain
their behavior. Automatic defaults are a later rollout decision. Aggressive
corridor pruning is documented as an optional later improvement, not part of
conservative mode.

The screenshot is qualitative evidence, not a reproducible route input.
Historical fronts persist, native progress can include pre-prune candidates,
and the map smooths front geometry. A displayed line over land does not establish
that an accepted route crosses land or that the branch is still expanding.

## Current boundary

Navtool pins router-lib development revision
`cd476a84ef3edea9582d77f21588a23af727e083`; the bridge is ABI 8, final native JSON
is `route_result_v2`, and saved plans use schema 6.

`NativeConfiguredRouteEngine` passes frozen options, boat, forecast and selected
land source into the bridge. Default Natural Earth polygons enforce individual
segments through a callback. Optional polygon-derived SDF and regional GSHHG
use native enforcement instead. The existing bridge rejects conflicting land
owners.

Upstream beam pruning uses geometric distance/bearing buckets and strategic
diversity, not land-aware remaining travel cost. It returns on the first
arrival-bearing time step. Early arrival-bound pruning therefore also needs a
separately validated feasible route, not merely a new distance score.

## Responsibilities

| Layer | Planned responsibility |
| --- | --- |
| router-lib | Conservative topology, admissible remaining-time bounds, feasible incumbent, pruning, diagnostics and active-front semantics |
| Native bridge | Versioned options/request/progress, capability negotiation, geometry/topology ownership and native audit |
| Navtool infrastructure | Selected-source preparation, actual domain, immutable inputs, per-leg/model lifecycle and strict output validation |
| Navtool core | Requested/effective settings, progress and final audit, failure semantics and saved-plan compatibility |
| Navtool UI | Explicit opt-in, diagnostic state, and distinction between active search and historical fronts |

## Implementation sequence (design reference)

1. **Capture the baseline and finalize the upstream contract.** Create a
   deterministic strait fixture with a long northern detour and fixed input
   identities. Record Off-mode expansions, arrival and costs. Exact screenshot
   reproduction additionally needs its saved plan and matching assets; do not
   infer exact coordinates, boat or forecast settings from pixels.
2. **Deliver the router-lib prerequisite.** Implement the linked contract with
   certified bounds, bounded feasible-route seeding and native regressions.
   Do not expose a working Navtool option until this capability exists.
3. **Extend and pin the bridge.** Adopt a reviewed immutable upstream revision.
   Add a new configured-routing ABI (proposed 9), leaving ABI 8 and older layouts
   frozen. Add matching capability flags, sized options/request/progress
   structures, owned immutable topology handles and preflight checks. Finalize
   numbering and native JSON compatibility against the delivered upstream API.
4. **Wire configuration and execution.** Add typed `Off` /
   `ConservativeLandAware` setup, with Off as the default. Validate structural
   support while freezing setup and data-dependent support after loading the
   actual land/forecast domain. Prepare topology from the selected source without
   changing collision enforcement. Reuse geometry where valid, but derive
   destination/arrival-area bounds separately per leg and model.
5. **Persist and present the feature.** Advance saved-plan schema 6 to the next
   schema (proposed 7), migrate old plans to Off with unavailable historic audit,
   and preserve backup-before-overwrite and geometry/provenance. Show requested
   versus effective pruning, unavailable-bound reasons, incumbent availability
   and separate reason counters. Use post-proof retained fronts for live search;
   keep historical fronts visibly historical rather than clipping northern lines.
6. **Qualify behavior end to end.** Add native/managed regressions and paired
   Off/On measurements. Keep automatic defaults and aggressive heuristics out of
   this delivery.

## Navtool changes by surface

| Surface | Files and changes |
| --- | --- |
| Settings and immutable context | `src/Navtool.Core/RoutingSetup.cs`: mode, capability validation, effective settings and audit; budgets remain professional/session-only |
| Core progress/workflow | `Routing.cs`, `RoutingWorkflow.cs`, `RoutePlanRoutingWorkflow.cs` as needed: reason counters, per-model/leg isolation and audit consistency |
| Land preparation/execution | `NativeRoutingSetupService.cs`, `NativeConfiguredRouteEngine.cs`: selected polygon/SDF/GSHHG source, actual coverage, bounded cancellable preparation |
| Managed native boundary | `NativeConfiguredRouting.cs`, `NativeRoutingOptions.cs`, `NativeRouterBridge.cs`, and new interop/handle types beside `NativeRouterV8Interop.cs` |
| C++ bridge | `native/Navtool.RouterBridge/include/navtool_router_bridge.h`, versioned implementation beside `src/bridge_v8.inc`, `CMakeLists.txt` and preflight/layout tests |
| Parsing and persistence | Native final-result parsing, `NativeRouteV2Validation.cs`, `RoutePlanJsonRepository.cs`: strict audit validation and schema migration |
| UI | `RoutingSetupViewModel.cs`, `RoutingSetupView.axaml`, `MainViewModel.cs`, `RouteMapLayers.cs`: opt-in, diagnostic labels and active-front payload |

## Safety and compatibility rules

Default polygon routing must benefit; a GSHHG-only implementation is incomplete.
Topology is auxiliary proof data, not another collision-enforcement owner.
Retain the callback for polygon enforcement and existing native ownership rules.

Do not silently enable SDF, alter source/clearance, close unresolved narrow
passages, or reduce the search domain to the viewport or provisional corridor.
Unknown topology must not imply disconnection. A collision-safe coarse SDF or
water-node shortest-path graph is not automatically an admissible lower bound.

Explicit opt-in on an unsupported bridge, land source or solver fails preflight
with an actionable error. Beam support is the initial requirement; unsupported
lattice configurations must be rejected, never silently switched.

A supported run may have no usable bound or incumbent yet. Keep uncertain
branches and report that state. This does not authorize ignoring malformed data,
missing required land, cancellation or resource errors. Only validated final
native output authorizes accepted geometry.

Cache keys include source identity, domain, clearance, representation/version
and resolution; destination fields also include the arrival area. Bound memory,
preserve immutable handle lifetime through callbacks, and do not persist grids
or native handles. Source topology can be reusable; time bounds and incumbents
must not leak across models or legs.

Do not claim that northern expansion stops immediately on entering the strait:
it stops when conservative evidence is sufficient. Beam routing remains
approximate and this feature is not a global-optimality or chart-safety guarantee.

## Acceptance

Run paired fixed-worker cases with identical boat, weather, land, environment,
arrival radius, duration and resolution. Require the controlled strait case to
arrive with no worse ETA beyond a declared native time tolerance, at least 50%
fewer post-bound northern expansions, and fewer total main-search expansions.
Freeze the fixture/baseline before implementation. Report seed/preparation work,
wall time and peak memory separately; reduced displayed geometry is not success.

Preserve the existing mirrored delayed-corridor and losing-first-tack winners
in `bridge_v8_tests.cpp`. Add north-is-better weather, long valid detours,
narrow passages, disconnected basins, holes, antimeridian geometry and arrival
areas crossing cells. Exercise favorable currents, time-varying exclusions,
absent/invalid incumbents, unknown coverage, source/domain changes, unsupported
capabilities, cancellation, work caps and partial/forecast-limited completion.

Tiny native reference problems must demonstrate bound admissibility and safe
label rejection. Audit counters must be monotonic and attributable. Removed
branches cannot reappear as active retained fronts; historical fronts may remain.

Extend the existing `RoutingSetupTests`, `RoutingWorkflowTests`,
`RoutePlanRoutingWorkflowTests`, native interop/integration tests,
`NativeRouteEngineTests`, `NativeRouteV2ParserTests`,
`RoutePlanJsonRepositoryTests`, `RoutingMigrationEndToEndTests`,
`RoutingSetupWorkflowTests`, `MainViewModelWorkflowTests`, `MapRenderingTests`
and `CoalescingProgressTests` where behavior changes.

Use targeted existing `dotnet test` selections and the native build scripts in
the current worktree, with required native fixture paths for integration runs.
Launch and capture screenshots only with `scripts/run.sh` or `scripts/run.ps1`;
require successful bridge preflight and no `Routing engine unavailable`.
Distributable validation uses the existing publish scripts.

## Deferred improvement B

A separately opt-in aggressive corridor or geographic-commitment heuristic may
prune sooner without proof, at the cost of potentially losing a better route.
It needs explicit quality tradeoffs, escape/widening behavior, diagnostic
provenance and its own north-is-better comparisons. It must not silently become
a fallback for conservative pruning.
