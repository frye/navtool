# Test Pump Strategy Contracts

## Contract 1: pumpAndWait() Helper

### Signature
```dart
Future<void> pumpAndWait(
  WidgetTester tester, {
  Duration wait = const Duration(milliseconds: 800),
}) async
```

### Purpose
Provides controlled waiting for async operations in widget tests without risk of infinite loops.

### Behavior
1. Call `tester.pump()` to process current frame
2. Wait for `wait` duration using `Future.delayed()`
3. Call `tester.pump()` again to process frames after async completion

### Preconditions
- `tester` must be valid WidgetTester from testWidgets()
- `wait` duration should match expected async operation completion time

### Postconditions
- Two frames processed with explicit delay between them
- Test clock advanced by `wait` duration
- No infinite loop risk

### Usage Contract
```dart
// After async operation like tap or state change
await tester.tap(find.text('Filter by Scale Range'));
await pumpAndWait(tester);  // Wait for filter UI to build

// With custom wait time
await pumpAndWait(tester, wait: const Duration(seconds: 1));
```

### Error Handling
- If `wait` is too short, UI may not fully update: User must increase duration
- If `wait` is too long, test runs slower: User should optimize duration

---

## Contract 2: pumpAndSettleWithTimeout() Helper

### Signature
```dart
Future<void> pumpAndSettleWithTimeout(
  WidgetTester tester, {
  Duration timeout = const Duration(seconds: 15),
}) async
```

### Purpose
Provides pumpAndSettle() with extended timeout for complex marine navigation UI.

### Behavior
1. Call `tester.pumpAndSettle(timeout)` with specified timeout
2. Wait for all animations and rebuilds to complete
3. Throw timeout error if settling takes longer than `timeout`

### Preconditions
- `tester` must be valid WidgetTester
- Widget must eventually reach stable state (no infinite rebuilds)

### Postconditions
- All animations complete
- No pending rebuilds
- Widget tree in stable state

### Usage Contract
```dart
// For complex UI with multiple animations
await tester.tap(find.text('California'));
await pumpAndSettleWithTimeout(tester);  // 15s default

// For simple UI (use shorter timeout)
await pumpAndSettleWithTimeout(tester, timeout: const Duration(seconds: 5));
```

### Error Handling
- If widget has infinite rebuild loop: Test WILL hang until timeout
- If timeout too short: Test fails prematurely
- **DO NOT USE** for filter interactions that trigger continuous updates

---

## Contract 3: Manual pump() Pattern

### Signature
```dart
await tester.pump();                              // Process current frame
await Future.delayed(const Duration(milliseconds: 100));  // Explicit wait
await tester.pump();                              // Process next frame
```

### Purpose
Provides maximum control over frame processing for debugging stuck tests.

### Behavior
1. Process one frame at a time
2. Explicit waits between frames
3. No automatic settling

### Preconditions
- Developer understands widget rebuild cycle
- Async operations have known completion time

### Postconditions
- Exact number of frames processed as specified
- Test clock advanced by explicit delays

### Usage Contract
```dart
// For debugging: See exactly when UI updates
await tester.tap(find.byIcon(Icons.info_outline));
await tester.pump();  // Process tap
await Future.delayed(const Duration(milliseconds: 200));  // Wait for dialog animation
await tester.pump();  // Process dialog build
await Future.delayed(const Duration(milliseconds: 100));  // Wait for content
await tester.pump();  // Final frame

// Verify dialog is now visible
expect(find.byType(AlertDialog), findsOneWidget);
```

### Error Handling
- If too few pump() calls: UI not fully rendered
- If delays too short: Async operations not complete
- If delays too long: Test unnecessarily slow

---

## Contract 4: Test Timeout Configuration

### Signature
```dart
testWidgets(
  'test description',
  (WidgetTester tester) async {
    // test body
  },
  timeout: Timeout(Duration(minutes: 15)),
);
```

### Purpose
Prevents tests from hanging indefinitely by enforcing maximum execution time.

### Behavior
1. Test runs normally
2. If execution exceeds timeout, test fails with timeout error
3. Framework kills test and proceeds to next test

### Preconditions
- Timeout duration must be reasonable for test complexity
- Test must be designed to complete within timeout

### Postconditions
- Test either completes successfully or fails with timeout
- No infinite hangs

### Usage Contract
```dart
// For complex marine UI tests
testWidgets(
  'should filter charts by scale range',
  (WidgetTester tester) async {
    // Complex interaction testing
  },
  timeout: Timeout(Duration(minutes: 2)),  // Marine UI complexity requires time
);

// For simple tests (use default timeout)
testWidgets('should display title', (WidgetTester tester) async {
  // Simple test
});
```

### Error Handling
- If timeout too short: Valid slow tests fail
- If timeout too long: Stuck tests waste time
- Recommended: 2 minutes for complex UI, 30 seconds for simple tests

---

## Implementation Checklist

For each test that hangs:

1. ✅ Identify pump strategy: pumpAndSettle(), pump(), or pumpAndWait()
2. ✅ Check for infinite rebuild triggers (Slider, continuous animations)
3. ✅ Replace pumpAndSettle() with pumpAndWait() for filter interactions
4. ✅ Add explicit timeout to test if not present
5. ✅ Verify test completes within timeout locally
6. ✅ Preserve all test assertions (no behavioral changes)
7. ✅ Run full test suite to ensure no regressions
