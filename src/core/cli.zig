const std = @import("std");
const print = std.debug.print;

pub const Command = enum { install, search, remove, update, list, info, help, version, @"export", import, backup, recover, config, fallback_search };

pub fn parseCommand(args: []const []const u8) ?Command {
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
    if (std.mem.eql(u8, cmd, "backup")) return .backup;
    if (std.mem.eql(u8, cmd, "recover")) return .recover;
    if (std.mem.eql(u8, cmd, "config")) return .config;

    // If no known command matches, treat it as a search query (like yay does)
    return .fallback_search;
}

pub fn showHelp() void {
    print("🏠 here - Universal package manager that speaks your system's language\n\n", .{});
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
    print("                      Use --interactive for TUI selection\n", .{});
    print("                      Use --install-native, --install-flatpak, --install-appimage, or --install-all for batch installation\n", .{});
    print("  backup <source>     Smart file backup for migration\n", .{});
    print("  recover [service]   Recover services (docker, podman, postgresql) from backup\n", .{});
    print("                      Use --all to recover all services interactively\n", .{});
    print("                      Use --docker, --podman, --postgresql for specific services\n", .{});
    print("  config recovery     Configure recovery system settings\n", .{});
    print("  version             Show version information\n", .{});
    print("  help                Show this help\n\n", .{});
    print("Examples:\n", .{});
    print("  here install firefox\n", .{});
    print("  here search python\n", .{});
    print("  here remove bloatware\n", .{});
    print("  here update\n", .{});
    print("  here export my-setup.json\n", .{});
    print("  here export --include-config my-full-setup.json\n", .{});
    print("  here import my-setup.json\n", .{});
    print("  here import --interactive my-setup.json\n", .{});
    print("  here import --install-all my-setup.json\n", .{});
    print("  here backup ~ -d /mnt/backup/home\n", .{});
    print("  here recover --all\n", .{});
    print("  here recover --docker --postgresql\n", .{});
    print("  here recover postgresql\n", .{});
    print("  here config recovery\n", .{});
    print("💖 Support development: 0xaf462cef9e8913a9cb7b6f0ba0ddf5d733eae57a (ETH/Base)\n", .{});
    print("For more information, visit: https://github.com/instance-select/here\n", .{});
}

pub fn showVersion() void {
    print("here version 1.1.0\n", .{});
    print("Universal package manager with system recovery and migration\n", .{});
    print("Built with Zig 0.15.2\n", .{});
}

pub fn showUnknownCommand(command: []const u8) void {
    print("❌ Unknown command: {s}\n", .{command});
    showHelp();
}

pub fn isLikelySearchQuery(command: []const u8) bool {
    // Check if the command looks like a package name rather than a typo of a real command
    // Package names typically don't match command names and are often longer
    if (command.len < 2) return false;

    // Don't treat obvious command typos as search queries
    const common_typos = [_][]const u8{ "instal", "serach", "remov", "updat", "lis", "inf", "hel", "versio", "expor", "impor", "backu", "recov", "confi" };
    for (common_typos) |typo| {
        if (std.mem.eql(u8, command, typo)) return false;
    }

    return true;
}
