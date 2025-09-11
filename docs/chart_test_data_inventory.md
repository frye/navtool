# Chart Test Data Inventory

This document provides a complete inventory of test chart data available for development and testing.

## NOAA ENC Test Charts

Location: `test/fixtures/charts/noaa_enc/`

### Elliott Bay / Seattle Harbor Test Set

Downloaded September 3, 2025 from NOAA's official ENC distribution.

| Chart File | Cell ID | Scale | Coverage | Size | Usage |
|------------|---------|-------|----------|------|-------|
| `US5WA50M_harbor_elliott_bay.zip` | US5WA50M | Harbor (1:20,000) | Elliott Bay, Seattle Harbor | 143.9 KB | S-57 parsing, harbor-scale rendering |
| `US3WA01M_coastal_puget_sound.zip` | US3WA01M | Coastal (1:90,000) | Puget Sound region | 625.3 KB | Multi-scale testing, coastal overview |

### Chart Content Summary

**US5WA50M** (Harbor Scale):
- Primary data: 411,513 bytes (`US5WA50M.000`)
- Updates: 7,223 bytes (`US5WA50M.001`)
- Features: Detailed harbor bathymetry, pier structures, navigation aids
- Title: "APPROACHES TO EVERETT"
- Last Modified: September 2, 2025

**US3WA01M** (Coastal Scale):
- Broader coverage of Puget Sound
- Includes approach channels and coastal features
- Suitable for testing multi-resolution chart display

## Data Integrity

All test charts include SHA256 checksums for verification:

```
US5WA50M: B5C5C72CB867F045EB08AFA0E007D74E97D0E57D6C137349FA0056DB8E816FAE
US3WA01M: [Checksum available in download logs]
```

## Testing Applications

### S-57 Format Parsing
- Binary data structure validation
- Coordinate system transformations
- Feature object extraction
- Attribute parsing and validation

### Chart Rendering
- Harbor-scale detail rendering (US5WA50M)
- Coastal overview rendering (US3WA01M)
- Scale-dependent feature visibility
- Symbol placement and styling

### Spatial Operations
- Bounding box calculations
- Point-in-polygon testing with real chart boundaries
- Distance calculations using actual navigational features
- Coordinate projection testing

### Performance Benchmarking
- Real-world data size processing
- Memory usage with actual chart complexity
- Rendering performance with authentic feature density

## Phase 4 Real Data Policy (Issue #203)

During Phase 4 (Elliott Bay Chart Loading UX Improvements), all new or modified widget/integration tests that exercise chart loading, progress overlays, layer visibility, or chart information dialogs MUST parse real NOAA ENC fixtures (no synthetic placeholder feature sets). Specifically:

- Required fixtures: `US5WA50M_harbor_elliott_bay.zip`, `US3WA01M_coastal_puget_sound.zip`
- Tests must decompress in-memory and parse the `.000` dataset
- Feature counts asserted must derive from actual parsed features
- Any missing fixture results in an explicit skip with guidance (not silent pass)
- Synthetic byte arrays remain only in low-level parser unit tests isolated from UX

Helper utilities:
- `S57Parser.loadFromZip(path, chartId: id)` simplifies real chart parsing
- `bin/validate_enc_fixtures.dart` verifies size & checksums

Acceptance success criteria include verification that user-visible counts, statistics, and layer toggles reflect real ENC content, eliminating reliance on sample items (3) placeholder data.

## Important Disclaimers

⚠️ **These are snapshot copies for testing only** - not suitable for navigation
⚠️ **Data is from September 2025** - charts may be outdated
⚠️ **Official charts available at**: https://nauticalcharts.noaa.gov/

## Adding New Test Charts

When adding new chart data:

1. Place files in appropriate subdirectory under `test/fixtures/charts/`
2. Use descriptive filenames indicating scale and region
3. Document in this inventory with:
   - Source and download date
   - File size and checksum
   - Intended test usage
   - Coverage area description
4. Include disclaimers about currency and navigation use

---
*Chart test data maintained for navtool development*