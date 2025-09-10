#!/bin/bash

# Elliott Bay Chart Rendering Validation Script
# Tests the complete chart rendering pipeline for Elliott Bay charts

set -e

echo "🗺️  Elliott Bay Chart Rendering Validation"
echo "==========================================="

# Check if we're in the correct directory
if [[ ! -f "pubspec.yaml" ]]; then
    echo "❌ Error: This script must be run from the navtool root directory"
    exit 1
fi

echo "📁 Checking test data availability..."

# Check Elliott Bay test files
ELLIOTT_BAY_FILE="test/fixtures/charts/noaa_enc/US5WA50M_harbor_elliott_bay.zip"
PUGET_SOUND_FILE="test/fixtures/charts/noaa_enc/US3WA01M_coastal_puget_sound.zip"

if [[ ! -f "$ELLIOTT_BAY_FILE" ]]; then
    echo "❌ Elliott Bay test data missing: $ELLIOTT_BAY_FILE"
    echo "   Please ensure test fixtures are available"
    exit 1
fi

if [[ ! -f "$PUGET_SOUND_FILE" ]]; then
    echo "❌ Puget Sound test data missing: $PUGET_SOUND_FILE"
    echo "   Please ensure test fixtures are available"
    exit 1
fi

echo "✅ Elliott Bay chart files found"
echo "   - Elliott Bay Harbor: $(du -h "$ELLIOTT_BAY_FILE" | cut -f1)"
echo "   - Puget Sound Coastal: $(du -h "$PUGET_SOUND_FILE" | cut -f1)"

echo ""
echo "🔧 Installing dependencies..."
flutter pub get

echo ""
echo "🧪 Running Elliott Bay rendering pipeline tests..."

# Run the specific Elliott Bay rendering tests
flutter test test/features/charts/elliott_bay_rendering_test.dart --verbose

echo ""
echo "🏗️  Running chart rendering service tests..."

# Run chart rendering service tests to ensure the rendering pipeline works
flutter test test/core/services/chart_rendering_service_test.dart --verbose

echo ""
echo "📊 Running Washington charts fixture tests..."

# Run Washington charts fixture tests to ensure test data integration works
flutter test test/core/fixtures/washington_charts_test.dart --verbose

echo ""
echo "🎯 Running S-57 to Maritime adapter tests..."

# Run adapter tests to ensure S-57 conversion works
flutter test test/core/adapters/s57_to_maritime_adapter_test.dart --verbose

echo ""
echo "📋 Test Summary"
echo "==============="

echo "✅ Elliott Bay ZIP extraction and S-57 parsing"
echo "✅ Maritime feature conversion pipeline" 
echo "✅ Chart rendering service integration"
echo "✅ Washington charts test data validation"

echo ""
echo "🚀 Running a quick integration validation..."

# Run a focused test on the chart tile management which includes Elliott Bay features
flutter test test/core/models/chart_tile_management_test.dart --verbose

echo ""
echo "✅ Elliott Bay Chart Rendering Pipeline Validation Complete!"
echo ""
echo "Next steps:"
echo "1. Run the app with: flutter run -d linux"
echo "2. Navigate to Charts > Elliott Bay Harbor Chart"
echo "3. Verify depth contours and buoys are rendered"
echo "4. Check that feature count is > 10 (not just boundary features)"

echo ""
echo "Expected Elliott Bay features:"
echo "- Depth contours (blue lines with depth labels)"
echo "- Depth areas (colored polygons by depth range)"
echo "- Navigation buoys (red/green symbols)"
echo "- Beacons (navigation aid symbols)"
echo "- Coastlines (Seattle waterfront boundaries)"
echo "- Harbor infrastructure"