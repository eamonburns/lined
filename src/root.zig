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

/// Cross-platform function to enable "raw mode".
///
/// Notable effects (see comments in function body for all effects):
/// - Unbuffered input from stdin
/// - Disable input echoing
/// - Disable output processing: e.g. traslation of \n to \r\n
/// - Disable special handling of Ctrl sequences
///     - Ctrl-C
///     - Ctrl-Q
///     - Ctrl-S
///     - Ctrl-V
///     - Ctrl-Z
///
/// Disable raw mode by running `rawModeStop`.
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

pub const EditLineError = error{
    ReadFailed,
    WriteFailed,
    OutOfMemory,
    TODOBetterError, // TODO: Better error
};

/// Reads from `input` until a newline is encountered, and then returns the
/// resulting line of text, which must be `free`d.
///
/// Prints to `output` to modify the visible text on the current line.
///
/// Assumes `rawModeStart` was called before.
pub fn editLine(
    gpa: Allocator,
    input: *std.Io.Reader,
    output: *std.Io.Writer,
) EditLineError![]const u8 {
    var line: std.ArrayList(u8) = .empty;
    errdefer line.deinit(gpa);
    // Index of next character to be inserted
    var i: usize = 0;

    while (input.peekByte()) |c| {
        if (c == '\x1b') {
            const esc = Escape.parse(input) catch return error.TODOBetterError;
            log.info("escape: '{any}'", .{esc});
            switch (esc) {
                // TODO: Handle going past end of screen
                .cursor_forward => {
                    if (i < line.items.len) {
                        i += 1;
                        try esc.write(output);
                        try output.flush();
                    }
                },
                .cursor_back => {
                    if (i > 0) {
                        i -= 1;
                        try esc.write(output);
                        try output.flush();
                    }
                },
                else => {},
            }
            continue;
        }
        input.toss(1);
        // In raw mode, <enter> sends a "carriage return", rather than a "new line"
        if (c == '\r') {
            try output.writeAll(line.items[i..]);
            try output.writeAll("\r\n"); // \r\n in raw mode
            try output.flush();
            break;
        }
        if (c == 'p') {
            log.info("asking for cursor position", .{});
            try Escape.write(.device_status_report, output);
            try output.flush();
            continue;
        }

        if (std.ascii.isControl(c)) {
            log.info("control: {d}", .{c});
            try output.flush(); // Do I need this?
            continue;
        }
        try line.insert(gpa, i, c);
        try output.writeByte(line.items[i]); // Write inserted character
        i += 1;
        if (line.items[i..].len > 0) {
            // Save position, write characters after cursor, restore position
            try output.writeAll("\x1b7"); // TODO: Don't hard code this
            try output.writeAll(line.items[i..]);
            try output.writeAll("\x1b8");
        }
        try output.flush();
        log.info("line: '{s}', i: {d}, len: {d}", .{ line.items, i, line.items.len });
    } else |err| switch (err) {
        error.ReadFailed => |e| {
            log.err("{t}", .{e});
            return e;
        },
        error.EndOfStream => {
            log.info("end of stream", .{});
        },
    }
    return line.toOwnedSlice(gpa);
}

test {
    _ = std.testing.refAllDecls(@This());
}
