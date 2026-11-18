const std = @import("std");
const fs_compat = @import("fs_compat.zig");
const print = std.debug.print;
const Allocator = std.mem.Allocator;

pub const Error = error{
    Network,
    Parse,
    PinMismatch,
    UnsafeTag,
    FileSystem,
};

const script_limit: usize = 1024 * 1024;
const probe_limit: usize = 12;

pub const Hit = struct {
    owner: []u8,
    name: []u8,
    repo: []u8,
    tag: []u8,
    description: []u8,
    /// Previous owner when the repo saved at install time now resolves elsewhere.
    changed_from: ?[]u8 = null,
    allocator: Allocator,

    pub fn deinit(self: *Hit) void {
        self.allocator.free(self.owner);
        self.allocator.free(self.name);
        self.allocator.free(self.repo);
        self.allocator.free(self.tag);
        self.allocator.free(self.description);
        if (self.changed_from) |previous| self.allocator.free(previous);
    }
};

pub const Selection = struct {
    repo: []const u8,
    tag: []const u8,
};

const Candidate = struct {
    owner: []u8,
    name: []u8,
    repo: []u8,
    description: []u8,
    stars: i64,
    allocator: Allocator,

    fn deinit(self: *Candidate) void {
        self.allocator.free(self.owner);
        self.allocator.free(self.name);
        self.allocator.free(self.repo);
        self.allocator.free(self.description);
    }
};

pub fn validTag(tag: []const u8) bool {
    if (tag.len == 0 or tag.len > 64) return false;
    for (tag) |c| {
        const ok = std.ascii.isAlphanumeric(c) or c == '.' or c == '_' or c == '-' or c == '+';
        if (!ok) return false;
    }
    return true;
}

pub fn parseTagName(json: []const u8) ?[]const u8 {
    const key = "\"tag_name\"";
    const at = std.mem.indexOf(u8, json, key) orelse return null;
    var i = at + key.len;
    while (i < json.len and (json[i] == ' ' or json[i] == '\t' or json[i] == '\n' or json[i] == '\r' or json[i] == ':')) : (i += 1) {}
    if (i >= json.len or json[i] != '"') return null;
    i += 1;
    const start = i;
    while (i < json.len and json[i] != '"' and json[i] != '\\') : (i += 1) {}
    if (i >= json.len or json[i] != '"') return null;
    const tag = json[start..i];
    if (!validTag(tag)) return null;
    return tag;
}

/// `github/<owner>/<name> <tag>` with an optional parenthetical note after the tag.
pub fn parseSelection(id: []const u8) ?Selection {
    const trimmed = std.mem.trim(u8, id, " ");
    const prefix = "github/";
    if (!std.mem.startsWith(u8, trimmed, prefix)) return null;
    var rest = trimmed[prefix.len..];
    if (std.mem.indexOf(u8, rest, " (")) |note| rest = rest[0..note];
    const space = std.mem.indexOfScalar(u8, rest, ' ') orelse return null;
    const repo = rest[0..space];
    const tag = std.mem.trim(u8, rest[space + 1 ..], " ");
    if (std.mem.count(u8, repo, "/") != 1) return null;
    if (!validTag(tag)) return null;
    const slash = std.mem.indexOfScalar(u8, repo, '/').?;
    if (slash == 0 or slash + 1 >= repo.len) return null;
    if (!validTag(repo[0..slash]) or !validTag(repo[slash + 1 ..])) return null;
    return .{ .repo = repo, .tag = tag };
}

pub fn exactRepos(allocator: Allocator, json: []const u8, query: []const u8) Error![]Candidate {
    if (std.mem.indexOf(u8, json, "rate limit") != null) return Error.Network;
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, json, .{}) catch return Error.Parse;
    defer parsed.deinit();
    if (parsed.value != .object) return Error.Parse;
    const items_val = parsed.value.object.get("items") orelse return allocator.alloc(Candidate, 0) catch Error.FileSystem;
    if (items_val != .array) return Error.Parse;

    var found = std.ArrayList(Candidate){ .items = &.{}, .capacity = 0 };
    errdefer {
        for (found.items) |*item| item.deinit();
        found.deinit(allocator);
    }
    for (items_val.array.items) |item| {
        if (item != .object) continue;
        if (item.object.get("fork")) |fork| {
            if (fork == .bool and fork.bool) continue;
        }
        const name_val = item.object.get("name") orelse continue;
        if (name_val != .string) continue;
        if (!std.ascii.eqlIgnoreCase(name_val.string, query)) continue;
        const owner_val = item.object.get("owner") orelse continue;
        if (owner_val != .object) continue;
        const login_val = owner_val.object.get("login") orelse continue;
        if (login_val != .string or !validTag(login_val.string)) continue;
        if (!validTag(name_val.string)) continue;

        const description = if (item.object.get("description")) |desc|
            if (desc == .string) desc.string else ""
        else
            "";
        const stars: i64 = if (item.object.get("stargazers_count")) |count| switch (count) {
            .integer => |n| n,
            .float => |n| @intFromFloat(n),
            else => 0,
        } else 0;

        const owner = allocator.dupe(u8, login_val.string) catch return Error.FileSystem;
        errdefer allocator.free(owner);
        const name = allocator.dupe(u8, name_val.string) catch return Error.FileSystem;
        errdefer allocator.free(name);
        const repo = std.fmt.allocPrint(allocator, "{s}/{s}", .{ owner, name }) catch return Error.FileSystem;
        errdefer allocator.free(repo);
        const desc = allocator.dupe(u8, description) catch return Error.FileSystem;
        found.append(allocator, .{
            .owner = owner,
            .name = name,
            .repo = repo,
            .description = desc,
            .stars = stars,
            .allocator = allocator,
        }) catch return Error.FileSystem;
    }

    std.mem.sort(Candidate, found.items, {}, struct {
        fn lessThan(_: void, a: Candidate, b: Candidate) bool {
            return a.stars > b.stars;
        }
    }.lessThan);

    if (found.items.len > probe_limit) {
        for (found.items[probe_limit..]) |*extra| extra.deinit();
        found.shrinkRetainingCapacity(probe_limit);
    }
    return found.toOwnedSlice(allocator) catch Error.FileSystem;
}

pub fn search(allocator: Allocator, query: []const u8) Error![]Hit {
    if (!validTag(query)) return allocator.alloc(Hit, 0) catch Error.FileSystem;
    const url = std.fmt.allocPrint(allocator, "https://api.github.com/search/repositories?q={s}+in:name&per_page=30&sort=stars", .{query}) catch return Error.FileSystem;
    defer allocator.free(url);
    const body = curlAlloc(allocator, url, true) catch |err| {
        if (err == Error.Network) return allocator.alloc(Hit, 0) catch Error.FileSystem;
        return err;
    };
    defer allocator.free(body);
    if (std.mem.indexOf(u8, body, "rate limit") != null) {
        print("GitHub rate limit reached; no install.sh rows for this search.\n", .{});
        return allocator.alloc(Hit, 0) catch Error.FileSystem;
    }

    const candidates = exactRepos(allocator, body, query) catch |err| {
        if (err == Error.Parse or err == Error.Network) return allocator.alloc(Hit, 0) catch Error.FileSystem;
        return err;
    };
    defer {
        for (candidates) |*candidate| candidate.deinit();
        allocator.free(candidates);
    }

    var owner_state = OwnerState{};
    const owner_thread = std.Thread.spawn(.{}, loadOwnerChange, .{ query, &owner_state }) catch null;
    const probed = probeCandidates(candidates) catch |err| {
        if (owner_thread) |thread| thread.join() else loadOwnerChange(query, &owner_state);
        applyOwnerChange(allocator, &.{}, &owner_state);
        return err;
    };
    defer std.heap.page_allocator.free(probed);
    if (owner_thread) |thread| thread.join() else loadOwnerChange(query, &owner_state);

    var hits = std.ArrayList(Hit){ .items = &.{}, .capacity = 0 };
    errdefer {
        applyOwnerChange(allocator, hits.items, &owner_state);
        for (hits.items) |*hit| hit.deinit();
        hits.deinit(allocator);
    }
    for (candidates, probed) |candidate, slot| {
        const tag = slot.tag orelse continue;
        defer std.heap.page_allocator.free(tag);
        const owner = allocator.dupe(u8, candidate.owner) catch return Error.FileSystem;
        const name = allocator.dupe(u8, candidate.name) catch return Error.FileSystem;
        const repo = allocator.dupe(u8, candidate.repo) catch return Error.FileSystem;
        const description = allocator.dupe(u8, candidate.description) catch return Error.FileSystem;
        const owned_tag = allocator.dupe(u8, tag) catch return Error.FileSystem;
        hits.append(allocator, .{
            .owner = owner,
            .name = name,
            .repo = repo,
            .tag = owned_tag,
            .description = description,
            .allocator = allocator,
        }) catch return Error.FileSystem;
    }

    applyOwnerChange(allocator, hits.items, &owner_state);
    return hits.toOwnedSlice(allocator) catch Error.FileSystem;
}

const Slot = struct { tag: ?[]u8 = null };

fn probeWidth(remaining: usize) usize {
    const cpu = std.Thread.getCpuCount() catch 4;
    // Each probe is waiting on the network, so a few workers past the core count still help.
    const budget = @min(@max(cpu, 4), 16);
    return @min(remaining, budget);
}

fn probeRepo(repo: []const u8, slot: *Slot) void {
    const alloc = std.heap.page_allocator;
    const tag = latestTag(alloc, repo) catch return;
    if (!scriptExists(repo, tag)) {
        alloc.free(tag);
        return;
    }
    slot.tag = tag;
}

fn probeCandidates(candidates: []const Candidate) Error![]Slot {
    const allocator = std.heap.page_allocator;
    const slots = allocator.alloc(Slot, candidates.len) catch return Error.FileSystem;
    for (slots) |*slot| slot.* = .{};

    var cursor: usize = 0;
    while (cursor < candidates.len) {
        const width = probeWidth(candidates.len - cursor);
        var threads: [16]std.Thread = undefined;
        var started: usize = 0;
        for (0..width) |offset| {
            const repo = candidates[cursor + offset].repo;
            const slot = &slots[cursor + offset];
            if (std.Thread.spawn(.{}, probeRepo, .{ repo, slot })) |thread| {
                threads[started] = thread;
                started += 1;
            } else |_| {
                probeRepo(repo, slot);
            }
        }
        for (threads[0..started]) |thread| thread.join();
        cursor += width;
    }
    return slots;
}

const OwnerState = struct {
    previous: ?[]u8 = null,
    current: ?[]u8 = null,
};

fn loadOwnerChange(query: []const u8, state: *OwnerState) void {
    const alloc = std.heap.page_allocator;
    const stored = readTrimmedFile(alloc, query, "repo", false) orelse return;
    defer alloc.free(stored);
    const slash = std.mem.indexOfScalar(u8, stored, '/') orelse return;
    if (slash == 0 or slash + 1 >= stored.len) return;
    if (!std.ascii.eqlIgnoreCase(stored[slash + 1 ..], query)) return;
    const current = resolveOwner(alloc, stored) orelse return;
    if (std.ascii.eqlIgnoreCase(stored[0..slash], current)) {
        alloc.free(current);
        return;
    }
    state.previous = alloc.dupe(u8, stored[0..slash]) catch {
        alloc.free(current);
        return;
    };
    state.current = current;
}

fn applyOwnerChange(allocator: Allocator, hits: []Hit, state: *OwnerState) void {
    defer if (state.previous) |value| {
        state.previous = null;
        std.heap.page_allocator.free(value);
    };
    defer if (state.current) |value| {
        state.current = null;
        std.heap.page_allocator.free(value);
    };
    const previous = state.previous orelse return;
    const current = state.current orelse return;
    for (hits) |*hit| {
        if (!std.ascii.eqlIgnoreCase(hit.owner, current)) continue;
        hit.changed_from = allocator.dupe(u8, previous) catch return;
    }
}

pub fn install(allocator: Allocator, repo: []const u8, tag: []const u8) Error!void {
    if (std.mem.count(u8, repo, "/") != 1 or !validTag(tag)) return Error.UnsafeTag;
    const slash = std.mem.indexOfScalar(u8, repo, '/') orelse return Error.UnsafeTag;
    const owner = repo[0..slash];
    const name = repo[slash + 1 ..];
    if (!validTag(owner) or !validTag(name)) return Error.UnsafeTag;

    const home = fs_compat.getenv("HOME") orelse return Error.FileSystem;
    const dir = std.fmt.allocPrint(allocator, "{s}/.local/share/here/github/{s}/{s}", .{ home, name, tag }) catch return Error.FileSystem;
    defer allocator.free(dir);
    fs_compat.cwd().makePath(dir) catch return Error.FileSystem;

    const script_url = std.fmt.allocPrint(allocator, "https://raw.githubusercontent.com/{s}/{s}/install.sh", .{ repo, tag }) catch return Error.FileSystem;
    defer allocator.free(script_url);
    print("github/{s} {s}\n", .{ repo, tag });
    print("  script {s}\n", .{script_url});

    const body = try curlAlloc(allocator, script_url, false);
    defer allocator.free(body);
    if (body.len == 0 or body.len > script_limit) return Error.Parse;

    var digest: [std.crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(body, &digest, .{});
    const hex = std.fmt.bytesToHex(digest, .lower);

    const pin_path = std.fmt.allocPrint(allocator, "{s}/install.sh.sha256", .{dir}) catch return Error.FileSystem;
    defer allocator.free(pin_path);
    if (fs_compat.readFileAlloc(allocator, pin_path, 128) catch null) |previous| {
        defer allocator.free(previous);
        const pinned = std.mem.trim(u8, previous, " \t\r\n");
        if (pinned.len > 0 and !std.mem.eql(u8, pinned, &hex)) {
            print("❌ {s} is pinned to {s}\n", .{ tag, pinned });
            print("   The script at that tag now hashes to {s}\n", .{&hex});
            return Error.PinMismatch;
        }
    }

    const script_path = std.fmt.allocPrint(allocator, "{s}/install.sh", .{dir}) catch return Error.FileSystem;
    defer allocator.free(script_path);
    fs_compat.writeFileAll(script_path, body) catch return Error.FileSystem;
    fs_compat.writeFileAll(pin_path, &hex) catch return Error.FileSystem;
    print("  sha256 {s}\n", .{&hex});

    const shell = shellFor(body);
    var child = fs_compat.Child.init(&.{ shell, script_path }, allocator);
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;
    const term = child.spawnAndWait() catch return Error.FileSystem;
    switch (term) {
        .Exited => |code| if (code != 0) return Error.Network,
        else => return Error.Network,
    }

    const base = std.fmt.allocPrint(allocator, "{s}/.local/share/here/github/{s}", .{ home, name }) catch return Error.FileSystem;
    defer allocator.free(base);
    fs_compat.cwd().makePath(base) catch return Error.FileSystem;
    const installed_path = std.fmt.allocPrint(allocator, "{s}/installed", .{base}) catch return Error.FileSystem;
    defer allocator.free(installed_path);
    const repo_path = std.fmt.allocPrint(allocator, "{s}/repo", .{base}) catch return Error.FileSystem;
    defer allocator.free(repo_path);
    fs_compat.writeFileAll(installed_path, tag) catch return Error.FileSystem;
    fs_compat.writeFileAll(repo_path, repo) catch return Error.FileSystem;
}

pub fn installedTag(allocator: Allocator, name: []const u8) ?[]u8 {
    return readTrimmedFile(allocator, name, "installed", true);
}

fn shellFor(body: []const u8) []const u8 {
    const line_end = std.mem.indexOfScalar(u8, body, '\n') orelse body.len;
    const line = body[0..@min(line_end, 80)];
    if (std.mem.indexOf(u8, line, "bash") != null) return "bash";
    return "sh";
}

fn resolveOwner(allocator: Allocator, repo: []const u8) ?[]u8 {
    const url = std.fmt.allocPrint(allocator, "https://api.github.com/repos/{s}", .{repo}) catch return null;
    defer allocator.free(url);
    const body = curlAlloc(allocator, url, true) catch return null;
    defer allocator.free(body);
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch return null;
    defer parsed.deinit();
    if (parsed.value != .object) return null;
    const owner_val = parsed.value.object.get("owner") orelse return null;
    if (owner_val != .object) return null;
    const login = owner_val.object.get("login") orelse return null;
    if (login != .string or !validTag(login.string)) return null;
    return allocator.dupe(u8, login.string) catch null;
}

fn readTrimmedFile(allocator: Allocator, name: []const u8, leaf: []const u8, tag_file: bool) ?[]u8 {
    if (!validTag(name)) return null;
    const home = fs_compat.getenv("HOME") orelse return null;
    const path = std.fmt.allocPrint(allocator, "{s}/.local/share/here/github/{s}/{s}", .{ home, name, leaf }) catch return null;
    defer allocator.free(path);
    const body = fs_compat.readFileAlloc(allocator, path, 256) catch return null;
    const trimmed = std.mem.trim(u8, body, " \t\r\n");
    if (tag_file and !validTag(trimmed)) {
        allocator.free(body);
        return null;
    }
    if (trimmed.len == 0 or trimmed.len > 128) {
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

pub fn latestTag(allocator: Allocator, repo: []const u8) Error![]u8 {
    const url = std.fmt.allocPrint(allocator, "https://api.github.com/repos/{s}/releases/latest", .{repo}) catch return Error.FileSystem;
    defer allocator.free(url);
    const body = try curlAlloc(allocator, url, true);
    defer allocator.free(body);
    const tag = parseTagName(body) orelse return Error.Parse;
    return allocator.dupe(u8, tag) catch Error.FileSystem;
}

fn scriptExists(repo: []const u8, tag: []const u8) bool {
    var url_buf: [256]u8 = undefined;
    const url = std.fmt.bufPrint(&url_buf, "https://raw.githubusercontent.com/{s}/{s}/install.sh", .{ repo, tag }) catch return false;
    const argv = [_][]const u8{ "curl", "-fsSL", "--max-time", "15", "-o", "/dev/null", "-H", "User-Agent: here", url };
    const result = fs_compat.Child.run(.{
        .allocator = std.heap.page_allocator,
        .argv = &argv,
    }) catch return false;
    std.heap.page_allocator.free(result.stdout);
    std.heap.page_allocator.free(result.stderr);
    return switch (result.term) {
        .Exited => |code| code == 0,
        else => false,
    };
}

fn curlAlloc(allocator: Allocator, url: []const u8, github_api: bool) Error![]u8 {
    const argv: []const []const u8 = if (github_api)
        &.{ "curl", "-fsSL", "--max-time", "20", "-H", "Accept: application/vnd.github+json", "-H", "User-Agent: here", url }
    else
        &.{ "curl", "-fsSL", "--max-time", "20", "-H", "User-Agent: here", url };
    const result = fs_compat.Child.run(.{
        .allocator = allocator,
        .argv = argv,
    }) catch return Error.Network;
    defer allocator.free(result.stderr);
    errdefer allocator.free(result.stdout);
    switch (result.term) {
        .Exited => |code| if (code != 0) {
            allocator.free(result.stdout);
            return Error.Network;
        },
        else => {
            allocator.free(result.stdout);
            return Error.Network;
        },
    }
    if (result.stdout.len > script_limit) {
        allocator.free(result.stdout);
        return Error.Parse;
    }
    return result.stdout;
}

test "exact name keeps the owner and drops forks and lookalikes" {
    const sample =
        \\{"items":[
        \\{"name":"koma","fork":false,"stargazers_count":88,"description":"ide","owner":{"login":"aula-id"}},
        \\{"name":"Koma","fork":true,"stargazers_count":500,"description":"fork","owner":{"login":"someone"}},
        \\{"name":"komai","fork":false,"stargazers_count":9,"description":"chat","owner":{"login":"other"}}
        \\]}
    ;
    const found = try exactRepos(std.testing.allocator, sample, "koma");
    defer {
        for (found) |*item| item.deinit();
        std.testing.allocator.free(found);
    }
    try std.testing.expectEqual(@as(usize, 1), found.len);
    try std.testing.expectEqualStrings("aula-id", found[0].owner);
    try std.testing.expectEqualStrings("aula-id/koma", found[0].repo);
}

test "menu id keeps owner and tag and ignores the takeover note" {
    const selected = parseSelection("github/aula-id/koma v0.4.6 (owner changed: aula-id -> evil)").?;
    try std.testing.expectEqualStrings("aula-id/koma", selected.repo);
    try std.testing.expectEqualStrings("v0.4.6", selected.tag);
    try std.testing.expect(parseSelection("github/aula-id/koma") == null);
    try std.testing.expect(parseTagName("{\"tag_name\": \"v1.0;rm -rf\"}") == null);
}
