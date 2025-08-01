# NavTool - Work in Progress - Learning experiment

A comprehensive marine navigation and routing application designed for recreational and professional mariners. Built with Flutter for optimal cross-platform desktop performance.

## Overview

NavTool is a modern Electronic Chart Display and Information System (ECDIS) designed to provide mariners with advanced navigation capabilities. The application features a clean, responsive interface that adapts to different screen sizes and platforms.

## Key Features

### Navigation & Charts
- **Electronic Chart Display and Information System (ECDIS)**
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

### Building for Production

```bash
# Linux
flutter build linux --release

# Windows
flutter build windows --release

# macOS
flutter build macos --release
```

## Contributing

This is a private project focused on marine navigation solutions. For questions or collaboration opportunities, please contact the project maintainer.

## License

This project is not published to pub.dev and is intended for private use.

---

**NavTool** - Professional Marine Navigation for the Modern Mariner
