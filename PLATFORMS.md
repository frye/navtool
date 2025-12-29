# IMPORTANT: Native Applications Only

This project is designed for **native desktop and mobile applications only**.

## Supported Platforms

- ✅ Windows (`flutter run -d windows`)
- ✅ macOS (`flutter run -d macos`)
- ✅ Linux (`flutter run -d linux`)
- ✅ Android (`flutter run -d android`)
- ✅ iOS (`flutter run -d ios`)

## Explicitly NOT Supported

- ❌ Web (`flutter run -d chrome`)
- ❌ Web Server (`flutter run -d web-server`)
- ❌ Edge browser
- ❌ Any browser-based execution

## Development Commands

```bash
# Windows
flutter run -d windows

# macOS
flutter run -d macos

# Linux
flutter run -d linux

# Android (requires device/emulator)
flutter run -d android

# iOS (requires macOS with Xcode)
flutter run -d ios
```

## Why Native Only?

1. **Performance**: Native rendering provides better performance for chart display
2. **File Access**: Direct file system access for chart data
3. **GPS Integration**: Future GPS features require native platform access
4. **Offline Capability**: Native apps work fully offline

## Disabling Web Support

Web support has been explicitly disabled in this project. If Flutter suggests web options, always choose a native platform instead.
