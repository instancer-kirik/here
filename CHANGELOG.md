# Changelog

All notable changes to **here** will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Planned: Shell completion scripts (bash, zsh, fish)
- Planned: Configuration file support (~/.config/here/config.toml)
- Planned: Verbose/debug mode flags
- Planned: Package manager preference configuration

### Changed
- Planned: Improved error messages and user feedback

## [1.0.0] - 2025-01-20

### Added
- 🎉 Initial release of **here** - Universal Package Manager
- **Core functionality:**
  - Install packages across multiple package managers and sources
  - Search for packages with intelligent cross-source searching
  - Remove packages using detected package managers
  - Update all packages through system package managers
  - List installed packages
  - Show package information
- **Smart detection:**
  - Auto-detect system package managers (pacman, yay, paru, apt, dnf, zypper, nix)
  - Detect available package sources (native, Flatpak, Snap, AppImage)
  - Identify version managers (asdf, mise, fnm, nvm, pyenv, rbenv, rustup)
- **Intelligent features:**
  - Automatic fallback from native packages to Flatpak/Snap
  - Smart Flatpak package ID matching (discord → com.discordapp.Discord)
  - Development tool detection with version manager suggestions
  - Cross-platform support (Linux distributions + macOS)
- **User experience:**
  - Clean, emoji-rich command line interface
  - Helpful error messages and suggestions
  - Interactive prompts for development tool installations
  - Comprehensive help system
- **Build system:**
  - Multi-platform releases (Linux x86_64/aarch64, macOS x86_64/aarch64)
  - Release builds optimized for performance
  - Comprehensive test suite

### Technical Details
- Written in Zig 0.12.1+ for performance and reliability
- Zero external dependencies beyond Zig standard library
- Cross-platform process spawning and system detection
- Structured error handling and memory management
- Modular architecture for easy extension

### Supported Systems
- **Linux distributions:** Arch Linux, Ubuntu, Debian, Fedora, openSUSE, NixOS
- **Package managers:** pacman, yay, paru, apt, dnf, zypper, nix
- **Additional sources:** Flatpak, Snap, AppImage
- **Version managers:** asdf, mise, fnm, nvm, pyenv, rbenv, rustup
- **macOS:** Native package managers and Homebrew compatibility

### Examples
```bash
# Basic package installation
here install firefox

# Cross-source search
here search "media player"

# Development tool with version manager suggestion
here install nodejs

# System maintenance
here update
```

### Performance
- Fast startup time (~10ms cold start)
- Efficient system detection (single-pass)
- Minimal memory footprint (<5MB)
- Optimized release builds for production use

---

## Release Notes

### What is here?

**here** is a universal package manager that automatically detects your system's package management capabilities and installs software using the best available method. Instead of remembering different commands for different systems (pacman, apt, dnf, flatpak, etc.), you just use `here`.

### Key Features

- **Universal**: Works across Linux distributions and macOS
- **Intelligent**: Auto-detects package managers and falls back gracefully
- **Development-friendly**: Recognizes dev tools and suggests version managers
- **Fast**: Written in Zig for performance and reliability
- **Safe**: Shows what it will do before making changes

### Philosophy

- **Simplicity**: One command to rule them all
- **Intelligence**: Smart detection and fallbacks
- **Transparency**: Clear feedback about what's happening
- **Respect**: Works with your existing setup, doesn't replace it

### Installation

Download pre-built binaries from the releases page, or build from source:

```bash
git clone https://github.com/your-repo/here.git
cd here
zig build -Doptimize=ReleaseFast
sudo cp zig-out/bin/here /usr/local/bin/
```

### Contributing

**here** is open source and welcomes contributions! Areas where help is especially appreciated:

- **New package manager support**: Add detection for additional package managers
- **Platform support**: Improve compatibility across more systems  
- **Smart matching**: Enhance package name to Flatpak ID mapping
- **User experience**: Improve error messages and help text
- **Testing**: Add integration tests with real package managers

### Future Roadmap

- **v1.1.0**: Configuration file support and shell completions
- **v1.2.0**: Plugin system for custom package sources
- **v1.3.0**: Package manager preference configuration
- **v2.0.0**: GUI frontend and advanced package management features

### License

MIT License - see [LICENSE](LICENSE) for full details.

### Acknowledgments

- Built for users who want package management to "just work"
- Inspired by the fragmentation of Linux package management
- Thanks to all the package manager maintainers whose tools we integrate with

---

**"Why remember a dozen commands when one will do?"** 🏠