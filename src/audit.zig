//! Supply-chain / orphan-takeover audit for ecosystem package installs.
//!
//! Defends against the "abandoned package takeover" attack where a malicious
//! actor publishes a new version of a formerly-trusted package that includes
//! lifecycle scripts (preinstall/install/postinstall/prepare) to exfiltrate
//! credentials, install backdoors, etc.
//!
//! Covers: npm / bun / yarn / pnpm (node_modules), pip (site-packages), cargo
//! PKGBUILD viewer: fetches PKGBUILD from AUR so you can review before building

const std = @import("std");
const print = std.debug.print;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

// ---------------------------------------------------------------------------
// Risk classification
// ---------------------------------------------------------------------------

pub const RiskLevel = enum {
    info,
    low,
    medium,
    high,
    critical,

    pub fn toString(self: RiskLevel) []const u8 {
        return switch (self) {
            .info => "INFO",
            .low => "LOW",
            .medium => "MEDIUM",
            .high => "HIGH",
            .critical => "CRITICAL",
        };
    }

    pub fn emoji(self: RiskLevel) []const u8 {
        return switch (self) {
            .info => "ℹ️ ",
            .low => "🟡",
            .medium => "🟠",
            .high => "🔴",
            .critical => "💀",
        };
    }
};

/// Suspicious patterns we search for inside lifecycle script strings.
/// Ordered from highest to lowest suspicion weight.
const SuspiciousPattern = struct {
    pattern: []const u8,
    description: []const u8,
    risk: RiskLevel,
};

const SUSPICIOUS_PATTERNS = [_]SuspiciousPattern{
    // --- Remote code execution via fetch+eval ---
    .{ .pattern = "eval(", .description = "eval() – arbitrary code execution", .risk = .critical },
    .{ .pattern = "new Function(", .description = "new Function() – dynamic code execution", .risk = .critical },
    .{ .pattern = "vm.runInNewContext", .description = "vm sandbox escape", .risk = .critical },

    // --- Shell exec inside Node scripts ---
    .{ .pattern = "execSync(", .description = "execSync – synchronous shell execution", .risk = .high },
    .{ .pattern = "spawnSync(", .description = "spawnSync – synchronous shell execution", .risk = .high },
    .{ .pattern = "child_process", .description = "child_process module imported", .risk = .high },
    .{ .pattern = "require('child_process')", .description = "require('child_process')", .risk = .high },
    .{ .pattern = "require(\"child_process\")", .description = "require(\"child_process\")", .risk = .high },

    // --- Network access ---
    .{ .pattern = "curl ", .description = "curl – outbound HTTP", .risk = .high },
    .{ .pattern = "wget ", .description = "wget – outbound HTTP", .risk = .high },
    .{ .pattern = "node-fetch", .description = "node-fetch HTTP call", .risk = .medium },
    .{ .pattern = "axios", .description = "axios HTTP call", .risk = .medium },
    .{ .pattern = "https.get(", .description = "https.get() outbound call", .risk = .medium },
    .{ .pattern = "http.get(", .description = "http.get() outbound call", .risk = .medium },
    .{ .pattern = "fetch(", .description = "fetch() outbound call", .risk = .medium },

    // --- Obfuscation / encoding ---
    .{ .pattern = "Buffer.from(", .description = "Buffer.from – possible base64 obfuscation", .risk = .medium },
    .{ .pattern = "atob(", .description = "atob() base64 decode", .risk = .medium },
    .{ .pattern = "btoa(", .description = "btoa() base64 encode", .risk = .low },
    .{ .pattern = "toString('hex')", .description = "hex encoding", .risk = .low },
    .{ .pattern = "fromCharCode", .description = "String.fromCharCode obfuscation", .risk = .medium },

    // --- Sensitive file / env access ---
    .{ .pattern = "process.env", .description = "reads environment variables (possible secret leak)", .risk = .medium },
    .{ .pattern = "$HOME", .description = "accesses $HOME in shell", .risk = .medium },
    .{ .pattern = "~/.ssh", .description = "accesses SSH directory", .risk = .critical },
    .{ .pattern = "~/.gnupg", .description = "accesses GPG directory", .risk = .critical },
    .{ .pattern = "~/.npmrc", .description = "accesses .npmrc (tokens)", .risk = .high },
    .{ .pattern = "~/.gitconfig", .description = "accesses git config", .risk = .high },
    .{ .pattern = "/etc/passwd", .description = "reads /etc/passwd", .risk = .critical },
    .{ .pattern = "/etc/shadow", .description = "reads /etc/shadow", .risk = .critical },
    .{ .pattern = "authorized_keys", .description = "touches SSH authorized_keys", .risk = .critical },

    // --- Persistence ---
    .{ .pattern = "crontab", .description = "modifies crontab (persistence)", .risk = .critical },
    .{ .pattern = "systemctl", .description = "interacts with systemd", .risk = .high },
    .{ .pattern = ".bashrc", .description = "modifies shell rc (persistence)", .risk = .high },
    .{ .pattern = ".zshrc", .description = "modifies shell rc (persistence)", .risk = .high },
    .{ .pattern = ".profile", .description = "modifies shell profile (persistence)", .risk = .high },

    // --- Crypto mining indicators ---
    .{ .pattern = "xmrig", .description = "xmrig miner binary", .risk = .critical },
    .{ .pattern = "stratum+tcp", .description = "mining pool connection", .risk = .critical },
    .{ .pattern = "monero", .description = "Monero reference", .risk = .high },
};

// ---------------------------------------------------------------------------
// Findings
// ---------------------------------------------------------------------------

pub const ScriptFinding = struct {
    hook: []u8, // "postinstall", "preinstall", etc.
    content: []u8, // full script content
    flags: [][]u8, // matched suspicious descriptions
    risk: RiskLevel,
    allocator: Allocator,

    pub fn deinit(self: *ScriptFinding) void {
        self.allocator.free(self.hook);
        self.allocator.free(self.content);
        for (self.flags) |f| self.allocator.free(f);
        self.allocator.free(self.flags);
    }
};

pub const PackageFinding = struct {
    name: []u8,
    version: []u8,
    path: []u8,
    scripts: []ScriptFinding,
    recently_modified: bool, // mtime within RECENT_DAYS
    days_ago: i64,
    risk: RiskLevel,
    allocator: Allocator,

    pub fn deinit(self: *PackageFinding) void {
        self.allocator.free(self.name);
        self.allocator.free(self.version);
        self.allocator.free(self.path);
        for (self.scripts) |*s| {
            var ms = s;
            ms.deinit();
        }
        self.allocator.free(self.scripts);
    }
};

// Packages modified within this many days are flagged as "recent"
const RECENT_DAYS: i64 = 7;

// ---------------------------------------------------------------------------
// Utility helpers
// ---------------------------------------------------------------------------

fn runCaptured(allocator: Allocator, argv: []const []const u8) ![]u8 {
    var child = std.process.Child.init(argv, allocator);
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Ignore;
    try child.spawn();

    var out = ArrayList(u8){};
    defer {
        // only clean up on error path – caller owns the slice
    }
    var buf: [4096]u8 = undefined;
    while (true) {
        const n = child.stdout.?.read(&buf) catch break;
        if (n == 0) break;
        try out.appendSlice(allocator, buf[0..n]);
    }
    _ = child.wait() catch {};
    return out.toOwnedSlice(allocator);
}

fn maxRisk(a: RiskLevel, b: RiskLevel) RiskLevel {
    const ai = @intFromEnum(a);
    const bi = @intFromEnum(b);
    return if (ai >= bi) a else b;
}

fn dupeStr(allocator: Allocator, s: []const u8) ![]u8 {
    return allocator.dupe(u8, s);
}

// ---------------------------------------------------------------------------
// npm / bun / yarn / pnpm  –  node_modules scanner
// ---------------------------------------------------------------------------

/// Lifecycle hooks that can run arbitrary code during install
const LIFECYCLE_HOOKS = [_][]const u8{
    "preinstall",
    "install",
    "postinstall",
    "prepare",
    "prepack",
    "prepublish",
};

/// Scan a single node_modules directory for suspicious packages.
/// `modules_dir` should be the absolute path to `node_modules`.
pub fn scanNodeModules(allocator: Allocator, modules_dir: []const u8) ![]PackageFinding {
    var findings = ArrayList(PackageFinding){};
    errdefer findings.deinit(allocator);

    var dir = std.fs.openDirAbsolute(modules_dir, .{ .iterate = true }) catch |err| {
        if (err == error.FileNotFound or err == error.NotDir) return &[_]PackageFinding{};
        return err;
    };
    defer dir.close();

    const now_sec: i64 = @intCast(std.time.timestamp());

    var it = dir.iterate();
    while (try it.next()) |entry| {
        if (entry.kind != .directory) continue;

        // Handle scoped packages (@scope/pkg)
        if (std.mem.startsWith(u8, entry.name, "@")) {
            const scope_path = try std.fs.path.join(allocator, &.{ modules_dir, entry.name });
            defer allocator.free(scope_path);

            var scope_dir = std.fs.openDirAbsolute(scope_path, .{ .iterate = true }) catch continue;
            defer scope_dir.close();

            var sit = scope_dir.iterate();
            while (try sit.next()) |sentry| {
                if (sentry.kind != .directory) continue;
                const scoped_name = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ entry.name, sentry.name });
                defer allocator.free(scoped_name);
                const pkg_path = try std.fs.path.join(allocator, &.{ modules_dir, entry.name, sentry.name });
                defer allocator.free(pkg_path);

                if (try auditNodePackage(allocator, pkg_path, scoped_name, now_sec)) |finding| {
                    try findings.append(allocator, finding);
                }
            }
        } else {
            const pkg_path = try std.fs.path.join(allocator, &.{ modules_dir, entry.name });
            defer allocator.free(pkg_path);

            if (try auditNodePackage(allocator, pkg_path, entry.name, now_sec)) |finding| {
                try findings.append(allocator, finding);
            }
        }
    }

    return findings.toOwnedSlice(allocator);
}

/// Returns a PackageFinding if the package has lifecycle scripts or was recently modified.
/// Returns null if the package is clean.
fn auditNodePackage(allocator: Allocator, pkg_path: []const u8, pkg_name: []const u8, now_sec: i64) !?PackageFinding {
    // Read package.json
    const pkg_json_path = try std.fs.path.join(allocator, &.{ pkg_path, "package.json" });
    defer allocator.free(pkg_json_path);

    const pkg_json_data = std.fs.cwd().readFileAlloc(allocator, pkg_json_path, 256 * 1024) catch return null;
    defer allocator.free(pkg_json_data);

    // Get mtime of package.json as proxy for when the package was installed/modified
    const stat = std.fs.cwd().statFile(pkg_json_path) catch return null;
    const mtime_sec: i64 = @intCast(@divFloor(stat.mtime, std.time.ns_per_s));
    const days_ago: i64 = @divFloor(now_sec - mtime_sec, 86400);
    const recently_modified = days_ago >= 0 and days_ago <= RECENT_DAYS;

    // Parse package.json
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, pkg_json_data, .{}) catch return null;
    defer parsed.deinit();

    const root = parsed.value.object;

    const version_val = root.get("version");
    const version_str = if (version_val != null and version_val.? == .string) version_val.?.string else "unknown";

    const scripts_val = root.get("scripts");
    if (scripts_val == null or scripts_val.? != .object) {
        // No scripts – only report if recently modified
        if (recently_modified) {
            return PackageFinding{
                .name = try dupeStr(allocator, pkg_name),
                .version = try dupeStr(allocator, version_str),
                .path = try dupeStr(allocator, pkg_path),
                .scripts = try allocator.alloc(ScriptFinding, 0),
                .recently_modified = true,
                .days_ago = days_ago,
                .risk = .info,
                .allocator = allocator,
            };
        }
        return null;
    }

    const scripts_obj = scripts_val.?.object;
    var script_findings = ArrayList(ScriptFinding){};
    errdefer script_findings.deinit(allocator);

    var overall_risk: RiskLevel = .info;

    for (LIFECYCLE_HOOKS) |hook| {
        const script_val = scripts_obj.get(hook) orelse continue;
        if (script_val != .string) continue;
        const content = script_val.string;

        // Scan for suspicious patterns
        var flags = ArrayList([]u8){};
        errdefer flags.deinit(allocator);
        var script_risk: RiskLevel = .info;

        for (SUSPICIOUS_PATTERNS) |sp| {
            if (std.mem.indexOf(u8, content, sp.pattern) != null) {
                try flags.append(allocator, try dupeStr(allocator, sp.description));
                script_risk = maxRisk(script_risk, sp.risk);
            }
        }

        overall_risk = maxRisk(overall_risk, script_risk);

        const finding = ScriptFinding{
            .hook = try dupeStr(allocator, hook),
            .content = try dupeStr(allocator, content),
            .flags = try flags.toOwnedSlice(allocator),
            .risk = script_risk,
            .allocator = allocator,
        };
        try script_findings.append(allocator, finding);
    }

    if (script_findings.items.len == 0 and !recently_modified) {
        return null;
    }

    if (recently_modified) {
        overall_risk = maxRisk(overall_risk, .info);
    }

    return PackageFinding{
        .name = try dupeStr(allocator, pkg_name),
        .version = try dupeStr(allocator, version_str),
        .path = try dupeStr(allocator, pkg_path),
        .scripts = try script_findings.toOwnedSlice(allocator),
        .recently_modified = recently_modified,
        .days_ago = days_ago,
        .risk = overall_risk,
        .allocator = allocator,
    };
}

// ---------------------------------------------------------------------------
// pip / site-packages scanner
// ---------------------------------------------------------------------------

/// Scan a Python site-packages directory for recently installed packages and
/// packages that ship a `setup.py` or `*.dist-info/RECORD` with suspicious
/// console_scripts / entry_points that exec shell commands.
pub fn scanPipPackages(allocator: Allocator, site_packages_dir: []const u8) ![]PackageFinding {
    var findings = ArrayList(PackageFinding){};
    errdefer findings.deinit(allocator);

    var dir = std.fs.openDirAbsolute(site_packages_dir, .{ .iterate = true }) catch |err| {
        if (err == error.FileNotFound or err == error.NotDir) return &[_]PackageFinding{};
        return err;
    };
    defer dir.close();

    const now_sec: i64 = @intCast(std.time.timestamp());

    var it = dir.iterate();
    while (try it.next()) |entry| {
        // dist-info directories hold metadata
        if (!std.mem.endsWith(u8, entry.name, ".dist-info")) continue;
        if (entry.kind != .directory) continue;

        // Parse "name-version.dist-info" directory name
        const base = entry.name[0 .. entry.name.len - ".dist-info".len];
        const dash_pos = std.mem.lastIndexOf(u8, base, "-") orelse continue;
        const pkg_name = base[0..dash_pos];
        const pkg_version = base[dash_pos + 1 ..];

        // Check WHEEL or METADATA mtime as install proxy
        const metadata_path = try std.fs.path.join(allocator, &.{ site_packages_dir, entry.name, "METADATA" });
        defer allocator.free(metadata_path);

        const stat = std.fs.cwd().statFile(metadata_path) catch continue;
        const mtime_sec: i64 = @intCast(@divFloor(stat.mtime, std.time.ns_per_s));
        const days_ago: i64 = @divFloor(now_sec - mtime_sec, 86400);
        const recently_modified = days_ago >= 0 and days_ago <= RECENT_DAYS;

        // Look for entry_points.txt which defines installed scripts
        const ep_path = try std.fs.path.join(allocator, &.{ site_packages_dir, entry.name, "entry_points.txt" });
        defer allocator.free(ep_path);

        var script_findings = ArrayList(ScriptFinding){};
        errdefer script_findings.deinit(allocator);

        if (std.fs.cwd().readFileAlloc(allocator, ep_path, 64 * 1024)) |ep_data| {
            defer allocator.free(ep_data);

            var flags = ArrayList([]u8){};
            errdefer flags.deinit(allocator);
            var risk: RiskLevel = .info;

            for (SUSPICIOUS_PATTERNS) |sp| {
                if (std.mem.indexOf(u8, ep_data, sp.pattern) != null) {
                    try flags.append(allocator, try dupeStr(allocator, sp.description));
                    risk = maxRisk(risk, sp.risk);
                }
            }

            if (flags.items.len > 0) {
                try script_findings.append(allocator, ScriptFinding{
                    .hook = try dupeStr(allocator, "entry_points"),
                    .content = try dupeStr(allocator, ep_data),
                    .flags = try flags.toOwnedSlice(allocator),
                    .risk = risk,
                    .allocator = allocator,
                });
            } else {
                flags.deinit(allocator);
            }
        } else |_| {}

        if (script_findings.items.len == 0 and !recently_modified) continue;

        const overall_risk = if (script_findings.items.len > 0) script_findings.items[0].risk else .info;

        const pkg_path = try std.fs.path.join(allocator, &.{ site_packages_dir, entry.name });
        try findings.append(allocator, PackageFinding{
            .name = try dupeStr(allocator, pkg_name),
            .version = try dupeStr(allocator, pkg_version),
            .path = pkg_path,
            .scripts = try script_findings.toOwnedSlice(allocator),
            .recently_modified = recently_modified,
            .days_ago = days_ago,
            .risk = overall_risk,
            .allocator = allocator,
        });
    }

    return findings.toOwnedSlice(allocator);
}

// ---------------------------------------------------------------------------
// Auto-discovery: find node_modules and site-packages under a search root
// ---------------------------------------------------------------------------

const MAX_SEARCH_DEPTH: usize = 6;

/// Discovered scan target
const ScanTarget = struct {
    kind: enum { node_modules, site_packages },
    path: []u8,
    allocator: Allocator,

    pub fn deinit(self: *ScanTarget) void {
        self.allocator.free(self.path);
    }
};

fn discoverTargets(allocator: Allocator, search_root: []const u8, targets: *ArrayList(ScanTarget), depth: usize) !void {
    if (depth > MAX_SEARCH_DEPTH) return;

    var dir = std.fs.openDirAbsolute(search_root, .{ .iterate = true }) catch return;
    defer dir.close();

    var it = dir.iterate();
    while (try it.next()) |entry| {
        if (entry.kind != .directory) continue;
        // Skip hidden dirs and common noise
        if (std.mem.startsWith(u8, entry.name, ".git")) continue;
        if (std.mem.eql(u8, entry.name, ".cache")) continue;
        if (std.mem.eql(u8, entry.name, "proc")) continue;
        if (std.mem.eql(u8, entry.name, "sys")) continue;

        const child_path = try std.fs.path.join(allocator, &.{ search_root, entry.name });

        if (std.mem.eql(u8, entry.name, "node_modules")) {
            try targets.append(allocator, ScanTarget{
                .kind = .node_modules,
                .path = child_path,
                .allocator = allocator,
            });
            // Don't recurse into node_modules
            continue;
        }

        if (std.mem.eql(u8, entry.name, "site-packages")) {
            try targets.append(allocator, ScanTarget{
                .kind = .site_packages,
                .path = child_path,
                .allocator = allocator,
            });
            allocator.free(child_path);
            continue;
        }

        try discoverTargets(allocator, child_path, targets, depth + 1);
        allocator.free(child_path);
    }
}

// ---------------------------------------------------------------------------
// Native npm/bun audit runner (delegates to the tool itself for CVE data)
// ---------------------------------------------------------------------------

fn runNativeAudit(allocator: Allocator, project_dir: []const u8) void {
    // Detect which lock file is present to pick the right tool
    const lock_files = [_]struct { file: []const u8, tool: []const u8, args: []const []const u8 }{
        .{ .file = "bun.lockb", .tool = "bun", .args = &.{ "bun", "audit" } },
        .{ .file = "bun.lock", .tool = "bun", .args = &.{ "bun", "audit" } },
        .{ .file = "package-lock.json", .tool = "npm", .args = &.{ "npm", "audit" } },
        .{ .file = "yarn.lock", .tool = "yarn", .args = &.{ "yarn", "audit" } },
        .{ .file = "pnpm-lock.yaml", .tool = "pnpm", .args = &.{ "pnpm", "audit" } },
    };

    for (lock_files) |lf| {
        const lock_path = std.fs.path.join(allocator, &.{ project_dir, lf.file }) catch continue;
        defer allocator.free(lock_path);

        std.fs.cwd().access(lock_path, .{}) catch continue;

        print("🔍 Running {s} audit in {s}...\n", .{ lf.tool, project_dir });

        var child = std.process.Child.init(lf.args, allocator);
        child.cwd = project_dir;
        child.stdout_behavior = .Inherit;
        child.stderr_behavior = .Inherit;
        _ = child.spawnAndWait() catch {};
        return;
    }
}

// ---------------------------------------------------------------------------
// Report renderer
// ---------------------------------------------------------------------------

fn printSeparator(char: u8, len: usize) void {
    var i: usize = 0;
    while (i < len) : (i += 1) print("{c}", .{char});
    print("\n", .{});
}

fn printFinding(f: *const PackageFinding) void {
    const risk_icon = f.risk.emoji();
    print("\n  {s} {s}@{s}\n", .{ risk_icon, f.name, f.version });
    print("     Path: {s}\n", .{f.path});

    if (f.recently_modified) {
        if (f.days_ago == 0) {
            print("     ⏱️  Modified: today\n", .{});
        } else {
            print("     ⏱️  Modified: {} day(s) ago\n", .{f.days_ago});
        }
    }

    for (f.scripts) |s| {
        print("     📜 Lifecycle hook: {s}  [{s}]\n", .{ s.hook, s.risk.toString() });
        // Show first 120 chars of script to avoid flooding terminal
        const preview_len = @min(s.content.len, 120);
        print("        Script: {s}", .{s.content[0..preview_len]});
        if (s.content.len > preview_len) print("…", .{});
        print("\n", .{});

        if (s.flags.len > 0) {
            print("        ⚠️  Flags:\n", .{});
            for (s.flags) |flag| {
                print("           • {s}\n", .{flag});
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Main entry points
// ---------------------------------------------------------------------------

/// `here audit [path]`
/// Scans the given path (default: cwd) for suspicious package installations.
pub fn runAudit(allocator: Allocator, args: []const []const u8) !void {
    // Determine search root
    var search_root_buf: [std.fs.max_path_bytes]u8 = undefined;
    const search_root = if (args.len > 0 and !std.mem.startsWith(u8, args[0], "--"))
        args[0]
    else blk: {
        const cwd = try std.process.getCwd(&search_root_buf);
        break :blk cwd;
    };

    const verbose = for (args) |a| {
        if (std.mem.eql(u8, a, "--verbose") or std.mem.eql(u8, a, "-v")) break true;
    } else false;

    const recent_only = for (args) |a| {
        if (std.mem.eql(u8, a, "--recent")) break true;
    } else false;

    print("\n🛡️  Supply-Chain Audit\n", .{});
    print("====================\n", .{});
    print("📂 Scanning: {s}\n", .{search_root});
    print("🎯 Checking for: lifecycle scripts, recently-modified packages\n\n", .{});

    // Run native audit tool if available (provides CVE data we don't have)
    runNativeAudit(allocator, search_root);

    // Discover scan targets
    var targets = ArrayList(ScanTarget){};
    defer {
        for (targets.items) |*t| t.deinit();
        targets.deinit(allocator);
    }

    try discoverTargets(allocator, search_root, &targets, 0);

    if (targets.items.len == 0) {
        print("ℹ️  No node_modules or site-packages directories found under {s}\n", .{search_root});
        print("💡 Run from a project root or pass the directory path explicitly.\n", .{});
        return;
    }

    print("📦 Found {} package directory/directories to scan\n\n", .{targets.items.len});

    var total_critical: usize = 0;
    var total_high: usize = 0;
    var total_medium: usize = 0;
    var total_recent: usize = 0;
    var total_clean: usize = 0;

    for (targets.items) |target| {
        const label = switch (target.kind) {
            .node_modules => "node_modules",
            .site_packages => "site-packages",
        };

        print("─────────────────────────────────────────────\n", .{});
        print("📁 {s}: {s}\n", .{ label, target.path });
        printSeparator('-', 45);

        const findings = switch (target.kind) {
            .node_modules => scanNodeModules(allocator, target.path) catch |err| {
                print("  ❌ Scan failed: {}\n", .{err});
                continue;
            },
            .site_packages => scanPipPackages(allocator, target.path) catch |err| {
                print("  ❌ Scan failed: {}\n", .{err});
                continue;
            },
        };
        defer {
            for (findings) |*f| {
                var mf = f;
                mf.deinit();
            }
            allocator.free(findings);
        }

        if (findings.len == 0) {
            print("  ✅ No suspicious packages found\n", .{});
            total_clean += 1;
            continue;
        }

        var section_had_output = false;

        for (findings) |*f| {
            const skip = recent_only and f.scripts.len == 0;
            if (skip) continue;
            if (!verbose and f.risk == .info and f.scripts.len == 0) {
                total_recent += 1;
                continue;
            }

            printFinding(f);
            section_had_output = true;

            switch (f.risk) {
                .critical => total_critical += 1,
                .high => total_high += 1,
                .medium => total_medium += 1,
                else => total_recent += 1,
            }
        }

        if (!section_had_output) {
            // All findings were .info (recently modified, no scripts)
            const recent_count = blk: {
                var cnt: usize = 0;
                for (findings) |f| if (f.recently_modified) {
                    cnt += 1;
                };
                break :blk cnt;
            };
            if (recent_count > 0) {
                print("  ⏱️  {} recently installed/modified package(s) (no lifecycle scripts)\n", .{recent_count});
                print("     Tip: run with --verbose to list them\n", .{});
                total_recent += recent_count;
            } else {
                print("  ✅ No suspicious packages found\n", .{});
                total_clean += 1;
            }
        }
    }

    // Summary
    print("\n", .{});
    printSeparator('=', 45);
    print("📊 Audit Summary\n", .{});
    printSeparator('-', 45);
    print("  💀 Critical : {}\n", .{total_critical});
    print("  🔴 High     : {}\n", .{total_high});
    print("  🟠 Medium   : {}\n", .{total_medium});
    print("  ⏱️  Recent   : {}\n", .{total_recent});
    print("  ✅ Clean    : {}\n", .{total_clean});
    printSeparator('=', 45);

    if (total_critical > 0 or total_high > 0) {
        print("\n⚠️  Action required: review the flagged packages above.\n", .{});
        print("   Consider:\n", .{});
        print("   • Pinning to a specific known-good version\n", .{});
        print("   • Reviewing the full script with: here pkgbuild <pkg>\n", .{});
        print("   • Deleting node_modules and re-installing from a locked lockfile\n", .{});
        print("   • Running `npm audit fix` / `bun audit` for CVE patches\n", .{});
    } else if (total_medium > 0) {
        print("\n💡 Some packages use patterns worth reviewing (outbound HTTP, env access).\n", .{});
        print("   These are common in legitimate build tools – use judgement.\n", .{});
    } else {
        print("\n✨ Audit clean – no lifecycle-script attack indicators found.\n", .{});
    }
    print("\n", .{});
}

// ---------------------------------------------------------------------------
// PKGBUILD viewer (Arch / AUR)
// ---------------------------------------------------------------------------

/// `here pkgbuild <package-name>`
/// Fetches and displays the PKGBUILD from AUR, or shows cached PKGBUILD if
/// the package was installed via yay/paru.
pub fn viewPkgbuild(allocator: Allocator, package_name: []const u8) !void {
    print("\n📦 PKGBUILD viewer: {s}\n", .{package_name});
    printSeparator('-', 40);

    // 1. Try yay/paru --getpkgbuild  (most reliable for AUR)
    const aur_helpers = [_][]const u8{ "yay", "paru" };
    for (aur_helpers) |helper| {
        const argv = [_][]const u8{ helper, "--getpkgbuild", package_name };

        // Check if helper exists
        var which = std.process.Child.init(&.{ "which", helper }, allocator);
        which.stdout_behavior = .Ignore;
        which.stderr_behavior = .Ignore;
        const which_term = which.spawnAndWait() catch continue;
        if (which_term != .Exited or which_term.Exited != 0) continue;

        print("📥 Fetching PKGBUILD via {s}...\n\n", .{helper});

        var child = std.process.Child.init(&argv, allocator);
        child.stdout_behavior = .Inherit;
        child.stderr_behavior = .Inherit;
        const term = child.spawnAndWait() catch continue;
        if (term == .Exited and term.Exited == 0) {
            // yay --getpkgbuild downloads to cwd; cat the file for the user
            const pkgbuild_path = try std.fs.path.join(allocator, &.{ package_name, "PKGBUILD" });
            defer allocator.free(pkgbuild_path);

            if (std.fs.cwd().readFileAlloc(allocator, pkgbuild_path, 512 * 1024)) |data| {
                defer allocator.free(data);
                print("\n", .{});
                printSeparator('-', 60);
                print("{s}\n", .{data});
                printSeparator('-', 60);
                print("\n📂 Full PKGBUILD saved in ./{s}/PKGBUILD\n", .{package_name});
                print("💡 Review checksums, sources, and the build() / package() functions\n", .{});
                print("   before running `{s} -S {s}`\n\n", .{ helper, package_name });
            } else |_| {
                // yay may have printed it inline already
                print("\n💡 Review before running `{s} -S {s}`\n\n", .{ helper, package_name });
            }
            return;
        }
    }

    // 2. Try asp (Arch source package tool) for official repo packages
    {
        var which = std.process.Child.init(&.{ "which", "asp" }, allocator);
        which.stdout_behavior = .Ignore;
        which.stderr_behavior = .Ignore;
        _ = which.spawnAndWait() catch null;

        const asp_argv = [_][]const u8{ "asp", "show", package_name };
        var child = std.process.Child.init(&asp_argv, allocator);
        child.stdout_behavior = .Inherit;
        child.stderr_behavior = .Inherit;
        if (child.spawnAndWait()) |term| {
            if (term == .Exited and term.Exited == 0) return;
        } else |_| {}
    }

    // 3. Fall back to fetching raw PKGBUILD from AUR cgit via curl
    print("🌐 Fetching PKGBUILD from AUR...\n", .{});
    const aur_url = try std.fmt.allocPrint(
        allocator,
        "https://aur.archlinux.org/cgit/aur.git/plain/PKGBUILD?h={s}",
        .{package_name},
    );
    defer allocator.free(aur_url);

    const curl_argv = [_][]const u8{ "curl", "-fsSL", aur_url };
    if (runCaptured(allocator, &curl_argv)) |data| {
        defer allocator.free(data);

        if (data.len == 0 or std.mem.startsWith(u8, data, "Not found")) {
            print("❌ Package '{s}' not found in AUR.\n", .{package_name});
            print("💡 Check the exact package name at https://aur.archlinux.org/\n\n", .{});
            return;
        }

        print("\n", .{});
        printSeparator('-', 60);
        print("{s}\n", .{data});
        printSeparator('-', 60);
        print("\n🔎 PKGBUILD tips:\n", .{});
        print("  • Verify 'source' URLs point to trusted upstream repositories\n", .{});
        print("  • Check 'sha256sums'/'b2sums' are present (missing = no integrity check)\n", .{});
        print("  • Review prepare(), build(), and package() for unexpected commands\n", .{});
        print("  • Watch for: curl|bash, eval, obfuscated strings, non-standard install paths\n\n", .{});
    } else |_| {
        print("❌ Could not fetch PKGBUILD. Is 'curl' installed?\n", .{});
        print("💡 Try: curl -fsSL '{s}'\n\n", .{aur_url});
    }
}

// ---------------------------------------------------------------------------
// `here pkgbuild` entry point
// ---------------------------------------------------------------------------

pub fn runPkgbuild(allocator: Allocator, args: []const []const u8) !void {
    if (args.len == 0) {
        print("❌ No package name specified\n", .{});
        print("💡 Usage: here pkgbuild <package-name>\n", .{});
        print("   Examples:\n", .{});
        print("     here pkgbuild yay\n", .{});
        print("     here pkgbuild visual-studio-code-bin\n", .{});
        return;
    }
    try viewPkgbuild(allocator, args[0]);
}
