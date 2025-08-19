#!/bin/bash

# Script to set up proper application icons for Linux
# This script should be run after building the application

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build/linux/arm64/debug/bundle"

echo "Setting up NavTool desktop integration..."

# Create directories for icons
mkdir -p ~/.local/share/icons/hicolor/{16x16,32x32,48x48,64x64,128x128,256x256}/apps

# For now, we'll copy the SVG to these directories
# In production, you would convert the SVG to proper PNG sizes
cp "$PROJECT_DIR/assets/icons/app_icon.svg" ~/.local/share/icons/hicolor/16x16/apps/navtool.png
cp "$PROJECT_DIR/assets/icons/app_icon.svg" ~/.local/share/icons/hicolor/32x32/apps/navtool.png
cp "$PROJECT_DIR/assets/icons/app_icon.svg" ~/.local/share/icons/hicolor/48x48/apps/navtool.png
cp "$PROJECT_DIR/assets/icons/app_icon.svg" ~/.local/share/icons/hicolor/64x64/apps/navtool.png
cp "$PROJECT_DIR/assets/icons/app_icon.svg" ~/.local/share/icons/hicolor/128x128/apps/navtool.png
cp "$PROJECT_DIR/assets/icons/app_icon.svg" ~/.local/share/icons/hicolor/256x256/apps/navtool.png

# Create desktop entry
cat > ~/.local/share/applications/navtool.desktop << EOF
[Desktop Entry]
Type=Application
Name=NavTool
Comment=Marine Navigation Tool
Icon=navtool
Exec=$BUILD_DIR/navtool
Categories=Navigation;Engineering;Science;
StartupNotify=true
StartupWMClass=navtool
EOF

# Update icon cache
if command -v gtk-update-icon-cache &> /dev/null; then
    gtk-update-icon-cache ~/.local/share/icons/hicolor
fi

echo "Desktop integration setup complete!"
echo "NavTool should now appear in your application launcher."
echo "Note: For production use, convert the SVG icon to proper PNG sizes."
