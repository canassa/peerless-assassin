//! Which LED index lights which element of the display. See README.md,
//! "LED map". Everything outside this file talks in elements, not indices.

const std = @import("std");
const led_count = @import("protocol.zig").led_count;

pub const Segment = enum(u3) { a, b, c, d, e, f, g };

/// LED index of each segment of a seven-segment digit, indexed by `Segment`.
pub const Digit = [7]u8;

/// A digit whose LEDs are consecutive, in the wire order c, d, e, g, b, a, f.
fn contiguous(first: u8) Digit {
    return .{ first + 5, first + 4, first, first + 1, first + 2, first + 6, first + 3 };
}

pub const Range = struct {
    first: u8,
    len: u8,

    pub fn end(r: Range) u8 {
        return r.first + r.len;
    }
};

// Bottom row: 8888 MHz, 188 %.
pub const bottom_right_stripes: Range = .{ .first = 0, .len = 10 };
pub const percent_label: u8 = 10;
/// Right to left.
pub const percent_digits = [2]Digit{ contiguous(11), contiguous(18) };
/// The leading `1` of 100%: segments b and c only.
pub const percent_hundred = struct {
    pub const b: u8 = 25;
    pub const c: u8 = 26;
};
pub const mhz_label: u8 = 27;
/// Right to left.
pub const mhz_digits = [4]Digit{ contiguous(28), contiguous(35), contiguous(42), contiguous(49) };

/// Left to right. Each LED lights the same spot on both divider lines.
pub const bars: Range = .{ .first = 56, .len = 14 };

// Top row: CPU/GPU 888 °C°F, 888 W.
pub const watt_label: u8 = 70;
/// Right to left.
pub const watt_digits = [3]Digit{ contiguous(71), contiguous(78), contiguous(85) };
pub const celsius_label: u8 = 92;
pub const fahrenheit_label: u8 = 93;
pub const gpu_label: u8 = 100;
/// Right to left. The right digit skips LED 100, the `GPU` label inside it.
pub const temp_digits = [3]Digit{
    .{ 99, 98, 94, 95, 96, 101, 97 },
    contiguous(102),
    contiguous(109),
};
pub const cpu_label: u8 = 116;
pub const logo_left_stripes: Range = .{ .first = 117, .len = 12 };
pub const logo_right_stripes: Range = .{ .first = 129, .len = 15 };

test "every LED belongs to exactly one element" {
    var uses: [led_count]u8 = @splat(0);
    for ([_]u8{
        percent_label, percent_hundred.b, percent_hundred.c, mhz_label,
        watt_label,    celsius_label,     fahrenheit_label,  gpu_label,
        cpu_label,
    }) |i| uses[i] += 1;
    for (percent_digits ++ mhz_digits ++ watt_digits ++ temp_digits) |digit| {
        for (digit) |i| uses[i] += 1;
    }
    for ([_]Range{ bottom_right_stripes, bars, logo_left_stripes, logo_right_stripes }) |r| {
        for (r.first..r.end()) |i| uses[i] += 1;
    }
    for (uses, 0..) |n, i| {
        errdefer std.debug.print("LED {d} is used {d} times\n", .{ i, n });
        try std.testing.expectEqual(1, n);
    }
}

test "contiguous digits follow the c, d, e, g, b, a, f wire order" {
    const d = contiguous(11);
    try std.testing.expectEqual(11, d[@backingInt(Segment.c)]);
    try std.testing.expectEqual(14, d[@backingInt(Segment.g)]);
    try std.testing.expectEqual(17, d[@backingInt(Segment.f)]);
}
