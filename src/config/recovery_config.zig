const std = @import("std");

// Recovery system configuration management
pub const RecoveryConfig = struct {
    // Backup source configuration
    backup_path: []const u8,
    cloud_config: ?CloudConfig = null,

    // Database preferences
    auto_detect_databases: bool = true,
    preferred_migration_strategy: MigrationStrategy = .container_based,
    enable_progress_tracking: bool = true,

    // Safety settings
    backup_existing_data: bool = true,
    dry_run_mode: bool = false,
    require_confirmation: bool = true,

    // Performance settings
    max_parallel_operations: u8 = 2,
    timeout_seconds: u32 = 3600,
    chunk_size_mb: u32 = 100,

    // Logging and monitoring
    log_level: LogLevel = .info,
    enable_metrics: bool = false,
    metrics_port: u16 = 8080,

    pub const CloudConfig = struct {
        provider: CloudProvider,
        endpoint: []const u8,
        bucket: []const u8,
        region: ?[]const u8 = null,
        access_key: []const u8,
        secret_key: []const u8,

        pub const CloudProvider = enum {
            s3,
            google_cloud,
            azure,
            digitalocean,

            pub fn toString(self: CloudProvider) []const u8 {
                return switch (self) {
                    .s3 => "Amazon S3",
                    .google_cloud => "Google Cloud Storage",
                    .azure => "Azure Blob Storage",
                    .digitalocean => "DigitalOcean Spaces",
                };
            }
        };
    };

    pub const MigrationStrategy = enum {
        direct_restore,
        container_based,
        dump_restore,

        pub fn toString(self: MigrationStrategy) []const u8 {
            return switch (self) {
                .direct_restore => "Direct file copy (fastest, same version only)",
                .container_based => "Container-based migration (recommended)",
                .dump_restore => "Dump and restore (safest, slowest)",
            };
        }
    };

    pub const LogLevel = enum {
        debug,
        info,
        warn,
        err,

        pub fn toString(self: LogLevel) []const u8 {
            return switch (self) {
                .debug => "DEBUG",
                .info => "INFO",
                .warn => "WARN",
                .err => "ERROR",
            };
        }
    };

    // Default configuration
    pub fn default() RecoveryConfig {
        return RecoveryConfig{
            .backup_path = "/run/media/bon/MainStorage/MAIN_SWAP/home-backup",
        };
    }

    // Load configuration from file
    pub fn loadFromFile(allocator: std.mem.Allocator, path: []const u8) !RecoveryConfig {
        const file_content = std.fs.cwd().readFileAlloc(allocator, path, 1024 * 1024) catch |err| switch (err) {
            error.FileNotFound => {
                std.debug.print("📋 No config file found, using defaults\n", .{});
                return default();
            },
            else => return err,
        };
        defer allocator.free(file_content);

        return parseConfig(allocator, file_content);
    }

    // Save configuration to file
    pub fn saveToFile(self: *const RecoveryConfig, allocator: std.mem.Allocator, path: []const u8) !void {
        const config_text = try self.toText(allocator);
        defer allocator.free(config_text);

        const file = std.fs.cwd().createFile(path, .{}) catch |err| {
            std.debug.print("❌ Failed to create config file: {}\n", .{err});
            return err;
        };
        defer file.close();

        try file.writeAll(config_text);
        std.debug.print("✅ Configuration saved to {s}\n", .{path});
    }

    // Convert configuration to simple text format
    pub fn toText(self: *const RecoveryConfig, allocator: std.mem.Allocator) ![]u8 {
        var config_text = std.ArrayList(u8){};
        defer config_text.deinit(allocator);

        const writer = config_text.writer(allocator);
        try writer.print("backup_path={s}\n", .{self.backup_path});
        try writer.print("auto_detect_databases={}\n", .{self.auto_detect_databases});
        try writer.print("preferred_migration_strategy={s}\n", .{@tagName(self.preferred_migration_strategy)});
        try writer.print("enable_progress_tracking={}\n", .{self.enable_progress_tracking});
        try writer.print("backup_existing_data={}\n", .{self.backup_existing_data});
        try writer.print("dry_run_mode={}\n", .{self.dry_run_mode});
        try writer.print("require_confirmation={}\n", .{self.require_confirmation});
        try writer.print("max_parallel_operations={}\n", .{self.max_parallel_operations});
        try writer.print("timeout_seconds={}\n", .{self.timeout_seconds});
        try writer.print("chunk_size_mb={}\n", .{self.chunk_size_mb});
        try writer.print("log_level={s}\n", .{@tagName(self.log_level)});
        try writer.print("enable_metrics={}\n", .{self.enable_metrics});
        try writer.print("metrics_port={}\n", .{self.metrics_port});

        return config_text.toOwnedSlice(allocator);
    }

    // Parse configuration from text format
    fn parseConfig(allocator: std.mem.Allocator, text_content: []const u8) !RecoveryConfig {
        var config = default();

        var lines = std.mem.splitSequence(u8, text_content, "\n");
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r\n");
            if (trimmed.len == 0 or trimmed[0] == '#') continue;

            if (std.mem.indexOf(u8, trimmed, "=")) |eq_pos| {
                const key = std.mem.trim(u8, trimmed[0..eq_pos], " \t");
                const value = std.mem.trim(u8, trimmed[eq_pos + 1 ..], " \t");

                if (std.mem.eql(u8, key, "backup_path")) {
                    config.backup_path = try allocator.dupe(u8, value);
                } else if (std.mem.eql(u8, key, "auto_detect_databases")) {
                    config.auto_detect_databases = std.mem.eql(u8, value, "true");
                } else if (std.mem.eql(u8, key, "preferred_migration_strategy")) {
                    config.preferred_migration_strategy = std.meta.stringToEnum(MigrationStrategy, value) orelse .container_based;
                } else if (std.mem.eql(u8, key, "enable_progress_tracking")) {
                    config.enable_progress_tracking = std.mem.eql(u8, value, "true");
                } else if (std.mem.eql(u8, key, "backup_existing_data")) {
                    config.backup_existing_data = std.mem.eql(u8, value, "true");
                } else if (std.mem.eql(u8, key, "dry_run_mode")) {
                    config.dry_run_mode = std.mem.eql(u8, value, "true");
                } else if (std.mem.eql(u8, key, "require_confirmation")) {
                    config.require_confirmation = std.mem.eql(u8, value, "true");
                } else if (std.mem.eql(u8, key, "max_parallel_operations")) {
                    config.max_parallel_operations = @intCast(std.fmt.parseInt(u8, value, 10) catch 2);
                } else if (std.mem.eql(u8, key, "timeout_seconds")) {
                    config.timeout_seconds = @intCast(std.fmt.parseInt(u32, value, 10) catch 3600);
                } else if (std.mem.eql(u8, key, "chunk_size_mb")) {
                    config.chunk_size_mb = @intCast(std.fmt.parseInt(u32, value, 10) catch 100);
                } else if (std.mem.eql(u8, key, "log_level")) {
                    config.log_level = std.meta.stringToEnum(LogLevel, value) orelse .info;
                } else if (std.mem.eql(u8, key, "enable_metrics")) {
                    config.enable_metrics = std.mem.eql(u8, value, "true");
                } else if (std.mem.eql(u8, key, "metrics_port")) {
                    config.metrics_port = @intCast(std.fmt.parseInt(u16, value, 10) catch 8080);
                }
            }
        }

        return config;
    }

    // Interactive configuration setup
    pub fn setupInteractive(allocator: std.mem.Allocator) !RecoveryConfig {
        var config = default();

        std.debug.print("🔧 Recovery System Configuration\n", .{});
        std.debug.print("================================\n\n", .{});

        // Backup path configuration
        std.debug.print("📁 Backup path [{s}]: ", .{config.backup_path});
        var buffer: [512]u8 = undefined;
        const stdin = std.fs.File.stdin();
        if (stdin.read(buffer[0..])) |bytes_read| {
            if (bytes_read > 0) {
                const input = buffer[0..bytes_read];
                const trimmed = std.mem.trim(u8, input, " \t\r\n");
                if (trimmed.len > 0) {
                    config.backup_path = try allocator.dupe(u8, trimmed);
                }
            }
        } else |_| {}

        // Migration strategy
        std.debug.print("\n🔄 Migration strategy:\n", .{});
        std.debug.print("   1. Direct restore (fastest, same version)\n", .{});
        std.debug.print("   2. Container-based (recommended)\n", .{});
        std.debug.print("   3. Dump/restore (safest, slowest)\n", .{});
        std.debug.print("Choose [2]: ", .{});

        if (stdin.read(buffer[0..])) |bytes_read| {
            if (bytes_read > 0) {
                const choice = buffer[0..bytes_read];
                const trimmed = std.mem.trim(u8, choice, " \t\r\n");
                if (std.mem.eql(u8, trimmed, "1")) {
                    config.preferred_migration_strategy = .direct_restore;
                } else if (std.mem.eql(u8, trimmed, "3")) {
                    config.preferred_migration_strategy = .dump_restore;
                }
            }
        } else |_| {}

        // Progress tracking
        std.debug.print("\n📊 Enable progress tracking? [Y/n]: ", .{});
        if (stdin.read(buffer[0..])) |bytes_read| {
            if (bytes_read > 0) {
                const choice = buffer[0..bytes_read];
                const trimmed = std.mem.trim(u8, choice, " \t\r\n");
                if (std.mem.eql(u8, trimmed, "n") or std.mem.eql(u8, trimmed, "N")) {
                    config.enable_progress_tracking = false;
                }
            }
        } else |_| {}

        // Safety settings
        std.debug.print("\n🛡️  Backup existing data before recovery? [Y/n]: ", .{});
        if (stdin.read(buffer[0..])) |bytes_read| {
            if (bytes_read > 0) {
                const choice = buffer[0..bytes_read];
                const trimmed = std.mem.trim(u8, choice, " \t\r\n");
                if (std.mem.eql(u8, trimmed, "n") or std.mem.eql(u8, trimmed, "N")) {
                    config.backup_existing_data = false;
                }
            }
        } else |_| {}

        std.debug.print("\n✅ Configuration complete!\n", .{});
        return config;
    }

    // Validate configuration
    pub fn validate(self: *const RecoveryConfig) !void {
        // Check backup path exists
        std.fs.cwd().access(self.backup_path, .{}) catch {
            std.debug.print("❌ Backup path not accessible: {s}\n", .{self.backup_path});
            return error.InvalidBackupPath;
        };

        // Validate timeout
        if (self.timeout_seconds < 60) {
            std.debug.print("⚠️  Timeout too low, minimum 60 seconds\n", .{});
            return error.InvalidTimeout;
        }

        // Validate parallel operations
        if (self.max_parallel_operations == 0 or self.max_parallel_operations > 8) {
            std.debug.print("⚠️  Invalid parallel operations count: {}\n", .{self.max_parallel_operations});
            return error.InvalidParallelCount;
        }

        std.debug.print("✅ Configuration validation passed\n", .{});
    }

    // Print current configuration
    pub fn print(self: *const RecoveryConfig) void {
        std.debug.print("\n🔧 Current Recovery Configuration\n", .{});
        std.debug.print("=================================\n", .{});
        std.debug.print("📁 Backup path: {s}\n", .{self.backup_path});
        std.debug.print("🔍 Auto-detect databases: {}\n", .{self.auto_detect_databases});
        std.debug.print("🔄 Migration strategy: {s}\n", .{self.preferred_migration_strategy.toString()});
        std.debug.print("📊 Progress tracking: {}\n", .{self.enable_progress_tracking});
        std.debug.print("🛡️  Backup existing data: {}\n", .{self.backup_existing_data});
        std.debug.print("🏃 Dry run mode: {}\n", .{self.dry_run_mode});
        std.debug.print("✋ Require confirmation: {}\n", .{self.require_confirmation});
        std.debug.print("⚡ Max parallel operations: {}\n", .{self.max_parallel_operations});
        std.debug.print("⏰ Timeout: {}s\n", .{self.timeout_seconds});
        std.debug.print("📦 Chunk size: {}MB\n", .{self.chunk_size_mb});
        std.debug.print("📝 Log level: {s}\n", .{self.log_level.toString()});
        std.debug.print("📈 Enable metrics: {}\n", .{self.enable_metrics});
        if (self.enable_metrics) {
            std.debug.print("🔌 Metrics port: {}\n", .{self.metrics_port});
        }
        if (self.cloud_config) |cloud| {
            std.debug.print("☁️  Cloud provider: {s}\n", .{cloud.provider.toString()});
        }
        std.debug.print("\n", .{});
    }
};

// Configuration file paths
pub const CONFIG_DIR = ".config/here";
pub const CONFIG_FILE = "recovery.conf";

// Get configuration file path
pub fn getConfigPath(allocator: std.mem.Allocator) ![]u8 {
    const home = std.process.getEnvVarOwned(allocator, "HOME") catch {
        return error.HomeNotFound;
    };
    defer allocator.free(home);

    return std.fmt.allocPrint(allocator, "{s}/{s}/{s}", .{ home, CONFIG_DIR, CONFIG_FILE });
}

// Ensure configuration directory exists
pub fn ensureConfigDir(allocator: std.mem.Allocator) !void {
    const home = std.process.getEnvVarOwned(allocator, "HOME") catch {
        return error.HomeNotFound;
    };
    defer allocator.free(home);

    const config_dir = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ home, CONFIG_DIR });
    defer allocator.free(config_dir);

    std.fs.cwd().makeDir(config_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {}, // Directory exists, that's fine
        else => return err,
    };
}

test "RecoveryConfig default" {
    const config = RecoveryConfig.default();
    try std.testing.expect(config.auto_detect_databases == true);
    try std.testing.expect(config.backup_existing_data == true);
    try std.testing.expect(config.max_parallel_operations == 2);
}

test "RecoveryConfig JSON serialization" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var config = RecoveryConfig.default();
    config.dry_run_mode = true;
    config.max_parallel_operations = 4;

    const json = try config.toJson(allocator);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"dry_run_mode\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"max_parallel_operations\":4") != null);
}
