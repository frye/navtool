# router-lib handoff: conservative coastal search pruning

Status: original design requirements. The conservative implementation is being
integrated through a carried router-lib patch; see
[implemented behavior and limitations](coastal-route-pruning.md).
Certified disconnection, automatic land-guided seed construction and aggressive
corridors are not part of the initial implementation.

Consumer: Navtool. Examined upstream revision: `cd476a84ef3edea9582d77f21588a23af727e083` (0.6.0 development snapshot).

See [the Navtool integration plan](coastal-route-pruning.md) for application changes and rollout.

## Desired outcome

For a route exiting the Strait of Juan de Fuca toward its western waypoint, stop expanding northern coastal alternatives once they provably cannot improve arrival. Generalize to arbitrary coastal topology; do not hard-code BC, latitude cutoffs or a one-way geographic commitment rule.

Northern waters are not necessarily globally disconnected from the destination. The right criterion is feasible water reachability and an optimistic arrival-time bound, not the appearance of a blocked straight line on a map.

Initial mode is explicit opt-in. Keep existing behavior when Off. Aggressive corridor pruning is deferred.

## Relevant current upstream implementation

- [Search, geometric buckets, future scoring and immediate arrival return](https://github.com/frye/router-lib/blob/cd476a84ef3edea9582d77f21588a23af727e083/src/routing/router.cpp): `pruning_key_for`, `score_future_positions`, `prune_candidates_into`, and the main optimization loop.
- [Public options, diagnostics and progress types](https://github.com/frye/router-lib/blob/cd476a84ef3edea9582d77f21588a23af727e083/include/sailroute/types.hpp): `RoutingOptions`, `RouteDiagnostics`, `RoutingProgressView`, `DestinationFrontMode`.
- [Router API](https://github.com/frye/router-lib/blob/cd476a84ef3edea9582d77f21588a23af727e083/include/sailroute/router.hpp): optimization and replay boundary.
- [Lattice heuristic](https://github.com/frye/router-lib/blob/cd476a84ef3edea9582d77f21588a23af727e083/src/routing/lattice_solver.cpp): great-circle travel-time bound; current-enabled routing uses Dijkstra.
- [Landmask implementation](https://github.com/frye/router-lib/blob/cd476a84ef3edea9582d77f21588a23af727e083/src/environment/landmask.cpp) and public `include/sailroute/environment.hpp` / `land_data.hpp`.
- `src/routing/transition.cpp`, `integration.cpp`, `front.cpp` and `src/serialization/json.cpp` are adjacent integration points.
- Existing tests include `tests/test_strategic_routing.cpp`, `test_routing_contracts.cpp`, `test_routing.cpp` and `test_landmask.cpp`.

These sources establish the current boundary, not the exact shape of the proposed API.

## Required contract

### Inputs and ownership

Add a typed conservative-pruning policy, immutable topology preparation input/result, bounded preparation options, and support metadata. API names and enum numbers must be finalized upstream before Navtool binds them.

Support the same selected land source as route enforcement:
- Native signed-distance/GSHHG data, with source/version, coverage, numerical uncertainty, clearance and missing-data policy.
- Application polygon geometry with holes/multipolygons and an explicit domain, enabling Navtool's default Natural Earth and configured OSM routes. Preserve application segment eligibility as final authority; do not imply that an arbitrary Boolean callback provides global topology.

An auxiliary proof model can coexist with an application callback without pretending to be a second land-enforcement source. Its blocked region must be a certified subset of what the enforcement contract actually forbids. Different geometry semantics, source identity or domain must invalidate the proof model or reject the configuration. Additional unknown application restrictions may be relaxed in the proof model, but never skipped when validating transitions or incumbents.

Topology handles are immutable and reusable. Document lifetime/threading, byte limits, cancellation and source/domain identity. Distinguish preprocessing geometry from destination-specific fields so Navtool can reuse geometry safely across independent legs and forecast models. Bound retained caches; do not persist opaque pointers or large grids.

### Admissible remaining-cost bound

For every state, return a nonnegative optimistic remaining duration, with validity/status and diagnostic reason. Unknown is not infinity.

If `L(x)` is a certified lower bound on legal water-path length from state x to the arrival area and `V_upper` bounds possible future speed over ground, then:

`h(x) = L(x) / V_upper`

is one possible time bound. The implementation may use a tighter proven formulation.

Requirements:
- Target the complete arrival area, not just the waypoint center. Endpoint-to-cell connections and interpolation must retain the lower-bound property.
- Account for geodesic geometry, antimeridian wrapping, clearance and floating-point error conservatively.
- Include all possible speed contributions in `V_upper`, including boat factor, polar interpolation/range policies, favorable current and any sea-state model that can increase speed. Ignore nonnegative maneuver penalties if necessary for optimism. Never divide by present boat speed.
- If a speed bound cannot be certified, use a weaker valid bound or zero and record the reason; do not prune using an unsafe polar-only speed cap.
- Relax dynamic exclusion zones unless their closure for the full relevant interval is established. A passage closed now may open later.
- Unknown/coarse cells remain potentially passable. Allowing too much water weakens pruning but is safe; falsely closing a channel is not.
- A shortest path restricted to a finite water-node graph normally overestimates the continuous optimum. Dijkstra/A* over that graph is not automatically an admissible bound. Deliver the mathematical relaxation/error argument and regression tests; do not ship grid distance as proof without one.
- Signed distance to shore is not remaining water-route distance. Existing conservative collision masks may close passages and must not be reused directly for impossibility claims without a suitable optimistic relaxation.
- Infinity is permitted only for certified disconnection in the complete declared routing domain. Incomplete preprocessing coverage must not imply a land barrier. A smaller internal topology crop is not a new user-authorized routing domain.

### Feasible incumbent and early pruning

The current beam loop returns upon finding an arrival. Merely adding an incumbent comparison there would do little to stop early northern expansion.

Add a bounded native seed phase or equivalent feasible-completion mechanism:
- Use a geometric/coarse guide only to propose timed sailing actions.
- Validate the complete route from the request start under the exact boat, departure, weather, currents, waves, maneuver state, integration policy, segment callback, native land/exclusions, arrival radius and horizon.
- Only successful complete validation creates an incumbent upper bound. Provisional partial paths, straight connectors and geometric lengths cannot do so.
- Preserve enough action and transition audit to reproduce validation without inferring controls from displayed vertices.
- Reuse the incumbent in the final result contract; do not return a later-found but slower arrival. Improve it only with another validated feasible route.
- Count and budget seed work explicitly. Failure to find a seed is normal and observable; invalid source/physics/provider data retains its existing error semantics.

At state time `t`, safely skip future expansion when:
- Reachability is certified impossible; or
- `t + h(x)` is strictly beyond the search horizon, with conservative numerical handling; or
- `t + h(x)` is strictly worse than the validated incumbent arrival, after tolerance/tie policy.

Prefer strict comparisons initially to preserve ties. Retain uncertain states. Recheck frontier parents before expensive expansion after bounds improve; filter children before strategic scoring/beam retention. Keep ordinary strategic diversity and sailing-state identity intact for surviving candidates.

Define exhaustion semantics: return a validated incumbent when available; otherwise preserve the existing partial/forecast-limited/error distinctions and best known legal partial trace. Do not promote a callback result, report global no-route from a capped preprocessing search, or lose cancellation/resource failures.

The beam's approximation remains explicit. Altering its retained population can change later search choices even with sound rejection bounds; test route-quality regressions rather than claiming general equivalence to Off.

### Progress, audit and capabilities

Expose requested/effective mode, supported solver/source combinations, topology source/domain/version, preparation state/reason, admissibility status, seed status, incumbent ETA if present, and current bound availability.

Add cumulative counters for:
- Parent expansions skipped.
- Candidates rejected by certified disconnection, horizon and incumbent bounds separately.
- Ordinary beam pruning separately.
- Bound-unavailable cases.
- Seed expansions/transition evaluations and topology construction work.

Define whether each counter counts states or transitions, its phase and its monotonicity. Preserve existing aggregate meanings or version changed meanings explicitly.

Provide a post-proof retained-front payload clearly distinguished from eligible-pre-prune diagnostics. Preserve disconnected segment boundaries. A branch removed from active search must not be presented as a current retained branch; historical geometry remains valid history.

Final JSON must record effective settings and diagnostic provenance matching the run. Unknown/unavailable is not zero. Specify whether this is a compatible addition to `route_result_v2` or requires a new native schema; Navtool will validate the negotiated contract rather than assume.

Expose solver support explicitly. Beam support is required for initial delivery; lattice is either separately implemented/proven or explicitly unsupported when this option is enabled. Do not silently switch solver.

## Navtool integration dependency

Navtool will add a new versioned bridge boundary, capability negotiation, explicit opt-in setup, source/topology marshalling, immutable handle lifecycle, live/final diagnostics and saved-plan migration.

Frozen ABI 8 structs cannot grow in place. Proposed ABI 9 gets its own options/request/progress layouts and ownership functions. JSON and saved-plan versions are separate. Existing exports remain available; new enabled requests must reject absent capability or invalid combinations before search.

The application must retain the default polygon enforcement path. Requiring GSHHG or silently replacing Natural Earth with an SDF would not complete the Navtool requirement.

## Upstream acceptance evidence

1. Deterministic strait with a long northern detour: compare Off/On under identical fixed-worker inputs, preserve arrival quality, and demonstrate at least 50% fewer northern expansions after bounds become available plus fewer total main-search expansions. Include seed/preprocessing overhead in end-to-end reporting.
2. Tiny reference problems establish `h <= optimal remaining duration` and verify that removed labels cannot beat the incumbent.
3. Preserve strategic delayed-wind and losing-first-tack fixtures and their mirrored cases; add a case where the northern detour actually wins.
4. Cover narrow passages, holes, disconnected basins, long open detours, arrival circles crossing cells, antimeridian geometry, changed clearance, incomplete data and limited topology domains.
5. Cover no incumbent, valid/invalid seed, currents faster than polar maximum, evolving weather, opening timed exclusions, missing bounds, cancellation, preparation/work limits and deterministic worker behavior.
6. Verify progress/final audit parity, reason counters, active-vs-historical front semantics, partial results and exact error classification.

Performance numbers are controlled-case goals, not a universal promise. Acceptance requires actual reduced search work, not only fewer rendered lines.

## Deferred improvement B: aggressive corridor mode

Possible later option: guide-biased corridors, geographic commitment or stronger detour-ratio rejection. These can discard a globally better route and must be labeled heuristic, separately opt-in and separately audited. Define escape/widening retries, north-is-better regression coverage and quality comparisons before proposing rollout. This is not a fallback silently used by Conservative mode.
