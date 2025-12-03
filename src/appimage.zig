const std = @import("std");
const print = std.debug.print;
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

pub const AppImageError = error{
    NetworkError,
    ParseError,
    DownloadError,
    FileSystemError,
    NotFound,
    InvalidResponse,
};

pub const AppImageRelease = struct {
    name: []const u8,
    download_url: []const u8,
    version: []const u8,
    size: u64,
    published_at: []const u8,

    pub fn deinit(self: AppImageRelease, allocator: Allocator) void {
        allocator.free(self.name);
        allocator.free(self.download_url);
        allocator.free(self.version);
        allocator.free(self.published_at);
    }
};

pub const AppImageRegistry = struct {
    // Popular AppImage repositories with their GitHub repo paths
    const KNOWN_APPS = [_]struct { name: []const u8, repo: []const u8, binary_name: ?[]const u8 }{
        .{ .name = "obsidian", .repo = "obsidianmd/obsidian-releases", .binary_name = "Obsidian" },
        .{ .name = "vscodium", .repo = "VSCodium/vscodium", .binary_name = "VSCodium" },
        .{ .name = "balenaetcher", .repo = "balena-io/etcher", .binary_name = "balenaEtcher" },
        .{ .name = "standardnotes", .repo = "standardnotes/app", .binary_name = "standard-notes" },
        .{ .name = "joplin", .repo = "laurent22/joplin", .binary_name = "Joplin" },
        .{ .name = "drawio", .repo = "jgraph/drawio-desktop", .binary_name = "draw.io" },
        .{ .name = "discord", .repo = "discord/discord", .binary_name = null }, // No official AppImage
        .{ .name = "figma", .repo = "Figma-Linux/figma-linux", .binary_name = "figma-linux" },
        .{ .name = "insomnia", .repo = "Kong/insomnia", .binary_name = "Insomnia" },
        .{ .name = "postman", .repo = "postmanlabs/postman-app-support", .binary_name = "Postman" },
        .{ .name = "krita", .repo = "KDE/krita", .binary_name = "krita" },
        .{ .name = "gimp", .repo = "GNOME/gimp", .binary_name = null }, // Use Flatpak instead
        .{ .name = "blender", .repo = "blender/blender", .binary_name = "blender" },
        .{ .name = "kdenlive", .repo = "KDE/kdenlive", .binary_name = "kdenlive" },
        .{ .name = "appimage-builder", .repo = "AppImageCrafters/appimage-builder", .binary_name = "appimage-builder" },
        .{ .name = "appimagelauncher", .repo = "TheAssassin/AppImageLauncher", .binary_name = "AppImageLauncher" },
    };

    allocator: Allocator,

    pub fn init(allocator: Allocator) AppImageRegistry {
        return AppImageRegistry{
            .allocator = allocator,
        };
    }

    pub fn findRepository(self: AppImageRegistry, package_name: []const u8) ?[]const u8 {
        _ = self;
        for (KNOWN_APPS) |app| {
            if (std.mem.eql(u8, package_name, app.name)) {
                return app.repo;
            }
        }
        return null;
    }

    pub fn getBinaryName(self: AppImageRegistry, package_name: []const u8) ?[]const u8 {
        _ = self;
        for (KNOWN_APPS) |app| {
            if (std.mem.eql(u8, package_name, app.name)) {
                return app.binary_name orelse package_name;
            }
        }
        return package_name;
    }

    pub fn isKnownApp(self: AppImageRegistry, package_name: []const u8) bool {
        return self.findRepository(package_name) != null;
    }
};

pub const AppImageInstaller = struct {
    allocator: Allocator,
    registry: AppImageRegistry,
    install_dir: []const u8,

    pub fn init(allocator: Allocator) !AppImageInstaller {
        const home_dir = std.posix.getenv("HOME") orelse return AppImageError.FileSystemError;
        const install_dir = try std.fmt.allocPrint(allocator, "{s}/.local/bin", .{home_dir});

        return AppImageInstaller{
            .allocator = allocator,
            .registry = AppImageRegistry.init(allocator),
            .install_dir = install_dir,
        };
    }

    pub fn deinit(self: *AppImageInstaller) void {
        self.allocator.free(self.install_dir);
    }

    pub fn install(self: *AppImageInstaller, package_name: []const u8) !bool {
        print("🚀 Installing {s} AppImage...\n", .{package_name});

        const repo = self.registry.findRepository(package_name) orelse {
            try self.searchAppImageHub(package_name);
            return false;
        };

        // Ensure install directory exists
        std.fs.makeDirAbsolute(self.install_dir) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => {
                print("❌ Failed to create install directory: {}\n", .{err});
                return AppImageError.FileSystemError;
            },
        };

        print("📡 Fetching latest release information...\n", .{});
        const release = self.getLatestRelease(repo) catch |err| {
            print("❌ Failed to fetch release information: {}\n", .{err});
            return false;
        };
        defer release.deinit(self.allocator);

        print("📦 Found {s} version {s} ({d} bytes)\n", .{ release.name, release.version, release.size });

        // Download the AppImage
        const binary_name = self.registry.getBinaryName(package_name) orelse package_name;
        const install_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ self.install_dir, binary_name });
        defer self.allocator.free(install_path);

        print("⬇️  Downloading to {s}...\n", .{install_path});
        self.downloadFile(release.download_url, install_path) catch |err| {
            print("❌ Download failed: {}\n", .{err});
            return false;
        };

        // Make executable
        self.makeExecutable(install_path) catch |err| {
            print("❌ Failed to make executable: {}\n", .{err});
            return false;
        };

        print("✅ Successfully installed {s}!\n", .{package_name});
        print("💡 You can now run: {s}\n", .{binary_name});

        // Check if ~/.local/bin is in PATH
        self.checkPath();

        return true;
    }

    fn getLatestRelease(self: *AppImageInstaller, repo: []const u8) !AppImageRelease {
        const url = try std.fmt.allocPrint(self.allocator, "https://api.github.com/repos/{s}/releases/latest", .{repo});
        defer self.allocator.free(url);

        const curl_result = std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{ "curl", "-s", "-f", "-H", "Accept: application/vnd.github+json", "-H", "X-GitHub-Api-Version: 2022-11-28", url },
        }) catch return AppImageError.NetworkError;

        defer self.allocator.free(curl_result.stdout);
        defer self.allocator.free(curl_result.stderr);

        if (curl_result.term.Exited != 0) {
            print("❌ GitHub API request failed: {s}\n", .{curl_result.stderr});
            return AppImageError.NetworkError;
        }

        return self.parseReleaseJson(curl_result.stdout);
    }

    fn parseReleaseJson(self: *AppImageInstaller, json_data: []const u8) !AppImageRelease {
        const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, json_data, .{}) catch return AppImageError.ParseError;
        defer parsed.deinit();

        const root = parsed.value.object;

        const tag_name = root.get("tag_name") orelse return AppImageError.ParseError;
        const published_at = root.get("published_at") orelse return AppImageError.ParseError;
        const assets = root.get("assets") orelse return AppImageError.ParseError;

        if (assets.array.items.len == 0) {
            return AppImageError.NotFound;
        }

        // Find the AppImage asset
        for (assets.array.items) |asset| {
            const asset_obj = asset.object;
            const name = asset_obj.get("name") orelse continue;
            const download_url = asset_obj.get("browser_download_url") orelse continue;
            const size = asset_obj.get("size") orelse continue;

            const name_str = name.string;
            if (std.mem.endsWith(u8, name_str, ".AppImage") or
                std.mem.endsWith(u8, name_str, ".appimage"))
            {
                return AppImageRelease{
                    .name = try self.allocator.dupe(u8, name_str),
                    .download_url = try self.allocator.dupe(u8, download_url.string),
                    .version = try self.allocator.dupe(u8, tag_name.string),
                    .size = @intCast(size.integer),
                    .published_at = try self.allocator.dupe(u8, published_at.string),
                };
            }
        }

        return AppImageError.NotFound;
    }

    fn downloadFile(self: *AppImageInstaller, url: []const u8, destination: []const u8) !void {
        const curl_result = std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{ "curl", "-L", "-f", "-o", destination, "--progress-bar", url },
        }) catch return AppImageError.DownloadError;

        defer self.allocator.free(curl_result.stdout);
        defer self.allocator.free(curl_result.stderr);

        if (curl_result.term.Exited != 0) {
            print("❌ Download failed: {s}\n", .{curl_result.stderr});
            return AppImageError.DownloadError;
        }
    }

    fn makeExecutable(self: *AppImageInstaller, file_path: []const u8) !void {
        const chmod_result = std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{ "chmod", "+x", file_path },
        }) catch return AppImageError.FileSystemError;

        defer self.allocator.free(chmod_result.stdout);
        defer self.allocator.free(chmod_result.stderr);

        if (chmod_result.term.Exited != 0) {
            return AppImageError.FileSystemError;
        }
    }

    fn checkPath(self: *AppImageInstaller) void {
        const path_env = std.posix.getenv("PATH") orelse "";

        if (std.mem.indexOf(u8, path_env, self.install_dir) == null) {
            print("⚠️  Warning: {s} is not in your PATH\n", .{self.install_dir});
            print("💡 Add this to your shell profile (~/.bashrc, ~/.zshrc, etc.):\n", .{});
            print("   export PATH=\"{s}:$PATH\"\n", .{self.install_dir});
        }
    }

    pub fn searchAppImageHub(self: *AppImageInstaller, package_name: []const u8) !void {
        print("🧊 Searching AppImageHub for '{s}'...\n", .{package_name});

        const curl_result = std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{ "curl", "-s", "-f", "https://appimage.github.io/feed.json" },
        }) catch {
            print("❌ Failed to query AppImageHub\n", .{});
            return AppImageError.NetworkError;
        };
        defer self.allocator.free(curl_result.stdout);
        defer self.allocator.free(curl_result.stderr);

        if (curl_result.term.Exited != 0) {
            print("❌ AppImageHub query failed\n", .{});
            return AppImageError.NetworkError;
        }

        const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, curl_result.stdout, .{}) catch {
            // Fallback to basic text search if JSON parsing fails
            return self.searchAppImageHubFallback(curl_result.stdout, package_name);
        };
        defer parsed.deinit();

        var found_count: u32 = 0;
        const items = parsed.value.object.get("items") orelse return AppImageError.ParseError;

        for (items.array.items) |item| {
            const item_obj = item.object;
            const name = item_obj.get("name") orelse continue;
            const description = item_obj.get("description");
            const categories = item_obj.get("categories");

            const name_str = name.string;

            // Check if package name matches (case insensitive)
            if (std.ascii.indexOfIgnoreCase(name_str, package_name) != null) {
                print("  📦 {s}", .{name_str});
                if (description) |desc| {
                    print(" - {s}", .{desc.string});
                }
                if (categories) |cats| {
                    print(" (", .{});
                    for (cats.array.items, 0..) |cat, i| {
                        if (i > 0) print(", ", .{});
                        print("{s}", .{cat.string});
                    }
                    print(")", .{});
                }
                print("\n", .{});
                found_count += 1;

                if (found_count >= 10) break; // Limit results
            }
        }

        if (found_count == 0) {
            print("  No AppImages found for '{s}'\n", .{package_name});
        }
        print("  💡 Visit https://appimage.github.io for more options\n", .{});
    }

    fn searchAppImageHubFallback(self: *AppImageInstaller, data: []const u8, package_name: []const u8) !void {
        _ = self;
        var lines = std.mem.splitScalar(u8, data, '\n');
        var found_count: u32 = 0;

        while (lines.next()) |line| {
            if (std.mem.indexOf(u8, line, "\"name\"") != null and
                std.ascii.indexOfIgnoreCase(line, package_name) != null)
            {
                // Extract app name (basic parsing)
                if (std.mem.indexOf(u8, line, ":") != null) {
                    const name_part = std.mem.trim(u8, line[std.mem.indexOf(u8, line, ":").? + 1 ..], " \",");
                    print("  📦 {s}\n", .{name_part});
                    found_count += 1;
                    if (found_count >= 10) break; // Limit results
                }
            }
        }

        if (found_count == 0) {
            print("  No AppImages found for '{s}'\n", .{package_name});
        }
        print("  💡 Visit https://appimage.github.io for more options\n", .{});
    }

    pub fn listInstalled(self: *AppImageInstaller) !void {
        print("📦 Installed AppImages:\n", .{});

        var install_dir = std.fs.openDirAbsolute(self.install_dir, .{ .iterate = true }) catch {
            print("  No AppImages installed (directory doesn't exist)\n", .{});
            return;
        };
        defer install_dir.close();

        var iterator = install_dir.iterate();
        var count: u32 = 0;

        while (try iterator.next()) |entry| {
            if (entry.kind == .file) {
                // Check if file is executable
                const file_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ self.install_dir, entry.name });
                defer self.allocator.free(file_path);

                const file = std.fs.openFileAbsolute(file_path, .{}) catch continue;
                defer file.close();

                const metadata = file.metadata() catch continue;
                const is_executable = (metadata.permissions().inner.mode & 0o111) != 0;

                if (is_executable) {
                    const file_size = metadata.size();
                    print("  ✅ {s} ({d} bytes)\n", .{ entry.name, file_size });
                    count += 1;
                }
            }
        }

        if (count == 0) {
            print("  No AppImages found in {s}\n", .{self.install_dir});
        } else {
            print("\n  Total: {d} AppImage(s) installed\n", .{count});
        }
    }

    pub fn remove(self: *AppImageInstaller, package_name: []const u8) !bool {
        const binary_name = self.registry.getBinaryName(package_name) orelse package_name;
        const install_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ self.install_dir, binary_name });
        defer self.allocator.free(install_path);

        std.fs.deleteFileAbsolute(install_path) catch |err| switch (err) {
            error.FileNotFound => {
                print("❌ {s} is not installed\n", .{package_name});
                return false;
            },
            else => {
                print("❌ Failed to remove {s}: {}\n", .{ package_name, err });
                return false;
            },
        };

        print("✅ Successfully removed {s}\n", .{package_name});
        return true;
    }
};

// Test function for development
pub fn testAppImageInstaller() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var installer = AppImageInstaller.init(allocator) catch |err| {
        print("Failed to initialize installer: {}\n", .{err});
        return;
    };
    defer installer.deinit();

    print("🧪 Testing AppImage installer...\n", .{});

    // Test registry lookups
    print("Testing registry lookups:\n", .{});
    const test_apps = [_][]const u8{ "obsidian", "vscodium", "nonexistent" };
    for (test_apps) |app| {
        const repo = installer.registry.findRepository(app);
        print("  {s}: {?s}\n", .{ app, repo });
    }

    // Test listing installed AppImages
    try installer.listInstalled();
}
