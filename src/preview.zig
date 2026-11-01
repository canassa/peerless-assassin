//! Draws a frame in the terminal with 24-bit ANSI colours, laid out like the
//! physical display, so rendering can be checked without the device.

const std = @import("std");
const Io = std.Io;
const protocol = @import("protocol.zig");
const leds = @import("leds.zig");

const Rgb = protocol.Rgb;
const Frame = [protocol.led_count]Rgb;

/// Unlit elements are drawn dim so the layout stays visible.
const unlit: Rgb = .{ .r = 0x30, .g = 0x30, .b = 0x30 };

pub fn draw(w: *Io.Writer, frame: *const Frame) Io.Writer.Error!void {
    // ////// LOGO //////
    try stripes(w, frame, leds.logo_left_stripes);
    try w.writeAll(" LOGO ");
    try stripes(w, frame, leds.logo_right_stripes);
    try w.writeAll("\n");

    // CPU 888 °C        888 W
    // GPU          °F
    for (0..3) |row| {
        switch (row) {
            1 => try text(w, frame, leds.cpu_label, "CPU "),
            2 => try text(w, frame, leds.gpu_label, "GPU "),
            else => try w.writeAll("    "),
        }
        try digitRow(w, frame, &leds.temp_digits, row);
        switch (row) {
            1 => try text(w, frame, leds.celsius_label, " °C"),
            2 => try text(w, frame, leds.fahrenheit_label, " °F"),
            else => try w.writeAll("   "),
        }
        try w.writeAll("       ");
        try digitRow(w, frame, &leds.watt_digits, row);
        if (row == 2) try text(w, frame, leds.watt_label, " W");
        try w.writeAll("\n");
    }

    for (0..2) |_| {
        for (leds.bars.first..leds.bars.end()) |i| try text(w, frame, @intCast(i), "──");
        try w.writeAll("\n");
    }

    // 8888 MHz   188 %
    for (0..3) |row| {
        try digitRow(w, frame, &leds.mhz_digits, row);
        if (row == 2) try text(w, frame, leds.mhz_label, " MHz") else try w.writeAll("    ");
        try w.writeAll("   ");
        switch (row) {
            1 => try text(w, frame, leds.percent_hundred.b, "|"),
            2 => try text(w, frame, leds.percent_hundred.c, "|"),
            else => try w.writeAll(" "),
        }
        try digitRow(w, frame, &leds.percent_digits, row);
        if (row == 2) try text(w, frame, leds.percent_label, " %");
        try w.writeAll("\n");
    }

    try w.writeAll("                   ");
    try stripes(w, frame, leds.bottom_right_stripes);
    try w.writeAll("\x1b[0m\n");
}

/// One text row of a run of digits stored right to left, drawn left to right:
///  _
/// |_|
/// |_|
fn digitRow(w: *Io.Writer, frame: *const Frame, digits: []const leds.Digit, row: usize) Io.Writer.Error!void {
    var i = digits.len;
    while (i > 0) {
        i -= 1;
        const d = digits[i];
        const seg = struct {
            fn at(digit: leds.Digit, s: leds.Segment) u8 {
                return digit[@backingInt(s)];
            }
        }.at;
        switch (row) {
            0 => {
                try w.writeAll(" ");
                try text(w, frame, seg(d, .a), "_");
                try w.writeAll(" ");
            },
            1 => {
                try text(w, frame, seg(d, .f), "|");
                try text(w, frame, seg(d, .g), "_");
                try text(w, frame, seg(d, .b), "|");
            },
            else => {
                try text(w, frame, seg(d, .e), "|");
                try text(w, frame, seg(d, .d), "_");
                try text(w, frame, seg(d, .c), "|");
            },
        }
    }
}

fn stripes(w: *Io.Writer, frame: *const Frame, r: leds.Range) Io.Writer.Error!void {
    for (r.first..r.end()) |i| try text(w, frame, @intCast(i), "/");
}

fn text(w: *Io.Writer, frame: *const Frame, led: u8, s: []const u8) Io.Writer.Error!void {
    const c = if (frame[led].isOff()) unlit else frame[led];
    try w.print("\x1b[38;2;{d};{d};{d}m{s}", .{ c.r, c.g, c.b, s });
}

test "draw writes every element" {
    const display = @import("display.zig");
    const frame = display.render(.{ .cpu_temp_c = 45, .cpu_mhz = 4500, .power_w = 87, .disk_used_pct = 29 });
    var buf: [16 * 1024]u8 = undefined;
    var w: Io.Writer = .fixed(&buf);
    try draw(&w, &frame);
    try std.testing.expect(std.mem.indexOf(u8, w.buffered(), "LOGO") != null);
}
