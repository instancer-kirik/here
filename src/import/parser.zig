const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

pub const ProfileInfo = struct {
    system_distro: []const u8,
    system_package_manager: []const u8,
    system_arch: []const u8,
    native_packages: ArrayList([]const u8),
    flatpak_packages: ArrayList([]const u8),
    appimage_packages: ArrayList([]const u8),
    dotfiles: ArrayList([]const u8),

    const Self = @This();

    pub fn init() Self {
        return Self{
            .system_distro = "unknown",
            .system_package_manager = "unknown",
            .system_arch = "unknown",
            .native_packages = ArrayList([]const u8){ .items = &[_][]const u8{}, .capacity = 0 },
            .flatpak_packages = ArrayList([]const u8){ .items = &[_][]const u8{}, .capacity = 0 },
            .appimage_packages = ArrayList([]const u8){ .items = &[_][]const u8{}, .capacity = 0 },
            .dotfiles = ArrayList([]const u8){ .items = &[_][]const u8{}, .capacity = 0 },
        };
    }

    pub fn deinit(self: *Self, allocator: Allocator) void {
        for (self.native_packages.items) |pkg| allocator.free(pkg);
        for (self.flatpak_packages.items) |pkg| allocator.free(pkg);
        for (self.appimage_packages.items) |pkg| allocator.free(pkg);
        for (self.dotfiles.items) |file| allocator.free(file);

        self.native_packages.deinit(allocator);
        self.flatpak_packages.deinit(allocator);
        self.appimage_packages.deinit(allocator);
        self.dotfiles.deinit(allocator);
    }

    pub fn totalPackages(self: *const Self) u32 {
        return @intCast(self.native_packages.items.len +
            self.flatpak_packages.items.len +
            self.appimage_packages.items.len);
    }
};

pub const ProfileParser = struct {
    allocator: Allocator,

    const Self = @This();

    pub fn init(allocator: Allocator) Self {
        return Self{ .allocator = allocator };
    }

    pub fn parseProfile(self: *Self, contents: []const u8) !ProfileInfo {
        var profile = ProfileInfo.init();

        // Extract system information
        profile.system_distro = self.extractStringValue(contents, "\"distro\": \"") orelse "unknown";
        profile.system_package_manager = self.extractStringValue(contents, "\"package_manager\": \"") orelse "unknown";
        profile.system_arch = self.extractStringValue(contents, "\"arch\": \"") orelse "unknown";

        // Extract packages
        try self.extractPackageArray(contents, "native", &profile.native_packages);
        try self.extractPackageArray(contents, "flatpak", &profile.flatpak_packages);
        try self.extractPackageArray(contents, "appimage", &profile.appimage_packages);

        // Extract dotfiles if present
        try self.extractDotfiles(contents, &profile.dotfiles);

        return profile;
    }

    fn extractStringValue(self: *Self, contents: []const u8, pattern: []const u8) ?[]const u8 {
        _ = self;
        if (std.mem.indexOf(u8, contents, pattern)) |start| {
            const after_pattern = contents[start + pattern.len ..];
            if (std.mem.indexOf(u8, after_pattern, "\"")) |end| {
                return after_pattern[0..end];
            }
        }
        return null;
    }

    fn extractPackageArray(self: *Self, contents: []const u8, section_name: []const u8, packages: *ArrayList([]const u8)) !void {
        const search_pattern = try std.fmt.allocPrint(self.allocator, "\"{s}\": [", .{section_name});
        defer self.allocator.free(search_pattern);

        if (std.mem.indexOf(u8, contents, search_pattern)) |section_start| {
            const section = contents[section_start..];
            if (std.mem.indexOf(u8, section, "]")) |section_end| {
                const section_content = section[0..section_end];
                var lines = std.mem.splitScalar(u8, section_content, '\n');

                while (lines.next()) |line| {
                    const trimmed = std.mem.trim(u8, line, " \t\r\n");

                    // Handle package entries with trailing comma
                    if (std.mem.startsWith(u8, trimmed, "\"") and std.mem.endsWith(u8, trimmed, "\",")) {
                        const pkg_name = trimmed[1 .. trimmed.len - 2];
                        if (pkg_name.len > 0) {
                            try packages.append(self.allocator, try self.allocator.dupe(u8, pkg_name));
                        }
                    }
                    // Handle last package entry without trailing comma
                    else if (std.mem.startsWith(u8, trimmed, "\"") and std.mem.endsWith(u8, trimmed, "\"")) {
                        const pkg_name = trimmed[1 .. trimmed.len - 1];
                        if (pkg_name.len > 0) {
                            try packages.append(self.allocator, try self.allocator.dupe(u8, pkg_name));
                        }
                    }
                }
            }
        }
    }

    fn extractDotfiles(self: *Self, contents: []const u8, dotfiles: *ArrayList([]const u8)) !void {
        const search_pattern = "\"dotfiles\": [";

        if (std.mem.indexOf(u8, contents, search_pattern)) |section_start| {
            const section = contents[section_start..];
            if (std.mem.indexOf(u8, section, "]")) |section_end| {
                const section_content = section[0..section_end];
                var lines = std.mem.splitScalar(u8, section_content, '\n');

                while (lines.next()) |line| {
                    const trimmed = std.mem.trim(u8, line, " \t\r\n");

                    if (std.mem.startsWith(u8, trimmed, "\"") and std.mem.endsWith(u8, trimmed, "\",")) {
                        const file_name = trimmed[1 .. trimmed.len - 2];
                        if (file_name.len > 0) {
                            try dotfiles.append(self.allocator, try self.allocator.dupe(u8, file_name));
                        }
                    } else if (std.mem.startsWith(u8, trimmed, "\"") and std.mem.endsWith(u8, trimmed, "\"")) {
                        const file_name = trimmed[1 .. trimmed.len - 1];
                        if (file_name.len > 0) {
                            try dotfiles.append(self.allocator, try self.allocator.dupe(u8, file_name));
                        }
                    }
                }
            }
        }
    }

    pub fn countPackagesInSection(contents: []const u8, section_name: []const u8) u32 {
        const allocator = std.heap.page_allocator;
        const search_pattern = std.fmt.allocPrint(allocator, "\"{s}\": [", .{section_name}) catch return 0;
        defer allocator.free(search_pattern);

        var count: u32 = 0;

        if (std.mem.indexOf(u8, contents, search_pattern)) |section_start| {
            const section = contents[section_start..];
            if (std.mem.indexOf(u8, section, "]")) |section_end| {
                const section_content = section[0..section_end];
                var lines = std.mem.splitScalar(u8, section_content, '\n');

                while (lines.next()) |line| {
                    const trimmed = std.mem.trim(u8, line, " \t\r\n");
                    if (std.mem.startsWith(u8, trimmed, "\"") and
                        (std.mem.endsWith(u8, trimmed, "\",") or std.mem.endsWith(u8, trimmed, "\"")))
                    {
                        count += 1;
                    }
                }
            }
        }

        return count;
    }
};

pub fn parseProfileQuick(allocator: Allocator, contents: []const u8) !ProfileInfo {
    var parser = ProfileParser.init(allocator);
    return parser.parseProfile(contents);
}
