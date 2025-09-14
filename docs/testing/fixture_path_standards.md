# Test Fixture Path Standards

This document defines the standard fixture paths for NavTool's test suite to prevent path inconsistencies and improve maintainability.

## 📁 Standard Directory Structure

```
test/fixtures/
├── charts/                          # Chart-related fixtures
│   └── s57_data/                    # S57 chart data (centralized location)
│       ├── *.zip                    # Compressed NOAA ENC charts
│       └── ENC_ROOT/                # Extracted S57 files
│           ├── US5WA50M/            # Elliott Bay Harbor
│           │   └── US5WA50M.000     # Raw S57 data
│           └── US3WA01M/            # Puget Sound Coastal
│               └── US3WA01M.000     # Raw S57 data
├── geometry/                        # Geometry test fixtures
├── golden/                          # Golden snapshot files
├── iso8211/                        # ISO 8211 test data
└── s57/                            # S57 object test fixtures
```

## 🎯 Path Standards

### ✅ DO: Use Centralized Constants

```dart
// GOOD: Use centralized path constants
import '../utils/fixture_paths.dart';

final zipPath = FixturePaths.ChartPaths.elliottBayZip;
final s57Path = FixturePaths.ChartPaths.elliottBayS57;
```

### ❌ DON'T: Use Hardcoded Paths

```dart
// BAD: Hardcoded paths lead to inconsistencies
final path = 'test/fixtures/charts/noaa_enc/US5WA50M_harbor_elliott_bay.zip';
final path2 = 'test/fixtures/charts/s57_data/US5WA50M_harbor_elliott_bay.zip';
```

## 🔧 Centralized Constants

All fixture paths are defined in `test/utils/fixture_paths.dart`:

### Base Paths
- `FixturePaths.charts` - Base chart fixtures directory
- `FixturePaths.s57Data` - S57 chart data directory (both ZIP and extracted)
- `FixturePaths.s57EncRoot` - Extracted S57 files directory
- `FixturePaths.golden` - Golden snapshot files

### Chart-Specific Paths
- `FixturePaths.ChartPaths.elliottBayZip` - Elliott Bay ZIP file
- `FixturePaths.ChartPaths.elliottBayS57` - Elliott Bay S57 file
- `FixturePaths.ChartPaths.pugetSoundZip` - Puget Sound ZIP file
- `FixturePaths.ChartPaths.pugetSoundS57` - Puget Sound S57 file

## 🛠️ Utilities

### Fixture Validation

```dart
import '../utils/fixture_paths.dart';

// Check if all required fixtures are available
final validation = FixtureUtils.validateChartFixtures();
if (!validation.allAvailable) {
  print('Missing fixtures: ${validation.missingFixtures}');
}
```

### Path Utilities

```dart
// Check if fixture exists
final exists = FixtureUtils.exists(FixturePaths.ChartPaths.elliottBayZip);

// Get absolute path
final absolutePath = FixtureUtils.getAbsolutePath(relativePath);
```

## 🔄 Migration from Old Paths

### Before (Inconsistent)
```dart
// Multiple different paths used across codebase:
'test/fixtures/charts/noaa_enc/US5WA50M_harbor_elliott_bay.zip'
'test/fixtures/charts/s57_data/ENC_ROOT/US5WA50M/US5WA50M.000'
```

### After (Standardized)
```dart
// Single source of truth:
FixturePaths.ChartPaths.elliottBayZip
FixturePaths.ChartPaths.elliottBayS57
```

## 📋 Migration Checklist

When adding new fixtures or tests:

- [ ] Use `FixturePaths` constants instead of hardcoded paths
- [ ] Add new path constants to `fixture_paths.dart` if needed  
- [ ] Update fixture validation in `FixtureUtils.validateChartFixtures()`
- [ ] Add test coverage for new paths in `fixture_paths_test.dart`
- [ ] Document the fixture purpose and expected format

## 🔍 CI Validation

The path consistency is validated in CI through:
- `test/utils/fixture_paths_test.dart` - Path structure validation
- Fixture availability checks in relevant test suites
- Build failures if fixtures are missing or paths are incorrect

## 🚫 Deprecated Patterns

### TestChartData Class
The `TestChartData` class in `test/fixtures/charts/test_chart_data.dart` is deprecated:

```dart
// DEPRECATED: Use FixturePaths instead
TestChartData.elliottBayHarborChart

// NEW: Use centralized constants
FixturePaths.ChartPaths.elliottBayZip
```

### Direct Path References
Avoid directly referencing the old `noaa_enc` directory (now removed):

```dart
// REMOVED: This directory no longer exists
'test/fixtures/charts/noaa_enc/'

// CURRENT: Unified location
'test/fixtures/charts/s57_data/'
```

## 📈 Benefits

1. **Consistency**: Single source of truth for all fixture paths
2. **Maintainability**: Easy to update paths in one location
3. **Discoverability**: Clear documentation of available fixtures
4. **Validation**: Automated checks for fixture availability
5. **CI Integration**: Path consistency enforced in continuous integration

## 🆘 Troubleshooting

### Missing Fixtures Error
If you see fixture-related test failures:

1. Run fixture validation:
   ```dart
   final validation = FixtureUtils.validateChartFixtures();
   print(validation.statusMessage);
   ```

2. Check if fixtures exist in correct location:
   ```bash
   ls -la test/fixtures/charts/s57_data/
   ```

3. Verify paths match the constants in `fixture_paths.dart`

### Path Update Required
When updating fixture paths:

1. Update constants in `test/utils/fixture_paths.dart`
2. Update validation logic in `FixtureUtils.validateChartFixtures()`
3. Add tests in `test/utils/fixture_paths_test.dart`
4. Update this documentation

---

**Remember**: Always use the centralized `FixturePaths` constants to maintain consistency and prevent future path-related issues! 🎯