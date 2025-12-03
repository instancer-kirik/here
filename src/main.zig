const std = @import("std");
const print = std.debug.print;
const build_options = @import("build_options");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const appimage = @import("appimage.zig");
const appman = @import("appman_integration.zig");

const SystemInfo = struct {
    distro: Distro,
    package_manager: PackageManager,
    version_managers: []const VersionManager,
    package_sources: []const PackageSource,
};

const PackageSource = enum {
    native,
    flatpak,
    appimage,
    snap,

    pub fn toString(self: PackageSource) []const u8 {
        return switch (self) {
            .native => "native",
            .flatpak => "flatpak",
            .appimage => "appimage",
            .snap => "snap",
        };
    }
};

const PackageMatch = struct {
    name: []const u8,
    source: PackageSource,
    id: []const u8,
};

const VersionManager = enum {
    asdf,
    mise,
    fnm,
    nvm,
    pyenv,
    rbenv,
    rustup,
    kiex,
    kerl,
    exenv,
    gvm,
    g,
    jenv,
    jabba,
    sdkman,
    phpenv,
    phpbrew,
    luaenv,
    plenv,
    perlbrew,
    scalaenv,
    svm,
    tfenv,
    tgenv,
    krew,
    volta,
    protostar,
    rtx,
    vfox,
    ghcup,
    juliaup,
    zigup,
    dvm,
    rvm,
    swiftenv,
    nodenv,
    pyflow,
    pipenv,
    conda,
    mambaforge,
    cargo,
    npm,
    yarn,
    pnpm,
    bun,
    gem,
    pip,
    mix,
    hex,
    rebar3,
    dub,
    none,

    pub fn toString(self: VersionManager) []const u8 {
        return switch (self) {
            .asdf => "asdf",
            .mise => "mise",
            .fnm => "fnm",
            .nvm => "nvm",
            .pyenv => "pyenv",
            .rbenv => "rbenv",
            .rustup => "rustup",
            .kiex => "kiex",
            .kerl => "kerl",
            .exenv => "exenv",
            .gvm => "gvm",
            .g => "g",
            .jenv => "jenv",
            .jabba => "jabba",
            .sdkman => "sdkman",
            .phpenv => "phpenv",
            .phpbrew => "phpbrew",
            .luaenv => "luaenv",
            .plenv => "plenv",
            .perlbrew => "perlbrew",
            .scalaenv => "scalaenv",
            .svm => "svm",
            .tfenv => "tfenv",
            .tgenv => "tgenv",
            .krew => "krew",
            .volta => "volta",
            .protostar => "protostar",
            .rtx => "rtx",
            .vfox => "vfox",
            .ghcup => "ghcup",
            .juliaup => "juliaup",
            .zigup => "zigup",
            .dvm => "dvm",
            .rvm => "rvm",
            .swiftenv => "swiftenv",
            .nodenv => "nodenv",
            .pyflow => "pyflow",
            .pipenv => "pipenv",
            .conda => "conda",
            .mambaforge => "mambaforge",
            .cargo => "cargo",
            .npm => "npm",
            .yarn => "yarn",
            .pnpm => "pnpm",
            .bun => "bun",
            .gem => "gem",
            .pip => "pip",
            .mix => "mix",
            .hex => "hex",
            .rebar3 => "rebar3",
            .dub => "dub",
            .none => "none",
        };
    }
};

const Distro = enum {
    arch,
    debian,
    ubuntu,
    armbian,
    opensuse,
    fedora,
    nixos,
    unknown,

    pub fn toString(self: Distro) []const u8 {
        return switch (self) {
            .arch => "Arch Linux",
            .debian => "Debian",
            .ubuntu => "Ubuntu",
            .armbian => "Armbian",
            .opensuse => "openSUSE",
            .fedora => "Fedora",
            .nixos => "NixOS",
            .unknown => "Unknown",
        };
    }
};

const PackageManager = enum {
    yay,
    paru,
    pacman,
    apt,
    zypper,
    dnf,
    nix,
    unknown,

    pub fn toString(self: PackageManager) []const u8 {
        return switch (self) {
            .yay => "yay",
            .paru => "paru",
            .pacman => "pacman",
            .apt => "apt",
            .zypper => "zypper",
            .dnf => "dnf",
            .nix => "nix",
            .unknown => "unknown",
        };
    }
};

const Command = enum { install, search, remove, update, list, info, help, version, @"export", import };

const DevelopmentTool = enum {
    node,
    python,
    ruby,
    rust,
    go,
    java,
    other,

    pub fn getVersionManagers(self: DevelopmentTool) []const VersionManager {
        return switch (self) {
            .node => &[_]VersionManager{ .fnm, .nvm, .asdf, .mise },
            .python => &[_]VersionManager{ .pyenv, .asdf, .mise },
            .ruby => &[_]VersionManager{ .rbenv, .asdf, .mise },
            .rust => &[_]VersionManager{.rustup},
            .go => &[_]VersionManager{ .asdf, .mise },
            .java => &[_]VersionManager{ .asdf, .mise },
            .other => &[_]VersionManager{ .asdf, .mise },
        };
    }
};

fn detectPackageSources(allocator: Allocator) ![]const PackageSource {
    var sources = ArrayList(PackageSource).init(allocator);

    // Native packages are always available if we have a package manager
    try sources.append(.native);

    // Check for Flatpak
    if (commandExists("flatpak")) {
        try sources.append(.flatpak);
    }

    // AppImage support is always available since it uses web APIs and AppMan
    // Only requires curl which is checked elsewhere
    if (commandExists("curl")) {
        try sources.append(.appimage);
    }

    // Check for Snap
    if (commandExists("snap")) {
        try sources.append(.snap);
    }

    return sources.toOwnedSlice();
}

fn detectVersionManagers(allocator: Allocator) ![]const VersionManager {
    var managers = ArrayList(VersionManager).init(allocator);

    const managers_to_check = [_]VersionManager{ .asdf, .mise, .fnm, .nvm, .pyenv, .rbenv, .rustup, .kiex, .kerl, .exenv, .gvm, .g, .jenv, .jabba, .sdkman, .phpenv, .phpbrew, .luaenv, .plenv, .perlbrew, .scalaenv, .svm, .tfenv, .tgenv, .krew, .volta, .protostar, .rtx, .vfox, .ghcup, .juliaup, .zigup, .dvm, .rvm, .swiftenv, .nodenv, .pyflow, .pipenv, .conda, .mambaforge, .cargo, .npm, .yarn, .pnpm, .bun, .gem, .pip, .mix, .hex, .rebar3, .dub };

    for (managers_to_check) |manager| {
        if (commandExists(manager.toString())) {
            try managers.append(manager);
        }
    }

    return managers.toOwnedSlice();
}

fn detectSystem(allocator: Allocator) !SystemInfo {
    // Try to read OS release files to detect distro
    const os_release_paths = [_][]const u8{
        "/etc/os-release",
        "/usr/lib/os-release",
    };

    for (os_release_paths) |path| {
        const file = std.fs.openFileAbsolute(path, .{}) catch continue;
        defer file.close();

        const contents = file.readToEndAlloc(allocator, 1024 * 1024) catch continue;
        defer allocator.free(contents);

        var distro: Distro = .unknown;

        // Parse os-release file
        var lines = std.mem.splitScalar(u8, contents, '\n');
        while (lines.next()) |line| {
            if (std.mem.startsWith(u8, line, "ID=")) {
                const id = std.mem.trim(u8, line[3..], "\"");
                if (std.mem.eql(u8, id, "arch")) {
                    distro = .arch;
                } else if (std.mem.eql(u8, id, "debian")) {
                    distro = .debian;
                } else if (std.mem.eql(u8, id, "ubuntu")) {
                    distro = .ubuntu;
                } else if (std.mem.eql(u8, id, "armbian")) {
                    distro = .armbian;
                } else if (std.mem.eql(u8, id, "opensuse") or std.mem.eql(u8, id, "opensuse-leap") or std.mem.eql(u8, id, "opensuse-tumbleweed")) {
                    distro = .opensuse;
                } else if (std.mem.eql(u8, id, "fedora")) {
                    distro = .fedora;
                } else if (std.mem.eql(u8, id, "nixos")) {
                    distro = .nixos;
                }
                break;
            }
        }

        // Detect available package manager
        const package_manager = detectPackageManager(distro);

        const version_managers = try detectVersionManagers(allocator);
        const package_sources = try detectPackageSources(allocator);

        return SystemInfo{
            .distro = distro,
            .package_manager = package_manager,
            .version_managers = version_managers,
            .package_sources = package_sources,
        };
    }

    const version_managers = try detectVersionManagers(allocator);
    const package_sources = try detectPackageSources(allocator);

    return SystemInfo{
        .distro = .unknown,
        .package_manager = .unknown,
        .version_managers = version_managers,
        .package_sources = package_sources,
    };
}

fn detectPackageManager(distro: Distro) PackageManager {
    // Check which package managers are available
    const managers_to_check = switch (distro) {
        .arch => &[_]PackageManager{ .yay, .paru, .pacman },
        .debian, .ubuntu, .armbian => &[_]PackageManager{.apt},
        .opensuse => &[_]PackageManager{.zypper},
        .fedora => &[_]PackageManager{.dnf},
        .nixos => &[_]PackageManager{.nix},
        .unknown => &[_]PackageManager{ .yay, .paru, .pacman, .apt, .zypper, .dnf, .nix },
    };

    for (managers_to_check) |manager| {
        if (commandExists(manager.toString())) {
            return manager;
        }
    }

    return .unknown;
}

fn commandExists(command: []const u8) bool {
    var child = std.process.Child.init(&[_][]const u8{ "which", command }, std.heap.page_allocator);
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;

    const term = child.spawnAndWait() catch return false;
    return term == .Exited and term.Exited == 0;
}

fn parseCommand(args: []const []const u8) ?Command {
    if (args.len < 2) return null;

    const cmd = args[1];
    if (std.mem.eql(u8, cmd, "install")) return .install;
    if (std.mem.eql(u8, cmd, "search")) return .search;
    if (std.mem.eql(u8, cmd, "remove")) return .remove;
    if (std.mem.eql(u8, cmd, "update")) return .update;
    if (std.mem.eql(u8, cmd, "list")) return .list;
    if (std.mem.eql(u8, cmd, "info")) return .info;
    if (std.mem.eql(u8, cmd, "help")) return .help;
    if (std.mem.eql(u8, cmd, "version")) return .version;
    if (std.mem.eql(u8, cmd, "export")) return .@"export";
    if (std.mem.eql(u8, cmd, "import")) return .import;

    return null;
}

fn isDevelopmentTool(package: []const u8) ?DevelopmentTool {
    if (std.mem.eql(u8, package, "node") or std.mem.eql(u8, package, "nodejs")) return .node;
    if (std.mem.eql(u8, package, "python") or std.mem.eql(u8, package, "python3")) return .python;
    if (std.mem.eql(u8, package, "ruby")) return .ruby;
    if (std.mem.eql(u8, package, "rust") or std.mem.eql(u8, package, "cargo")) return .rust;
    if (std.mem.eql(u8, package, "go") or std.mem.eql(u8, package, "golang")) return .go;
    if (std.mem.eql(u8, package, "java") or std.mem.eql(u8, package, "openjdk")) return .java;
    return null;
}

fn suggestVersionManager(system: SystemInfo, tool: DevelopmentTool, package: []const u8) void {
    const preferred_managers = tool.getVersionManagers();

    // Check if we already have a suitable version manager
    for (system.version_managers) |vm| {
        for (preferred_managers) |preferred| {
            if (vm == preferred) {
                print("💡 Detected {s} - consider: {s} install {s} latest\n", .{ vm.toString(), vm.toString(), package });
                return;
            }
        }
    }

    // Suggest Nix if available (great for dev environments)
    if (system.package_manager == .nix) {
        switch (tool) {
            .node => print("💡 Nix option: nix shell nixpkgs#nodejs\n", .{}),
            .python => print("💡 Nix option: nix shell nixpkgs#python3\n", .{}),
            .rust => print("💡 Nix option: nix shell nixpkgs#rustc nixpkgs#cargo\n", .{}),
            .go => print("💡 Nix option: nix shell nixpkgs#go\n", .{}),
            .java => print("💡 Nix option: nix shell nixpkgs#jdk\n", .{}),
            else => {},
        }
    }

    // Suggest installing a version manager
    if (preferred_managers.len > 0) {
        print("💡 For {s}, consider installing a version manager first:\n", .{package});
        print("   Recommended: here install {s}\n", .{preferred_managers[0].toString()});
    }
}

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
    const date_str = try std.fmt.allocPrint(allocator, "{}", .{timestamp});
    defer allocator.free(date_str);

    // Detect system info
    const system = detectSystem(allocator) catch |err| {
        print("❌ Failed to detect system: {}\n", .{err});
        return;
    };
    defer allocator.free(system.version_managers);
    defer allocator.free(system.package_sources);

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
    var native_packages = std.ArrayList([]const u8).init(allocator);
    defer {
        for (native_packages.items) |pkg| allocator.free(pkg);
        native_packages.deinit();
    }

    var flatpak_packages = std.ArrayList([]const u8).init(allocator);
    defer {
        for (flatpak_packages.items) |pkg| allocator.free(pkg);
        flatpak_packages.deinit();
    }

    var appimage_packages = std.ArrayList([]const u8).init(allocator);
    defer {
        for (appimage_packages.items) |pkg| allocator.free(pkg);
        appimage_packages.deinit();
    }

    var vm_packages = std.ArrayList([]const u8).init(allocator);
    defer {
        for (vm_packages.items) |pkg| allocator.free(pkg);
        vm_packages.deinit();
    }

    // Config data collections (if needed)
    var dotfiles = std.ArrayList([]const u8).init(allocator);
    defer {
        for (dotfiles.items) |item| allocator.free(item);
        dotfiles.deinit();
    }

    var xdg_config = std.ArrayList([]const u8).init(allocator);
    defer {
        for (xdg_config.items) |item| allocator.free(item);
        xdg_config.deinit();
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
                try dotfiles.append(owned_name);
            } else |_| {}
        }

        // Collect XDG config directories
        const config_dirs = [_][]const u8{ ".config/nvim", ".config/git", ".config/Code", ".config/alacritty", ".config/zsh", ".config/tmux", ".config/fontconfig", ".config/awesome", ".config/fish", ".config/starship.toml" };

        for (config_dirs) |config_path| {
            if (home_dir.access(config_path, .{})) {
                const owned_name = try allocator.dupe(u8, config_path);
                try xdg_config.append(owned_name);
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
    for (system.package_sources) |source| {
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
        try vm_packages.append(vm_name);
    }

    // Create profile JSON manually (simple approach)
    const profile_file = std.fs.cwd().createFile(profile_name, .{}) catch |err| {
        print("❌ Failed to create profile file: {}\n", .{err});
        return;
    };
    defer profile_file.close();

    const writer = profile_file.writer();
    try writer.writeAll("{\n");
    try writer.print("  \"created\": \"{s}\",\n", .{date_str});
    try writer.writeAll("  \"system\": {\n");
    try writer.print("    \"distro\": \"{s}\",\n", .{system.distro.toString()});
    try writer.print("    \"package_manager\": \"{s}\",\n", .{system.package_manager.toString()});
    try writer.print("    \"arch\": \"{s}\",\n", .{arch});
    try writer.print("    \"kernel\": \"{s}\"\n", .{kernel});
    try writer.writeAll("  },\n");
    try writer.writeAll("  \"packages\": {\n");

    // Native packages
    try writer.writeAll("    \"native\": [\n");
    for (native_packages.items, 0..) |pkg, i| {
        if (i > 0) try writer.writeAll(",\n");
        try writer.print("      \"{s}\"", .{pkg});
    }
    try writer.writeAll("\n    ],\n");

    // Flatpak packages
    try writer.writeAll("    \"flatpak\": [\n");
    for (flatpak_packages.items, 0..) |pkg, i| {
        if (i > 0) try writer.writeAll(",\n");
        try writer.print("      \"{s}\"", .{pkg});
    }
    try writer.writeAll("\n    ],\n");

    // AppImage packages
    try writer.writeAll("    \"appimage\": [\n");
    for (appimage_packages.items, 0..) |pkg, i| {
        if (i > 0) try writer.writeAll(",\n");
        try writer.print("      \"{s}\"", .{pkg});
    }
    try writer.writeAll("\n    ],\n");

    // Version managers
    try writer.writeAll("    \"version_managers\": [\n");
    for (vm_packages.items, 0..) |pkg, i| {
        if (i > 0) try writer.writeAll(",\n");
        try writer.print("      \"{s}\"", .{pkg});
    }
    try writer.writeAll("\n    ]\n");

    try writer.writeAll("  }");

    // Add config section if included
    if (include_config) {
        try writer.writeAll(",\n  \"config\": {\n");

        try writer.writeAll("    \"dotfiles\": [\n");
        for (dotfiles.items, 0..) |file, i| {
            if (i > 0) try writer.writeAll(",\n");
            try writer.print("      \"{s}\"", .{file});
        }
        try writer.writeAll("\n    ],\n");

        try writer.writeAll("    \"xdg_config\": [\n");
        for (xdg_config.items, 0..) |dir, i| {
            if (i > 0) try writer.writeAll(",\n");
            try writer.print("      \"{s}\"", .{dir});
        }
        try writer.writeAll("\n    ],\n");

        try writer.writeAll("    \"ssh_keys\": ");
        try writer.writeAll(if (has_ssh_keys) "true" else "false");
        try writer.writeAll(",\n    \"git_config\": ");
        try writer.writeAll(if (has_git_config) "true" else "false");
        try writer.writeAll("\n");
        try writer.writeAll("  }\n");
    } else {
        try writer.writeAll("\n");
    }

    try writer.writeAll("}\n");

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

fn collectNativePackages(allocator: Allocator, system: SystemInfo, packages: *std.ArrayList([]const u8)) !void {
    const cmd = switch (system.package_manager) {
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
            try packages.append(owned_name);
        }
    }
}

fn collectFlatpakPackages(allocator: Allocator, packages: *std.ArrayList([]const u8)) !void {
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
        try packages.append(owned_name);
    }
}

fn collectAppImagePackages(allocator: Allocator, packages: *std.ArrayList([]const u8)) !void {
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
                    try packages.append(owned_name);
                    appman_found = true;
                }
            }
        }
    }

    // Also scan filesystem for AppImages not managed by AppMan
    collectAppImageFromFilesystem(allocator, packages) catch {};
}

fn collectAppImageFromFilesystem(allocator: Allocator, packages: *std.ArrayList([]const u8)) !void {
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
    scanDirectoryForAppImages(allocator, "/usr/local/bin", packages) catch {};
    scanDirectoryForAppImages(allocator, "/opt", packages) catch {};
}

fn scanDirectoryForAppImages(allocator: Allocator, dir_path: []const u8, packages: *std.ArrayList([]const u8)) !void {
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
                try packages.append(owned_name);
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

fn searchFlatpak(allocator: Allocator, package_name: []const u8) !void {
    print("📦 Flatpak results:\n", .{});
    var cmd_parts = ArrayList([]const u8).init(allocator);
    defer cmd_parts.deinit();

    try cmd_parts.append("flatpak");
    try cmd_parts.append("search");
    try cmd_parts.append(package_name);

    const cmd_slice = try cmd_parts.toOwnedSlice();
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
    var cmd_parts = ArrayList([]const u8).init(allocator);
    defer cmd_parts.deinit();

    try cmd_parts.append("flatpak");
    try cmd_parts.append("search");
    try cmd_parts.append(query);

    const cmd_slice = try cmd_parts.toOwnedSlice();
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
    var cmd_parts = ArrayList([]const u8).init(allocator);
    defer cmd_parts.deinit();

    try cmd_parts.append("flatpak");
    try cmd_parts.append("install");
    try cmd_parts.append("flathub");
    try cmd_parts.append(package);
    try cmd_parts.append("-y");

    const cmd_slice = try cmd_parts.toOwnedSlice();
    defer allocator.free(cmd_slice);

    var child = std.process.Child.init(cmd_slice, allocator);
    const term = child.spawnAndWait() catch return false;

    return switch (term) {
        .Exited => |code| code == 0,
        else => false,
    };
}

fn buildCommand(allocator: Allocator, system: SystemInfo, command: Command, packages: []const []const u8) ![][]const u8 {
    var cmd_parts = ArrayList([]const u8).init(allocator);

    switch (system.package_manager) {
        .yay, .paru => {
            try cmd_parts.append(system.package_manager.toString());
            switch (command) {
                .install => {
                    try cmd_parts.append("-S");
                    for (packages) |pkg| try cmd_parts.append(pkg);
                },
                .search => {
                    try cmd_parts.append("-Ss");
                    for (packages) |pkg| try cmd_parts.append(pkg);
                },
                .remove => {
                    try cmd_parts.append("-R");
                    for (packages) |pkg| try cmd_parts.append(pkg);
                },
                .update => {
                    try cmd_parts.append("-Syu");
                },
                else => return error.UnsupportedCommand,
            }
        },
        .pacman => {
            try cmd_parts.append("sudo");
            try cmd_parts.append("pacman");
            switch (command) {
                .install => {
                    try cmd_parts.append("-S");
                    for (packages) |pkg| try cmd_parts.append(pkg);
                },
                .search => {
                    try cmd_parts.append("-Ss");
                    for (packages) |pkg| try cmd_parts.append(pkg);
                },
                .remove => {
                    try cmd_parts.append("-R");
                    for (packages) |pkg| try cmd_parts.append(pkg);
                },
                .update => {
                    try cmd_parts.append("-Syu");
                },
                else => return error.UnsupportedCommand,
            }
        },
        .apt => {
            try cmd_parts.append("sudo");
            try cmd_parts.append("apt");
            switch (command) {
                .install => {
                    try cmd_parts.append("install");
                    for (packages) |pkg| try cmd_parts.append(pkg);
                },
                .search => {
                    try cmd_parts.append("search");
                    for (packages) |pkg| try cmd_parts.append(pkg);
                },
                .remove => {
                    try cmd_parts.append("remove");
                    for (packages) |pkg| try cmd_parts.append(pkg);
                },
                .update => {
                    try cmd_parts.append("update");
                    try cmd_parts.append("&&");
                    try cmd_parts.append("sudo");
                    try cmd_parts.append("apt");
                    try cmd_parts.append("upgrade");
                },
                else => return error.UnsupportedCommand,
            }
        },
        .zypper => {
            try cmd_parts.append("sudo");
            try cmd_parts.append("zypper");
            switch (command) {
                .install => {
                    try cmd_parts.append("install");
                    for (packages) |pkg| try cmd_parts.append(pkg);
                },
                .search => {
                    try cmd_parts.append("search");
                    for (packages) |pkg| try cmd_parts.append(pkg);
                },
                .remove => {
                    try cmd_parts.append("remove");
                    for (packages) |pkg| try cmd_parts.append(pkg);
                },
                .update => {
                    try cmd_parts.append("refresh");
                    try cmd_parts.append("&&");
                    try cmd_parts.append("sudo");
                    try cmd_parts.append("zypper");
                    try cmd_parts.append("update");
                },
                else => return error.UnsupportedCommand,
            }
        },
        .dnf => {
            try cmd_parts.append("sudo");
            try cmd_parts.append("dnf");
            switch (command) {
                .install => {
                    try cmd_parts.append("install");
                    for (packages) |pkg| try cmd_parts.append(pkg);
                },
                .search => {
                    try cmd_parts.append("search");
                    for (packages) |pkg| try cmd_parts.append(pkg);
                },
                .remove => {
                    try cmd_parts.append("remove");
                    for (packages) |pkg| try cmd_parts.append(pkg);
                },
                .update => {
                    try cmd_parts.append("update");
                },
                else => return error.UnsupportedCommand,
            }
        },
        .nix => {
            try cmd_parts.append("nix");
            switch (command) {
                .install => {
                    // Use modern nix profile install
                    try cmd_parts.append("profile");
                    try cmd_parts.append("install");
                    for (packages) |pkg| {
                        // Smart package resolution - try nixpkgs# prefix for common packages
                        if (std.mem.eql(u8, pkg, "firefox") or
                            std.mem.eql(u8, pkg, "git") or
                            std.mem.eql(u8, pkg, "curl") or
                            std.mem.eql(u8, pkg, "wget") or
                            std.mem.eql(u8, pkg, "vim") or
                            std.mem.eql(u8, pkg, "emacs") or
                            std.mem.eql(u8, pkg, "nodejs") or
                            std.mem.eql(u8, pkg, "python") or
                            std.mem.eql(u8, pkg, "rust") or
                            std.mem.eql(u8, pkg, "go"))
                        {
                            const prefixed = try std.fmt.allocPrint(allocator, "nixpkgs#{s}", .{pkg});
                            try cmd_parts.append(prefixed);
                        } else {
                            try cmd_parts.append(pkg);
                        }
                    }
                },
                .search => {
                    try cmd_parts.append("search");
                    try cmd_parts.append("nixpkgs");
                    for (packages) |pkg| try cmd_parts.append(pkg);
                },
                .remove => {
                    try cmd_parts.append("profile");
                    try cmd_parts.append("remove");
                    for (packages) |pkg| try cmd_parts.append(pkg);
                },
                .update => {
                    try cmd_parts.append("profile");
                    try cmd_parts.append("upgrade");
                    try cmd_parts.append(".*");
                },
                .list => {
                    try cmd_parts.append("profile");
                    try cmd_parts.append("list");
                },
                else => return error.UnsupportedCommand,
            }
        },
        else => return error.UnsupportedPackageManager,
    }

    return cmd_parts.toOwnedSlice();
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
    print("For more information: https://github.com/instance-select/here\n", .{});
}

fn printHelp() void {
    print("🏠 here - {s}\n\n", .{build_options.description});
    print("Usage: here <command> [packages...]\n\n", .{});
    print("Commands:\n", .{});
    print("  install <packages>   Install packages\n", .{});
    print("  search <term>        Search for packages\n", .{});
    print("  remove <packages>    Remove packages\n", .{});
    print("  update              Update all packages\n", .{});
    print("  list                List installed packages\n", .{});
    print("  info <package>      Show package information\n", .{});
    print("  export [file]       Create package export profile for migration\n", .{});
    print("                      Use --include-config to include dotfiles and configs\n", .{});
    print("  import <file>       Import and install packages from profile\n", .{});
    print("  version             Show version information\n", .{});
    print("  help                Show this help\n\n", .{});
    print("Examples:\n", .{});
    print("  here install firefox\n", .{});
    print("  here search python\n", .{});
    print("  here remove bloatware\n", .{});
    print("  here update\n", .{});
    print("  here export my-setup.json\n", .{});
    print("  here export --include-config my-full-setup.json\n", .{});
    print("  here import my-setup.json\n\n", .{});
    print("💖 Support development: 0xaf462cef9e8913a9cb7b6f0ba0ddf5d733eae57a (ETH/Base)\n", .{});
    print("For more information, visit: https://github.com/instance-select/here\n", .{});
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    // Convert args to proper type
    var string_args = std.ArrayList([]const u8).init(allocator);
    defer string_args.deinit();
    for (args) |arg| {
        try string_args.append(arg);
    }
    const converted_args = try string_args.toOwnedSlice();
    defer allocator.free(converted_args);

    if (args.len < 2) {
        printHelp();
        return;
    }

    const command = parseCommand(converted_args) orelse {
        print("❌ Unknown command: {s}\n", .{converted_args[1]});
        printHelp();
        return;
    };

    if (command == .help) {
        printHelp();
        return;
    }

    if (command == .version) {
        printVersion();
        return;
    }

    // Detect system
    const system = detectSystem(allocator) catch |err| {
        print("❌ Failed to detect system: {}\n", .{err});
        return;
    };
    defer allocator.free(system.version_managers);
    defer allocator.free(system.package_sources);

    if (system.package_manager == .unknown and system.package_sources.len == 0) {
        print("❌ No supported package sources found\n", .{});
        print("💡 Supported: yay, paru, pacman, apt, zypper, dnf, nix, flatpak, snap\n", .{});
        return;
    }

    print("🔍 Detected {s}", .{system.distro.toString()});
    if (system.package_manager != .unknown) {
        print(" with {s}", .{system.package_manager.toString()});
    }
    print("\n", .{});

    if (system.package_sources.len > 0) {
        print("📦 Package sources: ", .{});
        for (system.package_sources, 0..) |src, i| {
            if (i > 0) print(", ", .{});
            print("{s}", .{src.toString()});
        }
        print("\n", .{});
    }

    if (system.version_managers.len > 0) {
        print("🔧 Version managers: ", .{});
        for (system.version_managers, 0..) |vm, i| {
            if (i > 0) print(", ", .{});
            print("{s}", .{vm.toString()});
        }
        print("\n", .{});
    }

    // Get packages from remaining args
    const packages = if (converted_args.len > 2) converted_args[2..] else &[_][]const u8{};

    if (command != .update and command != .@"export" and command != .import and packages.len == 0) {
        print("❌ No packages specified\n", .{});
        return;
    }

    if (command == .@"export") {
        var include_config = false;
        var filename: ?[]const u8 = null;

        // Parse export arguments
        for (packages) |arg| {
            if (std.mem.eql(u8, arg, "--include-config")) {
                include_config = true;
            } else if (!std.mem.startsWith(u8, arg, "--")) {
                filename = arg;
            }
        }

        exportProfile(allocator, filename, include_config) catch |err| {
            print("❌ Failed to create export profile: {}\n", .{err});
        };
        return;
    }

    if (command == .import) {
        if (packages.len == 0) {
            print("❌ No profile file specified\n", .{});
            print("💡 Usage: here import <profile.json>\n", .{});
            return;
        }

        importProfile(allocator, packages[0]) catch |err| {
            print("❌ Failed to import profile: {}\n", .{err});
        };
        return;
    }

    // Handle search across multiple package sources
    if (command == .search) {
        print("\n", .{});

        // Search native packages first
        if (system.package_manager != .unknown) {
            print("🏠 Native packages:\n", .{});
            const cmd_parts = buildCommand(allocator, system, command, packages) catch |err| {
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
        for (system.package_sources) |source| {
            switch (source) {
                .flatpak => {
                    print("\n", .{});
                    searchFlatpak(allocator, packages[0]) catch {};
                },
                .appimage => {
                    print("\n", .{});
                    searchAppImage(allocator, packages[0]) catch {};
                },
                else => {},
            }
        }
        return;
    }

    // Check if any packages are development tools that might benefit from version managers
    if (command == .install) {
        for (packages) |pkg| {
            if (isDevelopmentTool(pkg)) |tool| {
                suggestVersionManager(system, tool, pkg);

                // Read user input
                print("🤔 Continue with system package manager? [y/N]: ", .{});
                const stdin = std.io.getStdIn().reader();
                var buf: [256]u8 = undefined;
                if (stdin.readUntilDelimiterOrEof(buf[0..], '\n') catch null) |input| {
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
        if (system.package_manager != .unknown) {
            const cmd_parts = buildCommand(allocator, system, command, packages) catch |err| {
                print("❌ Failed to build native command: {}\n", .{err});

                // Try alternative sources as fallback
                for (system.package_sources) |source| {
                    if (packages.len > 0) {
                        switch (source) {
                            .flatpak => {
                                print("🔄 Trying Flatpak...\n", .{});

                                // First try direct install with the given name
                                if (installFlatpak(allocator, packages[0]) catch false) {
                                    print("✅ Installed via Flatpak\n", .{});
                                    return;
                                }

                                // If that fails, try to find a matching Flatpak ID
                                if (findFlatpakMatch(allocator, packages[0]) catch null) |flatpak_id| {
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
                                if (installAppImage(allocator, packages[0]) catch false) {
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
                for (system.package_sources) |source| {
                    if (source == .flatpak and packages.len > 0) {
                        print("🔄 Trying Flatpak...\n", .{});

                        // First try direct install with the given name
                        if (installFlatpak(allocator, packages[0]) catch false) {
                            print("✅ Installed via Flatpak\n", .{});
                            return;
                        }

                        // If that fails, try to find a matching Flatpak ID
                        if (findFlatpakMatch(allocator, packages[0]) catch null) |flatpak_id| {
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
                        for (system.package_sources) |source| {
                            if (source == .flatpak and packages.len > 0) {
                                print("🔄 Trying Flatpak...\n", .{});

                                // First try direct install with the given name
                                if (installFlatpak(allocator, packages[0]) catch false) {
                                    print("✅ Installed via Flatpak\n", .{});
                                    return;
                                }

                                // If that fails, try to find a matching Flatpak ID
                                if (findFlatpakMatch(allocator, packages[0]) catch null) |flatpak_id| {
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
        for (system.package_sources) |source| {
            if (packages.len > 0) {
                switch (source) {
                    .flatpak => {
                        print("🚀 Installing via Flatpak: {s}\n", .{packages[0]});

                        // First try direct install
                        if (installFlatpak(allocator, packages[0]) catch false) {
                            print("✅ Installed via Flatpak\n", .{});
                            return;
                        }

                        // If that fails, try to find a matching Flatpak ID
                        if (findFlatpakMatch(allocator, packages[0]) catch null) |flatpak_id| {
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
                        print("🚀 Installing via AppMan/AppImage: {s}\n", .{packages[0]});
                        if (installAppImage(allocator, packages[0]) catch false) {
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

    // Handle list command with AppImage support
    if (command == .list) {
        // Show native packages first
        if (system.package_manager != .unknown) {
            const cmd_parts = buildCommand(allocator, system, command, packages) catch |err| {
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
        for (system.package_sources) |source| {
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
    if (system.package_manager == .unknown) {
        print("❌ No supported package manager found for this operation\n", .{});
        return;
    }

    const cmd_parts = buildCommand(allocator, system, command, packages) catch |err| {
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
            }
        },
        else => {
            print("❌ Command terminated unexpectedly\n", .{});
        },
    }
}
