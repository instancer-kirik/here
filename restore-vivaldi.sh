#!/bin/bash

# 🏠 here - Vivaldi Browser Data Restoration Script
# Restore bookmarks and help with extension restoration from backup

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
BACKUP_PATH="/run/media/bon/MainStorage/MAIN_SWAP/home-backup"
VIVALDI_CONFIG="$HOME/.config/vivaldi"
VIVALDI_PROFILE="$HOME/.config/vivaldi/Profile 1"
CACHY_BACKUP="$BACKUP_PATH/.cachy/5aa1tbhk.default-release"
TEMP_DIR="/tmp/vivaldi-restore-$$"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

log() {
    echo -e "${GREEN}[$(date +'%H:%M:%S')]${NC} $*"
}

warn() {
    echo -e "${YELLOW}⚠️  [$(date +'%H:%M:%S')]${NC} $*"
}

error() {
    echo -e "${RED}❌ [$(date +'%H:%M:%S')]${NC} $*"
}

info() {
    echo -e "${BLUE}ℹ️  [$(date +'%H:%M:%S')]${NC} $*"
}

success() {
    echo -e "${GREEN}✅ [$(date +'%H:%M:%S')]${NC} $*"
}

# Check if backup exists
check_backup() {
    if [[ ! -d "$BACKUP_PATH" ]]; then
        error "Backup directory not found at: $BACKUP_PATH"
        error "Please mount your backup drive first!"
        exit 1
    fi

    if [[ ! -d "$CACHY_BACKUP" ]]; then
        error "Cachy Browser backup not found at: $CACHY_BACKUP"
        exit 1
    fi

    log "✅ Backup found at: $BACKUP_PATH"
}

# Check if Vivaldi is running
check_vivaldi_running() {
    if pgrep -x "vivaldi" > /dev/null; then
        error "Vivaldi is currently running!"
        error "Please close Vivaldi completely before running this script."
        info "💡 Use: killall vivaldi"
        exit 1
    fi
}

# Create backup of current Vivaldi profile
backup_current_profile() {
    log "Creating backup of current Vivaldi profile..."

    if [[ -d "$VIVALDI_PROFILE" ]]; then
        local backup_dir="$HOME/.vivaldi-backup-$TIMESTAMP"
        cp -r "$VIVALDI_CONFIG" "$backup_dir"
        success "Current profile backed up to: $backup_dir"
    else
        warn "No existing Vivaldi profile found - this might be a fresh installation"
    fi
}

# Create temporary working directory
setup_temp_dir() {
    mkdir -p "$TEMP_DIR"
    log "Created temporary directory: $TEMP_DIR"
}

# Extract Firefox bookmarks
extract_bookmarks() {
    log "Extracting bookmarks from Cachy Browser backup..."

    # Check for bookmark backup files
    local bookmark_backup="$CACHY_BACKUP/bookmarkbackups"
    if [[ -d "$bookmark_backup" ]]; then
        local latest_backup=$(ls -t "$bookmark_backup"/*.jsonlz4 2>/dev/null | head -1)
        if [[ -f "$latest_backup" ]]; then
            info "Found bookmark backup: $(basename "$latest_backup")"

            # Try to decompress the bookmark file using python
            if command -v python3 > /dev/null; then
                cat > "$TEMP_DIR/decompress_bookmarks.py" << 'EOF'
import lz4.frame
import sys
import json

def decompress_mozilla_lz4(file_path, output_path):
    with open(file_path, 'rb') as f:
        # Skip the first 8 bytes (Mozilla's LZ4 header)
        f.seek(8)
        compressed_data = f.read()

    try:
        decompressed = lz4.frame.decompress(compressed_data)
        with open(output_path, 'wb') as out:
            out.write(decompressed)
        return True
    except Exception as e:
        print(f"Error: {e}")
        return False

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python3 decompress_bookmarks.py input.jsonlz4 output.json")
        sys.exit(1)

    success = decompress_mozilla_lz4(sys.argv[1], sys.argv[2])
    if success:
        print("Successfully decompressed bookmarks")
    else:
        print("Failed to decompress bookmarks")
        sys.exit(1)
EOF

                # Install lz4 if needed
                if ! python3 -c "import lz4.frame" 2>/dev/null; then
                    info "Installing required Python LZ4 library..."
                    pip3 install --user lz4 || warn "Could not install lz4 library"
                fi

                # Decompress bookmarks
                python3 "$TEMP_DIR/decompress_bookmarks.py" "$latest_backup" "$TEMP_DIR/bookmarks.json" 2>/dev/null || {
                    warn "Could not decompress Firefox bookmarks automatically"
                    warn "You'll need to import bookmarks manually from Vivaldi's import menu"
                    return 1
                }

                success "Bookmarks extracted to: $TEMP_DIR/bookmarks.json"
                return 0
            else
                warn "Python3 not found - cannot extract compressed bookmarks"
                return 1
            fi
        fi
    fi

    warn "No bookmark backups found"
    return 1
}

# List extensions from backup
list_extensions() {
    log "Analyzing extensions from Cachy Browser backup..."

    local extensions_file="$CACHY_BACKUP/extensions.json"
    local addons_file="$CACHY_BACKUP/addons.json"

    if [[ -f "$addons_file" ]]; then
        info "🧩 Extensions found in backup:"
        echo ""

        # Parse addons.json to show installed extensions
        if command -v jq > /dev/null; then
            jq -r '.addons[] | select(.type == "extension" and .active == true) | "  • \(.name) v\(.version) - \(.description // "No description")"' "$addons_file" 2>/dev/null || {
                warn "Could not parse extensions with jq, showing raw file location"
                info "Extensions file location: $addons_file"
            }
        else
            # Fallback without jq
            grep -o '"name":"[^"]*"' "$addons_file" | sed 's/"name":"\([^"]*\)"/  • \1/' | sort -u || {
                info "Extensions file location: $addons_file"
                warn "Install 'jq' for better extension parsing"
            }
        fi
        echo ""
    else
        warn "No extensions file found in backup"
    fi
}

# Import bookmarks to Vivaldi
import_bookmarks() {
    if [[ -f "$TEMP_DIR/bookmarks.json" ]]; then
        log "Converting Firefox bookmarks to Vivaldi format..."

        # Create a simple HTML bookmarks file that Vivaldi can import
        cat > "$TEMP_DIR/bookmarks.html" << 'EOF'
<!DOCTYPE NETSCAPE-Bookmark-file-1>
<!-- This is an automatically generated file.
     It will be read and overwritten.
     DO NOT EDIT! -->
<META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">
<TITLE>Bookmarks</TITLE>
<H1>Bookmarks</H1>
<DT><H3>Imported Bookmarks</H3>
<DL><p>
EOF

        # Simple extraction of URLs and titles (basic approach)
        if command -v jq > /dev/null; then
            jq -r '.children[]? | objects | select(.type=="text/x-moz-place") | "<DT><A HREF=\"\(.uri)\">\(.title // .uri)</A>"' "$TEMP_DIR/bookmarks.json" >> "$TEMP_DIR/bookmarks.html" 2>/dev/null || {
                warn "Could not convert bookmarks format"
            }
        fi

        echo "</DL><p>" >> "$TEMP_DIR/bookmarks.html"

        success "Bookmark HTML file created at: $TEMP_DIR/bookmarks.html"
        info "You can import this file manually in Vivaldi:"
        info "  Vivaldi Menu → Bookmarks → Import Bookmarks and Settings"
        info "  Choose 'Bookmarks HTML File' and select: $TEMP_DIR/bookmarks.html"
    fi
}

# Create extension installation guide
create_extension_guide() {
    log "Creating extension installation guide..."

    cat > "$TEMP_DIR/extension-guide.md" << 'EOF'
# 🧩 Vivaldi Extension Restoration Guide

## How to Install Extensions

### Method 1: Chrome Web Store (Recommended)
1. Open Vivaldi
2. Go to Settings → Extensions (or type `vivaldi://extensions/`)
3. Enable "Developer mode" (toggle in top right)
4. Visit the Chrome Web Store: https://chrome.google.com/webstore
5. Search for and install your extensions

### Method 2: Manual Installation
1. Download .crx files from extension developers
2. Go to `vivaldi://extensions/`
3. Enable "Developer mode"
4. Drag and drop the .crx file onto the page

### Common Extensions to Consider:
- **uBlock Origin** - Ad blocker
- **Bitwarden** - Password manager
- **Dark Reader** - Dark mode for websites
- **Honey** - Coupon finder
- **LastPass** - Password manager
- **Grammarly** - Writing assistant
- **OneTab** - Tab manager
- **Privacy Badger** - Privacy protection
- **Decentraleyes** - Privacy protection
- **ClearURLs** - Remove tracking parameters

### Vivaldi Built-in Features
Before installing extensions, check if Vivaldi has built-in alternatives:
- **Ad Blocker**: Built-in (Settings → Privacy → Tracker and Ad Blocker)
- **Tab Management**: Advanced tab stacking, workspaces
- **Note Taking**: Built-in notes panel
- **Screenshot Tool**: Built-in capture tools
- **Translation**: Built-in translation
- **Reader Mode**: Built-in reader view

## Next Steps
1. Import your bookmarks using the HTML file
2. Install essential extensions
3. Configure Vivaldi settings to match your preferences
4. Set up sync if desired (Vivaldi Account)
EOF

    success "Extension guide created at: $TEMP_DIR/extension-guide.md"
}

# Show restoration summary
show_summary() {
    echo ""
    log "🎉 Vivaldi Restoration Summary"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    info "✅ Current Vivaldi profile backed up"

    if [[ -f "$TEMP_DIR/bookmarks.html" ]]; then
        info "✅ Bookmarks extracted and ready for import"
        info "   📁 Location: $TEMP_DIR/bookmarks.html"
    else
        warn "⚠️  Could not extract bookmarks automatically"
        info "   📄 Manual bookmark file: $CACHY_BACKUP/bookmarkbackups/"
    fi

    info "✅ Extension restoration guide created"
    info "   📄 Guide: $TEMP_DIR/extension-guide.md"

    echo ""
    info "🔧 Next Steps:"
    echo "  1. Start Vivaldi"
    echo "  2. Import bookmarks: Vivaldi Menu → Bookmarks → Import Bookmarks and Settings"
    if [[ -f "$TEMP_DIR/bookmarks.html" ]]; then
        echo "     Choose 'Bookmarks HTML File' and select: $TEMP_DIR/bookmarks.html"
    else
        echo "     Choose 'Firefox' and select the backup profile directory"
    fi
    echo "  3. Install extensions from Chrome Web Store (see guide)"
    echo "  4. Configure Vivaldi settings to your preference"
    echo ""

    info "📚 Useful Resources:"
    echo "  • Extension Guide: $TEMP_DIR/extension-guide.md"
    echo "  • Chrome Web Store: https://chrome.google.com/webstore"
    echo "  • Vivaldi Extensions: vivaldi://extensions/"
    echo "  • Vivaldi Settings: vivaldi://settings/"
    echo ""

    success "Restoration preparation complete! 🚀"
}

# Cleanup function
cleanup() {
    if [[ -d "$TEMP_DIR" ]]; then
        read -p "Remove temporary files? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rm -rf "$TEMP_DIR"
            log "Temporary files cleaned up"
        else
            info "Temporary files preserved at: $TEMP_DIR"
        fi
    fi
}

# Main restoration process
main() {
    log "🏠 here - Starting Vivaldi restoration from backup"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    check_backup
    check_vivaldi_running
    backup_current_profile
    setup_temp_dir

    # Extract and process data
    extract_bookmarks
    import_bookmarks
    list_extensions
    create_extension_guide

    show_summary

    # Cleanup
    trap cleanup EXIT
}

# Handle command line arguments
case "${1:-}" in
    -h|--help)
        echo "🏠 here - Vivaldi Browser Data Restoration Script"
        echo ""
        echo "Usage: $0 [options]"
        echo ""
        echo "This script helps restore Vivaldi bookmarks and extensions from a"
        echo "Cachy Browser (Firefox) backup located on your external drive."
        echo ""
        echo "Options:"
        echo "  -h, --help     Show this help message"
        echo ""
        echo "The script will:"
        echo "  1. Backup your current Vivaldi profile"
        echo "  2. Extract bookmarks from Firefox backup"
        echo "  3. Create importable bookmark files"
        echo "  4. Generate an extension installation guide"
        echo ""
        echo "Requirements:"
        echo "  • Vivaldi must be closed"
        echo "  • Backup drive must be mounted at: $BACKUP_PATH"
        echo "  • Python3 (optional, for bookmark extraction)"
        echo "  • jq (optional, for better parsing)"
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac
