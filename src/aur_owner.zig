const std = @import("std");
const fs_compat = @import("fs_compat.zig");
const Allocator = std.mem.Allocator;

pub const Info = struct {
    name: []u8,
    /// Empty when the AUR package is orphaned.
    maintainer: []u8,
    allocator: Allocator,

    pub fn deinit(self: *Info) void {
        self.allocator.free(self.name);
        self.allocator.free(self.maintainer);
    }
};

pub fn lookup(allocator: Allocator, names: []const []const u8) ![]Info {
    if (names.len == 0) return allocator.alloc(Info, 0);
    var url = std.ArrayList(u8){ .items = &.{}, .capacity = 0 };
    defer url.deinit(allocator);
    try url.appendSlice(allocator, "https://aur.archlinux.org/rpc/v5/info?");
    for (names, 0..) |name, i| {
        if (i > 0) try url.append(allocator, '&');
        try url.appendSlice(allocator, "arg[]=");
        try url.appendSlice(allocator, name);
    }

    const result = fs_compat.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "curl", "-fsSL", "--max-time", "20", "-H", "User-Agent: here", url.items },
    }) catch return error.Network;
    defer allocator.free(result.stderr);
    defer allocator.free(result.stdout);
    switch (result.term) {
        .Exited => |code| if (code != 0) return error.Network,
        else => return error.Network,
    }
    return parseInfo(allocator, result.stdout);
}

pub fn parseInfo(allocator: Allocator, json: []const u8) ![]Info {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.Parse;
    const results = parsed.value.object.get("results") orelse return allocator.alloc(Info, 0);
    if (results != .array) return error.Parse;

    var found = std.ArrayList(Info){ .items = &.{}, .capacity = 0 };
    errdefer {
        for (found.items) |*item| item.deinit();
        found.deinit(allocator);
    }
    for (results.array.items) |item| {
        if (item != .object) continue;
        const name_val = item.object.get("Name") orelse continue;
        if (name_val != .string or name_val.string.len == 0) continue;
        const maintainer = if (item.object.get("Maintainer")) |value|
            if (value == .string) value.string else ""
        else
            "";
        const name = try allocator.dupe(u8, name_val.string);
        errdefer allocator.free(name);
        const who = try allocator.dupe(u8, maintainer);
        errdefer allocator.free(who);
        try found.append(allocator, .{
            .name = name,
            .maintainer = who,
            .allocator = allocator,
        });
    }
    return try found.toOwnedSlice(allocator);
}

/// Suffix for an AUR row. The first time an installed package is seen, its
/// maintainer is recorded and not treated as a change. A later difference
/// keeps warning against that recorded maintainer.
pub fn suffix(allocator: Allocator, pkg: []const u8, maintainer: []const u8, installed: bool) ![]u8 {
    const current = if (maintainer.len == 0) "orphan" else maintainer;
    if (!installed) return formatCurrent(allocator, current);

    const previous = readStored(allocator, pkg);
    defer if (previous) |value| allocator.free(value);
    if (previous == null) {
        writeStored(allocator, pkg, current) catch {};
        return formatCurrent(allocator, current);
    }
    if (!std.mem.eql(u8, previous.?, current)) {
        return std.fmt.allocPrint(allocator, " (owner changed: {s} -> {s})", .{ previous.?, current });
    }
    return formatCurrent(allocator, current);
}

fn formatCurrent(allocator: Allocator, current: []const u8) ![]u8 {
    if (std.mem.eql(u8, current, "orphan")) return allocator.dupe(u8, " (Orphaned)");
    return std.fmt.allocPrint(allocator, " (maintainer: {s})", .{current});
}

fn storePath(allocator: Allocator, pkg: []const u8) ![]u8 {
    const home = fs_compat.getenv("HOME") orelse return error.NoHome;
    return std.fmt.allocPrint(allocator, "{s}/.local/share/here/aur/{s}", .{ home, pkg });
}

fn readStored(allocator: Allocator, pkg: []const u8) ?[]u8 {
    const path = storePath(allocator, pkg) catch return null;
    defer allocator.free(path);
    const body = fs_compat.readFileAlloc(allocator, path, 128) catch return null;
    const trimmed = std.mem.trim(u8, body, " \t\r\n");
    if (trimmed.len == 0) {
        allocator.free(body);
        return null;
    }
    if (trimmed.ptr == body.ptr and trimmed.len == body.len) return body;
    const owned = allocator.dupe(u8, trimmed) catch {
        allocator.free(body);
        return null;
    };
    allocator.free(body);
    return owned;
}

fn writeStored(allocator: Allocator, pkg: []const u8, maintainer: []const u8) !void {
    const path = try storePath(allocator, pkg);
    defer allocator.free(path);
    if (std.fs.path.dirname(path)) |dir| fs_compat.cwd().makePath(dir) catch return error.FileSystem;
    try fs_compat.writeFileAll(path, maintainer);
}

test "aur info reads the maintainer and an orphan" {
    const sample =
        \\{"resultcount":2,"results":[
        \\{"Name":"akkoma","Maintainer":"alice"},
        \\{"Name":"akkoma-bin","Maintainer":null}
        \\],"type":"multiinfo"}
    ;
    const found = try parseInfo(std.testing.allocator, sample);
    defer {
        for (found) |*item| item.deinit();
        std.testing.allocator.free(found);
    }
    try std.testing.expectEqual(@as(usize, 2), found.len);
    try std.testing.expectEqualStrings("alice", found[0].maintainer);
    try std.testing.expectEqual(@as(usize, 0), found[1].maintainer.len);
}
