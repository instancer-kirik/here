#!/usr/bin/env python3
"""
Migration Preparation Script
Backs up important files while skipping build artifacts and respecting gitignore patterns.
Preserves config files, dotfiles, and environment files.
"""

import argparse
import fnmatch
import json
import logging
import os
import shutil
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Set

# Configure logging
logging.basicConfig(
    level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s"
)
logger = logging.getLogger(__name__)


class MigrationPrep:
    def __init__(self, source_dir: str, backup_dir: str):
        self.source_dir = Path(source_dir).expanduser().resolve()
        self.backup_dir = Path(backup_dir).expanduser().resolve()
        self.stats = {"copied": 0, "skipped": 0, "errors": 0, "size_copied": 0}

        # Common build/cache directories to skip
        self.skip_dirs = {
            "__pycache__",
            ".pytest_cache",
            ".mypy_cache",
            ".tox",
            "node_modules",
            ".npm",
            ".yarn",
            "dist",
            "build",
            "target",
            ".venv",
            "venv",
            "env",
            ".env",
            "virtualenv",
            ".git",
            ".svn",
            ".hg",
            ".bzr",
            ".Rproj.user",
            ".ropeproject",
            "cmake-build-debug",
            "cmake-build-release",
            ".gradle",
            ".m2",
            ".ivy2",
            ".cargo/registry",
            ".cargo/git",
            "zig-cache",
            "zig-out",
            ".stack-work",
            "_build",
            "deps",
            "_deps",
            ".elixir_ls",
            ".mix",
            "coverage",
            ".coverage",
            ".nyc_output",
            "logs",
            "*.log",
            "tmp",
            "temp",
            ".tmp",
            ".temp",
        }

        # Common build/temp file patterns to skip
        self.skip_patterns = [
            "*.pyc",
            "*.pyo",
            "*.pyd",
            "*.so",
            "*.dll",
            "*.dylib",
            "*.o",
            "*.obj",
            "*.class",
            "*.jar",
            "*.war",
            "*.beam",
            "*.plt",
            "*.exe",
            "*.app",
            "*.dmg",
            "*.pkg",
            "*.deb",
            "*.rpm",
            "*.zip",
            "*.tar.gz",
            "*.tar.bz2",
            "*.7z",
            "*.rar",
            "*.swp",
            "*.swo",
            "*~",
            ".DS_Store",
            "Thumbs.db",
            "*.tmp",
            "*.temp",
            "*.cache",
            "*.log",
            "core",
            "core.*",
            "*.core",
            "*.lock",
            "package-lock.json",
            "yarn.lock",
            "pnpm-lock.yaml",
            "*.min.js",
            "*.min.css",
            "*.map",
            "*.min.js.map",
            "*.min.css.map",
        ]

        # Important files/patterns to always keep
        self.keep_patterns = [
            ".*rc",
            ".*profile",
            ".*_profile",
            ".*_history",
            ".env*",
            ".environment",
            "environment.*",
            "*.conf",
            "*.config",
            "config.*",
            "configuration.*",
            ".gitconfig",
            ".gitignore_global",
            ".ssh/config",
            "requirements.txt",
            "Pipfile",
            "pyproject.toml",
            "package.json",
            "Cargo.toml",
            "mix.exs",
            "build.zig",
            "Makefile",
            "CMakeLists.txt",
            "Dockerfile*",
            "flake.nix",
            "shell.nix",
            "default.nix",
            "*.md",
            "*.rst",
            "*.txt",
            "LICENSE*",
            "README*",
            "tsconfig.json",
            "webpack.config.js",
            "vite.config.*",
        ]

        # Important dotfiles/directories to keep
        self.keep_dotfiles = {
            ".ssh",
            ".gnupg",
            ".gitconfig",
            ".vimrc",
            ".nvim",
            ".bashrc",
            ".zshrc",
            ".profile",
            ".bash_profile",
            ".tmux.conf",
            ".screenrc",
            ".inputrc",
            ".config",
            ".local/share",
            ".mozilla",
            ".thunderbird",
            ".aws",
            ".docker",
            ".kube",
            ".terraform.d",
            ".cargo/config.toml",
            ".rustup/settings.toml",
            ".npmrc",
            ".yarnrc",
            ".pip",
            ".poetry",
            ".mix",
            ".hex",
            ".iex.exs",
            ".emacs.d",
            ".doom.d",
            ".spacemacs.d",
        }

    def load_gitignore_patterns(self, directory: Path) -> Set[str]:
        """Load patterns from .gitignore files"""
        patterns = set()
        gitignore_file = directory / ".gitignore"

        if gitignore_file.exists():
            try:
                with open(gitignore_file, "r", encoding="utf-8") as f:
                    for line in f:
                        line = line.strip()
                        if line and not line.startswith("#"):
                            patterns.add(line)
            except Exception as e:
                logger.warning(f"Could not read .gitignore from {directory}: {e}")

        return patterns

    def should_skip_file(self, file_path: Path, gitignore_patterns: Set[str]) -> bool:
        """Determine if a file should be skipped"""
        filename = file_path.name
        relative_path = str(file_path.relative_to(self.source_dir))

        # Check if it's an important file to keep
        for pattern in self.keep_patterns:
            if fnmatch.fnmatch(filename, pattern):
                return False

        # Check gitignore patterns
        for pattern in gitignore_patterns:
            if fnmatch.fnmatch(relative_path, pattern) or fnmatch.fnmatch(
                filename, pattern
            ):
                return True

        # Check skip patterns
        for pattern in self.skip_patterns:
            if fnmatch.fnmatch(filename, pattern):
                return True

        return False

    def should_skip_directory(self, dir_path: Path) -> bool:
        """Determine if a directory should be skipped"""
        dirname = dir_path.name

        # Always keep important dotfiles/directories
        relative_path = str(dir_path.relative_to(self.source_dir))
        for keep_pattern in self.keep_dotfiles:
            if relative_path.startswith(keep_pattern) or dirname == keep_pattern:
                return False

        # Skip common build/cache directories
        if dirname in self.skip_dirs:
            return True

        # Skip directories matching skip patterns
        for pattern in self.skip_patterns:
            if fnmatch.fnmatch(dirname, pattern):
                return True

        return False

    def copy_file_safely(self, src: Path, dst: Path) -> bool:
        """Copy a file with error handling"""
        try:
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src, dst)
            self.stats["copied"] += 1
            self.stats["size_copied"] += src.stat().st_size
            return True
        except Exception as e:
            logger.error(f"Failed to copy {src} to {dst}: {e}")
            self.stats["errors"] += 1
            return False

    def backup_directory(self, src_dir: Path, dst_dir: Path, level: int = 0) -> None:
        """Recursively backup a directory"""
        if level > 10:  # Prevent infinite recursion
            logger.warning(f"Maximum recursion depth reached for {src_dir}")
            return

        try:
            gitignore_patterns = self.load_gitignore_patterns(src_dir)

            for item in src_dir.iterdir():
                try:
                    if item.is_symlink():
                        # Handle symlinks carefully
                        if item.exists():
                            target_path = dst_dir / item.name
                            if item.is_file():
                                if not self.should_skip_file(item, gitignore_patterns):
                                    self.copy_file_safely(item, target_path)
                                else:
                                    self.stats["skipped"] += 1
                        continue

                    if item.is_file():
                        if not self.should_skip_file(item, gitignore_patterns):
                            target_path = dst_dir / item.name
                            self.copy_file_safely(item, target_path)
                        else:
                            self.stats["skipped"] += 1

                    elif item.is_dir():
                        if not self.should_skip_directory(item):
                            target_dir = dst_dir / item.name
                            self.backup_directory(item, target_dir, level + 1)
                        else:
                            logger.info(f"Skipping directory: {item}")
                            self.stats["skipped"] += 1

                except PermissionError:
                    logger.warning(f"Permission denied: {item}")
                    self.stats["errors"] += 1
                except Exception as e:
                    logger.error(f"Error processing {item}: {e}")
                    self.stats["errors"] += 1

        except Exception as e:
            logger.error(f"Error scanning directory {src_dir}: {e}")
            self.stats["errors"] += 1

    def create_backup_info(self) -> None:
        """Create a backup info file with metadata"""
        info = {
            "timestamp": datetime.now().isoformat(),
            "source": str(self.source_dir),
            "destination": str(self.backup_dir),
            "stats": self.stats,
            "version": "1.0",
        }

        info_file = self.backup_dir / "backup_info.json"
        try:
            with open(info_file, "w") as f:
                json.dump(info, f, indent=2)
        except Exception as e:
            logger.error(f"Could not create backup info file: {e}")

    def run_backup(self) -> None:
        """Run the main backup process"""
        logger.info(
            f"Starting migration prep backup from {self.source_dir} to {self.backup_dir}"
        )

        if not self.source_dir.exists():
            raise ValueError(f"Source directory does not exist: {self.source_dir}")

        # Create backup directory
        self.backup_dir.mkdir(parents=True, exist_ok=True)

        # Start backup
        start_time = datetime.now()
        self.backup_directory(self.source_dir, self.backup_dir)
        end_time = datetime.now()

        # Create backup info
        self.create_backup_info()

        # Print summary
        duration = end_time - start_time
        size_mb = self.stats["size_copied"] / (1024 * 1024)

        logger.info("=" * 50)
        logger.info("BACKUP SUMMARY")
        logger.info("=" * 50)
        logger.info(f"Files copied: {self.stats['copied']}")
        logger.info(f"Files skipped: {self.stats['skipped']}")
        logger.info(f"Errors: {self.stats['errors']}")
        logger.info(f"Size copied: {size_mb:.2f} MB")
        logger.info(f"Duration: {duration}")
        logger.info(f"Backup location: {self.backup_dir}")


def main():
    parser = argparse.ArgumentParser(description="Prepare files for home migration")
    parser.add_argument("source", help="Source directory to backup (use ~ for home)")
    parser.add_argument("destination", help="Destination backup directory")
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Show what would be copied without copying",
    )
    parser.add_argument("--verbose", "-v", action="store_true", help="Verbose output")

    args = parser.parse_args()

    if args.verbose:
        logging.getLogger().setLevel(logging.DEBUG)

    try:
        if args.dry_run:
            logger.info("DRY RUN MODE - No files will be copied")

        backup = MigrationPrep(args.source, args.destination)

        if not args.dry_run:
            backup.run_backup()
        else:
            logger.info(
                "Dry run completed - use without --dry-run to perform actual backup"
            )

    except KeyboardInterrupt:
        logger.info("Backup interrupted by user")
    except Exception as e:
        logger.error(f"Backup failed: {e}")
        return 1

    return 0


if __name__ == "__main__":
    exit(main())
