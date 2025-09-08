#!/bin/bash

# Feature Distribution Baseline Refresh Script
#
# This script helps update the feature distribution baseline when intentional
# changes occur in the S-57 parser or catalog that affect feature counts.
#
# Usage:
#   ./scripts/refresh_baseline.sh
#   OR
#   chmod +x scripts/refresh_baseline.sh && ./scripts/refresh_baseline.sh

set -e

BASELINE_FILE="test/fixtures/s57/feature_distribution_baseline.json"
TEST_FILE="test/core/services/s57/feature_distribution_snapshot_test.dart"

echo "🔧 Feature Distribution Baseline Refresh"
echo "========================================"
echo

# Check if baseline file exists
if [ ! -f "$BASELINE_FILE" ]; then
    echo "❌ Baseline file not found: $BASELINE_FILE"
    exit 1
fi

# Check if test file exists  
if [ ! -f "$TEST_FILE" ]; then
    echo "❌ Test file not found: $TEST_FILE"
    exit 1
fi

echo "📁 Files found:"
echo "   Baseline: $BASELINE_FILE"
echo "   Test:     $TEST_FILE"
echo

# Show current baseline version
CURRENT_VERSION=$(grep '"version"' "$BASELINE_FILE" | cut -d'"' -f4)
echo "📊 Current baseline version: $CURRENT_VERSION"
echo

echo "📝 Manual Baseline Update Instructions:"
echo "   1. Edit the baseline file: $BASELINE_FILE"
echo "   2. Update the 'featureFrequency' section with new expected counts"
echo "   3. Update 'metadata.version' and 'metadata.lastUpdated'"
echo "   4. Document the reason for changes in your commit message"
echo

echo "🧪 Running test to verify current baseline..."
if flutter test "$TEST_FILE"; then
    echo "✅ Current baseline passes all tests"
    echo
    echo "💡 If you need to update the baseline:"
    echo "   - The test output above shows current vs expected counts"
    echo "   - Use the tolerance ranges to set new baseline values"
    echo "   - Update version to $(echo "$CURRENT_VERSION" | awk -F. '{print $1"."($2+1)}') in $BASELINE_FILE"
else
    echo "❌ Current baseline fails tests"
    echo
    echo "🔧 Update required! The test failure above shows:"
    echo "   - Which features are out of tolerance"
    echo "   - Expected ranges vs actual values"
    echo "   - Use this information to update $BASELINE_FILE"
    echo
    echo "Example update for $BASELINE_FILE:"
    echo '   "featureFrequency": {'
    echo '     "DEPARE": <new_count_from_test_output>,'
    echo '     "SOUNDG": <new_count_from_test_output>,'
    echo '     ...'
    echo '   }'
fi

echo
echo "🔍 To verify your changes, run:"
echo "   flutter test $TEST_FILE"
echo
echo "📚 For more information, see the documentation in:"
echo "   - $TEST_FILE (test header comments)"
echo "   - S57_IMPLEMENTATION_ANALYSIS.md"