//! Turns sensor readings into a colour for every LED.

const std = @import("std");
const protocol = @import("protocol.zig");
const leds = @import("leds.zig");

const Rgb = protocol.Rgb;
const Digit = leds.Digit;
const Segment = leds.Segment;

pub const white: Rgb = .{ .r = 0xff, .g = 0xff, .b = 0xff };
pub const yellow: Rgb = .{ .r = 0xff, .g = 0xc0, .b = 0x00 };
pub const red: Rgb = .{ .r = 0xff, .g = 0x00, .b = 0x00 };

/// What the display shows. `null` means the reading failed or isn't available
/// yet; its digits show dashes.
pub const Reading = struct {
    cpu_temp_c: ?u32 = null,
    cpu_mhz: ?u32 = null,
    /// CPU plus GPU power.
    power_w: ?u32 = null,
    /// Used space on the root filesystem.
    disk_used_pct: ?u32 = null,
};

pub fn diskColor(used_pct: ?u32) Rgb {
    const pct = used_pct orelse return white;
    if (pct >= 90) return red;
    if (pct >= 70) return yellow;
    return white;
}

pub fn render(reading: Reading) [protocol.led_count]Rgb {
    var out: [protocol.led_count]Rgb = @splat(Rgb.off);

    for ([_]leds.Range{
        leds.bottom_right_stripes, leds.bars, leds.logo_left_stripes, leds.logo_right_stripes,
    }) |r| @memset(out[r.first..r.end()], white);

    out[leds.cpu_label] = white;
    out[leds.celsius_label] = white;
    drawNumber(&out, &leds.temp_digits, reading.cpu_temp_c, white);

    out[leds.watt_label] = white;
    drawNumber(&out, &leds.watt_digits, reading.power_w, white);

    out[leds.mhz_label] = white;
    drawNumber(&out, &leds.mhz_digits, reading.cpu_mhz, white);

    const disk = diskColor(reading.disk_used_pct);
    out[leds.percent_label] = disk;
    if (reading.disk_used_pct) |pct| {
        if (pct >= 100) {
            out[leds.percent_hundred.b] = disk;
            out[leds.percent_hundred.c] = disk;
            for (leds.percent_digits) |d| drawGlyph(&out, d, glyphs[0], disk);
        } else drawNumber(&out, &leds.percent_digits, pct, disk);
    } else drawNumber(&out, &leds.percent_digits, null, disk);

    return out;
}

/// Segment masks, bit `n` = `Segment` with backing integer `n`.
const glyphs = blk: {
    const S = Segment;
    const table = [_][]const S{
        &.{ .a, .b, .c, .d, .e, .f },
        &.{ .b, .c },
        &.{ .a, .b, .d, .e, .g },
        &.{ .a, .b, .c, .d, .g },
        &.{ .b, .c, .f, .g },
        &.{ .a, .c, .d, .f, .g },
        &.{ .a, .c, .d, .e, .f, .g },
        &.{ .a, .b, .c },
        &.{ .a, .b, .c, .d, .e, .f, .g },
        &.{ .a, .b, .c, .d, .f, .g },
    };
    var masks: [10]u7 = undefined;
    for (table, &masks) |segments, *mask| {
        mask.* = 0;
        for (segments) |s| mask.* |= @as(u7, 1) << @backingInt(s);
    }
    break :blk masks;
};
const dash: u7 = 1 << @backingInt(Segment.g);

fn drawGlyph(out: *[protocol.led_count]Rgb, digit: Digit, mask: u7, color: Rgb) void {
    for (digit, 0..) |led, s| {
        out[led] = if (mask & (@as(u7, 1) << @intCast(s)) != 0) color else Rgb.off;
    }
}

/// Draws `value` right-aligned without leading zeros, clamped to the largest
/// number that fits. `digits` runs right to left. `null` draws dashes.
fn drawNumber(out: *[protocol.led_count]Rgb, digits: []const Digit, value: ?u32, color: Rgb) void {
    const v = value orelse {
        for (digits) |d| drawGlyph(out, d, dash, color);
        return;
    };
    const max = std.math.pow(u32, 10, @intCast(digits.len)) - 1;
    var rest = @min(v, max);
    for (digits, 0..) |d, i| {
        const mask: u7 = if (i == 0 or rest != 0) glyphs[rest % 10] else 0;
        drawGlyph(out, d, mask, color);
        rest /= 10;
    }
}

fn litMask(out: *const [protocol.led_count]Rgb, digit: Digit) u7 {
    var mask: u7 = 0;
    for (digit, 0..) |led, s| {
        if (!out[led].isOff()) mask |= @as(u7, 1) << @intCast(s);
    }
    return mask;
}

test "numbers are right-aligned without leading zeros" {
    const out = render(.{ .cpu_temp_c = 7 });
    try std.testing.expectEqual(glyphs[7], litMask(&out, leds.temp_digits[0]));
    try std.testing.expectEqual(0, litMask(&out, leds.temp_digits[1]));
    try std.testing.expectEqual(0, litMask(&out, leds.temp_digits[2]));
}

test "zero shows a single 0" {
    const out = render(.{ .power_w = 0 });
    try std.testing.expectEqual(glyphs[0], litMask(&out, leds.watt_digits[0]));
    try std.testing.expectEqual(0, litMask(&out, leds.watt_digits[1]));
}

test "numbers too large for the digits clamp to all nines" {
    const out = render(.{ .cpu_mhz = 12345 });
    for (leds.mhz_digits) |d| try std.testing.expectEqual(glyphs[9], litMask(&out, d));
}

test "missing readings show dashes" {
    const out = render(.{});
    for (leds.temp_digits ++ leds.watt_digits ++ leds.mhz_digits ++ leds.percent_digits) |d| {
        try std.testing.expectEqual(dash, litMask(&out, d));
    }
}

test "100% lights the leading 1" {
    const out = render(.{ .disk_used_pct = 100 });
    try std.testing.expect(!out[leds.percent_hundred.b].isOff());
    try std.testing.expect(!out[leds.percent_hundred.c].isOff());
    for (leds.percent_digits) |d| try std.testing.expectEqual(glyphs[0], litMask(&out, d));

    const below = render(.{ .disk_used_pct = 99 });
    try std.testing.expect(below[leds.percent_hundred.b].isOff());
}

test "disk usage colours the % area" {
    try std.testing.expectEqual(white, diskColor(69));
    try std.testing.expectEqual(yellow, diskColor(70));
    try std.testing.expectEqual(yellow, diskColor(89));
    try std.testing.expectEqual(red, diskColor(90));

    const out = render(.{ .disk_used_pct = 75, .cpu_temp_c = 50 });
    try std.testing.expectEqual(yellow, out[leds.percent_label]);
    try std.testing.expectEqual(white, out[leds.cpu_label]);
}

test "GPU and °F stay off" {
    const out = render(.{ .cpu_temp_c = 50 });
    try std.testing.expect(out[leds.gpu_label].isOff());
    try std.testing.expect(out[leds.fahrenheit_label].isOff());
}
