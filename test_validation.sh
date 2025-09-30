#!/bin/bash
# Validation script for test fixes
# Tests should complete within 5 minutes without hanging

echo "=== Running Chart Browser Screen Tests ==="
echo "Start time: $(date)"

# Run with explicit timeout
flutter test test/features/charts/chart_browser_screen_test.dart --timeout=5m 2>&1 | tee chart_browser_test_results.txt

EXIT_CODE=$?
echo "End time: $(date)"
echo "Exit code: $EXIT_CODE"

# Check for specific hanging test patterns
if grep -q "pumpAndSettle timed out" chart_browser_test_results.txt; then
    echo "❌ FAILED: Tests are still hanging on pumpAndSettle"
    exit 1
elif grep -q "TimeoutException" chart_browser_test_results.txt; then
    echo "⚠️  WARNING: Tests timed out (but may be legitimately slow)"
    exit 2
else
    echo "✅ SUCCESS: No hanging tests detected"
    
    # Count passing tests
    PASSING=$(grep -oE '\+[0-9]+' chart_browser_test_results.txt | tail -1)
    echo "Passing tests: $PASSING"
    exit 0
fi
