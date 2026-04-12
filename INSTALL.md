# 🏠 here - Installation Guide

**here** is a universal package manager that works when your regular package managers don't. Since it's designed to fix package management issues, it shouldn't depend on package managers to install!

## 🚀 Quick Install (Recommended)

### One-Line Installer (Linux/macOS)
```bash
curl -fsSL https://instance.select/here | bash
```

Or with wget:
```bash
wget -qO- https://instance.select/here | bash
```

This installer:
- ✅ Auto-detects your platform (Linux x86_64/ARM64, macOS Intel/Apple Silicon)
- ✅ Downloads the latest release binary
- ✅ Installs to `/usr/local/bin/here` (in your PATH)
- ✅ Verifies the installation works
- ✅ Requires no dependencies

### Custom Installation Directory
```bash
curl -fsSL https://instance.select/here | bash -s -- --dir ~/.local/bin
```

---

## 📦 Manual Installation

### 1. Download Pre-Built Binaries

Choose your platform and download from [Codeberg Releases](https://codeberg.org/OverHereEnterprise/here/releases):

**Linux:**
```bash
# x86_64
wget https://codeberg.org/OverHereEnterprise/here/releases/download/v1.1.0/here-x86_64-linux
chmod +x here-x86_64-linux
sudo mv here-x86_64-linux /usr/local/bin/here

# ARM64
wget https://codeberg.org/OverHereEnterprise/here/releases/download/v1.1.0/here-aarch64-linux
chmod +x here-aarch64-linux
sudo mv here-aarch64-linux /usr/local/bin/here
```

**macOS:**
```bash
# Intel
wget https://codeberg.org/OverHereEnterprise/here/releases/download/v1.1.0/here-x86_64-macos
chmod +x here-x86_64-macos
sudo mv here-x86_64-macos /usr/local/bin/here

# Apple Silicon
wget https://codeberg.org/OverHereEnterprise/here/releases/download/v1.1.0/here-aarch64-macos
chmod +x here-aarch64-macos
sudo mv here-aarch64-macos /usr/local/bin/here
```

### 2. Verify Installation
```bash
here version
here help
```

---

## 🗂️ AppImage (Portable Linux)

For a completely portable installation that works anywhere:

```bash
# Download AppImage
wget https://codeberg.org/OverHereEnterprise/here/releases/download/v1.1.0/here-1.1.0-x86_64.AppImage
chmod +x here-1.1.0-x86_64.AppImage

# Run directly
./here-1.1.0-x86_64.AppImage version
./here-1.1.0-x86_64.AppImage search firefox

# Optional: Add to PATH
sudo mv here-1.1.0-x86_64.AppImage /usr/local/bin/here
```

**AppImage Benefits:**
- ✅ Works on any Linux distribution
- ✅ No installation required
- ✅ Self-contained (no dependencies)
- ✅ Can run from USB drives
- ✅ Perfect for rescue scenarios

---

## 🔧 Build from Source

If you want to build from source or contribute:

### Prerequisites
- [Zig 0.15.0+](https://ziglang.org/download/)
- Git

### Build Steps
```bash
# Clone repository
git clone https://codeberg.org/OverHereEnterprise/here.git
cd here

# Build optimized release
zig build -Doptimize=ReleaseFast

# Install
sudo cp zig-out/bin/here /usr/local/bin/

# Or build for all platforms
zig build release
```

### Build AppImage
```bash
./build-appimage.sh
```

---

## 🐳 Container Usage

Run **here** in a container environment:

```bash
# Docker
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
  codeberg.org/overhere-enterprise/here:latest version

# Podman
podman run --rm codeberg.org/overhere-enterprise/here:latest help
```

---

## 📦 Package Managers (Coming Soon)

We're working on getting **here** into official repositories:

### Arch Linux (AUR)
```bash
# Coming soon
yay -S here-bin
```

### Homebrew (macOS)
```bash
# Coming soon
brew install here
```

### Debian/Ubuntu
```bash
# Coming soon
sudo apt install here
```

---

## ✅ Verification

After installation, verify **here** is working:

```bash
# Check version
here version

# Test system detection
here search --help

# Try a search (safe, no installation)
here search firefox
```

Expected output:
```
🔍 Detected [Your Distro] with [Your Package Manager]
📦 Package sources: native, flatpak, appimage
🔧 Version managers: npm, cargo, pip
```

---

## 🔄 Updates

### Update via Install Script
```bash
curl -fsSL https://instance.select/here | bash
```

### Manual Update
1. Download the latest binary from [releases](https://codeberg.org/OverHereEnterprise/here/releases)
2. Replace your existing binary
3. Verify with `here version`

---

## 🗑️ Uninstall

### Quick Uninstall
```bash
curl -fsSL https://instance.select/here | bash -s -- uninstall
```

### Manual Uninstall
```bash
sudo rm /usr/local/bin/here
```

---

## 🆘 Troubleshooting

### Permission Denied
```bash
# If you get permission denied during installation:
curl -fsSL https://instance.select/here | sudo bash
```

### Binary Not Found After Install
```bash
# Check if /usr/local/bin is in your PATH
echo $PATH

# Add to PATH if missing (add to ~/.bashrc or ~/.zshrc)
export PATH="/usr/local/bin:$PATH"
```

### AppImage Won't Run
```bash
# Install FUSE (required for AppImages)
# Ubuntu/Debian:
sudo apt install fuse

# Fedora:
sudo dnf install fuse

# Or extract and run without FUSE:
./here-1.1.0-x86_64.AppImage --appimage-extract
./squashfs-root/AppRun version
```

### Still Having Issues?

1. Check our [Codeberg Issues](https://codeberg.org/OverHereEnterprise/here/issues)
2. Join our [Discussions](https://codeberg.org/OverHereEnterprise/here/issues)
3. Read the [troubleshooting guide](./README.md#troubleshooting)

---

## 💡 Why These Installation Methods?

**here** is designed to work when package managers are broken or missing:

- **Clean domain**: `curl instance.select/here` - easy to remember
- **Curl installer**: Works when `apt`/`pacman`/`dnf` are broken
- **Static binaries**: No dependencies, work anywhere
- **AppImage**: Portable, perfect for rescue USB drives
- **No package manager dependencies**: Breaks the chicken-and-egg problem

---

## 💖 Support Development

If **here** saves you time and makes package management easier:

**Ethereum/Base**: `0xaf462cef9e8913a9cb7b6f0ba0ddf5d733eae57a`

Your support helps fund:
- 🔧 New package manager integrations
- 🌍 Cross-platform compatibility improvements
- 🚀 Performance optimizations and features
- 📚 Documentation and community support

---

**"Why remember a dozen commands when one will do?"** 🏠