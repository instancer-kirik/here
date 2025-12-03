#!/bin/bash

# 🏠 here - Comprehensive System Migration Script
# Complete backup and migration solution for desktop environments

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
MIGRATION_DIR="${HOME}/.here-migrations/migration-$(date +%Y%m%d-%H%M%S)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERBOSE=${VERBOSE:-0}
SKIP_PACKAGES=${SKIP_PACKAGES:-0}
SKIP_DESKTOP=${SKIP_DESKTOP:-0}
SKIP_THEMES=${SKIP_THEMES:-0}

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

verbose() {
    [[ $VERBOSE -eq 1 ]] && echo -e "${CYAN}🔍 [$(date +'%H:%M:%S')]${NC} $*"
}

# Print banner
print_banner() {
    echo -e "${PURPLE}"
    echo "██╗  ██╗███████╗██████╗ ███████╗"
    echo "██║  ██║██╔════╝██╔══██╗██╔════╝"
    echo "███████║█████╗  ██████╔╝█████╗  "
    echo "██╔══██║██╔══╝  ██╔══██╗██╔══╝  "
    echo "██║  ██║███████╗██║  ██║███████╗"
    echo "╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝╚══════╝"
    echo -e "${NC}"
    echo "🏠 here - Universal Package Manager"
    echo "🚀 Complete System Migration Tool"
    echo ""
}

# Check dependencies
check_dependencies() {
    local missing_deps=()

    # Check for here binary
    if ! command -v here >/dev/null 2>&1 && [[ ! -f "$SCRIPT_DIR/zig-out/bin/here" ]]; then
        missing_deps+=("here (build with 'zig build' or install)")
    fi

    # Check for backup scripts
    if [[ ! -f "$SCRIPT_DIR/backup-desktop-state.sh" ]]; then
        missing_deps+=("backup-desktop-state.sh")
    fi

    if [[ ! -f "$SCRIPT_DIR/backup-cachyos-themes.sh" ]]; then
        missing_deps+=("backup-cachyos-themes.sh")
    fi

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        error "Missing dependencies:"
        for dep in "${missing_deps[@]}"; do
            echo "  - $dep"
        done
        return 1
    fi
}

# Setup migration directory
setup_migration_dir() {
    log "Setting up migration directory..."
    mkdir -p "$MIGRATION_DIR"/{packages,desktop,themes,scripts,docs}

    # Create migration manifest
    cat > "$MIGRATION_DIR/migration-manifest.json" << EOF
{
  "migration": {
    "created": "$(date -Iseconds)",
    "created_by": "$(whoami)@$(hostname)",
    "source_system": {
      "os": "$(lsb_release -d 2>/dev/null | cut -f2 || cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2 | tr -d '\"' || uname -s)",
      "kernel": "$(uname -r)",
      "arch": "$(uname -m)",
      "desktop": "${XDG_CURRENT_DESKTOP:-Unknown}",
      "shell": "$SHELL"
    },
    "components": {
      "packages": $([ $SKIP_PACKAGES -eq 0 ] && echo "true" || echo "false"),
      "desktop": $([ $SKIP_DESKTOP -eq 0 ] && echo "true" || echo "false"),
      "themes": $([ $SKIP_THEMES -eq 0 ] && echo "true" || echo "false")
    }
  }
}
EOF

    verbose "Migration directory created at: $MIGRATION_DIR"
}

# Backup packages using here tool
backup_packages() {
    if [[ $SKIP_PACKAGES -eq 1 ]]; then
        warn "Skipping package backup (SKIP_PACKAGES=1)"
        return
    fi

    log "Backing up packages with here..."

    local here_binary=""
    if command -v here >/dev/null 2>&1; then
        here_binary="here"
    elif [[ -f "$SCRIPT_DIR/zig-out/bin/here" ]]; then
        here_binary="$SCRIPT_DIR/zig-out/bin/here"
    else
        error "here binary not found"
        return 1
    fi

    # Export packages with configuration
    verbose "Creating package profile with configurations..."
    cd "$MIGRATION_DIR/packages"
    $here_binary export --include-config complete-system-profile.json || {
        error "Failed to export packages"
        return 1
    }

    # Export packages without configuration (lighter profile)
    verbose "Creating lightweight package profile..."
    $here_binary export packages-only-profile.json || {
        warn "Failed to export lightweight profile"
    }

    success "Package backup completed"
}

# Backup desktop environment
backup_desktop() {
    if [[ $SKIP_DESKTOP -eq 1 ]]; then
        warn "Skipping desktop backup (SKIP_DESKTOP=1)"
        return
    fi

    log "Backing up desktop environment..."

    # Run desktop backup script
    if [[ -f "$SCRIPT_DIR/backup-desktop-state.sh" ]]; then
        verbose "Running desktop state backup..."
        VERBOSE=$VERBOSE "$SCRIPT_DIR/backup-desktop-state.sh" || {
            warn "Desktop backup script failed, continuing..."
        }

        # Move desktop backup to migration directory
        local latest_desktop_backup=$(find "$HOME/.here-backups" -name "desktop-*" -type d | sort | tail -1)
        if [[ -n "$latest_desktop_backup" && -d "$latest_desktop_backup" ]]; then
            verbose "Moving desktop backup to migration directory..."
            mv "$latest_desktop_backup" "$MIGRATION_DIR/desktop/desktop-backup"
        fi
    else
        warn "Desktop backup script not found, skipping desktop backup"
    fi

    success "Desktop backup completed"
}

# Backup themes and customizations
backup_themes() {
    if [[ $SKIP_THEMES -eq 1 ]]; then
        warn "Skipping theme backup (SKIP_THEMES=1)"
        return
    fi

    log "Backing up themes and customizations..."

    # Run CachyOS theme backup script
    if [[ -f "$SCRIPT_DIR/backup-cachyos-themes.sh" ]]; then
        verbose "Running CachyOS theme backup..."
        VERBOSE=$VERBOSE "$SCRIPT_DIR/backup-cachyos-themes.sh" || {
            warn "Theme backup script failed, continuing..."
        }

        # Move theme backup to migration directory
        local latest_theme_backup=$(find "$HOME/.here-backups" -name "cachyos-themes-*" -type d | sort | tail -1)
        if [[ -n "$latest_theme_backup" && -d "$latest_theme_backup" ]]; then
            verbose "Moving theme backup to migration directory..."
            mv "$latest_theme_backup" "$MIGRATION_DIR/themes/theme-backup"
        fi
    else
        warn "Theme backup script not found, skipping theme backup"
    fi

    success "Theme backup completed"
}

# Copy migration scripts
copy_scripts() {
    log "Copying migration scripts..."

    # Copy all backup/restore scripts
    local scripts_to_copy=(
        "backup-desktop-state.sh"
        "backup-cachyos-themes.sh"
        "migrate-system.sh"
    )

    for script in "${scripts_to_copy[@]}"; do
        if [[ -f "$SCRIPT_DIR/$script" ]]; then
            verbose "Copying $script"
            cp "$SCRIPT_DIR/$script" "$MIGRATION_DIR/scripts/"
        fi
    done

    # Make scripts executable
    chmod +x "$MIGRATION_DIR/scripts"/*.sh 2>/dev/null || true

    success "Scripts copied"
}

# Create comprehensive restore script
create_master_restore_script() {
    log "Creating master restore script..."

    cat > "$MIGRATION_DIR/restore-complete-system.sh" << 'EOF'
#!/bin/bash

# 🏠 here - Master System Restore Script
# Restore complete system from here migration backup

set -euo pipefail

MIGRATION_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY_RUN=${DRY_RUN:-0}
SKIP_PACKAGES=${SKIP_PACKAGES:-0}
SKIP_DESKTOP=${SKIP_DESKTOP:-0}
SKIP_THEMES=${SKIP_THEMES:-0}

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date +'%H:%M:%S')]${NC} $*"; }
warn() { echo -e "${YELLOW}⚠️  [$(date +'%H:%M:%S')]${NC} $*"; }
error() { echo -e "${RED}❌ [$(date +'%H:%M:%S')]${NC} $*"; }
info() { echo -e "${BLUE}ℹ️  [$(date +'%H:%M:%S')]${NC} $*"; }

print_banner() {
    echo -e "\033[0;35m"
    echo "██████╗ ███████╗███████╗████████╗ ██████╗ ██████╗ ███████╗"
    echo "██╔══██╗██╔════╝██╔════╝╚══██╔══╝██╔═══██╗██╔══██╗██╔════╝"
    echo "██████╔╝█████╗  ███████╗   ██║   ██║   ██║██████╔╝█████╗  "
    echo "██╔══██╗██╔══╝  ╚════██║   ██║   ██║   ██║██╔══██╗██╔══╝  "
    echo "██║  ██║███████╗███████║   ██║   ╚██████╔╝██║  ██║███████╗"
    echo "╚═╝  ╚═╝╚══════╝╚══════╝   ╚═╝    ╚═════╝ ╚═╝  ╚═╝╚══════╝"
    echo -e "${NC}"
    echo "🏠 here - System Restore"
    echo ""
}

main() {
    print_banner
    log "🏠 here - Starting complete system restore from $MIGRATION_DIR"

    if [[ $DRY_RUN -eq 1 ]]; then
        warn "DRY RUN MODE - No changes will be made"
    fi

    # Show migration info
    if [[ -f "$MIGRATION_DIR/migration-manifest.json" ]]; then
        info "Migration created: $(jq -r '.migration.created' "$MIGRATION_DIR/migration-manifest.json" 2>/dev/null || echo 'Unknown')"
        info "Source system: $(jq -r '.migration.source_system.os' "$MIGRATION_DIR/migration-manifest.json" 2>/dev/null || echo 'Unknown')"
    fi

    # Restore packages
    if [[ $SKIP_PACKAGES -eq 0 && -f "$MIGRATION_DIR/packages/complete-system-profile.json" ]]; then
        log "Restoring packages..."
        if command -v here >/dev/null 2>&1; then
            if [[ $DRY_RUN -eq 0 ]]; then
                here import "$MIGRATION_DIR/packages/complete-system-profile.json" || warn "Package restore failed"
            else
                echo "Would run: here import $MIGRATION_DIR/packages/complete-system-profile.json"
            fi
        else
            warn "here command not found, skipping package restore"
        fi
    fi

    # Restore desktop environment
    if [[ $SKIP_DESKTOP -eq 0 && -f "$MIGRATION_DIR/desktop/desktop-backup/restore.sh" ]]; then
        log "Restoring desktop environment..."
        if [[ $DRY_RUN -eq 0 ]]; then
            cd "$MIGRATION_DIR/desktop/desktop-backup" && ./restore.sh || warn "Desktop restore failed"
        else
            echo "Would run desktop restore script"
        fi
    fi

    # Restore themes
    if [[ $SKIP_THEMES -eq 0 && -f "$MIGRATION_DIR/themes/theme-backup/restore-cachyos-themes.sh" ]]; then
        log "Restoring themes..."
        if [[ $DRY_RUN -eq 0 ]]; then
            cd "$MIGRATION_DIR/themes/theme-backup" && DRY_RUN=$DRY_RUN ./restore-cachyos-themes.sh || warn "Theme restore failed"
        else
            echo "Would run theme restore script"
        fi
    fi

    log "✅ System restore completed!"
    log "💡 You may need to:"
    log "   • Reboot the system"
    log "   • Log out and back in"
    log "   • Run 'fc-cache -fv' to refresh fonts"
    log "   • Manually configure display settings"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        --skip-packages)
            SKIP_PACKAGES=1
            shift
            ;;
        --skip-desktop)
            SKIP_DESKTOP=1
            shift
            ;;
        --skip-themes)
            SKIP_THEMES=1
            shift
            ;;
        -h|--help)
            echo "🏠 here - Master System Restore Script"
            echo ""
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --dry-run         Show what would be done without making changes"
            echo "  --skip-packages   Skip package restoration"
            echo "  --skip-desktop    Skip desktop environment restoration"
            echo "  --skip-themes     Skip theme restoration"
            echo "  -h, --help        Show this help"
            echo ""
            echo "Environment variables:"
            echo "  DRY_RUN=1         Same as --dry-run"
            echo "  SKIP_PACKAGES=1   Same as --skip-packages"
            echo "  SKIP_DESKTOP=1    Same as --skip-desktop"
            echo "  SKIP_THEMES=1     Same as --skip-themes"
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            exit 1
            ;;
    esac
done

main "$@"
EOF

    chmod +x "$MIGRATION_DIR/restore-complete-system.sh"
    success "Master restore script created"
}

# Create documentation
create_documentation() {
    log "Creating migration documentation..."

    cat > "$MIGRATION_DIR/README.md" << EOF
# 🏠 here - Complete System Migration

This directory contains a complete system migration created by the **here** universal package manager.

## Migration Contents

- **📦 Packages** (\`packages/\`): Complete package inventory with configurations
- **🖥️ Desktop** (\`desktop/\`): Desktop environment settings and configurations
- **🎨 Themes** (\`themes/\`): GTK themes, icon themes, wallpapers, and customizations
- **📜 Scripts** (\`scripts/\`): All backup and restore scripts
- **📚 Documentation** (\`docs/\`): This documentation and system information

## Quick Restore

To restore this system on a new machine:

\`\`\`bash
# Download and install here first
curl -fsSL https://raw.githubusercontent.com/instance-select/here/main/install.sh | bash

# Then restore everything
./restore-complete-system.sh
\`\`\`

## Selective Restore

You can restore individual components:

\`\`\`bash
# Packages only
here import packages/complete-system-profile.json

# Desktop environment only
cd desktop/desktop-backup && ./restore.sh

# Themes only
cd themes/theme-backup && ./restore-cachyos-themes.sh

# Test before applying (dry run)
DRY_RUN=1 ./restore-complete-system.sh
\`\`\`

## Migration Information

$(if [[ -f "$MIGRATION_DIR/migration-manifest.json" ]]; then
    echo "- **Created**: $(jq -r '.migration.created' "$MIGRATION_DIR/migration-manifest.json" 2>/dev/null || echo 'Unknown')"
    echo "- **Source OS**: $(jq -r '.migration.source_system.os' "$MIGRATION_DIR/migration-manifest.json" 2>/dev/null || echo 'Unknown')"
    echo "- **Desktop Environment**: $(jq -r '.migration.source_system.desktop' "$MIGRATION_DIR/migration-manifest.json" 2>/dev/null || echo 'Unknown')"
    echo "- **Architecture**: $(jq -r '.migration.source_system.arch' "$MIGRATION_DIR/migration-manifest.json" 2>/dev/null || echo 'Unknown')"
fi)

## File Structure

\`\`\`
$(tree -L 2 "$MIGRATION_DIR" 2>/dev/null || find "$MIGRATION_DIR" -type d | head -20)
\`\`\`

## Support

For more information about the **here** universal package manager:
- GitHub: https://github.com/instance-select/here
- Documentation: Run \`here help\` after installation

---
*Generated by here v$(here version 2>/dev/null | head -1 | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+' || echo '1.0.0')*
EOF

    success "Documentation created"
}

# Create migration summary
create_summary() {
    log "Creating migration summary..."

    local total_files=$(find "$MIGRATION_DIR" -type f | wc -l)
    local total_size=$(du -sh "$MIGRATION_DIR" | cut -f1)
    local package_count="Unknown"

    # Try to get package count
    if [[ -f "$MIGRATION_DIR/packages/complete-system-profile.json" ]]; then
        if command -v jq >/dev/null 2>&1; then
            local native_count=$(jq -r '.packages.native | length' "$MIGRATION_DIR/packages/complete-system-profile.json" 2>/dev/null || echo 0)
            local flatpak_count=$(jq -r '.packages.flatpak | length' "$MIGRATION_DIR/packages/complete-system-profile.json" 2>/dev/null || echo 0)
            local appimage_count=$(jq -r '.packages.appimage | length' "$MIGRATION_DIR/packages/complete-system-profile.json" 2>/dev/null || echo 0)
            package_count="$native_count native, $flatpak_count flatpak, $appimage_count appimage"
        fi
    fi

    cat > "$MIGRATION_DIR/MIGRATION_SUMMARY.txt" << EOF
🏠 here - Migration Summary
===========================

Migration created: $(date)
Source system: $(whoami)@$(hostname)
Total files: $total_files
Total size: $total_size
Packages: $package_count

Components included:
$([ $SKIP_PACKAGES -eq 0 ] && echo "✅ Packages and configurations" || echo "❌ Packages (skipped)")
$([ $SKIP_DESKTOP -eq 0 ] && echo "✅ Desktop environment settings" || echo "❌ Desktop environment (skipped)")
$([ $SKIP_THEMES -eq 0 ] && echo "✅ Themes and customizations" || echo "❌ Themes (skipped)")

To restore on a new system:
1. Install here: curl -fsSL https://raw.githubusercontent.com/instance-select/here/main/install.sh | bash
2. Run: ./restore-complete-system.sh

For selective restore, see README.md
EOF

    success "Migration summary created"
}

# Main function
main() {
    print_banner

    log "🏠 here - Starting comprehensive system migration..."

    # Preflight checks
    check_dependencies || {
        error "Dependency check failed"
        exit 1
    }

    setup_migration_dir

    # Perform backups
    backup_packages
    backup_desktop
    backup_themes
    copy_scripts

    # Create restore tools
    create_master_restore_script
    create_documentation
    create_summary

    success "✅ Complete system migration created!"
    success "📁 Migration saved to: $MIGRATION_DIR"
    success "🚀 To restore: cd '$MIGRATION_DIR' && ./restore-complete-system.sh"
    success "🧪 To test restore: DRY_RUN=1 ./restore-complete-system.sh"

    echo ""
    info "📊 Migration Summary:"
    echo "  Files: $(find "$MIGRATION_DIR" -type f | wc -l)"
    echo "  Size: $(du -sh "$MIGRATION_DIR" | cut -f1)"
    echo "  Location: $MIGRATION_DIR"

    echo ""
    info "🎯 Next Steps:"
    echo "  1. Copy migration to new system: scp -r '$MIGRATION_DIR' user@newhost:"
    echo "  2. Install here on new system: curl -fsSL https://raw.githubusercontent.com/instance-select/here/main/install.sh | bash"
    echo "  3. Restore system: ./restore-complete-system.sh"
    echo ""
    info "💾 Archive for transfer: tar czf migration-$(basename "$MIGRATION_DIR").tar.gz -C $(dirname "$MIGRATION_DIR") $(basename "$MIGRATION_DIR")"
}

# Handle command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -v|--verbose)
            VERBOSE=1
            shift
            ;;
        --skip-packages)
            SKIP_PACKAGES=1
            shift
            ;;
        --skip-desktop)
            SKIP_DESKTOP=1
            shift
            ;;
        --skip-themes)
            SKIP_THEMES=1
            shift
            ;;
        -h|--help)
            echo "🏠 here - Comprehensive System Migration Script"
            echo ""
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  -v, --verbose      Enable verbose output"
            echo "  --skip-packages    Skip package backup/export"
            echo "  --skip-desktop     Skip desktop environment backup"
            echo "  --skip-themes      Skip theme and customization backup"
            echo "  -h, --help         Show this help message"
            echo ""
            echo "Environment variables:"
            echo "  VERBOSE=1          Enable verbose output"
            echo "  SKIP_PACKAGES=1    Skip package backup"
            echo "  SKIP_DESKTOP=1     Skip desktop backup"
            echo "  SKIP_THEMES=1      Skip theme backup"
            echo ""
            echo "This script creates a complete system migration including:"
            echo "  • Package inventory with configurations (here export)"
            echo "  • Desktop environment settings and dotfiles"
            echo "  • Themes, icons, wallpapers, and customizations"
            echo "  • Restore scripts for easy system migration"
            echo ""
            echo "The migration will be saved to ~/.here-migrations/migration-YYYYMMDD-HHMMSS"
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
