//! All sensor sources, opened once at startup. A source that can't be opened
//! is logged and left out; its part of the display shows dashes.

const std = @import("std");
const Io = std.Io;
const display = @import("display.zig");

pub const CpuTemp = @import("sensors/cpu_temp.zig");
pub const CpuFreq = @import("sensors/cpu_freq.zig");
pub const Rapl = @import("sensors/rapl.zig");
pub const Nvml = @import("sensors/nvml.zig");
pub const disk = @import("sensors/disk.zig");

const log = std.log.scoped(.sensors);

cpu_temp: ?CpuTemp,
cpu_freq: ?CpuFreq,
rapl: ?Rapl,
/// Absent on machines without an NVIDIA GPU; power is then CPU only.
nvml: ?Nvml,

const Sensors = @This();

pub fn open(io: Io) Sensors {
    return .{
        .cpu_temp = CpuTemp.open(io) catch |err| blk: {
            log.warn("CPU temperature unavailable: {t}", .{err});
            break :blk null;
        },
        .cpu_freq = CpuFreq.open(io) catch |err| blk: {
            log.warn("CPU clock unavailable: {t}", .{err});
            break :blk null;
        },
        .rapl = Rapl.open(io) catch |err| blk: {
            log.warn("CPU power unavailable: {t} (energy_uj is root-only by default)", .{err});
            break :blk null;
        },
        .nvml = Nvml.open() catch |err| blk: {
            log.info("no NVIDIA GPU power: {t}", .{err});
            break :blk null;
        },
    };
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
