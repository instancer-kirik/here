const std = @import("std");
const print = std.debug.print;
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const system = @import("system.zig");
const SystemInfo = system.SystemInfo;

pub const PackageProfile = struct {
    created: []const u8,
    system: ProfileSystemInfo,
    packages: Packages,
    config: ?ConfigData = null,

    const ProfileSystemInfo = struct {
        distro: []const u8,
        package_manager: []const u8,
        arch: []const u8,
        kernel: []const u8,
    };

    const Packages = struct {
        native: [][]const u8,
        flatpak: ?[][]const u8 = null,
        appimage: ?[][]const u8 = null,
        snap: ?[][]const u8 = null,
    };

    const ConfigData = struct {
        dotfiles: ?[][]const u8 = null,
        xdg_config: ?[][]const u8 = null,
        version_managers: ?VersionManagerData = null,
    };

    const VersionManagerData = struct {
        asdf: ?[][]const u8 = null,
        nvm: ?[][]const u8 = null,
        rustup: ?[][]const u8 = null,
    };
};

pub fn exportProfile(allocator: Allocator, filename: ?[]const u8, include_config: bool) !void {
    const profile_name = filename orelse "here-profile.json";

    if (include_config) {
        print("📦 Creating package export profile with config data to '{s}'...\n", .{profile_name});
    } else {
        print("📦 Creating package export profile to '{s}'...\n", .{profile_name});
    }

    // Get current timestamp
    const timestamp = std.time.timestamp();
    const timestamp_str = try std.fmt.allocPrint(allocator, "{d}", .{timestamp});
    defer allocator.free(timestamp_str);

    // Detect current system
    const system_info = try system.detectSystem(allocator);
    defer allocator.free(system_info.version_managers);
    defer allocator.free(system_info.package_sources);

    // Get kernel version
    const kernel_version = try getKernelVersion(allocator);
    defer allocator.free(kernel_version);

    // Get architecture
    const arch = try getArchitecture(allocator);
    defer allocator.free(arch);

    // Start building JSON
    var json_parts = ArrayList([]const u8){ .items = &[_][]const u8{}, .capacity = 0 };
    defer {
        for (json_parts.items) |part| allocator.free(part);
        json_parts.deinit(allocator);
    }

    // Header
    try json_parts.append(allocator, try allocator.dupe(u8, "{\n"));
    try json_parts.append(allocator, try std.fmt.allocPrint(allocator, "  \"created\": \"{s}\",\n", .{timestamp_str}));

    // System info
    try json_parts.append(allocator, try allocator.dupe(u8, "  \"system\": {\n"));
    try json_parts.append(allocator, try std.fmt.allocPrint(allocator, "    \"distro\": \"{s}\",\n", .{system_info.distro.toString()}));
    try json_parts.append(allocator, try std.fmt.allocPrint(allocator, "    \"package_manager\": \"{s}\",\n", .{system_info.package_manager.toString()}));
    try json_parts.append(allocator, try std.fmt.allocPrint(allocator, "    \"arch\": \"{s}\",\n", .{arch}));
    try json_parts.append(allocator, try std.fmt.allocPrint(allocator, "    \"kernel\": \"{s}\"\n", .{kernel_version}));
    try json_parts.append(allocator, try allocator.dupe(u8, "  },\n"));

    // Packages
    try json_parts.append(allocator, try allocator.dupe(u8, "  \"packages\": {\n"));

    // Native packages
    const native_packages = try getNativePackages(allocator, system_info.package_manager);
    defer {
        for (native_packages) |pkg| allocator.free(pkg);
        allocator.free(native_packages);
    }

    try json_parts.append(allocator, try allocator.dupe(u8, "    \"native\": [\n"));
    for (native_packages, 0..) |package, i| {
        const comma = if (i == native_packages.len - 1) "" else ",";
        try json_parts.append(allocator, try std.fmt.allocPrint(allocator, "      \"{s}\"{s}\n", .{ package, comma }));
    }
    try json_parts.append(allocator, try allocator.dupe(u8, "    ]"));

    // Flatpak packages
    const flatpak_packages = try getFlatpakPackages(allocator);
    defer {
        for (flatpak_packages) |pkg| allocator.free(pkg);
        allocator.free(flatpak_packages);
    }

    if (flatpak_packages.len > 0) {
        try json_parts.append(allocator, try allocator.dupe(u8, ",\n    \"flatpak\": [\n"));
        for (flatpak_packages, 0..) |package, i| {
            const comma = if (i == flatpak_packages.len - 1) "" else ",";
            try json_parts.append(allocator, try std.fmt.allocPrint(allocator, "      \"{s}\"{s}\n", .{ package, comma }));
        }
        try json_parts.append(allocator, try allocator.dupe(u8, "    ]"));
    }

    // AppImage packages
    const appimage_packages = try getAppImagePackages(allocator);
    defer {
        for (appimage_packages) |pkg| allocator.free(pkg);
        allocator.free(appimage_packages);
    }

    if (appimage_packages.len > 0) {
        try json_parts.append(allocator, try allocator.dupe(u8, ",\n    \"appimage\": [\n"));
        for (appimage_packages, 0..) |package, i| {
            const comma = if (i == appimage_packages.len - 1) "" else ",";
            try json_parts.append(allocator, try std.fmt.allocPrint(allocator, "      \"{s}\"{s}\n", .{ package, comma }));
        }
        try json_parts.append(allocator, try allocator.dupe(u8, "    ]"));
    }

    try json_parts.append(allocator, try allocator.dupe(u8, "\n  }"));

    // Version managers
    if (system_info.version_managers.len > 0) {
        try json_parts.append(allocator, try allocator.dupe(u8, ",\n  \"version_managers\": {\n"));
        for (system_info.version_managers, 0..) |vm, i| {
            const packages = try getVersionManagerPackages(allocator, vm);
            defer {
                for (packages) |pkg| allocator.free(pkg);
                allocator.free(packages);
            }

            if (packages.len > 0) {
                const comma = if (i == system_info.version_managers.len - 1) "" else ",";
                try json_parts.append(allocator, try std.fmt.allocPrint(allocator, "    \"{s}\": [\n", .{vm.toString()}));
                for (packages, 0..) |package, j| {
                    const pkg_comma = if (j == packages.len - 1) "" else ",";
                    try json_parts.append(allocator, try std.fmt.allocPrint(allocator, "      \"{s}\"{s}\n", .{ package, pkg_comma }));
                }
                try json_parts.append(allocator, try std.fmt.allocPrint(allocator, "    ]{s}\n", .{comma}));
            }
        }
        try json_parts.append(allocator, try allocator.dupe(u8, "  }"));
    }

    // Config data (if requested)
    if (include_config) {
        try json_parts.append(allocator, try allocator.dupe(u8, ",\n  \"config\": {\n"));

        // Dotfiles
        const dotfiles = try getDotfiles(allocator);
        defer {
            for (dotfiles) |file| allocator.free(file);
            allocator.free(dotfiles);
        }

        if (dotfiles.len > 0) {
            try json_parts.append(allocator, try allocator.dupe(u8, "    \"dotfiles\": [\n"));
            for (dotfiles, 0..) |file, i| {
                const comma = if (i == dotfiles.len - 1) "" else ",";
                try json_parts.append(allocator, try std.fmt.allocPrint(allocator, "      \"{s}\"{s}\n", .{ file, comma }));
            }
            try json_parts.append(allocator, try allocator.dupe(u8, "    ]\n"));
        }

        try json_parts.append(allocator, try allocator.dupe(u8, "  }"));
    }

    try json_parts.append(allocator, try allocator.dupe(u8, "\n}\n"));

    // Write to file
    const file = try std.fs.cwd().createFile(profile_name, .{});
    defer file.close();

    for (json_parts.items) |part| {
        try file.writeAll(part);
    }

    // Summary
    print("✅ Profile export created successfully!\n", .{});
    print("📊 Summary:\n", .{});
    print("  • Native packages: {}\n", .{native_packages.len});
    print("  • Flatpak packages: {}\n", .{flatpak_packages.len});
    print("  • AppImage packages: {}\n", .{appimage_packages.len});
    print("  • Version managers: {}\n", .{system_info.version_managers.len});
    if (include_config) {
        print("  • Configuration data included\n", .{});
    }
    print("💡 Import on new system with: here import {s}\n", .{profile_name});
}

fn getKernelVersion(allocator: Allocator) ![]const u8 {
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "uname", "-r" },
    }) catch return try allocator.dupe(u8, "unknown");

    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    if (result.stdout.len > 0) {
        const trimmed = std.mem.trim(u8, result.stdout, " \t\r\n");
        return try allocator.dupe(u8, trimmed);
    }

    return try allocator.dupe(u8, "unknown");
}

fn getArchitecture(allocator: Allocator) ![]const u8 {
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "uname", "-m" },
    }) catch return try allocator.dupe(u8, "unknown");

    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    if (result.stdout.len > 0) {
        const trimmed = std.mem.trim(u8, result.stdout, " \t\r\n");
        return try allocator.dupe(u8, trimmed);
    }

    return try allocator.dupe(u8, "unknown");
}

fn getNativePackages(allocator: Allocator, package_manager: system.PackageManager) ![][]const u8 {
    var packages = ArrayList([]const u8){ .items = &[_][]const u8{}, .capacity = 0 };

    const cmd = switch (package_manager) {
        .yay, .paru => &[_][]const u8{ package_manager.toString(), "-Q" },
        .pacman => &[_][]const u8{ "pacman", "-Q" },
        .apt => &[_][]const u8{ "apt", "list", "--installed" },
        .zypper => &[_][]const u8{ "zypper", "search", "--installed-only" },
        .dnf => &[_][]const u8{ "dnf", "list", "installed" },
        .nix => &[_][]const u8{ "nix-env", "-q" },
        .unknown => return packages.toOwnedSlice(allocator),
    };

    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = cmd,
    }) catch return packages.toOwnedSlice(allocator);

    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    if (result.stdout.len > 0) {
        var lines = std.mem.splitScalar(u8, result.stdout, '\n');
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r\n");
            if (trimmed.len == 0) continue;

            // Extract package name based on package manager format
            const package_name = switch (package_manager) {
                .yay, .paru, .pacman => blk: {
                    if (std.mem.indexOf(u8, trimmed, " ")) |space_idx| {
                        break :blk trimmed[0..space_idx];
                    }
                    break :blk trimmed;
                },
                .apt => blk: {
                    if (std.mem.startsWith(u8, trimmed, "WARNING:") or
                        std.mem.startsWith(u8, trimmed, "Listing...")) continue;
                    if (std.mem.indexOf(u8, trimmed, "/")) |slash_idx| {
                        break :blk trimmed[0..slash_idx];
                    }
                    break :blk trimmed;
                },
                .zypper, .dnf => blk: {
                    var parts = std.mem.splitScalar(u8, trimmed, ' ');
                    if (parts.next()) |first_part| {
                        break :blk first_part;
                    }
                    break :blk trimmed;
                },
                .nix => trimmed,
                .unknown => trimmed,
            };

            if (package_name.len > 0) {
                try packages.append(allocator, try allocator.dupe(u8, package_name));
            }
        }
    }

    return packages.toOwnedSlice(allocator);
}

fn getFlatpakPackages(allocator: Allocator) ![][]const u8 {
    var packages = ArrayList([]const u8){ .items = &[_][]const u8{}, .capacity = 0 };

    if (!system.commandExists("flatpak")) {
        return packages.toOwnedSlice(allocator);
    }

    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "flatpak", "list", "--app", "--columns=application" },
    }) catch return packages.toOwnedSlice(allocator);

    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    if (result.stdout.len > 0) {
        var lines = std.mem.splitScalar(u8, result.stdout, '\n');
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r\n");
            if (trimmed.len > 0 and !std.mem.eql(u8, trimmed, "Application ID")) {
                try packages.append(allocator, try allocator.dupe(u8, trimmed));
            }
        }
    }

    return packages.toOwnedSlice(allocator);
}

fn getAppImagePackages(allocator: Allocator) ![][]const u8 {
    var packages = ArrayList([]const u8){ .items = &[_][]const u8{}, .capacity = 0 };

    // Look for AppImages in common directories
    const appimage_dirs = [_][]const u8{
        "~/Applications",
        "~/.local/bin",
        "/opt",
        "/usr/local/bin",
    };

    for (appimage_dirs) |dir_path| {
        const expanded_path = if (std.mem.startsWith(u8, dir_path, "~/"))
            try std.fmt.allocPrint(allocator, "{s}/{s}", .{ std.posix.getenv("HOME") orelse "/home/unknown", dir_path[2..] })
        else
            try allocator.dupe(u8, dir_path);
        defer allocator.free(expanded_path);

        var dir = std.fs.cwd().openDir(expanded_path, .{ .iterate = true }) catch continue;
        defer dir.close();

        var iterator = dir.iterate();
        while (iterator.next() catch null) |entry| {
            if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".AppImage")) {
                const name_without_ext = entry.name[0 .. entry.name.len - 9]; // Remove .AppImage
                try packages.append(allocator, try allocator.dupe(u8, name_without_ext));
            }
        }
    }

    return packages.toOwnedSlice(allocator);
}

fn getVersionManagerPackages(allocator: Allocator, vm: system.VersionManager) ![][]const u8 {
    var packages = ArrayList([]const u8){ .items = &[_][]const u8{}, .capacity = 0 };

    const cmd = switch (vm) {
        .asdf => &[_][]const u8{ "asdf", "plugin", "list" },
        .nvm => &[_][]const u8{ "nvm", "list" },
        .rustup => &[_][]const u8{ "rustup", "show" },
        else => return packages.toOwnedSlice(allocator),
    };

    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = cmd,
    }) catch return packages.toOwnedSlice(allocator);

    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    if (result.stdout.len > 0) {
        var lines = std.mem.splitScalar(u8, result.stdout, '\n');
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r\n");
            if (trimmed.len > 0) {
                try packages.append(allocator, try allocator.dupe(u8, trimmed));
            }
        }
    }

    return packages.toOwnedSlice(allocator);
}

fn getDotfiles(allocator: Allocator) ![][]const u8 {
    var dotfiles = ArrayList([]const u8){ .items = &[_][]const u8{}, .capacity = 0 };

    const home_dir = std.posix.getenv("HOME") orelse return dotfiles.toOwnedSlice(allocator);

    var dir = std.fs.cwd().openDir(home_dir, .{ .iterate = true }) catch return dotfiles.toOwnedSlice(allocator);
    defer dir.close();

    var iterator = dir.iterate();
    while (iterator.next() catch null) |entry| {
        if (entry.kind == .file and std.mem.startsWith(u8, entry.name, ".") and entry.name.len > 1) {
            // Common dotfiles
            if (std.mem.eql(u8, entry.name, ".bashrc") or
                std.mem.eql(u8, entry.name, ".zshrc") or
                std.mem.eql(u8, entry.name, ".gitconfig") or
                std.mem.eql(u8, entry.name, ".vimrc") or
                std.mem.eql(u8, entry.name, ".tmux.conf") or
                std.mem.eql(u8, entry.name, ".profile"))
            {
                try dotfiles.append(allocator, try allocator.dupe(u8, entry.name));
            }
        }
    }

    return dotfiles.toOwnedSlice(allocator);
}
