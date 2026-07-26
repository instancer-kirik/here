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
// Cross-ecosystem defenses
// ---------------------------------------------------------------------------
// Lessons learned from Hex (cooldown, retirement), RubyGems (owner roles,
// bundle-audit), PyPI (trusted publishing, attestations), crates.io (cargo-
// audit, build.rs risk), and npq (Author Marshall: publisher-change signal).
//
// Three converging defenses every ecosystem has independently discovered:
//   1. Version-age gating  – don't blindly trust brand-new releases
//   2. Publisher continuity – a new face on an old package is high-signal
//   3. Build-script auditing – any code that runs at install time is a risk
// ---------------------------------------------------------------------------

// ---- 1. Typosquatting detector -------------------------------------------
//
// A static list of the most-downloaded packages across npm / pip / gems /
// cargo. We check each installed package name against this list with a
// Levenshtein distance of 1 or 2 to surface likely typosquats.

const POPULAR_PACKAGES = [_][]const u8{
    // npm
    "react",       "react-dom",       "lodash",             "express",
    "axios",       "typescript",      "webpack",            "babel-core",
    "eslint",      "prettier",        "jest",               "mocha",
    "moment",      "chalk",           "commander",          "dotenv",
    "uuid",        "async",           "underscore",         "request",
    "bluebird",    "mkdirp",          "rimraf",             "glob",
    "minimist",    "yargs",           "semver",             "debug",
    "through2",    "readable-stream", "colors",             "inquirer",
    "passport",    "socket.io",       "mongoose",           "sequelize",
    "knex",        "redis",           "bcrypt",             "jsonwebtoken",
    "multer",      "sharp",           "cheerio",            "puppeteer",
    "playwright",  "cypress",         "vitest",             "rollup",
    "vite",        "esbuild",         "turbo",              "nx",
    "next",        "nuxt",            "svelte",             "vue",
    "angular",     "gatsby",          "astro",              "remix",
    // pip
    "requests",    "numpy",           "pandas",             "scipy",
    "matplotlib",  "pillow",          "flask",              "django",
    "fastapi",     "sqlalchemy",      "celery",             "pydantic",
    "boto3",       "paramiko",        "cryptography",       "pyopenssl",
    "pytest",      "setuptools",      "pip",                "wheel",
    "urllib3",     "certifi",         "charset-normalizer",
    // gems
    "rails",
    "rake",        "bundler",         "devise",             "activerecord",
    "nokogiri",    "rspec",           "sidekiq",            "puma",
    "sinatra",     "capistrano",      "rubocop",
    // cargo
               "serde",
    "tokio",       "rand",            "anyhow",             "clap",
    "thiserror",   "log",             "env-logger",         "reqwest",
    "hyper",       "actix-web",       "axum",               "rayon",
    "lazy-static", "once-cell",       "bytes",
};

/// Compute Levenshtein edit distance between two strings.
/// Uses stack-allocated arrays (max 64 chars) to avoid any heap allocation
/// in the hot path – this is called for every package × every popular name.
fn levenshtein(a: []const u8, b: []const u8) usize {
    if (a.len == 0) return b.len;
    if (b.len == 0) return a.len;

    const MAX = 64;
    if (a.len > MAX or b.len > MAX) {
        // Fall back to a simple bound: if they differ in length by more than
        // our threshold we already skip before calling, so this is safe.
        return if (a.len > b.len) a.len - b.len else b.len - a.len;
    }

    var prev: [MAX + 1]usize = undefined;
    var curr: [MAX + 1]usize = undefined;

    for (0..b.len + 1) |j| prev[j] = j;

    for (0..a.len) |i| {
        curr[0] = i + 1;
        for (0..b.len) |j| {
            const cost: usize = if (a[i] == b[j]) 0 else 1;
            curr[j + 1] = @min(
                curr[j] + 1,
                @min(prev[j + 1] + 1, prev[j] + cost),
            );
        }
        @memcpy(prev[0 .. b.len + 1], curr[0 .. b.len + 1]);
    }
    return prev[b.len];
}

pub const TyposquatFinding = struct {
    installed: []u8,
    similar_to: []u8,
    distance: usize,
    allocator: Allocator,

    pub fn deinit(self: *TyposquatFinding) void {
        self.allocator.free(self.installed);
        self.allocator.free(self.similar_to);
    }
};

/// Check a package name against the popular-package list.
/// Returns a TyposquatFinding if the name is suspiciously close to a popular package
/// but is not itself that package.
pub fn detectTyposquat(allocator: Allocator, pkg_name: []const u8) ?TyposquatFinding {
    // Strip scoped prefix (@org/) for matching
    const name = if (std.mem.startsWith(u8, pkg_name, "@")) blk: {
        const slash = std.mem.indexOf(u8, pkg_name, "/") orelse break :blk pkg_name;
        break :blk pkg_name[slash + 1 ..];
    } else pkg_name;

    for (POPULAR_PACKAGES) |popular| {
        if (std.mem.eql(u8, name, popular)) return null; // is the popular package itself

        // Skip if lengths are too different to be a typosquat
        const len_diff = if (name.len > popular.len) name.len - popular.len else popular.len - name.len;
        if (len_diff > 3) continue;

        const dist = levenshtein(name, popular);
        if (dist > 0 and dist <= 2) {
            return TyposquatFinding{
                .installed = dupeStr(allocator, pkg_name) catch return null,
                .similar_to = dupeStr(allocator, popular) catch return null,
                .distance = dist,
                .allocator = allocator,
            };
        }
    }
    return null;
}

// ---- 2. npm registry publisher-change & version-age check ----------------
//
// Implements the "Author Marshall" pattern from npq:
//   - Who published the installed version? Is it a new face on this package?
//   - How old is this version? (Hex cooldown concept applied post-install)
//   - Is the package deprecated? (Hex retirement equivalent)
//
// Uses the public npm registry API (no auth required).
// Requires curl. Called only with --deep flag to avoid spamming the registry.

pub const RegistryFinding = struct {
    pkg_name: []u8,
    installed_version: []u8,
    publisher_is_new: bool, // first time this npm user published to this package
    publisher_name: []u8, // _npmUser.name for the installed version
    version_age_days: i64, // how many days since this version was published
    is_deprecated: bool, // package or version marked deprecated
    deprecation_msg: []u8, // deprecation message if any
    allocator: Allocator,

    pub fn deinit(self: *RegistryFinding) void {
        self.allocator.free(self.pkg_name);
        self.allocator.free(self.installed_version);
        self.allocator.free(self.publisher_name);
        self.allocator.free(self.deprecation_msg);
    }

    pub fn risk(self: *const RegistryFinding) RiskLevel {
        if (self.publisher_is_new and self.version_age_days <= 21) return .high;
        if (self.publisher_is_new) return .medium;
        if (self.version_age_days <= 7) return .medium;
        if (self.is_deprecated) return .low;
        return .info;
    }
};

/// Parse an ISO-8601 datetime string ("2024-01-15T10:30:00.000Z") into a Unix
/// timestamp. Handles the subset of dates we get from the npm registry.
fn parseIso8601(s: []const u8) ?i64 {
    // Expect at least "YYYY-MM-DD"
    if (s.len < 10) return null;
    const year = std.fmt.parseInt(i32, s[0..4], 10) catch return null;
    const month = std.fmt.parseInt(u32, s[5..7], 10) catch return null;
    const day = std.fmt.parseInt(u32, s[8..10], 10) catch return null;
    if (month < 1 or month > 12 or day < 1 or day > 31) return null;

    // Days since Unix epoch using a simple Gregorian calculation.
    // Good enough for year >= 1970 and 30-year date range we care about.
    const days_per_month = [_]u32{ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
    var total_days: i64 = 0;
    var y: i32 = 1970;
    while (y < year) : (y += 1) {
        const leap = (@rem(y, 4) == 0 and (@rem(y, 100) != 0 or @rem(y, 400) == 0));
        total_days += if (leap) 366 else 365;
    }
    const leap_cur = (@rem(year, 4) == 0 and (@rem(year, 100) != 0 or @rem(year, 400) == 0));
    var m: u32 = 1;
    while (m < month) : (m += 1) {
        var dpm = days_per_month[m - 1];
        if (m == 2 and leap_cur) dpm = 29;
        total_days += dpm;
    }
    total_days += day - 1;
    return total_days * 86400;
}

/// Query the npm registry for publisher and age information about a package version.
/// Returns null if curl is unavailable or the package is not on npm.
pub fn checkNpmRegistry(allocator: Allocator, pkg_name: []const u8, installed_version: []const u8) !?RegistryFinding {
    // Build registry URL; scope (@org/pkg) needs encoding
    const encoded_name = if (std.mem.startsWith(u8, pkg_name, "@")) blk: {
        const slash_pos = std.mem.indexOf(u8, pkg_name, "/") orelse break :blk pkg_name;
        // URL-encode the slash to %2F
        const scope = pkg_name[0..slash_pos];
        const name = pkg_name[slash_pos + 1 ..];
        break :blk try std.fmt.allocPrint(allocator, "{s}%2F{s}", .{ scope, name });
    } else pkg_name;
    const free_encoded = !std.mem.eql(u8, encoded_name, pkg_name);
    defer if (free_encoded) allocator.free(encoded_name);

    const url = try std.fmt.allocPrint(allocator, "https://registry.npmjs.org/{s}", .{encoded_name});
    defer allocator.free(url);

    const json_data = runCaptured(allocator, &.{ "curl", "-fsSL", "--max-time", "8", url }) catch return null;
    defer allocator.free(json_data);
    if (json_data.len == 0) return null;

    const parsed = std.json.parseFromSlice(std.json.Value, allocator, json_data, .{}) catch return null;
    defer parsed.deinit();

    const root = parsed.value.object;

    // --- Deprecation check ---
    const deprecated_val = root.get("deprecated");
    const is_deprecated = deprecated_val != null and deprecated_val.? == .string and deprecated_val.?.string.len > 0;
    const deprecation_msg = if (is_deprecated) deprecated_val.?.string else "";

    // Also check per-version deprecation
    var ver_deprecated = false;
    var ver_deprecation_msg: []const u8 = "";
    const versions_val = root.get("versions");
    if (versions_val != null and versions_val.? == .object) {
        const ver_obj = versions_val.?.object.get(installed_version);
        if (ver_obj != null and ver_obj.? == .object) {
            const vd = ver_obj.?.object.get("deprecated");
            if (vd != null and vd.? == .string and vd.?.string.len > 0) {
                ver_deprecated = true;
                ver_deprecation_msg = vd.?.string;
            }
        }
    }
    const final_deprecated = is_deprecated or ver_deprecated;
    const final_dep_msg = if (ver_deprecated) ver_deprecation_msg else if (is_deprecated) deprecation_msg else "";

    // --- Version publish time → age ---
    const time_val = root.get("time");
    var version_age_days: i64 = -1;
    if (time_val != null and time_val.? == .object) {
        const publish_time_val = time_val.?.object.get(installed_version);
        if (publish_time_val != null and publish_time_val.? == .string) {
            const ts = parseIso8601(publish_time_val.?.string);
            if (ts) |publish_ts| {
                const now: i64 = @intCast(std.time.timestamp());
                version_age_days = @divFloor(now - publish_ts, 86400);
            }
        }
    }

    // --- Publisher / Author Marshall check ---
    // Get the _npmUser for the installed version
    var installed_publisher: []const u8 = "";
    if (versions_val != null and versions_val.? == .object) {
        const ver_obj = versions_val.?.object.get(installed_version);
        if (ver_obj != null and ver_obj.? == .object) {
            const npm_user = ver_obj.?.object.get("_npmUser");
            if (npm_user != null and npm_user.? == .object) {
                const uname = npm_user.?.object.get("name");
                if (uname != null and uname.? == .string) {
                    installed_publisher = uname.?.string;
                }
            }
        }
    }

    // Collect the set of all historical publishers (for all versions older than installed)
    var historical_publishers = ArrayList([]const u8){};
    defer historical_publishers.deinit(allocator);

    if (versions_val != null and versions_val.? == .object) {
        var vit = versions_val.?.object.iterator();
        while (vit.next()) |entry| {
            const ver = entry.key_ptr.*;
            if (std.mem.eql(u8, ver, installed_version)) continue;
            if (entry.value_ptr.* != .object) continue;
            const npm_user = entry.value_ptr.*.object.get("_npmUser");
            if (npm_user == null or npm_user.? != .object) continue;
            const uname = npm_user.?.object.get("name");
            if (uname == null or uname.? != .string) continue;
            try historical_publishers.append(allocator, uname.?.string);
        }
    }

    var publisher_is_new = installed_publisher.len > 0;
    for (historical_publishers.items) |hist| {
        if (std.mem.eql(u8, hist, installed_publisher)) {
            publisher_is_new = false;
            break;
        }
    }
    // Edge case: if there's only one version ever (this one), it's not a "new" publisher
    if (historical_publishers.items.len == 0) publisher_is_new = false;

    // Only return a finding if something is interesting
    if (!publisher_is_new and version_age_days > 21 and !final_deprecated) return null;

    return RegistryFinding{
        .pkg_name = try dupeStr(allocator, pkg_name),
        .installed_version = try dupeStr(allocator, installed_version),
        .publisher_is_new = publisher_is_new,
        .publisher_name = try dupeStr(allocator, installed_publisher),
        .version_age_days = version_age_days,
        .is_deprecated = final_deprecated,
        .deprecation_msg = try dupeStr(allocator, final_dep_msg),
        .allocator = allocator,
    };
}

// ---- 3. Cargo build.rs scanner -------------------------------------------
//
// In Rust, `build.rs` is an arbitrary program that runs at compile time.
// It is the exact analog of npm's postinstall: legitimate uses exist (bindgen,
// compiling C deps), but it is also the primary supply-chain attack vector in
// the Rust ecosystem (see crates.io security audit, cargo-crev rationale).

pub const BuildRsFinding = struct {
    crate_name: []u8,
    build_rs_path: []u8,
    flags: [][]u8,
    risk: RiskLevel,
    allocator: Allocator,

    pub fn deinit(self: *BuildRsFinding) void {
        self.allocator.free(self.crate_name);
        self.allocator.free(self.build_rs_path);
        for (self.flags) |f| self.allocator.free(f);
        self.allocator.free(self.flags);
    }
};

// Patterns suspicious specifically in build.rs context
const BUILD_RS_PATTERNS = [_]SuspiciousPattern{
    .{ .pattern = "Command::new(", .description = "spawns a shell command during build", .risk = .high },
    .{ .pattern = "std::process::Command", .description = "process execution during build", .risk = .high },
    .{ .pattern = "reqwest", .description = "HTTP client used in build script", .risk = .high },
    .{ .pattern = "ureq", .description = "HTTP client used in build script", .risk = .high },
    .{ .pattern = "curl", .description = "curl called from build script", .risk = .high },
    .{ .pattern = "wget", .description = "wget called from build script", .risk = .high },
    .{ .pattern = "TcpStream", .description = "raw TCP connection in build script", .risk = .high },
    .{ .pattern = "include!(concat!(", .description = "dynamic file inclusion (obfuscation)", .risk = .medium },
    .{ .pattern = "env!(", .description = "reads env var at compile time", .risk = .medium },
    .{ .pattern = "CARGO_MANIFEST_DIR", .description = "accesses source tree path", .risk = .low },
    .{ .pattern = "~/.ssh", .description = "accesses SSH directory", .risk = .critical },
    .{ .pattern = "~/.aws", .description = "accesses AWS credentials", .risk = .critical },
    .{ .pattern = "~/.cargo/credentials", .description = "accesses Cargo registry token", .risk = .critical },
    .{ .pattern = "unsafe", .description = "unsafe block in build script", .risk = .low },
};

/// Scan a single build.rs file for suspicious patterns.
fn auditBuildRs(allocator: Allocator, build_rs_path: []const u8, crate_name: []const u8) !?BuildRsFinding {
    const content = std.fs.cwd().readFileAlloc(allocator, build_rs_path, 512 * 1024) catch return null;
    defer allocator.free(content);

    var flags = ArrayList([]u8){};
    errdefer flags.deinit(allocator);
    var risk: RiskLevel = .info;

    for (BUILD_RS_PATTERNS) |sp| {
        if (std.mem.indexOf(u8, content, sp.pattern) != null) {
            try flags.append(allocator, try dupeStr(allocator, sp.description));
            risk = maxRisk(risk, sp.risk);
        }
    }

    if (flags.items.len == 0) return null;

    return BuildRsFinding{
        .crate_name = try dupeStr(allocator, crate_name),
        .build_rs_path = try dupeStr(allocator, build_rs_path),
        .flags = try flags.toOwnedSlice(allocator),
        .risk = risk,
        .allocator = allocator,
    };
}

/// Walk a directory tree looking for Cargo.toml + build.rs pairs.
/// Returns all suspicious build scripts found.
pub fn scanCargoBuildScripts(allocator: Allocator, search_root: []const u8) ![]BuildRsFinding {
    var findings = ArrayList(BuildRsFinding){};
    errdefer findings.deinit(allocator);

    try walkCargoDir(allocator, search_root, &findings, 0);
    return findings.toOwnedSlice(allocator);
}

fn walkCargoDir(allocator: Allocator, dir_path: []const u8, findings: *ArrayList(BuildRsFinding), depth: usize) !void {
    if (depth > 8) return;

    var dir = if (std.fs.path.isAbsolute(dir_path))
        std.fs.openDirAbsolute(dir_path, .{ .iterate = true }) catch return
    else
        std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch return;
    defer dir.close();

    var it = dir.iterate();
    while (try it.next()) |entry| {
        if (std.mem.startsWith(u8, entry.name, ".")) continue;
        if (std.mem.eql(u8, entry.name, "target")) continue; // build output

        if (entry.kind == .directory) {
            const child = try std.fs.path.join(allocator, &.{ dir_path, entry.name });
            defer allocator.free(child);
            try walkCargoDir(allocator, child, findings, depth + 1);
            continue;
        }

        if (!std.mem.eql(u8, entry.name, "build.rs")) continue;

        // Found a build.rs; try to determine the crate name from sibling Cargo.toml
        const cargo_toml_path = try std.fs.path.join(allocator, &.{ dir_path, "Cargo.toml" });
        defer allocator.free(cargo_toml_path);
        const crate_name = blk: {
            const toml = std.fs.cwd().readFileAlloc(allocator, cargo_toml_path, 64 * 1024) catch break :blk entry.name;
            defer allocator.free(toml);
            // Very simple TOML name extraction: find 'name = "..."'
            const name_key = "name = \"";
            const start = std.mem.indexOf(u8, toml, name_key) orelse break :blk entry.name;
            const after = toml[start + name_key.len ..];
            const end = std.mem.indexOf(u8, after, "\"") orelse break :blk entry.name;
            break :blk after[0..end];
        };

        const build_rs_path = try std.fs.path.join(allocator, &.{ dir_path, "build.rs" });
        defer allocator.free(build_rs_path);

        if (try auditBuildRs(allocator, build_rs_path, crate_name)) |finding| {
            try findings.append(allocator, finding);
        }
    }
}

// ---- 4. Ecosystem-native audit delegation --------------------------------
//
// Delegate to each ecosystem's own CVE / retirement / advisory database.
// We cover more ground by running the tools that maintain up-to-date advisories.

const EcosystemAuditSpec = struct {
    indicator_file: []const u8, // file that signals this ecosystem is present
    tool: []const u8, // binary to run
    args: []const []const u8, // argv
    label: []const u8,
};

const ECOSYSTEM_AUDITORS = [_]EcosystemAuditSpec{
    // npm / bun / yarn / pnpm handled separately in runNativeAudit (lockfile detection)
    .{ .indicator_file = "mix.exs", .tool = "mix", .args = &.{ "mix", "hex.audit" }, .label = "Elixir / Hex" },
    .{ .indicator_file = "Gemfile.lock", .tool = "bundle", .args = &.{ "bundle", "exec", "bundle-audit", "check", "--update" }, .label = "Ruby / Bundler" },
    .{ .indicator_file = "Cargo.lock", .tool = "cargo", .args = &.{ "cargo", "audit" }, .label = "Rust / Cargo" },
    .{ .indicator_file = "go.sum", .tool = "govulncheck", .args = &.{ "govulncheck", "./..." }, .label = "Go / govulncheck" },
    .{ .indicator_file = "requirements.txt", .tool = "pip", .args = &.{ "pip", "audit" }, .label = "Python / pip" },
    .{ .indicator_file = "poetry.lock", .tool = "poetry", .args = &.{ "poetry", "check" }, .label = "Python / Poetry" },
    .{ .indicator_file = "Pipfile.lock", .tool = "pipenv", .args = &.{ "pipenv", "check" }, .label = "Python / Pipenv" },
};

/// Check whether a command is on PATH by probing common binary directories.
/// Zero subprocess forks – just stat() calls.
fn commandExistsOnPath(cmd: []const u8) bool {
    const path_dirs = [_][]const u8{
        "/usr/bin", "/usr/local/bin", "/bin",
        "/usr/sbin", "/snap/bin", "/home/linuxbrew/.linuxbrew/bin",
    };
    var buf: [512]u8 = undefined;
    for (path_dirs) |dir| {
        const full = std.fmt.bufPrint(&buf, "{s}/{s}", .{ dir, cmd }) catch continue;
        std.fs.cwd().access(full, .{}) catch continue;
        return true;
    }
    // Also check $PATH via the environment variable if the above misses
    const path_env = std.process.getEnvVarOwned(std.heap.page_allocator, "PATH") catch return false;
    defer std.heap.page_allocator.free(path_env);
    var parts = std.mem.splitScalar(u8, path_env, ':');
    while (parts.next()) |dir| {
        const full = std.fmt.bufPrint(&buf, "{s}/{s}", .{ dir, cmd }) catch continue;
        std.fs.cwd().access(full, .{}) catch continue;
        return true;
    }
    return false;
}

/// Default (fast) mode: one access() per ecosystem indicator file, zero forks.
/// Prints suggestions for any tool not yet installed.
/// With run_tools=true (--deep), actually executes the audit commands.
fn runEcosystemAuditors(allocator: Allocator, project_dir: []const u8, run_tools: bool) void {
    for (ECOSYSTEM_AUDITORS) |spec| {
        const indicator = std.fs.path.join(allocator, &.{ project_dir, spec.indicator_file }) catch continue;
        defer allocator.free(indicator);
        std.fs.cwd().access(indicator, .{}) catch continue;

        const tool_present = commandExistsOnPath(spec.tool);

        if (!run_tools) {
            // Fast path: just tell the user what's available
            if (tool_present) {
                print("💡 {s} detected – run `here audit --deep` to execute {s}\n",
                    .{ spec.label, spec.tool });
            } else {
                print("💡 {s} detected – install '{s}' for advisory checks\n",
                    .{ spec.label, spec.tool });
            }
            continue;
        }

        // --deep mode: actually run the tool
        if (!tool_present) {
            print("💡 {s}: '{s}' not found, skipping\n", .{ spec.label, spec.tool });
            continue;
        }

        print("\n🔍 Running {s} advisory check...\n", .{spec.label});
        var child = std.process.Child.init(spec.args, allocator);
        child.cwd = project_dir;
        child.stdout_behavior = .Inherit;
        child.stderr_behavior = .Inherit;
        _ = child.spawnAndWait() catch {};
    }
}

// ---- 5. Lockfile presence / freshness check ------------------------------
//
// Inspired by Bundler --frozen and Cargo's philosophy of immutable Cargo.lock.
// A missing or gitignored lockfile means every install can silently pull
// different versions. We surface this as a low-level warning.

const LockfileSpec = struct {
    manifest: []const u8,
    lockfile: []const u8,
    ecosystem: []const u8,
    freeze_hint: []const u8,
};

const LOCKFILE_SPECS = [_]LockfileSpec{
    .{ .manifest = "package.json", .lockfile = "package-lock.json", .ecosystem = "npm", .freeze_hint = "`npm ci` instead of `npm install` in CI" },
    .{ .manifest = "package.json", .lockfile = "bun.lockb", .ecosystem = "bun", .freeze_hint = "`bun install --frozen-lockfile` in CI" },
    .{ .manifest = "package.json", .lockfile = "yarn.lock", .ecosystem = "yarn", .freeze_hint = "`yarn install --frozen-lockfile` in CI" },
    .{ .manifest = "package.json", .lockfile = "pnpm-lock.yaml", .ecosystem = "pnpm", .freeze_hint = "`pnpm install --frozen-lockfile` in CI" },
    .{ .manifest = "Cargo.toml", .lockfile = "Cargo.lock", .ecosystem = "cargo", .freeze_hint = "commit Cargo.lock and use `cargo fetch`" },
    .{ .manifest = "Gemfile", .lockfile = "Gemfile.lock", .ecosystem = "bundler", .freeze_hint = "`bundle install --frozen` in CI" },
    .{ .manifest = "mix.exs", .lockfile = "mix.lock", .ecosystem = "mix", .freeze_hint = "`mix deps.get --only prod`" },
    .{ .manifest = "pyproject.toml", .lockfile = "poetry.lock", .ecosystem = "poetry", .freeze_hint = "`poetry install --no-update`" },
    .{ .manifest = "Pipfile", .lockfile = "Pipfile.lock", .ecosystem = "pipenv", .freeze_hint = "`pipenv install --ignore-pipfile`" },
};

fn checkLockfiles(project_dir: []const u8, allocator: Allocator) void {
    var printed_header = false;

    for (LOCKFILE_SPECS) |spec| {
        const manifest_path = std.fs.path.join(allocator, &.{ project_dir, spec.manifest }) catch continue;
        defer allocator.free(manifest_path);
        std.fs.cwd().access(manifest_path, .{}) catch continue;

        const lock_path = std.fs.path.join(allocator, &.{ project_dir, spec.lockfile }) catch continue;
        defer allocator.free(lock_path);

        if (std.fs.cwd().access(lock_path, .{})) {
            // lockfile exists – good
        } else |_| {
            if (!printed_header) {
                print("\n⚠️  Missing lockfiles detected\n", .{});
                print("   Lockfiles pin exact dependency versions and hashes.\n", .{});
                print("   Without them, every install can pull different code.\n", .{});
                printed_header = true;
            }
            print("   🔓 {s}: no {s} found\n", .{ spec.ecosystem, spec.lockfile });
            print("      Fix: {s}\n", .{spec.freeze_hint});
        }
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

/// `here audit [path] [--deep] [--verbose] [--recent]`
///
/// Flags:
///   --deep       Enable npm registry publisher-change + version-age checks
///                (makes one HTTPS request per direct dependency)
///   --verbose    Show all recently installed packages, even without scripts
///   --recent     Show only recently modified packages
///
/// Cross-ecosystem defenses applied:
///   • Lifecycle/build-script scanning  (npm postinstall, Cargo build.rs)
///   • Typosquatting detection          (Levenshtein vs popular packages)
///   • npm publisher-change signal      (Author Marshall / npq concept)    [--deep]
///   • Version publish-date age         (Hex cooldown applied post-install) [--deep]
///   • npm deprecation status           (Hex retirement equivalent)        [--deep]
///   • Ecosystem-native audit delegation (mix hex.audit, cargo audit, etc.)
///   • Lockfile presence check          (Bundler --frozen, Cargo philosophy)
pub fn runAudit(allocator: Allocator, args: []const []const u8) !void {
    // Determine search root – always resolve to an absolute path
    var search_root_buf: [std.fs.max_path_bytes]u8 = undefined;
    const cwd_abs = try std.process.getCwd(&search_root_buf);
    var abs_buf: [std.fs.max_path_bytes]u8 = undefined;
    const search_root = if (args.len > 0 and !std.mem.startsWith(u8, args[0], "--")) blk: {
        const given = args[0];
        if (std.fs.path.isAbsolute(given)) break :blk given;
        // Resolve relative path against cwd
        const joined = try std.fs.path.join(allocator, &.{ cwd_abs, given });
        defer allocator.free(joined);
        const resolved = try std.fs.realpath(joined, &abs_buf);
        break :blk resolved;
    } else cwd_abs;

    const verbose = for (args) |a| {
        if (std.mem.eql(u8, a, "--verbose") or std.mem.eql(u8, a, "-v")) break true;
    } else false;

    const recent_only = for (args) |a| {
        if (std.mem.eql(u8, a, "--recent")) break true;
    } else false;

    // --deep: enables registry API calls (publisher change + version age + deprecation)
    const deep = for (args) |a| {
        if (std.mem.eql(u8, a, "--deep")) break true;
    } else false;

    print("\n🛡️  Supply-Chain Audit\n", .{});
    print("====================\n", .{});
    print("📂 Scanning: {s}\n", .{search_root});
    print("🎯 Defenses: lifecycle scripts, typosquatting, recency, lockfile check", .{});
    if (deep) print(", registry publisher/age (--deep)", .{});
    print("\n\n", .{});

    // --- Lockfile presence (Bundler --frozen / Cargo philosophy) ---
    checkLockfiles(search_root, allocator);

    // --- Ecosystem-native CVE / advisory / retirement audits ---
    runNativeAudit(allocator, search_root);
    runEcosystemAuditors(allocator, search_root, deep);

    // --- Cargo build.rs scanning (only if Cargo.toml or .rs files are present) ---
    print("\n", .{});
    const has_cargo = blk: {
        const ct = std.fs.path.join(allocator, &.{ search_root, "Cargo.toml" }) catch break :blk false;
        defer allocator.free(ct);
        if (std.fs.cwd().access(ct, .{})) { break :blk true; } else |_| { break :blk false; }
    };
    if (has_cargo) {
        const bfindings = scanCargoBuildScripts(allocator, search_root) catch |err| blk: {
            print("  ⚠️  Cargo build.rs scan failed: {}\n", .{err});
            break :blk &[_]BuildRsFinding{};
        };
        defer {
            for (bfindings) |*bf| {
                @constCast(bf).deinit();
            }
            allocator.free(bfindings);
        }

        if (bfindings.len > 0) {
            print("🦀 Cargo build.rs findings:\n", .{});
            printSeparator('-', 40);
            for (bfindings) |*bf| {
                print("  {s} {s}\n", .{ bf.risk.emoji(), bf.crate_name });
                print("     {s}\n", .{bf.build_rs_path});
                for (bf.flags) |flag| {
                    print("     ⚠️  {s}\n", .{flag});
                }
            }
        }
    }

    // --- node_modules / site-packages discovery and scan ---
    var targets = ArrayList(ScanTarget){};
    defer {
        for (targets.items) |*t| t.deinit();
        targets.deinit(allocator);
    }

    try discoverTargets(allocator, search_root, &targets, 0);

    if (targets.items.len == 0) {
        print("ℹ️  No node_modules or site-packages found under {s}\n", .{search_root});
    }

    var total_critical: usize = 0;
    var total_high: usize = 0;
    var total_medium: usize = 0;
    var total_recent: usize = 0;
    var total_clean: usize = 0;
    var total_typosquat: usize = 0;
    var total_registry: usize = 0;

    for (targets.items) |target| {
        const label = switch (target.kind) {
            .node_modules => "node_modules",
            .site_packages => "site-packages",
        };

        print("\n--------------------------------------------\n", .{});
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

        // Typosquatting check on every package in this directory
        {
            var dir = std.fs.openDirAbsolute(target.path, .{ .iterate = true }) catch null;
            if (dir) |*d| {
                defer d.close();
                var it = d.iterate();
                while (it.next() catch null) |entry| {
                    if (entry.kind != .directory) continue;
                    const ts_opt = detectTyposquat(allocator, entry.name);
                    if (ts_opt) |ts| {
                        var mts = ts;
                        defer mts.deinit();
                        print("  🔤 Typosquat? '{s}' is distance {} from popular '{s}'\n", .{ mts.installed, mts.distance, mts.similar_to });
                        total_typosquat += 1;
                    }
                }
            }
        }

        if (findings.len == 0) {
            print("  ✅ No lifecycle-script findings\n", .{});
            total_clean += 1;
        } else {
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

                // --deep: check npm registry for this package
                if (deep and target.kind == .node_modules) {
                    const rf_opt = checkNpmRegistry(allocator, f.name, f.version) catch null;
                    if (rf_opt) |rf| {
                        var mrf = rf;
                        defer mrf.deinit();
                        printRegistryFinding(&mrf);
                        total_registry += 1;
                    }
                }
            }

            if (!section_had_output) {
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

        // --deep: registry check on all directly-listed packages (from package.json)
        if (deep and target.kind == .node_modules) {
            const pkg_json_path = blk: {
                // parent of node_modules
                const parent = std.fs.path.dirname(target.path) orelse break :blk "";
                break :blk try std.fs.path.join(allocator, &.{ parent, "package.json" });
            };
            defer allocator.free(pkg_json_path);

            if (std.fs.cwd().readFileAlloc(allocator, pkg_json_path, 512 * 1024)) |pj| {
                defer allocator.free(pj);
                if (std.json.parseFromSlice(std.json.Value, allocator, pj, .{})) |parsed| {
                    defer parsed.deinit();
                    const proot = parsed.value.object;
                    const dep_keys = [_][]const u8{ "dependencies", "devDependencies", "optionalDependencies" };
                    for (dep_keys) |dk| {
                        const deps = proot.get(dk) orelse continue;
                        if (deps != .object) continue;
                        var dit = deps.object.iterator();
                        while (dit.next()) |dep_entry| {
                            const dep_name = dep_entry.key_ptr.*;
                            // Get installed version from package.json inside node_modules
                            const nm_pkg_path = try std.fs.path.join(allocator, &.{ target.path, dep_name, "package.json" });
                            defer allocator.free(nm_pkg_path);
                            const nm_pj = std.fs.cwd().readFileAlloc(allocator, nm_pkg_path, 64 * 1024) catch continue;
                            defer allocator.free(nm_pj);
                            const nm_parsed = std.json.parseFromSlice(std.json.Value, allocator, nm_pj, .{}) catch continue;
                            defer nm_parsed.deinit();
                            const ver_val = nm_parsed.value.object.get("version") orelse continue;
                            if (ver_val != .string) continue;
                            const ver = ver_val.string;

                            const rfo = checkNpmRegistry(allocator, dep_name, ver) catch null;
                            if (rfo) |rf| {
                                var mrf = rf;
                                defer mrf.deinit();
                                printRegistryFinding(&mrf);
                                total_registry += 1;
                            }
                        }
                    }
                } else |_| {}
            } else |_| {}
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
    print("  🔤 Typosquat: {}\n", .{total_typosquat});
    if (deep) print("  🌐 Registry : {}\n", .{total_registry});
    print("  ✅ Clean    : {}\n", .{total_clean});
    printSeparator('=', 45);

    if (total_critical > 0 or total_high > 0) {
        print("\n⚠️  Action required: review the flagged packages above.\n", .{});
        print("   • Pin to a specific known-good version in your lockfile\n", .{});
        print("   • Delete node_modules and reinstall from a frozen lockfile\n", .{});
        print("   • Run `npm audit fix` / `bun audit` / `cargo audit` for CVE patches\n", .{});
        print("   • For AUR packages: here pkgbuild <pkg> to review PKGBUILD\n", .{});
    } else if (total_typosquat > 0) {
        print("\n🔤 Possible typosquats detected – verify you installed the right packages.\n", .{});
    } else if (total_medium > 0) {
        print("\n💡 Some packages use patterns worth reviewing (outbound HTTP, env access).\n", .{});
        print("   Common in legitimate build tools – use judgement.\n", .{});
    } else {
        print("\n✨ Audit clean – no lifecycle-script attack indicators found.\n", .{});
        if (!deep) print("   Tip: run with --deep for npm publisher-change and version-age checks.\n", .{});
    }
    print("\n", .{});
}

fn printRegistryFinding(rf: *const RegistryFinding) void {
    const r = rf.risk();
    print("     {s} Registry: {s}@{s}\n", .{ r.emoji(), rf.pkg_name, rf.installed_version });
    if (rf.publisher_is_new) {
        print("        ⚠️  Publisher '{s}' is NEW to this package (Author Marshall signal)\n", .{rf.publisher_name});
        if (rf.version_age_days >= 0 and rf.version_age_days <= 21) {
            print("        ⏱️  AND this version is only {} day(s) old – high-risk combination\n", .{rf.version_age_days});
        }
    } else if (rf.version_age_days >= 0 and rf.version_age_days <= 7) {
        print("        ⏱️  Version published {} day(s) ago (Hex cooldown: consider waiting)\n", .{rf.version_age_days});
    }
    if (rf.is_deprecated) {
        print("        🚫 Deprecated: {s}\n", .{rf.deprecation_msg});
    }
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
