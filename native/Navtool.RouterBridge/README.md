# Native ABI 8 boundary

The default router-lib revision is the immutable
`cd476a84ef3edea9582d77f21588a23af727e083` **0.6.0 development snapshot**.
The latest published release at adoption was v0.4.3. Ensembles are disabled;
native land-data support is enabled. `navtool_router_build_info_v8` reports the
resolved source, revision, version, dirty state, architecture and compiled
features. A local override is identified as such, never relabeled the pinned
release. Dirty state is captured at configure time.

## Compatibility and ownership

All pre-v8 layouts and export names remain frozen. Their compatibility is
binary, not a guarantee of historical physics or byte-identical old JSON.
ABI, native JSON (`route_result_v2`) and managed plan schema are independent.
Configured v8 requests require an explicit loaded polar or explicitly-created
demo handle. No asset error falls back to demo. Automatic polar parsing does
not report a resolved input format, so metadata leaves that value unknown.
The parser supports an optional minimum sailing angle for imported files only.
Maximum-angle restrictions and angle restrictions on built-in demo assets are
not exposed by the upstream API and must be rejected by callers.

Forecast, polar and land handles own immutable native data. Hold them alive for
the entire operation, including every synchronous callback. Dispose after all
uses complete. Destroy operations clear the supplied handle and permit a second
destruction of that cleared handle; callers must not reuse dangling aliases.
Every returned UTF-8/JSON buffer is freed with `navtool_router_bridge_free_v1`.
Callbacks and their arrays are borrowed synchronous views; copy before returning.
Callbacks are never final results: only successful returned v2 JSON authorizes
geometry. Invalid polar, cancellation and resource limits are distinct errors.

`quality_defaults_v8` calls native `routing_options_for_quality`; the returned
complete options carry `override_flags=ALL`. To retain only selected overrides,
clear the other bits before resolving. Grouped bits replace their whole group.
The native defaults are linear polar interpolation and `NoSpeed` above the polar
range. Navtool's cruising choice is Balanced plus an **explicit PCHIP override**;
the bridge does not hide that override inside the preset.

The v7 environment is reused. V8 rejects simultaneous GSHHG and SDF land, and
rejects either native land owner alongside an application segment callback.
An application polygon callback alone is not presented as native landmask audit.
Current is applied once by native physics; progress includes the resulting
water-relative polar wind, STW and ground-motion audit when present.

Forecast gap limits are explicit inclusive seconds; exact native valid times and
minimum/maximum spacing are exposed. Single-time files have no cadence.
Declared crop and actual loaded interpolation bounds are separate concepts.
There is no extrapolation beyond native forecast coverage.

## GSHHG and planned holds

GSHHG loading uses the upstream native binary loader with no downloader or second
geometry parser. Preview reproduces that pinned loader's bounded grid/halo
arithmetic: ±85 latitude, positive spans at most 120°, spacing 0.05–120 nm, cap
1–600 nm, at most 250,000 grid nodes, 10 million source points and 100 million
geometry tests. Callers may lower, not raise, caps. The actual interpolation
allowance is approximately the **sum of cell extents**, plus the native numerical
allowance, not a half-diagonal. The distance cap must exceed it; halos cannot
reach a pole. Preview does not inspect source geometry or certify completeness.
All source points count even outside the retained region. GSHHG is not a chart.

Planned holds call `ExclusionZoneSet::intersects_segment` at equal coordinates
over the full arrival/departure interval, honoring native half-open activation,
boundary policy, holes and antimeridian geometry. A successful check only states
whether configured exclusions conflict; it is not anchorage or station-keeping
certification. Null/unconfigured exclusions cannot be reported as a completed
native validation. Loading and replay have no immediate cancellation callback.

## Validation and diagnostic artifacts

Run `./scripts/build-native.sh` (or `scripts/build-native.ps1`), only in the
current worktree. This runs exact-library ABI/revision preflight, frozen legacy
tests and v8 tests. Required CI passes explicit current-worktree bridge and GRIB
paths with `NAVTOOL_REQUIRE_NATIVE_TESTS=1`.
Set `NAVTOOL_ROUTER_V8_FIXTURE_DIR` to that build directory's `fixtures-v8`
for the required managed strategic/replay boundary tests.

V8 tests generate reproducible inputs and real final v2 fixtures under the native
build directory's `fixtures-v8/`: explicit boats, arrived/partial/current/maneuver
and GSHHG results, plus mirrored delayed-corridor and losing-first-tack island
results. Tests verify early sacrifice, later complete arrival improvement and
native timed-segment legality, with fixed worker count.

For optional bounded diagnostics run:

```sh
NAVTOOL_NATIVE_DIAGNOSTICS=ON ./scripts/build-native.sh
```

PowerShell: `.\scripts\build-native.ps1 -Diagnostics`.
This replays only the controlled fixture's verified, fixed-hour heading policy
and compares a declared nine-action `{45°,135°}` exhaustive grid. It is not a
continuous global optimum or general inference of controls from route vertices.
Arrivals, partials, errors and runtime are reported separately. No exhaustive
reference runs in the ordinary regression mode.

Publish scripts rebuild/test first, reject mismatched native host/RID pairs,
copy Windows multi-config `Release` outputs, and load the exact packaged bridge
for preflight. Publishing stays framework-dependent; ecCodes remains a runtime
dependency. Other-platform jobs are CI validation, not local cross-compilation.
