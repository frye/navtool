# Phase 1: Data Model - Test Execution States

**Status**: Complete  
**Date**: September 29, 2025

## Overview

This bug fix does not introduce new data models in the application code. Instead, it documents the internal state machines and workflows for test execution and mock generation that must be understood to fix the hanging tests.

## Entity 1: Test Execution State

### Purpose
Represents the internal state of a Flutter widget test as it progresses through setup, execution, and teardown phases.

### States
```
NOT_STARTED
  ↓ (testWidgets() called)
SETUP
  ↓ (setUp() complete, widget built)
PUMPING
  ↓ (pump() / pumpAndSettle() called)
WAITING_FOR_FRAMES
  ↓ (animation frames processed)
IDLE
  ↓ (next interaction)
INTERACTING
  ↓ (tap(), drag(), enterText())
PUMPING (loop)
  ↓ (test assertions)
ASSERTING
  ↓ (all assertions pass)
COMPLETE
  ↓ (tearDown())
CLEANED_UP

ERROR STATES:
STUCK_PUMPING      # pumpAndSettle() never completes (ISSUE)
TIMEOUT            # test exceeds timeout duration
ASSERTION_FAILED   # expect() fails
EXCEPTION          # unhandled exception
```

### State Transitions

#### Normal Flow
1. `NOT_STARTED` → `SETUP`: Test begins, setUp() runs
2. `SETUP` → `PUMPING`: First pumpWidget() called
3. `PUMPING` → `WAITING_FOR_FRAMES`: Flutter schedules frames
4. `WAITING_FOR_FRAMES` → `IDLE`: All pending frames processed
5. `IDLE` → `INTERACTING`: Test performs tap(), drag(), etc.
6. `INTERACTING` → `PUMPING`: pump() called after interaction
7. `PUMPING` → `IDLE`: Frames processed
8. `IDLE` → `ASSERTING`: Test runs expect() statements
9. `ASSERTING` → `COMPLETE`: All assertions pass
10. `COMPLETE` → `CLEANED_UP`: tearDown() runs

#### Error Flow (Current Issue)
1. `IDLE` → `INTERACTING`: Test taps filter control
2. `INTERACTING` → `PUMPING`: pumpAndSettle() called
3. `PUMPING` → `WAITING_FOR_FRAMES`: Widget rebuilds scheduled
4. `WAITING_FOR_FRAMES` → `PUMPING`: New rebuild scheduled (INFINITE LOOP)
5. **STUCK**: Test never reaches `IDLE`, hangs indefinitely

### Attributes
- **currentState**: Current test execution state
- **frameCount**: Number of frames processed since last pump
- **pendingTimers**: Active Timer/Future callbacks
- **rebuildCount**: Widgets scheduled for rebuild
- **timeout**: Maximum test duration (e.g., 15 minutes)
- **elapsedTime**: Time since test started

### Validation Rules
- Test MUST transition from PUMPING to IDLE within timeout
- STUCK_PUMPING MUST trigger timeout error after 15 minutes
- pumpAndSettle() MUST have maximum iteration limit (default: 100)

## Entity 2: Widget Pump Strategy

### Purpose
Represents the different strategies for advancing widget test frames and waiting for UI updates.

### Types

#### pumpAndSettle()
```dart
await tester.pumpAndSettle(
  Duration timeout = const Duration(seconds: 10),
  EnginePhase phase = EnginePhase.sendSemanticsUpdate,
  Duration duration = const Duration(milliseconds: 100),
);
```
- **Behavior**: Repeatedly calls pump() until no frames scheduled
- **Risk**: Infinite loop if continuous rebuilds
- **Use Case**: Simple UIs with finite animations
- **Current Issue**: Hangs on filter controls with continuous updates

#### pump()
```dart
await tester.pump(Duration? duration);
```
- **Behavior**: Advances test clock by duration, processes single frame
- **Risk**: May not capture all async state changes
- **Use Case**: Fine-grained control over frame processing
- **Recommended**: Use with explicit Future.delayed() for async operations

#### pumpAndWait() (Custom Helper)
```dart
await pumpAndWait(
  WidgetTester tester,
  Duration wait = const Duration(milliseconds: 800),
);
```
- **Behavior**: pump() → Future.delayed() → pump()
- **Risk**: Fixed delay may be too short or too long
- **Use Case**: Async operations with known completion time
- **Current Implementation**: Already defined in chart_browser_screen_test.dart

#### pumpAndSettleWithTimeout() (Custom Helper)
```dart
await pumpAndSettleWithTimeout(
  WidgetTester tester,
  Duration timeout = const Duration(seconds: 15),
);
```
- **Behavior**: pumpAndSettle() with extended timeout
- **Risk**: Still hangs if infinite rebuild loop
- **Use Case**: Complex marine UI requiring longer settle time
- **Current Implementation**: Already defined with 15s timeout

### Attributes
- **strategy**: Type of pump strategy (pumpAndSettle, pump, pumpAndWait)
- **timeout**: Maximum wait duration
- **explicitDelay**: Duration for Future.delayed() in pumpAndWait
- **maxIterations**: Maximum pump() calls for pumpAndSettle()
- **skipFrames**: Whether to skip animation frames

### Validation Rules
- pumpAndSettle() MUST have timeout to prevent infinite hangs
- Custom helpers MUST use pump() primitives correctly
- Async operations MUST be awaited before pump()

## Entity 3: Mock Generation Workflow

### Purpose
Represents the build_runner code generation process for creating .mocks.dart files.

### States
```
NOT_STARTED
  ↓ (flutter packages pub run build_runner build)
RESOLVING_DEPENDENCIES
  ↓ (pub get complete)
SCANNING_ANNOTATIONS
  ↓ (@GenerateMocks found)
GENERATING_CODE
  ↓ (mockito generates .mocks.dart)
WRITING_FILES
  ↓ (files written to disk)
COMPLETE

ERROR STATES:
DEPENDENCY_CONFLICT    # Package version incompatibility (ISSUE)
ANNOTATION_ERROR       # Invalid @GenerateMocks syntax (ISSUE)
GENERATION_FAILURE     # mockito code generation fails
FILE_WRITE_ERROR       # Permission or path issues
```

### State Transitions

#### Normal Flow
1. `NOT_STARTED` → `RESOLVING_DEPENDENCIES`: build_runner starts
2. `RESOLVING_DEPENDENCIES` → `SCANNING_ANNOTATIONS`: Dependencies resolved
3. `SCANNING_ANNOTATIONS` → `GENERATING_CODE`: @GenerateMocks found
4. `GENERATING_CODE` → `WRITING_FILES`: Mock code generated
5. `WRITING_FILES` → `COMPLETE`: .mocks.dart files written

#### Error Flow (Current Issue)
1. `NOT_STARTED` → `RESOLVING_DEPENDENCIES`: build_runner starts in CI
2. `RESOLVING_DEPENDENCIES` → `DEPENDENCY_CONFLICT`: Version mismatch
3. **FAILURE**: build_runner exits with error code

### Attributes
- **currentState**: Current generation workflow state
- **targetFiles**: Test files with @GenerateMocks annotations
- **generatedFiles**: Created .mocks.dart files
- **errors**: List of generation errors
- **verboseOutput**: Detailed diagnostic messages
- **cacheDir**: .dart_tool/build cache directory

### Validation Rules
- All @GenerateMocks classes MUST be importable
- Generated .mocks.dart files MUST compile without errors
- build_runner MUST complete within 5 minutes
- CI and local environments MUST produce identical output

## Entity 4: Test Fixture State

### Purpose
Represents test data and mock configurations used in chart_browser_screen_test.dart.

### Structure
```dart
// Mock services
MockNoaaChartDiscoveryService mockDiscoveryService;
MockAppLogger mockLogger;
MockGpsService mockGpsService;

// Test data
List<Chart> testCharts = createTestCharts();

// Widget configuration
ProviderScope(
  overrides: [
    noaaChartDiscoveryServiceProvider.overrideWithValue(mockDiscoveryService),
    loggerProvider.overrideWithValue(mockLogger),
    gpsServiceProvider.overrideWithValue(mockGpsService),
  ],
  child: MaterialApp(home: ChartBrowserScreen()),
)
```

### Attributes
- **mockServices**: List of mocked dependencies
- **testData**: Chart fixtures for testing
- **providerOverrides**: Riverpod provider test overrides
- **mockBehaviors**: Configured mock responses (when().thenAnswer())

### Validation Rules
- Mocks MUST be configured before widget pump
- Mock behaviors MUST match production service contracts
- Test data MUST use realistic marine coordinates (Constitution IX)

## Relationships

```
Test Execution State
  ├── uses → Widget Pump Strategy
  ├── validates → Test Fixture State
  └── triggers → Mock Generation Workflow (during setUp)

Widget Pump Strategy
  ├── modifies → Test Execution State
  └── waits for → UI State Changes

Mock Generation Workflow
  ├── creates → Test Fixture State (.mocks.dart files)
  └── validates → @GenerateMocks annotations

Test Fixture State
  ├── injected into → Chart Browser Screen Widget
  └── validated by → Test Assertions
```

## Affected Files

### Test Files
- `test/features/charts/chart_browser_screen_test.dart` (2100+ lines)
  - Current pump strategies causing hangs
  - Helper methods: pumpAndWait(), pumpAndSettleWithTimeout()
  
- `test/features/charts/chart_browser_screen_test.mocks.dart` (generated)
  - MockNoaaChartDiscoveryService
  - MockAppLogger
  - MockGpsService

### Configuration Files
- `pubspec.yaml` (lines 90-103)
  - mockito: ^5.4.4
  - build_runner: ^2.4.12
  
- `build.yaml` (if exists)
  - build_runner targets configuration

### CI Files
- `.github/workflows/noaa_integration_tests.yml` (line 66)
- `.github/workflows/binary-builds.yml` (lines 47, 130, 224, 327)
  - Mock generation step

## Summary

The bug fix requires understanding:
1. **Test Execution State Machine**: How tests progress through pumping/waiting cycles
2. **Pump Strategy Selection**: When to use pumpAndSettle() vs pump() vs custom helpers
3. **Mock Generation Workflow**: How build_runner creates .mocks.dart files
4. **Test Fixture Configuration**: How mocks are injected via Riverpod providers

No new data models are added to the application. All changes are in test infrastructure and execution patterns.
