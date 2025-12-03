const std = @import("std");

// Version information
const version = "1.0.0";
const description = "Universal package manager that speaks your system's language";
const author = "here contributors";
const license = "MIT";

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Add version as a compile-time option
    const version_option = b.addOptions();
    version_option.addOption([]const u8, "version", version);
    version_option.addOption([]const u8, "description", description);
    version_option.addOption([]const u8, "author", author);
    version_option.addOption([]const u8, "license", license);

    const exe = b.addExecutable(.{
        .name = "here",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addOptions("build_options", version_option);
    b.installArtifact(exe);

    // Create run step
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Create test step
    const unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    unit_tests.root_module.addOptions("build_options", version_option);
    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    // Create static build options for different targets
    const targets = [_]std.Target.Query{
        .{ .cpu_arch = .x86_64, .os_tag = .linux },
        .{ .cpu_arch = .aarch64, .os_tag = .linux },
        .{ .cpu_arch = .x86_64, .os_tag = .macos },
        .{ .cpu_arch = .aarch64, .os_tag = .macos },
    };

    const release_step = b.step("release", "Build release binaries for all targets");

    for (targets) |t| {
        const release_exe = b.addExecutable(.{
            .name = "here",
            .root_source_file = b.path("src/main.zig"),
            .target = b.resolveTargetQuery(t),
            .optimize = .ReleaseFast,
        });

        release_exe.root_module.addOptions("build_options", version_option);
        const target_output = b.addInstallArtifact(release_exe, .{
            .dest_dir = .{
                .override = .{
                    .custom = b.fmt("release/{s}-{s}", .{ @tagName(t.cpu_arch.?), @tagName(t.os_tag.?) }),
                },
            },
        });

        release_step.dependOn(&target_output.step);
    }
}
