const std = @import("std");
const print = std.debug.print;
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

pub const MigrationStats = struct {
    files_copied: u64,
    files_skipped: u64,
    dirs_skipped: u64,
    errors: u64,
    bytes_copied: u64,
    start_time: i64,
    end_time: i64,

    pub fn init() MigrationStats {
        return MigrationStats{
            .files_copied = 0,
            .files_skipped = 0,
            .dirs_skipped = 0,
            .errors = 0,
            .bytes_copied = 0,
            .start_time = std.time.timestamp(),
            .end_time = 0,
        };
    }

    pub fn finish(self: *MigrationStats) void {
        self.end_time = std.time.timestamp();
    }

    pub fn duration(self: *const MigrationStats) i64 {
        return self.end_time - self.start_time;
    }
};

pub const MigrationOptions = struct {
    verbose: bool,
    dry_run: bool,
    source_path: []const u8,
    dest_path: []const u8,
    skip_code: bool,
    skip_downloads: bool,
};

pub const MigrationBackup = struct {
    allocator: Allocator,
    options: MigrationOptions,
    stats: MigrationStats,
    gitignore_cache: std.HashMap([]const u8, ArrayList([]const u8), std.hash_map.StringContext, 80),

    // Core directories to skip (performance-critical exact matches)
    const SKIP_DIRS = [_][]const u8{
        // Version control
        ".git",               ".svn",              ".hg",                 ".bzr",
        // Build artifacts
        "node_modules",       "__pycache__",       "zig-cache",           "zig-out",
        "target",             "build",             "dist",                "out",
        // Caches
        ".cache",             "cache",             "Cache",               ".npm",
        ".yarn",              ".pnpm-store",
        // Virtual environments
              ".venv",               "venv",
        "env",                "virtualenv",
        // Trash and temp
               ".Trash",              ".Trash-1000",
        ".local/share/Trash", "tmp",               "temp",                ".tmp",
        ".temp",
        // Development tools
                     ".pytest_cache",     ".mypy_cache",         ".tox",
        ".gradle",            ".m2",               ".ivy2",
        // Language specific
                      ".cargo/registry",
        ".cargo/git",         ".stack-work",       "_build",              "deps",
        "_deps",              ".elixir_ls",        ".mix",                "coverage",
        ".coverage",          ".nyc_output",
        // System directories
              ".gvfs",               ".dbus",
        ".pulse",
        // Test directories (major performance impact)
                    "test",              "tests",               "testing",
        "spec",               "specs",             "__tests__",           ".pytest_cache",
        "test-results",
        // Media cache directories
              ".thumbnails",       "thumbnails",          ".thumb",
        "thumb",              "previews",          ".previews",           "generated-assets",
        // Cloud storage directories (usually synced elsewhere)
        "Dropbox",            "OneDrive",          "Google Drive",        "iCloud Drive",
        // Package manager caches
        "yay",                "paru",              "trizen",              "pikaur",
        "sdists-v0",          "sdists-v1",         "sdists-v2",           "sdists-v3",
        "sdists-v4",          "sdists-v5",         "sdists-v6",           "wheels-v0",
        "wheels-v1",          "wheels-v2",         "wheels-v3",           "wheels-v4",
        // IDE and editor artifacts
        ".vscode",            ".idea",             ".vs",                 ".fleet",
        "CMakeFiles",         "cmake-build-debug", "cmake-build-release",
    };

    // File patterns to skip
    const SKIP_PATTERNS = [_][]const u8{
        // System files
        ".DS_Store",     "Thumbs.db",      "desktop.ini",  ".directory",
        ".ICEauthority", ".Xauthority",    "*.pid",        "*.sock",
        "*.lock",
        // Build artifacts
               "*.pyc",          "*.pyo",        "*.o",
        "*.class",       "*.beam",         "*.so",         "*.dll",
        // Temporary files
        "*.tmp",         "*.temp",         "*.swp",        "*.swo",
        "*~",            "core",           "core.*",
        // Package locks
              "package-lock.json",
        "yarn.lock",     "pnpm-lock.yaml",
        // Logs
        "*.log",
        // Test artifacts (major space savers)
               "*.out",
        "*.perf",        "*.test",         "*.spec",       "*.coverage",
        "*test.xml",     "*test.json",     "test_*.xml",
        // Binary artifacts
          "*.exe",
        "*.app",         "*.dmg",          "*.pkg",        "*.deb",
        "*.rpm",         "*.msi",          "*.appimage",
        // Archives (often cached/generated)
          "*.zip",
        "*.tar.gz",      "*.tar.bz2",      "*.7z",         "*.rar",
        "*.whl",         "*.egg",          "*.jar",
        // Media caches and thumbnails
               "*.cache",
        "*.idx",         "*.db",           "*.sqlite",     "*.sqlite3",
        "*.db-journal",  "Thumbs.db",      ".DS_Store",    "*.thumbnail",
        "*.thumb",       ".thumbnails",
        // Generated media (not originals)
           "*-preview.*",  "*-thumb.*",
        "*_thumb.*",     "*_preview.*",    "*.webp.cache", "*.jpg.cache",
        "*.png.cache",
    };

    // Important patterns to always keep
    const KEEP_PATTERNS = [_][]const u8{
        ".*rc",           ".*profile",    ".*_profile",       ".*_history",
        ".env*",          ".environment", "environment.*",    "*.conf",
        "*.config",       "config.*",     "configuration.*",  ".gitconfig",
        ".gitignore*",    ".ssh/config",  "requirements.txt", "Pipfile",
        "pyproject.toml", "package.json", "Cargo.toml",       "mix.exs",
        "build.zig",      "Makefile",     "CMakeLists.txt",   "*.md",
        "*.rst",          "*.txt",        "LICENSE*",         "README*",
        "Dockerfile*",    "*.nix",
    };

    // Important directories to always keep
    const KEEP_DOTFILES = [_][]const u8{
        ".ssh",       ".gnupg",   ".config",       ".local/share",
        ".gitconfig", ".vimrc",   ".nvim",         ".bashrc",
        ".zshrc",     ".profile", ".bash_profile", ".tmux.conf",
        ".screenrc",
    };

    pub fn init(allocator: Allocator, options: MigrationOptions) MigrationBackup {
        return MigrationBackup{
            .allocator = allocator,
            .options = options,
            .stats = MigrationStats.init(),
            .gitignore_cache = std.HashMap([]const u8, ArrayList([]const u8), std.hash_map.StringContext, 80).init(allocator),
        };
    }

    pub fn deinit(self: *MigrationBackup) void {
        var iterator = self.gitignore_cache.iterator();
        while (iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            for (entry.value_ptr.items) |pattern| {
                self.allocator.free(pattern);
            }
            entry.value_ptr.deinit(self.allocator);
        }
        self.gitignore_cache.deinit();
    }

    pub fn run(self: *MigrationBackup) !void {
        if (self.options.verbose) {
            print("🚀 Starting migration backup...\n", .{});
            print("📂 Source: {s}\n", .{self.options.source_path});
            print("📁 Destination: {s}\n", .{self.options.dest_path});
        }

        // Verify source exists
        std.fs.cwd().access(self.options.source_path, .{}) catch |err| {
            print("❌ Source directory does not exist: {s}\n", .{self.options.source_path});
            return err;
        };

        // Create destination directory if not dry run
        if (!self.options.dry_run) {
            std.fs.cwd().makePath(self.options.dest_path) catch |err| {
                print("❌ Failed to create destination directory: {s}\n", .{self.options.dest_path});
                return err;
            };
        }

        // Start backup
        try self.backupDirectory(self.options.source_path, self.options.dest_path, 0);

        // Finish and show stats
        self.stats.finish();
        try self.printSummary();
        try self.createBackupInfo();
    }

    fn backupDirectory(self: *MigrationBackup, source: []const u8, dest: []const u8, depth: u32) !void {
        // Prevent infinite recursion
        if (depth > 20) {
            if (self.options.verbose) {
                print("⚠️  Maximum depth reached, skipping: {s}\n", .{source});
            }
            return;
        }

        var source_dir = std.fs.cwd().openDir(source, .{ .iterate = true }) catch |err| {
            if (self.options.verbose) {
                print("⚠️  Cannot access directory: {s} ({})\n", .{ source, err });
            }
            self.stats.errors += 1;
            return;
        };
        defer source_dir.close();

        // Load gitignore patterns for this directory
        const gitignore_patterns = try self.loadGitignorePatterns(source);

        var iterator = source_dir.iterate();
        while (try iterator.next()) |entry| {
            const source_path = try std.fs.path.join(self.allocator, &[_][]const u8{ source, entry.name });
            defer self.allocator.free(source_path);

            const dest_path = try std.fs.path.join(self.allocator, &[_][]const u8{ dest, entry.name });
            defer self.allocator.free(dest_path);

            switch (entry.kind) {
                .file => {
                    if (self.shouldSkipFile(entry.name, gitignore_patterns)) {
                        if (self.options.verbose) {
                            print("⏭️  Skipping file: {s}\n", .{source_path});
                        }
                        self.stats.files_skipped += 1;
                    } else {
                        try self.copyFile(source_path, dest_path);
                        // Show progress every 1000 files
                        if (!self.options.verbose and self.stats.files_copied % 1000 == 0) {
                            print("📁 Processed {} files...\n", .{self.stats.files_copied});
                        }
                    }
                },
                .directory => {
                    if (self.shouldSkipDirectory(entry.name, source_path, gitignore_patterns)) {
                        // Skip and count files in directory
                        continue;
                    } else {
                        if (!self.options.dry_run) {
                            std.fs.cwd().makePath(dest_path) catch |err| {
                                if (self.options.verbose) {
                                    print("❌ Failed to create directory {s}: {}\n", .{ dest_path, err });
                                }
                                self.stats.errors += 1;
                                continue;
                            };
                        }
                        try self.backupDirectory(source_path, dest_path, depth + 1);
                    }
                },
                .sym_link => {
                    // Handle symlinks by preserving them
                    if (!self.options.dry_run) {
                        var link_buffer: [std.fs.max_path_bytes]u8 = undefined;
                        const target_path = std.fs.cwd().readLink(source_path, &link_buffer) catch |err| {
                            if (self.options.verbose) {
                                print("⚠️  Failed to read symlink {s}: {}\n", .{ source_path, err });
                            }
                            self.stats.errors += 1;
                            continue;
                        };

                        std.fs.cwd().symLink(target_path, dest_path, .{}) catch |err| {
                            if (self.options.verbose) {
                                print("⚠️  Failed to create symlink {s}: {}\n", .{ dest_path, err });
                            }
                            self.stats.errors += 1;
                            continue;
                        };
                    }

                    if (self.options.verbose) {
                        print("🔗 Symlink: {s}\n", .{source_path});
                    }
                    self.stats.files_copied += 1;
                },
                else => {
                    // Skip other file types
                    continue;
                },
            }
        }
    }

    fn copyFile(self: *MigrationBackup, source: []const u8, dest: []const u8) !void {
        if (self.options.dry_run) {
            if (self.options.verbose) {
                print("📄 Would copy: {s}\n", .{source});
            }
            self.stats.files_copied += 1;
            return;
        }

        const source_file = std.fs.cwd().openFile(source, .{}) catch |err| {
            if (self.options.verbose) {
                print("❌ Failed to open source file {s}: {}\n", .{ source, err });
            }
            self.stats.errors += 1;
            return;
        };
        defer source_file.close();

        // Get file size for statistics
        const file_size = source_file.getEndPos() catch 0;

        // Create destination directory if needed
        if (std.fs.path.dirname(dest)) |dest_dir| {
            std.fs.cwd().makePath(dest_dir) catch |err| {
                if (self.options.verbose) {
                    print("❌ Failed to create destination directory {s}: {}\n", .{ dest_dir, err });
                }
                self.stats.errors += 1;
                return;
            };
        }

        const dest_file = std.fs.cwd().createFile(dest, .{}) catch |err| {
            if (self.options.verbose) {
                print("❌ Failed to create destination file {s}: {}\n", .{ dest, err });
            }
            self.stats.errors += 1;
            return;
        };
        defer dest_file.close();

        // Copy file content
        const bytes_copied = source_file.copyRangeAll(0, dest_file, 0, file_size) catch |err| {
            if (self.options.verbose) {
                print("❌ Failed to copy file content {s}: {}\n", .{ source, err });
            }
            self.stats.errors += 1;
            return;
        };

        // Copy file metadata (permissions, timestamps)
        const source_stat = source_file.stat() catch {
            // If we can't get metadata, file was still copied
            if (self.options.verbose) {
                print("⚠️  Could not copy metadata for {s}\n", .{source});
            }
            self.stats.files_copied += 1;
            self.stats.bytes_copied += bytes_copied;
            return;
        };

        dest_file.chmod(source_stat.mode) catch {};

        if (self.options.verbose) {
            print("✅ Copied: {s} ({} bytes)\n", .{ source, bytes_copied });
        }

        self.stats.files_copied += 1;
        self.stats.bytes_copied += bytes_copied;
    }

    fn shouldSkipFile(self: *MigrationBackup, filename: []const u8, gitignore_patterns: []const []const u8) bool {
        // Check if it's an important file to keep first
        for (KEEP_PATTERNS) |pattern| {
            if (self.matchesPattern(filename, pattern)) {
                return false;
            }
        }

        // Check gitignore patterns
        for (gitignore_patterns) |pattern| {
            if (self.matchesPattern(filename, pattern)) {
                return true;
            }
        }

        // Check skip patterns
        for (SKIP_PATTERNS) |pattern| {
            if (self.matchesPattern(filename, pattern)) {
                return true;
            }
        }

        return false;
    }

    fn shouldSkipDirectory(self: *MigrationBackup, dirname: []const u8, full_path: []const u8, gitignore_patterns: []const []const u8) bool {
        // Check optional skip flags first
        if (self.options.skip_code and (std.mem.eql(u8, dirname, "Code") or std.mem.eql(u8, dirname, "code") or
            std.mem.eql(u8, dirname, "Development") or std.mem.eql(u8, dirname, "dev")))
        {
            if (self.options.verbose) {
                print("🚫 Skipped code directory (--skip-code): {s}\n", .{dirname});
            }
            self.stats.dirs_skipped += 1;
            return true;
        }

        if (self.options.skip_downloads and (std.mem.eql(u8, dirname, "Downloads") or std.mem.eql(u8, dirname, "downloads"))) {
            if (self.options.verbose) {
                print("🚫 Skipped downloads directory (--skip-downloads): {s}\n", .{dirname});
            }
            self.stats.dirs_skipped += 1;
            return true;
        }

        // Always keep important dotfiles/directories
        for (KEEP_DOTFILES) |keep_pattern| {
            if (std.mem.endsWith(u8, full_path, keep_pattern) or std.mem.eql(u8, dirname, keep_pattern)) {
                return false;
            }
        }

        // Check critical skip directories first (fastest - exact match)
        for (SKIP_DIRS) |skip_dir| {
            if (std.mem.eql(u8, dirname, skip_dir)) {
                const skipped_files = self.countFilesInDirectory(full_path) catch 1;
                self.stats.files_skipped += skipped_files;
                self.stats.dirs_skipped += 1;
                if (self.options.verbose) {
                    print("🚫 Skipped directory: {s} ({} files)\n", .{ dirname, skipped_files });
                }
                return true;
            }
        }

        // Early detection: Skip massive directories before counting (performance critical)
        if (self.isMassiveDirectory(full_path)) {
            // Estimate file count without full traversal for massive dirs
            const estimated_files = 50000; // Conservative estimate
            self.stats.files_skipped += estimated_files;
            self.stats.dirs_skipped += 1;
            if (self.options.verbose) {
                print("🚫 Skipped massive directory: {s} (~{} files)\n", .{ dirname, estimated_files });
            }
            return true;
        }

        // Check gitignore patterns
        for (gitignore_patterns) |pattern| {
            if (self.matchesPattern(dirname, pattern)) {
                const skipped_files = self.countFilesInDirectory(full_path) catch 1;
                self.stats.files_skipped += skipped_files;
                self.stats.dirs_skipped += 1;
                if (self.options.verbose) {
                    print("🚫 Skipped directory (gitignore): {s} ({} files)\n", .{ dirname, skipped_files });
                }
                return true;
            }
        }

        // Heuristic: Skip very large directories that look like caches (only for smaller dirs)
        const file_count = self.countFilesInDirectory(full_path) catch return false;
        if (file_count > 5000 and (std.mem.indexOf(u8, dirname, "cache") != null or
            std.mem.indexOf(u8, dirname, "Cache") != null or
            std.mem.indexOf(u8, dirname, "tmp") != null or
            std.mem.indexOf(u8, dirname, "test") != null))
        {
            self.stats.files_skipped += file_count;
            self.stats.dirs_skipped += 1;
            if (self.options.verbose) {
                print("🚫 Skipped large directory: {s} ({} files)\n", .{ dirname, file_count });
            }
            return true;
        }

        return false;
    }

    fn matchesPattern(self: *MigrationBackup, text: []const u8, pattern: []const u8) bool {
        _ = self;

        if (std.mem.indexOf(u8, pattern, "*")) |star_pos| {
            const prefix = pattern[0..star_pos];
            const suffix = pattern[star_pos + 1 ..];

            if (prefix.len > 0 and !std.mem.startsWith(u8, text, prefix)) {
                return false;
            }

            if (suffix.len > 0 and !std.mem.endsWith(u8, text, suffix)) {
                return false;
            }

            return true;
        } else {
            return std.mem.eql(u8, text, pattern);
        }
    }

    fn loadGitignorePatterns(self: *MigrationBackup, dir_path: []const u8) ![]const []const u8 {
        // Check cache first
        if (self.gitignore_cache.get(dir_path)) |patterns| {
            return patterns.items;
        }

        var patterns = ArrayList([]const u8){ .items = &[_][]const u8{}, .capacity = 0 };

        const gitignore_path = try std.fs.path.join(self.allocator, &[_][]const u8{ dir_path, ".gitignore" });
        defer self.allocator.free(gitignore_path);

        const gitignore_file = std.fs.cwd().openFile(gitignore_path, .{}) catch {
            // No .gitignore file, cache empty patterns
            const owned_path = try self.allocator.dupe(u8, dir_path);
            try self.gitignore_cache.put(owned_path, patterns);
            return patterns.items;
        };
        defer gitignore_file.close();

        const content = gitignore_file.readToEndAlloc(self.allocator, 1024 * 1024) catch {
            const owned_path = try self.allocator.dupe(u8, dir_path);
            try self.gitignore_cache.put(owned_path, patterns);
            return patterns.items;
        };
        defer self.allocator.free(content);

        var lines = std.mem.splitScalar(u8, content, '\n');
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r");
            if (trimmed.len == 0 or trimmed[0] == '#') {
                continue;
            }

            const owned_pattern = try self.allocator.dupe(u8, trimmed);
            try patterns.append(self.allocator, owned_pattern);
        }

        const patterns_slice = try patterns.toOwnedSlice(self.allocator);
        const owned_path = try self.allocator.dupe(u8, dir_path);

        // Convert slice back to ArrayList for cache storage
        const cache_patterns = ArrayList([]const u8){ .items = patterns_slice, .capacity = patterns_slice.len };
        try self.gitignore_cache.put(owned_path, cache_patterns);
        return patterns_slice;
    }

    // Fast check for massive directories without full traversal
    fn isMassiveDirectory(self: *MigrationBackup, dir_path: []const u8) bool {
        _ = self;
        var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch return false;
        defer dir.close();

        var count: u32 = 0;
        var iterator = dir.iterate();

        // Sample first 1000 entries - if we hit this limit quickly, it's massive
        while (iterator.next() catch null) |_| {
            count += 1;
            if (count >= 1000) {
                return true; // Definitely massive
            }
        }

        return false;
    }

    fn countFilesInDirectory(self: *MigrationBackup, dir_path: []const u8) !u64 {
        _ = self;
        var count: u64 = 0;
        var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch return 0;
        defer dir.close();

        var iterator = dir.iterate();
        while (try iterator.next()) |_| {
            count += 1;
            // Don't recurse for counting - just count immediate children for speed
            // Stop counting at reasonable limit to avoid hanging on massive dirs
            if (count >= 20000) {
                return count; // Return what we found so far
            }
        }

        return count;
    }

    fn printSummary(self: *MigrationBackup) !void {
        const duration = self.stats.duration();

        print("\n", .{});
        print("╔════════════════════════════════════════════════════════════════╗\n", .{});
        print("║                        BACKUP SUMMARY                         ║\n", .{});
        print("╠════════════════════════════════════════════════════════════════╣\n", .{});
        print("║ Files copied:        {:>8}                               ║\n", .{self.stats.files_copied});
        print("║ Files skipped:       {:>8}                               ║\n", .{self.stats.files_skipped});
        print("║ Directories skipped: {:>8}                               ║\n", .{self.stats.dirs_skipped});
        print("║ Errors:              {:>8}                               ║\n", .{self.stats.errors});
        print("║ Bytes copied:        {:>8}                               ║\n", .{self.stats.bytes_copied});
        print("║ Duration:            {:>8} seconds                       ║\n", .{duration});
        print("╚════════════════════════════════════════════════════════════════╝\n", .{});
        print("\n", .{});
    }

    fn createBackupInfo(self: *MigrationBackup) !void {
        if (self.options.dry_run) return;

        const info_path = try std.fs.path.join(self.allocator, &[_][]const u8{ self.options.dest_path, "backup_info.json" });
        defer self.allocator.free(info_path);

        const info_file = std.fs.cwd().createFile(info_path, .{}) catch {
            if (self.options.verbose) {
                print("⚠️  Could not create backup info file\n", .{});
            }
            return;
        };
        defer info_file.close();

        const info_content = try std.fmt.allocPrint(self.allocator,
            \\{{
            \\  "timestamp": "{d}",
            \\  "source": "{s}",
            \\  "destination": "{s}",
            \\  "stats": {{
            \\    "files_copied": {d},
            \\    "files_skipped": {d},
            \\    "dirs_skipped": {d},
            \\    "errors": {d},
            \\    "bytes_copied": {d},
            \\    "duration_seconds": {d}
            \\  }}
            \\}}
            \\
        , .{
            self.stats.start_time,
            self.options.source_path,
            self.options.dest_path,
            self.stats.files_copied,
            self.stats.files_skipped,
            self.stats.dirs_skipped,
            self.stats.errors,
            self.stats.bytes_copied,
            self.stats.duration(),
        });
        defer self.allocator.free(info_content);

        info_file.writeAll(info_content) catch {
            if (self.options.verbose) {
                print("⚠️  Could not write backup info\n", .{});
            }
        };
    }
};

pub fn runMigrationBackup(allocator: Allocator, args: []const []const u8) !void {
    var options = MigrationOptions{
        .verbose = false,
        .dry_run = false,
        .source_path = undefined,
        .dest_path = undefined,
        .skip_code = false,
        .skip_downloads = false,
    };

    var source_set = false;
    var dest_set = false;

    // Parse arguments - support both "source dest" and "source -d dest" formats
    var i: usize = 2; // Skip "here" and "backup"
    while (i < args.len) {
        const arg = args[i];

        if (std.mem.eql(u8, arg, "--verbose") or std.mem.eql(u8, arg, "-v")) {
            options.verbose = true;
        } else if (std.mem.eql(u8, arg, "--dry-run") or std.mem.eql(u8, arg, "-n")) {
            options.dry_run = true;
        } else if (std.mem.eql(u8, arg, "--skip-code")) {
            options.skip_code = true;
        } else if (std.mem.eql(u8, arg, "--skip-downloads")) {
            options.skip_downloads = true;
        } else if (std.mem.eql(u8, arg, "--destination") or std.mem.eql(u8, arg, "-d")) {
            if (i + 1 >= args.len) {
                print("❌ --destination requires a path argument\n", .{});
                return;
            }
            options.dest_path = args[i + 1];
            dest_set = true;
            i += 1; // Skip the destination path
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            printMigrationHelp();
            return;
        } else if (!source_set) {
            options.source_path = arg;
            source_set = true;
        } else if (!dest_set) {
            // Second positional argument is destination
            options.dest_path = arg;
            dest_set = true;
        } else {
            print("❌ Unknown argument: {s}\n", .{arg});
            printMigrationHelp();
            return;
        }

        i += 1;
    }

    if (!source_set) {
        print("❌ Source path is required\n", .{});
        printMigrationHelp();
        return;
    }

    if (!dest_set) {
        // Generate default destination path
        const timestamp = std.time.timestamp();
        const dest_name = try std.fmt.allocPrint(allocator, "migration-backup-{}", .{timestamp});
        defer allocator.free(dest_name);
        options.dest_path = dest_name;

        // We need to keep this alive, so duplicate it
        options.dest_path = try allocator.dupe(u8, dest_name);
    }

    var backup = MigrationBackup.init(allocator, options);
    defer backup.deinit();

    backup.run() catch |err| {
        print("❌ Migration backup failed: {}\n", .{err});
        return;
    };

    // Free allocated destination if we created it
    if (!dest_set) {
        allocator.free(options.dest_path);
    }
}

fn printMigrationHelp() void {
    print("🏠 here backup - Intelligent file backup for migration\n", .{});
    print("\n", .{});
    print("Usage: here backup <source> [destination] [OPTIONS]\n", .{});
    print("       here backup [OPTIONS] <source> [destination]\n", .{});
    print("\n", .{});
    print("Arguments:\n", .{});
    print("  <source>                 Source directory to backup\n", .{});
    print("  [destination]            Destination directory (default: migration-backup-<timestamp>)\n", .{});
    print("\n", .{});
    print("Options:\n", .{});
    print("  -d, --destination <path> Destination directory (alternative to positional)\n", .{});
    print("  -v, --verbose            Verbose output\n", .{});
    print("  -n, --dry-run            Show what would be copied without copying\n", .{});
    print("      --skip-code          Skip Code/Development directories\n", .{});
    print("      --skip-downloads     Skip Downloads directory\n", .{});
    print("  -h, --help               Show this help\n", .{});
    print("\n", .{});
    print("Examples:\n", .{});
    print("  here backup ~/Code /backup/code                  # Simple source → dest\n", .{});
    print("  here backup ~                                    # Backup home (auto-generated dest)\n", .{});
    print("  here backup ~ --skip-code                        # Skip Code directory\n", .{});
    print("  here backup ~/Documents /mnt/backup/docs        # Documents backup\n", .{});
    print("  here backup ~/Code --dry-run --verbose           # Preview with details\n", .{});
    print("\n", .{});
    print("Features:\n", .{});
    print("• Automatically skips build artifacts (node_modules, __pycache__, etc.)\n", .{});
    print("• Respects .gitignore patterns in each directory\n", .{});
    print("• Preserves important config files and dotfiles\n", .{});
    print("• Handles symlinks safely\n", .{});
    print("• Shows progress during backup\n", .{});
    print("• Creates backup manifest for verification\n", .{});
}
