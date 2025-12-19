//! Parsing escape sequences

const std = @import("std");
const log = std.log;

/// [Control Sequence Introducer](https://en.wikipedia.org/wiki/ANSI_escape_code#CSIsection)
const CSI = "\x1b[";

/// Bytes in the range 0x30–0x3F (inclusive)
const CSI_PARAMETER_BYTES = "0–9:;<=>?";
const PARAMETER_BYTE_FIRST = 0x30;
const PARAMETER_BYTE_LAST = 0x3F;
/// Bytes in the range 0x20–0x2F (inclusive)
const CSI_INTERMEDIATE_BYTES = " !\"#$%&'()*+,-./";
const INTERMEDIATE_BYTE_FIRST = 0x20;
const INTERMEDIATE_BYTE_LAST = 0x2F;
/// Bytes in the range 0x40–0x7E (inclusive)
const CSI_FINAL_BYTES = "@A–Z[\\]^_`a–z{|}~";
const FINAL_BYTE_FIRST = 0x40;
const FINAL_BYTE_LAST = 0x7E;

/// <https://invisible-island.net/xterm/ecma-48-parameter-format.html>
pub const Escape = union(enum) {
    /// CUU
    /// Format: `CSI <n> A`
    ///
    /// Moves the cursor `n` (default 1) cells up.
    /// If the cursor is already at the edge of the screen, this has no effect.
    cursor_up: u32,
    /// CUD
    /// Format: `CSI <n> B`
    ///
    /// Moves the cursor `n` (default 1) cells down.
    /// If the cursor is already at the edge of the screen, this has no effect.
    cursor_down: u32,
    /// CUF
    /// Format: `CSI <n> C`
    ///
    /// Moves the cursor `n` (default 1) cells forward.
    /// If the cursor is already at the edge of the screen, this has no effect.
    cursor_forward: u32,
    /// CUB
    /// Format: `CSI <n> D`
    ///
    /// Moves the cursor `n` (default 1) cells back.
    /// If the cursor is already at the edge of the screen, this has no effect.
    cursor_back: u32,
    /// CNL
    /// Format: `CSI <n> E`
    ///
    /// Moves cursor to beginning of the line `n` (default 1) lines down.
    cursor_next_line: u32,
    /// CPL
    /// Format: `CSI <n> F`
    ///
    /// Moves cursor to beginning of the line `n` (default 1) lines up.
    cursor_previous_line: u32,
    /// CHA
    /// Format: `CSI <n> G`
    ///
    /// Moves the cursor to column `n` (default 1).
    cursor_horizontal_absolute: u32,
    /// CUP
    /// Format: `CSI <n> ; <m> H`
    ///
    /// Moves the cursor to row `n`, column `m`.
    /// The values are 1-based, and default to 1 (top left corner) if omitted.
    /// A sequence such as `CSI ;5H` is a synonym for `CSI 1;5H` as well as `CSI 17;H` is the same as `CSI 17H` and `CSI 17;1H`
    cursor_position: struct { u32, u32 },
    /// ED
    /// Format: `CSI <n> J`
    ///
    /// Clears part of the screen.
    /// If `n` is 0 (or missing), clear from cursor to end of screen.
    /// If `n` is 1, clear from cursor to beginning of the screen.
    /// If `n` is 2, clear entire screen (and moves cursor to upper left on DOS ANSI.SYS).
    /// If `n` is 3, clear entire screen and delete all lines saved in the scrollback buffer (this feature was added for xterm and is supported by other terminal applications).
    erase_in_display: u32,
    /// EL
    /// Format: `CSI <n> K`
    ///
    /// Erases part of the line.
    /// If `n` is 0 (or missing), clear from cursor to the end of the line.
    /// If `n` is 1, clear from cursor to beginning of the line.
    /// If `n` is 2, clear entire line.
    /// Cursor position does not change.
    erase_in_line: u32,
    /// CPR
    /// Format: `CSI <n> ; <m> R`
    ///
    /// Cursor position , where `n` is the row and `m` is the column.
    cursor_position_report: struct { u32, u32 },
    /// SU
    /// Format: `CSI <n> S`
    ///
    /// Scroll whole page up by `n` (default 1) lines.
    /// New lines are added at the bottom.
    scroll_up: u32,
    /// SD
    /// Format: `CSI <n> T`
    ///
    /// Scroll whole page down by `n` (default 1) lines.
    /// New lines are added at the top.
    scroll_down: u32,
    /// HVP
    /// Format: `CSI <n> ; <m> f`
    ///
    /// Same as CUP, but counts as a format effector function (like CR or LF) rather than an editor function (like CUD or CNL).
    /// This can lead to different handling in certain terminal modes.
    horizontal_vertical_position: struct { u32, u32 },
    /// SGR
    /// Format: `CSI <n> m`
    ///
    /// Sets colors and style of the characters following this code.
    ///
    /// Data is stored in the buffer of the `Reader` this code was read from.
    select_graphic_rendition: []const u8,
    /// ???
    /// Format: `CSI 5 i`
    ///
    /// Enable aux serial port usually for local serial printer.
    aux_port_on,
    /// ???
    /// Format: `CSI 4 i`
    ///
    /// Disable aux serial port usually for local serial printer.
    aux_port_off,
    /// DSR
    /// Format: `CSI 6 n`
    ///
    /// Reports the cursor position (CPR) by transmitting `CSI <n> ; <m> R`, where `n` is the row and `m` is the column.
    device_status_report,
    /// ???
    /// Format: `CSI <n> ; <m> ~`
    ///
    /// Escape sequence encoding a key code `n` with possible modifiers `m` (default 1).
    ///
    /// Key code values:
    /// - `1`: Home
    /// - `2`: Insert
    /// - `3`: Delete
    /// - `4`: End
    /// - `5`: PgUp
    /// - `6`: PgDn
    /// - `7`: Home
    /// - `8`: End
    /// - `9`: ...
    /// - `10-15`: F0-F5
    /// - `16`: ...
    /// - `17-21`: F6-F10
    /// - `22`: ...
    /// - `23-26`: F11-F14
    /// - `27`: ...
    /// - `28-29`: F15-F16
    /// - `30`: ...
    /// - `31-26`: F17-F20
    /// - `35`: ...
    ///
    /// The modifier value is 1 plus the sum of the modifier keys pressed:
    /// - Shift: 1
    /// - (Left) Alt: 2
    /// - Control: 4
    /// - Meta: 8
    ///
    /// After subtracting 1 from the result, it is a bitmap of the modifier keys pressed.
    /// - `8 4 2 1`
    /// - `m c a s`
    ///
    /// e.g. Shift + Alt + Control + Meta -> 1 + 1 + 2 + 4 + 8 -> 16
    // NOTE: Name is kind of arbitrary
    keycode_sequence: struct { u32, u32 },
    /// Unknown escape code. Contains escape code after CSI up to and
    /// including the final byte (e.g. `\x1b[1;2x` -> `1;2x`).
    ///
    /// Data is stored in the buffer of the `Reader` this code was read from.
    unknown: []const u8,

    // TODO: I think this function would be a good candidate for fuzz testing

    /// NOTE: Some returned `Escape`s are backed by data obtained using `input.take`,
    /// which means "the data is invalidated by the next call to `take`, `peek`, `fill`,
    /// and functions with those prefixes" on `input`.
    pub fn parse(input: *std.Io.Reader) !Escape {
        const csi = try input.peek(CSI.len);
        if (!std.mem.eql(u8, csi, CSI)) return error.ExpectedCsi;
        input.toss(CSI.len);

        var i: usize = 0;
        var buf = try input.peek(i + 1);
        var c = buf[i];
        // Parameter
        const param_start = i;
        while (PARAMETER_BYTE_FIRST <= c and c <= PARAMETER_BYTE_LAST) {
            i += 1;
            buf = try input.peek(i + 1);
            c = buf[i];
        }
        // Intermediate
        const inter_start = i;
        while (INTERMEDIATE_BYTE_FIRST <= c and c <= INTERMEDIATE_BYTE_LAST) {
            i += 1;
            buf = try input.peek(i + 1);
            c = buf[i];
        }
        // Final
        if (c < FINAL_BYTE_FIRST or FINAL_BYTE_LAST < c) {
            return error.UnexpectedCharacter;
        }
        const final_idx = i;
        const esc_buf = try input.take(buf.len); // Shorten to length of actual escape sequence

        log.info("esc_buf: '{s}'", .{esc_buf});

        return esc: switch (esc_buf[final_idx]) {
            'A' => {
                const n = try parseParam1(esc_buf[param_start..inter_start]) orelse 1;
                break :esc .{ .cursor_up = n };
            },
            'B' => {
                const n = try parseParam1(esc_buf[param_start..inter_start]) orelse 1;
                break :esc .{ .cursor_down = n };
            },
            'C' => {
                const n = try parseParam1(esc_buf[param_start..inter_start]) orelse 1;
                break :esc .{ .cursor_forward = n };
            },
            'D' => {
                const n = try parseParam1(esc_buf[param_start..inter_start]) orelse 1;
                break :esc .{ .cursor_back = n };
            },
            'E' => {
                const n = try parseParam1(esc_buf[param_start..inter_start]) orelse 1;
                break :esc .{ .cursor_next_line = n };
            },
            'F' => {
                const n = try parseParam1(esc_buf[param_start..inter_start]) orelse 1;
                break :esc .{ .cursor_previous_line = n };
            },
            'G' => {
                const n = try parseParam1(esc_buf[param_start..inter_start]) orelse 1;
                break :esc .{ .cursor_horizontal_absolute = n };
            },
            'H' => {
                const n, const m = try parseParam2(esc_buf[param_start..inter_start]);
                break :esc .{ .cursor_position = .{ n orelse 1, m orelse 1 } };
            },
            'J' => {
                const n = try parseParam1(esc_buf[param_start..inter_start]) orelse 0;
                break :esc .{ .erase_in_display = n };
            },
            'K' => {
                const n = try parseParam1(esc_buf[param_start..inter_start]) orelse 0;
                break :esc .{ .erase_in_line = n };
            },
            'R' => {
                const n, const m = try parseParam2(esc_buf[param_start..inter_start]);
                break :esc .{ .cursor_position_report = .{ n orelse 1, m orelse 1 } };
            },
            'S' => {
                const n = try parseParam1(esc_buf[param_start..inter_start]) orelse 1;
                break :esc .{ .scroll_up = n };
            },
            'T' => {
                const n = try parseParam1(esc_buf[param_start..inter_start]) orelse 1;
                break :esc .{ .scroll_down = n };
            },
            'f' => {
                const n, const m = try parseParam2(esc_buf[param_start..inter_start]);
                break :esc .{ .horizontal_vertical_position = .{ n orelse 1, m orelse 1 } };
            },
            '~' => {
                const n, const m = try parseParam2(esc_buf[param_start..inter_start]);
                break :esc .{ .keycode_sequence = .{ n orelse return error.TODOBetterError, m orelse 1 } };
            },
            'm' => break :esc .{ .select_graphic_rendition = esc_buf },
            else => break :esc .{ .unknown = esc_buf },
        };
    }

    pub fn write(
        self: Escape,
        writer: *std.Io.Writer,
    ) std.Io.Writer.Error!void {
        switch (self) {
            .cursor_up => |n| try writeParam1Esc(writer, n, 'A'),
            .cursor_down => |n| try writeParam1Esc(writer, n, 'B'),
            .cursor_forward => |n| try writeParam1Esc(writer, n, 'C'),
            .cursor_back => |n| try writeParam1Esc(writer, n, 'D'),
            .cursor_next_line => |n| try writeParam1Esc(writer, n, 'E'),
            .cursor_previous_line => |n| try writeParam1Esc(writer, n, 'F'),
            .cursor_horizontal_absolute => |n| try writeParam1Esc(writer, n, 'G'),
            .cursor_position => |nm| try writeParam2Esc(writer, nm.@"0", nm.@"1", 'H'),
            .erase_in_display => |n| try writeParam1Esc(writer, n, 'J'),
            .erase_in_line => |n| try writeParam1Esc(writer, n, 'K'),
            .cursor_position_report => |nm| try writeParam2Esc(writer, nm.@"0", nm.@"1", 'R'),
            .scroll_up => |n| try writeParam1Esc(writer, n, 'S'),
            .scroll_down => |n| try writeParam1Esc(writer, n, 'T'),
            .horizontal_vertical_position => |nm| try writeParam2Esc(writer, nm.@"0", nm.@"1", 'f'),
            .aux_port_on => try writeParam1Esc(writer, 5, 'i'),
            .aux_port_off => try writeParam1Esc(writer, 4, 'i'),
            .device_status_report => try writeParam1Esc(writer, 6, 'n'),
            .keycode_sequence => |nm| try writeParam2Esc(writer, nm.@"0", nm.@"1", '~'),
            .unknown, .select_graphic_rendition => |s| try writer.print("\x1b{s}", .{s}),
        }
    }
};

test "parse escapes" {
    const expectEqualDeep = std.testing.expectEqualDeep;
    var input0: std.Io.Reader = .fixed("\x1b[A");
    try expectEqualDeep(Escape{ .cursor_up = 1 }, Escape.parse(&input0));
    var input1: std.Io.Reader = .fixed("\x1b[123D");
    try expectEqualDeep(Escape{ .cursor_back = 123 }, Escape.parse(&input1));
    var input2: std.Io.Reader = .fixed("\x1b[38;2;12;34;56m");
    try expectEqualDeep(Escape{ .select_graphic_rendition = "38;2;12;34;56m" }, Escape.parse(&input2));
    var input3: std.Io.Reader = .fixed("\x1b[ma whole bunch of extra stuff");
    try expectEqualDeep(Escape{ .select_graphic_rendition = "m" }, Escape.parse(&input3));
}

fn parseParam1(buf: []const u8) !?u32 {
    if (buf.len == 0) return null;
    return try std.fmt.parseInt(u32, buf, 10); // NOTE: This is more lenient than the actual escape codes are (e.g. it accepts 1_000)
}

test parseParam1 {
    const expectEqual = std.testing.expectEqual;
    try expectEqual(null, try parseParam1(""));
    try expectEqual(123, try parseParam1("123"));
}

/// Adapted example, where "null" is to be replaced with the default value for the escape sequence:
/// "A sequence such as `;5` is a synonym for `null;5`, and `17;` is the same as `17` and `17;null`"
fn parseParam2(buf: []const u8) !struct { ?u32, ?u32 } {
    if (std.mem.indexOf(u8, buf, ";")) |idx| {
        const n_buf = buf[0..idx];
        const n = if (n_buf.len > 0)
            try std.fmt.parseInt(u32, n_buf, 10)
        else
            null;

        const m_buf = buf[idx + 1 ..];
        const m = if (m_buf.len > 0)
            try std.fmt.parseInt(u32, m_buf, 10)
        else
            null;

        return .{ n, m };
    } else {
        const n = try parseParam1(buf);
        const m = null;
        return .{ n, m };
    }
}

test parseParam2 {
    const expectEqual = std.testing.expectEqual;
    try expectEqual(.{ null, null }, try parseParam2(""));
    try expectEqual(.{ null, null }, try parseParam2(";"));

    try expectEqual(.{ null, 5 }, try parseParam2(";5"));
    try expectEqual(.{ 0, 5 }, try parseParam2("0;5"));

    try expectEqual(.{ 17, null }, try parseParam2("17;"));
    try expectEqual(.{ 17, null }, try parseParam2("17"));
    try expectEqual(.{ 17, 0 }, try parseParam2("17;0"));
}

fn writeParam1Esc(
    writer: *std.Io.Writer,
    n: u32,
    final: u8,
) std.Io.Writer.Error!void {
    try writer.print("\x1b[{d}{c}", .{ n, final });
}

fn writeParam2Esc(
    writer: *std.Io.Writer,
    n: u32,
    m: u32,
    final: u8,
) std.Io.Writer.Error!void {
    try writer.print("\x1b[{d};{d}{c}", .{ n, m, final });
}
