# Migration Prep Tools

A comprehensive backup solution for preparing home directory migrations. This tool intelligently backs up important files while skipping build artifacts, cache files, and other temporary data that doesn't need to be migrated.

## Features

- ✅ **Smart Filtering**: Automatically skips build artifacts, cache directories, and temporary files
- ✅ **Gitignore Respect**: Honors `.gitignore` patterns in each directory
- ✅ **Config Preservation**: Always preserves configuration files, dotfiles, and environment files
- ✅ **Multiple Backup Modes**: Home, code-only, config-only, or custom backups
- ✅ **Dry Run Support**: Preview what will be backed up without actually copying
- ✅ **Progress Tracking**: Detailed logging and statistics
- ✅ **Safe Operations**: Error handling and permission management

## Quick Start

### Basic Usage

```bash
# Backup entire home directory
./migration_prep.sh home

# Backup only code directories
./migration_prep.sh code

# Backup only configuration files
./migration_prep.sh config

# Preview what would be backed up (dry run)
./migration_prep.sh dry-run ~
```

### Advanced Usage

```bash
# Custom source and destination
./migration_prep.sh custom ~/Documents ~/backup/documents

# Verbose output
./migration_prep.sh home --verbose

# Custom destination directory
./migration_prep.sh home --destination ~/my-backup

# Dry run with verbose output
./migration_prep.sh dry-run ~ --verbose
```

## What Gets Skipped

The tool automatically skips these types of files and directories:

### Build Artifacts
- `node_modules/`, `dist/`, `build/`, `target/`
- `__pycache__/`, `.pytest_cache/`, `.mypy_cache/`
- `.venv/`, `venv/`, `env/`, `virtualenv/`
- `zig-cache/`, `zig-out/`, `.stack-work/`
- `_build/`, `deps/`, `_deps/`, `.elixir_ls/`
- Compiled files: `*.pyc`, `*.o`, `*.class`, `*.beam`

### Cache and Temporary Files
- `.npm/`, `.yarn/`, `.cargo/registry/`, `.cargo/git/`
- `.gradle/`, `.m2/`, `.ivy2/`
- `logs/`, `tmp/`, `temp/`, `.tmp/`, `.temp/`
- `*.log`, `*.tmp`, `*.cache`, `*.swp`, `*~`
- `.DS_Store`, `Thumbs.db`

### Version Control Internals
- `.git/`, `.svn/`, `.hg/`, `.bzr/`
- Lock files: `package-lock.json`, `yarn.lock`, `*.lock`

## What Gets Preserved

### Configuration Files
- Shell configs: `.bashrc`, `.zshrc`, `.profile`, `.bash_profile`
- Editor configs: `.vimrc`, `.nvim/`, `.emacs.d/`
- Terminal configs: `.tmux.conf`, `.screenrc`, `.inputrc`
- Any file matching: `*.conf`, `*.config`, `config.*`

### Environment and Authentication
- `.env*`, `.environment`, `environment.*`
- `.ssh/`, `.gnupg/`, `.aws/`, `.docker/`, `.kube/`
- `.gitconfig`, `.gitignore_global`

### Project Files
- `requirements.txt`, `Pipfile`, `pyproject.toml`
- `package.json`, `tsconfig.json`, `webpack.config.js`
- `Cargo.toml`, `mix.exs`, `build.zig`
- `Makefile`, `CMakeLists.txt`, `Dockerfile*`
- `flake.nix`, `shell.nix`, `default.nix`

### Documentation
- `README*`, `*.md`, `*.rst`, `*.txt`
- `LICENSE*`, `CONTRIBUTING*`, `CHANGELOG*`

### Important Directories
- `.config/`, `.local/share/`
- `.mozilla/`, `.thunderbird/`
- `.cargo/config.toml`, `.rustup/settings.toml`
- `.npmrc`, `.yarnrc`, `.pip/`, `.poetry/`

## Command Reference

### Shell Script Commands

```bash
./migration_prep.sh COMMAND [OPTIONS]
```

**Commands:**
- `home` - Backup entire home directory
- `code` - Backup code directories only  
- `config` - Backup config files and dotfiles only
- `custom <source> <dest>` - Custom backup with source and destination
- `dry-run <source>` - Show what would be backed up (no copying)
- `help` - Show help message

**Options:**
- `-v, --verbose` - Verbose output
- `-d, --destination DIR` - Override default destination
- `-n, --dry-run` - Preview mode
- `-h, --help` - Show help

### Python Script Direct Usage

```bash
python3 migration_prep.py SOURCE DESTINATION [OPTIONS]
```

**Options:**
- `--dry-run` - Preview mode
- `--verbose, -v` - Verbose output

## Output and Statistics

After completion, you'll see a summary like this:

```
==================================================
BACKUP SUMMARY
==================================================
Files copied: 15,432
Files skipped: 127,891
Errors: 3
Size copied: 2,847.32 MB
Duration: 0:05:23
Backup location: /home/user/migration-backup-20240101_120000
```

## Backup Information

Each backup includes a `backup_info.json` file with metadata:

```json
{
  "timestamp": "2024-01-01T12:00:00.123456",
  "source": "/home/user",
  "destination": "/home/user/migration-backup-20240101_120000",
  "stats": {
    "copied": 15432,
    "skipped": 127891,
    "errors": 3,
    "size_copied": 2987654321
  },
  "version": "1.0"
}
```

## Safety Features

- **Permission Handling**: Gracefully handles permission denied errors
- **Symlink Safety**: Properly handles symbolic links
- **Error Recovery**: Continues operation even if individual files fail
- **Dry Run**: Test your backup strategy without actually copying files
- **Logging**: Comprehensive logging of all operations

## Customization

You can modify the skip patterns and keep patterns by editing the Python script:

- **skip_dirs**: Directories to always skip
- **skip_patterns**: File patterns to skip
- **keep_patterns**: File patterns to always preserve
- **keep_dotfiles**: Important dotfiles/directories to preserve

## Examples

### Migrating to a New Machine

1. **Prepare backup on old machine:**
   ```bash
   ./migration_prep.sh home --destination /external/drive/backup
   ```

2. **Preview what's included:**
   ```bash
   ./migration_prep.sh dry-run /external/drive/backup --verbose
   ```

3. **Restore on new machine:**
   ```bash
   cp -r /external/drive/backup/* ~/
   ```

### Development Environment Backup

```bash
# Backup just your code
./migration_prep.sh code --destination ~/Dropbox/code-backup

# Backup development configs
./migration_prep.sh config --destination ~/Dropbox/dev-configs
```

### Regular Maintenance

```bash
# Weekly config backup
./migration_prep.sh config --destination ~/backups/weekly-$(date +%Y%m%d)

# Monthly full backup
./migration_prep.sh home --destination /external/monthly-backup
```

## Requirements

- Python 3.6+
- Standard library modules only (no external dependencies)
- Unix-like system (Linux, macOS)

## Files

- `migration_prep.py` - Main Python script
- `migration_prep.sh` - Shell wrapper with convenient presets
- `MIGRATION_PREP_README.md` - This documentation

## Troubleshooting

### Common Issues

**Permission Denied:**
- The tool will log permission errors but continue with other files
- Run with `sudo` only if absolutely necessary

**Large Backup Size:**
- Use `--dry-run` to preview what will be copied
- Consider using `code` or `config` modes for smaller backups

**Slow Performance:**
- Use `--verbose` to see progress
- Consider excluding large directories manually

### Getting Help

Run with `--help` for command-line help:
```bash
./migration_prep.sh help
python3 migration_prep.py --help
```

Check the logs for detailed error information if backup fails.