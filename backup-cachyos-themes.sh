#!/bin/bash

# 🏠 here - CachyOS Theme & Customization Backup Script
# Specialized backup for CachyOS desktop themes and customizations

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
BACKUP_DIR="${HOME}/.here-backups/cachyos-themes-$(date +%Y%m%d-%H%M%S)"
VERBOSE=${VERBOSE:-0}

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

verbose() {
    [[ $VERBOSE -eq 1 ]] && echo -e "${CYAN}🔍 [$(date +'%H:%M:%S')]${NC} $*"
}

# Create backup directories
setup_backup_dirs() {
    mkdir -p "$BACKUP_DIR"/{cachyos-configs,fish-configs,themes,wallpapers,icons,cursors,fonts,plasma-themes,cinnamon-themes}
}

# Backup CachyOS specific configurations
backup_cachyos_configs() {
    log "Backing up CachyOS specific configurations..."

    # CachyOS Hello and system configs
    [[ -d "$HOME/.config/cachyos-hello" ]] && cp -r "$HOME/.config/cachyos-hello" "$BACKUP_DIR/cachyos-configs/" 2>/dev/null || true

    # CachyOS Fish configuration
    if [[ -d "$HOME/.config/fish" ]]; then
        verbose "Copying CachyOS Fish config"
        cp -r "$HOME/.config/fish" "$BACKUP_DIR/fish-configs/" 2>/dev/null || true
    fi

    # CachyOS specific dotfiles
    local cachyos_files=(
        ".config/cachyos"
        ".local/share/cachyos"
        ".cache/cachyos"
    )

    for config in "${cachyos_files[@]}"; do
        if [[ -e "$HOME/$config" ]]; then
            verbose "Copying $config"
            mkdir -p "$BACKUP_DIR/cachyos-configs/$(dirname "$config")"
            cp -r "$HOME/$config" "$BACKUP_DIR/cachyos-configs/$config" 2>/dev/null || warn "Failed to copy $config"
        fi
    done
}

# Backup CachyOS wallpapers
backup_cachyos_wallpapers() {
    log "Backing up CachyOS wallpapers..."

    # System wallpapers
    if [[ -d "/usr/share/pixmaps/cachyos" ]]; then
        verbose "Copying system CachyOS wallpapers"
        mkdir -p "$BACKUP_DIR/wallpapers/system"
        cp -r "/usr/share/pixmaps/cachyos" "$BACKUP_DIR/wallpapers/system/" 2>/dev/null || true
    fi

    # User wallpapers
    local wallpaper_dirs=(
        "$HOME/Pictures/Wallpapers"
        "$HOME/.local/share/wallpapers"
        "$HOME/Wallpapers"
        "$HOME/.config/wallpapers"
        "$HOME/Pictures/CachyOS"
    )

    for wallpaper_dir in "${wallpaper_dirs[@]}"; do
        if [[ -d "$wallpaper_dir" ]]; then
            verbose "Copying wallpapers from $wallpaper_dir"
            local dir_name=$(basename "$wallpaper_dir")
            cp -r "$wallpaper_dir" "$BACKUP_DIR/wallpapers/$dir_name" 2>/dev/null || true
        fi
    done

    # Current wallpaper settings
    if command -v gsettings >/dev/null 2>&1; then
        verbose "Saving current wallpaper settings"
        {
            echo "# Current wallpaper settings - $(date)"
            echo "# Cinnamon wallpaper"
            gsettings get org.cinnamon.desktop.background picture-uri 2>/dev/null || echo "# Cinnamon not available"
            echo "# GNOME wallpaper"
            gsettings get org.gnome.desktop.background picture-uri 2>/dev/null || echo "# GNOME not available"
            echo "# Lock screen wallpaper"
            gsettings get org.cinnamon.desktop.screensaver picture-uri 2>/dev/null || echo "# Screensaver setting not available"
        } > "$BACKUP_DIR/wallpapers/current-wallpaper-settings.txt"
    fi
}

# Backup themes and appearance
backup_themes() {
    log "Backing up themes and appearance..."

    # GTK themes
    local theme_dirs=(
        "$HOME/.themes"
        "$HOME/.local/share/themes"
        "/usr/share/themes" # System themes (read-only backup)
    )

    for theme_dir in "${theme_dirs[@]}"; do
        if [[ -d "$theme_dir" ]]; then
            local backup_name=$(basename "$theme_dir")
            [[ "$theme_dir" == "/usr/share/themes" ]] && backup_name="system-themes"
            verbose "Copying themes from $theme_dir"
            cp -r "$theme_dir" "$BACKUP_DIR/themes/$backup_name" 2>/dev/null || warn "Failed to copy $theme_dir"
        fi
    done

    # Current theme settings
    if command -v gsettings >/dev/null 2>&1; then
        verbose "Saving current theme settings"
        {
            echo "# Current theme settings - $(date)"
            echo "# GTK theme"
            gsettings get org.cinnamon.desktop.interface gtk-theme 2>/dev/null || echo "# GTK theme not available"
            echo "# Icon theme"
            gsettings get org.cinnamon.desktop.interface icon-theme 2>/dev/null || echo "# Icon theme not available"
            echo "# Cursor theme"
            gsettings get org.cinnamon.desktop.interface cursor-theme 2>/dev/null || echo "# Cursor theme not available"
            echo "# Window theme"
            gsettings get org.cinnamon.theme name 2>/dev/null || echo "# Window theme not available"
        } > "$BACKUP_DIR/themes/current-theme-settings.txt"
    fi
}

# Backup icon themes
backup_icons() {
    log "Backing up icon themes..."

    local icon_dirs=(
        "$HOME/.icons"
        "$HOME/.local/share/icons"
    )

    for icon_dir in "${icon_dirs[@]}"; do
        if [[ -d "$icon_dir" ]]; then
            local backup_name=$(basename "$icon_dir")
            verbose "Copying icons from $icon_dir"
            cp -r "$icon_dir" "$BACKUP_DIR/icons/$backup_name" 2>/dev/null || warn "Failed to copy $icon_dir"
        fi
    done

    # Backup Bibata cursor theme specifically (since it's in your package list)
    if [[ -d "/usr/share/icons/Bibata-Modern-Classic" ]]; then
        verbose "Backing up Bibata cursor theme"
        mkdir -p "$BACKUP_DIR/cursors/system"
        cp -r "/usr/share/icons/Bibata-Modern-Classic" "$BACKUP_DIR/cursors/system/" 2>/dev/null || true
    fi
}

# Backup Cinnamon specific settings
backup_cinnamon() {
    log "Backing up Cinnamon desktop environment..."

    # Cinnamon configurations
    local cinnamon_configs=(
        ".config/cinnamon"
        ".local/share/cinnamon"
        ".config/nemo"
        ".config/cinnamon-session"
    )

    for config in "${cinnamon_configs[@]}"; do
        if [[ -d "$HOME/$config" ]]; then
            verbose "Copying $config"
            cp -r "$HOME/$config" "$BACKUP_DIR/cinnamon-themes/" 2>/dev/null || warn "Failed to copy $config"
        fi
    done

    # Backup dconf settings for Cinnamon
    if command -v dconf >/dev/null 2>&1; then
        info "Backing up Cinnamon dconf settings..."
        dconf dump /org/cinnamon/ > "$BACKUP_DIR/cinnamon-themes/cinnamon-dconf.conf" 2>/dev/null || warn "Failed to dump Cinnamon dconf"
        dconf dump /org/nemo/ > "$BACKUP_DIR/cinnamon-themes/nemo-dconf.conf" 2>/dev/null || warn "Failed to dump Nemo dconf"

        # Backup extensions and applets
        verbose "Backing up Cinnamon extensions and applets settings"
        for schema in org.cinnamon.extensions org.cinnamon.applets org.cinnamon.desklets; do
            dconf dump /$schema/ > "$BACKUP_DIR/cinnamon-themes/$(echo $schema | tr '.' '-').conf" 2>/dev/null || true
        done
    fi
}

# Backup Awesome WM configuration (since you have it installed)
backup_awesome() {
    if [[ -d "$HOME/.config/awesome" ]]; then
        log "Backing up Awesome WM configuration..."
        cp -r "$HOME/.config/awesome" "$BACKUP_DIR/cachyos-configs/" 2>/dev/null || warn "Failed to copy Awesome WM config"

        # Backup awesome themes if they exist
        if [[ -d "$HOME/.config/awesome/themes" ]]; then
            verbose "Copying Awesome WM themes"
            cp -r "$HOME/.config/awesome/themes" "$BACKUP_DIR/themes/awesome-themes" 2>/dev/null || true
        fi
    fi
}

# Backup fonts including CachyOS specific ones
backup_fonts() {
    log "Backing up fonts..."

    local font_dirs=(
        "$HOME/.fonts"
        "$HOME/.local/share/fonts"
    )

    for font_dir in "${font_dirs[@]}"; do
        if [[ -d "$font_dir" ]]; then
            verbose "Copying fonts from $font_dir"
            local backup_name=$(basename "$font_dir")
            cp -r "$font_dir" "$BACKUP_DIR/fonts/$backup_name" 2>/dev/null || warn "Failed to copy $font_dir"
        fi
    done

    # Font configuration
    if [[ -f "$HOME/.config/fontconfig/fonts.conf" ]]; then
        verbose "Copying fontconfig configuration"
        mkdir -p "$BACKUP_DIR/fonts/config"
        cp "$HOME/.config/fontconfig/fonts.conf" "$BACKUP_DIR/fonts/config/" 2>/dev/null || true
    fi

    # List installed fonts
    if command -v fc-list >/dev/null 2>&1; then
        verbose "Creating font inventory"
        fc-list > "$BACKUP_DIR/fonts/installed-fonts.txt" 2>/dev/null || true
    fi
}

# Create system information specific to CachyOS
create_cachyos_system_info() {
    log "Creating CachyOS system information snapshot..."

    {
        echo "# 🏠 here - CachyOS Theme Backup System Information"
        echo "# Generated: $(date)"
        echo "# Hostname: $(hostname)"
        echo "# User: $(whoami)"
        echo ""
        echo "## CachyOS System Information"
        if [[ -f /etc/cachyos-release ]]; then
            echo "CachyOS Release: $(cat /etc/cachyos-release)"
        fi
        echo "OS: $(lsb_release -d 2>/dev/null | cut -f2 || cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2 | tr -d '"' || uname -s)"
        echo "Kernel: $(uname -r)"
        echo "Architecture: $(uname -m)"
        echo "Desktop: ${XDG_CURRENT_DESKTOP:-Unknown}"
        echo "Session: ${XDG_SESSION_TYPE:-Unknown}"
        echo "Shell: $SHELL"
        echo ""
        echo "## CachyOS Specific Packages"
        if command -v pacman >/dev/null 2>&1; then
            echo "### CachyOS packages:"
            pacman -Q | grep -i cachyos || echo "No CachyOS specific packages found"
        fi
        echo ""
        echo "## Theme Information"
        if command -v gsettings >/dev/null 2>&1; then
            echo "Current GTK theme: $(gsettings get org.cinnamon.desktop.interface gtk-theme 2>/dev/null || echo 'Unknown')"
            echo "Current icon theme: $(gsettings get org.cinnamon.desktop.interface icon-theme 2>/dev/null || echo 'Unknown')"
            echo "Current cursor theme: $(gsettings get org.cinnamon.desktop.interface cursor-theme 2>/dev/null || echo 'Unknown')"
        fi
        echo ""
        echo "## Display Information"
        if command -v xrandr >/dev/null 2>&1 && [[ -n "${DISPLAY:-}" ]]; then
            echo "### Display setup"
            xrandr --listmonitors 2>/dev/null || echo "Could not detect displays"
        fi
        echo ""
        echo "## Backup Contents"
        find "$BACKUP_DIR" -type f | wc -l | xargs echo "Total files backed up:"
        du -sh "$BACKUP_DIR" | cut -f1 | xargs echo "Total size:"
    } > "$BACKUP_DIR/cachyos-system-info.txt"
}

# Create restore script for CachyOS themes
create_restore_script() {
    log "Creating CachyOS theme restore script..."

    cat > "$BACKUP_DIR/restore-cachyos-themes.sh" << 'EOF'
#!/bin/bash

# 🏠 here - CachyOS Theme Restore Script
# Restore CachyOS themes and customizations

set -euo pipefail

BACKUP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY_RUN=${DRY_RUN:-0}

log() { echo -e "\033[0;32m[$(date +'%H:%M:%S')]\033[0m $*"; }
warn() { echo -e "\033[1;33m⚠️  [$(date +'%H:%M:%S')]\033[0m $*"; }
error() { echo -e "\033[0;31m❌ [$(date +'%H:%M:%S')]\033[0m $*"; }

restore_directory() {
    local source_dir="$1"
    local target_dir="$2"
    local description="$3"

    if [[ ! -d "$source_dir" ]]; then
        warn "Backup directory $source_dir not found, skipping $description"
        return
    fi

    log "Restoring $description..."

    if [[ $DRY_RUN -eq 1 ]]; then
        echo "Would restore $source_dir to $target_dir"
        return
    fi

    # Create backup of existing files
    if [[ -d "$target_dir" ]]; then
        local backup_name="${target_dir}.backup-$(date +%s)"
        mv "$target_dir" "$backup_name" 2>/dev/null || true
        log "Existing $target_dir backed up to $backup_name"
    fi

    mkdir -p "$(dirname "$target_dir")"
    cp -r "$source_dir" "$target_dir"
}

restore_dconf() {
    local conf_file="$1"
    local description="$2"

    if [[ ! -f "$conf_file" ]] || ! command -v dconf >/dev/null 2>&1; then
        return
    fi

    log "Restoring $description..."

    if [[ $DRY_RUN -eq 1 ]]; then
        echo "Would restore dconf from $conf_file"
        return
    fi

    dconf load / < "$conf_file" 2>/dev/null || warn "Failed to restore $description"
}

main() {
    log "🏠 here - Starting CachyOS theme restore from $BACKUP_DIR"

    if [[ $DRY_RUN -eq 1 ]]; then
        warn "DRY RUN MODE - No files will be modified"
    fi

    # Restore CachyOS configs
    restore_directory "$BACKUP_DIR/cachyos-configs" "$HOME/.config" "CachyOS configurations"
    restore_directory "$BACKUP_DIR/fish-configs/fish" "$HOME/.config/fish" "Fish shell configuration"

    # Restore themes
    restore_directory "$BACKUP_DIR/themes/.themes" "$HOME/.themes" "GTK themes"
    restore_directory "$BACKUP_DIR/themes/.local/share/themes" "$HOME/.local/share/themes" "local themes"

    # Restore icons
    restore_directory "$BACKUP_DIR/icons/.icons" "$HOME/.icons" "icon themes"
    restore_directory "$BACKUP_DIR/icons/.local/share/icons" "$HOME/.local/share/icons" "local icons"

    # Restore fonts
    restore_directory "$BACKUP_DIR/fonts/.fonts" "$HOME/.fonts" "user fonts"
    restore_directory "$BACKUP_DIR/fonts/.local/share/fonts" "$HOME/.local/share/fonts" "local fonts"

    # Restore wallpapers
    for wallpaper_backup in "$BACKUP_DIR/wallpapers"/*; do
        if [[ -d "$wallpaper_backup" && "$(basename "$wallpaper_backup")" != "system" ]]; then
            local wallpaper_name=$(basename "$wallpaper_backup")
            restore_directory "$wallpaper_backup" "$HOME/Pictures/$wallpaper_name" "$wallpaper_name wallpapers"
        fi
    done

    # Restore Cinnamon settings
    restore_directory "$BACKUP_DIR/cinnamon-themes/.config/cinnamon" "$HOME/.config/cinnamon" "Cinnamon configuration"
    restore_directory "$BACKUP_DIR/cinnamon-themes/.config/nemo" "$HOME/.config/nemo" "Nemo file manager"

    # Restore dconf settings
    restore_dconf "$BACKUP_DIR/cinnamon-themes/cinnamon-dconf.conf" "Cinnamon dconf settings"
    restore_dconf "$BACKUP_DIR/cinnamon-themes/nemo-dconf.conf" "Nemo dconf settings"

    # Update font cache
    if command -v fc-cache >/dev/null 2>&1; then
        log "Updating font cache..."
        if [[ $DRY_RUN -eq 0 ]]; then
            fc-cache -fv >/dev/null 2>&1 || warn "Failed to update font cache"
        else
            echo "Would run: fc-cache -fv"
        fi
    fi

    log "✅ CachyOS theme restore completed!"
    log "💡 You may need to log out and back in for all changes to take effect"
    log "🎨 To apply themes: Open System Settings > Themes"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
EOF

    chmod +x "$BACKUP_DIR/restore-cachyos-themes.sh"
}

# Main backup function
main() {
    log "🏠 here - Starting CachyOS theme and customization backup..."

    setup_backup_dirs

    backup_cachyos_configs
    backup_cachyos_wallpapers
    backup_themes
    backup_icons
    backup_cinnamon
    backup_awesome
    backup_fonts

    create_cachyos_system_info
    create_restore_script

    log "✅ CachyOS theme backup completed successfully!"
    log "📁 Backup saved to: $BACKUP_DIR"
    log "🔄 To restore: cd '$BACKUP_DIR' && ./restore-cachyos-themes.sh"
    log "🧪 To test restore: DRY_RUN=1 ./restore-cachyos-themes.sh"

    # Show backup summary
    echo ""
    info "📊 CachyOS Theme Backup Summary:"
    find "$BACKUP_DIR" -type f | wc -l | xargs echo "  Files backed up:"
    du -sh "$BACKUP_DIR" | cut -f1 | xargs echo "  Total size:"

    # Integration note
    echo ""
    info "💡 This backup complements 'here export --include-config' for complete system migration"
    info "🎨 Backup includes: themes, icons, wallpapers, Cinnamon settings, fonts, and CachyOS configs"
}

# Handle command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -v|--verbose)
            VERBOSE=1
            shift
            ;;
        -h|--help)
            echo "🏠 here - CachyOS Theme & Customization Backup Script"
            echo ""
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  -v, --verbose    Enable verbose output"
            echo "  -h, --help       Show this help message"
            echo ""
            echo "This script backs up:"
            echo "  • CachyOS specific configurations"
            echo "  • Fish shell configuration"
            echo "  • GTK themes and icon themes"
            echo "  • Wallpapers and backgrounds"
            echo "  • Cinnamon desktop settings"
            echo "  • Awesome WM configuration (if present)"
            echo "  • Custom fonts and font configuration"
            echo "  • Cursor themes"
            echo ""
            echo "The backup will be saved to ~/.here-backups/cachyos-themes-YYYYMMDD-HHMMSS"
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
