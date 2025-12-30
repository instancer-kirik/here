#!/bin/bash

# Install script for here fish shell completions
# This script installs the fish shell autocompletion for the 'here' package manager

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if fish is installed
if ! command -v fish &> /dev/null; then
    print_error "Fish shell is not installed. Please install fish first."
    print_info "On Arch Linux: sudo pacman -S fish"
    print_info "On Ubuntu/Debian: sudo apt install fish"
    print_info "On CentOS/RHEL: sudo dnf install fish"
    exit 1
fi

print_info "Fish shell found: $(command -v fish)"

# Get the fish completions directory
FISH_COMPLETIONS_DIR="$HOME/.config/fish/completions"

# Create the fish completions directory if it doesn't exist
if [ ! -d "$FISH_COMPLETIONS_DIR" ]; then
    print_info "Creating fish completions directory: $FISH_COMPLETIONS_DIR"
    mkdir -p "$FISH_COMPLETIONS_DIR"
fi

# Get the script directory (where this script is located)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPLETIONS_SOURCE="$SCRIPT_DIR/completions/here.fish"

# Check if the completions file exists
if [ ! -f "$COMPLETIONS_SOURCE" ]; then
    print_error "Completions file not found at: $COMPLETIONS_SOURCE"
    print_info "Make sure you're running this script from the here project root directory"
    exit 1
fi

# Copy the completions file
COMPLETIONS_DEST="$FISH_COMPLETIONS_DIR/here.fish"
print_info "Installing completions to: $COMPLETIONS_DEST"

cp "$COMPLETIONS_SOURCE" "$COMPLETIONS_DEST"

if [ $? -eq 0 ]; then
    print_success "Fish completions installed successfully!"
else
    print_error "Failed to install completions"
    exit 1
fi

# Check if here binary is available
if command -v here &> /dev/null; then
    print_success "here binary found: $(command -v here)"
    print_info "Completions should work immediately in new fish sessions"
else
    print_warning "here binary not found in PATH"
    print_info "Make sure to install the here binary first with: zig build"
    print_info "And create a symlink: ln -sf $(pwd)/zig-out/bin/here ~/.local/bin/here"
fi

print_info ""
print_info "🐟 Fish shell completions installed!"
print_info ""
print_info "To use completions:"
print_info "1. Start a new fish shell session or run: exec fish"
print_info "2. Type 'here ' and press TAB to see available commands"
print_info "3. Type 'here import --' and press TAB to see import options"
print_info ""
print_info "Available completions:"
print_info "• Commands: install, search, remove, update, list, info, export, import, backup, version, help"
print_info "• Export options: --include-config"
print_info "• Import options: --interactive, --install-native, --install-flatpak, --install-appimage, --install-all"
print_info "• File completions for .json profiles"
print_info "• Package name completions (from system package manager)"
print_info ""
print_success "Setup complete! Happy package managing! 🏠"
