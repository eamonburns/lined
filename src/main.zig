const std = @import("std");
const log = std.log;
const builtin = @import("builtin");
const lined = @import("lined");

var log_writer: *std.Io.Writer = undefined; // Must be initialized before `logFn` is called
var debug_allocator: std.heap.DebugAllocator(.{}) = .init;

pub fn main() !void {
    const gpa, const is_debug = switch (builtin.mode) {
        .Debug => .{ debug_allocator.allocator(), true },
        .ReleaseFast, .ReleaseSafe, .ReleaseSmall => .{ std.heap.smp_allocator, false },
    };
    // FIXME: Why doesn't .deinit report leaks using the custom logFn?
    defer if (is_debug) std.debug.assert(debug_allocator.deinit() == .ok); // NOTE: If this fails, change the logFn back to default and set log_level to .err

    // Initialize log file
    const log_file = try std.fs.cwd().createFile("lined.log", .{ .truncate = true, .lock = .exclusive, .read = false });
    defer log_file.close();
    var log_buffer: [128]u8 = undefined;
    var log_file_writer = log_file.writer(&log_buffer);
    log_writer = &log_file_writer.interface;

    // Initialize input and output
    var stdin_buf: [1024]u8 = undefined;
    var stdout_buf: [1024]u8 = undefined;
    var stdin = std.fs.File.stdin().reader(&stdin_buf);
    var stdout = std.fs.File.stdout().writer(&stdout_buf);

    try lined.rawModeStart();
    defer lined.rawModeStop();

    if (lined.editLine(gpa, &stdin.interface, &stdout.interface)) |line| {
        defer gpa.free(line);
        std.debug.print("line: '{s}'\r\n", .{line}); // \r\n during raw mode
    } else |err| {
        std.debug.print("error: {t}\r\n", .{err}); // \r\n during raw mode
    }
}

pub const std_options: std.Options = .{
    .logFn = logFn,
};

fn logFn(
    comptime message_level: std.log.Level,
    comptime scope: @Type(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    const level_txt = comptime message_level.asText();
    const prefix2 = if (scope == .default) ": " else "(" ++ @tagName(scope) ++ "): ";
    nosuspend log_writer.print(level_txt ++ prefix2 ++ format ++ "\n", args) catch return;
    log_writer.flush() catch {};
}
