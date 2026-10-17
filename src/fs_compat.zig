//! Zig 0.15 filesystem calls that Zig 0.16 moved onto `std.Io`.
//!
//! `std.fs.cwd()`, `std.fs.File`, and `openDirAbsolute` now require an `Io`.
//! These helpers keep the 0.15 call shape and talk to the kernel directly.

const std = @import("std");
const Allocator = std.mem.Allocator;
const posix = std.posix;
const linux = std.os.linux;

pub const OpenOptions = struct {
    iterate: bool = false,
};

pub const File = struct {
    handle: posix.fd_t,

    pub fn stdin() File {
        return .{ .handle = posix.STDIN_FILENO };
    }

    pub fn read(self: File, buffer: []u8) posix.ReadError!usize {
        return posix.read(self.handle, buffer);
    }

    pub fn readAll(self: File, buffer: []u8) !usize {
        var filled: usize = 0;
        while (filled < buffer.len) {
            const n = try self.read(buffer[filled..]);
            if (n == 0) break;
            filled += n;
        }
        return filled;
    }

    pub fn readToEndAlloc(self: File, allocator: Allocator, max_bytes: usize) ![]u8 {
        return readFdAlloc(allocator, self.handle, max_bytes);
    }

    pub fn write(self: File, bytes: []const u8) !usize {
        try self.writeAll(bytes);
        return bytes.len;
    }

    pub fn writeAll(self: File, bytes: []const u8) !void {
        var written: usize = 0;
        while (written < bytes.len) {
            const rc = linux.write(self.handle, bytes.ptr + written, bytes.len - written);
            const n = try syscallLen(rc);
            if (n == 0) return error.Unexpected;
            written += n;
        }
    }

    pub fn close(self: File) void {
        if (self.handle >= 0) _ = linux.close(self.handle);
    }

    pub fn getEndPos(self: File) !u64 {
        const rc = linux.lseek(self.handle, 0, linux.SEEK.END);
        const pos = try syscallLen(rc);
        _ = linux.lseek(self.handle, 0, linux.SEEK.SET);
        return pos;
    }

    pub fn stat(self: File) !Stat {
        return statFd(self.handle);
    }

    pub fn chmod(self: File, mode: u32) !void {
        try syscallVoid(linux.fchmod(self.handle, @intCast(mode)));
    }

    pub fn copyRangeAll(self: File, in_offset: u64, dest: File, out_offset: u64, len: u64) !u64 {
        _ = try syscallLen(linux.lseek(self.handle, @intCast(in_offset), linux.SEEK.SET));
        _ = try syscallLen(linux.lseek(dest.handle, @intCast(out_offset), linux.SEEK.SET));
        var left = len;
        var copied: u64 = 0;
        var buf: [64 * 1024]u8 = undefined;
        while (left > 0) {
            const want = @min(buf.len, left);
            const n = self.read(buf[0..want]) catch return error.InputOutput;
            if (n == 0) break;
            try dest.writeAll(buf[0..n]);
            left -= n;
            copied += n;
        }
        return copied;
    }
};

pub const Stat = struct {
    size: u64,
    mode: u32,
    /// Modification time in nanoseconds since the Unix epoch.
    mtime: i128,
};

pub const Entry = struct {
    name: []const u8,
    kind: Kind,

    pub const Kind = enum {
        block_device,
        character_device,
        directory,
        named_pipe,
        sym_link,
        file,
        unix_domain_socket,
        whiteout,
        unknown,
    };
};

pub const Dir = struct {
    handle: posix.fd_t,

    pub fn close(self: Dir) void {
        if (self.handle == posix.AT.FDCWD or self.handle < 0) return;
        _ = linux.close(self.handle);
    }

    pub fn openDir(self: Dir, sub_path: []const u8, options: OpenOptions) !Dir {
        _ = options;
        const fd = try posix.openat(self.handle, sub_path, .{ .ACCMODE = .RDONLY, .DIRECTORY = true }, 0);
        return .{ .handle = fd };
    }

    pub fn openFile(self: Dir, sub_path: []const u8, options: OpenOptions) !File {
        _ = options;
        const fd = try posix.openat(self.handle, sub_path, .{ .ACCMODE = .RDONLY }, 0);
        return .{ .handle = fd };
    }

    pub fn createFile(self: Dir, sub_path: []const u8, options: OpenOptions) !File {
        _ = options;
        const fd = try posix.openat(self.handle, sub_path, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, 0o644);
        return .{ .handle = fd };
    }

    pub fn access(self: Dir, sub_path: []const u8, options: OpenOptions) !void {
        _ = options;
        var buf: [linux.PATH_MAX]u8 = undefined;
        const z = try terminated(sub_path, &buf);
        try syscallVoid(linux.faccessat(self.handle, z.ptr, 0, 0));
    }

    pub fn makeDir(self: Dir, sub_path: []const u8) !void {
        var buf: [linux.PATH_MAX]u8 = undefined;
        const z = try terminated(sub_path, &buf);
        syscallVoid(linux.mkdirat(self.handle, z.ptr, 0o755)) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };
    }

    pub fn makePath(self: Dir, sub_path: []const u8) !void {
        _ = self;
        try createPath(sub_path);
    }

    pub fn readFileAlloc(self: Dir, allocator: Allocator, sub_path: []const u8, max_bytes: usize) ![]u8 {
        const file = try self.openFile(sub_path, .{});
        defer file.close();
        return file.readToEndAlloc(allocator, max_bytes);
    }

    pub fn statFile(self: Dir, sub_path: []const u8) !Stat {
        var buf: [linux.PATH_MAX]u8 = undefined;
        const z = try terminated(sub_path, &buf);
        var stx: linux.Statx = undefined;
        try syscallVoid(linux.statx(self.handle, z.ptr, 0, linux.STATX.BASIC_STATS, &stx));
        return statFromX(stx);
    }

    pub fn readLink(self: Dir, sub_path: []const u8, buffer: []u8) ![]u8 {
        var path_buf: [linux.PATH_MAX]u8 = undefined;
        const z = try terminated(sub_path, &path_buf);
        const rc = linux.readlinkat(self.handle, z.ptr, buffer.ptr, buffer.len);
        const n = try syscallLen(rc);
        if (n >= buffer.len) return error.NameTooLong;
        return buffer[0..n];
    }

    pub fn symLink(self: Dir, target_path: []const u8, new_path: []const u8, options: OpenOptions) !void {
        _ = self;
        _ = options;
        var target_buf: [linux.PATH_MAX]u8 = undefined;
        var new_buf: [linux.PATH_MAX]u8 = undefined;
        const target_z = try terminated(target_path, &target_buf);
        const new_z = try terminated(new_path, &new_buf);
        try syscallVoid(linux.symlink(target_z.ptr, new_z.ptr));
    }

    pub fn iterate(self: Dir) Iterator {
        return .{ .dir = self };
    }
};

pub const Iterator = struct {
    dir: Dir,
    owned: ?posix.fd_t = null,
    buf: [8192]u8 align(8) = undefined,
    offset: usize = 0,
    filled: usize = 0,
    done: bool = false,

    pub fn next(self: *Iterator) !?Entry {
        if (self.owned == null and self.dir.handle == posix.AT.FDCWD) {
            self.owned = try posix.openat(posix.AT.FDCWD, ".", .{ .ACCMODE = .RDONLY, .DIRECTORY = true }, 0);
        }
        const fd = self.owned orelse self.dir.handle;
        while (true) {
            if (self.offset >= self.filled) {
                if (self.done) return null;
                const rc = linux.syscall3(.getdents64, @as(usize, @intCast(fd)), @intFromPtr(&self.buf), self.buf.len);
                const signed: isize = @bitCast(rc);
                if (signed < 0) return error.Unexpected;
                if (rc == 0) {
                    self.done = true;
                    if (self.owned) |owned| {
                        _ = linux.close(owned);
                        self.owned = null;
                    }
                    return null;
                }
                self.filled = rc;
                self.offset = 0;
            }
            const dirent: *align(1) linux.dirent64 = @ptrCast(&self.buf[self.offset]);
            const name = std.mem.sliceTo(@as([*:0]const u8, @ptrCast(&dirent.name)), 0);
            const kind: Entry.Kind = switch (dirent.type) {
                linux.DT.REG => .file,
                linux.DT.DIR => .directory,
                linux.DT.LNK => .sym_link,
                linux.DT.BLK => .block_device,
                linux.DT.CHR => .character_device,
                linux.DT.FIFO => .named_pipe,
                linux.DT.SOCK => .unix_domain_socket,
                else => .unknown,
            };
            self.offset += dirent.reclen;
            if (std.mem.eql(u8, name, ".") or std.mem.eql(u8, name, "..")) continue;
            return .{ .name = name, .kind = kind };
        }
    }
};

pub fn cwd() Dir {
    return .{ .handle = posix.AT.FDCWD };
}

pub fn openDirAbsolute(path: []const u8, options: OpenOptions) !Dir {
    return cwd().openDir(path, options);
}

pub fn accessAbsolute(path: []const u8, options: OpenOptions) !void {
    return cwd().access(path, options);
}

pub fn realpath(path: []const u8, out_buffer: []u8) ![]u8 {
    const file = try cwd().openFile(path, .{});
    defer file.close();
    var link_buf: [64]u8 = undefined;
    const link = std.fmt.bufPrint(&link_buf, "/proc/self/fd/{d}", .{file.handle}) catch return error.NameTooLong;
    var zbuf: [linux.PATH_MAX]u8 = undefined;
    const z = try terminated(link, &zbuf);
    const rc = linux.readlink(z.ptr, out_buffer.ptr, out_buffer.len);
    const n = try syscallLen(rc);
    if (n >= out_buffer.len) return error.NameTooLong;
    return out_buffer[0..n];
}

pub fn readFileAlloc(allocator: Allocator, path: []const u8, max_bytes: usize) ![]u8 {
    return cwd().readFileAlloc(allocator, path, max_bytes);
}

pub fn writeFileAll(path: []const u8, contents: []const u8) !void {
    const file = try cwd().createFile(path, .{});
    defer file.close();
    try file.writeAll(contents);
}

pub fn accessExists(path: []const u8) bool {
    cwd().access(path, .{}) catch return false;
    return true;
}

pub fn fileSize(path: []const u8) u64 {
    const st = statPath(path) catch return 0;
    return st.size;
}

pub fn statPath(path: []const u8) !Stat {
    return cwd().statFile(path);
}

pub fn makeDir(path: []const u8) !void {
    try cwd().makeDir(path);
}

fn createPath(path: []const u8) !void {
    if (path.len == 0) return;
    var end: usize = if (path[0] == '/') 1 else 0;
    while (end < path.len) {
        while (end < path.len and path[end] != '/') : (end += 1) {}
        if (end == 0) {
            end += 1;
            continue;
        }
        try cwd().makeDir(path[0..end]);
        while (end < path.len and path[end] == '/') : (end += 1) {}
    }
}

pub fn deleteFile(path: []const u8) !void {
    var buf: [linux.PATH_MAX]u8 = undefined;
    const z = try terminated(path, &buf);
    try syscallVoid(linux.unlinkat(posix.AT.FDCWD, z.ptr, 0));
}

/// Owned directory entry from `iterDir`.
pub const DirEntry = struct {
    name: []u8,
    kind: Kind,

    pub const Kind = enum { file, dir, symlink, other };

    pub fn deinit(self: *DirEntry, allocator: Allocator) void {
        allocator.free(self.name);
    }
};

pub fn iterDir(allocator: Allocator, path: []const u8) ![]DirEntry {
    var dir = try openDirAbsolute(path, .{});
    defer dir.close();
    var iterator = dir.iterate();
    var entries: std.ArrayList(DirEntry) = .{ .items = &.{}, .capacity = 0 };
    errdefer {
        for (entries.items) |*e| allocator.free(e.name);
        entries.deinit(allocator);
    }
    while (try iterator.next()) |entry| {
        const kind: DirEntry.Kind = switch (entry.kind) {
            .file => .file,
            .directory => .dir,
            .sym_link => .symlink,
            else => .other,
        };
        try entries.append(allocator, .{
            .name = try allocator.dupe(u8, entry.name),
            .kind = kind,
        });
    }
    return entries.toOwnedSlice(allocator);
}

pub const RunResult = struct {
    term: Term,
    stdout: []u8,
    stderr: []u8,
};

pub const Term = union(enum) {
    Exited: u32,
    Signal: u32,
    Stopped: u32,
    Unknown: u32,
};

/// Zig 0.15 `std.process.Child`. Zig 0.16 spawn requires an `Io`.
pub const Child = struct {
    argv: []const []const u8,
    allocator: Allocator,
    stdout_behavior: Stdio = .Inherit,
    stderr_behavior: Stdio = .Inherit,
    stdin_behavior: Stdio = .Inherit,
    cwd: ?[]const u8 = null,
    stdout: ?File = null,
    stderr: ?File = null,
    stdin: ?File = null,

    inner: ?std.process.Child = null,
    threaded: ?*std.Io.Threaded = null,

    pub const Stdio = enum { Inherit, Ignore, Pipe };

    pub fn init(argv: []const []const u8, allocator: Allocator) Child {
        return .{ .argv = argv, .allocator = allocator };
    }

    pub fn spawn(self: *Child) !void {
        const threaded = try self.allocator.create(std.Io.Threaded);
        errdefer self.allocator.destroy(threaded);
        threaded.* = std.Io.Threaded.init(std.heap.page_allocator, .{ .environ = currentEnviron() });
        errdefer threaded.deinit();
        const io = threaded.io();
        const inner = try std.process.spawn(io, .{
            .argv = self.argv,
            .cwd = if (self.cwd) |dir| .{ .path = dir } else .inherit,
            .stdin = toStdio(self.stdin_behavior),
            .stdout = toStdio(self.stdout_behavior),
            .stderr = toStdio(self.stderr_behavior),
        });
        self.threaded = threaded;
        if (inner.stdout) |file| self.stdout = .{ .handle = file.handle };
        if (inner.stderr) |file| self.stderr = .{ .handle = file.handle };
        if (inner.stdin) |file| self.stdin = .{ .handle = file.handle };
        self.inner = inner;
    }

    pub fn wait(self: *Child) !Term {
        const threaded = self.threaded orelse return error.NotRunning;
        const io = threaded.io();
        var inner = &(self.inner orelse return error.NotRunning);
        if (self.stdin == null) inner.stdin = null;
        const term = try inner.wait(io);
        self.inner = null;
        threaded.deinit();
        self.allocator.destroy(threaded);
        self.threaded = null;
        return mapTerm(term);
    }

    pub fn spawnAndWait(self: *Child) !Term {
        try self.spawn();
        return self.wait();
    }

    pub fn collectOutput(self: *Child, allocator: Allocator, stdout_buf: *std.ArrayList(u8), stderr_buf: *std.ArrayList(u8), max_bytes: usize) !void {
        _ = max_bytes;
        const stderr_file = self.stderr;
        var stderr_local: std.ArrayList(u8) = .{ .items = &.{}, .capacity = 0 };
        const drain = try std.Thread.spawn(.{}, drainFile, .{ stderr_file, &stderr_local });
        if (self.stdout) |file| try appendFile(allocator, stdout_buf, file);
        drain.join();
        defer stderr_local.deinit(std.heap.page_allocator);
        try stdout_buf.appendSlice(allocator, &.{});
        try stderr_buf.appendSlice(allocator, stderr_local.items);
    }

    pub fn run(args: struct {
        allocator: Allocator,
        argv: []const []const u8,
        max_output_bytes: usize = 50 * 1024 * 1024,
        cwd: ?[]const u8 = null,
        env_map: ?*anyopaque = null,
    }) !RunResult {
        _ = args.env_map;
        _ = args.max_output_bytes;
        var threaded = std.Io.Threaded.init(std.heap.page_allocator, .{ .environ = currentEnviron() });
        defer threaded.deinit();
        const result = try std.process.run(args.allocator, threaded.io(), .{
            .argv = args.argv,
            .cwd = if (args.cwd) |dir| .{ .path = dir } else .inherit,
        });
        return .{
            .term = mapTerm(result.term),
            .stdout = result.stdout,
            .stderr = result.stderr,
        };
    }
};

fn toStdio(behavior: Child.Stdio) std.process.SpawnOptions.StdIo {
    return switch (behavior) {
        .Inherit => .inherit,
        .Ignore => .ignore,
        .Pipe => .pipe,
    };
}

fn mapTerm(term: std.process.Child.Term) Term {
    return switch (term) {
        .exited => |code| .{ .Exited = code },
        .signal => |sig| .{ .Signal = @intFromEnum(sig) },
        .stopped => |sig| .{ .Stopped = @intFromEnum(sig) },
        .unknown => |code| .{ .Unknown = code },
    };
}

var process_environ: std.process.Environ = .empty;

pub fn setEnviron(env: std.process.Environ) void {
    process_environ = env;
}

fn currentEnviron() std.process.Environ {
    return process_environ;
}

pub fn getEnvVarOwned(allocator: Allocator, key: []const u8) ![]u8 {
    const value = getenv(key) orelse return error.EnvironmentVariableNotFound;
    return allocator.dupe(u8, value);
}

pub fn getenv(key: []const u8) ?[:0]const u8 {
    return std.process.Environ.getPosix(process_environ, key);
}

pub fn sleep(ns: u64) void {
    const req = linux.timespec{
        .sec = @intCast(ns / std.time.ns_per_s),
        .nsec = @intCast(ns % std.time.ns_per_s),
    };
    _ = linux.nanosleep(&req, null);
}

pub fn getCwd(buffer: []u8) ![]u8 {
    const n = try syscallLen(linux.getcwd(buffer.ptr, buffer.len));
    if (n == 0) return error.Unexpected;
    return buffer[0 .. n - 1];
}

pub fn timestamp() i64 {
    var ts: linux.timespec = undefined;
    _ = linux.clock_gettime(.REALTIME, &ts);
    return @intCast(ts.sec);
}

fn drainFile(file: ?File, dest: *std.ArrayList(u8)) void {
    const opened = file orelse return;
    appendFile(std.heap.page_allocator, dest, opened) catch {};
}

fn appendFile(allocator: Allocator, dest: *std.ArrayList(u8), file: File) !void {
    var tmp: [4096]u8 = undefined;
    while (true) {
        const n = file.read(&tmp) catch return;
        if (n == 0) return;
        try dest.appendSlice(allocator, tmp[0..n]);
    }
}

pub fn copyFileSpawn(allocator: Allocator, src: []const u8, dst: []const u8) bool {
    var child = Child.init(&[_][]const u8{ "cp", src, dst }, allocator);
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;
    const term = child.spawnAndWait() catch return false;
    return switch (term) {
        .Exited => |code| code == 0,
        else => false,
    };
}

pub fn collectChildStdout(allocator: Allocator, argv: []const []const u8) ![]u8 {
    var child = Child.init(argv, allocator);
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Ignore;
    try child.spawn();
    var out: std.ArrayList(u8) = .{ .items = &.{}, .capacity = 0 };
    errdefer out.deinit(allocator);
    if (child.stdout) |stdout_file| {
        const collected = try readFdAlloc(allocator, stdout_file.handle, 64 * 1024 * 1024);
        defer allocator.free(collected);
        try out.appendSlice(allocator, collected);
    }
    _ = child.wait() catch {};
    return out.toOwnedSlice(allocator);
}

pub fn readLine(buf: []u8) []const u8 {
    const n = posix.read(posix.STDIN_FILENO, buf) catch return buf[0..0];
    if (n == 0) return buf[0..0];
    return std.mem.trim(u8, buf[0..n], " \t\r\n");
}

fn readFdAlloc(allocator: Allocator, fd: posix.fd_t, max_bytes: usize) ![]u8 {
    var list: std.ArrayList(u8) = .{ .items = &.{}, .capacity = 0 };
    errdefer list.deinit(allocator);
    var buf: [4096]u8 = undefined;
    while (list.items.len < max_bytes) {
        const n = try posix.read(fd, &buf);
        if (n == 0) break;
        const room = max_bytes - list.items.len;
        try list.appendSlice(allocator, buf[0..@min(n, room)]);
        if (n > room) break;
    }
    return list.toOwnedSlice(allocator);
}

fn statFd(fd: posix.fd_t) !Stat {
    var stx: linux.Statx = undefined;
    try syscallVoid(linux.statx(fd, "", linux.AT.EMPTY_PATH, linux.STATX.BASIC_STATS, &stx));
    return statFromX(stx);
}

fn statFromX(stx: linux.Statx) Stat {
    const nsec: i128 = stx.mtime.nsec;
    return .{
        .size = stx.size,
        .mode = stx.mode,
        .mtime = @as(i128, stx.mtime.sec) * std.time.ns_per_s + nsec,
    };
}

fn terminated(path: []const u8, buf: *[linux.PATH_MAX]u8) ![:0]u8 {
    if (path.len >= buf.len) return error.NameTooLong;
    @memcpy(buf[0..path.len], path);
    buf[path.len] = 0;
    return buf[0..path.len :0];
}

fn syscallLen(rc: usize) !usize {
    const signed: isize = @bitCast(rc);
    if (signed >= 0) return @intCast(signed);
    try mapErrno(-signed);
    unreachable;
}

fn syscallVoid(rc: usize) !void {
    const signed: isize = @bitCast(rc);
    if (signed >= 0) return;
    try mapErrno(-signed);
}

fn mapErrno(code: isize) !void {
    return switch (code) {
        @intFromEnum(linux.E.EXIST) => error.PathAlreadyExists,
        @intFromEnum(linux.E.NOENT) => error.FileNotFound,
        @intFromEnum(linux.E.ACCES) => error.AccessDenied,
        @intFromEnum(linux.E.PERM) => error.AccessDenied,
        @intFromEnum(linux.E.NOTDIR) => error.NotDir,
        @intFromEnum(linux.E.ISDIR) => error.IsDir,
        @intFromEnum(linux.E.NAMETOOLONG) => error.NameTooLong,
        else => error.Unexpected,
    };
}
