#!/bin/bash

# Migration Prep Shell Wrapper
# Convenient interface for the migration prep Python script

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON_SCRIPT="$SCRIPT_DIR/migration_prep.py"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print colored output
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

show_help() {
    cat << EOF
Migration Prep Tool - Home Directory Backup for Migration

USAGE:
    $0 [COMMAND] [OPTIONS]

COMMANDS:
    home                    Backup entire home directory
    code                    Backup code directories only
    config                  Backup config files and dotfiles only
    custom <source> <dest>  Custom backup with source and destination
    dry-run <source>        Show what would be backed up (no actual copying)
    help                    Show this help message

EXAMPLES:
    $0 home                                 # Backup ~/to ~/migration-backup-YYYYMMDD
    $0 code                                 # Backup ~/Code to ~/code-backup-YYYYMMDD
    $0 config                              # Backup config files to ~/config-backup-YYYYMMDD
    $0 custom ~/Documents ~/backup/docs    # Custom source and destination
    $0 dry-run ~                          # Preview what would be backed up from home

OPTIONS:
    -v, --verbose          Verbose output
    -d, --destination DIR  Override default destination directory
    -n, --dry-run         Preview mode (show what would be copied)
    -h, --help            Show this help

The tool automatically skips:
- Build artifacts (node_modules, __pycache__, target/, dist/, etc.)
- Cache directories (.cache, .npm, .yarn, etc.)
- Temporary files (*.tmp, *.cache, *.log, etc.)
- Version control internals (.git/, .svn/, etc.)
- Virtual environments (.venv, venv/, env/)

The tool preserves:
- Configuration files (.bashrc, .vimrc, config.*, etc.)
- Environment files (.env*, environment.*)
- SSH keys and config (.ssh/)
- Important project files (package.json, requirements.txt, etc.)
- Documentation (README.md, *.rst, etc.)
- License files

EOF
}

# Get timestamp for backup directory naming
get_timestamp() {
    date +%Y%m%d_%H%M%S
}

# Check if Python script exists
check_python_script() {
    if [[ ! -f "$PYTHON_SCRIPT" ]]; then
        print_error "Python script not found: $PYTHON_SCRIPT"
        exit 1
    fi
}

# Parse arguments (deprecated - now handled in main)
parse_args() {
    # This function is no longer used but kept for compatibility
    return 0
}

# Build Python command with options
build_python_cmd() {
    local source="$1"
    local dest="$2"

    cmd="python3 $PYTHON_SCRIPT"

    if [[ "$VERBOSE" == true ]]; then
        cmd="$cmd --verbose"
    fi

    if [[ "$DRY_RUN" == true ]]; then
        cmd="$cmd --dry-run"
    fi

    cmd="$cmd '$source' '$dest'"
    echo "$cmd"
}

# Execute backup command
execute_backup() {
    local source="$1"
    local dest="$2"

    print_info "Source: $source"
    print_info "Destination: $dest"

    if [[ ! -d "$source" ]]; then
        print_error "Source directory does not exist: $source"
        exit 1
    fi

    # Create destination parent directory if needed
    if [[ ! "$DRY_RUN" == true ]]; then
        mkdir -p "$(dirname "$dest")"
    fi

    # Execute the backup
    cmd=$(build_python_cmd "$source" "$dest")
    print_info "Executing: $cmd"

    eval "$cmd"

    if [[ $? -eq 0 && ! "$DRY_RUN" == true ]]; then
        print_success "Backup completed successfully!"
        print_info "Backup saved to: $dest"
    fi
}

# Main command handling
main() {
    check_python_script

    VERBOSE=false
    DRY_RUN=false
    CUSTOM_DEST=""

    # Parse all arguments to find flags
    local args=()
    while [[ $# -gt 0 ]]; do
        case $1 in
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -d|--destination)
                CUSTOM_DEST="$2"
                shift 2
                ;;
            -n|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                args+=("$1")
                shift
                ;;
        esac
    done

    # Restore non-flag arguments
    set -- "${args[@]}"

    if [[ $# -eq 0 ]]; then
        show_help
        exit 1
    fi

    local command="$1"
    local timestamp=$(get_timestamp)

    case "$command" in
        home)
            local dest="${CUSTOM_DEST:-$HOME/migration-backup-$timestamp}"
            execute_backup "$HOME" "$dest"
            ;;
        code)
            local code_dir="$HOME/Code"
            if [[ ! -d "$code_dir" ]]; then
                code_dir="$HOME/code"
            fi
            if [[ ! -d "$code_dir" ]]; then
                print_error "No Code directory found in $HOME/Code or $HOME/code"
                exit 1
            fi
            local dest="${CUSTOM_DEST:-$HOME/code-backup-$timestamp}"
            execute_backup "$code_dir" "$dest"
            ;;
        config)
            local temp_dir="/tmp/config-staging-$$"
            local dest="${CUSTOM_DEST:-$HOME/config-backup-$timestamp}"

            print_info "Creating staged config backup..."
            mkdir -p "$temp_dir"

            # Copy important config directories and files
            config_items=(
                ".ssh"
                ".gnupg"
                ".config"
                ".local/share"
                ".bashrc"
                ".zshrc"
                ".profile"
                ".bash_profile"
                ".vimrc"
                ".tmux.conf"
                ".gitconfig"
                ".gitignore_global"
                ".inputrc"
                ".screenrc"
                ".aws"
                ".docker"
                ".kube"
                ".npmrc"
                ".yarnrc"
                ".pip"
                ".poetry"
                ".cargo/config.toml"
                ".rustup/settings.toml"
            )

            for item in "${config_items[@]}"; do
                if [[ -e "$HOME/$item" ]]; then
                    print_info "Staging $item..."
                    mkdir -p "$temp_dir/$(dirname "$item")"
                    cp -r "$HOME/$item" "$temp_dir/$item" 2>/dev/null || true
                fi
            done

            execute_backup "$temp_dir" "$dest"
            rm -rf "$temp_dir"
            ;;
        custom)
            if [[ $# -lt 3 ]]; then
                print_error "Custom backup requires source and destination"
                print_info "Usage: $0 custom <source> <destination>"
                exit 1
            fi
            execute_backup "$2" "$3"
            ;;
        dry-run)
            if [[ $# -lt 2 ]]; then
                print_error "Dry run requires source directory"
                print_info "Usage: $0 dry-run <source>"
                exit 1
            fi
            DRY_RUN=true
            local temp_dest="/tmp/migration-preview"
            execute_backup "$2" "$temp_dest"
            ;;
        help)
            show_help
            ;;
        *)
            print_error "Unknown command: $command"
            show_help
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"
