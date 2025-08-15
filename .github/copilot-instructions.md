# NavTool - AI Coding Assistant Instructions

## Stack

Flutter 3.8.1+, Dart, Material Design 3, Custom SVG Icons (flutter_svg), Cross-platform Desktop (Windows, macOS, Linux, iOS).

## General guidance
- When working with issues always use GitHub MCP server to check the frye/navtool for related issues.
- Always keep the remote issue up to date with current status using MCP tools.
- When starting to work on an issue, always create a new feature branch for that work. Use descriptive name.
- When issue implementation is complete, create a pull request for review using the implementation summary as the PR description.

## Development Environment

- Use **Flutter run** for development: `flutter run -d windows` (or `-d macos`, `-d linux`)
- Hot reload enabled for rapid development iteration
- Assets pre-configured in `pubspec.yaml` for `assets/icons/` directory
- Package info integration via `package_info_plus` for version management
- IMPORTANT Always wait for the test run to complete before attempting to analyze its output. The waitn needs to happen without additional commands and user input to continue.

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

# Planning

Use todo lists to break down navigation feature development and chart integration tasks.

## Error Handling

- Use Dart's built-in exception handling with try-catch blocks
- Implement custom exception classes for marine data operations
- Console logging for development debugging
- User-friendly error messages for navigation-critical failures

# Code Style and Structure

- Write concise, idiomatic Dart code following Flutter conventions.
- Use StatelessWidget for immutable UI components, StatefulWidget for interactive components.
- Prefer composition over inheritance; use mixins where appropriate.
- Use descriptive variable names with clear intent (e.g., `isChartLoaded`, `hasGpsSignal`).
- Structure Dart files: imports, main widget class, helper methods, private methods.

# Naming Conventions

- Use snake_case for file and directory names (e.g., `home_screen.dart`, `chart_display/`).
- Use PascalCase for class names (e.g., `HomeScreen`, `ChartDisplayWidget`).
- Use camelCase for variable and method names (e.g., `chartData`, `loadNavigationData()`).
- Prefix private members with underscore (e.g., `_privateMethod()`).

# Recommended Tools

- For marine data research and navigation standards, use the `perplexity_ask` tool.
- For Flutter development guidance, reference Flutter documentation
- Use `semantic_search` for finding existing navigation-related code patterns

# UI and Styling

- Use Material Design 3 widgets from Flutter's material library
- Implement custom SVG icons using `flutter_svg` package for marine symbols
- Use `MediaQuery` and `LayoutBuilder` for responsive layouts
- Apply marine navigation UI principles:
  - High contrast for outdoor visibility
  - Large touch targets for use with gloves
  - Clear visual hierarchy for critical navigation data
  - Consistent with maritime software conventions

# Syntax and Formatting

- Follow Dart formatting guidelines with `dart format`
- Use const constructors where possible for performance
- Prefer named parameters for widget constructors
- Use trailing commas for better formatting and diffs

# Performance Optimization

- Use `const` widgets to reduce rebuilds
- Implement proper `Key` usage for widget identity
- Use `ListView.builder` for large datasets (chart lists, waypoints)
- Optimize chart rendering with efficient data structures
- Consider memory management for large nautical chart data

# Key Conventions

- Marine Navigation Focus:
  - Prioritize accuracy and reliability for safety-critical features
  - Follow maritime software conventions and standards
  - Consider offline usage scenarios for marine environments
  - Implement GPS integration patterns for position tracking
- Flutter Best Practices:
  - Use proper widget lifecycle management
  - Implement clean separation between UI and business logic
  - Follow Flutter's reactive programming patterns
  - Use appropriate state management (setState, Provider, etc.)
- File Organization:
  - Group related marine features together (charts, navigation, weather)
  - Separate platform-specific code when needed
  - Maintain clear boundaries between UI and data layers
