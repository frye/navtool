# Router-lib 0.6 migration

Navtool pins router-lib commit
`cd476a84ef3edea9582d77f21588a23af727e083`. Its upstream project version is
0.6.0, but this pin is a **development snapshot**, not a published v0.6 release.
Changing a release override must not conceal which revision was actually linked.
The fetched snapshot carries a small UTF-8 path compatibility patch for polar
and GSHHG metadata/errors on Windows; build identity reports the patched source
as dirty rather than claiming an untouched upstream tree. Source archives without
their own Git root report unknown revision instead of inheriting Navtool's SHA.

Three versions describe different boundaries:

| Boundary | Version |
| --- | --- |
| Native Navtool bridge | ABI 9 (frozen ABI 8 exports retained) |
| Native final route JSON | `route_result_v2` |
| Saved Navtool route plans | Schema 7 |

Retained older bridge exports preserve their binary layouts, not the numerical
behavior, defaults, departure fallback, or serialized bytes of router-lib
v0.4.3. The old solver comparison in the native patch notes is historical
evidence, not a quality benchmark for this snapshot.

## Boats and cruising settings

A new calculation requires an explicit boat: import a supported polar or choose
the labeled demo boat. The demo is not a substitute for an invalid or missing
polar. Imported polars are application-managed, content-identified assets, so a
route does not depend only on a mutable file in a downloads directory.

Normal quality settings start with router-lib's native presets. Navtool's
standard Balanced setup explicitly overrides polar-angle interpolation to PCHIP
to retain its existing interpolation behavior. Above-range wind uses `NoSpeed`,
not the previous `Clamp`; this can materially change route feasibility and ETA.
The 100% boat performance setting scales polar performance once and does not
scale the forecast wind.

Normal cruising setup belongs to the saved plan, while remembered everyday
preferences provide defaults for new passages. Professional values can be
remembered, but their activation remains optional and session-scoped.
A saved result's run audit records effective
professional values without re-enabling those controls when the plan is opened.
Requested inputs, effective native settings, and observed result metadata are
not interchangeable.

Expected passage duration sizes forecast acquisition; it is not a native hard
deadline. The ten-day application planning policy remains separate from loaded
forecast coverage and native search limits. Native hard duration is expressed
in integral hours. Integration intervals are minutes; maneuver and timed replay
durations use seconds. Arbitrary deadlines must not be silently rounded.

## Arrival areas and itinerary history

The nominal waypoint is the center of an arrival area, not an exact promised
physical endpoint. Each forecast model starts its next leg at that model's
accepted endpoint and uses arrival plus the planned stopover for departure.
There is no unsailed connector to the marker center.

The initial active leg still starts at the explicitly supplied current-position
marker when present, otherwise its declared start waypoint. A partial or failed
predecessor cannot authorize a downstream leg. Saved predecessor references
must identify the accepted model, leg, execution and result.

Sailed results remain historical planning context, not GPS vessel tracks.
Recalculation and plan copying must preserve original per-leg execution
provenance rather than relabel retained geometry with a new model session.

Stopovers are user-planned holds at actual arrival locations. A known timed
exclusion conflict blocks subsequent legs while retaining the inbound result.
A clear exclusion check does not certify anchoring, mooring, station keeping,
depth, traffic or other navigational safety.

Each leg is optimized separately. A forecast-optimized itinerary is not proof
of the globally earliest multi-waypoint passage. Upstream does not expose the
complete initial sailing state needed to carry exact tack/heading maneuver
accounting between optimizer calls. Navtool does not invent corrective managed
penalties after the route has been calculated.

## Forecast and route measurements

Forecast corridor buffering remains 20% of route distance, clamped to 300-900 nm.
Do not equate the map viewport or current provisional route with the complete
search domain. Provider cadence changes are valid: GFS transitions from hourly
to three-hour steps, and ECMWF cadence and horizon vary with the run.

Route wind is the applied sailing sample, potentially sampled at a midpoint.
It is not a new observation at the displayed endpoint. Keep ground-relative
forecast wind, effective water-relative polar wind, speed through water, and
speed/course over ground distinct. Apparent wind must use a consistent frame;
missing audit cannot be interpreted as zero current.

Zero speed through water may coexist with nonzero speed over ground during
drift. Such a native segment is not a stationary stopover. A planned hold does
not produce a new native wind measurement by copying an earlier sample to a
later timestamp. Weather queried at a selected map location/time is displayed
separately.

Only validated final native JSON authorizes a completed or partial route.
Cancellation, resource limits and invalid data must not promote the latest
callback candidate into final geometry. Live progress includes available point
audit and search counters; cumulative environmental diagnostics are final-only
in this upstream API.

## Land protection and optional GSHHG

Bundled Natural Earth polygons remain the default. A verified application
polygon constraint may enforce land protection while the native JSON correctly
reports that no native landmask was configured. Both owners are reported
separately. Generic eligibility callbacks are not proof of land protection.
Unavailable required land data is not permission to calculate over unchecked
open water or silently substitute another source.

Local GSHHG is an optional, user-supplied native binary dataset, not a coastline
download service or a new chart engine. Missing or changed source files require
an explicit resolution before recalculation. Saved geometry remains viewable.
Retain the source identity, coverage, numerical allowance and attribution.

The pinned upstream regional adapter imposes these limits:

| Limit | Maximum or supported range |
| --- | --- |
| Latitude and longitude spans | 120 degrees each |
| Latitude | -85 to +85 degrees, subject to halo restrictions |
| Nominal node spacing | 0.05-120 nm |
| Distance cap / source halo | 1-600 nm |
| Grid nodes | 250,000 |
| Source points | 10,000,000 |
| Geometry work units | 100,000,000 |

The loader can reject unsupported geometry or hierarchy even when grid sizing
is feasible. The entire file counts toward source limits; cropping does not
make source processing free. Wholly omitted shoreline records cannot be
detected, so successful loading does not certify dataset completeness.

Native numerical allowance can approach the sum of the latitude and longitude
cell extents. Two-nm node spacing can therefore imply an allowance near four nm;
node spacing is not a claim of coastal accuracy. It is not interchangeable with
the managed SDF builder's half-diagonal allowance.

A fine mask over the broad forecast corridor can exceed these caps. Choose a
coarser mask or explicitly declare a smaller study/routing domain and retain the
strategic limitation in the plan. Never silently narrow the routing area to fit
a mask. Wide-domain fine tiled or mixed-resolution coverage requires additional
upstream capability.

## Saved plans and recovery

Schema 1-6 plans migrate forward while keeping their geometry, stable IDs,
completion state and sailed history. Missing old boat, settings and run audit
remain legacy/unknown. They do not become verified 0.6 defaults. A legacy plan
requires an explicit boat before recalculation.

Opening an old plan does not rewrite its file. Before its first migrated
overwrite, Navtool retains the original bytes beneath `routes/backups/` in the
application data root. Content-identified backup names are never overwritten.
Backup failure prevents replacement of the old file. Backups are not listed as
additional plans.

To use an older Navtool version again, first preserve the new file elsewhere,
then restore an appropriate original backup to its original
`routes/<plan-id>.route.json` name. Older application versions cannot be assumed
to read schema 6. Never edit the schema number alone to make an incompatible
document appear readable. Schema 7 additionally records coastal pruning;
schema 6 readers cannot read schema 7 plans.

Run snapshots contain compact asset references and audit, not embedded forecast
binaries or repeated complete environment grids. Missing external assets do not
prevent viewing saved results, but can prevent recalculation.

## Build and execution

Use `scripts/build-native.sh` or `scripts/build-native.ps1` for native validation
in the current worktree. Use `scripts/run.sh` or `scripts/run.ps1` for functional
source launches and screenshots, and `scripts/publish.sh` or
`scripts/publish.ps1` for distributables. A managed-only build cannot establish
native availability. Do not reuse another checkout's bridge.

Supported release layouts retain the existing osx-arm64, linux-x64 and win-x64
targets and the documented .NET/ecCodes runtime dependency model. Selecting a
RID does not cross-compile a native library. Check packaged architecture,
revision and ABI, including multi-configuration Windows output locations.

Native optimization supports callback cancellation. Forecast, polar and GSHHG
loading and diagnostic action replay do not currently expose the same immediate
interrupt mechanism; cancelled work is discarded at supported boundaries, not
interrupted by unsafe handle disposal.

Controlled routing-quality diagnostics compare complete arrivals under matched
boat, forecast, arrival-area and constraint settings. Action replay requires
explicit timed headings; route vertices alone do not necessarily encode the
original control policy. Two deterministic forecast routes are scenarios, not a
calibrated probabilistic confidence interval.

## Opt-in coastal search pruning

General, opt-in land-aware pruning is described in
[the coastal pruning guide](coastal-route-pruning.md) and
[router-lib requirements](router-lib-land-aware-pruning.md).
It is carried as a patch over the pinned snapshot, not claimed as an upstream
published release. It preserves potentially competitive detours using
conservative native bounds, not map clipping or a narrower destination-front
display. Schema 6 plans migrate to Off with unknown historical coastal audit.
