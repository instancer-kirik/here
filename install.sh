#!/bin/bash

# here - Universal Package Manager Installation Script
# https://instance.select/here

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
REPO="instancer-kirik/here"
INSTALL_DIR="/usr/local/bin"
TMP_DIR="/tmp/here-install"

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

# Detect system architecture and OS
detect_platform() {
    local os
    local arch

    case "$(uname -s)" in
        Linux*)     os="linux";;
        Darwin*)    os="macos";;
        *)          print_error "Unsupported operating system: $(uname -s)";;
    esac

    case "$(uname -m)" in
        x86_64|amd64)   arch="x86_64";;
        aarch64|arm64)  arch="aarch64";;
        *)              print_error "Unsupported architecture: $(uname -m)";;
    esac

    echo "${arch}-${os}"
}

# Check if curl or wget is available
check_downloader() {
    if command -v curl >/dev/null 2>&1; then
        DOWNLOADER="curl"
    elif command -v wget >/dev/null 2>&1; then
        DOWNLOADER="wget"
    else
        print_error "Neither curl nor wget found. Please install one of them."
    fi
}

# Download file
download_file() {
    local url="$1"
    local output="$2"

    print_info "Downloading from: $url"

    case "$DOWNLOADER" in
        curl)
            curl -fsSL "$url" -o "$output" || print_error "Failed to download file"
            ;;
        wget)
            wget -q "$url" -O "$output" || print_error "Failed to download file"
            ;;
    esac
}

# Check if running as root for system installation
check_permissions() {
    if [[ "$INSTALL_DIR" == "/usr/local/bin" ]] && [[ $EUID -ne 0 ]]; then
        print_warning "Installing to $INSTALL_DIR requires root privileges"
        print_info "Re-running with sudo..."
        exec sudo "$0" "$@"
    fi
}

# Get latest release version
get_latest_version() {
    local api_url="https://api.github.com/repos/$REPO/releases/latest"

    if command -v curl >/dev/null 2>&1; then
        curl -s "$api_url" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/'
    elif command -v wget >/dev/null 2>&1; then
        wget -qO- "$api_url" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/'
    else
        echo "v1.0.0"  # Fallback version
    fi
}

# Main installation function
install_here() {
    local platform
    local version
    local binary_name
    local download_url

    print_info "🏠 Installing here - Universal Package Manager"
    echo

    # Detect platform
    platform=$(detect_platform)
    print_info "Detected platform: $platform"

    # Check for downloader
    check_downloader
    print_info "Using downloader: $DOWNLOADER"

    # Check permissions
    check_permissions "$@"

    # Get latest version
    version=$(get_latest_version)
    print_info "Latest version: $version"

    # Setup download
    binary_name="here-${platform}"
    download_url="https://github.com/$REPO/releases/download/$version/$binary_name"

    # Create temporary directory
    mkdir -p "$TMP_DIR"
    cd "$TMP_DIR"

    # Download binary
    print_info "Downloading here binary..."
    download_file "$download_url" "here"

    # Make executable
    chmod +x "here"

    # Verify the binary works
    print_info "Verifying installation..."
    if ! ./here version >/dev/null 2>&1; then
        print_error "Downloaded binary is not working correctly"
    fi

    # Install binary
    print_info "Installing to $INSTALL_DIR..."
    mv "here" "$INSTALL_DIR/here"

    # Cleanup
    cd /
    rm -rf "$TMP_DIR"

    # Success message
    echo
    print_success "here has been successfully installed to $INSTALL_DIR/here"
    print_info "Run 'here help' to get started"

    # Show version
    echo
    "$INSTALL_DIR/here" version

    # Support message
    echo
    print_info "💖 If here saves you time, consider supporting development:"
    print_info "   ETH/Base: 0xaf462cef9e8913a9cb7b6f0ba0ddf5d733eae57a"
}

# Uninstall function
uninstall_here() {
    print_info "🗑️  Uninstalling here..."

    if [[ -f "$INSTALL_DIR/here" ]]; then
        # Check permissions
        if [[ "$INSTALL_DIR" == "/usr/local/bin" ]] && [[ $EUID -ne 0 ]]; then
            print_warning "Uninstalling from $INSTALL_DIR requires root privileges"
            exec sudo "$0" uninstall
        fi

        rm "$INSTALL_DIR/here"
        print_success "here has been uninstalled from $INSTALL_DIR"
    else
        print_warning "here is not installed in $INSTALL_DIR"
    fi
}

# Show usage
show_usage() {
    cat << EOF
🏠 here Installation Script

Usage:
    $0 [command]

Commands:
    install     Install here (default)
    uninstall   Uninstall here
    help        Show this help message

Options:
    --dir DIR   Install to custom directory (default: /usr/local/bin)

Examples:
    $0                          # Install here
    $0 install                  # Install here
    $0 --dir ~/.local/bin       # Install to custom directory
    $0 uninstall                # Uninstall here

For more information, visit: https://instance.select/here

💖 Support development:
    ETH/Base: 0xaf462cef9e8913a9cb7b6f0ba0ddf5d733eae57a
EOF
}

# Parse command line arguments
main() {
    local command="install"

    while [[ $# -gt 0 ]]; do
        case $1 in
            install)
                command="install"
                shift
                ;;
            uninstall)
                command="uninstall"
                shift
                ;;
            help|--help|-h)
                show_usage
                exit 0
                ;;
            --dir)
                INSTALL_DIR="$2"
                shift 2
                ;;
            *)
                print_error "Unknown option: $1"
                ;;
        esac
    done

    case "$command" in
        install)
            install_here "$@"
            ;;
        uninstall)
            uninstall_here
            ;;
        *)
            show_usage
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
