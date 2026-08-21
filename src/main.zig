const std = @import("std");
const Io = std.Io;
const log = std.log;
const builtin = @import("builtin");
const lined = @import("lined");

var log_writer: *std.Io.Writer = undefined; // Must be initialized before `logFn` is called
var debug_allocator: std.heap.DebugAllocator(.{}) = .init;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

    // Initialize log file
    const log_file = try Io.Dir.cwd().createFile(io, "lined.log", .{ .truncate = true, .lock = .exclusive, .read = false });
    defer log_file.close(io);
    var log_buffer: [128]u8 = undefined;
    var log_file_writer = log_file.writer(io, &log_buffer);
    log_writer = &log_file_writer.interface;

    // Initialize input and output
    var stdin_buf: [1024]u8 = undefined;
    var stdout_buf: [1024]u8 = undefined;
    var stdin = Io.File.stdin().reader(io, &stdin_buf);
    var stdout = Io.File.stdout().writer(io, &stdout_buf);

    const input = &stdin.interface;
    const output = &stdout.interface;

    std.debug.print("> ", .{});
    if (lined.editLine(io, gpa, input, output)) |line| {
        defer gpa.free(line);
        std.debug.print(":'{s}'\r\n", .{line}); // \r\n during raw mode
    } else |err| {
        std.debug.print("error: {t}\r\n", .{err}); // \r\n during raw mode
    }
}

pub const std_options: std.Options = .{
    // .log_scope_levels = &.{
    //     .{ .scope = .lined, .level = .err },
    // },
    .logFn = logFn,
};

fn logFn(
    comptime message_level: std.log.Level,
    comptime scope: @EnumLiteral(),
    comptime format: []const u8,
    args: anytype,
) void {
    const level_txt = comptime message_level.asText();
    const prefix2 = if (scope == .default) ": " else "(" ++ @tagName(scope) ++ "): ";
    nosuspend log_writer.print(level_txt ++ prefix2 ++ format ++ "\n", args) catch return;
    log_writer.flush() catch {};
}
