//! CPU clock: the fastest core's `scaling_cur_freq`. With most cores idle the
//! average barely moves, while the fastest core shows boost under load.

const std = @import("std");
const Io = std.Io;
const sysfs = @import("sysfs.zig");

const cpu_root = "/sys/devices/system/cpu";
const max_cpus = 1024;

files: [max_cpus]Io.File,
len: usize,

const CpuFreq = @This();

pub fn open(io: Io) !CpuFreq {
    var root = try Io.Dir.openDirAbsolute(io, cpu_root, .{ .iterate = true });
    defer root.close(io);

    var f: CpuFreq = .{ .files = undefined, .len = 0 };
    errdefer f.close(io);
    var it = root.iterate();
    while (try it.next(io)) |entry| {
        if (!isCpuDir(entry.name) or f.len == max_cpus) continue;
        var path_buf: [64]u8 = undefined;
        const path = std.fmt.bufPrint(&path_buf, "{s}/cpufreq/scaling_cur_freq", .{entry.name}) catch continue;
        f.files[f.len] = root.openFile(io, path, .{}) catch continue;
        f.len += 1;
    }
    if (f.len == 0) return error.SensorNotFound;
    return f;
}

pub fn close(f: CpuFreq, io: Io) void {
    for (f.files[0..f.len]) |file| file.close(io);
}

/// MHz of the fastest core.
pub fn read(f: CpuFreq, io: Io) sysfs.ReadError!u32 {
    var max_khz: u64 = 0;
    for (f.files[0..f.len]) |file| max_khz = @max(max_khz, try sysfs.readInt(io, file));
    return @intCast(@min(max_khz / 1000, std.math.maxInt(u32)));
}

/// `cpu0`, `cpu31`, but not `cpufreq` or `cpuidle`.
fn isCpuDir(name: []const u8) bool {
    if (!std.mem.startsWith(u8, name, "cpu") or name.len == 3) return false;
    for (name[3..]) |c| if (!std.ascii.isDigit(c)) return false;
    return true;
}

test isCpuDir {
    try std.testing.expect(isCpuDir("cpu0"));
    try std.testing.expect(isCpuDir("cpu31"));
    try std.testing.expect(!isCpuDir("cpu"));
    try std.testing.expect(!isCpuDir("cpufreq"));
    try std.testing.expect(!isCpuDir("cpuidle"));
}
