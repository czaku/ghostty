const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const Action = @import("ghostty.zig").Action;
const args = @import("args.zig");
const internal_os = @import("../os/main.zig");

pub const Options = struct {
    /// This is set by the CLI parser for deinit.
    _arena: ?ArenaAllocator = null,

    /// Path to the session file to restore. If not provided, the most
    /// recently saved session will be used.
    path: ?[:0]const u8 = null,

    pub fn deinit(self: *Options) void {
        if (self._arena) |arena| arena.deinit();
        self.* = undefined;
    }

    /// Enables "-h" and "--help" to work.
    pub fn help(self: Options) !void {
        _ = self;
        return Action.help_error;
    }
};

/// The `restore-session` action writes a pending-restore marker file and
/// opens the Ghostty app, which will restore the session on the next launch.
///
/// If `--path` is not provided, the most recently saved session in the
/// sessions directory is used.
///
/// Flags:
///
///   * `--path=<file>`: Path to the session JSON file to restore.
///
/// Only supported on macOS.
pub fn run(alloc: Allocator) !u8 {
    var iter = try args.argsIterator(alloc);
    defer iter.deinit();

    var buffer: [1024]u8 = undefined;
    var stderr_writer = std.fs.File.stderr().writer(&buffer);
    const stderr = &stderr_writer.interface;

    const result = runArgs(alloc, &iter, stderr);
    stderr.flush() catch {};
    return result;
}

fn runArgs(
    alloc_gpa: Allocator,
    argsIter: anytype,
    stderr: *std.Io.Writer,
) !u8 {
    if (comptime builtin.os.tag != .macos) {
        try stderr.print("+restore-session is only supported on macOS.\n", .{});
        return 1;
    }

    var arena = ArenaAllocator.init(alloc_gpa);
    defer arena.deinit();
    const alloc = arena.allocator();

    var opts: Options = .{};
    defer opts.deinit();

    args.parse(Options, alloc_gpa, &opts, argsIter) catch |err| switch (err) {
        error.ActionHelpRequested => return err,
        else => {
            try stderr.print("Error parsing args: {}\n", .{err});
            return 1;
        },
    };

    // Resolve the session file path.
    const session_path: []const u8 = if (opts.path) |p|
        try alloc.dupe(u8, p)
    else blk: {
        // Find the most recent session file in the sessions directory.
        const sessions_dir = internal_os.macos.appSupportDir(alloc, "sessions") catch {
            try stderr.print("Could not find sessions directory.\n", .{});
            return 1;
        };

        var dir = std.fs.openDirAbsolute(sessions_dir, .{ .iterate = true }) catch {
            try stderr.print("No sessions directory found at: {s}\n", .{sessions_dir});
            return 1;
        };
        defer dir.close();

        // Find the newest .json file
        var newest_name: ?[]const u8 = null;
        var newest_mtime: i128 = std.math.minInt(i128);
        var it = dir.iterate();
        while (try it.next()) |entry| {
            if (entry.kind != .file) continue;
            if (!std.mem.endsWith(u8, entry.name, ".json")) continue;
            const stat = dir.statFile(entry.name) catch continue;
            if (stat.mtime > newest_mtime) {
                newest_mtime = stat.mtime;
                newest_name = try alloc.dupe(u8, entry.name);
            }
        }

        const name = newest_name orelse {
            try stderr.print("No session files found in: {s}\n", .{sessions_dir});
            return 1;
        };
        break :blk try std.fs.path.join(alloc, &.{ sessions_dir, name });
    };

    // Verify the session file exists.
    std.fs.accessAbsolute(session_path, .{}) catch {
        try stderr.print("Session file not found: {s}\n", .{session_path});
        return 1;
    };

    // Write a pending-restore marker file that the Ghostty GUI will read
    // on the next launch.
    const pending_path = internal_os.macos.appSupportDir(alloc, "restore-pending.json") catch {
        try stderr.print("Could not resolve pending restore path.\n", .{});
        return 1;
    };

    // Ensure the parent directory exists.
    if (std.fs.path.dirname(pending_path)) |parent| {
        std.fs.makeDirAbsolute(parent) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => {
                try stderr.print("Could not create directory: {s}\n", .{parent});
                return 1;
            },
        };
    }

    // Write the session file path to the pending restore file.
    const f = std.fs.createFileAbsolute(pending_path, .{}) catch {
        try stderr.print("Could not write pending restore file.\n", .{});
        return 1;
    };
    defer f.close();
    f.writeAll(session_path) catch {
        try stderr.print("Could not write session path to pending restore file.\n", .{});
        return 1;
    };

    // Launch the Ghostty app. We find the .app bundle by walking up from
    // the current executable path.
    const exe_path = std.fs.selfExePathAlloc(alloc) catch null;
    if (exe_path) |exe| {
        if (std.mem.indexOf(u8, exe, ".app/")) |app_end| {
            const app_path = exe[0 .. app_end + 4];
            var child = std.process.Child.init(&.{ "/usr/bin/open", app_path }, alloc);
            _ = child.spawnAndWait() catch {};
            return 0;
        }
    }

    // Fallback: try to open by app name.
    var child = std.process.Child.init(&.{ "/usr/bin/open", "-a", "Ghostty" }, alloc);
    _ = child.spawnAndWait() catch {
        try stderr.print(
            "Session restore queued. Open Ghostty to restore your session.\n",
            .{},
        );
    };

    return 0;
}
