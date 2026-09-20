//! Compatibility shims for Zig 0.16.0 std.fs API changes.
//!
//! In 0.16.0, std.fs lost cwd(), openFileAbsolute, openDirAbsolute, etc.
//! Everything moved to std.Io.Dir which needs an `io` handle.
//! These helpers use std.posix directly so they work without io.

const std = @import("std");
const Allocator = std.mem.Allocator;
const posix = std.posix;

/// Read a file at an absolute or cwd-relative path into an allocated slice.
pub fn readFileAlloc(allocator: Allocator, path: []const u8, max_bytes: usize) ![]u8 {
    const fd = try posix.openat(posix.AT.FDCWD, path, .{ .ACCMODE = .RDONLY }, 0);
    defer posix.close(fd);
    var list = std.ArrayList(u8).init(allocator);
    errdefer list.deinit();
    var buf: [4096]u8 = undefined;
    while (list.items.len < max_bytes) {
        const n = try posix.read(fd, &buf);
        if (n == 0) break;
        try list.appendSlice(buf[0..n]);
    }
    return list.toOwnedSlice();
}

/// Write bytes to a file, creating it if needed, truncating if exists.
/// Returns error if write fails. Caller must have write permission.
pub fn writeFileAll(path: []const u8, contents: []const u8) !void {
    const fd = try posix.openat(
        posix.AT.FDCWD,
        path,
        .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true },
        0o644,
    );
    defer posix.close(fd);
    var written: usize = 0;
    while (written < contents.len) {
        written += try posix.write(fd, contents[written..]);
    }
}

/// Returns true if path exists and is accessible.
pub fn accessExists(path: []const u8) bool {
    posix.access(path, posix.F_OK) catch return false;
    return true;
}

/// Returns the size in bytes of the file at path, or 0 on error.
pub fn fileSize(path: []const u8) u64 {
    const fd = posix.openat(posix.AT.FDCWD, path, .{ .ACCMODE = .RDONLY }, 0) catch return 0;
    defer posix.close(fd);
    const s = posix.fstat(fd) catch return 0;
    return @intCast(s.size);
}

/// Stat a path, returning the posix stat struct.
pub fn statPath(path: []const u8) !posix.Stat {
    const fd = try posix.openat(posix.AT.FDCWD, path, .{ .ACCMODE = .RDONLY }, 0);
    defer posix.close(fd);
    return posix.fstat(fd);
}

/// A directory entry from iterDir.
pub const DirEntry = struct {
    name: []u8,
    kind: Kind,

    pub const Kind = enum { file, dir, symlink, other };

    pub fn deinit(self: *DirEntry, allocator: Allocator) void {
        allocator.free(self.name);
    }
};

/// List the entries of a directory. Caller owns returned slice and must call
/// entry.deinit() + allocator.free(slice).
pub fn iterDir(allocator: Allocator, path: []const u8) ![]DirEntry {
    const fd = try posix.openat(
        posix.AT.FDCWD,
        path,
        .{ .ACCMODE = .RDONLY, .DIRECTORY = true },
        0,
    );
    defer posix.close(fd);

    var entries = std.ArrayList(DirEntry).init(allocator);
    errdefer {
        for (entries.items) |*e| allocator.free(e.name);
        entries.deinit();
    }

    var buf: [8192]u8 align(8) = undefined;
    const linux = std.os.linux;
    while (true) {
        const rc = linux.syscall3(
            .getdents64,
            @intCast(fd),
            @intFromPtr(&buf),
            buf.len,
        );
        if (rc == 0) break;
        if (@as(isize, @bitCast(rc)) < 0) return error.GetdentsFailed;
        const n: usize = @intCast(rc);
        var offset: usize = 0;
        while (offset < n) {
            const dirent: *align(1) linux.dirent64 = @ptrCast(&buf[offset]);
            const name = std.mem.sliceTo(@as([*:0]const u8, @ptrCast(&dirent.d_name)), 0);
            if (!std.mem.eql(u8, name, ".") and !std.mem.eql(u8, name, "..")) {
                const kind: DirEntry.Kind = switch (dirent.d_type) {
                    linux.DT.REG => .file,
                    linux.DT.DIR => .dir,
                    linux.DT.LNK => .symlink,
                    else => .other,
                };
                try entries.append(.{
                    .name = try allocator.dupe(u8, name),
                    .kind = kind,
                });
            }
            offset += dirent.d_reclen;
        }
    }
    return entries.toOwnedSlice();
}

/// Make a directory (no-op if already exists). Returns error on real failures.
pub fn makeDir(path: []const u8) !void {
    posix.mkdir(path, 0o755) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
}

/// Delete a file. Returns error if it doesn't exist or can't be removed.
pub fn deleteFile(path: []const u8) !void {
    try posix.unlinkat(posix.AT.FDCWD, path, 0);
}

/// Copy a file by spawning `cp`. Returns true on success.
pub fn copyFileSpawn(allocator: Allocator, src: []const u8, dst: []const u8) bool {
    var child = std.process.Child.init(
        &[_][]const u8{ "cp", src, dst },
        allocator,
    );
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;
    const term = child.spawnAndWait() catch return false;
    return switch (term) {
        .Exited => |code| code == 0,
        else => false,
    };
}

/// Read all stdout from a child process into an owned slice.
/// Caller must free the returned slice.
pub fn collectChildStdout(allocator: Allocator, argv: []const []const u8) ![]u8 {
    var child = std.process.Child.init(argv, allocator);
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Ignore;
    try child.spawn();

    var out = std.ArrayList(u8).init(allocator);
    errdefer out.deinit();

    if (child.stdout) |stdout_file| {
        const stdout_fd = stdout_file.handle;
        var buf: [4096]u8 = undefined;
        while (true) {
            const n = posix.read(stdout_fd, &buf) catch break;
            if (n == 0) break;
            try out.appendSlice(buf[0..n]);
        }
    }
    _ = child.wait() catch {};
    return out.toOwnedSlice();
}

/// Read a line from stdin (STDIN_FILENO). Strips trailing newline.
/// Returns a slice into `buf` (not owned).
pub fn readLine(buf: []u8) []const u8 {
    const n = posix.read(posix.STDIN_FILENO, buf) catch return buf[0..0];
    if (n == 0) return buf[0..0];
    return std.mem.trim(u8, buf[0..n], " \t\r\n");
}
