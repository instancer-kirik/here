#!/bin/bash

# 🏠 here - Vivaldi Bookmark Restoration Script
# Extract and import bookmarks from Cachy Browser backup

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
BACKUP_PATH="/run/media/bon/MainStorage/MAIN_SWAP/home-backup"
CACHY_BACKUP="$BACKUP_PATH/.cachy/5aa1tbhk.default-release"
TEMP_DIR="/tmp/bookmark-restore-$$"

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

# Create temporary directory
setup_temp() {
    mkdir -p "$TEMP_DIR"
    log "Created temporary directory: $TEMP_DIR"
}

# Try different methods to extract bookmarks
extract_bookmarks() {
    log "Attempting to extract bookmarks..."

    local bookmark_backup="$CACHY_BACKUP/bookmarkbackups"

    if [[ -d "$bookmark_backup" ]]; then
        local latest_backup=$(ls -t "$bookmark_backup"/*.jsonlz4 2>/dev/null | head -1)

        if [[ -f "$latest_backup" ]]; then
            info "Found compressed bookmark file: $(basename "$latest_backup")"

            # Try using lz4 command line tool if available
            if command -v lz4 >/dev/null 2>&1; then
                log "Attempting extraction with lz4 command..."

                # Skip Mozilla's 8-byte header and decompress
                tail -c +9 "$latest_backup" | lz4 -d > "$TEMP_DIR/bookmarks.json" 2>/dev/null && {
                    log "✅ Successfully extracted bookmarks with lz4"
                    return 0
                } || warn "lz4 extraction failed"
            fi

            # Try Python method if available
            if command -v python3 >/dev/null 2>&1; then
                log "Attempting extraction with Python..."

                if python3 - "$latest_backup" "$TEMP_DIR/bookmarks.json" << 'EOF'
import sys
import json

# Simple fallback - try to find JSON data in the file
try:
    with open(sys.argv[1], 'rb') as f:
        data = f.read()

    # Look for JSON start after the LZ4 header
    json_start = data.find(b'{')
    if json_start > 0:
        # Try to extract what looks like JSON
        potential_json = data[json_start:].decode('utf-8', errors='ignore')

        # Find the likely end of JSON
        brace_count = 0
        end_pos = 0
        for i, char in enumerate(potential_json):
            if char == '{':
                brace_count += 1
            elif char == '}':
                brace_count -= 1
                if brace_count == 0:
                    end_pos = i + 1
                    break

        if end_pos > 0:
            json_data = potential_json[:end_pos]
            # Validate JSON
            parsed = json.loads(json_data)

            with open(sys.argv[2], 'w') as out:
                json.dump(parsed, out, indent=2)
            print("Python extraction successful")
        else:
            raise Exception("No valid JSON structure found")
    else:
        raise Exception("No JSON data found")

except Exception as e:
    print(f"Python extraction failed: {e}")
    sys.exit(1)
EOF
                then
                    log "✅ Successfully extracted bookmarks with Python"
                    return 0
                else
                    warn "Python extraction failed"
                fi
            fi

            warn "Could not extract compressed bookmarks automatically"
            info "Compressed bookmark file location: $latest_backup"
            return 1
        fi
    fi

    # Check for uncompressed bookmarks
    if [[ -f "$CACHY_BACKUP/places.sqlite" ]]; then
        info "Found Firefox places database"
        warn "SQLite extraction not implemented in this script"
        info "Database location: $CACHY_BACKUP/places.sqlite"
        return 1
    fi

    warn "No extractable bookmarks found"
    return 1
}

# Convert extracted bookmarks to HTML format
convert_to_html() {
    if [[ ! -f "$TEMP_DIR/bookmarks.json" ]]; then
        return 1
    fi

    log "Converting bookmarks to HTML format..."

    # Create HTML bookmark file header
    cat > "$TEMP_DIR/bookmarks.html" << 'EOF'
<!DOCTYPE NETSCAPE-Bookmark-file-1>
<!-- This is an automatically generated file.
     It will be read and overwritten.
     DO NOT EDIT! -->
<META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">
<TITLE>Bookmarks</TITLE>
<H1>Bookmarks</H1>
<DT><H3 PERSONAL_TOOLBAR_FOLDER="true">Bookmarks Toolbar</H3>
<DL><p>
EOF

    # Simple bookmark extraction using basic tools
    if command -v jq >/dev/null 2>&1; then
        log "Using jq for bookmark conversion..."

        # Extract bookmarks recursively
        jq -r '
        def extract_bookmarks:
            if type == "object" then
                if .type == "text/x-moz-place" and .uri then
                    "<DT><A HREF=\"\(.uri)\">\(.title // .uri)</A>"
                else
                    (.children // empty)[] | extract_bookmarks
                end
            elif type == "array" then
                .[] | extract_bookmarks
            else
                empty
            end;

        extract_bookmarks
        ' "$TEMP_DIR/bookmarks.json" >> "$TEMP_DIR/bookmarks.html" 2>/dev/null || {
            warn "jq conversion failed, trying alternative method"
        }
    else
        log "Using grep/sed for bookmark conversion..."

        # Fallback method using grep and sed
        grep -o '"uri":"[^"]*","title":"[^"]*"' "$TEMP_DIR/bookmarks.json" 2>/dev/null | \
        sed 's/"uri":"\([^"]*\)","title":"\([^"]*\)"/<DT><A HREF="\1">\2<\/A>/' >> "$TEMP_DIR/bookmarks.html" || {
            warn "Basic conversion failed"
        }
    fi

    # Close HTML structure
    echo "</DL><p>" >> "$TEMP_DIR/bookmarks.html"

    if [[ -s "$TEMP_DIR/bookmarks.html" ]] && grep -q "HREF=" "$TEMP_DIR/bookmarks.html"; then
        log "✅ Successfully converted bookmarks to HTML"
        return 0
    else
        warn "HTML conversion produced no valid bookmarks"
        return 1
    fi
}

# Show import instructions
show_instructions() {
    echo ""
    log "🎉 Bookmark Restoration Complete!"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    if [[ -f "$TEMP_DIR/bookmarks.html" ]] && grep -q "HREF=" "$TEMP_DIR/bookmarks.html" 2>/dev/null; then
        info "✅ HTML bookmark file created: $TEMP_DIR/bookmarks.html"
        echo ""
        info "🔧 To import into Vivaldi:"
        echo "  1. Open Vivaldi browser"
        echo "  2. Go to: Vivaldi Menu → Bookmarks → Import Bookmarks and Settings"
        echo "  3. Choose: 'Bookmarks HTML File'"
        echo "  4. Select file: $TEMP_DIR/bookmarks.html"
        echo "  5. Click 'Import'"
        echo ""

        # Show bookmark count
        local bookmark_count=$(grep -c "HREF=" "$TEMP_DIR/bookmarks.html" 2>/dev/null || echo "unknown")
        info "📊 Found approximately $bookmark_count bookmarks"
    else
        warn "❌ Automatic bookmark extraction failed"
        echo ""
        info "🔧 Manual import options:"
        echo "  1. Install Firefox temporarily: yay -S firefox"
        echo "  2. Create Firefox profile pointing to backup directory:"
        echo "     $CACHY_BACKUP"
        echo "  3. Export bookmarks from Firefox as HTML"
        echo "  4. Import HTML file into Vivaldi"
        echo ""
        info "📁 Backup bookmark files location:"
        if [[ -d "$CACHY_BACKUP/bookmarkbackups" ]]; then
            ls -la "$CACHY_BACKUP/bookmarkbackups/" 2>/dev/null || true
        fi
    fi

    echo ""
    info "💡 Alternative: Direct Firefox Profile Import"
    echo "  In Vivaldi's import dialog, choose 'Firefox' and select:"
    echo "  $CACHY_BACKUP"
    echo ""

    info "🧩 Don't forget to install your extensions!"
    echo "  • uBlock Origin (Ad blocker)"
    echo "  • Dark Reader (Dark mode)"
    echo "  • Bitwarden (Password manager)"
    echo "  See: here/vivaldi-restore-guide.md for details"
    echo ""
}

# Cleanup
cleanup() {
    if [[ -d "$TEMP_DIR" ]]; then
        echo ""
        read -p "Keep temporary files? [y/N]: " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            rm -rf "$TEMP_DIR"
            log "Cleaned up temporary files"
        else
            info "Temporary files preserved at: $TEMP_DIR"
        fi
    fi
}

# Main function
main() {
    log "🏠 here - Starting bookmark extraction from Cachy Browser backup"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    check_backup
    setup_temp

    if extract_bookmarks; then
        convert_to_html
    fi

    show_instructions

    trap cleanup EXIT
}

# Handle command line arguments
case "${1:-}" in
    -h|--help)
        echo "🏠 here - Vivaldi Bookmark Restoration Script"
        echo ""
        echo "Usage: $0 [options]"
        echo ""
        echo "This script extracts bookmarks from your Cachy Browser backup"
        echo "and converts them to a format Vivaldi can import."
        echo ""
        echo "Options:"
        echo "  -h, --help     Show this help message"
        echo ""
        echo "Requirements:"
        echo "  • Backup drive mounted at: $BACKUP_PATH"
        echo "  • Optional: lz4, python3, jq for better extraction"
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac
