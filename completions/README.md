# Fish Shell Completions for `here`

This directory contains fish shell autocompletion support for the `here` universal package manager.

## Installation

### Automatic Installation

Run the installation script from the project root:

```bash
./install-completions.sh
```

### Manual Installation

1. Copy the completion file to your fish completions directory:
   ```bash
   cp completions/here.fish ~/.config/fish/completions/
   ```

2. Start a new fish shell session or reload completions:
   ```bash
   exec fish
   ```

## Features

The fish completions provide intelligent autocompletion for:

### Commands
- `here install` - Install packages
- `here search` - Search for packages
- `here remove` - Remove packages
- `here update` - Update all packages
- `here list` - List installed packages
- `here info` - Show package information
- `here export` - Create package export profile
- `here import` - Import and install packages from profile
- `here backup` - Smart file backup for migration
- `here version` - Show version information
- `here help` - Show help information

### Command Options

#### Export Command
- `--include-config` - Include dotfiles and configs in export
- Automatic `.json` file completion

#### Import Command
- `--interactive` - Use interactive TUI selection
- `--install-native` - Install only native packages
- `--install-flatpak` - Install only Flatpak packages
- `--install-appimage` - Install only AppImage packages
- `--install-all` - Install all packages (batch mode)
- Automatic `.json` profile file completion

#### Backup Command
- `-d` - Destination directory for backup
- Directory path completion

### Package Name Completions

The completions intelligently detect your system's package manager and provide package name suggestions for:

- **Arch Linux**: `yay` or `pacman` packages
- **Ubuntu/Debian**: `apt` packages
- **Fedora/RHEL**: `dnf` packages
- **openSUSE**: `zypper` packages
- **Flatpak**: Available Flatpak applications

### File Completions

- **JSON profiles**: Automatic completion for `.json` files when using `import` or `export`
- **Directories**: Path completion for backup operations
- **Suggested filenames**: Common profile names like `my-setup.json`, `system-backup.json`

## Usage Examples

Once installed, you can use TAB completion like this:

```bash
# Complete commands
here <TAB>
# Shows: install search remove update list info export import backup version help

# Complete import options
here import --<TAB>
# Shows: --interactive --install-native --install-flatpak --install-appimage --install-all

# Complete package names
here install fire<TAB>
# Shows: firefox firefox-developer-edition firefox-esr (etc.)

# Complete JSON files
here import <TAB>
# Shows: my-setup.json test-profile.json migration-profile.json (etc.)

# Complete export with config option
here export --include-config <TAB>
# Shows suggested filenames and existing .json files
```

## Troubleshooting

### Completions Not Working

1. **Check fish installation**: `fish --version`
2. **Verify completion file exists**: `ls ~/.config/fish/completions/here.fish`
3. **Restart fish shell**: `exec fish`
4. **Check here binary**: `which here`

### Package Name Completions Not Working

The completions automatically detect your package manager. If package name completion isn't working:

1. **Arch Linux**: Install `yay` or ensure `pacman` is available
2. **Ubuntu/Debian**: Ensure `apt` is available and cache is updated
3. **Fedora**: Ensure `dnf` is available
4. **openSUSE**: Ensure `zypper` is available

### Performance Issues

If completions are slow, the completion functions limit results to:
- 100 package names from system package managers
- 50 Flatpak applications
- 20 JSON files in current directory

## Contributing

To improve the completions:

1. Edit `completions/here.fish`
2. Test with: `fish -c "complete -C 'here '"`
3. Submit a pull request

## Requirements

- Fish shell 3.0+
- `here` binary installed and in PATH
- System package manager (for package name completions)

## License

Same as the main `here` project.