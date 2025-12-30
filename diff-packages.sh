#!/bin/bash

# Script to compare final-profile-with-config.json vs current-system.json
# Shows what packages are missing from current system

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FINAL_PROFILE="$SCRIPT_DIR/final-profile-with-config.json"
CURRENT_SYSTEM="$SCRIPT_DIR/current-system.json"

if [[ ! -f "$FINAL_PROFILE" ]]; then
    echo "❌ Error: final-profile-with-config.json not found"
    exit 1
fi

if [[ ! -f "$CURRENT_SYSTEM" ]]; then
    echo "❌ Error: current-system.json not found"
    exit 1
fi

echo "🔍 Package Diff Analysis"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo

# Extract native packages from both files
echo "📦 Extracting package lists..."
jq -r '.packages.native[]' "$FINAL_PROFILE" | sort > /tmp/final_native.txt
jq -r '.packages.native[]' "$CURRENT_SYSTEM" | sort > /tmp/current_native.txt

# Find missing packages
echo "🔍 Finding missing packages..."
MISSING_COUNT=$(comm -23 /tmp/final_native.txt /tmp/current_native.txt | wc -l)
EXTRA_COUNT=$(comm -13 /tmp/final_native.txt /tmp/current_native.txt | wc -l)

echo "📊 Summary:"
echo "  • Missing packages: $MISSING_COUNT"
echo "  • Extra packages: $EXTRA_COUNT"
echo

if [[ $MISSING_COUNT -gt 0 ]]; then
    echo "❌ Missing packages (in final profile but not current):"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # Categorize missing packages
    echo
    echo "🎧 Bluetooth/Audio packages:"
    comm -23 /tmp/final_native.txt /tmp/current_native.txt | grep -E "(blue|audio|sound|pulse|jack|alsa)" || echo "  None"

    echo
    echo "💻 Development tools:"
    comm -23 /tmp/final_native.txt /tmp/current_native.txt | grep -E "(nodejs|npm|python|elixir|go|rust|zig|java|kotlin|ruby|php|lua)" || echo "  None"

    echo
    echo "🖥️ Desktop Environment packages:"
    comm -23 /tmp/final_native.txt /tmp/current_native.txt | grep -E "(xfce|gnome|kde|cosmic|awesome|cinnamon)" || echo "  None"

    echo
    echo "🏢 Applications:"
    comm -23 /tmp/final_native.txt /tmp/current_native.txt | grep -E "(firefox|chrome|code|discord|spotify|obs|gimp|vlc|libreoffice)" || echo "  None"

    echo
    echo "📝 All missing packages:"
    comm -23 /tmp/final_native.txt /tmp/current_native.txt | sed 's/^/  • /'
fi

if [[ $EXTRA_COUNT -gt 0 ]]; then
    echo
    echo "➕ Extra packages (in current but not final profile):"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    comm -13 /tmp/final_native.txt /tmp/current_native.txt | sed 's/^/  • /'
fi

echo
echo "🛠️ Flatpak comparison:"
jq -r '.packages.flatpak[]' "$FINAL_PROFILE" | sort > /tmp/final_flatpak.txt 2>/dev/null || touch /tmp/final_flatpak.txt
jq -r '.packages.flatpak[]' "$CURRENT_SYSTEM" | sort > /tmp/current_flatpak.txt 2>/dev/null || touch /tmp/current_flatpak.txt

MISSING_FLATPAK=$(comm -23 /tmp/final_flatpak.txt /tmp/current_flatpak.txt | wc -l)
if [[ $MISSING_FLATPAK -gt 0 ]]; then
    echo "❌ Missing Flatpak packages:"
    comm -23 /tmp/final_flatpak.txt /tmp/current_flatpak.txt | sed 's/^/  • /'
else
    echo "✅ All Flatpak packages present"
fi

echo
echo "🎯 AppImage comparison:"
jq -r '.packages.appimage[]' "$FINAL_PROFILE" | sort > /tmp/final_appimage.txt 2>/dev/null || touch /tmp/final_appimage.txt
jq -r '.packages.appimage[]' "$CURRENT_SYSTEM" | sort > /tmp/current_appimage.txt 2>/dev/null || touch /tmp/current_appimage.txt

MISSING_APPIMAGE=$(comm -23 /tmp/final_appimage.txt /tmp/current_appimage.txt | wc -l)
if [[ $MISSING_APPIMAGE -gt 0 ]]; then
    echo "❌ Missing AppImage packages:"
    comm -23 /tmp/final_appimage.txt /tmp/current_appimage.txt | sed 's/^/  • /'
else
    echo "✅ All AppImage packages present"
fi

echo
echo "💡 Quick install commands:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Generate install commands for priority packages
echo
echo "🎧 Fix Bluetooth (Priority #1):"
BLUETOOTH_PACKAGES=$(comm -23 /tmp/final_native.txt /tmp/current_native.txt | grep -E "(blueberry|bluetui|pipewire-jack)" | tr '\n' ' ')
if [[ -n "$BLUETOOTH_PACKAGES" ]]; then
    echo "  yay -S $BLUETOOTH_PACKAGES"
else
    echo "  ✅ Bluetooth packages already installed"
fi

echo
echo "💻 Development tools:"
DEV_PACKAGES=$(comm -23 /tmp/final_native.txt /tmp/current_native.txt | grep -E "(nodejs|npm|python-poetry|python-pipx|elixir|go)" | tr '\n' ' ')
if [[ -n "$DEV_PACKAGES" ]]; then
    echo "  yay -S $DEV_PACKAGES"
else
    echo "  ✅ Main dev tools already installed"
fi

echo
echo "🖥️ Desktop Environment:"
XFCE_PACKAGES=$(comm -23 /tmp/final_native.txt /tmp/current_native.txt | grep -E "xfce4-" | tr '\n' ' ')
if [[ -n "$XFCE_PACKAGES" ]]; then
    echo "  yay -S $XFCE_PACKAGES"
else
    echo "  ✅ XFCE packages already installed"
fi

# Cleanup temp files
rm -f /tmp/final_native.txt /tmp/current_native.txt
rm -f /tmp/final_flatpak.txt /tmp/current_flatpak.txt
rm -f /tmp/final_appimage.txt /tmp/current_appimage.txt

echo
echo "🏁 Analysis complete!"
echo "💡 Run this script with output to file: ./diff-packages.sh > package_diff.txt"
