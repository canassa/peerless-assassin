//! All sensor sources. A source that can't be opened is logged and left out,
//! and its part of the display shows dashes. Missing sources are retried now
//! and then: at boot the service can start before udev has made the RAPL
//! counter readable.

const std = @import("std");
const Io = std.Io;
const display = @import("display.zig");

pub const CpuTemp = @import("sensors/cpu_temp.zig");
pub const CpuFreq = @import("sensors/cpu_freq.zig");
pub const Rapl = @import("sensors/rapl.zig");
pub const Nvml = @import("sensors/nvml.zig");
pub const disk = @import("sensors/disk.zig");

const log = std.log.scoped(.sensors);

const retry_interval: Io.Duration = .fromSeconds(30);

cpu_temp: ?CpuTemp = null,
cpu_freq: ?CpuFreq = null,
rapl: ?Rapl = null,
/// Absent on machines without an NVIDIA GPU; power is then CPU only.
nvml: ?Nvml = null,
last_attempt: Io.Timestamp,

const Sensors = @This();

pub fn open(io: Io) Sensors {
    var s: Sensors = .{ .last_attempt = .now(io, .awake) };
    s.openMissing(io, true);
    return s;
}

fn openMissing(s: *Sensors, io: Io, first: bool) void {
    if (s.cpu_temp == null) s.cpu_temp = opened(CpuTemp, "CPU temperature", CpuTemp.open(io), first);
    if (s.cpu_freq == null) s.cpu_freq = opened(CpuFreq, "CPU clock", CpuFreq.open(io), first);
    if (s.rapl == null) s.rapl = opened(Rapl, "CPU power (RAPL energy_uj)", Rapl.open(io), first);
    if (s.nvml == null) s.nvml = opened(Nvml, "NVIDIA GPU power", Nvml.open(), first);
    s.last_attempt = .now(io, .awake);
}

/// Logs a failure on the first attempt only, and a later success.
fn opened(comptime T: type, what: []const u8, result: anyerror!T, first: bool) ?T {
    const value = result catch |err| {
        if (first) log.warn("{s} unavailable: {t}; retrying every 30 s", .{ what, err });
        return null;
    };
    if (!first) log.info("{s} now available", .{what});
    return value;
}

pub fn close(s: *Sensors, io: Io) void {
    if (s.cpu_temp) |t| t.close(io);
    if (s.cpu_freq) |f| f.close(io);
    if (s.rapl) |r| r.close(io);
    if (s.nvml) |*n| n.close();
}

/// Reads every source. CPU power compares against the previous call, so the
/// first reading has no power figure.
pub fn read(s: *Sensors, io: Io) display.Reading {
    if (s.last_attempt.untilNow(io, .awake).nanoseconds >= retry_interval.nanoseconds) {
        s.openMissing(io, false);
    }
    return .{
        .cpu_temp_c = if (s.cpu_temp) |t| t.read(io) catch null else null,
        .cpu_mhz = if (s.cpu_freq) |f| f.read(io) catch null else null,
        .power_w = s.readPower(io),
        .disk_used_pct = disk.usedPercent("/") catch null,
    };
}

/// CPU plus GPU. Without the CPU part the total would mislead, so it shows
/// nothing; without an NVIDIA GPU it is the CPU alone.
fn readPower(s: *Sensors, io: Io) ?u32 {
    const rapl = if (s.rapl) |*r| r else return null;
    const cpu = (rapl.read(io) catch return null) orelse return null;
    const gpu = if (s.nvml) |n| n.read() catch return null else 0;
    return cpu + gpu;
}

test {
    _ = CpuTemp;
    _ = CpuFreq;
    _ = Rapl;
    _ = Nvml;
    _ = disk;
    _ = @import("sensors/sysfs.zig");
}
