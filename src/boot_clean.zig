//! /boot partition health check and junk cleaner.
//!
//! Identifies the active rEFInd theme, scans /boot for large junk files
//! (rEFInd screenshots, FSCK recovery dumps, recycle bins), checks free
//! space, and offers interactive cleanup — so mkinitcpio never fails mid
//! upgrade because your bootloader left 7 uncompressed BMP screenshots
//! filling the partition.

const std = @import("std");
const print = std.debug.print;
const Allocator = std.mem.Allocator;
const fs_compat = @import("fs_compat.zig");

const BOOT_PATH = "/boot";
/// Warn when free space drops below this many MB.
const WARN_THRESHOLD_MB: u64 = 50;

// ---------------------------------------------------------------------------
// rEFInd theme detection
// ---------------------------------------------------------------------------

/// Detect the active rEFInd theme by parsing refind.conf files.
/// Returns an owned slice (caller must free) or null if not found.
pub fn detectRefindTheme(allocator: Allocator) ?[]const u8 {
    const conf_paths = [_][]const u8{
        "/boot/EFI/refind/refind.conf",
        "/boot/EFI/Boot/refind.conf",
        "/boot/refind.conf",
    };
    for (conf_paths) |conf_path| {
        const contents = fs_compat.readFileAlloc(allocator, conf_path, 512 * 1024) catch continue;
        defer allocator.free(contents);

        var lines = std.mem.splitScalar(u8, contents, '\n');
        while (lines.next()) |line| {
            const t = std.mem.trim(u8, line, " \t\r");
            if (t.len == 0 or t[0] == '#') continue;
            // Look for: include themes/<name>/...
            if (!std.mem.startsWith(u8, t, "include")) continue;
            const rest = std.mem.trimLeft(u8, t[7..], " \t");
            if (!std.mem.startsWith(u8, rest, "themes/")) continue;
            const after = rest[7..]; // skip "themes/"
            const slash = std.mem.indexOf(u8, after, "/") orelse continue;
            const name = after[0..slash];
            if (name.len == 0) continue;
            return allocator.dupe(u8, name) catch null;
        }
    }
    return null;
}

// ---------------------------------------------------------------------------
// Disk space
// ---------------------------------------------------------------------------

const DiskInfo = struct { used_mb: u64, avail_mb: u64, total_mb: u64 };

/// Get /boot disk usage (MB) via `df`.
fn getBootDisk(allocator: Allocator) !DiskInfo {
    const argv = [_][]const u8{ "df", "--block-size=1M", "--output=used,avail,size", BOOT_PATH };
    const out = try fs_compat.collectChildStdout(allocator, &argv);
    defer allocator.free(out);

    var lines = std.mem.splitScalar(u8, out, '\n');
    _ = lines.next(); // skip header
    const data = lines.next() orelse return error.ParseError;
    var fields = std.mem.tokenizeAny(u8, data, " \t");
    const used = try std.fmt.parseInt(u64, fields.next() orelse return error.ParseError, 10);
    const avail = try std.fmt.parseInt(u64, fields.next() orelse return error.ParseError, 10);
    const total = try std.fmt.parseInt(u64, fields.next() orelse return error.ParseError, 10);
    return .{ .used_mb = used, .avail_mb = avail, .total_mb = total };
}

// ---------------------------------------------------------------------------
// Junk classification
// ---------------------------------------------------------------------------

const JunkRule = struct {
    prefix: ?[]const u8 = null,
    suffix: ?[]const u8 = null,
    exact: ?[]const u8 = null,
    reason: []const u8,
};

/// Rules for files/dirs directly inside /boot that are safe to remove.
const JUNK_RULES = [_]JunkRule{
    .{
        .prefix = "screenshot_",
        .suffix = ".bmp",
        .reason = "rEFInd screenshot (F10 key pressed accidentally in boot menu)",
    },
    .{
        .prefix = "FSCK",
        .suffix = ".REC",
        .reason = "FAT filesystem recovery dump (from a prior fsck run)",
    },
    .{
        .exact = "$RECYCLE.BIN",
        .reason = "Windows recycle bin stub on EFI/FAT partition",
    },
    .{
        .exact = "System Volume Information",
        .reason = "Windows metadata stub on EFI partition",
    },
};

fn classifyJunk(name: []const u8) ?[]const u8 {
    for (JUNK_RULES) |rule| {
        if (rule.exact) |e| {
            if (std.mem.eql(u8, name, e)) return rule.reason;
            continue;
        }
        const prefix_ok = if (rule.prefix) |p| std.mem.startsWith(u8, name, p) else true;
        const suffix_ok = if (rule.suffix) |s| std.mem.endsWith(u8, name, s) else true;
        if (prefix_ok and suffix_ok) return rule.reason;
    }
    return null;
}

// ---------------------------------------------------------------------------
// Main command
// ---------------------------------------------------------------------------

/// Run `here boot-clean [--dry-run]`.
pub fn runBootClean(allocator: Allocator, dry_run: bool) !void {
    print("\n🥾 Boot Partition Health Check\n", .{});
    print("================================\n\n", .{});

    // ---- 1. Active rEFInd theme ----
    const active_theme = detectRefindTheme(allocator);
    defer if (active_theme) |t| allocator.free(t);

    if (active_theme) |theme| {
        print("🎨 Active rEFInd theme : {s}\n", .{theme});
        print("   Preserve           : /boot/EFI/refind/themes/{s}/\n\n", .{theme});
    } else {
        print("🎨 No rEFInd theme detected (rEFInd not in use or no theme set)\n\n", .{});
    }

    // ---- 2. Disk space ----
    const disk = getBootDisk(allocator) catch |err| blk: {
        print("⚠️  Cannot read /boot disk stats: {}\n\n", .{err});
        break :blk null;
    };
    if (disk) |d| {
        const pct: u64 = if (d.total_mb > 0) (d.used_mb * 100 / d.total_mb) else 0;
        print("💾 /boot: {d} MB used / {d} MB total ({d}% full, {d} MB free)\n", .{
            d.used_mb, d.total_mb, pct, d.avail_mb,
        });
        if (d.avail_mb < WARN_THRESHOLD_MB) {
            print("🚨 DANGER: only {d} MB free — mkinitcpio will likely fail!\n", .{d.avail_mb});
        }
        print("\n", .{});
    }

    // ---- 3. Scan /boot top-level entries ----
    const entries = fs_compat.iterDir(allocator, BOOT_PATH) catch |err| {
        print("❌ Cannot read /boot: {}\n\n", .{err});
        return;
    };
    defer {
        for (entries) |*e| e.deinit(allocator);
        allocator.free(entries);
    }

    // Collect junk
    const JunkFile = struct {
        path: []const u8, // static string in entries — no ownership needed
        name: []const u8,
        reason: []const u8, // static string from JUNK_RULES
        size_mb: u64,
    };
    var junk = std.ArrayList(JunkFile).init(allocator);
    defer junk.deinit();

    var total_junk_mb: u64 = 0;
    for (entries) |e| {
        const reason = classifyJunk(e.name) orelse continue;
        const full_path = std.fmt.allocPrint(allocator, "{s}/{s}", .{ BOOT_PATH, e.name }) catch continue;
        defer allocator.free(full_path);
        const sz = fs_compat.fileSize(full_path) / 1024 / 1024;
        total_junk_mb += sz;
        // Store a copy of the path for later use
        const owned_path = allocator.dupe(u8, full_path) catch continue;
        junk.append(.{
            .path = owned_path,
            .name = e.name,
            .reason = reason,
            .size_mb = sz,
        }) catch {
            allocator.free(owned_path);
        };
    }

    // ---- 4. Report ----
    if (junk.items.len == 0) {
        print("✅ No junk files found in /boot — looks clean!\n\n", .{});
        return;
    }

    print("🗑️  Junk files found ({d}):\n\n", .{junk.items.len});
    for (junk.items) |f| {
        print("  [{d:>3} MB] {s}\n", .{ f.size_mb, f.path });
        print("          Reason: {s}\n\n", .{f.reason});
    }
    print("  Recoverable: ~{d} MB\n\n", .{total_junk_mb});

    if (dry_run) {
        print("ℹ️  Dry-run mode — nothing deleted.\n", .{});
        print("   Run  here boot-clean          to clean interactively\n", .{});
        print("   Run  sudo here boot-clean      if removal needs root\n\n", .{});
        // Cleanup owned paths before returning
        for (junk.items) |f| allocator.free(@constCast(f.path));
        return;
    }

    // ---- 5. Confirm & delete ----
    print("❓ Remove these {d} file(s)? [y/N]: ", .{junk.items.len});
    var input_buf: [16]u8 = undefined;
    const answer = fs_compat.readLine(&input_buf);
    if (answer.len == 0 or (answer[0] != 'y' and answer[0] != 'Y')) {
        print("⏹️  Cancelled. Run  sudo rm -f {s}/screenshot_*.bmp {s}/FSCK*.REC  manually.\n\n", .{ BOOT_PATH, BOOT_PATH });
        for (junk.items) |f| allocator.free(@constCast(f.path));
        return;
    }

    var deleted: u32 = 0;
    var failed: u32 = 0;
    for (junk.items) |f| {
        defer allocator.free(@constCast(f.path));
        // Try without sudo first (running as root), then with sudo
        const ok = blk: {
            fs_compat.deleteFile(f.path) catch {
                // Fallback: spawn sudo rm
                var rm = std.process.Child.init(
                    &[_][]const u8{ "sudo", "rm", "-rf", f.path },
                    allocator,
                );
                rm.stdout_behavior = .Ignore;
                rm.stderr_behavior = .Inherit;
                const term = rm.spawnAndWait() catch break :blk false;
                break :blk switch (term) {
                    .Exited => |c| c == 0,
                    else => false,
                };
            };
            break :blk true;
        };
        if (ok) {
            print("  🗑️  Removed {s}\n", .{f.path});
            deleted += 1;
        } else {
            print("  ❌ Failed   {s}\n", .{f.path});
            failed += 1;
        }
    }

    print("\n", .{});
    if (deleted > 0) {
        print("✅ Removed {d} file(s), freed ~{d} MB on /boot\n", .{ deleted, total_junk_mb });
    }
    if (failed > 0) {
        print("⚠️  {d} file(s) could not be removed — try:  sudo here boot-clean\n", .{failed});
    }

    // Re-check disk space
    if (deleted > 0) {
        const new_disk = getBootDisk(allocator) catch return;
        print("\n💾 /boot now: {d} MB free of {d} MB\n\n", .{ new_disk.avail_mb, new_disk.total_mb });
        if (new_disk.avail_mb >= WARN_THRESHOLD_MB) {
            print("✅ Space is healthy — safe to run  sudo mkinitcpio -P\n\n", .{});
        }
    }
}
