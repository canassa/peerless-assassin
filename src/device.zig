//! Finds the display's hidraw node and writes frames to it. See README.md,
//! "Device".

const std = @import("std");
const Io = std.Io;
const protocol = @import("protocol.zig");

/// `HID_ID` in the hidraw device's uevent: USB bus, vendor 0416, product 8001.
const hid_id = "HID_ID=0003:00000416:00008001";

const sysfs_hidraw = "/sys/class/hidraw";

file: Io.File,

const Device = @This();

pub const OpenError = error{DeviceNotFound} || Io.Dir.OpenError || Io.Dir.Iterator.Error || Io.File.OpenError;

/// Opens the first hidraw node whose USB ID matches the display.
pub fn open(io: Io) OpenError!Device {
    var dir = try Io.Dir.openDirAbsolute(io, sysfs_hidraw, .{ .iterate = true });
    defer dir.close(io);

    var it = dir.iterate();
    while (try it.next(io)) |entry| {
        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const uevent_path = std.fmt.bufPrint(&path_buf, "{s}/device/uevent", .{entry.name}) catch continue;
        var uevent_buf: [1024]u8 = undefined;
        const uevent = dir.readFile(io, uevent_path, &uevent_buf) catch continue;
        if (!matchesUevent(uevent)) continue;

        const dev_path = std.fmt.bufPrint(&path_buf, "/dev/{s}", .{entry.name}) catch continue;
        const file = try Io.Dir.openFileAbsolute(io, dev_path, .{ .mode = .write_only });
        return .{ .file = file };
    }
    return error.DeviceNotFound;
}

pub fn close(d: Device, io: Io) void {
    d.file.close(io);
}

/// Sends one frame. Each report must go out in a single write.
pub fn send(d: Device, io: Io, leds: *const [protocol.led_count]protocol.Rgb) !void {
    const reports = protocol.encode(leds);
    for (&reports) |*report| {
        const n = try d.file.writeStreaming(io, &.{}, &.{report}, 1);
        if (n != report.len) return error.ShortWrite;
    }
}

fn matchesUevent(uevent: []const u8) bool {
    var lines = std.mem.splitScalar(u8, uevent, '\n');
    while (lines.next()) |line| {
        if (std.mem.eql(u8, line, hid_id)) return true;
    }
    return false;
}

test "matchesUevent finds the display's HID_ID line" {
    try std.testing.expect(matchesUevent(
        \\DRIVER=hid-generic
        \\HID_ID=0003:00000416:00008001
        \\HID_NAME=Nuvoton HID Transfer
        \\
    ));
    try std.testing.expect(!matchesUevent(
        \\DRIVER=hid-generic
        \\HID_ID=0003:0000046D:0000C52B
        \\
    ));
    try std.testing.expect(!matchesUevent("HID_ID=0003:00000416:000080010"));
}
