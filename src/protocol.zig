//! Wire format of the display: one frame carries a colour for every LED and is
//! sent as a run of 64-byte HID output reports. See README.md, "Frame".

const std = @import("std");

pub const Rgb = struct {
    r: u8,
    g: u8,
    b: u8,

    pub const off: Rgb = .{ .r = 0, .g = 0, .b = 0 };

    pub fn isOff(c: Rgb) bool {
        return c.r == 0 and c.g == 0 and c.b == 0;
    }
};

pub const led_count = 144;

const magic = [4]u8{ 0xda, 0xdb, 0xdc, 0xdd };
pub const header_len = 20;
pub const payload_len = led_count * 3;
pub const frame_len = header_len + payload_len;

/// Data bytes in one HID report, not counting the leading report ID.
pub const report_len = 64;
pub const report_count = std.math.divCeil(usize, frame_len, report_len) catch unreachable;

/// One report as written to hidraw: report ID 0, then 64 data bytes.
pub const Report = [1 + report_len]u8;

comptime {
    std.debug.assert(payload_len == 0x01b0);
    std.debug.assert(report_count == 8);
}

/// Encodes one frame into the reports to write, in order. The last report is
/// zero-padded.
pub fn encode(leds: *const [led_count]Rgb) [report_count]Report {
    var frame: [report_count * report_len]u8 = @splat(0);
    frame[0..4].* = magic;
    std.mem.writeInt(u16, frame[16..18], payload_len, .little);
    frame[18..20].* = .{ 0x00, 0xff };
    for (leds, 0..) |c, i| {
        frame[header_len + 3 * i ..][0..3].* = .{ c.r, c.g, c.b };
    }

    var reports: [report_count]Report = undefined;
    for (&reports, 0..) |*report, i| {
        report[0] = 0;
        report[1..].* = frame[i * report_len ..][0..report_len].*;
    }
    return reports;
}

test "encode lays out header, payload and padding" {
    var leds: [led_count]Rgb = @splat(Rgb.off);
    leds[0] = .{ .r = 0x11, .g = 0x22, .b = 0x33 };
    leds[led_count - 1] = .{ .r = 0xaa, .g = 0xbb, .b = 0xcc };
    const reports = encode(&leds);

    for (reports) |report| try std.testing.expectEqual(0, report[0]);

    const first = reports[0][1..];
    try std.testing.expectEqualSlices(u8, &magic, first[0..4]);
    try std.testing.expectEqualSlices(u8, &@as([12]u8, @splat(0)), first[4..16]);
    try std.testing.expectEqualSlices(u8, &.{ 0xb0, 0x01, 0x00, 0xff }, first[16..20]);
    try std.testing.expectEqualSlices(u8, &.{ 0x11, 0x22, 0x33 }, first[20..23]);

    // The frame is 452 bytes: 7 full reports, then 4 bytes in the last one,
    // the blue of LED 142 and all of LED 143.
    const last = reports[report_count - 1][1..];
    try std.testing.expectEqualSlices(u8, &.{ 0x00, 0xaa, 0xbb, 0xcc }, last[0..4]);
    try std.testing.expectEqualSlices(u8, &@as([60]u8, @splat(0)), last[4..]);
}
