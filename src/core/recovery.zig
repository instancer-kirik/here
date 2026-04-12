const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const system = @import("system.zig");
const SystemInfo = system.SystemInfo;
const PackageManager = system.PackageManager;

pub const RecoveryActionType = enum {
    skip_checksums,
    install_dependencies,
    manual_intervention,
};

pub const RecoveryAction = struct {
    action_type: RecoveryActionType,
    packages_to_install: [][]const u8,
    message: []const u8,

    pub fn deinit(self: RecoveryAction, allocator: Allocator) void {
        allocator.free(self.message);
        for (self.packages_to_install) |pkg| {
            allocator.free(pkg);
        }
        allocator.free(self.packages_to_install);
    }
};

pub fn analyzeFailure(allocator: Allocator, system_info: SystemInfo, stdout: []const u8, stderr: []const u8) !?RecoveryAction {
    _ = system_info; // May be used later for PM-specific parsing
    const combined_output = try std.fmt.allocPrint(allocator, "{s}\n{s}", .{stdout, stderr});
    defer allocator.free(combined_output);

    if (std.mem.indexOf(u8, combined_output, "One or more files did not pass the validity check") != null or
        (std.mem.indexOf(u8, combined_output, "FAILED") != null and std.mem.indexOf(u8, combined_output, "sha256sums") != null)) {
        
        return RecoveryAction{
            .action_type = .skip_checksums,
            .packages_to_install = &[_][]const u8{},
            .message = try allocator.dupe(u8, "Checksum validation failed. This often happens when AUR packages are outdated but the source file changed. You can try installing while skipping checksum validation."),
        };
    }

    if (std.mem.indexOf(u8, combined_output, "Missing dependencies:") != null or
        std.mem.indexOf(u8, combined_output, "Could not resolve all dependencies") != null) {
        
        var missing_deps = ArrayList([]const u8){ .items = &[_][]const u8{}, .capacity = 0 };
        
        var lines = std.mem.splitScalar(u8, combined_output, '\n');
        var in_missing = false;
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r\n");
            
            if (std.mem.startsWith(u8, trimmed, "Missing dependencies:")) {
                in_missing = true;
                continue;
            }
            if (in_missing) {
                if (std.mem.startsWith(u8, trimmed, "-> ")) {
                    const dep = std.mem.trim(u8, trimmed[3..], " \t\r\n");
                    if (dep.len > 0) {
                        try missing_deps.append(allocator, try allocator.dupe(u8, dep));
                    }
                } else if (std.mem.startsWith(u8, trimmed, "==> ERROR:")) {
                    break;
                }
            }
        }

        if (missing_deps.items.len > 0) {
            return RecoveryAction{
                .action_type = .install_dependencies,
                .packages_to_install = try missing_deps.toOwnedSlice(allocator),
                .message = try allocator.dupe(u8, "Missing dependencies detected. We can attempt to install them first."),
            };
        } else {
            missing_deps.deinit(allocator);
        }
    }

    if (std.mem.indexOf(u8, combined_output, "A failure occurred in build()") != null or
        std.mem.indexOf(u8, combined_output, "A failure occurred in prepare()") != null) {
        return RecoveryAction{
            .action_type = .manual_intervention,
            .packages_to_install = &[_][]const u8{},
            .message = try allocator.dupe(u8, "The package failed to build or patch. This usually means the AUR recipe is broken or incompatible with the current source. Manual intervention required."),
        };
    }

    return null;
}
