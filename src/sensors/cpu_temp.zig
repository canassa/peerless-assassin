//! CPU temperature from hwmon: AMD `k10temp` Tctl, or Intel `coretemp`
//! package temperature. hwmon numbers change between boots, so the sensor is
//! found by driver name and label.

const std = @import("std");
const Io = std.Io;
const sysfs = @import("sysfs.zig");

const hwmon_root = "/sys/class/hwmon";

const Candidate = struct { name: []const u8, label: []const u8 };
const candidates = [_]Candidate{
    .{ .name = "k10temp", .label = "Tctl" },
    .{ .name = "coretemp", .label = "Package id 0" },
};

input: Io.File,

const CpuTemp = @This();

pub fn open(io: Io) !CpuTemp {
    var root = try Io.Dir.openDirAbsolute(io, hwmon_root, .{ .iterate = true });
    defer root.close(io);

    var it = root.iterate();
    while (try it.next(io)) |entry| {
        var hwmon = root.openDir(io, entry.name, .{ .iterate = true }) catch continue;
        defer hwmon.close(io);

        var name_buf: [64]u8 = undefined;
        const name = sysfs.readText(io, hwmon, "name", &name_buf) orelse continue;
        const candidate = for (candidates) |c| {
            if (std.mem.eql(u8, c.name, name)) break c;
        } else continue;

        if (try findInput(io, hwmon, candidate.label)) |input| return .{ .input = input };
    }
    return error.SensorNotFound;
}

/// Opens the `tempN_input` whose `tempN_label` is `label`.
fn findInput(io: Io, hwmon: Io.Dir, label: []const u8) !?Io.File {
    var it = hwmon.iterate();
    while (try it.next(io)) |entry| {
        if (!std.mem.startsWith(u8, entry.name, "temp") or !std.mem.endsWith(u8, entry.name, "_label")) continue;

        var label_buf: [64]u8 = undefined;
        const text = sysfs.readText(io, hwmon, entry.name, &label_buf) orelse continue;
        if (!std.mem.eql(u8, text, label)) continue;

        var path_buf: [64]u8 = undefined;
        const prefix = entry.name[0 .. entry.name.len - "_label".len];
        const input_path = std.fmt.bufPrint(&path_buf, "{s}_input", .{prefix}) catch continue;
        return try hwmon.openFile(io, input_path, .{});
    }
    return null;
}

pub fn close(t: CpuTemp, io: Io) void {
    t.input.close(io);
}

/// Degrees Celsius, rounded.
pub fn read(t: CpuTemp, io: Io) sysfs.ReadError!u32 {
    return celsius(try sysfs.readInt(io, t.input));
}

/// hwmon reports millidegrees.
fn celsius(millidegrees: u64) u32 {
    return @intCast(@min((millidegrees + 500) / 1000, std.math.maxInt(u32)));
}

test celsius {
    try std.testing.expectEqual(45, celsius(45250));
    try std.testing.expectEqual(46, celsius(45500));
    try std.testing.expectEqual(0, celsius(0));
}
