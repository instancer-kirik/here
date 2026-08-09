const std = @import("std");
const print = std.debug.print;
const build_options = @import("build_options");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const appimage = @import("appimage.zig");
const appman = @import("appman_integration.zig");
const migration = @import("migration.zig");
const recovery = @import("recovery.zig");
const interactive_import = @import("import/interactive.zig");
const profile_parser = @import("import/parser.zig");

// Core modules
const system = @import("core/system.zig");
const cli = @import("core/cli.zig");
const packages = @import("core/packages.zig");
const profiles = @import("core/profiles.zig");
const audit = @import("audit.zig");

// Type aliases for compatibility
const SystemInfo = system.SystemInfo;
const PackageSource = system.PackageSource;
const Command = cli.Command;

fn searchAppImage(allocator: Allocator, package_name: []const u8) !void {
    // Try AppMan first (production-ready with 2500+ apps)
    var appman_manager = appman.AppManManager.init(allocator) catch |err| {
        print("⚠️  AppMan initialization failed: {}, falling back to basic AppImage search\n", .{err});

        // Fallback to basic AppImage search
        var installer = appimage.AppImageInstaller.init(allocator) catch |fallback_err| {
            print("❌ Failed to initialize AppImage installer: {}\n", .{fallback_err});
            return;
        };
        defer installer.deinit();

        installer.searchAppImageHub(package_name) catch |search_err| {
            print("❌ AppImage search failed: {}\n", .{search_err});
        };
        return;
    };
    defer appman_manager.deinit();

    print("🔍 Searching with AppMan (2500+ applications)...\n", .{});
    const results = appman_manager.search(package_name) catch |err| {
        print("❌ AppMan search failed: {}, trying fallback\n", .{err});

        // Fallback to basic AppImage search
        var installer = appimage.AppImageInstaller.init(allocator) catch |fallback_err| {
            print("❌ Failed to initialize AppImage installer: {}\n", .{fallback_err});
            return;
        };
        defer installer.deinit();

        installer.searchAppImageHub(package_name) catch |search_err| {
            print("❌ AppImage search failed: {}\n", .{search_err});
        };
        return;
    };

    if (results.len > 0) {
        print("📦 Found {} results:\n", .{results.len});
        for (results) |result| {
            print("  • {s} - {s}\n", .{ result.name, result.description });
            result.deinit(allocator);
        }
        allocator.free(results);
    } else {
        print("  No applications found for '{s}'\n", .{package_name});
    }
}

fn installAppImage(allocator: Allocator, package_name: []const u8) !bool {
    // Try AppMan first for production-ready installation
    var appman_manager = appman.AppManManager.init(allocator) catch |err| {
        print("⚠️  AppMan not available: {}, using fallback installer\n", .{err});

        // Fallback to basic AppImage installation
        var installer = appimage.AppImageInstaller.init(allocator) catch |fallback_err| {
            print("❌ Failed to initialize AppImage installer: {}\n", .{fallback_err});
            return false;
        };
        defer installer.deinit();

        return installer.install(package_name) catch |install_err| {
            print("❌ AppImage installation failed: {}\n", .{install_err});
            return false;
        };
    };
    defer appman_manager.deinit();

    print("🚀 Installing {s} via AppMan (production-ready)...\n", .{package_name});
    appman_manager.install(package_name) catch |err| {
        print("❌ AppMan installation failed: {}, trying fallback\n", .{err});

        // Fallback to basic AppImage installation
        var installer = appimage.AppImageInstaller.init(allocator) catch |fallback_err| {
            print("❌ Failed to initialize AppImage installer: {}\n", .{fallback_err});
            return false;
        };
        defer installer.deinit();

        return installer.install(package_name) catch |install_err| {
            print("❌ AppImage installation failed: {}\n", .{install_err});
            return false;
        };
    };

    return true;
}

const PackageProfile = struct {
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
        flatpak: [][]const u8,
        appimage: [][]const u8,
        version_managers: [][]const u8,
    };

    const ConfigData = struct {
        dotfiles: [][]const u8,
        xdg_config: [][]const u8,
        ssh_keys: bool = false,
        git_config: bool = false,
    };
};

fn exportProfile(allocator: Allocator, filename: ?[]const u8, include_config: bool) !void {
    const profile_name = filename orelse "here-profile.json";

    if (include_config) {
        print("📦 Creating package export profile with config data to '{s}'...\n", .{profile_name});
    } else {
        print("📦 Creating package export profile to '{s}'...\n", .{profile_name});
    }

    // Get current timestamp
    const timestamp = std.time.timestamp();
    const date_str = try std.fmt.allocPrint(allocator, "{d}", .{timestamp});
    defer allocator.free(date_str);

    // Detect system info
    const system_info = system.detectSystem(allocator) catch |err| {
        print("❌ Failed to detect system: {}\n", .{err});
        return;
    };
    defer allocator.free(system_info.version_managers);
    defer allocator.free(system_info.package_sources);

    // Get system details
    const uname_result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "uname", "-m" },
    }) catch {
        print("❌ Failed to get system architecture\n", .{});
        return;
    };
    defer allocator.free(uname_result.stdout);
    defer allocator.free(uname_result.stderr);

    const arch = std.mem.trim(u8, uname_result.stdout, " \n\r\t");

    const kernel_result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "uname", "-r" },
    }) catch {
        print("❌ Failed to get kernel version\n", .{});
        return;
    };
    defer allocator.free(kernel_result.stdout);
    defer allocator.free(kernel_result.stderr);

    const kernel = std.mem.trim(u8, kernel_result.stdout, " \n\r\t");

    // Collect installed packages
    var native_packages = std.ArrayList([]const u8){ .items = &[_][]const u8{}, .capacity = 0 };
    defer {
        for (native_packages.items) |pkg| allocator.free(pkg);
        native_packages.deinit(allocator);
    }

    var flatpak_packages = std.ArrayList([]const u8){ .items = &[_][]const u8{}, .capacity = 0 };
    defer {
        for (flatpak_packages.items) |pkg| allocator.free(pkg);
        flatpak_packages.deinit(allocator);
    }

    var appimage_packages = std.ArrayList([]const u8){ .items = &[_][]const u8{}, .capacity = 0 };
    defer {
        for (appimage_packages.items) |pkg| allocator.free(pkg);
        appimage_packages.deinit(allocator);
    }

    var vm_packages = std.ArrayList([]const u8){ .items = &[_][]const u8{}, .capacity = 0 };
    defer {
        for (vm_packages.items) |pkg| allocator.free(pkg);
        vm_packages.deinit(allocator);
    }

    // Config data collections (if needed)
    var dotfiles = std.ArrayList([]const u8){ .items = &[_][]const u8{}, .capacity = 0 };
    defer {
        for (dotfiles.items) |item| allocator.free(item);
        dotfiles.deinit(allocator);
    }

    var xdg_config = std.ArrayList([]const u8){ .items = &[_][]const u8{}, .capacity = 0 };
    defer {
        for (xdg_config.items) |item| allocator.free(item);
        xdg_config.deinit(allocator);
    }

    // Simple config detection
    var has_ssh_keys = false;
    var has_git_config = false;

    if (include_config) {
        // Get home directory
        const home_dir_path = std.process.getEnvVarOwned(allocator, "HOME") catch "/tmp";
        defer if (!std.mem.eql(u8, home_dir_path, "/tmp")) allocator.free(home_dir_path);
        var home_dir = std.fs.openDirAbsolute(home_dir_path, .{}) catch {
            print("⚠️  Could not access home directory\n", .{});
            return;
        };
        defer home_dir.close();

        // Collect common dotfiles
        const common_dotfiles = [_][]const u8{ ".bashrc", ".bash_profile", ".zshrc", ".zsh_profile", ".vimrc", ".tmux.conf", ".gitconfig", ".gitignore_global", ".xinitrc", ".xprofile", ".Xresources", ".profile" };

        for (common_dotfiles) |dotfile| {
            if (home_dir.access(dotfile, .{})) {
                const owned_name = try allocator.dupe(u8, dotfile);
                try dotfiles.append(allocator, owned_name);
            } else |_| {}
        }

        // Collect XDG config directories
        const config_dirs = [_][]const u8{ ".config/nvim", ".config/git", ".config/Code", ".config/alacritty", ".config/zsh", ".config/tmux", ".config/fontconfig", ".config/awesome", ".config/fish", ".config/starship.toml" };

        for (config_dirs) |config_path| {
            if (home_dir.access(config_path, .{})) {
                const owned_name = try allocator.dupe(u8, config_path);
                try xdg_config.append(allocator, owned_name);
            } else |_| {}
        }

        // Check for SSH and Git
        if (home_dir.access(".ssh", .{})) {
            has_ssh_keys = true;
        } else |_| {}

        if (home_dir.access(".gitconfig", .{})) {
            has_git_config = true;
        } else |_| {}
    }

    // Get native packages
    if (system.package_manager != .unknown) {
        collectNativePackages(allocator, system, &native_packages) catch |err| {
            print("⚠️  Failed to collect native packages: {}\n", .{err});
        };
    }

    // Get Flatpak packages
    for (system_info.package_sources) |source| {
        if (source == .flatpak) {
            collectFlatpakPackages(allocator, &flatpak_packages) catch |err| {
                print("⚠️  Failed to collect Flatpak packages: {}\n", .{err});
            };
        } else if (source == .appimage) {
            collectAppImagePackages(allocator, &appimage_packages) catch |err| {
                print("⚠️  Failed to collect AppImage packages: {}\n", .{err});
            };
        }
    }

    // Get version manager packages
    for (system.version_managers) |vm| {
        const vm_name = try std.fmt.allocPrint(allocator, "{s}", .{vm.toString()});
        try vm_packages.append(allocator, vm_name);
    }

    // Create profile JSON manually (simple approach)
    const profile_file = std.fs.cwd().createFile(profile_name, .{}) catch |err| {
        print("❌ Failed to create profile file: {}\n", .{err});
        return;
    };
    defer profile_file.close();

    // Build JSON string in memory
    var json_content = std.ArrayList(u8){ .items = &[_]u8{}, .capacity = 0 };
    defer json_content.deinit(allocator);

    try json_content.appendSlice(allocator, "{\n");
    const created_line = try std.fmt.allocPrint(allocator, "  \"created\": \"{s}\",\n", .{date_str});
    defer allocator.free(created_line);
    try json_content.appendSlice(allocator, created_line);

    try json_content.appendSlice(allocator, "  \"system\": {\n");
    const distro_line = try std.fmt.allocPrint(allocator, "    \"distro\": \"{s}\",\n", .{system.distro.toString()});
    defer allocator.free(distro_line);
    try json_content.appendSlice(allocator, distro_line);

    const pkg_mgr_line = try std.fmt.allocPrint(allocator, "    \"package_manager\": \"{s}\",\n", .{system.package_manager.toString()});
    defer allocator.free(pkg_mgr_line);
    try json_content.appendSlice(allocator, pkg_mgr_line);

    const arch_line = try std.fmt.allocPrint(allocator, "    \"arch\": \"{s}\",\n", .{arch});
    defer allocator.free(arch_line);
    try json_content.appendSlice(allocator, arch_line);

    const kernel_line = try std.fmt.allocPrint(allocator, "    \"kernel\": \"{s}\"\n", .{kernel});
    defer allocator.free(kernel_line);
    try json_content.appendSlice(allocator, kernel_line);

    try json_content.appendSlice(allocator, "  },\n");
    try json_content.appendSlice(allocator, "  \"packages\": {\n");

    // Native packages
    try json_content.appendSlice(allocator, "    \"native\": [\n");
    for (native_packages.items, 0..) |pkg, i| {
        if (i > 0) try json_content.appendSlice(allocator, ",\n");
        const pkg_line = try std.fmt.allocPrint(allocator, "      \"{s}\"", .{pkg});
        defer allocator.free(pkg_line);
        try json_content.appendSlice(allocator, pkg_line);
    }
    try json_content.appendSlice(allocator, "\n    ],\n");

    // Flatpak packages
    try json_content.appendSlice(allocator, "    \"flatpak\": [\n");
    for (flatpak_packages.items, 0..) |pkg, i| {
        if (i > 0) try json_content.appendSlice(allocator, ",\n");
        const pkg_line = try std.fmt.allocPrint(allocator, "      \"{s}\"", .{pkg});
        defer allocator.free(pkg_line);
        try json_content.appendSlice(allocator, pkg_line);
    }
    try json_content.appendSlice(allocator, "\n    ],\n");

    // AppImage packages
    try json_content.appendSlice(allocator, "    \"appimage\": [\n");
    for (appimage_packages.items, 0..) |pkg, i| {
        if (i > 0) try json_content.appendSlice(allocator, ",\n");
        const pkg_line = try std.fmt.allocPrint(allocator, "      \"{s}\"", .{pkg});
        defer allocator.free(pkg_line);
        try json_content.appendSlice(allocator, pkg_line);
    }
    try json_content.appendSlice(allocator, "\n    ],\n");

    // Version managers
    try json_content.appendSlice(allocator, "    \"version_managers\": [\n");
    for (vm_packages.items, 0..) |pkg, i| {
        if (i > 0) try json_content.appendSlice(allocator, ",\n");
        const pkg_line = try std.fmt.allocPrint(allocator, "      \"{s}\"", .{pkg});
        defer allocator.free(pkg_line);
        try json_content.appendSlice(allocator, pkg_line);
    }
    try json_content.appendSlice(allocator, "\n    ]\n");
    try json_content.appendSlice(allocator, "  },\n");

    // Config
    try json_content.appendSlice(allocator, "  \"config\": {\n");
    try json_content.appendSlice(allocator, "    \"dotfiles\": [\n");
    for (dotfiles.items, 0..) |item, i| {
        if (i > 0) try json_content.appendSlice(allocator, ",\n");
        const item_line = try std.fmt.allocPrint(allocator, "      \"{s}\"", .{item});
        defer allocator.free(item_line);
        try json_content.appendSlice(allocator, item_line);
    }
    try json_content.appendSlice(allocator, "\n    ],\n");

    try json_content.appendSlice(allocator, "    \"xdg_config\": [\n");
    for (xdg_config.items, 0..) |item, i| {
        if (i > 0) try json_content.appendSlice(allocator, ",\n");
        const item_line = try std.fmt.allocPrint(allocator, "      \"{s}\"", .{item});
        defer allocator.free(item_line);
        try json_content.appendSlice(allocator, item_line);
    }
    try json_content.appendSlice(allocator, "\n    ]\n");
    try json_content.appendSlice(allocator, "  }\n");
    try json_content.appendSlice(allocator, "}\n");

    // Write all content to file at once
    try profile_file.writeAll(json_content.items);

    print("✅ Profile export created successfully!\n", .{});
    print("📊 Summary:\n", .{});
    print("  • Native packages: {}\n", .{native_packages.items.len});
    print("  • Flatpak packages: {}\n", .{flatpak_packages.items.len});
    print("  • AppImage packages: {}\n", .{appimage_packages.items.len});
    print("  • Version managers: {}\n", .{vm_packages.items.len});

    if (include_config) {
        print("  • Dotfiles: {}\n", .{dotfiles.items.len});
        print("  • XDG config dirs: {}\n", .{xdg_config.items.len});
        print("  • SSH keys: {s}\n", .{if (has_ssh_keys) "found" else "none"});
        print("  • Git config: {s}\n", .{if (has_git_config) "found" else "none"});
    }

    print("💡 Import on new system with: here import {s}\n", .{profile_name});
}

fn collectNativePackages(allocator: Allocator, system_info: SystemInfo, package_list: *std.ArrayList([]const u8)) !void {
    const cmd = switch (system_info.package_manager) {
        .pacman, .yay, .paru => &[_][]const u8{ "pacman", "-Qe" },
        .apt => &[_][]const u8{ "apt", "list", "--installed" },
        .dnf => &[_][]const u8{ "dnf", "list", "installed" },
        .zypper => &[_][]const u8{ "zypper", "search", "--installed-only" },
        else => return,
    };

    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = cmd,
    }) catch return;

    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    if (result.term.Exited != 0) return;

    var lines = std.mem.splitScalar(u8, result.stdout, '\n');
    while (lines.next()) |line| {
        if (line.len == 0) continue;

        // Parse package name based on package manager format
        const pkg_name = switch (system.package_manager) {
            .pacman, .yay, .paru => blk: {
                var parts = std.mem.splitScalar(u8, line, ' ');
                break :blk parts.next() orelse continue;
            },
            .apt => blk: {
                if (std.mem.indexOf(u8, line, "/")) |idx| {
                    break :blk line[0..idx];
                }
                break :blk line;
            },
            else => line,
        };

        if (pkg_name.len > 0) {
            const owned_name = try allocator.dupe(u8, pkg_name);
            try package_list.append(allocator, owned_name);
        }
    }
}

fn collectFlatpakPackages(allocator: Allocator, package_list: *std.ArrayList([]const u8)) !void {
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "flatpak", "list", "--app", "--columns=application" },
    }) catch return;

    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    if (result.term.Exited != 0) return;

    var lines = std.mem.splitScalar(u8, result.stdout, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \n\r\t");
        if (trimmed.len == 0 or std.mem.eql(u8, trimmed, "Application ID")) continue;

        const owned_name = try allocator.dupe(u8, trimmed);
        try package_list.append(allocator, owned_name);
    }
}

fn collectAppImagePackages(allocator: Allocator, package_list: *std.ArrayList([]const u8)) !void {
    // Try AppMan first
    var appman_manager = appman.AppManManager.init(allocator) catch {
        // If AppMan fails, just scan filesystem
        return collectAppImageFromFilesystem(allocator, packages);
    };
    defer appman_manager.deinit();

    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ appman_manager.config.appman_path, "-f" },
    }) catch {
        return collectAppImageFromFilesystem(allocator, packages);
    };

    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    var appman_found = false;
    if (result.term.Exited == 0) {
        var lines = std.mem.splitScalar(u8, result.stdout, '\n');
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \n\r\t");
            if (trimmed.len == 0) continue;

            // Extract app name from AppMan output
            if (std.mem.indexOf(u8, trimmed, " : ")) |idx| {
                const app_name = std.mem.trim(u8, trimmed[0..idx], " \t◆");
                if (app_name.len > 0) {
                    const owned_name = try allocator.dupe(u8, app_name);
                    try package_list.append(allocator, owned_name);
                    appman_found = true;
                }
            }
        }
    }

    // Also scan filesystem for AppImages not managed by AppMan
    collectAppImageFromFilesystem(allocator, package_list) catch {};
}

fn collectAppImageFromFilesystem(allocator: Allocator, package_list: *std.ArrayList([]const u8)) !void {
    const home_dir = std.posix.getenv("HOME") orelse return;

    // Common AppImage locations
    const search_paths = [_][]const u8{
        "Applications",
        ".local/bin",
        "AppImages",
        "Downloads",
        "Desktop",
        "bin",
    };

    for (search_paths) |subdir| {
        const full_path = std.fmt.allocPrint(allocator, "{s}/{s}", .{ home_dir, subdir }) catch continue;
        defer allocator.free(full_path);

        scanDirectoryForAppImages(allocator, full_path, packages) catch {};
    }

    // Also scan /usr/local/bin and /opt
    scanDirectoryForAppImages(allocator, "/usr/local/bin", package_list) catch {};
    scanDirectoryForAppImages(allocator, "/opt", package_list) catch {};
}

fn scanDirectoryForAppImages(allocator: Allocator, dir_path: []const u8, package_list: *std.ArrayList([]const u8)) !void {
    var dir = std.fs.openDirAbsolute(dir_path, .{ .iterate = true }) catch return;
    defer dir.close();

    var iterator = dir.iterate();
    while (try iterator.next()) |entry| {
        if (entry.kind != .file) continue;

        const name = entry.name;
        if (std.mem.endsWith(u8, name, ".AppImage") or std.mem.endsWith(u8, name, ".appimage")) {
            // Extract base name without .AppImage extension
            const base_name = if (std.mem.endsWith(u8, name, ".AppImage"))
                name[0 .. name.len - 9]
            else
                name[0 .. name.len - 9]; // .appimage

            // Check if already added to avoid duplicates
            var already_added = false;
            for (packages.items) |existing| {
                if (std.mem.eql(u8, existing, base_name)) {
                    already_added = true;
                    break;
                }
            }

            if (!already_added) {
                const owned_name = try allocator.dupe(u8, base_name);
                try package_list.append(allocator, owned_name);
            }
        }
    }
}

fn restoreProfile(allocator: Allocator, filename: []const u8) !void {
    print("📥 Restoring package profile from '{s}'...\n", .{filename});

    const profile_file = std.fs.cwd().openFile(filename, .{}) catch |err| {
        print("❌ Failed to open profile file: {}\n", .{err});
        return;
    };
    defer profile_file.close();

    const file_size = try profile_file.getEndPos();
    const contents = try allocator.alloc(u8, file_size);
    defer allocator.free(contents);
    _ = try profile_file.readAll(contents);

    print("📋 Profile contents preview:\n", .{});

    // Simple JSON parsing for preview (show first few lines)
    var lines = std.mem.splitScalar(u8, contents, '\n');
    var line_count: u32 = 0;
    while (lines.next()) |line| {
        if (line_count >= 10) {
            print("  ... (truncated)\n", .{});
            break;
        }
        print("  {s}\n", .{line});
        line_count += 1;
    }

    print("\n⚠️  Profile import functionality is ready for implementation!\n", .{});
    print("💡 This would install packages based on the export profile.\n", .{});
    print("🚀 Full import feature coming in next update.\n", .{});

    // TODO: Implement actual JSON parsing and package installation
    // For now, just show what would be installed

    print("✅ Profile analysis complete.\n", .{});
}

fn importProfile(allocator: Allocator, filename: []const u8) !void {
    print("📥 Importing package profile from '{s}'...\n", .{filename});

    const profile_file = std.fs.cwd().openFile(filename, .{}) catch |err| {
        print("❌ Failed to open profile file: {}\n", .{err});
        return;
    };
    defer profile_file.close();

    const file_size = try profile_file.getEndPos();
    const contents = try allocator.alloc(u8, file_size);
    defer allocator.free(contents);
    _ = try profile_file.readAll(contents);

    print("📋 Analyzing profile structure...\n", .{});

    // Use the new parser for cleaner code
    var parser = profile_parser.ProfileParser.init(allocator);
    var profile_info = parser.parseProfile(contents) catch |err| {
        print("❌ Failed to parse profile: {}\n", .{err});
        return;
    };
    defer profile_info.deinit(allocator);

    // Show detailed analysis
    print("\n🖥️  Source System:\n", .{});
    print("  • Distribution: {s}\n", .{profile_info.system_distro});
    print("  • Package Manager: {s}\n", .{profile_info.system_package_manager});
    print("  • Architecture: {s}\n", .{profile_info.system_arch});

    print("\n📊 Package Summary:\n", .{});
    print("  • Native packages: {}\n", .{profile_info.native_packages.items.len});
    print("  • Flatpak packages: {}\n", .{profile_info.flatpak_packages.items.len});
    print("  • AppImage packages: {}\n", .{profile_info.appimage_packages.items.len});
    print("  • Total packages: {}\n", .{profile_info.totalPackages()});

    if (profile_info.totalPackages() == 0) {
        print("⚠️  No packages found in profile.\n", .{});
        return;
    }

    // Show some example packages
    print("\n📦 Sample packages to install:\n", .{});

    if (profile_info.native_packages.items.len > 0) {
        print("  Native packages (showing first 10):\n", .{});
        const max_show = @min(10, profile_info.native_packages.items.len);
        for (profile_info.native_packages.items[0..max_show]) |pkg| {
            print("    • {s}\n", .{pkg});
        }
        if (profile_info.native_packages.items.len > 10) {
            print("    ... and {} more\n", .{profile_info.native_packages.items.len - 10});
        }
    }

    // Interactive TUI option
    print("\n🎯 Interactive Import Available!\n", .{});
    print("  • Run with --interactive for TUI selection\n", .{});
    print("  • Example: here import --interactive {s}\n", .{filename});

    // Simple installation options
    print("\n💡 Quick Install Options:\n", .{});
    if (profile_info.native_packages.items.len > 0) {
        print("  • Native packages: here install-batch <native-packages>\n", .{});
    }
    if (profile_info.flatpak_packages.items.len > 0) {
        print("  • Flatpak packages: here install-batch <flatpak-packages>\n", .{});
    }
    if (profile_info.appimage_packages.items.len > 0) {
        print("  • AppImage packages: here install-batch <appimage-packages>\n", .{});
    }

    print("✅ Profile analysis complete!\n", .{});
}

fn searchFlatpak(allocator: Allocator, package_name: []const u8) !void {
    print("📦 Flatpak results:\n", .{});
    var cmd_parts = ArrayList([]const u8){ .items = &[_][]const u8{}, .capacity = 0 };
    defer cmd_parts.deinit(allocator);

    try cmd_parts.append(allocator, "flatpak");
    try cmd_parts.append(allocator, "search");
    try cmd_parts.append(allocator, package_name);

    const cmd_slice = try cmd_parts.toOwnedSlice(allocator);
    defer allocator.free(cmd_slice);

    var child = std.process.Child.init(cmd_slice, allocator);
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;

    _ = child.spawnAndWait() catch {
        print("   (search failed)\n", .{});
        return;
    };
}

fn findFlatpakMatch(allocator: Allocator, query: []const u8) !?[]const u8 {
    var cmd_parts = ArrayList([]const u8){ .items = &[_][]const u8{}, .capacity = 0 };
    defer cmd_parts.deinit(allocator);

    try cmd_parts.append(allocator, "flatpak");
    try cmd_parts.append(allocator, "search");
    try cmd_parts.append(allocator, query);

    const cmd_slice = try cmd_parts.toOwnedSlice(allocator);
    defer allocator.free(cmd_slice);

    var child = std.process.Child.init(cmd_slice, allocator);
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Ignore;

    try child.spawn();
    const output = try child.stdout.?.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(output);

    const term = try child.wait();
    if (term != .Exited or term.Exited != 0) return null;

    // Parse flatpak search output to find matching package ID
    // Format: Name<TAB>Description<TAB>org.package.Name<TAB>Version<TAB>Branch<TAB>Remote
    var lines = std.mem.splitScalar(u8, output, '\n');
    while (lines.next()) |line| {
        if (std.mem.indexOf(u8, line, query) != null) {
            // Split by tabs to get the proper columns
            var parts = std.mem.splitScalar(u8, line, '\t');
            _ = parts.next(); // Skip name column
            _ = parts.next(); // Skip description column
            if (parts.next()) |package_id| {
                // Trim whitespace and check if it looks like a package ID
                const trimmed_id = std.mem.trim(u8, package_id, " \t\r\n");
                if (std.mem.count(u8, trimmed_id, ".") >= 2) {
                    const id_lower = std.ascii.allocLowerString(allocator, trimmed_id) catch continue;
                    defer allocator.free(id_lower);
                    const query_lower = std.ascii.allocLowerString(allocator, query) catch continue;
                    defer allocator.free(query_lower);

                    if (std.mem.indexOf(u8, id_lower, query_lower) != null) {
                        return try allocator.dupe(u8, trimmed_id);
                    }
                }
            }
        }
    }

    return null;
}

fn installFlatpak(allocator: Allocator, package: []const u8) !bool {
    var cmd_parts = ArrayList([]const u8){ .items = &[_][]const u8{}, .capacity = 0 };
    defer cmd_parts.deinit(allocator);

    try cmd_parts.append(allocator, "flatpak");
    try cmd_parts.append(allocator, "install");
    try cmd_parts.append(allocator, "-y");
    try cmd_parts.append(allocator, "flathub");
    try cmd_parts.append(allocator, package);
    try cmd_parts.append(allocator, "-y");

    const cmd_slice = try cmd_parts.toOwnedSlice(allocator);
    defer allocator.free(cmd_slice);

    var child = std.process.Child.init(cmd_slice, allocator);
    const term = child.spawnAndWait() catch return false;

    return switch (term) {
        .Exited => |code| code == 0,
        else => false,
    };
}

fn printVersion() void {
    print("🏠 here {s}\n", .{build_options.version});
    print("{s}\n\n", .{build_options.description});
    print("Author: {s}\n", .{build_options.author});
    print("License: {s}\n", .{build_options.license});
    print("Built with Zig\n\n", .{});
    print("🧊 AppImage Support: AppMan integration (2500+ apps)\n", .{});
    print("   AppMan by ivan-hc: https://github.com/ivan-hc/AM\n\n", .{});
    print("💖 Support development:\n", .{});
    print("   here project: 0xaf462cef9e8913a9cb7b6f0ba0ddf5d733eae57a (ETH/Base)\n", .{});
    print("   AppMan project: ko-fi.com/IvanAlexHC | PayPal.me/IvanAlexHC\n", .{});
    print("For more information: https://codeberg.org/OverHereEnterprise/here\n", .{});
}

// Use cli.showHelp() instead of local printHelp()

pub fn main(init: std.process.Init.Minimal) !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Collect args from the 0.16 iterator into a slice
    var args_list = ArrayList([]const u8){ .items = &[_][]const u8{}, .capacity = 0 };
    defer args_list.deinit(allocator);
    var args_it = std.process.Args.Iterator.init(init.args);
    while (args_it.next()) |arg| {
        try args_list.append(allocator, arg);
    }
    const args = args_list.items;
    const converted_args = args;

    if (args.len < 2) {
        cli.showHelp();
        return;
    }

    const command = cli.parseCommand(converted_args) orelse {
        cli.showUnknownCommand(converted_args[1]);
        return;
    };

    // Handle fallback search - treat unknown command as search query
    if (command == .fallback_search) {
        if (!cli.isLikelySearchQuery(converted_args[1])) {
            cli.showUnknownCommand(converted_args[1]);
            return;
        }

        // Prepare to perform search with the fallback query

        // Detect system for search
        const system_info = system.detectSystem(allocator) catch |err| {
            print("❌ Failed to detect system: {}\n", .{err});
            return;
        };
        defer allocator.free(system_info.version_managers);
        defer allocator.free(system_info.package_sources);

        print("🔍 Detected {s}", .{system_info.distro.toString()});
        if (system_info.package_manager != .unknown) {
            print(" with {s}", .{system_info.package_manager.toString()});
        }
        print("\n", .{});

        if (system_info.package_sources.len > 0) {
            print("📦 Package sources: ", .{});
            for (system_info.package_sources, 0..) |source, i| {
                print("{s}", .{source.toString()});
                if (i < system_info.package_sources.len - 1) print(", ", .{});
            }
            print("\n", .{});
        }

        if (system_info.version_managers.len > 0) {
            print("🔧 Version managers: ", .{});
            for (system_info.version_managers, 0..) |manager, i| {
                print("{s}", .{manager.toString()});
                if (i < system_info.version_managers.len - 1) print(", ", .{});
            }
            print("\n", .{});
        }

        // For yay/paru, do complete pass-through (search + install) to preserve full functionality
        if (system_info.package_manager == .yay or system_info.package_manager == .paru) {
            print("\n", .{});

            // Build command for yay/paru without any flags - this gives the full interactive experience
            var cmd_parts = ArrayList([]const u8){};
            try cmd_parts.append(allocator, system_info.package_manager.toString());
            try cmd_parts.append(allocator, converted_args[1]);

            const final_cmd_parts = try cmd_parts.toOwnedSlice(allocator);
            defer allocator.free(final_cmd_parts);

            var child = std.process.Child.init(final_cmd_parts, allocator);
            child.stdout_behavior = .Inherit;
            child.stderr_behavior = .Inherit;
            child.stdin_behavior = .Inherit;

            _ = child.spawnAndWait() catch |err| {
                print("❌ Command failed: {}\n", .{err});
                return;
            };
        } else {
            // Fall back to interactive search for other package managers
            packages.performInteractiveSearch(allocator, system_info, converted_args[1]) catch |err| {
                print("❌ Interactive search failed: {}\n", .{err});
            };
        }
        return;
    }

    if (command == .help) {
        cli.showHelp();
        return;
    }

    if (command == .version) {
        cli.showVersion();
        return;
    }

    // Detect system
    const system_info = system.detectSystem(allocator) catch |err| {
        print("❌ Failed to detect system: {}\n", .{err});
        return;
    };
    defer allocator.free(system_info.version_managers);
    defer allocator.free(system_info.package_sources);

    if (system_info.package_manager == .unknown and system_info.package_sources.len == 0) {
        print("❌ No supported package sources found\n", .{});
        print("💡 Supported: yay, paru, pacman, apt, zypper, dnf, nix, flatpak, snap\n", .{});
        return;
    }

    print("🔍 Detected {s}", .{system_info.distro.toString()});
    if (system_info.package_manager != .unknown) {
        print(" with {s}", .{system_info.package_manager.toString()});
    }
    print("\n", .{});

    if (system_info.package_sources.len > 0) {
        print("📦 Package sources: ", .{});
        for (system_info.package_sources, 0..) |source, i| {
            print("{s}", .{source.toString()});
            if (i < system_info.package_sources.len - 1) print(", ", .{});
        }
        print("\n", .{});
    }

    if (system_info.version_managers.len > 0) {
        print("🔧 Version managers: ", .{});
        for (system_info.version_managers, 0..) |manager, i| {
            print("{s}", .{manager.toString()});
            if (i < system_info.version_managers.len - 1) print(", ", .{});
        }
        print("\n", .{});
    }

    // Get packages from remaining args
    const package_args = if (converted_args.len > 2) converted_args[2..] else &[_][]const u8{};

    if (command != .update and command != .@"export" and command != .import and command != .backup and command != .recover and command != .unlock and command != .prunable and command != .standalone and command != .sweep and command != .clean and command != .link and command != .audit and command != .pkgbuild and package_args.len == 0) {
        print("❌ No packages specified\n", .{});
        return;
    }

    if (command == .@"export") {
        var include_config = false;
        var filename: ?[]const u8 = null;

        // Parse export arguments
        for (package_args) |arg| {
            if (std.mem.eql(u8, arg, "--include-config")) {
                include_config = true;
            } else if (!std.mem.startsWith(u8, arg, "--")) {
                filename = arg;
            }
        }

        profiles.exportProfile(allocator, filename, include_config) catch |err| {
            print("❌ Failed to create export profile: {}\n", .{err});
        };
        return;
    }

    if (command == .import) {
        var interactive = false;
        var install_native = false;
        var install_flatpak = false;
        var install_appimage = false;
        var install_all = false;

        if (package_args.len == 0) {
            print("❌ No profile file specified\n", .{});
            print("💡 Usage: here import <profile.json>\n", .{});
            print("💡 Usage: here import --interactive <profile.json>\n", .{});
            print("💡 Usage: here import --install-native <profile.json>\n", .{});
            print("💡 Usage: here import --install-flatpak <profile.json>\n", .{});
            print("💡 Usage: here import --install-appimage <profile.json>\n", .{});
            print("💡 Usage: here import --install-all <profile.json>\n", .{});
            return;
        }

        var profile_file: []const u8 = "";

        // Parse command line options
        var i: usize = 0;
        while (i < package_args.len) {
            if (std.mem.eql(u8, package_args[i], "--interactive")) {
                interactive = true;
            } else if (std.mem.eql(u8, package_args[i], "--install-native")) {
                install_native = true;
            } else if (std.mem.eql(u8, package_args[i], "--install-flatpak")) {
                install_flatpak = true;
            } else if (std.mem.eql(u8, package_args[i], "--install-appimage")) {
                install_appimage = true;
            } else if (std.mem.eql(u8, package_args[i], "--install-all")) {
                install_all = true;
            } else if (!std.mem.startsWith(u8, package_args[i], "--")) {
                profile_file = package_args[i];
            }
            i += 1;
        }

        if (profile_file.len == 0) {
            print("❌ No profile file specified\n", .{});
            return;
        }

        if (interactive) {
            // Use interactive import
            const profile_contents = std.fs.cwd().readFileAlloc(allocator, profile_file, 1024 * 1024) catch |err| {
                print("❌ Failed to read profile file: {}\n", .{err});
                return;
            };
            defer allocator.free(profile_contents);

            interactive_import.runInteractiveImport(allocator, profile_contents, profile_file) catch |err| {
                print("❌ Interactive import failed: {}\n", .{err});
            };
        } else if (install_native or install_flatpak or install_appimage or install_all) {
            // Use batch installation
            packages.installPackagesBatch(allocator, profile_file, install_native, install_flatpak, install_appimage, install_all) catch |err| {
                print("❌ Failed to install packages: {}\n", .{err});
            };
        } else {
            // Use standard import (analysis only)
            importProfile(allocator, profile_file) catch |err| {
                print("❌ Failed to import profile: {}\n", .{err});
            };
        }
        return;
    }

    if (command == .backup) {
        migration.runMigrationBackup(allocator, converted_args) catch |err| {
            print("❌ Backup command failed: {}\n", .{err});
        };
        return;
    }

    if (command == .recover) {
        recovery.runRecovery(allocator, package_args) catch |err| {
            print("❌ Recovery command failed: {}\n", .{err});
        };
        return;
    }

    if (command == .config) {
        if (package_args.len > 0 and std.mem.eql(u8, package_args[0], "recovery")) {
            const recovery_config = @import("config/recovery_config.zig");

            print("🔧 Recovery Configuration Setup\n", .{});
            print("==============================\n\n", .{});

            // Setup interactive configuration
            const config = recovery_config.RecoveryConfig.setupInteractive(allocator) catch |err| {
                print("❌ Configuration setup failed: {}\n", .{err});
                return;
            };

            // Validate configuration
            config.validate() catch |err| {
                print("❌ Configuration validation failed: {}\n", .{err});
                return;
            };

            // Ensure config directory exists
            recovery_config.ensureConfigDir(allocator) catch |err| {
                print("❌ Failed to create config directory: {}\n", .{err});
                return;
            };

            // Get config file path
            const config_path = recovery_config.getConfigPath(allocator) catch |err| {
                print("❌ Failed to get config path: {}\n", .{err});
                return;
            };
            defer allocator.free(config_path);

            // Save configuration
            config.saveToFile(allocator, config_path) catch |err| {
                print("❌ Failed to save configuration: {}\n", .{err});
                return;
            };

            print("\n✅ Recovery configuration saved successfully!\n", .{});
            config.print();
        } else {
            print("❌ Unknown config subcommand\n", .{});
            print("Available options:\n", .{});
            print("  here config recovery  - Configure recovery system\n", .{});
        }
        return;
    }

    if (command == .unlock) {
        packages.unlockPackageManager(allocator, system_info) catch |err| {
            print("❌ Unlock command failed: {}\n", .{err});
        };
        return;
    }

    // Handle search across multiple package sources
    if (command == .search) {
        print("\n", .{});

        // Search native packages first
        if (system_info.package_manager != .unknown) {
            print("🏠 Native packages:\n", .{});
            const cmd_parts = packages.buildCommand(allocator, system_info, command, package_args) catch |err| {
                print("❌ Failed to build command: {}\n", .{err});
                return;
            };
            defer allocator.free(cmd_parts);

            var child = std.process.Child.init(cmd_parts, allocator);
            child.stdout_behavior = .Inherit;
            child.stderr_behavior = .Inherit;
            _ = child.spawnAndWait() catch {};
        }

        // Search additional sources
        if (package_args.len > 0) {
            for (system_info.package_sources) |source| {
                switch (source) {
                    .flatpak => {
                        print("\n", .{});
                        searchFlatpak(allocator, package_args[0]) catch {};
                    },
                    .appimage => {
                        print("\n", .{});
                        searchAppImage(allocator, package_args[0]) catch {};
                    },
                    else => {},
                }
            }
        }
        return;
    }

    // Check if any packages are development tools that might benefit from version managers
    if (command == .install) {
        for (package_args) |pkg| {
            if (packages.isDevelopmentTool(pkg)) |tool| {
                packages.suggestVersionManager(system_info, tool, pkg);

                // Read user input
                print("🤔 Continue with system package manager? [y/N]: ", .{});
                var buf: [256]u8 = undefined;
                const stdin_file = std.fs.File.stdin();
                const bytes_read = stdin_file.read(buf[0..]) catch 0;
                if (bytes_read > 0) {
                    const input = buf[0..bytes_read];
                    const trimmed = std.mem.trim(u8, input, " \t\r\n");
                    if (trimmed.len == 0 or (trimmed[0] != 'y' and trimmed[0] != 'Y')) {
                        print("⏹️  Installation cancelled.\n", .{});
                        return;
                    }
                } else {
                    print("⏹️  Installation cancelled.\n", .{});
                    return;
                }
            }
        }

        // For install, try Flatpak first if native package manager fails
        if (system_info.package_manager != .unknown) {
            const cmd_parts = packages.buildCommand(allocator, system_info, command, package_args) catch |err| {
                print("❌ Failed to build native command: {}\n", .{err});

                // Try alternative sources as fallback
                for (system_info.package_sources) |source| {
                    if (package_args.len > 0) {
                        switch (source) {
                            .flatpak => {
                                print("🔄 Trying Flatpak...\n", .{});

                                // First try direct install with the given name
                                if (installFlatpak(allocator, package_args[0]) catch false) {
                                    print("✅ Installed via Flatpak\n", .{});
                                    return;
                                }

                                // If that fails, try to find a matching Flatpak ID
                                if (findFlatpakMatch(allocator, package_args[0]) catch null) |flatpak_id| {
                                    defer allocator.free(flatpak_id);
                                    print("🎯 Found Flatpak match: {s}\n", .{flatpak_id});
                                    if (installFlatpak(allocator, flatpak_id) catch false) {
                                        print("✅ Installed via Flatpak\n", .{});
                                        return;
                                    }
                                }
                            },
                            .appimage => {
                                print("🔄 Trying AppImage via AppMan...\n", .{});
                                if (installAppImage(allocator, package_args[0]) catch false) {
                                    print("✅ AppImage installed successfully\n", .{});
                                    return;
                                }
                            },
                            else => {},
                        }
                    }
                }
                return;
            };
            defer allocator.free(cmd_parts);

            print("🚀 Running: ", .{});
            for (cmd_parts, 0..) |part, i| {
                if (i > 0) print(" ", .{});
                print("{s}", .{part});
            }
            print("\n", .{});

            var child = std.process.Child.init(cmd_parts, allocator);
            const term = child.spawnAndWait() catch |err| {
                print("❌ Failed to execute command: {}\n", .{err});

                // Try Flatpak as fallback with intelligent matching
                for (system_info.package_sources) |source| {
                    if (source == .flatpak and package_args.len > 0) {
                        print("🔄 Trying Flatpak...\n", .{});

                        // First try direct install with the given name
                        if (installFlatpak(allocator, package_args[0]) catch false) {
                            print("✅ Installed via Flatpak\n", .{});
                            return;
                        }

                        // If that fails, try to find a matching Flatpak ID
                        if (findFlatpakMatch(allocator, package_args[0]) catch null) |flatpak_id| {
                            defer allocator.free(flatpak_id);
                            print("🎯 Found Flatpak match: {s}\n", .{flatpak_id});
                            if (installFlatpak(allocator, flatpak_id) catch false) {
                                print("✅ Installed via Flatpak\n", .{});
                                return;
                            }
                        }
                    }
                }
                return;
            };

            switch (term) {
                .Exited => |code| {
                    if (code == 0) {
                        print("✅ Command completed successfully\n", .{});
                    } else {
                        print("❌ Command failed with exit code: {}\n", .{code});

                        // Try Flatpak as fallback with intelligent matching
                        for (system_info.package_sources) |source| {
                            if (source == .flatpak and package_args.len > 0) {
                                print("🔄 Trying Flatpak...\n", .{});

                                // First try direct install with the given name
                                if (installFlatpak(allocator, package_args[0]) catch false) {
                                    print("✅ Installed via Flatpak\n", .{});
                                    return;
                                }

                                // If that fails, try to find a matching Flatpak ID
                                if (findFlatpakMatch(allocator, package_args[0]) catch null) |flatpak_id| {
                                    defer allocator.free(flatpak_id);
                                    print("🎯 Found Flatpak match: {s}\n", .{flatpak_id});
                                    if (installFlatpak(allocator, flatpak_id) catch false) {
                                        print("✅ Installed via Flatpak\n", .{});
                                        return;
                                    }
                                }
                            }
                        }
                    }
                },
                else => {
                    print("❌ Command terminated unexpectedly\n", .{});
                },
            }
            return;
        }

        // If no native package manager, try alternative sources
        for (system_info.package_sources) |source| {
            if (package_args.len > 0) {
                switch (source) {
                    .flatpak => {
                        print("🚀 Installing via Flatpak: {s}\n", .{package_args[0]});

                        // First try direct install
                        if (installFlatpak(allocator, package_args[0]) catch false) {
                            print("✅ Installed via Flatpak\n", .{});
                            return;
                        }

                        // If that fails, try to find a matching Flatpak ID
                        if (findFlatpakMatch(allocator, package_args[0]) catch null) |flatpak_id| {
                            defer allocator.free(flatpak_id);
                            print("🎯 Found Flatpak match: {s}\n", .{flatpak_id});
                            if (installFlatpak(allocator, flatpak_id) catch false) {
                                print("✅ Installed via Flatpak\n", .{});
                                return;
                            }
                        }

                        print("❌ Flatpak installation failed\n", .{});
                    },
                    .appimage => {
                        print("🚀 Installing via AppMan/AppImage: {s}\n", .{package_args[0]});
                        if (installAppImage(allocator, package_args[0]) catch false) {
                            print("✅ AppImage installed successfully\n", .{});
                            return;
                        }
                        print("❌ AppImage not available through AppMan or fallback methods\n", .{});
                    },
                    else => {},
                }
            }
        }

        print("❌ No available package sources for installation\n", .{});
        return;
    }

    // Handle prunable and standalone commands with "better wording" headers
    if (command == .prunable or command == .standalone) {
        if (system_info.package_manager != .unknown) {
            const cmd_parts = packages.buildCommand(allocator, system_info, command, package_args) catch |err| {
                print("❌ Failed to build command: {}\n", .{err});
                return;
            };
            defer allocator.free(cmd_parts);

            if (command == .prunable) {
                print("\n🧹 Prunable packages (unneeded dependencies):\n", .{});
                print("============================================\n", .{});
            } else {
                print("\n📦 Standalone packages (top-level):\n", .{});
                print("==================================\n", .{});
            }

            var child = std.process.Child.init(cmd_parts, allocator);
            child.stdout_behavior = .Inherit;
            child.stderr_behavior = .Inherit;
            _ = child.spawnAndWait() catch {};
            print("\n", .{});
        } else {
            print("❌ No supported package manager found for this operation\n", .{});
        }
        return;
    }

    // Handle list command with AppImage support
    if (command == .sweep) {
        packages.performPruneFlow(allocator, system_info) catch |err| {
            print("❌ Sweep command failed: {}\n", .{err});
        };
        return;
    }

    if (command == .clean) {
        packages.performCleanFlow(allocator, system_info, package_args) catch |err| {
            print("❌ Clean command failed: {}\n", .{err});
        };
        return;
    }

    if (command == .link) {
        print("🔗 Managing links via biglinks...\n", .{});

        var cmd_parts = ArrayList([]const u8){ .items = &[_][]const u8{}, .capacity = 0 };
        defer cmd_parts.deinit(allocator);

        cmd_parts.append(allocator, "biglinks") catch return;
        for (package_args) |arg| {
            cmd_parts.append(allocator, arg) catch return;
        }

        var child = std.process.Child.init(cmd_parts.items, allocator);
        child.stdout_behavior = .Inherit;
        child.stderr_behavior = .Inherit;

        const term = child.spawnAndWait() catch |err| {
            print("❌ Failed to execute biglinks: {}\n", .{err});
            print("💡 Ensure 'biglinks' is installed and in your PATH.\n", .{});
            return;
        };

        switch (term) {
            .Exited => |code| {
                if (code != 0) {
                    print("❌ biglinks exited with code: {}\n", .{code});
                }
            },
            else => print("❌ biglinks terminated unexpectedly\n", .{}),
        }
        return;
    }

    if (command == .pkgbuild) {
        audit.runPkgbuild(allocator, package_args) catch |err| {
            print("❌ pkgbuild command failed: {}\n", .{err});
        };
        return;
    }

    if (command == .audit) {
        audit.runAudit(allocator, package_args) catch |err| {
            print("❌ Audit failed: {}\n", .{err});
        };
        return;
    }

    if (command == .list) {
        // Show native packages first
        if (system_info.package_manager != .unknown) {
            const cmd_parts = packages.buildCommand(allocator, system_info, command, package_args) catch |err| {
                print("❌ Failed to build command: {}\n", .{err});
                return;
            };
            defer allocator.free(cmd_parts);

            print("🚀 Running: ", .{});
            for (cmd_parts, 0..) |part, i| {
                if (i > 0) print(" ", .{});
                print("{s}", .{part});
            }
            print("\n\n", .{});

            var child = std.process.Child.init(cmd_parts, allocator);
            child.stdout_behavior = .Inherit;
            child.stderr_behavior = .Inherit;
            _ = child.spawnAndWait() catch {};
        }

        // Also list AppImages if available
        for (system_info.package_sources) |source| {
            if (source == .appimage) {
                print("\n", .{});
                // Try AppMan first for comprehensive listing
                var appman_manager = appman.AppManManager.init(allocator) catch {
                    // Fallback to basic AppImage listing
                    var installer = appimage.AppImageInstaller.init(allocator) catch continue;
                    defer installer.deinit();
                    installer.listInstalled() catch {};
                    continue;
                };
                defer appman_manager.deinit();

                appman_manager.listInstalled() catch {
                    // Fallback if AppMan listing fails
                    var installer = appimage.AppImageInstaller.init(allocator) catch continue;
                    defer installer.deinit();
                    installer.listInstalled() catch {};
                };
            }
        }
        return;
    }

    // For other commands, use native package manager
    if (system_info.package_manager == .unknown) {
        print("❌ No supported package manager found for this operation\n", .{});
        return;
    }

    const cmd_parts = packages.buildCommand(allocator, system_info, command, package_args) catch |err| {
        print("❌ Failed to build command: {}\n", .{err});
        return;
    };
    defer allocator.free(cmd_parts);

    print("🚀 Running: ", .{});
    for (cmd_parts, 0..) |part, i| {
        if (i > 0) print(" ", .{});
        print("{s}", .{part});
    }
    print("\n", .{});

    var child = std.process.Child.init(cmd_parts, allocator);
    const term = child.spawnAndWait() catch |err| {
        print("❌ Failed to execute command: {}\n", .{err});
        return;
    };

    switch (term) {
        .Exited => |code| {
            if (code == 0) {
                print("✅ Command completed successfully\n", .{});
            } else {
                print("❌ Command failed with exit code: {}\n", .{code});
                if (command == .install) {
                    print("\n⚠️  Installation failed. Would you like to run a Smart Diagnostic? [y/N]: ", .{});
                    var buf: [256]u8 = undefined;
                    const stdin = std.fs.File.stdin();
                    const bytes_read = stdin.read(buf[0..]) catch 0;
                    if (bytes_read > 0) {
                        const input = std.mem.trim(u8, buf[0..bytes_read], " \t\r\n");
                        if (input.len > 0 and (input[0] == 'y' or input[0] == 'Y')) {
                            print("\n🔍 Analyzing failure (this will rerun the process silently, please wait)...\n", .{});
                            const smart_recovery = @import("core/recovery.zig");

                            var diag_child = std.process.Child.init(cmd_parts, allocator);
                            diag_child.stdout_behavior = .Pipe;
                            diag_child.stderr_behavior = .Pipe;

                            var stdout_buf = std.ArrayList(u8){};
                            var stderr_buf = std.ArrayList(u8){};
                            defer stdout_buf.deinit(allocator);
                            defer stderr_buf.deinit(allocator);

                            diag_child.spawn() catch {};
                            diag_child.collectOutput(allocator, &stdout_buf, &stderr_buf, 10 * 1024 * 1024) catch {};
                            _ = diag_child.wait() catch {};

                            const action_opt = smart_recovery.analyzeFailure(allocator, system_info, stdout_buf.items, stderr_buf.items) catch null;
                            if (action_opt) |action| {
                                defer action.deinit(allocator);
                                print("\n✨ Smart Diagnosis Complete!\n", .{});
                                print("💡 {s}\n", .{action.message});

                                if (action.action_type == .skip_checksums) {
                                    print("\n🔧 Apply fix automatically? [y/N]: ", .{});
                                    const fix_bytes = stdin.read(buf[0..]) catch 0;
                                    const fix_input = std.mem.trim(u8, buf[0..fix_bytes], " \t\r\n");
                                    if (fix_input.len > 0 and (fix_input[0] == 'y' or fix_input[0] == 'Y')) {
                                        var fixed_cmd = std.ArrayList([]const u8){};
                                        defer fixed_cmd.deinit(allocator);

                                        for (cmd_parts) |part| {
                                            fixed_cmd.append(allocator, part) catch continue;
                                            if (std.mem.eql(u8, part, "-S") or std.mem.eql(u8, part, "install")) {
                                                fixed_cmd.append(allocator, "--mflags") catch continue;
                                                fixed_cmd.append(allocator, "--skipchecksums") catch continue;
                                            }
                                        }

                                        print("\n🚀 Rerunning with skipped checksums...\n", .{});
                                        var fixed_child = std.process.Child.init(fixed_cmd.items, allocator);
                                        _ = fixed_child.spawnAndWait() catch {};
                                    }
                                } else if (action.action_type == .install_dependencies) {
                                    print("\n📦 Missing dependencies: ", .{});
                                    for (action.packages_to_install) |dep| print("{s} ", .{dep});
                                    print("\n\n🔧 Install them now? [y/N]: ", .{});

                                    const fix_bytes = stdin.read(buf[0..]) catch 0;
                                    const fix_input = std.mem.trim(u8, buf[0..fix_bytes], " \t\r\n");
                                    if (fix_input.len > 0 and (fix_input[0] == 'y' or fix_input[0] == 'Y')) {
                                        const dep_cmd = packages.buildCommand(allocator, system_info, .install, action.packages_to_install) catch return;
                                        defer allocator.free(dep_cmd);

                                        print("\n🚀 Installing dependencies...\n", .{});
                                        var dep_child = std.process.Child.init(dep_cmd, allocator);
                                        const dep_term = dep_child.spawnAndWait() catch return;

                                        if (dep_term == .Exited and dep_term.Exited == 0) {
                                            print("\n✅ Dependencies installed! Run your original install command again.\n", .{});
                                        }
                                    }
                                }
                            } else {
                                print("\n🤷 No automated fix found for this issue.\n", .{});
                            }
                        }
                    }
                }
            }
        },
        else => {
            print("❌ Command terminated unexpectedly\n", .{});
        },
    }
}
