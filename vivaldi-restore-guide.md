# 🏠 Vivaldi Browser Data Restoration Guide

## 🎯 Quick Start

Your backup contains **Cachy Browser** (Firefox) data, not Vivaldi data. But don't worry! You can restore everything manually using Vivaldi's import features and extension store.

## 📚 What You Had (From Backup Analysis)

### 🧩 Extensions Found in Your Backup:
- **uBlock Origin** v1.63.2 - Content blocker (ad/tracker blocking)
- **Dark Reader** v4.9.106 - Dark mode for websites
- **Bitwarden Password Manager** v2025.4.0 - Password manager
- **Catppuccin Mocha - Blue** v2.0 - Firefox theme (won't work in Vivaldi)

### 📁 Bookmarks Location:
- **Latest Backup**: `/run/media/bon/MainStorage/MAIN_SWAP/home-backup/.cachy/5aa1tbhk.default-release/bookmarkbackups/bookmarks-2025-05-15_7_*.jsonlz4`
- **Extensions Backup**: `/run/media/bon/MainStorage/MAIN_SWAP/home-backup/.cachy/5aa1tbhk.default-release/extensions/`

## 🔧 Step-by-Step Restoration

### 1. 📖 Import Bookmarks

#### Method A: Direct Firefox Import (Recommended)
1. Open Vivaldi
2. Go to **Vivaldi Menu** → **Bookmarks** → **Import Bookmarks and Settings**
3. Choose **"From Firefox"** as the source
4. Select the backup profile directory: `/run/media/bon/MainStorage/MAIN_SWAP/home-backup/.cachy/5aa1tbhk.default-release/`
5. Click **Import** - this should import all your bookmarks automatically

#### Method B: Manual HTML Export (If Method A fails)
1. Install Firefox temporarily: `yay -S firefox`
2. Create a new Firefox profile pointing to your backup
3. Export bookmarks as HTML from Firefox
4. Import the HTML file into Vivaldi

### 2. 🧩 Install Extensions

Visit the **Chrome Web Store** (Vivaldi uses Chrome extensions) and install:

#### Essential Extensions from Your Backup:

**🛡️ uBlock Origin**
- URL: https://chrome.google.com/webstore/detail/ublock-origin/cjpalhdlnbpafiamejdnhcphjbkeiagm
- Your version was: v1.63.2
- Purpose: Ad/tracker blocking (Essential for privacy)

**🌙 Dark Reader**
- URL: https://chrome.google.com/webstore/detail/dark-reader/eimadpbcbfnmbkopoojfekhnkhdbieeh
- Your version was: v4.9.106  
- Purpose: Dark mode for all websites

**🔐 Bitwarden Password Manager**
- URL: https://chrome.google.com/webstore/detail/bitwarden-password-manager/nngceckbapebfimnlniiiahkandclblb
- Your version was: v2025.4.0
- Purpose: Password management (Very Important!)

#### Installation Steps:
1. Open Vivaldi
2. Go to **Settings** → **Extensions** (or type `vivaldi://extensions/`)
3. Enable **"Developer mode"** (toggle in top right)
4. Visit the Chrome Web Store links above
5. Click **"Add to Chrome"** for each extension
6. Configure each extension with your previous settings

### 3. 🎨 Vivaldi Appearance & Theme

Your backup had **Catppuccin Mocha - Blue** theme for Firefox. For Vivaldi:

#### Built-in Theming:
1. Go to **Settings** → **Appearance**
2. Choose **Dark** theme
3. Customize accent colors to match your preference
4. Try the built-in **"Catppuccin"** theme if available

#### Custom Themes:
- Check Vivaldi's theme gallery: https://themes.vivaldi.net/
- Look for Catppuccin-inspired themes
- Or create your own custom theme

### 4. ⚙️ Configure Vivaldi Settings

#### Enable Built-in Features (Reduce Extension Needs):
1. **Ad Blocker**: Settings → Privacy & Security → **Enable Tracker and Ad Blocker**
2. **Translation**: Enable built-in translation
3. **Screenshots**: Use built-in capture tools
4. **Notes**: Enable side panel notes
5. **Tab Management**: Set up workspaces and tab stacking

#### Privacy Settings:
1. Settings → Privacy & Security
2. Enable **"Do Not Track"**
3. Configure **Tracker and Ad Blocker** (similar to uBlock Origin)
4. Set up **Search Engine** preferences

### 5. 🔗 Sync Setup (Optional)

If you want to keep your data synced:
1. Create a **Vivaldi Account** at vivaldi.com
2. Go to **Settings** → **Sync**
3. Enable syncing for: Bookmarks, Extensions, Settings, History

## 🚨 Important Notes

### ⚠️ Extension Data Recovery
- **Bitwarden**: Log in with your account to restore all passwords
- **uBlock Origin**: Will use default filter lists (your custom rules are lost)
- **Dark Reader**: Will reset to defaults (you'll need to reconfigure sites)

### 🔄 If Import Fails
If bookmark import doesn't work automatically:
```bash
# Install Firefox temporarily to help with conversion
yay -S firefox

# Or try converting the compressed bookmark file manually
# (requires python-lz4 package)
```

### 🔍 Verification Checklist
- [ ] Bookmarks imported successfully
- [ ] uBlock Origin installed and working
- [ ] Dark Reader installed and configured
- [ ] Bitwarden logged in with your account
- [ ] Vivaldi built-in ad blocker enabled
- [ ] Theme/appearance configured
- [ ] Sync set up (optional)

## 🆘 Troubleshooting

### Bookmarks Won't Import
1. Try the HTML export method using Firefox
2. Check if the backup drive is properly mounted
3. Verify file permissions on the backup directory

### Extensions Not Working
1. Make sure you're getting them from Chrome Web Store, not Firefox Add-ons
2. Enable Developer mode in `vivaldi://extensions/`
3. Restart Vivaldi after installing extensions

### Missing Features
Many Firefox extensions aren't needed in Vivaldi due to built-in features:
- **Built-in Ad Blocker** (instead of additional ad blockers)
- **Built-in Screenshot Tools**
- **Built-in Translation**
- **Built-in Tab Management**

## 📞 Need Help?

- **Vivaldi Community**: https://forum.vivaldi.net/
- **Chrome Web Store**: https://chrome.google.com/webstore
- **Bitwarden Help**: https://bitwarden.com/help/

---
*Generated by 🏠 here restoration script*
*Backup analyzed: December 4th, 2024*