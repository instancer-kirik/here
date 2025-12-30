const std = @import("std");
const print = std.debug.print;
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

// Import from core modules
const system = @import("../core/system.zig");
const packages = @import("../core/packages.zig");
const SystemInfo = system.SystemInfo;
const PackageManager = system.PackageManager;
const Command = packages.Command;
const detectSystem = system.detectSystem;
const buildCommand = packages.buildCommand;

const InteractiveImporter = struct {
    allocator: Allocator,
    contents: []const u8,
    filename: []const u8,
    native_count: u32,
    flatpak_count: u32,
    appimage_count: u32,

    const Self = @This();

    pub fn init(allocator: Allocator, contents: []const u8, filename: []const u8) !Self {
        var importer = Self{
            .allocator = allocator,
            .contents = contents,
            .filename = filename,
            .native_count = 0,
            .flatpak_count = 0,
            .appimage_count = 0,
        };

        // Count packages in each category
        importer.native_count = try countPackagesInSection(contents, "native");
        importer.flatpak_count = try countPackagesInSection(contents, "flatpak");
        importer.appimage_count = try countPackagesInSection(contents, "appimage");

        return importer;
    }

    pub fn showInteractiveMenu(self: *Self) !void {
        print("\n🎯 Interactive Package Selection\n", .{});
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});

        while (true) {
            self.displayMenu();

            const choice = getUserChoice() catch {
                print("❌ Failed to read input, showing preview\n", .{});
                try self.previewAllPackages();
                return;
            };

            if (try self.handleChoice(choice)) {
                break; // Exit the menu
            }
        }
    }

    fn displayMenu(self: *Self) void {
        print("\n📦 What would you like to install?\n", .{});
        print("   1️⃣  All native packages ({})\n", .{self.native_count});
        print("   2️⃣  All Flatpak packages ({})\n", .{self.flatpak_count});
        print("   3️⃣  All AppImage packages ({})\n", .{self.appimage_count});
        print("   4️⃣  Everything (recommended)\n", .{});
        print("   5️⃣  Browse and select specific packages\n", .{});
        print("   6️⃣  Preview packages only\n", .{});
        print("   7️⃣  Exit\n", .{});
        print("\n🔸 Enter your choice (1-7): ", .{});
    }

    fn getUserChoice() !u8 {
        // Use direct stdin reading for better reliability
        var buf: [256]u8 = undefined;
        const stdin = std.fs.File.stdin();

        const bytes_read = stdin.read(buf[0..]) catch return error.NoInput;
        if (bytes_read == 0) return error.NoInput;

        const input = buf[0..bytes_read];
        const trimmed = std.mem.trim(u8, input, " \t\r\n");
        if (trimmed.len > 0) {
            return trimmed[0];
        }

        return error.NoInput;
    }

    fn handleChoice(self: *Self, choice: u8) !bool {
        switch (choice) {
            '1' => {
                if (self.native_count > 0) {
                    print("1️⃣\n\n🚀 Installing {} native packages...\n", .{self.native_count});
                    try self.installPackagesFromSection("native");
                } else {
                    print("1️⃣\n\n⚠️  No native packages found.\n", .{});
                }
                return true;
            },
            '2' => {
                if (self.flatpak_count > 0) {
                    print("2️⃣\n\n🚀 Installing {} Flatpak packages...\n", .{self.flatpak_count});
                    try self.installPackagesFromSection("flatpak");
                } else {
                    print("2️⃣\n\n⚠️  No Flatpak packages found.\n", .{});
                }
                return true;
            },
            '3' => {
                if (self.appimage_count > 0) {
                    print("3️⃣\n\n🚀 Installing {} AppImage packages...\n", .{self.appimage_count});
                    try self.installPackagesFromSection("appimage");
                } else {
                    print("3️⃣\n\n⚠️  No AppImage packages found.\n", .{});
                }
                return true;
            },
            '4' => {
                print("4️⃣\n\n🚀 Installing all {} packages...\n", .{self.native_count + self.flatpak_count + self.appimage_count});
                if (self.native_count > 0) try self.installPackagesFromSection("native");
                if (self.flatpak_count > 0) try self.installPackagesFromSection("flatpak");
                if (self.appimage_count > 0) try self.installPackagesFromSection("appimage");
                return true;
            },
            '5' => {
                print("5️⃣\n\n🔍 Browse and select mode\n", .{});
                try self.browseAndSelectPackages();
                return true;
            },
            '6' => {
                print("6️⃣\n\n", .{});
                try self.previewAllPackages();
                return true;
            },
            '7' => {
                print("7️⃣\n\n👋 Goodbye!\n", .{});
                return true;
            },
            else => {
                print("❌ Invalid choice. Please select 1-7.\n", .{});
                return false;
            },
        }
    }

    fn installPackagesFromSection(self: *Self, section_type: []const u8) !void {
        var package_list = try self.extractPackagesFromSection(section_type);
        defer {
            for (package_list.items) |pkg| self.allocator.free(pkg);
            package_list.deinit(self.allocator);
        }

        if (package_list.items.len == 0) {
            print("⚠️  No packages found in {s} section.\n", .{section_type});
            return;
        }

        print("📋 Found {} {s} packages to install:\n", .{ package_list.items.len, section_type });

        // Show first 10 packages
        for (package_list.items, 0..) |pkg, i| {
            if (i < 10) {
                print("  • {s}\n", .{pkg});
            } else if (i == 10) {
                print("  ... and {} more\n", .{package_list.items.len - 10});
                break;
            }
        }

        if (!self.confirmInstallation()) {
            print("⏭️  Installation cancelled.\n", .{});
            return;
        }

        // Install packages one by one
        print("\n🚀 Starting installation...\n", .{});
        var installed: u32 = 0;
        var failed: u32 = 0;

        for (package_list.items, 0..) |pkg, i| {
            print("\n[{}/{}] Installing {s}...", .{ i + 1, package_list.items.len, pkg });

            if (self.installSinglePackage(pkg, section_type)) {
                print(" ✅\n", .{});
                installed += 1;
            } else |_| {
                print(" ❌\n", .{});
                failed += 1;
            }
        }

        print("\n🎉 Installation Summary:\n", .{});
        print("  ✅ Installed: {}\n", .{installed});
        print("  ❌ Failed: {}\n", .{failed});
        print("  📦 Total: {}\n", .{package_list.items.len});
    }

    fn confirmInstallation(_: *Self) bool {
        print("\n⚠️  Continue with installation? [Y/n]: ", .{});

        var buf: [256]u8 = undefined;
        const stdin = std.fs.File.stdin();
        const bytes_read = stdin.read(buf[0..]) catch return false;

        if (bytes_read == 0) return true; // Default to yes on empty input

        const input = std.mem.trim(u8, buf[0..bytes_read], " \t\r\n");
        return input.len == 0 or (input[0] != 'n' and input[0] != 'N');
    }

    fn installSinglePackage(self: *Self, package_name: []const u8, package_type: []const u8) !void {
        if (std.mem.eql(u8, package_type, "native")) {
            try self.installNativePackage(package_name);
        } else if (std.mem.eql(u8, package_type, "flatpak")) {
            try self.installFlatpakPackage(package_name);
        } else if (std.mem.eql(u8, package_type, "appimage")) {
            try self.installAppImagePackage(package_name);
        } else {
            return error.UnsupportedPackageType;
        }
    }

    fn installNativePackage(self: *Self, package_name: []const u8) !void {
        const system_info = detectSystem(self.allocator) catch return error.SystemDetectionFailed;
        defer self.allocator.free(system_info.version_managers);
        defer self.allocator.free(system_info.package_sources);

        const cmd_parts = buildCommand(self.allocator, system_info, .install, &[_][]const u8{package_name}) catch return error.CommandBuildFailed;
        defer self.allocator.free(cmd_parts);

        var child = std.process.Child.init(cmd_parts, self.allocator);
        child.stdin_behavior = .Inherit;
        child.stdout_behavior = .Inherit;
        child.stderr_behavior = .Inherit;

        const term = child.spawnAndWait() catch return error.ExecutionFailed;

        switch (term) {
            .Exited => |code| {
                if (code != 0) {
                    return error.InstallationFailed;
                }
            },
            else => return error.InstallationFailed,
        }
    }

    fn installFlatpakPackage(self: *Self, package_name: []const u8) !void {
        var child = std.process.Child.init(&[_][]const u8{ "flatpak", "install", "--user", "-y", package_name }, self.allocator);
        child.stdin_behavior = .Inherit;
        child.stdout_behavior = .Inherit;
        child.stderr_behavior = .Inherit;

        const term = child.spawnAndWait() catch return error.ExecutionFailed;

        switch (term) {
            .Exited => |code| {
                if (code != 0) {
                    return error.InstallationFailed;
                }
            },
            else => return error.InstallationFailed,
        }
    }

    fn installAppImagePackage(self: *Self, package_name: []const u8) !void {
        // This would integrate with the existing AppImage installation logic
        // For now, just return an error indicating it's not implemented
        _ = self;
        _ = package_name;
        return error.NotImplemented;
    }

    fn browseAndSelectPackages(self: *Self) !void {
        print("🔍 Browse and Select Packages\n", .{});
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});

        // Show sections and let user choose which to browse
        while (true) {
            print("\nSelect a category to browse:\n", .{});
            print("  1️⃣  Native packages ({})\n", .{self.native_count});
            print("  2️⃣  Flatpak packages ({})\n", .{self.flatpak_count});
            print("  3️⃣  AppImage packages ({})\n", .{self.appimage_count});
            print("  4️⃣  Back to main menu\n", .{});
            print("\nChoice: ", .{});

            const choice = getUserChoice() catch {
                print("Back to main menu\n", .{});
                return;
            };

            switch (choice) {
                '1' => try self.browseSection("native"),
                '2' => try self.browseSection("flatpak"),
                '3' => try self.browseSection("appimage"),
                '4' => return,
                else => print("Invalid choice, try again.\n", .{}),
            }
        }
    }

    fn browseSection(self: *Self, section_type: []const u8) !void {
        var package_list = try self.extractPackagesFromSection(section_type);
        defer {
            for (package_list.items) |pkg| self.allocator.free(pkg);
            package_list.deinit(self.allocator);
        }

        if (package_list.items.len == 0) {
            print("No {s} packages found.\n", .{section_type});
            return;
        }

        print("📦 {s} packages ({}):\n", .{ section_type, package_list.items.len });

        // Show packages with numbers
        for (package_list.items, 0..) |pkg, i| {
            print("  {d}. {s}\n", .{ i + 1, pkg });
        }

        print("\n🎯 Select packages to install:\n", .{});
        print("💡 Enter numbers (e.g., 1,3,5-8,10 or 1 3 5-8 10) or 'all' for everything, 'none' to go back\n", .{});
        print("📝 Input tips:\n", .{});
        print("   • Type your selection on one line and press Enter\n", .{});
        print("   • If terminal gets stuck on backspace, use Ctrl+C and restart\n", .{});
        print("   • For long lists, consider using ranges: 1-50,100-150\n", .{});
        print("Selection: ", .{});

        var input_buf: [1024]u8 = undefined;
        const stdin = std.fs.File.stdin();
        const bytes_read = stdin.read(input_buf[0..]) catch {
            print("Failed to read input, going back.\n", .{});
            return;
        };

        if (bytes_read == 0) {
            print("No input received, going back.\n", .{});
            return;
        }

        const input = std.mem.trim(u8, input_buf[0..bytes_read], " \t\r\n");

        if (std.mem.eql(u8, input, "none") or input.len == 0) {
            return;
        }

        if (std.mem.eql(u8, input, "all")) {
            print("\n🚀 Installing all {} {s} packages...\n", .{ package_list.items.len, section_type });
            try self.installPackagesFromSection(section_type);
            return;
        }

        // Parse selection and install selected packages
        try self.installSelectedPackages(package_list.items, input, section_type);
    }

    fn previewAllPackages(self: *Self) !void {
        print("🔍 Package Preview\n", .{});
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});

        if (self.native_count > 0) {
            print("\n📦 Native packages ({}):\n", .{self.native_count});
            try self.showPackageSection("native", 20);
        }

        if (self.flatpak_count > 0) {
            print("\n🏪 Flatpak packages ({}):\n", .{self.flatpak_count});
            try self.showPackageSection("flatpak", 10);
        }

        if (self.appimage_count > 0) {
            print("\n🎯 AppImage packages ({}):\n", .{self.appimage_count});
            try self.showPackageSection("appimage", 10);
        }

        print("\n💡 Use the interactive menu to install packages\n", .{});
    }

    fn showPackageSection(self: *Self, section_type: []const u8, max_show: u32) !void {
        const search_pattern = try std.fmt.allocPrint(self.allocator, "\"{s}\": [", .{section_type});
        defer self.allocator.free(search_pattern);

        if (std.mem.indexOf(u8, self.contents, search_pattern)) |section_start| {
            const section = self.contents[section_start..];
            if (std.mem.indexOf(u8, section, "]")) |section_end| {
                const section_content = section[0..section_end];
                var lines = std.mem.splitScalar(u8, section_content, '\n');
                var count: u32 = 0;
                var total_count: u32 = 0;

                while (lines.next()) |line| {
                    const trimmed = std.mem.trim(u8, line, " \t\r\n");
                    if (std.mem.startsWith(u8, trimmed, "\"") and
                        (std.mem.endsWith(u8, trimmed, "\",") or std.mem.endsWith(u8, trimmed, "\"")))
                    {
                        total_count += 1;
                        if (count < max_show) {
                            const pkg_name = if (std.mem.endsWith(u8, trimmed, "\","))
                                trimmed[1 .. trimmed.len - 2]
                            else
                                trimmed[1 .. trimmed.len - 1];

                            if (pkg_name.len > 0) {
                                print("  • {s}\n", .{pkg_name});
                                count += 1;
                            }
                        }
                    }
                }

                if (total_count > max_show) {
                    print("  ... and {} more packages\n", .{total_count - max_show});
                }
            }
        }
    }

    fn installSelectedPackages(self: *Self, package_list: [][]u8, selection: []const u8, section_type: []const u8) !void {
        var selected_indices = ArrayList(usize){ .items = &[_]usize{}, .capacity = 0 };
        defer selected_indices.deinit(self.allocator);

        // Parse the selection string (e.g., "1,3,5-8,10" or "1 3 5-8 10")
        // First normalize by replacing spaces with commas
        var normalized_selection = try std.fmt.allocPrint(self.allocator, "{s}", .{selection});
        defer self.allocator.free(normalized_selection);

        // Replace spaces with commas for consistent parsing
        for (normalized_selection, 0..) |c, i| {
            if (c == ' ') {
                normalized_selection[i] = ',';
            }
        }

        var parts = std.mem.splitScalar(u8, normalized_selection, ',');
        while (parts.next()) |part| {
            const trimmed_part = std.mem.trim(u8, part, " ");

            // Skip empty parts
            if (trimmed_part.len == 0) continue;

            if (std.mem.indexOf(u8, trimmed_part, "-")) |dash_pos| {
                // Handle range (e.g., "5-8")
                const start_str = trimmed_part[0..dash_pos];
                const end_str = trimmed_part[dash_pos + 1 ..];

                const start = std.fmt.parseInt(usize, start_str, 10) catch continue;
                const end = std.fmt.parseInt(usize, end_str, 10) catch continue;

                if (start >= 1 and end <= package_list.len and start <= end) {
                    var i: usize = start;
                    while (i <= end) : (i += 1) {
                        try selected_indices.append(self.allocator, i - 1); // Convert to 0-based
                    }
                }
            } else {
                // Handle single number
                const num = std.fmt.parseInt(usize, trimmed_part, 10) catch continue;
                if (num >= 1 and num <= package_list.len) {
                    try selected_indices.append(self.allocator, num - 1); // Convert to 0-based
                }
            }
        }

        if (selected_indices.items.len == 0) {
            print("❌ No valid packages selected from input: '{s}'\n", .{selection});
            print("💡 Valid format examples:\n", .{});
            print("   • Individual: 1,3,5 or 1 3 5\n", .{});
            print("   • Ranges: 5-10 or 1-5,8-12\n", .{});
            print("   • Mixed: 1,3,5-8,10\n", .{});
            print("   • All packages: all\n", .{});
            print("🔄 Going back to package list - you can try again\n", .{});
            return;
        }

        print("\n📋 Selected {} packages to install:\n", .{selected_indices.items.len});
        for (selected_indices.items) |idx| {
            print("  • {s}\n", .{package_list[idx]});
        }

        if (!self.confirmInstallation()) {
            print("⏭️  Installation cancelled.\n", .{});
            return;
        }

        print("\n🚀 Starting installation...\n", .{});
        var installed: u32 = 0;
        var failed: u32 = 0;

        // Ask user if they want batch or individual installation
        print("\n⚙️  Installation method:\n", .{});
        print("  1️⃣  Batch install (single yay command - recommended)\n", .{});
        print("      ✅ More efficient, better dependency resolution\n", .{});
        print("  2️⃣  Individual install (one package at a time)\n", .{});
        print("      ✅ More control, easier to debug failures\n", .{});
        print("Choice [1-2] (Enter = batch): ", .{});

        var method_buf: [256]u8 = undefined;
        const stdin = std.fs.File.stdin();
        const method_read = stdin.read(method_buf[0..]) catch {
            print("Using batch install (default)\n", .{});
            try self.installSelectedPackagesBatch(package_list, selected_indices.items, section_type);
            return;
        };

        const method_input = std.mem.trim(u8, method_buf[0..method_read], " \t\r\n");

        if (method_input.len > 0 and method_input[0] == '2') {
            // Individual installation
            for (selected_indices.items, 0..) |idx, i| {
                const pkg = package_list[idx];
                print("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
                print("📦 [{}/{}] Installing: {s}\n", .{ i + 1, selected_indices.items.len, pkg });
                print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});

                if (self.installSinglePackage(pkg, section_type)) {
                    print("\n✅ Successfully installed: {s}\n", .{pkg});
                    installed += 1;
                } else |_| {
                    print("\n❌ Failed to install: {s}\n", .{pkg});
                    failed += 1;
                }
            }

            print("\n🎉 Installation Summary:\n", .{});
            print("  ✅ Installed: {}\n", .{installed});
            print("  ❌ Failed: {}\n", .{failed});
            print("  📦 Total: {}\n", .{selected_indices.items.len});
        } else {
            // Batch installation (default)
            try self.installSelectedPackagesBatch(package_list, selected_indices.items, section_type);
        }
    }

    fn installSelectedPackagesBatch(self: *Self, package_list: [][]u8, selected_indices: []usize, section_type: []const u8) !void {
        print("\n🚀 Batch installing {} packages...\n", .{selected_indices.len});

        // Collect selected package names
        var selected_packages = ArrayList([]const u8){ .items = &[_][]const u8{}, .capacity = 0 };
        defer selected_packages.deinit(self.allocator);

        for (selected_indices) |idx| {
            try selected_packages.append(self.allocator, package_list[idx]);
        }

        if (std.mem.eql(u8, section_type, "native")) {
            try self.installNativePackagesBatch(selected_packages.items);
        } else if (std.mem.eql(u8, section_type, "flatpak")) {
            try self.installFlatpakPackagesBatch(selected_packages.items);
        } else {
            print("❌ Batch installation not supported for {s} packages yet\n", .{section_type});
        }
    }

    fn installNativePackagesBatch(self: *Self, package_names: []const []const u8) !void {
        const system_info = detectSystem(self.allocator) catch return error.SystemDetectionFailed;
        defer self.allocator.free(system_info.version_managers);
        defer self.allocator.free(system_info.package_sources);

        const cmd_parts = buildCommand(self.allocator, system_info, .install, package_names) catch return error.CommandBuildFailed;
        defer self.allocator.free(cmd_parts);

        print("\n🔧 Running command: ", .{});
        for (cmd_parts, 0..) |part, i| {
            if (i > 0) print(" ", .{});
            print("{s}", .{part});
        }
        print("\n\n", .{});

        var child = std.process.Child.init(cmd_parts, self.allocator);
        child.stdin_behavior = .Inherit;
        child.stdout_behavior = .Inherit;
        child.stderr_behavior = .Inherit;

        const term = child.spawnAndWait() catch {
            print("❌ Failed to execute batch installation\n", .{});
            return error.ExecutionFailed;
        };

        switch (term) {
            .Exited => |code| {
                if (code == 0) {
                    print("\n✅ Batch installation completed successfully!\n", .{});
                } else {
                    print("\n⚠️  Batch installation had failures (exit code: {})\n", .{code});
                    print("This is normal when some packages fail to build or have dependency issues.\n", .{});
                    print("\n🔧 Options to handle failed packages:\n", .{});
                    print("  1️⃣  Continue (ignore failed packages)\n", .{});
                    print("  2️⃣  Show failed packages and retry individually\n", .{});
                    print("  3️⃣  Get help with manual fixes\n", .{});
                    print("Choice [1-3] (Enter = continue): ", .{});

                    var choice_buf: [256]u8 = undefined;
                    const stdin = std.fs.File.stdin();
                    const choice_read = stdin.read(choice_buf[0..]) catch {
                        print("Continuing with successful packages...\n", .{});
                        return;
                    };

                    const choice_input = std.mem.trim(u8, choice_buf[0..choice_read], " \t\r\n");

                    if (choice_input.len > 0 and choice_input[0] == '2') {
                        try self.handleFailedPackagesRetry(package_names);
                    } else if (choice_input.len > 0 and choice_input[0] == '3') {
                        self.showPackageFailureHelp();
                    } else {
                        print("✅ Continuing with successfully installed packages.\n", .{});
                    }
                }
            },
            else => {
                print("\n❌ Batch installation failed\n", .{});
            },
        }
    }

    fn installFlatpakPackagesBatch(self: *Self, package_names: []const []const u8) !void {
        var cmd_args = ArrayList([]const u8){ .items = &[_][]const u8{}, .capacity = 0 };
        defer cmd_args.deinit(self.allocator);

        try cmd_args.append(self.allocator, "flatpak");
        try cmd_args.append(self.allocator, "install");
        try cmd_args.append(self.allocator, "--user");
        try cmd_args.append(self.allocator, "-y");

        for (package_names) |pkg| {
            try cmd_args.append(self.allocator, pkg);
        }

        var child = std.process.Child.init(cmd_args.items, self.allocator);
        child.stdin_behavior = .Inherit;
        child.stdout_behavior = .Inherit;
        child.stderr_behavior = .Inherit;

        const term = child.spawnAndWait() catch {
            print("❌ Failed to execute Flatpak batch installation\n", .{});
            return error.ExecutionFailed;
        };

        switch (term) {
            .Exited => |code| {
                if (code == 0) {
                    print("\n✅ Flatpak batch installation completed successfully!\n", .{});
                } else {
                    print("\n❌ Flatpak batch installation failed with exit code: {}\n", .{code});
                }
            },
            else => {
                print("\n❌ Flatpak batch installation failed\n", .{});
            },
        }
    }

    fn handleFailedPackagesRetry(self: *Self, package_names: []const []const u8) !void {
        print("\n🔄 Retry failed packages individually?\n", .{});
        print("This will attempt to install each package separately, skipping failures.\n", .{});
        print("Continue? [y/N]: ", .{});

        var confirm_buf: [256]u8 = undefined;
        const stdin = std.fs.File.stdin();
        const confirm_read = stdin.read(confirm_buf[0..]) catch return;
        const confirm_input = std.mem.trim(u8, confirm_buf[0..confirm_read], " \t\r\n");

        if (confirm_input.len == 0 or (confirm_input[0] != 'y' and confirm_input[0] != 'Y')) {
            return;
        }

        print("\n🚀 Retrying packages individually...\n", .{});
        var succeeded: u32 = 0;
        var failed: u32 = 0;

        for (package_names, 0..) |pkg, i| {
            print("\n[{}/{}] Trying: {s}\n", .{ i + 1, package_names.len, pkg });

            if (self.installSinglePackage(pkg, "native")) {
                print("✅ {s} installed successfully\n", .{pkg});
                succeeded += 1;
            } else |_| {
                print("❌ {s} failed - skipping\n", .{pkg});
                failed += 1;
            }
        }

        print("\n📊 Individual retry results:\n", .{});
        print("  ✅ Succeeded: {}\n", .{succeeded});
        print("  ❌ Failed: {}\n", .{failed});
        print("  📦 Total: {}\n", .{package_names.len});
    }

    fn showPackageFailureHelp(self: *Self) void {
        _ = self;
        print("\n🔧 Common AUR Package Failure Solutions:\n", .{});
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
        print("\n📋 For python-pysvn (PyCXX missing):\n", .{});
        print("  yay -S python-pycxx\n", .{});
        print("  # Then retry: yay -S python-pysvn\n", .{});
        print("\n📋 For general build failures:\n", .{});
        print("  • Check missing dependencies: yay -Si <package-name>\n", .{});
        print("  • Update system first: yay -Syu\n", .{});
        print("  • Try alternative packages: yay -Ss <search-term>\n", .{});
        print("  • Skip problematic packages and install manually later\n", .{});
        print("\n📋 For dependency conflicts:\n", .{});
        print("  • Use: yay -S --needed <package-name>\n", .{});
        print("  • Or: yay -S --overwrite '*' <package-name>\n", .{});
        print("\n💡 You can also edit your profile.json to remove problematic packages.\n", .{});
    }

    fn extractPackagesFromSection(self: *Self, section_type: []const u8) !ArrayList([]u8) {
        var package_list = ArrayList([]u8){ .items = &[_][]u8{}, .capacity = 0 };

        const search_pattern = try std.fmt.allocPrint(self.allocator, "\"{s}\": [", .{section_type});
        defer self.allocator.free(search_pattern);

        if (std.mem.indexOf(u8, self.contents, search_pattern)) |section_start| {
            const section = self.contents[section_start..];
            if (std.mem.indexOf(u8, section, "]")) |section_end| {
                const section_content = section[0..section_end];
                var lines = std.mem.splitScalar(u8, section_content, '\n');

                while (lines.next()) |line| {
                    const trimmed = std.mem.trim(u8, line, " \t\r\n");
                    if (std.mem.startsWith(u8, trimmed, "\"") and std.mem.endsWith(u8, trimmed, "\",")) {
                        const pkg_name = trimmed[1 .. trimmed.len - 2];
                        if (pkg_name.len > 0) {
                            try package_list.append(self.allocator, try self.allocator.dupe(u8, pkg_name));
                        }
                    } else if (std.mem.startsWith(u8, trimmed, "\"") and std.mem.endsWith(u8, trimmed, "\"")) {
                        const pkg_name = trimmed[1 .. trimmed.len - 1];
                        if (pkg_name.len > 0) {
                            try package_list.append(self.allocator, try self.allocator.dupe(u8, pkg_name));
                        }
                    }
                }
            }
        }

        return package_list;
    }
};

fn countPackagesInSection(contents: []const u8, section_type: []const u8) !u32 {
    var count: u32 = 0;

    const search_pattern = std.fmt.allocPrint(std.heap.page_allocator, "\"{s}\": [", .{section_type}) catch return 0;
    defer std.heap.page_allocator.free(search_pattern);

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

pub fn runInteractiveImport(allocator: Allocator, contents: []const u8, filename: []const u8) !void {
    var importer = try InteractiveImporter.init(allocator, contents, filename);
    try importer.showInteractiveMenu();
}
