# NavTool - Work in Progress - AI Learning experiment

A comprehensive marine navigation and routing application designed for recreational and professional mariners. Built with Flutter for optimal cross-platform desktop performance.

## Overview

NavTool is a modern Electronic Chart Display and Information System (ECDIS) designed to provide mariners with advanced navigation capabilities. The application features a clean, responsive interface that adapts to different screen sizes and platforms.

## Key Features

### Navigation & Charts
- **Electronic Chart Display and Information System (ECDIS)**
### Focused Remediation Groups (Phase 2)  
- **Advanced Route Planning and Optimization**
- **Weather Routing with GRIB Data Integration**
- **Real-time GPS Position and Tracking**

### Technical Features
- **Cross-platform Desktop Support** (Windows, macOS, Linux)
- **Responsive UI** for various screen sizes
- **Material Design 3** with modern theming
- **Custom SVG icon support**
- **Version display functionality**

## Platform Support

- ✅ **Linux** (Primary development platform)
- ✅ **Windows** (Full desktop support)
- ✅ **macOS** (Full desktop support)
- ✅ **iOS** (Mobile support)

## Technical Stack

- **Framework**: Flutter 3.8.1+
### Skipped Debug / Exploratory Test Rationale
- **Language**: Dart
- **UI Components**: Material Design 3
- **Icons**: Custom SVG with flutter_svg
- **Package Info**: package_info_plus for version management

## Project Structure

```
lib/
├── app/                    # App configuration and routing
│   ├── app.dart           # Main app widget
│   └── routes.dart        # Route definitions
├── features/              # Feature-based organization
│   ├── home/              # Home screen and main interface
│   └── about/             # About screen and app information
├── widgets/               # Reusable widgets
│   ├── app_icon.dart      # Custom SVG app icon
│   ├── main_menu.dart     # Desktop menu bar
│   └── version_text.dart  # Dynamic version display
└── main.dart              # App entry point
```

## Getting Started

### Prerequisites

- Flutter SDK 3.8.1 or higher
- Dart SDK
- Platform-specific development tools:
  - **Linux**: CMake, GTK development libraries
  - **Windows**: Visual Studio with C++ support
  - **macOS**: Xcode

### Installation

1. **Clone the repository**
   ```bash
   git clone https://github.com/frye/navtool.git
   cd navtool
   ```

2. **Install dependencies**
   ```bash
   flutter pub get
   ```

3. **Run the application**
   ```bash
   # For development
   flutter run -d linux    # Linux
   flutter run -d windows  # Windows
   flutter run -d macos    # macOS
   
   # For release build
   flutter build linux
   flutter build windows
   flutter build macos
   ```

## Recent Updates

### Version 0.0.1+1 (Latest)
- ✨ **Launch screen assets** and iOS project configuration
- 🎨 **Updated app icon** with custom SVG design
- 📱 **Version display functionality** with package_info_plus integration
- 🖥️ **Windows runner support** for desktop deployment
- 🎨 **Desktop-first UI design** with VS Code-inspired menu bar
- 📱 **Responsive layout** supporting both desktop and mobile interfaces
- ⚙️ **Material Design 3** implementation with adaptive theming

### Planned Features
- [ ] Chart data loading and display
- [ ] GRIB weather data integration
- [ ] GPS integration with NMEA support
- [ ] Route planning and optimization
- [ ] Waypoint management
- [ ] Navigation instruments display

## Development

This project follows Flutter best practices with:
- **Feature-based architecture** for scalability
- **Responsive design patterns** for multi-platform support
- **Material Design 3** for modern UI/UX
- **Modular widget system** for reusability

### Testing Strategy

NavTool implements a comprehensive dual testing strategy to ensure reliability in marine environments:

#### Quick Testing Commands
```bash
# Fast development feedback (recommended for development)
./scripts/test.sh unit

# All standard tests (recommended for pre-commit)
./scripts/test.sh validate

# Real network integration tests (manual validation)
./scripts/test.sh integration

# CI/CD appropriate tests
./scripts/test.sh ci
```

#### Test Types

**Mock-Based Unit Tests** (`test/`)
- Fast execution with mocked NOAA API responses
- Comprehensive error scenario testing
- Rate limiting and performance validation
- Runs in CI/CD pipelines

**Real Network Integration Tests** (`integration_test/`)
- Tests against actual NOAA API endpoints
- Validates real data structures and marine connectivity
- Handles slow/intermittent network scenarios
- Requires real device and network connectivity

**Coverage**
- All 10 previously failing integration tests now pass
- Mock tests provide immediate development feedback
- Integration tests ensure real-world compatibility

See [TEST_STRATEGY.md](TEST_STRATEGY.md) for detailed testing documentation.

### Building for Production

```bash
# Linux
flutter build linux --release

# Windows
flutter build windows --release

# macOS
flutter build macos --release
```

## Download System Refactor (Phase 1 Complete)

The first phase of the chart download reliability overhaul has been completed. Highlights:

- Unified progress model: all progress values now normalized (0.0–1.0) across service + state notifier.
- Atomic file writes: downloads stream into `<filename>.part` then rename after optional checksum validation to avoid partial/corrupt final files.
- Pause/Resume improvements: pause captures partial size and persists resume metadata explicitly; resume continues from existing `.part` file.
- Notifier integration: `DownloadServiceImpl` pushes progress/status directly into `DownloadQueueNotifier` (auto-creates entries if not pre-queued).
- Network suitability gate stub: hook in place for future adaptive deferral (currently always allows start, with logging scaffolding).
- Persistent resume data: saved periodically during transfer and on pause for recovery.
- New tests: `test/download/download_service_phase1_test.dart` validates normalization, atomic rename, and pause persistence.

Upcoming phases will introduce segmented/ranged downloads, adaptive concurrency, richer UI feedback, integrity verification pipelines, and metrics.

## Contributing

This is a private project focused on marine navigation solutions. For questions or collaboration opportunities, please contact the project maintainer.

## License

This project is not published to pub.dev and is intended for private use.

---

**NavTool** - Professional Marine Navigation for the Modern Mariner
