# NavTool - GitHub Copilot Development Instructions

**CRITICAL: Always follow these instructions first and fallback to additional search and context gathering only if the information in these instructions is incomplete or found to be in error.**

NavTool is a comprehensive marine navigation and routing application built with Flutter for cross-platform desktop performance. It features advanced Electronic Chart Display and Information System (ECDIS) capabilities, real-time GPS integration, and weather routing.

## Working Effectively

### Bootstrap and Dependencies
**NEVER CANCEL builds or long-running commands. Set timeouts of 90+ minutes for builds and 45+ minutes for tests.**

```bash
# Install system dependencies for Linux development
sudo apt-get update
sudo apt-get install -y build-essential cmake pkg-config libgtk-3-dev ninja-build

# For other platforms:
# Windows: Requires Visual Studio with C++ support
# macOS: Requires Xcode

# Install Flutter 3.8.1+ (exact version from pubspec.yaml)
# Download from: https://flutter.dev/docs/get-started/install
export PATH="$PATH:[PATH_TO_FLUTTER]/flutter/bin"

# Get dependencies - NEVER CANCEL: Takes 5-10 minutes
flutter pub get

# Generate mocks for testing - NEVER CANCEL: Takes 3-5 minutes  
flutter packages pub run build_runner build --delete-conflicting-outputs
```

### Build Commands
**CRITICAL: Set timeout to 90+ minutes for all build commands. NEVER CANCEL builds.**

```bash
# Development builds - NEVER CANCEL: Takes 15-30 minutes
flutter run -d linux    # Linux desktop
flutter run -d windows  # Windows desktop  
flutter run -d macos    # macOS desktop

# Release builds - NEVER CANCEL: Takes 45-90 minutes
flutter build linux --release
flutter build windows --release
flutter build macos --release
```

### Testing
**CRITICAL: Set timeout to 45+ minutes for test commands. NEVER CANCEL test runs.**

```bash
# Unit tests - NEVER CANCEL: Takes 10-15 minutes
flutter test --exclude-tags=integration,performance,real-endpoint

# Integration tests - NEVER CANCEL: Takes 20-30 minutes  
flutter test --tags=integration --timeout=30m --concurrency=1

# Performance tests - NEVER CANCEL: Takes 15-20 minutes
flutter test --tags=performance --timeout=20m

# Real endpoint tests (may fail if NOAA API down) - NEVER CANCEL: Takes 10-30 minutes
flutter test test/integration/noaa_real_endpoint_test.dart --timeout=30m

# All tests with coverage - NEVER CANCEL: Takes 30-45 minutes
flutter test --coverage --timeout=45m
```

### Analysis and Quality
**Always run these before committing or CI will fail.**

```bash
# Static analysis - Takes 1-2 minutes
flutter analyze --fatal-infos
dart analyze --fatal-infos

# Security audit - Takes 1-2 minutes  
flutter pub audit

# Format code - Takes < 1 minute
dart format .

# Check dependencies - Takes < 1 minute
flutter pub deps
```

## Validation

### Manual Testing Requirements
**ALWAYS manually validate changes with these scenarios:**

1. **Application Launch Test:**
   ```bash
   flutter run -d linux
   # Verify: Application opens with desktop window chrome
   # Verify: Main navigation menu displays correctly
   # Verify: About dialog shows correct version from pubspec.yaml
   ```

2. **Marine Navigation Workflow:**
   - Test chart data discovery (mock NOAA API calls)
   - Verify GPS coordinate handling and validation
   - Test offline functionality and data persistence
   - Validate marine-specific calculations and projections

3. **Cross-Platform Compatibility:**
   ```bash
   # Test on each target platform
   flutter run -d linux
   flutter run -d windows  
   flutter run -d macos
   ```

### Test Environment Setup
```bash
# Set test environment variables
export CI=false  # Local development
export SKIP_INTEGRATION_TESTS=false  # Enable integration tests
export SKIP_PERFORMANCE_TESTS=false  # Enable performance tests
export MARINE_SIMULATION=false  # Disable network simulation
```

## Common Tasks and File Locations

### Key Project Structure
```
lib/
├── app/                    # App configuration and routing
│   ├── app.dart           # Main app widget with navigation
│   └── routes.dart        # Route definitions
├── core/                   # Core business logic
│   ├── error/             # Error handling and classification
│   ├── monitoring/        # Rate limiting and metrics
│   ├── services/          # NOAA API and marine data services
│   └── state/             # Riverpod state management
├── features/              # Feature modules
│   ├── home/              # Main navigation interface
│   └── about/             # App information and settings
└── widgets/               # Reusable UI components

test/
├── core/                  # Core logic tests
├── features/              # Feature tests  
├── integration/           # End-to-end tests
├── utils/                 # Test utilities and fixtures
└── flutter_test_config.dart  # Global test configuration
```

### Important Configuration Files
- `pubspec.yaml` - Flutter dependencies and version (0.0.1+1)
- `analysis_options.yaml` - Dart linting rules
- `linux/CMakeLists.txt` - Linux desktop build configuration
- `windows/CMakeLists.txt` - Windows desktop build configuration
- `.github/workflows/noaa_integration_tests.yml` - CI/CD pipeline

### Frequently Modified Files
- **Marine Data Integration:** Always check `lib/core/services/noaa/` after API changes
- **State Management:** Check `lib/core/state/providers.dart` after adding new providers
- **Error Handling:** Update `lib/core/error/` when adding new error scenarios
- **Test Fixtures:** Update `test/utils/test_fixtures.dart` for new marine test data

## Platform-Specific Notes

### Linux (Primary Development Platform)
- Uses CMake build system with GTK 3.0
- Requires `build-essential cmake pkg-config libgtk-3-dev ninja-build`
- Custom window chrome implementation for desktop experience

### Windows
- Requires Visual Studio with C++ support
- Uses Win32 APIs for location services (avoids CMake issues)
- Custom window title bar implementation

### macOS  
- Requires Xcode
- Uses native menu bars (no custom window chrome)
- Includes macos_ui components for native feel

## Development Workflow

### Adding New Features
1. Create feature directory under `lib/features/[feature_name]/`
2. Add corresponding tests under `test/features/[feature_name]/`
3. Update route definitions in `lib/app/routes.dart`
4. Add provider registration in `lib/core/state/providers.dart`
5. **Always run full test suite before committing**

### Marine Navigation Development
- Use test fixtures from `test/utils/test_fixtures.dart` for realistic marine coordinates
- Follow maritime software conventions for critical navigation features
- Test with simulated GPS data using `MarineTestUtils.getMarineTestAreas()`
- Validate calculations against known marine navigation standards

### Error Handling Patterns
- Use `NoaaErrorClassifier` for API error categorization
- Implement retry logic with exponential backoff for marine connectivity
- Add error scenarios to `test/core/error/noaa_error_handling_test.dart`
- Follow marine safety patterns for critical navigation errors

## CI/CD Integration

The repository uses comprehensive GitHub Actions workflows:
- **Unit Tests:** 15-minute timeout, requires 90%+ coverage
- **Integration Tests:** 30-minute timeout, includes real NOAA API calls
- **Performance Tests:** 20-minute timeout, benchmarks marine calculations  
- **Cross-Platform Tests:** 25-minute timeout, validates all desktop platforms
- **Marine Environment Simulation:** Tests satellite connectivity scenarios

**CRITICAL:** All timeouts are set for marine environment conditions. Never reduce these timeouts as they account for satellite internet latency and intermittent connectivity scenarios that are common in marine environments.

## Architecture Patterns

### Widget Organization
- **Feature-based Structure**: `lib/features/[feature]/` (e.g., `home/`, `about/`)
- **Shared Widgets**: `lib/widgets/` for reusable components (e.g., `app_icon.dart`, `main_menu.dart`)
- **App Configuration**: `lib/app/` for routing and main app setup

### Responsive Design
- **Desktop-first approach** with `MediaQuery.of(context).size` for screen adaptation
- Target platforms: Desktop (Windows, macOS, Linux) with iOS support
- Use `LayoutBuilder` for responsive widget layouts
- Consider marine usage scenarios (outdoor visibility, touch vs mouse interaction)

### Theme System
- **Material Design 3** with `ColorScheme.fromSeed(seedColor: Colors.blue)`
- Marine-friendly color palette for nautical applications
- Dark/light theme support for day/night navigation usage
- High contrast options for outdoor visibility

## Error Handling

- Use Dart's built-in exception handling with try-catch blocks
- Implement custom exception classes for marine data operations
- Console logging for development debugging
- User-friendly error messages for navigation-critical failures

## Code Style and Structure

- Write concise, idiomatic Dart code following Flutter conventions.
- Use StatelessWidget for immutable UI components, StatefulWidget for interactive components.
- Prefer composition over inheritance; use mixins where appropriate.
- Use descriptive variable names with clear intent (e.g., `isChartLoaded`, `hasGpsSignal`).
- Structure Dart files: imports, main widget class, helper methods, private methods.

## Naming Conventions

- Use snake_case for file and directory names (e.g., `home_screen.dart`, `chart_display/`).
- Use PascalCase for class names (e.g., `HomeScreen`, `ChartDisplayWidget`).
- Use camelCase for variable and method names (e.g., `chartData`, `loadNavigationData()`).
- Prefix private members with underscore (e.g., `_privateMethod()`).

## UI and Styling

- Use Material Design 3 widgets from Flutter's material library
- Implement custom SVG icons using `flutter_svg` package for marine symbols
- Use `MediaQuery` and `LayoutBuilder` for responsive layouts
- Apply marine navigation UI principles:
  - High contrast for outdoor visibility
  - Large touch targets for use with gloves
  - Clear visual hierarchy for critical navigation data
  - Consistent with maritime software conventions

## Syntax and Formatting

- Follow Dart formatting guidelines with `dart format`
- Use const constructors where possible for performance
- Prefer named parameters for widget constructors
- Use trailing commas for better formatting and diffs

## Performance Optimization

- Use `const` widgets to reduce rebuilds
- Implement proper `Key` usage for widget identity
- Use `ListView.builder` for large datasets (chart lists, waypoints)
- Optimize chart rendering with efficient data structures
- Consider memory management for large nautical chart data

## Troubleshooting

### Common Build Issues
- **CMake errors on Linux:** Install `build-essential cmake libgtk-3-dev`
- **Windows location services:** Uses Win32 instead of geolocator_windows to avoid CMake conflicts
- **Flutter version conflicts:** Ensure Flutter 3.8.1+ as specified in pubspec.yaml

### Test Issues  
- **Integration test failures:** Check NOAA API availability, tests may fail if service is down
- **Performance test variations:** Marine calculations are CPU-intensive, allow for timing variations
- **Timeout errors:** NEVER reduce timeouts, increase if tests still fail

### Marine Development Issues
- **GPS coordinate validation:** Use `MarineTestUtils.getMarineTestAreas()` for valid test coordinates
- **Chart data errors:** Check NOAA API rate limiting and authentication
- **Offline functionality:** Ensure proper error handling for satellite connectivity loss

## Key Conventions

- **Marine Navigation Focus:**
  - Prioritize accuracy and reliability for safety-critical features
  - Follow maritime software conventions and standards
  - Consider offline usage scenarios for marine environments
  - Implement GPS integration patterns for position tracking
- **Flutter Best Practices:**
  - Use proper widget lifecycle management
  - Implement clean separation between UI and business logic
  - Follow Flutter's reactive programming patterns
  - Use appropriate state management (setState, Provider, etc.)
- **File Organization:**
  - Group related marine features together (charts, navigation, weather)
  - Separate platform-specific code when needed
  - Maintain clear boundaries between UI and data layers

---

**Remember:** NavTool is safety-critical marine navigation software. Always prioritize accuracy, reliability, and comprehensive testing over rapid development. When in doubt, consult maritime navigation standards and test thoroughly in simulated marine environments.
