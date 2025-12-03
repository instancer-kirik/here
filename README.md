# 🏠 here - Universal Package Manager

> A smart, cross-platform package manager that speaks your system's language

**here** is a universal package manager written in Zig that automatically detects your system's package managers, sources, and version managers, then intelligently installs software using the best available method. No more remembering different commands for different systems – just use `here`.

## ✨ Features

- 🔍 **Auto-detection**: Automatically detects your system's package managers (pacman, apt, dnf, zypper, nix, etc.)
- 📦 **Multiple Sources**: Supports native packages, Flatpak, Snap, AppImage, and Nix
- 🧊 **AppImage Integration**: First-class AppImage support with GitHub releases and AppImageHub indexing
- 🔧 **Version Managers**: Integrates with asdf, mise, fnm, nvm, pyenv, rbenv, rustup
- ❄️ **Nix Integration**: First-class support for Nix with modern `nix profile` commands
- 🚀 **Smart Fallbacks**: Tries native packages first, falls back to Flatpak/Snap/Nix/AppImage when needed
- 🎯 **Intelligent Matching**: Maps package names to correct Flatpak IDs, Nix packages, and AppImage releases automatically  
- 💡 **Helpful Suggestions**: Recommends version managers, Nix shells, and AppImages for development tools
- 🌍 **Cross-platform**: Works on Arch, Ubuntu, Debian, Fedora, openSUSE, NixOS, macOS, and more

## 🚀 Quick Start

```bash
# Install a package
here install firefox

# Search for packages
here search python

# Remove packages
here remove bloatware

# Update all packages
here update

# List installed packages
here list

# Get package information
here info nodejs
```

## 📦 Installation

### Quick Install

#### One-liner Installation (Recommended)
```bash
curl -fsSL https://raw.githubusercontent.com/your-repo/here/main/install.sh | bash
```

#### Package Managers

##### Nix (Linux/macOS)
```bash
# Install from flake
nix profile install github:your-repo/here

# Or run directly without installing
nix run github:your-repo/here -- help

# Development environment
nix develop github:your-repo/here
```

##### Arch Linux (AUR)
```bash
# Using yay
yay -S here

# Using paru
paru -S here
```

##### Homebrew (macOS)
```bash
brew install your-repo/tap/here
```

### Pre-built Binaries

Download the latest release for your platform from the [releases page](releases).

#### Linux (x86_64)
```bash
curl -L https://github.com/your-repo/here/releases/latest/download/here-linux-x86_64 -o here
chmod +x here
sudo mv here /usr/local/bin/
```

#### Linux (aarch64)
```bash
curl -L https://github.com/your-repo/here/releases/latest/download/here-linux-aarch64 -o here
chmod +x here
sudo mv here /usr/local/bin/
```

#### macOS (Intel)
```bash
curl -L https://github.com/your-repo/here/releases/latest/download/here-macos-x86_64 -o here
chmod +x here
sudo mv here /usr/local/bin/
```

#### macOS (Apple Silicon)
```bash
curl -L https://github.com/your-repo/here/releases/latest/download/here-macos-aarch64 -o here
chmod +x here
sudo mv here /usr/local/bin/
```

### Build from Source

Requirements:
- [Zig](https://ziglang.org/) 0.12.1 or later

```bash
git clone https://github.com/your-repo/here.git
cd here
zig build -Doptimize=ReleaseFast
sudo cp zig-out/bin/here /usr/local/bin/
```

## 🎯 How It Works

**here** automatically detects your system and available package sources:

```bash
$ here install code
🔍 Detected Arch Linux with yay
📦 Package sources: native, flatpak
🔧 Version managers: asdf, rustup

🚀 Running: yay -S code
```

If the native package manager fails, **here** intelligently falls back to other sources:

```bash
$ here install discord
🔍 Detected Ubuntu with apt
📦 Package sources: native, flatpak, snap

❌ Native package not found
🔄 Trying Flatpak...
🎯 Found Flatpak match: com.discordapp.Discord
✅ Installed via Flatpak
```

## 📚 Commands

| Command | Description | Example |
|---------|-------------|---------|
| `install <packages...>` | Install one or more packages | `here install firefox git nodejs` |
| `search <term>` | Search for packages across all sources | `here search media player` |
| `remove <packages...>` | Remove packages | `here remove bloatware` |
| `update` | Update all packages | `here update` |
| `list` | List installed packages | `here list` |
| `info <package>` | Show package information | `here info python` |
| `help` | Show help information | `here help` |

## 🎨 Smart Features

### Development Tool Integration

**here** recognizes development tools and suggests appropriate version managers:

```bash
$ here install node
🤔 Detected development tool: node
💡 Consider using a version manager for better control:
   - fnm: fnm install node
   - nvm: nvm install node
   - asdf: asdf install nodejs latest
🤔 Continue with system package manager? [y/N]: 
```

### Intelligent Package Matching

When installing via Flatpak, **here** automatically maps common package names to Flatpak IDs:

- `discord` → `com.discordapp.Discord`
- `spotify` → `com.spotify.Client`
- `vscode` → `com.visualstudio.code`
- `gimp` → `org.gimp.GIMP`

### Smart Nix Integration

**here** provides first-class Nix support with intelligent package resolution:

```bash
# Automatic nixpkgs# prefixing for common packages
here install firefox  # → nix profile install nixpkgs#firefox
here install nodejs   # → nix profile install nixpkgs#nodejs

# Development environment suggestions
here install python   # Suggests: nix shell nixpkgs#python3
here install rust     # Suggests: nix shell nixpkgs#rustc nixpkgs#cargo

# Modern nix profile commands (not legacy nix-env)
here update           # → nix profile upgrade .*
here list             # → nix profile list
here remove firefox   # → nix profile remove firefox
```

**Why this matters:**
- **No more remembering**: `nix-env -iA` vs `nix profile install` vs `nix shell`
- **Smart fallbacks**: If system packages fail, automatically try Nix
- **Best practices**: Uses modern Nix commands and flake-based packages
- **Universal**: Same command works on NixOS, Linux, macOS, WSL

### AppImage Intelligence

**here** provides comprehensive AppImage support with automatic discovery:

```bash
# Search AppImageHub and GitHub releases
here search obsidian    # Finds AppImages across multiple sources

# Install popular AppImages with guided setup
here install obsidian   # → Downloads from obsidianmd/obsidian-releases
here install vscodium   # → Downloads from VSCodium/vscodium  
here install joplin     # → Downloads from laurent22/joplin

# Automatic integration
# - Downloads to ~/.local/bin
# - Makes executable automatically
# - Provides desktop integration guidance
```

**AppImage advantages:**
- **No root required**: Install without sudo
- **Portable**: Runs on any Linux distribution
- **Self-contained**: No dependency conflicts
- **GitHub integration**: Direct access to latest releases

### Cross-Distribution Compatibility

**here** works seamlessly across different Linux distributions:

| Distribution | Package Manager | Additional Sources |
|--------------|-----------------|-------------------|
| Arch Linux | pacman, yay, paru | AUR, Flatpak, AppImage, Nix |
| Ubuntu/Debian | apt | PPA, Flatpak, Snap, AppImage, Nix |
| Fedora | dnf | Flatpak, RPM Fusion, AppImage, Nix |
| openSUSE | zypper | Flatpak, OBS, AppImage, Nix |
| NixOS | nix | Nixpkgs, AppImage |
| macOS | homebrew | Nix, MacPorts |

## 🔧 Supported Systems

### Package Managers
- **pacman** (Arch Linux)
- **yay** / **paru** (AUR helpers)
- **apt** (Debian, Ubuntu, derivatives)
- **dnf** (Fedora, RHEL, CentOS)
- **zypper** (openSUSE)
- **nix** (NixOS, Linux, macOS) - Modern `nix profile` commands

### Package Sources
- **Native**: System package manager
- **Nix**: Functional package management (nixpkgs)
- **Flatpak**: Universal Linux packages
- **Snap**: Ubuntu's universal packages  
- **AppImage**: Portable applications with GitHub releases integration

### Version Managers
- **asdf**: Multi-language version manager
- **mise**: Modern replacement for asdf
- **fnm**: Fast Node.js version manager
- **nvm**: Node Version Manager
- **pyenv**: Python version manager
- **rbenv**: Ruby version manager
- **rustup**: Rust toolchain manager

## 📖 Examples

### Basic Usage

```bash
# Install popular applications
here install firefox chrome discord spotify

# Install development tools (with smart Nix integration)
here install git nodejs python rust

# Search across all sources including Nix and AppImage
here search "media player"

# Multiple source suggestions
here install nodejs    # Suggests: fnm, nvm, nix shell nixpkgs#nodejs
here install obsidian  # Suggests: AppImage from GitHub releases
```

### Development Workflow

```bash
# Install Node.js (will suggest version managers and Nix shells)
here install nodejs
# Suggestions: fnm, nvm, asdf, or nix shell nixpkgs#nodejs

# Install Python development tools
here install python python-pip

# Install Rust (will detect existing rustup or suggest Nix)  
here install rust
# Suggestions: rustup, or nix shell nixpkgs#rustc nixpkgs#cargo

# Install GUI applications (AppImage preferred for portability)
here install vscodium  # Installs VSCodium AppImage
here install joplin    # Installs Joplin AppImage with desktop integration
```

### System Maintenance

```bash
# Update all packages
here update

# List installed packages
here list

# Remove unused packages
here remove old-package
```

## 🐛 Troubleshooting

### Package Not Found

If **here** can't find a package:

1. Try searching first: `here search packagename`
2. Check alternative package names
3. Package might only be available in specific sources (AUR, Flatpak, etc.)

### Permission Issues

If you get permission errors:

```bash
# Make sure here is executable
chmod +x /usr/local/bin/here

# For system packages, you might need sudo privileges
# here will prompt for sudo when needed
```

### Build Issues

If building from source fails:

1. Ensure you have Zig 0.12.1 or later: `zig version`
2. Update Zig: See [Zig installation guide](https://ziglang.org/learn/getting-started/#installing-zig)
3. Clean build: `rm -rf zig-cache zig-out && zig build`

## 💖 Support the Project

If **here** has saved you time and made your life easier, consider supporting its development:

**Ethereum/Base**: `0xaf462cef9e8913a9cb7b6f0ba0ddf5d733eae57a`

Your support helps fund:
- 🔧 **New package manager integrations**
- 🌍 **Cross-platform compatibility improvements**  
- 🚀 **Performance optimizations and new features**
- 📚 **Documentation and community support**

## 🤝 Contributing

We welcome contributions! Here's how to help:

1. **Report Issues**: Found a bug or missing package manager? [Open an issue](issues)
2. **Add Support**: Help us support more package managers and distributions
3. **Improve Detection**: Make package detection smarter and more reliable
4. **Documentation**: Help improve docs and examples

### Development Setup

#### With Nix (Recommended)
```bash
git clone https://github.com/your-repo/here.git
cd here

# Enter development shell
nix develop

# Or with direnv (auto-loads environment)
echo "use flake" > .envrc
direnv allow
```

#### Manual Setup
```bash
git clone https://github.com/your-repo/here.git
cd here

# Install Zig 0.12.1+
# See: https://ziglang.org/learn/getting-started/

# Build and test
zig build        # Debug build
zig build test   # Run tests
zig run src/main.zig -- help  # Test run
```

### Adding Package Manager Support

1. Add detection logic to `detectPackageManager()` 
2. Add command building logic to `buildCommand()`
3. Update `PackageManager` enum and `toString()` method
4. Add tests and documentation

## 📄 License

MIT License - see [LICENSE](LICENSE) for details.

## 🙏 Acknowledgments

- Built for users tired of remembering different package manager commands
- Inspired by the need for universal package management
- Thanks to all the package manager and version manager maintainers
- Special thanks to supporters who help fund development

---

**"Why remember a dozen commands when one will do?"** 🏠

**Support development**: `0xaf462cef9e8913a9cb7b6f0ba0ddf5d733eae57a` (ETH/Base)