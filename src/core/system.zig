const std = @import("std");
const print = std.debug.print;
const fs_compat = @import("../fs_compat.zig");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

pub const SystemInfo = struct {
    distro: Distro,
    package_manager: PackageManager,
    version_managers: []const VersionManager,
    package_sources: []const PackageSource,
};

pub const PackageSource = enum {
    native,
    flatpak,
    appimage,
    snap,
    github,

    pub fn toString(self: PackageSource) []const u8 {
        return switch (self) {
            .native => "native",
            .flatpak => "flatpak",
            .appimage => "appimage",
            .snap => "snap",
            .github => "github",
        };
    }
};

pub const VersionManager = enum {
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
            .sdkman => "sdk",
            .phpenv => "phpenv",
            .phpbrew => "phpbrew",
            .luaenv => "luaenv",
            .plenv => "plenv",
            .perlbrew => "perlbrew",
            .scalaenv => "scalaenv",
            .svm => "svm",
            .tfenv => "tfenv",
            .tgenv => "tgenv",
            .krew => "kubectl-krew",
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
            .mambaforge => "mamba",
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
        };
    }
};

pub const Distro = enum {
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

/// Maps an /etc/os-release `ID` (or `ID_LIKE` entry) to a known Distro.
/// Used both for the primary `ID=` field and as a fallback over `ID_LIKE=`,
/// so Arch/Debian/Ubuntu derivatives (CachyOS, EndeavourOS, Manjaro, Garuda,
/// Linux Mint, Pop!_OS, Armbian-based boards, etc.) resolve to a real distro
/// and get a working package manager instead of `.unknown`.
fn distroFromId(id: []const u8) ?Distro {
    if (std.mem.eql(u8, id, "arch")) return .arch;
    if (std.mem.eql(u8, id, "debian")) return .debian;
    if (std.mem.eql(u8, id, "ubuntu")) return .ubuntu;
    if (std.mem.eql(u8, id, "armbian")) return .armbian;
    if (std.mem.eql(u8, id, "opensuse") or std.mem.eql(u8, id, "opensuse-tumbleweed") or std.mem.eql(u8, id, "opensuse-leap")) return .opensuse;
    if (std.mem.eql(u8, id, "fedora")) return .fedora;
    if (std.mem.eql(u8, id, "nixos")) return .nixos;
    return null;
}

pub const PackageManager = enum {
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

pub fn detectPackageSources(allocator: Allocator) ![]const PackageSource {
    var sources = ArrayList(PackageSource){ .items = &[_]PackageSource{}, .capacity = 0 };

    // Native packages are always available if we have a package manager
    try sources.append(allocator, .native);

    // Check for Flatpak
    if (commandExists("flatpak")) {
        try sources.append(allocator, .flatpak);
    }

    // Check for Snap
    if (commandExists("snap")) {
        try sources.append(allocator, .snap);
    }

    // AppImage support is always available (no system dependency)
    try sources.append(allocator, .appimage);

    // Tagged install.sh entries. The catalog is local; the download happens on install.
    try sources.append(allocator, .github);

    return sources.toOwnedSlice(allocator);
}

pub fn detectVersionManagers(allocator: Allocator) ![]const VersionManager {
    var managers = ArrayList(VersionManager){ .items = &[_]VersionManager{}, .capacity = 0 };

    const managers_to_check = [_]VersionManager{ .asdf, .mise, .fnm, .nvm, .pyenv, .rbenv, .rustup, .kiex, .kerl, .exenv, .gvm, .g, .jenv, .jabba, .sdkman, .phpenv, .phpbrew, .luaenv, .plenv, .perlbrew, .scalaenv, .svm, .tfenv, .tgenv, .krew, .volta, .protostar, .rtx, .vfox, .ghcup, .juliaup, .zigup, .dvm, .rvm, .swiftenv, .nodenv, .pyflow, .pipenv, .conda, .mambaforge, .cargo, .npm, .yarn, .pnpm, .bun, .gem, .pip, .mix, .hex, .rebar3, .dub };

    for (managers_to_check) |manager| {
        if (commandExists(manager.toString())) {
            try managers.append(allocator, manager);
        }
    }

    return managers.toOwnedSlice(allocator);
}

pub fn detectSystem(allocator: Allocator) !SystemInfo {
    // Try to read OS release files to detect distro
    const os_release_paths = [_][]const u8{
        "/etc/os-release",
        "/usr/lib/os-release",
    };

    for (os_release_paths) |path| {
        const contents = fs_compat.readFileAlloc(allocator, path, 1024 * 1024) catch continue;
        defer allocator.free(contents);

        var distro: Distro = .unknown;
        var id_like: []const u8 = "";
        var lines = std.mem.splitScalar(u8, contents, '\n');
        while (lines.next()) |line| {
            if (std.mem.startsWith(u8, line, "ID=")) {
                const id = std.mem.trim(u8, line[3..], "\"");
                distro = distroFromId(id) orelse .unknown;
            } else if (std.mem.startsWith(u8, line, "ID_LIKE=")) {
                id_like = std.mem.trim(u8, line["ID_LIKE=".len..], "\"");
            }
        }

        // Derivatives (CachyOS, EndeavourOS, Manjaro, Garuda, Linux Mint, Pop!_OS,
        // etc.) set their own ID but declare their base distro via ID_LIKE, which
        // can list multiple space-separated values (e.g. "ubuntu debian" or just
        // "arch"). Fall back to the first ID_LIKE entry we recognize so these
        // still get a working package manager instead of landing on .unknown.
        if (distro == .unknown and id_like.len > 0) {
            var like_iter = std.mem.splitScalar(u8, id_like, ' ');
            while (like_iter.next()) |like_id| {
                if (distroFromId(like_id)) |matched| {
                    distro = matched;
                    break;
                }
            }
        }

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

    // Fallback if no os-release file found
    const package_manager = detectPackageManager(.unknown);
    const version_managers = try detectVersionManagers(allocator);
    const package_sources = try detectPackageSources(allocator);

    return SystemInfo{
        .distro = .unknown,
        .package_manager = package_manager,
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

pub fn commandExists(command: []const u8) bool {
    var child = fs_compat.Child.init(&[_][]const u8{ "which", command }, std.heap.page_allocator);
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;

    const term = child.spawnAndWait() catch return false;
    return term == .Exited and term.Exited == 0;
}
