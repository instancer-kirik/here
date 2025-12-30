# 🏠 here - Manual Landing Page Setup

If you prefer to set up the Findry landing page manually rather than importing JSON, here's a step-by-step guide.

## 🚀 Step-by-Step Setup

### 1. Create Project in Findry
1. Go to https://findry.com
2. Click "New Project"
3. Fill out basic info:
   - **Name**: `here - Universal Package Manager`
   - **Description**: `Cross-platform package manager with desktop migration tools`
   - **Category**: `Developer Tools`
   - **Tags**: `package-manager`, `linux`, `macos`, `migration`, `zig`
   - **Repository**: `https://github.com/instancer-kirik/here`

### 2. Enable Landing Page
1. Click "Create Landing" button in your project
2. Choose **"Technical Theme"**

### 3. Configure Hero Section
- **Hero Title**: `$ here install anything`
- **Hero Subtitle**: `Universal package manager that speaks every system's language. One tool to rule them all: native packages, Flatpak, AppImage, Nix, and version managers.`
- **Hero Image URL**: `https://images.unsplash.com/photo-1629654297299-c8506221ca97?w=1920&h=1080&fit=crop`
- **Call to Action Text**: `Install here`
- **CTA Link**: `https://github.com/instancer-kirik/here#installation`

### 4. Add Sections (in order)

#### Section 1: Quick Start
- **Type**: Text
- **Title**: `> Quick Start`
- **Content**:
```
# Install here
curl -fsSL https://raw.githubusercontent.com/instancer-kirik/here/main/install.sh | bash

# Use anywhere
here install firefox        # Finds best source automatically
here search python         # Cross-platform search
here update                 # Update everything

# System migration
here export my-system.json  # Backup your setup
here import my-system.json  # Restore on new machine

Zero configuration. Works on **any Linux distro + macOS**. Start using in **30 seconds**.
```

#### Section 2: Features
- **Type**: Features
- **Title**: `// Core Features`
- (This will auto-populate from your project components)

#### Section 3: System Support
- **Type**: Text  
- **Title**: `⚡ Universal Compatibility`
- **Content**:
```
**📦 Package Managers**
- pacman (Arch/Manjaro)
- apt (Ubuntu/Debian)  
- dnf (Fedora/RHEL)
- zypper (openSUSE)
- nix (NixOS/any)
- brew (macOS/Linux)
- yay/paru (AUR)

**🧊 App Formats**
- Native packages
- Flatpak
- Snap
- AppImage (2500+ apps)
- Nix packages
- Direct downloads

**🔧 Version Managers**
- asdf • mise
- rustup • cargo
- npm • yarn • bun
- pyenv • pip
- rbenv • gem
- zigup
```

#### Section 4: Migration Tools
- **Type**: Text
- **Title**: `🏠 Complete System Migration`
- **Content**:
```
Beyond package management - `here` includes enterprise-grade desktop migration tools:

# Complete system backup
./migrate-system.sh

# Desktop environment backup
./backup-desktop-state.sh

# Theme and customization backup
./backup-cachyos-themes.sh

**📁 Dotfiles & Configs**: Backup shell configs, editor settings, SSH keys, Git config

**🎨 Themes & Appearance**: GTK themes, icon themes, wallpapers, fonts, cursor themes

**🖥️ Desktop Environments**: GNOME, KDE, XFCE, Cinnamon, Awesome WM settings

**🔄 One-Command Restore**: Portable migration packages with automatic restore scripts
```

#### Section 5: Statistics
- **Type**: Text
- **Title**: `📊 By the Numbers`
- **Content**:
```
**2500+** AppImage apps via AppMan integration
**10+** Package managers supported  
**12+** Version managers integrated
**< 50ms** Average command execution
**385** Packages in test profile (real system)
**1.0.0** Production ready
```

### 5. Configure Social Links
- **GitHub**: `https://github.com/instancer-kirik/here` (Label: "View Source")
- **Website**: `https://github.com/instancer-kirik/here/releases` (Label: "Download")

### 6. Customize Colors
- **Background Color**: `#0a0a0a`
- **Text Color**: `#e5e5e5`  
- **Accent Color**: `#00d4aa`

### 7. Add Custom CSS (Optional)
If your Findry plan supports custom CSS, add this for enhanced styling:

```css
.hero-title { 
  font-family: 'JetBrains Mono', monospace; 
  text-shadow: 0 0 20px rgba(0, 212, 170, 0.3);
}

.cta-button { 
  background: linear-gradient(135deg, #00d4aa 0%, #00f5cc 100%);
  font-family: 'JetBrains Mono', monospace;
}

.cta-button:hover {
  box-shadow: 0 10px 25px rgba(0, 212, 170, 0.4);
  transform: translateY(-3px);
}

pre code {
  background: #111111;
  border: 1px solid rgba(0, 212, 170, 0.2);
  border-radius: 8px;
  padding: 1.5rem;
  font-size: 0.85rem;
  line-height: 1.6;
}

body {
  background: linear-gradient(135deg, #0a0a0a 0%, #1a1a1a 100%);
}
```

### 8. Preview & Publish
1. Use the preview feature to check your landing page
2. Make sure project visibility is set to **Public**
3. Save your configuration
4. Your landing page will be live at:
   `https://findry.com/projects/YOUR_PROJECT_ID/landing`

## 🎯 Key Features of This Setup

- **Terminal aesthetic** with JetBrains Mono font
- **Dark theme** optimized for developers
- **Code examples** showing real usage
- **Comprehensive feature showcase**
- **Migration tools highlight**
- **Real statistics** from your project
- **Mobile responsive** design

## 📱 Mobile Optimization

The technical theme automatically handles mobile responsiveness, but ensure you:
- Test on various screen sizes
- Keep text readable on small screens  
- Make sure CTAs are touch-friendly
- Verify code blocks display properly

## 🚀 Launch Tips

- Share your landing page URL on social media
- Include the link in your GitHub README
- Add it to your email signature
- Submit to developer tool directories
- Share in relevant communities (Reddit, Discord, etc.)

Your professional landing page will showcase `here` as a serious developer tool! 🎉