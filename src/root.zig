//! By convention, root.zig is the root source file when making a library.
const std = @import("std");
const log = std.log;
const Allocator = std.mem.Allocator;
const builtin = @import("builtin");

const Escape = @import("escape.zig").Escape;

var original_termios: ?std.posix.termios = null;

var term_width: usize = 80;
var term_height: usize = 24;
const csi = "\x1b[";

/// Cross-platform function to enable unbuffered input from stdin, and disable input echoing.
///
/// Non-Windows implementation: [Entering raw mode](https://viewsourcecode.org/snaptoken/kilo/02.enteringRawMode.html) (side note: This tutorial is awesome)
pub fn rawModeStart() !void {
    if (builtin.target.os.tag != .windows) {
        const handle = std.fs.File.stdin().handle;
        var raw = try std.posix.tcgetattr(handle);
        original_termios = raw;
        raw.iflag.BRKINT = false; // "When BRKINT is turned on, a break condition will cause a SIGINT signal to be sent to the program, like pressing Ctrl-C"
        raw.iflag.ICRNL = false; // Disable translation of '\r' to '\n' (also Ctrl-M to Ctrl-J)
        raw.iflag.INPCK = false; // "INPCK enables parity checking, which doesn’t seem to apply to modern terminal emulators"
        raw.iflag.ISTRIP = false; // "ISTRIP causes the 8th bit of each input byte to be stripped, meaning it will set it to 0. This is probably already turned off"
        raw.iflag.IXON = false; // Don't send "software flow control" codes (Ctrl-S, Ctrl-Q)

        raw.oflag.OPOST = false; // Disable output processing (e.g. translation of '\n' to '\r' + '\n')

        raw.cflag.CSIZE = .CS8; // "CS8 is not a flag, it is a bit mask with multiple bits, which we set using the bitwise-OR (|) operator unlike all the flags we are turning off. It sets the character size (CS) to 8 bits per byte. On my system, it’s already set that way"

        raw.lflag.ECHO = false; // Don't echo back input
        raw.lflag.ICANON = false; // Don't buffer lines (disable canonical mode)
        raw.lflag.IEXTEN = false; // Ctrl-V (fixes Ctrl-O on macOS)
        raw.lflag.ISIG = false; // Don't send process control signals (Ctrl-C, Ctrl-Z)
        try std.posix.tcsetattr(handle, .FLUSH, raw);

        // NOTE: This was the old implementation
        // termios.iflag.BRKINT = false;
        // termios.iflag.ICRNL = false;
        // termios.iflag.INPCK = false;
        // termios.iflag.ISTRIP = false;
        // termios.iflag.IXON = false;
        // termios.oflag.OPOST = false;
        // termios.lflag.ECHO = false;
        // termios.lflag.ICANON = false;
        // termios.lflag.IEXTEN = false;
        // termios.lflag.ISIG = false;
        // termios.cflag.CSIZE = .CS8;
        // termios.cc[@intFromEnum(std.posix.V.TIME)] = 0;
        // termios.cc[@intFromEnum(std.posix.V.MIN)] = 1;
        //
        // try std.posix.tcsetattr(handle, .FLUSH, termios);
        //
        // var ws: std.posix.winsize = undefined;
        // const err = std.posix.system.ioctl(handle, std.posix.T.IOCGWINSZ, @intFromPtr(&ws));
        // if (std.posix.errno(err) != .SUCCESS or ws.col == 0 or ws.row == 0) {
        //     return error.GetTerminalSizeErr;
        // }
        // term_width = ws.col;
        // term_height = ws.row;
    } else {
        var csbi: std.os.windows.CONSOLE_SCREEN_BUFFER_INFO = undefined;
        const stdouth = try std.os.windows.GetStdHandle(std.os.windows.STD_OUTPUT_HANDLE);
        _ = std.os.windows.kernel32.GetConsoleScreenBufferInfo(stdouth, &csbi);
        term_width = @intCast(csbi.srWindow.Right - csbi.srWindow.Left + 1);
        term_height = @intCast(csbi.srWindow.Bottom - csbi.srWindow.Top + 1);

        const ENABLE_PROCESSED_INPUT: u16 = 0x0001;
        const ENABLE_MOUSE_INPUT: u16 = 0x0010;
        const ENABLE_WINDOW_INPUT: u16 = 0x0008;

        const stdinh = try std.os.windows.GetStdHandle(std.os.windows.STD_INPUT_HANDLE);
        var oldMode: std.os.windows.DWORD = undefined;
        _ = std.os.windows.kernel32.GetConsoleMode(stdinh, &oldMode);
        const newMode = oldMode & ~ENABLE_MOUSE_INPUT & ~ENABLE_WINDOW_INPUT & ~ENABLE_PROCESSED_INPUT;
        _ = std.os.windows.kernel32.SetConsoleMode(stdinh, newMode);
        @compileError("Windows is not yet supported :(");
    }
}

pub fn rawModeStop() void {
    var buf: [512]u8 = undefined;
    var w = std.fs.File.stderr().writer(&buf);
    const stderr = &w.interface;

    stderr.print(csi ++ "48;2;{d};{d};{d}m", .{ 0x00, 0x00, 0x00 }) catch {}; // bg
    stderr.print(csi ++ "38;2;{d};{d};{d}m", .{ 0xFF, 0xFF, 0xFF }) catch {}; // fg

    if (builtin.target.os.tag != .windows) {
        if (original_termios) |termios| {
            std.posix.tcsetattr(std.fs.File.stdin().handle, .FLUSH, termios) catch {};
        }
    }
    _ = stderr.print("\n", .{}) catch 0;
}

/// Reads from `input` until a newline is encountered, and then returns the
/// resulting line of text. (blocking)
///
/// Prints to `output` to modify the visible text on the current line.
///
/// Assumes `rawModeStart` was called before.
pub fn editLine(
    gpa: Allocator,
    input: *std.Io.Reader,
    output: *std.Io.Writer,
) error{ ReadFailed, WriteFailed, TODOBetterError }![]const u8 {
    _ = gpa;
    while (input.peekByte()) |c| {
        if (c == '\x1b') {
            const esc = Escape.parse(input) catch return error.TODOBetterError;
            log.info("escape: '{any}'", .{esc});
            switch (esc) {
                .cursor_up, .cursor_down, .cursor_forward, .cursor_back => {
                    try esc.write(output);
                    try output.flush();
                },
                else => {},
            }
            continue;
        }
        input.toss(1);
        // TODO: Change back to newline
        // if (c == '\n') break;
        if (c == 'q') break;
        if (c == 'p') {
            log.info("asking for cursor position", .{});
            const dsr: Escape = .device_status_report;
            try dsr.write(output);
            try output.flush();
            continue;
        }
        if (std.ascii.isControl(c)) {
            log.info("{d}", .{c});
        } else {
            log.info("{d} ({c})", .{ c, c });
        }
        try output.flush();
    } else |err| switch (err) {
        error.ReadFailed => |e| {
            log.err("{t}", .{e});
            return e;
        },
        error.EndOfStream => |e| {
            log.info("{t}", .{e});
            return "todo: actually get input (end of stream)";
        },
    }
    return "todo: actually get input (quit)";
}

test {
    _ = std.testing.refAllDecls(@This());
}
