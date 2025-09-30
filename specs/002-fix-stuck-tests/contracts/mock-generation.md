# Mock Generation Contract

## Contract: build_runner Mock Generation

### Command
```bash
flutter packages pub run build_runner build --delete-conflicting-outputs [--verbose]
```

### Purpose
Generate .mocks.dart files from @GenerateMocks annotations for testing with mockito.

### Inputs

#### Source Files
- Test files with `@GenerateMocks([ClassA, ClassB, ...])` annotations
- Example: `test/features/charts/chart_browser_screen_test.dart`

#### Annotation Format
```dart
import 'package:mockito/annotations.dart';

@GenerateMocks([
  NoaaChartDiscoveryService,  // Must be importable class
  AppLogger,                   // Must not have private constructor
  GpsService,                  // Must not have circular dependencies
])
import 'chart_browser_screen_test.mocks.dart';  // Generated file

void main() {
  // Tests use MockNoaaChartDiscoveryService, MockAppLogger, MockGpsService
}
```

### Outputs

#### Generated Files
- `test/**/*.mocks.dart` files
- One .mocks.dart per test file with @GenerateMocks
- Example: `chart_browser_screen_test.mocks.dart`

#### Generated Mock Classes
```dart
// chart_browser_screen_test.mocks.dart
class MockNoaaChartDiscoveryService extends Mock implements NoaaChartDiscoveryService {}
class MockAppLogger extends Mock implements AppLogger {}
class MockGpsService extends Mock implements GpsService {}
```

### Preconditions
1. All classes in @GenerateMocks list must be importable
2. Classes must not have private constructors
3. No circular mock dependencies
4. pubspec.yaml must include:
   ```yaml
   dev_dependencies:
     mockito: ^5.4.4
     build_runner: ^2.4.12
   ```

### Postconditions
1. .mocks.dart files generated successfully
2. Mock classes compile without errors
3. Tests can import and use mock classes
4. No conflicting files (old vs new generation)

### Success Criteria
```
[INFO] Succeeded after XXXms with YYY outputs
```

### Failure Modes

#### 1. Dependency Conflict
```
Error: Could not resolve package 'mockito'
```
**Resolution**: Run `flutter pub get` first

#### 2. Invalid Annotation
```
Error: Could not find class 'SomeClass' in @GenerateMocks
```
**Resolution**: Add import for SomeClass or remove from annotation

#### 3. Private Constructor
```
Error: Cannot mock class with private constructor
```
**Resolution**: Use factory pattern or make constructor public for testing

#### 4. Circular Dependency
```
Error: Circular reference detected in mock generation
```
**Resolution**: Break dependency cycle in @GenerateMocks lists

#### 5. File Write Error
```
Error: Could not write to file 'test/**/*.mocks.dart'
```
**Resolution**: Check permissions, delete .dart_tool/build cache

### CI Integration

#### GitHub Actions Workflow
```yaml
- name: Generate mocks
  run: flutter packages pub run build_runner build --delete-conflicting-outputs --verbose
  timeout-minutes: 5
```

#### Flags
- `--delete-conflicting-outputs`: Remove stale generated files
- `--verbose`: Print detailed diagnostic information
- `timeout-minutes: 5`: Prevent infinite hangs in CI

#### Cache Strategy
```yaml
- name: Cache build artifacts
  uses: actions/cache@v3
  with:
    path: |
      .dart_tool/build
      **/*.mocks.dart
    key: ${{ runner.os }}-build-${{ hashFiles('**/pubspec.yaml') }}
```

### Validation

#### Local Validation
```bash
# Clean build artifacts
flutter clean
rm -rf .dart_tool/build

# Generate mocks with verbose output
flutter packages pub run build_runner build --delete-conflicting-outputs --verbose

# Verify generated files
ls test/**/*.mocks.dart

# Run tests to verify mocks work
flutter test test/features/charts/chart_browser_screen_test.dart
```

#### CI Validation
```bash
# In CI workflow:
# 1. Clean cache
# 2. Generate mocks with verbose output
# 3. Run tests
# 4. Upload logs on failure
```

### Performance

#### Expected Duration
- Local: 30 seconds - 2 minutes (depends on number of test files)
- CI: 1 - 5 minutes (includes cache restore/save)

#### Optimization
- Cache .dart_tool/build between runs
- Use --delete-conflicting-outputs to avoid incremental build issues
- Run once per CI build, not per test run

### Error Recovery

#### If mock generation fails:
1. Run `flutter clean`
2. Run `flutter pub get`
3. Delete `.dart_tool/build/` directory
4. Retry `flutter packages pub run build_runner build --delete-conflicting-outputs --verbose`
5. Check verbose output for specific error
6. Fix annotation or dependency issue
7. Retry generation

#### If CI fails but local succeeds:
1. Check Flutter/Dart version matches CI
2. Verify pubspec.lock is committed
3. Check CI cache is not corrupt
4. Add verbose logging to CI workflow
5. Review CI logs for permission or path issues

### Testing the Contract

#### Unit Test: Mock Generation Success
```bash
# Expectation: Mocks generate without errors
flutter packages pub run build_runner build --delete-conflicting-outputs --verbose

# Verify exit code 0
echo $?  # Should print 0

# Verify files created
ls test/features/charts/chart_browser_screen_test.mocks.dart  # Should exist
```

#### Unit Test: Invalid Annotation
```bash
# Add invalid class to @GenerateMocks
# Run mock generation
# Expectation: Error message about missing class
```

#### Integration Test: CI Mock Generation
```bash
# Run GitHub Actions workflow locally with act
act -j build

# Verify workflow completes mock generation step
# Check for success message in logs
```

## Summary

Mock generation contract ensures:
1. ✅ Consistent mock file generation across local and CI
2. ✅ Clear error messages for debugging failures
3. ✅ Fast execution (under 5 minutes)
4. ✅ No manual intervention required
5. ✅ Reproducible results

All mock generation failures must provide actionable error messages and suggested resolutions.
