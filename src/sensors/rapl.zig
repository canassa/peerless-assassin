//! CPU package power from RAPL (powercap). The kernel exposes a running
//! energy counter in microjoules; power is its change over time. On AMD the
//! zone is still called `intel-rapl`.
//!
//! `energy_uj` is root-only by default, so opening usually fails for a normal
//! user until its permissions are relaxed.

const std = @import("std");
const Io = std.Io;
const sysfs = @import("sysfs.zig");

const powercap_root = "/sys/class/powercap";

energy: Io.File,
/// The counter wraps to 0 after this many microjoules.
max_range_uj: u64,
last: ?Sample = null,

const Rapl = @This();

const Sample = struct { energy_uj: u64, time: Io.Timestamp };

pub fn open(io: Io) !Rapl {
    var root = try Io.Dir.openDirAbsolute(io, powercap_root, .{ .iterate = true });
    defer root.close(io);

    var it = root.iterate();
    while (try it.next(io)) |entry| {
        var zone = root.openDir(io, entry.name, .{}) catch continue;
        defer zone.close(io);

        var name_buf: [64]u8 = undefined;
        const name = sysfs.readText(io, zone, "name", &name_buf) orelse continue;
        if (!std.mem.eql(u8, name, "package-0")) continue;

        const range_file = try zone.openFile(io, "max_energy_range_uj", .{});
        defer range_file.close(io);
        const max_range_uj = try sysfs.readInt(io, range_file);
        return .{
            .energy = try zone.openFile(io, "energy_uj", .{}),
            .max_range_uj = max_range_uj,
        };
    }
    return error.SensorNotFound;
}

pub fn close(r: Rapl, io: Io) void {
    r.energy.close(io);
}

/// Average watts since the previous call. The first call has nothing to
/// compare against and returns null.
pub fn read(r: *Rapl, io: Io) sysfs.ReadError!?u32 {
    const now: Sample = .{
        .energy_uj = try sysfs.readInt(io, r.energy),
        .time = .now(io, .awake),
    };
    defer r.last = now;
    const last = r.last orelse return null;
    const elapsed_us = last.time.durationTo(now.time).toMicroseconds();
    return watts(last.energy_uj, now.energy_uj, r.max_range_uj, elapsed_us);
}

fn watts(before_uj: u64, after_uj: u64, max_range_uj: u64, elapsed_us: i64) ?u32 {
    if (elapsed_us <= 0) return null;
    const delta_uj = if (after_uj >= before_uj)
        after_uj - before_uj
    else
        max_range_uj - before_uj + after_uj;
    // µJ / µs = W
    const us: u64 = @intCast(elapsed_us);
    return @intCast(@min((delta_uj + us / 2) / us, std.math.maxInt(u32)));
}

test watts {
    try std.testing.expectEqual(87, watts(1_000_000, 88_000_000, 1 << 32, 1_000_000));
    try std.testing.expectEqual(null, watts(0, 100, 1 << 32, 0));
    // The counter wrapped: 10 J before the wrap plus 40 J after, over 1 s.
    try std.testing.expectEqual(50, watts(90_000_000, 40_000_000, 100_000_000, 1_000_000));
}
