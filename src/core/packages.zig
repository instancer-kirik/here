const std = @import("std");
const print = std.debug.print;
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const system = @import("system.zig");
const cli = @import("cli.zig");
const SystemInfo = system.SystemInfo;
const PackageManager = system.PackageManager;
const Command = cli.Command;

pub const DevelopmentTool = enum {
    node,
    python,
    ruby,
    rust,
    go,
    java,
    other,

    pub fn getVersionManagers(self: DevelopmentTool) []const system.VersionManager {
        return switch (self) {
            .node => &[_]system.VersionManager{ .asdf, .nvm, .fnm, .volta, .nodenv },
            .python => &[_]system.VersionManager{ .asdf, .pyenv, .conda, .pipenv, .pyflow },
            .ruby => &[_]system.VersionManager{ .asdf, .rbenv, .rvm },
            .rust => &[_]system.VersionManager{ .rustup, .asdf },
            .go => &[_]system.VersionManager{ .asdf, .g, .gvm },
            .java => &[_]system.VersionManager{ .asdf, .jenv, .jabba, .sdkman },
            .other => &[_]system.VersionManager{},
        };
    }
};

pub const PackageMatch = struct {
    name: []const u8,
    source: system.PackageSource,
    id: []const u8,
    description: []const u8,
};

pub const SearchResult = struct {
    packages: []PackageMatch,
    total_count: usize,

    pub fn deinit(self: SearchResult, allocator: Allocator) void {
        for (self.packages) |pkg| {
            allocator.free(pkg.name);
            allocator.free(pkg.id);
            allocator.free(pkg.description);
        }
        allocator.free(self.packages);
    }
};

pub fn buildCommand(allocator: Allocator, system_info: SystemInfo, command: Command, packages: []const []const u8) ![][]const u8 {
    var cmd_parts = ArrayList([]const u8){ .items = &[_][]const u8{}, .capacity = 0 };

    switch (system_info.package_manager) {
        .yay, .paru => {
            try cmd_parts.append(allocator, system_info.package_manager.toString());
            switch (command) {
                .install => {
                    try cmd_parts.append(allocator, "-S");
                    try cmd_parts.append(allocator, "--noconfirm");
                },
                .search => try cmd_parts.append(allocator, "-s"),
                .remove => {
                    try cmd_parts.append(allocator, "-R");
                    try cmd_parts.append(allocator, "--noconfirm");
                },
                .update => {
                    try cmd_parts.append(allocator, "-Syu");
                    try cmd_parts.append(allocator, "--noconfirm");
                },
                .list => try cmd_parts.append(allocator, "-Q"),
                .info => try cmd_parts.append(allocator, "-Si"),
                .prunable => try cmd_parts.append(allocator, "-Qdt"),
                .standalone => try cmd_parts.append(allocator, "-Qt"),
                else => return error.UnsupportedCommand,
            }
        },
        .pacman => {
            try cmd_parts.append(allocator, "sudo");
            try cmd_parts.append(allocator, "pacman");
            switch (command) {
                .install => {
                    try cmd_parts.append(allocator, "-S");
                    try cmd_parts.append(allocator, "--noconfirm");
                },
                .search => try cmd_parts.append(allocator, "-Ss"),
                .remove => {
                    try cmd_parts.append(allocator, "-R");
                    try cmd_parts.append(allocator, "--noconfirm");
                },
                .update => {
                    try cmd_parts.append(allocator, "-Syu");
                    try cmd_parts.append(allocator, "--noconfirm");
                },
                .list => try cmd_parts.append(allocator, "-Q"),
                .info => try cmd_parts.append(allocator, "-Si"),
                .prunable => try cmd_parts.append(allocator, "-Qdt"),
                .standalone => try cmd_parts.append(allocator, "-Qt"),
                else => return error.UnsupportedCommand,
            }
        },
        .apt => {
            try cmd_parts.append(allocator, "sudo");
            try cmd_parts.append(allocator, "apt");
            switch (command) {
                .install => {
                    try cmd_parts.append(allocator, "install");
                    try cmd_parts.append(allocator, "-y");
                },
                .search => try cmd_parts.append(allocator, "search"),
                .remove => {
                    try cmd_parts.append(allocator, "remove");
                    try cmd_parts.append(allocator, "-y");
                },
                .update => {
                    try cmd_parts.append(allocator, "update");
                },
                .list => try cmd_parts.append(allocator, "list --installed"),
                .info => try cmd_parts.append(allocator, "show"),
                .prunable => {
                    cmd_parts.clearRetainingCapacity();
                    try cmd_parts.append(allocator, "apt-mark");
                    try cmd_parts.append(allocator, "showauto");
                },
                .standalone => {
                    cmd_parts.clearRetainingCapacity();
                    try cmd_parts.append(allocator, "apt-mark");
                    try cmd_parts.append(allocator, "showmanual");
                },
                else => return error.UnsupportedCommand,
            }
        },
        .zypper => {
            try cmd_parts.append(allocator, "sudo");
            try cmd_parts.append(allocator, "zypper");
            switch (command) {
                .install => {
                    try cmd_parts.append(allocator, "install");
                    try cmd_parts.append(allocator, "-y");
                },
                .search => try cmd_parts.append(allocator, "search"),
                .remove => {
                    try cmd_parts.append(allocator, "remove");
                    try cmd_parts.append(allocator, "-y");
                },
                .update => {
                    try cmd_parts.append(allocator, "update");
                    try cmd_parts.append(allocator, "-y");
                },
                .list => try cmd_parts.append(allocator, "search --installed-only"),
                .info => try cmd_parts.append(allocator, "info"),
                .prunable => {
                    try cmd_parts.append(allocator, "packages");
                    try cmd_parts.append(allocator, "--unneeded");
                },
                .standalone => {
                    try cmd_parts.append(allocator, "packages");
                    try cmd_parts.append(allocator, "--orphaned");
                },
                else => return error.UnsupportedCommand,
            }
        },
        .dnf => {
            try cmd_parts.append(allocator, "sudo");
            try cmd_parts.append(allocator, "dnf");
            switch (command) {
                .install => {
                    try cmd_parts.append(allocator, "install");
                    try cmd_parts.append(allocator, "-y");
                },
                .search => try cmd_parts.append(allocator, "search"),
                .remove => {
                    try cmd_parts.append(allocator, "remove");
                    try cmd_parts.append(allocator, "-y");
                },
                .update => {
                    try cmd_parts.append(allocator, "update");
                    try cmd_parts.append(allocator, "-y");
                },
                .list => try cmd_parts.append(allocator, "list installed"),
                .info => try cmd_parts.append(allocator, "info"),
                .prunable => {
                    cmd_parts.clearRetainingCapacity();
                    try cmd_parts.append(allocator, "dnf");
                    try cmd_parts.append(allocator, "repoquery");
                    try cmd_parts.append(allocator, "--unneeded");
                },
                .standalone => {
                    cmd_parts.clearRetainingCapacity();
                    try cmd_parts.append(allocator, "dnf");
                    try cmd_parts.append(allocator, "repoquery");
                    try cmd_parts.append(allocator, "--userinstalled");
                },
                else => return error.UnsupportedCommand,
            }
        },
        .nix => {
            try cmd_parts.append(allocator, "nix-env");
            switch (command) {
                .install => try cmd_parts.append(allocator, "-iA"),
                .search => try cmd_parts.append(allocator, "-qaP"),
                .remove => try cmd_parts.append(allocator, "-e"),
                .update => try cmd_parts.append(allocator, "-u"),
                .list => try cmd_parts.append(allocator, "-q"),
                .info => try cmd_parts.append(allocator, "-qa --description"),
                else => return error.UnsupportedCommand,
            }
        },
        .unknown => return error.NoPackageManager,
    }

    // Add packages
    for (packages) |package| {
        try cmd_parts.append(allocator, package);
    }

    return cmd_parts.toOwnedSlice(allocator);
}

pub fn isDevelopmentTool(package: []const u8) ?DevelopmentTool {
    if (std.mem.eql(u8, package, "node") or std.mem.eql(u8, package, "nodejs")) return .node;
    if (std.mem.eql(u8, package, "python") or std.mem.eql(u8, package, "python3")) return .python;
    if (std.mem.eql(u8, package, "ruby")) return .ruby;
    if (std.mem.eql(u8, package, "rust") or std.mem.eql(u8, package, "cargo")) return .rust;
    if (std.mem.eql(u8, package, "go") or std.mem.eql(u8, package, "golang")) return .go;
    if (std.mem.eql(u8, package, "java") or std.mem.eql(u8, package, "openjdk")) return .java;
    return null;
}

pub fn suggestVersionManager(system_info: SystemInfo, tool: DevelopmentTool, package: []const u8) void {
    const preferred_managers = tool.getVersionManagers();

    // Check if we already have a suitable version manager
    for (system_info.version_managers) |vm| {
        for (preferred_managers) |preferred| {
            if (vm == preferred) {
                print("💡 Detected {s} - consider: {s} install {s} latest\n", .{ vm.toString(), vm.toString(), package });
                return;
            }
        }
    }

    // Suggest installing a version manager
    if (preferred_managers.len > 0) {
        const best_manager = preferred_managers[0];
        print("💡 For {s} development, consider installing {s} first:\n", .{ package, best_manager.toString() });

        switch (best_manager) {
            .asdf => print("   curl -L https://asdf-vm.com/install.sh | bash\n", .{}),
            .nvm => print("   curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash\n", .{}),
            .rustup => print("   curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh\n", .{}),
            else => print("   Visit the {s} documentation for installation instructions\n", .{best_manager.toString()}),
        }
        print("   Then use: {s} install {s} latest\n", .{ best_manager.toString(), package });
    }
}

pub fn installPackagesBatch(allocator: Allocator, filename: []const u8, install_native: bool, install_flatpak: bool, install_appimage: bool, install_all: bool) !void {
    const profile_parser = @import("../import/parser.zig");

    const contents = std.fs.cwd().readFileAlloc(allocator, filename, 1024 * 1024) catch |err| {
        print("❌ Failed to read profile file: {}\n", .{err});
        return;
    };
    defer allocator.free(contents);

    var parser = profile_parser.ProfileParser.init(allocator);
    var profile = parser.parseProfile(contents) catch |err| {
        print("❌ Failed to parse profile: {}\n", .{err});
        return;
    };
    defer profile.deinit(allocator);

    print("🚀 Starting batch package installation...\n", .{});
    print("📋 Profile: {s}\n", .{filename});
    print("🖥️  Source: {s} ({s})\n", .{ profile.system_distro, profile.system_package_manager });

    var installed_count: u32 = 0;
    var failed_count: u32 = 0;

    // Install native packages
    if (install_all or install_native) {
        if (profile.native_packages.items.len > 0) {
            print("\n📦 Installing {} native packages...\n", .{profile.native_packages.items.len});
            for (profile.native_packages.items, 0..) |pkg, idx| {
                print("  [{}/{}] Installing {s}... ", .{ idx + 1, profile.native_packages.items.len, pkg });

                const system_info = system.detectSystem(allocator) catch continue;
                defer allocator.free(system_info.version_managers);

                const cmd_parts = buildCommand(allocator, system_info, .install, &[_][]const u8{pkg}) catch {
                    print("❌ Failed\n", .{});
                    failed_count += 1;
                    continue;
                };
                defer allocator.free(cmd_parts);

                const result = std.process.Child.run(.{
                    .allocator = allocator,
                    .argv = cmd_parts,
                }) catch {
                    print("❌ Failed\n", .{});
                    failed_count += 1;
                    continue;
                };
                defer allocator.free(result.stdout);
                defer allocator.free(result.stderr);

                if (result.term.Exited == 0) {
                    print("✅ Success\n", .{});
                    installed_count += 1;
                } else {
                    print("❌ Failed\n", .{});
                    failed_count += 1;
                }
            }
        }
    }

    // Install Flatpak packages
    if (install_all or install_flatpak) {
        if (profile.flatpak_packages.items.len > 0) {
            print("\n🏪 Installing {} Flatpak packages...\n", .{profile.flatpak_packages.items.len});
            for (profile.flatpak_packages.items, 0..) |pkg, idx| {
                print("  [{}/{}] Installing {s}... ", .{ idx + 1, profile.flatpak_packages.items.len, pkg });

                const result = std.process.Child.run(.{
                    .allocator = allocator,
                    .argv = &[_][]const u8{ "flatpak", "install", "-y", pkg },
                }) catch {
                    print("❌ Failed\n", .{});
                    failed_count += 1;
                    continue;
                };
                defer allocator.free(result.stdout);
                defer allocator.free(result.stderr);

                if (result.term.Exited == 0) {
                    print("✅ Success\n", .{});
                    installed_count += 1;
                } else {
                    print("❌ Failed\n", .{});
                    failed_count += 1;
                }
            }
        }
    }

    // Install AppImage packages (just show info for now)
    if (install_all or install_appimage) {
        if (profile.appimage_packages.items.len > 0) {
            print("\n🎯 AppImage packages found ({}):\n", .{profile.appimage_packages.items.len});
            for (profile.appimage_packages.items) |pkg| {
                print("  • {s} (manual download required)\n", .{pkg});
            }
        }
    }

    print("\n✅ Batch installation complete!\n", .{});
    print("📊 Summary: {} installed, {} failed\n", .{ installed_count, failed_count });
}

pub fn unlockPackageManager(allocator: Allocator, system_info: SystemInfo) !void {
    print("🔓 Unlocking package manager for {s}...\n", .{system_info.distro.toString()});

    const lock_files = switch (system_info.package_manager) {
        .pacman, .yay, .paru => &[_][]const u8{"/var/lib/pacman/db.lck"},
        .apt => &[_][]const u8{
            "/var/lib/dpkg/lock",
            "/var/lib/dpkg/lock-frontend",
            "/var/lib/apt/lists/lock",
        },
        .dnf => &[_][]const u8{"/var/run/dnf.pid"},
        else => {
            print("⚠️  No known lock files for {s}\n", .{system_info.package_manager.toString()});
            return;
        },
    };

    var found_any = false;
    for (lock_files) |lock_file| {
        // Check if file exists
        std.fs.accessAbsolute(lock_file, .{}) catch {
            continue;
        };

        found_any = true;
        print("🔍 Found lock file: {s}\n", .{lock_file});
        print("🚀 Removing: sudo rm {s}\n", .{lock_file});

        const result = std.process.Child.run(.{
            .allocator = allocator,
            .argv = &[_][]const u8{ "sudo", "rm", lock_file },
        }) catch |err| {
            print("❌ Failed to run rm command: {}\n", .{err});
            continue;
        };
        defer allocator.free(result.stdout);
        defer allocator.free(result.stderr);

        if (result.term.Exited == 0) {
            print("✅ Successfully removed {s}\n", .{lock_file});
        } else {
            print("❌ Failed to remove {s} (exit code: {})\n", .{ lock_file, result.term.Exited });
            if (result.stderr.len > 0) {
                print("   Error: {s}", .{result.stderr});
            }
        }
    }

    if (!found_any) {
        print("✅ No lock files found. System is already unlocked!\n", .{});
    } else {
        print("\n✨ Unlock operation complete.\n", .{});
    }
}

pub fn performInteractiveSearch(allocator: Allocator, system_info: SystemInfo, search_term: []const u8) !void {
    print("\n", .{});

    // First get search results without showing them yet
    var search_results = ArrayList(PackageMatch){};
    defer {
        for (search_results.items) |pkg| {
            allocator.free(pkg.name);
            allocator.free(pkg.id);
            allocator.free(pkg.description);
        }
        search_results.deinit(allocator);
    }

    // Search native packages first
    if (system_info.package_manager == .yay or system_info.package_manager == .paru) {
        const native_results = try searchNativePackages(allocator, system_info, search_term);
        defer native_results.deinit(allocator);

        for (native_results.packages) |pkg| {
            try search_results.append(allocator, PackageMatch{
                .name = try allocator.dupe(u8, pkg.name),
                .source = .native,
                .id = try allocator.dupe(u8, pkg.id),
                .description = try allocator.dupe(u8, pkg.description),
            });
        }
    }

    if (search_results.items.len == 0) {
        print("❌ No packages found for '{s}'\n", .{search_term});
        return;
    }

    // Display results with numbers
    print("🏠 Found {} packages:\n", .{search_results.items.len});
    for (search_results.items, 0..) |pkg, i| {
        print("{} {s}\n", .{ i + 1, pkg.id });
        if (pkg.description.len > 0) {
            print("    {s}\n", .{pkg.description});
        }
    }

    // Get user selection
    print("\n==> Packages to install (eg: 1 2 3, 1-3 or ^4)\n==> ", .{});

    var buf: [256]u8 = undefined;
    const stdin = std.fs.File.stdin();
    const bytes_read = stdin.read(buf[0..]) catch {
        print("⏹️  Installation cancelled.\n", .{});
        return;
    };

    if (bytes_read > 0) {
        const input = buf[0..bytes_read];
        const trimmed = std.mem.trim(u8, input, " \t\r\n");

        if (trimmed.len == 0 or std.mem.eql(u8, trimmed, "^C")) {
            print("⏹️  Installation cancelled.\n", .{});
            return;
        }

        var selected_packages = try parseSelection(allocator, trimmed, search_results.items);
        defer selected_packages.deinit(allocator);

        if (selected_packages.items.len == 0) {
            print("❌ No valid packages selected\n", .{});
            return;
        }

        // Install selected packages
        print("\n🚀 Installing {} packages...\n", .{selected_packages.items.len});
        for (selected_packages.items) |pkg_name| {
            print("Installing {s}...\n", .{pkg_name});

            const cmd_parts = try buildCommand(allocator, system_info, .install, &[_][]const u8{pkg_name});
            defer allocator.free(cmd_parts);

            var child = std.process.Child.init(cmd_parts, allocator);
            child.stdout_behavior = .Inherit;
            child.stderr_behavior = .Inherit;
            _ = child.spawnAndWait() catch |err| {
                print("❌ Failed to install {s}: {}\n", .{ pkg_name, err });
                continue;
            };
        }
    }
}

fn searchNativePackages(allocator: Allocator, system_info: SystemInfo, search_term: []const u8) !SearchResult {
    const cmd_parts = try buildCommand(allocator, system_info, .search, &[_][]const u8{search_term});
    defer allocator.free(cmd_parts);

    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = cmd_parts,
        .max_output_bytes = 50 * 1024 * 1024,
    }) catch {
        return SearchResult{ .packages = &[_]PackageMatch{}, .total_count = 0 };
    };

    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    switch (result.term) {
        .Exited => |code| {
            if (code != 0) {
                return SearchResult{ .packages = &[_]PackageMatch{}, .total_count = 0 };
            }
        },
        else => {
            return SearchResult{ .packages = &[_]PackageMatch{}, .total_count = 0 };
        },
    }

    return parseYayOutput(allocator, result.stdout);
}

fn parseYayOutput(allocator: Allocator, output: []const u8) !SearchResult {
    var packages = ArrayList(PackageMatch){};
    var lines = std.mem.splitSequence(u8, output, "\n");

    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r\n");
        if (trimmed.len == 0) continue;

        // Parse yay output format: "repo/package-name version (votes popularity)"
        // Only match lines that start with known repository prefixes to avoid false matches
        if (std.mem.startsWith(u8, trimmed, "aur/") or std.mem.startsWith(u8, trimmed, "extra/") or
            std.mem.startsWith(u8, trimmed, "core/") or std.mem.startsWith(u8, trimmed, "community/") or
            std.mem.startsWith(u8, trimmed, "multilib/") or std.mem.startsWith(u8, trimmed, "cachyos/") or
            std.mem.startsWith(u8, trimmed, "chaotic-aur/"))
        {

            // Extract package name
            const slash_pos = std.mem.indexOf(u8, trimmed, "/") orelse continue;
            const space_pos = std.mem.indexOf(u8, trimmed[slash_pos + 1 ..], " ") orelse (trimmed.len - slash_pos - 1);

            const repo = trimmed[0..slash_pos];
            const pkg_name = trimmed[slash_pos + 1 .. slash_pos + 1 + space_pos];
            const full_name = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ repo, pkg_name });

            // Get description from next line if available
            var description: []const u8 = "";
            if (lines.next()) |desc_line| {
                const desc_trimmed = std.mem.trim(u8, desc_line, " \t\r\n");
                if (desc_trimmed.len > 0 and !std.mem.startsWith(u8, desc_trimmed, "aur/") and
                    !std.mem.startsWith(u8, desc_trimmed, "extra/") and !std.mem.startsWith(u8, desc_trimmed, "core/") and
                    !std.mem.startsWith(u8, desc_trimmed, "community/") and !std.mem.startsWith(u8, desc_trimmed, "multilib/") and
                    !std.mem.startsWith(u8, desc_trimmed, "cachyos/") and !std.mem.startsWith(u8, desc_trimmed, "chaotic-aur/") and
                    std.mem.indexOf(u8, desc_trimmed, "/") == null)
                {
                    description = try allocator.dupe(u8, desc_trimmed);
                } else {
                    // Put the line back by creating a new iterator from remaining content
                    const remaining = desc_line;
                    lines = std.mem.splitSequence(u8, remaining, "\n");
                }
            }

            if (description.len == 0) {
                description = try allocator.dupe(u8, "");
            }

            try packages.append(allocator, PackageMatch{
                .name = try allocator.dupe(u8, pkg_name),
                .source = .native,
                .id = full_name,
                .description = description,
            });
        }
    }

    const result_packages = try packages.toOwnedSlice(allocator);
    return SearchResult{
        .packages = result_packages,
        .total_count = result_packages.len,
    };
}

fn parseSelection(allocator: Allocator, input: []const u8, packages: []PackageMatch) !ArrayList([]const u8) {
    var selected = ArrayList([]const u8){};

    // Handle "^" prefix (invert selection)
    if (std.mem.startsWith(u8, input, "^")) {
        const exclude_input = input[1..];
        var excluded_indices = try parseIndices(allocator, exclude_input, packages.len);
        defer excluded_indices.deinit(allocator);

        // Add all packages except excluded ones
        for (packages, 0..) |pkg, i| {
            var should_exclude = false;
            for (excluded_indices.items) |excluded_idx| {
                if (i + 1 == excluded_idx) {
                    should_exclude = true;
                    break;
                }
            }
            if (!should_exclude) {
                try selected.append(allocator, try allocator.dupe(u8, pkg.name));
            }
        }
    } else {
        // Parse normal selection
        var indices = try parseIndices(allocator, input, packages.len);
        defer indices.deinit(allocator);

        for (indices.items) |idx| {
            if (idx > 0 and idx <= packages.len) {
                try selected.append(allocator, try allocator.dupe(u8, packages[idx - 1].name));
            }
        }
    }

    return selected;
}

fn parseIndices(allocator: Allocator, input: []const u8, max_packages: usize) !ArrayList(usize) {
    var indices = ArrayList(usize){};
    var parts = std.mem.splitSequence(u8, input, " ");

    while (parts.next()) |part| {
        const trimmed = std.mem.trim(u8, part, " \t");
        if (trimmed.len == 0) continue;

        if (std.mem.indexOf(u8, trimmed, "-")) |dash_pos| {
            // Handle range like "1-3"
            const start_str = trimmed[0..dash_pos];
            const end_str = trimmed[dash_pos + 1 ..];

            const start = std.fmt.parseInt(usize, start_str, 10) catch continue;
            const end = std.fmt.parseInt(usize, end_str, 10) catch continue;

            if (start <= end and start > 0 and end <= max_packages) {
                var i = start;
                while (i <= end) : (i += 1) {
                    try indices.append(allocator, i);
                }
            }
        } else {
            // Handle single number
            const num = std.fmt.parseInt(usize, trimmed, 10) catch continue;
            if (num > 0 and num <= max_packages) {
                try indices.append(allocator, num);
            }
        }
    }

    return indices;
}
pub const PrunablePackage = struct {
    name: []const u8,
    version: []const u8,
    description: []const u8,
    repository: []const u8,
    optional_for: []const u8,

    pub fn deinit(self: @This(), allocator: Allocator) void {
        allocator.free(self.name);
        if (self.version.len > 0) allocator.free(self.version);
        if (self.description.len > 0) allocator.free(self.description);
        if (self.repository.len > 0) allocator.free(self.repository);
        if (self.optional_for.len > 0) allocator.free(self.optional_for);
    }
};

pub fn getPrunablePackages(allocator: Allocator, system_info: SystemInfo) !ArrayList(PrunablePackage) {
    var cmd_parts = ArrayList([]const u8){ .items = &[_][]const u8{}, .capacity = 0 };
    defer cmd_parts.deinit(allocator);

    // Build the command specific to the package manager and request details if possible
    switch (system_info.package_manager) {
        .yay, .paru, .pacman => {
            try cmd_parts.append(allocator, system_info.package_manager.toString());
            try cmd_parts.append(allocator, "-Qdti");
        },
        .zypper => {
            try cmd_parts.append(allocator, "sudo");
            try cmd_parts.append(allocator, "zypper");
            try cmd_parts.append(allocator, "packages");
            try cmd_parts.append(allocator, "--unneeded");
        },
        .apt => {
            try cmd_parts.append(allocator, "apt-mark");
            try cmd_parts.append(allocator, "showauto");
        },
        else => {
            const basic_parts = try buildCommand(allocator, system_info, .prunable, &[_][]const u8{});
            for (basic_parts) |part| try cmd_parts.append(allocator, part);
            allocator.free(basic_parts);
        }
    }

    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = cmd_parts.items,
        .max_output_bytes = 10 * 1024 * 1024,
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    var packages = ArrayList(PrunablePackage){ .items = &[_]PrunablePackage{}, .capacity = 0 };
    if (result.term.Exited != 0) return packages;

    if (system_info.package_manager == .yay or system_info.package_manager == .paru or system_info.package_manager == .pacman) {
        // Parse pacman -Qdti output
        var lines = std.mem.splitScalar(u8, result.stdout, '\n');
        var current_pkg = PrunablePackage{ .name = "", .version = "", .description = "", .repository = "", .optional_for = "" };
        var has_current = false;

        while (lines.next()) |raw_line| {
            const trimmed = std.mem.trim(u8, raw_line, " \t\r\n");
            if (trimmed.len == 0) {
                if (has_current) {
                    try packages.append(allocator, current_pkg);
                    current_pkg = PrunablePackage{ .name = "", .version = "", .description = "", .repository = "", .optional_for = "" };
                    has_current = false;
                }
                continue;
            }

            if (std.mem.indexOf(u8, trimmed, ":")) |colon_idx| {
                const key = std.mem.trim(u8, trimmed[0..colon_idx], " ");
                const value = std.mem.trim(u8, trimmed[colon_idx + 1 ..], " ");

                if (std.mem.eql(u8, key, "Name")) {
                    current_pkg.name = try allocator.dupe(u8, value);
                    has_current = true;
                } else if (std.mem.eql(u8, key, "Version")) {
                    current_pkg.version = try allocator.dupe(u8, value);
                } else if (std.mem.eql(u8, key, "Description")) {
                    current_pkg.description = try allocator.dupe(u8, value);
                } else if (std.mem.eql(u8, key, "Installed From") or std.mem.eql(u8, key, "Repository")) {
                    current_pkg.repository = try std.fmt.allocPrint(allocator, "[{s}]", .{value});
                } else if (std.mem.eql(u8, key, "Optional For")) {
                    if (!std.mem.eql(u8, value, "None")) {
                        current_pkg.optional_for = try allocator.dupe(u8, value);
                    }
                }
            }
        }
        if (has_current) {
            try packages.append(allocator, current_pkg);
        }
    } else {
        // Fallback for other package managers
        var lines = std.mem.splitScalar(u8, result.stdout, '\n');
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r\n");
            if (trimmed.len == 0) continue;
            if (std.mem.eql(u8, system_info.package_manager.toString(), "apt") and std.mem.startsWith(u8, trimmed, "Listing...")) continue;

            const pkg_name = switch (system_info.package_manager) {
                .apt => blk: {
                    if (std.mem.indexOf(u8, trimmed, "/")) |idx| break :blk trimmed[0..idx];
                    break :blk trimmed;
                },
                .zypper => blk: {
                    var parts = std.mem.splitScalar(u8, trimmed, '|');
                    _ = parts.next() orelse break :blk trimmed;
                    const zypper_name = parts.next() orelse break :blk trimmed;
                    break :blk std.mem.trim(u8, zypper_name, " ");
                },
                else => trimmed,
            };

            // Avoid common header lines in zypper
            if (std.mem.eql(u8, pkg_name, "Name") or std.mem.eql(u8, pkg_name, "---") or std.mem.eql(u8, pkg_name, "S")) continue;

            if (pkg_name.len > 0) {
                try packages.append(allocator, PrunablePackage{
                    .name = try allocator.dupe(u8, pkg_name),
                    .version = try allocator.dupe(u8, ""),
                    .description = try allocator.dupe(u8, ""),
                    .repository = try allocator.dupe(u8, ""),
                    .optional_for = try allocator.dupe(u8, ""),
                });
            }
        }
    }

    return packages;
}

pub fn performPruneFlow(allocator: Allocator, system_info: SystemInfo) !void {
    print("🔍 Identifying unused packages...\n", .{});
    var prunable = try getPrunablePackages(allocator, system_info);
    defer {
        for (prunable.items) |pkg| pkg.deinit(allocator);
        prunable.deinit(allocator);
    }

    if (prunable.items.len == 0) {
        print("✅ No unused packages found. Your system is already lean!\n", .{});
        return;
    }

    print("\n🧹 Found {} unused packages:\n", .{prunable.items.len});
    for (prunable.items) |pkg| {
        if (pkg.description.len > 0 and pkg.repository.len > 0) {
            print("\n  • \x1b[1m{s}\x1b[0m {s} \x1b[38;5;242m{s}\x1b[0m\n      └─ {s}\n", .{pkg.name, pkg.repository, pkg.version, pkg.description});
        } else if (pkg.description.len > 0) {
            print("\n  • \x1b[1m{s}\x1b[0m \x1b[38;5;242m{s}\x1b[0m\n      └─ {s}\n", .{pkg.name, pkg.version, pkg.description});
        } else {
            print("  • \x1b[1m{s}\x1b[0m\n", .{pkg.name});
        }

        if (pkg.optional_for.len > 0) {
            print("      💡 \x1b[33mOptional requirement for:\x1b[0m {s}\n", .{pkg.optional_for});
        }
    }

    print("\n🤔 Prune these packages? [y/N]: ", .{});
    var buf: [256]u8 = undefined;
    const stdin = std.fs.File.stdin();
    const bytes_read = try stdin.read(buf[0..]);
    if (bytes_read > 0) {
        const input = std.mem.trim(u8, buf[0..bytes_read], " \t\r\n");
        if (input.len > 0 and (input[0] == 'y' or input[0] == 'Y')) {
            print("🚀 Pruning packages...\n", .{});
            
            var names = ArrayList([]const u8){ .items = &[_][]const u8{}, .capacity = 0 };
            defer names.deinit(allocator);
            for (prunable.items) |pkg| {
                try names.append(allocator, pkg.name);
            }

            const cmd_parts = try buildCommand(allocator, system_info, .remove, names.items);
            defer allocator.free(cmd_parts);

            var child = std.process.Child.init(cmd_parts, allocator);
            child.stdout_behavior = .Inherit;
            child.stderr_behavior = .Inherit;
            _ = try child.spawnAndWait();
            
            print("\n✅ System cleaned successfully!\n", .{});
        } else {
            print("⏹️  Prune cancelled.\n", .{});
        }
    }
}
