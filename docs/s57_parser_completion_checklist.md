## S-57 Parser Completion Checklist (Issue #20)

Tracking document for finishing the "3.1 S-57 Parser Implementation" (Issue #20).

This checklist converts the remaining gaps into concrete, reviewable tasks with explicit acceptance criteria and test expectations. Use it as a PR body or as a coordination artifact. Each major section can become a separate PR if desired; check items only when verifiably implemented with tests.

---
### Legend
- [ ] = Not started
- [~] = In progress (partial implementation / draft PR open)
- [x] = Complete & merged (with tests)

---
## 1. ISO 8211 Core Parsing
Robust decoding of ENC (ISO/IEC 8211) structures beyond the current synthetic single-record parsing.

- [ ] Parse multiple records sequentially (DDR, DSID, DSSI, DSPM, feature records, vector records)
- [ ] Implement proper directory entry loop until 0x1E field terminator
- [ ] Support subfield delimiter 0x1F within field area
- [ ] Validate leader fields (record length, base address, field control length) with strict error messages
- [ ] Graceful recovery / skip strategy for malformed records (log & continue when possible)
- [ ] Unit tests with crafted multi-record binary fixture (at least 3 records)
- [ ] Integration test using real NOAA `.000` file confirming non-zero feature count without synthetic fallback

Acceptance Criteria:
1. Parser reads >1 record and extracts correct raw field maps.  
2. Failing a single malformed record does not abort entire file (unless DDR invalid).  
3. Tests assert presence of DSID/DSPM metadata fields.

---
## 2. Official S-57 Object Catalog Integration
Replace simplified enum usage with authoritative mapping of object class codes.

- [ ] Create data file `lib/core/services/s57/catalog/object_classes.json` (code → acronym → name)
- [ ] Expand `S57FeatureType` or introduce mapping layer preserving backward compatibility (deprecate unknown placeholder)
- [ ] Support at minimum: DEPARE (120), SOUNDG (127), COALNE, BOYLAT, BOYISD, BOYSPP, LIGHTS, LNDARE, OBSTRN, WRECKS, UWTROC
- [ ] Add factory to resolve by code and by acronym safely
- [ ] Add unit tests: translation correctness, unknown fallback
- [ ] Document mapping source (IHO S-57 Appendix A, Object Catalogue) in code comment

Acceptance Criteria:
1. 100% of codes used in sample NOAA chart map to non-unknown types.  
2. Unknown codes produce deterministic `S57FeatureType.unknown` with warning (not silent).  
3. Tests verify at least 10 mapped object codes.

---
## 3. Attribute Decoding & Validation
Broaden attribute handling; associate required/optional attributes with objects.

- [ ] Create `attributes.json` (code, acronym, name, type)
- [ ] Implement generic binary → logical type coercion (int, float, enum, string)
- [ ] Map at least these attributes: DRVAL1, DRVAL2, VALSOU, QUASOU, COLOUR, CATBOY, COLPAT, OBJNAM, HEIGHT, VALNMR, WATLEV, CATCOA, CATLMK
- [ ] Add per-object required attribute list (e.g., DEPARE requires DRVAL1)
- [ ] Validation step that flags missing required attributes (warning list) without failing parse
- [ ] Tests: attribute decoding, required attribute warning path, unknown attribute pass-through

Acceptance Criteria:
1. DEPARE features expose numeric DRVAL1/DRVAL2 values.  
2. SOUNDG exposes VALSOU as double.  
3. Lighthouse emits OBJNAM / HEIGHT where present.  
4. Test demonstrates warning collection for missing required attributes (exposed via `S57ParsedData.warnings`).

---
## 4. Geometry Assembly (Vector → Feature)
Support assembling complex geometries from vector records (e.g., edges, nodes) instead of synthetic defaults.

- [ ] Parse vector primitives: VRID, VRTX/SG2D, VE/VC linkages (or minimal subset) 
- [ ] Support feature → spatial pointer resolution (FSPT) for lines/areas
- [ ] Build polygon rings for areas (close if necessary) and expose geometryType.area
- [ ] Distinguish point vs line vs area from primitive relationships (not only coordinate count)
- [ ] Handle orientation flag in spatial pointers
- [ ] Tests with constructed binary fixture: one area (DEPARE), one line (COALNE), one point (SOUNDG)

Acceptance Criteria:
1. No fallback default coordinates used when valid spatial pointers exist.  
2. Areas have first/last coordinate identical (closed) or closed programmatically.  
3. Line feature coordinate order respects orientation flags.

---
## 5. Update File Sequencing (.001, .002 …)
Apply sequential updates to base cell.

- [ ] Implement update file ingestion order (numeric ascending)
- [ ] Support RUIN (Record Update Instruction) semantics: I (insert), D (delete), M (modify)
- [ ] Maintain record version (RVER) tracking
- [ ] Provide summary in `S57ParsedData.updateSummary`
- [ ] Tests: apply synthetic .001 deleting a feature, .002 modifying attribute, .003 inserting new feature

Acceptance Criteria:
1. Final feature set reflects cumulative updates.  
2. Deleted features absent; modified features show new attributes/geometry.  
3. Summary reports counts of inserted/modified/deleted.

---
## 6. Spatial Index Performance Upgrade
Replace linear scan with sublinear structure.

- [ ] Introduce `S57SpatialTree` (quadtree or R-tree) with insert & query
- [ ] Bulk build from feature list
- [ ] Query APIs mirror existing: bounds, point (radius), type filtering
- [ ] Benchmarks: dataset of ≥10k mixed features
- [ ] Fallback to linear only in debug or tiny datasets (<200 features)
- [ ] Tests: correctness parity with old index on deterministic fixture

Performance Targets:
- Bounds query < 10 ms (10k features)
- Point radius query < 2 ms (P50) on dev machine

Acceptance Criteria:
1. Performance test logs included (not necessarily enforced, but documented).  
2. Queries return identical sets vs baseline linear implementation.

---
## 7. Real NOAA ENC Integration Tests
Leverage actual cell archives (if licensing/redistribution constraints allow locally).

- [ ] Add unzip helper for test fixtures (skip test if archive missing)
- [ ] Parse US5WA50M `.000` file: assert > N DEPARE, ≥1 LIGHTS (if present), coastline present
- [ ] (Optional) Parse US3WA01M for performance metrics & feature diversity
- [ ] Validate metadata (cell ID, usage band, scale if derivable)
- [ ] Golden snapshot (JSON) of feature type frequency to detect regressions (allow threshold deltas)

Acceptance Criteria:
1. Tests pass when fixtures present; skip gracefully (not fail CI) when absent.  
2. Snapshot diff warns when feature distribution shifts > specified tolerance (e.g., ±10%).

---
## 8. Error Handling & Diagnostics
Enhance transparency and resilience.

- [ ] Central `S57ParseWarning` model (type, message, recordId?)
- [ ] Collect non-fatal issues (missing attrs, geometry coercions) in `S57ParsedData.warnings`
- [ ] Configurable strict mode that throws on first validation error
- [ ] Structured logging hooks (interface or callback) for UI integration
- [ ] Tests ensuring warnings captured & strict mode behavior

Acceptance Criteria:
1. Parsing real ENC yields zero errors & finite warnings list.  
2. Strict mode converts first missing-required-attribute into thrown `AppError`.

---
## 9. Performance & Memory Benchmarks
Document baseline costs.

- [ ] Add benchmark harness (`tool/bench_s57.dart`)
- [ ] Measure parse time & spatial query time for synthetic 1k, 5k, 10k feature datasets
- [ ] Report memory (approx) using object counts/sizes
- [ ] Save results to `docs/benchmarks/s57_benchmarks.md`

Acceptance Criteria:
1. Bench doc included in repo with reproducible steps.  
2. At least one optimization commit references delta improvements.

---
## 10. Documentation & Developer Experience

- [ ] Update `S57_IMPLEMENTATION_ANALYSIS.md` sections to reflect new capabilities & remaining gaps removed
- [ ] Create `docs/s57_format_overview.md` (concise reference: record flow diagram, object/attribute mapping tables)
- [ ] Add README section for “Parsing ENC Files” with usage example
- [ ] Add troubleshooting guide (common errors, warnings)

Acceptance Criteria:
1. New docs link from root README or existing navigation docs.  
2. Developer can parse a chart by following doc without diving into source.

---
## 11. API & Model Enhancements

- [ ] Extend `S57ChartMetadata` with: cellId, usageBand, scale, horizontalDatum, projection, compilationScale if available
- [ ] Add `S57ParsedData.findFeatures({types, bounds, textQuery})`
- [ ] Provide serialization to GeoJSON subset (Point/LineString/Polygon) for external tooling
- [ ] Tests: GeoJSON export shape validation

Acceptance Criteria:
1. Metadata populated for real NOAA cell (cell ID must match filename).  
2. GeoJSON export validated by simple schema checks in tests.

---
## 12. Backward Compatibility & Migration

- [ ] Maintain existing `S57FeatureType` values used elsewhere; add alias layer for new official codes
- [ ] Deprecation notice for synthetic fallback path (remove once real parsing stable)
- [ ] Provide feature count & type summary method (`summary()`) for UI
- [ ] Tests confirm unchanged behavior for existing callers (snapshot or contract test)

---
## 13. Quality Gates Before Closing Issue #20

- [ ] All above mandatory sections (1–8) completed
- [ ] CI green: unit, integration, benchmark (non-failing), lint
- [ ] Real NOAA test executes locally producing non-synthetic features
- [ ] Documentation updated & linked
- [ ] At least one performance benchmark recorded showing sublinear query improvement
- [ ] No remaining TODO comments blocking production use

---
## Open Questions (Resolve Before Final Close)
- Do we need encrypted / secure chart handling (future phase)?
- Is update parsing required for MVP navigation, or can it defer one milestone?
- Target precision & scaling factors (confirm COMF, SOMF values from DSPM record instead of assuming 10^7)?

Track resolutions here:
- [ ] Scaling factors derived from DSPM
- [ ] Decision on update file timing
- [ ] Decision on minimal attribute set for MVP

---
## Suggested PR / Issue Breakdown
1. ISO 8211 Core Parser (Sections 1 & partially 3)  
2. Object Catalog + Attribute Mapping (Sections 2 & remainder of 3)  
3. Geometry Assembly (Section 4)  
4. Update Sequencing (Section 5)  
5. Spatial Index Upgrade + Benchmarks (Sections 6 & 9)  
6. Real ENC Integration Tests (Section 7)  
7. Error & Warning Infrastructure (Section 8)  
8. API & Metadata Enhancements (Sections 11 & 12)  
9. Documentation Pass (Section 10)  
10. Final Consolidation & Quality Gates (Section 13)

---
## Definition of Done (Re-Statement)
Issue #20 can be closed only when:
1. Real NOAA `.000` cell produces a valid, non-synthetic feature set (≥ expected core object classes).  
2. Parser derives coordinates using DSPM scaling factors (no hard-coded 10^7 assumption).  
3. Spatial queries operate in <10 ms on 10k feature dataset (documented).  
4. Update (.001) files applied correctly (demonstrated in test).  
5. Documentation enables a new contributor to parse and query an ENC in <10 minutes.

---
## Progress Log (Fill as Work Advances)
- YYYY-MM-DD: Section 1 parser refactor merged (#PR)
- YYYY-MM-DD: Object catalog integration (#PR)
- YYYY-MM-DD: ...

---
## Maintainers Notes
Keep synthetic feature generation code until real parsing proves stable; mark with `@deprecated` and remove after two real-chart releases.

---
Feel free to adapt or prune if scope changes. This file can be referenced directly from future PR descriptions.
