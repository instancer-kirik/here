#!/bin/bash

# here - AppImage Build Script
# Creates a portable AppImage for universal distribution

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
APP_NAME="here"
APP_VERSION="1.1.0"
ARCH="x86_64"
BUILD_DIR="appimage-build"
APPDIR="$BUILD_DIR/$APP_NAME.AppDir"

# Helper functions
print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
    exit 1
}

# Check dependencies
check_dependencies() {
    print_info "Checking dependencies..."

    if ! command -v zig >/dev/null 2>&1; then
        print_error "Zig compiler not found. Please install Zig."
    fi

    if ! command -v wget >/dev/null 2>&1 && ! command -v curl >/dev/null 2>&1; then
        print_error "Neither wget nor curl found. Please install one of them."
    fi

    print_success "Dependencies check passed"
}

# Download AppImageTool
download_appimagetool() {
    print_info "Downloading AppImageTool..."

    local tool_url="https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-${ARCH}.AppImage"
    local tool_path="$BUILD_DIR/appimagetool"

    mkdir -p "$BUILD_DIR"

    if command -v wget >/dev/null 2>&1; then
        wget -q "$tool_url" -O "$tool_path" || print_error "Failed to download AppImageTool"
    else
        curl -fsSL "$tool_url" -o "$tool_path" || print_error "Failed to download AppImageTool"
    fi

    chmod +x "$tool_path"
    print_success "AppImageTool downloaded"
}

# Build the binary
build_binary() {
    print_info "Building optimized binary..."

    zig build -Doptimize=ReleaseFast -Dtarget=${ARCH}-linux || print_error "Failed to build binary"

    if [[ ! -f "zig-out/release/${ARCH}-linux/here" ]]; then
        print_error "Binary not found after build"
    fi

    print_success "Binary built successfully"
}

# Create AppDir structure
create_appdir() {
    print_info "Creating AppDir structure..."

    # Clean and create AppDir
    rm -rf "$APPDIR"
    mkdir -p "$APPDIR"

    # Create standard directories
    mkdir -p "$APPDIR/usr/bin"
    mkdir -p "$APPDIR/usr/share/applications"
    mkdir -p "$APPDIR/usr/share/icons/hicolor/256x256/apps"
    mkdir -p "$APPDIR/usr/share/doc/$APP_NAME"

    print_success "AppDir structure created"
}

# Copy binary and resources
install_files() {
    print_info "Installing files to AppDir..."

    # Copy main binary
    cp "zig-out/release/${ARCH}-linux/here" "$APPDIR/usr/bin/" || print_error "Failed to copy binary"
    chmod +x "$APPDIR/usr/bin/here"

    # Create desktop file
    cat > "$APPDIR/usr/share/applications/$APP_NAME.desktop" << EOF
[Desktop Entry]
Type=Application
Name=here
Comment=Universal package manager with system recovery and migration
Exec=here
Icon=here
Terminal=true
Categories=System;PackageManager;Utility;
Keywords=package;manager;install;search;update;
StartupNotify=false
NoDisplay=false
EOF

    # Create a simple icon (text-based for now)
    cat > "$APPDIR/usr/share/icons/hicolor/256x256/apps/here.svg" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<svg width="256" height="256" viewBox="0 0 256 256" xmlns="http://www.w3.org/2000/svg">
  <rect width="256" height="256" fill="#2563eb" rx="24"/>
  <text x="128" y="140" font-family="monospace" font-size="72" font-weight="bold"
        text-anchor="middle" fill="white">🏠</text>
  <text x="128" y="180" font-family="monospace" font-size="24"
        text-anchor="middle" fill="#93c5fd">here</text>
  <text x="128" y="205" font-family="monospace" font-size="14"
        text-anchor="middle" fill="#cbd5e1">pkg manager</text>
</svg>
EOF

    # Copy documentation
    cp README.md "$APPDIR/usr/share/doc/$APP_NAME/" 2>/dev/null || echo "# here" > "$APPDIR/usr/share/doc/$APP_NAME/README.md"
    cp LICENSE "$APPDIR/usr/share/doc/$APP_NAME/" 2>/dev/null || echo "MIT License" > "$APPDIR/usr/share/doc/$APP_NAME/LICENSE"
    cp CHANGELOG.md "$APPDIR/usr/share/doc/$APP_NAME/" 2>/dev/null || echo "# Changelog" > "$APPDIR/usr/share/doc/$APP_NAME/CHANGELOG.md"

    # Create AppRun script (entry point)
    cat > "$APPDIR/AppRun" << 'EOF'
#!/bin/bash

# AppRun script for here AppImage
# This script is executed when the AppImage is run

# Get the directory where this AppImage is located
HERE="$(dirname "$(readlink -f "${0}")")"

# Set up environment
export PATH="${HERE}/usr/bin:${PATH}"

# If no arguments, show help
if [ $# -eq 0 ]; then
    exec "${HERE}/usr/bin/here" help
else
    # Pass all arguments to here
    exec "${HERE}/usr/bin/here" "$@"
fi
EOF

    chmod +x "$APPDIR/AppRun"

    # Create desktop file in root (required for AppImage)
    cp "$APPDIR/usr/share/applications/$APP_NAME.desktop" "$APPDIR/"

    # Create icon symlink in root (required for AppImage)
    ln -sf "usr/share/icons/hicolor/256x256/apps/here.svg" "$APPDIR/here.svg"

    print_success "Files installed to AppDir"
}

# Build the AppImage
build_appimage() {
    print_info "Building AppImage..."

    local output_name="${APP_NAME}-${APP_VERSION}-${ARCH}.AppImage"

    # Set environment variable to disable desktop integration prompts
    export APPIMAGE_EXTRACT_AND_RUN=1

    # Build AppImage
    ARCH="$ARCH" "$BUILD_DIR/appimagetool" "$APPDIR" "$BUILD_DIR/$output_name" || print_error "Failed to build AppImage"

    # Make it executable
    chmod +x "$BUILD_DIR/$output_name"

    # Move to root directory for easy access
    mv "$BUILD_DIR/$output_name" "./"

    print_success "AppImage built: $output_name"
}

# Test the AppImage
test_appimage() {
    local appimage_name="${APP_NAME}-${APP_VERSION}-${ARCH}.AppImage"

    print_info "Testing AppImage..."

    # Test version command
    if ! "./$appimage_name" version >/dev/null 2>&1; then
        print_error "AppImage test failed"
    fi

    # Show info about the AppImage
    print_success "AppImage test passed"

    echo
    print_info "AppImage details:"
    echo "  📦 File: $appimage_name"
    echo "  📊 Size: $(du -h "$appimage_name" | cut -f1)"
    echo "  🎯 Architecture: $ARCH"
    echo "  📋 Version: $APP_VERSION"

    echo
    print_info "Usage examples:"
    echo "  ./$appimage_name version"
    echo "  ./$appimage_name search firefox"
    echo "  ./$appimage_name install nodejs"
    echo "  ./$appimage_name help"
}

# Cleanup function
cleanup() {
    print_info "Cleaning up build artifacts..."
    rm -rf "$BUILD_DIR"
    print_success "Cleanup complete"
}

# Show usage information
show_usage() {
    cat << EOF
🏠 here AppImage Build Script

Usage:
    $0 [options]

Options:
    --arch ARCH     Target architecture (default: x86_64)
    --version VER   Application version (default: $APP_VERSION)
    --clean         Clean build artifacts only
    --help          Show this help message

Examples:
    $0                          # Build AppImage for x86_64
    $0 --arch aarch64           # Build for ARM64
    $0 --version 1.2.0          # Build specific version
    $0 --clean                  # Clean build artifacts

The resulting AppImage will be self-contained and portable.
EOF
}

# Main build process
main() {
    local clean_only=false

    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --arch)
                ARCH="$2"
                shift 2
                ;;
            --version)
                APP_VERSION="$2"
                shift 2
                ;;
            --clean)
                clean_only=true
                shift
                ;;
            --help|-h)
                show_usage
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                ;;
        esac
    done

    # Handle clean-only mode
    if [[ "$clean_only" == "true" ]]; then
        cleanup
        exit 0
    fi

    # Main build process
    print_info "🏠 Building here AppImage v$APP_VERSION for $ARCH"
    echo

    check_dependencies
    download_appimagetool
    build_binary
    create_appdir
    install_files
    build_appimage
    test_appimage

    echo
    print_success "🎉 AppImage build complete!"
    print_info "Run './here-${APP_VERSION}-${ARCH}.AppImage --help' to test"

    echo
    print_info "💖 Support development: ETH/Base 0xaf462cef9e8913a9cb7b6f0ba0ddf5d733eae57a"
}

# Handle script interruption
trap cleanup EXIT

# Run main function
main "$@"
