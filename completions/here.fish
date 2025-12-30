# Fish shell completions for here - Universal package manager
# Save this file to ~/.config/fish/completions/here.fish

# Main commands
complete -c here -f -n '__fish_use_subcommand' -a 'install' -d 'Install packages'
complete -c here -f -n '__fish_use_subcommand' -a 'search' -d 'Search for packages'
complete -c here -f -n '__fish_use_subcommand' -a 'remove' -d 'Remove packages'
complete -c here -f -n '__fish_use_subcommand' -a 'update' -d 'Update all packages'
complete -c here -f -n '__fish_use_subcommand' -a 'list' -d 'List installed packages'
complete -c here -f -n '__fish_use_subcommand' -a 'info' -d 'Show package information'
complete -c here -f -n '__fish_use_subcommand' -a 'export' -d 'Create package export profile for migration'
complete -c here -f -n '__fish_use_subcommand' -a 'import' -d 'Import and install packages from profile'
complete -c here -f -n '__fish_use_subcommand' -a 'backup' -d 'Smart file backup for migration'
complete -c here -f -n '__fish_use_subcommand' -a 'version' -d 'Show version information'
complete -c here -f -n '__fish_use_subcommand' -a 'help' -d 'Show help information'

# Export command options
complete -c here -f -n '__fish_seen_subcommand_from export' -l include-config -d 'Include dotfiles and configs in export'
complete -c here -F -n '__fish_seen_subcommand_from export' -a '*.json' -d 'JSON profile file'

# Import command options
complete -c here -f -n '__fish_seen_subcommand_from import' -l interactive -d 'Use interactive TUI selection'
complete -c here -f -n '__fish_seen_subcommand_from import' -l install-native -d 'Install only native packages'
complete -c here -f -n '__fish_seen_subcommand_from import' -l install-flatpak -d 'Install only Flatpak packages'
complete -c here -f -n '__fish_seen_subcommand_from import' -l install-appimage -d 'Install only AppImage packages'
complete -c here -f -n '__fish_seen_subcommand_from import' -l install-all -d 'Install all packages (batch mode)'
complete -c here -F -n '__fish_seen_subcommand_from import' -a '*.json' -d 'JSON profile file'

# Backup command options
complete -c here -f -n '__fish_seen_subcommand_from backup' -s d -d 'Destination directory for backup'
complete -c here -F -n '__fish_seen_subcommand_from backup'

# File completions for JSON profiles
complete -c here -F -n '__fish_seen_subcommand_from export import' -a '(find . -name "*.json" 2>/dev/null | head -20)'

# Package name completions for install/remove/info commands
# Try to get package suggestions from the system package manager
function __here_complete_packages
    # Try different package managers based on availability
    if command -q yay
        yay -Ssq 2>/dev/null | head -100
    else if command -q pacman
        pacman -Ssq 2>/dev/null | head -100
    else if command -q apt
        apt-cache pkgnames 2>/dev/null | head -100
    else if command -q dnf
        dnf list available 2>/dev/null | awk '{print $1}' | head -100
    else if command -q zypper
        zypper search 2>/dev/null | awk '{print $1}' | head -100
    end
end

complete -c here -f -n '__fish_seen_subcommand_from install remove info' -a '(__here_complete_packages)' -d 'Package name'

# Flatpak completions for install command
function __here_complete_flatpaks
    if command -q flatpak
        flatpak remote-ls 2>/dev/null | awk '{print $1}' | head -50
    end
end

complete -c here -f -n '__fish_seen_subcommand_from install' -a '(__here_complete_flatpaks)' -d 'Flatpak application'

# Directory completions for backup source
complete -c here -F -n '__fish_seen_subcommand_from backup' -d 'Source directory'

# Common JSON profile files in current directory
complete -c here -f -n '__fish_seen_subcommand_from import export' -a '(find . -maxdepth 1 -name "*.json" -type f 2>/dev/null | sed "s|./||")' -d 'Profile file'

# Suggested profile filenames for export
complete -c here -f -n '__fish_seen_subcommand_from export' -a 'my-setup.json system-backup.json migration-profile.json' -d 'Suggested filename'

# Help topics (no arguments needed but show available)
complete -c here -f -n '__fish_seen_subcommand_from help'

# Version command (no arguments)
complete -c here -f -n '__fish_seen_subcommand_from version'

# Update command (no arguments)
complete -c here -f -n '__fish_seen_subcommand_from update'

# List command (no arguments)
complete -c here -f -n '__fish_seen_subcommand_from list'
