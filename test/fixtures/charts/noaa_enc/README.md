# NOAA ENC Test Charts

This directory contains Electronic Navigational Chart (ENC) test data downloaded from NOAA for chart parsing and rendering tests.

## Chart Inventory

### Harbor Scale (Usage Band 5)
- **US5WA50M_harbor_elliott_bay.zip** - Harbor-scale chart covering Elliott Bay and Seattle Harbor
  - Cell ID: US5WA50M
  - Title: "APPROACHES TO EVERETT"
  - Coverage: Elliott Bay, Seattle Harbor, downtown Seattle waterfront
  - Scale: ~1:20,000 (harbor detail)
  - Size: 147,361 bytes (143.9 KB)
  - SHA256: `B5C5C72CB867F045EB08AFA0E007D74E97D0E57D6C137349FA0056DB8E816FAE`

### Coastal Scale (Usage Band 3)
- **US3WA01M_coastal_puget_sound.zip** - Coastal-scale chart covering broader Puget Sound region
  - Cell ID: US3WA01M
  - Coverage: Puget Sound, including Elliott Bay and surrounding waters
  - Scale: ~1:90,000 (coastal overview)
  - Size: 640,268 bytes (625.3 KB)

## Data Source and Disclaimers

**Source**: National Oceanic and Atmospheric Administration (NOAA)
- Downloaded from: `https://charts.noaa.gov/ENCs/`
- Official NOAA ENC® products in IHO S-57 format
- Downloaded on: September 3, 2025

**⚠️ Important Notice**: These are **point-in-time copies** downloaded for testing purposes only. They are **NOT up-to-date** versions of the charts and should **NEVER be used for actual navigation**.

For current, official charts suitable for navigation:
- Visit: https://nauticalcharts.noaa.gov/
- Use official NOAA ENC distribution: https://charts.noaa.gov/ENCs/
- Charts are updated weekly for Notice to Mariners

## Format Information

- **Standard**: IHO S-57 (International Hydrographic Organization Transfer Standard for Digital Hydrographic Data)
- **File Structure**: 
  - `.zip` archives containing:
    - `CATALOG.031` - S-57 format catalog
    - `US[X]WA[NN]M.000` - Primary chart data
    - `US[X]WA[NN]M.001` - Chart updates/corrections
    - Text files with chart notes and usage agreements

## Usage in Tests

These charts are intended for:
- S-57 format parsing validation
- Chart rendering engine testing
- Spatial data processing verification
- Performance benchmarking with real-world data

Example test usage:
```dart
// Load test chart for parsing
final chartPath = 'test/fixtures/charts/noaa_enc/US5WA50M_harbor_elliott_bay.zip';
final chartData = await S57Parser.loadFromZip(chartPath);
```

## Legal Notice

These NOAA ENC files are official products of the National Oceanic and Atmospheric Administration. Usage is subject to NOAA's terms and conditions included within each chart package.

---
*Test data organized for navtool chart parsing development - September 2025*