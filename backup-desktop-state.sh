#!/bin/bash

# 🏠 here - Desktop State Backup Script
# Comprehensive backup of desktop environment, themes, and user settings

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
BACKUP_DIR="${HOME}/.here-backups/desktop-$(date +%Y%m%d-%H%M%S)"
TEMP_DIR="/tmp/here-desktop-backup-$$"
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
    mkdir -p "$BACKUP_DIR"/{dotfiles,configs,themes,scripts,desktop-environments,fonts,wallpapers,keybindings,extensions}
    mkdir -p "$TEMP_DIR"
}

# Backup common dotfiles
backup_dotfiles() {
    log "Backing up dotfiles..."

    local dotfiles=(
        ".bashrc" ".bash_profile" ".bash_aliases" ".bash_logout"
        ".zshrc" ".zsh_profile" ".zsh_aliases" ".zsh_history"
        ".profile" ".xprofile" ".xinitrc" ".xsession"
        ".vimrc" ".vim" ".neovim" ".config/nvim"
        ".tmux.conf" ".tmux"
        ".gitconfig" ".gitignore_global" ".config/git"
        ".inputrc" ".dircolors"
        ".fonts.conf" ".config/fontconfig"
        ".Xresources" ".Xdefaults" ".xbindkeys" ".xbindkeysrc"
        ".gtkrc-2.0" ".config/gtk-2.0" ".config/gtk-3.0" ".config/gtk-4.0"
        ".themes" ".icons" ".local/share/themes" ".local/share/icons"
    )

    for dotfile in "${dotfiles[@]}"; do
        if [[ -e "$HOME/$dotfile" ]]; then
            verbose "Copying $dotfile"
            cp -r "$HOME/$dotfile" "$BACKUP_DIR/dotfiles/" 2>/dev/null || warn "Failed to copy $dotfile"
        fi
    done
}

# Backup XDG config directories
backup_xdg_configs() {
    log "Backing up XDG configurations..."

    local configs=(
        "alacritty" "kitty" "wezterm" "foot" "terminator"
        "Code" "code-oss" "codium" "vscodium"
        "fish" "zsh" "starship.toml"
        "awesome" "i3" "sway" "hyprland" "qtile" "xmonad" "bspwm"
        "polybar" "waybar" "tint2" "conky" "rofi" "wofi" "dmenu"
        "picom" "compton" "dunst" "mako" "swaync"
        "ranger" "nnn" "lf" "vifm"
        "mpv" "vlc" "ffmpeg"
        "discord" "telegram" "signal"
        "firefox" "chromium" "brave"
        "obs-studio" "kdenlive" "blender"
        "gimp" "inkscape" "krita"
        "libreoffice" "thunderbird"
        "transmission" "qbittorrent"
        "steam" "lutris" "bottles"
        "cinnamon" "mate" "xfce4" "lxqt"
        "dconf" "gconf"
    )

    for config in "${configs[@]}"; do
        if [[ -d "$HOME/.config/$config" ]]; then
            verbose "Copying .config/$config"
            cp -r "$HOME/.config/$config" "$BACKUP_DIR/configs/" 2>/dev/null || warn "Failed to copy .config/$config"
        fi
    done
}

# Backup desktop environment specific settings
backup_desktop_environments() {
    log "Backing up desktop environment settings..."

    # GNOME/Cinnamon dconf settings
    if command -v dconf >/dev/null 2>&1; then
        info "Backing up dconf settings..."
        dconf dump / > "$BACKUP_DIR/desktop-environments/dconf-settings.conf" 2>/dev/null || warn "Failed to dump dconf settings"

        # Specific desktop environment settings
        for schema in org.cinnamon org.gnome org.mate; do
            if dconf list /$schema/ >/dev/null 2>&1; then
                verbose "Dumping $schema settings"
                dconf dump /$schema/ > "$BACKUP_DIR/desktop-environments/$schema-settings.conf" 2>/dev/null || true
            fi
        done
    fi

    # KDE settings
    if [[ -d "$HOME/.config/kde" ]] || [[ -d "$HOME/.kde" ]]; then
        info "Backing up KDE settings..."
        [[ -d "$HOME/.config/kde" ]] && cp -r "$HOME/.config/kde" "$BACKUP_DIR/desktop-environments/" 2>/dev/null || true
        [[ -d "$HOME/.kde" ]] && cp -r "$HOME/.kde" "$BACKUP_DIR/desktop-environments/" 2>/dev/null || true
        [[ -f "$HOME/.config/kdeglobals" ]] && cp "$HOME/.config/kdeglobals" "$BACKUP_DIR/desktop-environments/" 2>/dev/null || true
    fi

    # XFCE settings
    if [[ -d "$HOME/.config/xfce4" ]]; then
        info "Backing up XFCE settings..."
        cp -r "$HOME/.config/xfce4" "$BACKUP_DIR/desktop-environments/" 2>/dev/null || warn "Failed to backup XFCE settings"
    fi

    # Window manager configs
    for wm in awesome i3 sway bspwm xmonad qtile; do
        if [[ -d "$HOME/.config/$wm" ]]; then
            verbose "Copying $wm config"
            cp -r "$HOME/.config/$wm" "$BACKUP_DIR/desktop-environments/" 2>/dev/null || true
        fi
    done
}

# Backup themes and appearance
backup_themes() {
    log "Backing up themes and appearance..."

    # GTK themes
    [[ -d "$HOME/.themes" ]] && cp -r "$HOME/.themes" "$BACKUP_DIR/themes/" 2>/dev/null || true
    [[ -d "$HOME/.local/share/themes" ]] && cp -r "$HOME/.local/share/themes" "$BACKUP_DIR/themes/local-themes" 2>/dev/null || true

    # Icon themes
    [[ -d "$HOME/.icons" ]] && cp -r "$HOME/.icons" "$BACKUP_DIR/themes/" 2>/dev/null || true
    [[ -d "$HOME/.local/share/icons" ]] && cp -r "$HOME/.local/share/icons" "$BACKUP_DIR/themes/local-icons" 2>/dev/null || true

    # Cursor themes
    [[ -d "$HOME/.local/share/cursors" ]] && cp -r "$HOME/.local/share/cursors" "$BACKUP_DIR/themes/" 2>/dev/null || true

    # Wallpapers
    for wallpaper_dir in "$HOME/Pictures/Wallpapers" "$HOME/.local/share/wallpapers" "$HOME/Wallpapers"; do
        if [[ -d "$wallpaper_dir" ]]; then
            verbose "Copying wallpapers from $wallpaper_dir"
            cp -r "$wallpaper_dir" "$BACKUP_DIR/wallpapers/" 2>/dev/null || true
        fi
    done
}

# Backup fonts
backup_fonts() {
    log "Backing up fonts..."

    [[ -d "$HOME/.fonts" ]] && cp -r "$HOME/.fonts" "$BACKUP_DIR/fonts/" 2>/dev/null || true
    [[ -d "$HOME/.local/share/fonts" ]] && cp -r "$HOME/.local/share/fonts" "$BACKUP_DIR/fonts/local-fonts" 2>/dev/null || true
}

# Backup keybindings and shortcuts
backup_keybindings() {
    log "Backing up keybindings..."

    # Various keybinding files
    local keybinding_files=(
        ".xbindkeysrc" ".config/sxhkd/sxhkdrc"
        ".config/i3/config" ".config/sway/config"
        ".config/awesome/rc.lua"
    )

    for kb_file in "${keybinding_files[@]}"; do
        if [[ -f "$HOME/$kb_file" ]]; then
            verbose "Copying $kb_file"
            mkdir -p "$BACKUP_DIR/keybindings/$(dirname "$kb_file")"
            cp "$HOME/$kb_file" "$BACKUP_DIR/keybindings/$kb_file" 2>/dev/null || true
        fi
    done
}

# Backup browser profiles and extensions
backup_browser_data() {
    log "Backing up browser configurations..."

    # Firefox profiles
    if [[ -d "$HOME/.mozilla/firefox" ]]; then
        info "Backing up Firefox profiles..."
        mkdir -p "$BACKUP_DIR/configs/mozilla"
        cp -r "$HOME/.mozilla/firefox" "$BACKUP_DIR/configs/mozilla/" 2>/dev/null || warn "Failed to backup Firefox profiles"
    fi

    # Chrome/Chromium (config only, not cache)
    for browser in google-chrome chromium brave; do
        browser_dir="$HOME/.config/$browser"
        if [[ -d "$browser_dir" ]]; then
            info "Backing up $browser configuration..."
            mkdir -p "$BACKUP_DIR/configs/$browser"
            # Copy only essential config, not cache/temp files
            find "$browser_dir" -name "Preferences" -o -name "Bookmarks" -o -name "Extensions" | \
                while read -r file; do
                    rel_path=${file#$browser_dir/}
                    mkdir -p "$BACKUP_DIR/configs/$browser/$(dirname "$rel_path")"
                    cp -r "$file" "$BACKUP_DIR/configs/$browser/$rel_path" 2>/dev/null || true
                done
        fi
    done
}

# Create system information snapshot
create_system_info() {
    log "Creating system information snapshot..."

    {
        echo "# 🏠 here - Desktop Backup System Information"
        echo "# Generated: $(date)"
        echo "# Hostname: $(hostname)"
        echo "# User: $(whoami)"
        echo ""
        echo "## System Information"
        echo "OS: $(lsb_release -d 2>/dev/null | cut -f2 || cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2 | tr -d '"' || uname -s)"
        echo "Kernel: $(uname -r)"
        echo "Architecture: $(uname -m)"
        echo "Desktop: ${XDG_CURRENT_DESKTOP:-Unknown}"
        echo "Session: ${XDG_SESSION_TYPE:-Unknown}"
        echo "Shell: $SHELL"
        echo ""
        echo "## Display Information"
        if command -v xrandr >/dev/null 2>&1; then
            echo "### X11 Displays"
            xrandr --listmonitors 2>/dev/null || true
        fi
        echo ""
        echo "## Installed Package Managers"
        for pm in pacman apt dnf zypper nix brew yay paru; do
            if command -v "$pm" >/dev/null 2>&1; then
                echo "- $pm: $(command -v "$pm")"
            fi
        done
        echo ""
        echo "## Environment Variables"
        env | grep -E "^(XDG_|QT_|GTK_|DESKTOP_|SESSION_)" | sort
        echo ""
        echo "## Backup Contents"
        find "$BACKUP_DIR" -type f | wc -l | xargs echo "Total files backed up:"
        du -sh "$BACKUP_DIR" | cut -f1 | xargs echo "Total size:"
    } > "$BACKUP_DIR/system-info.txt"
}

# Create restore script
create_restore_script() {
    log "Creating restore script..."

    cat > "$BACKUP_DIR/restore.sh" << 'EOF'
#!/bin/bash

# 🏠 here - Desktop State Restore Script
# Restore desktop environment, themes, and user settings

set -euo pipefail

BACKUP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY_RUN=${DRY_RUN:-0}

log() { echo -e "\033[0;32m[$(date +'%H:%M:%S')]\033[0m $*"; }
warn() { echo -e "\033[1;33m⚠️  [$(date +'%H:%M:%S')]\033[0m $*"; }
error() { echo -e "\033[0;31m❌ [$(date +'%H:%M:%S')]\033[0m $*"; }

restore_files() {
    local source_dir="$1"
    local target_dir="$2"
    local description="$3"

    if [[ ! -d "$source_dir" ]]; then
        warn "Backup directory $source_dir not found, skipping $description"
        return
    fi

    log "Restoring $description..."

    find "$source_dir" -type f | while read -r file; do
        rel_path="${file#$source_dir/}"
        target_file="$target_dir/$rel_path"
        target_parent="$(dirname "$target_file")"

        if [[ $DRY_RUN -eq 1 ]]; then
            echo "Would restore: $target_file"
        else
            mkdir -p "$target_parent"
            if [[ -f "$target_file" ]]; then
                cp "$target_file" "$target_file.backup-$(date +%s)" 2>/dev/null || true
            fi
            cp "$file" "$target_file"
        fi
    done
}

main() {
    log "🏠 here - Starting desktop restore from $BACKUP_DIR"

    if [[ $DRY_RUN -eq 1 ]]; then
        warn "DRY RUN MODE - No files will be modified"
    fi

    # Restore dotfiles
    restore_files "$BACKUP_DIR/dotfiles" "$HOME" "dotfiles"

    # Restore XDG configs
    restore_files "$BACKUP_DIR/configs" "$HOME/.config" "XDG configurations"

    # Restore themes
    restore_files "$BACKUP_DIR/themes" "$HOME" "themes and icons"

    # Restore fonts
    restore_files "$BACKUP_DIR/fonts" "$HOME" "fonts"

    # Restore keybindings
    restore_files "$BACKUP_DIR/keybindings" "$HOME" "keybindings"

    # Restore dconf settings
    if [[ -f "$BACKUP_DIR/desktop-environments/dconf-settings.conf" ]] && command -v dconf >/dev/null 2>&1; then
        log "Restoring dconf settings..."
        if [[ $DRY_RUN -eq 1 ]]; then
            echo "Would restore dconf settings"
        else
            dconf load / < "$BACKUP_DIR/desktop-environments/dconf-settings.conf" 2>/dev/null || warn "Failed to restore dconf settings"
        fi
    fi

    log "✅ Desktop restore completed!"
    log "💡 You may need to log out and back in for all changes to take effect"
    log "🔄 Run 'fc-cache -fv' to refresh font cache"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
EOF

    chmod +x "$BACKUP_DIR/restore.sh"
}

# Main backup function
main() {
    log "🏠 here - Starting comprehensive desktop backup..."

    setup_backup_dirs

    backup_dotfiles
    backup_xdg_configs
    backup_desktop_environments
    backup_themes
    backup_fonts
    backup_keybindings
    backup_browser_data

    create_system_info
    create_restore_script

    # Cleanup
    rm -rf "$TEMP_DIR"

    log "✅ Desktop backup completed successfully!"
    log "📁 Backup saved to: $BACKUP_DIR"
    log "🔄 To restore: cd '$BACKUP_DIR' && ./restore.sh"
    log "🧪 To test restore: DRY_RUN=1 ./restore.sh"

    # Show backup summary
    echo ""
    info "📊 Backup Summary:"
    find "$BACKUP_DIR" -type f | wc -l | xargs echo "  Files backed up:"
    du -sh "$BACKUP_DIR" | cut -f1 | xargs echo "  Total size:"

    # Integration with here tool
    if command -v here >/dev/null 2>&1; then
        echo ""
        info "💡 Tip: Combine with 'here export --include-config' for complete system migration"
    fi
}

# Handle command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -v|--verbose)
            VERBOSE=1
            shift
            ;;
        -h|--help)
            echo "🏠 here - Desktop State Backup Script"
            echo ""
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  -v, --verbose    Enable verbose output"
            echo "  -h, --help       Show this help message"
            echo ""
            echo "Environment variables:"
            echo "  VERBOSE=1        Enable verbose output"
            echo ""
            echo "The backup will be saved to ~/.here-backups/desktop-YYYYMMDD-HHMMSS"
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
