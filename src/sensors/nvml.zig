//! NVIDIA GPU power through NVML, the library behind `nvidia-smi`. It is
//! loaded at runtime, so the program still runs on machines without the
//! NVIDIA driver.

const std = @import("std");

/// The bare name is found through the normal library path; NixOS keeps the
/// driver's libraries under /run/opengl-driver/lib instead.
const library_paths = [_][]const u8{
    "libnvidia-ml.so.1",
    "/run/opengl-driver/lib/libnvidia-ml.so.1",
};

const max_devices = 8;

const Return = c_int;
const success: Return = 0;
const Device = *opaque {};

const Api = struct {
    init: *const fn () callconv(.c) Return,
    shutdown: *const fn () callconv(.c) Return,
    getCount: *const fn (count: *c_uint) callconv(.c) Return,
    getHandleByIndex: *const fn (index: c_uint, device: *Device) callconv(.c) Return,
    getPowerUsage: *const fn (device: Device, milliwatts: *c_uint) callconv(.c) Return,
};

lib: std.DynLib,
api: Api,
devices: [max_devices]Device,
len: usize,

const Nvml = @This();

pub fn open() !Nvml {
    var lib = for (library_paths) |path| {
        break std.DynLib.open(path) catch continue;
    } else return error.LibraryNotFound;
    errdefer lib.close();

    const api: Api = .{
        .init = lib.lookup(@FieldType(Api, "init"), "nvmlInit_v2") orelse return error.SymbolNotFound,
        .shutdown = lib.lookup(@FieldType(Api, "shutdown"), "nvmlShutdown") orelse return error.SymbolNotFound,
        .getCount = lib.lookup(@FieldType(Api, "getCount"), "nvmlDeviceGetCount_v2") orelse return error.SymbolNotFound,
        .getHandleByIndex = lib.lookup(@FieldType(Api, "getHandleByIndex"), "nvmlDeviceGetHandleByIndex_v2") orelse return error.SymbolNotFound,
        .getPowerUsage = lib.lookup(@FieldType(Api, "getPowerUsage"), "nvmlDeviceGetPowerUsage") orelse return error.SymbolNotFound,
    };
    if (api.init() != success) return error.InitFailed;
    errdefer _ = api.shutdown();

    var n: Nvml = .{ .lib = lib, .api = api, .devices = undefined, .len = 0 };
    var count: c_uint = 0;
    if (api.getCount(&count) != success) return error.InitFailed;
    for (0..@min(count, max_devices)) |i| {
        if (api.getHandleByIndex(@intCast(i), &n.devices[n.len]) == success) n.len += 1;
    }
    if (n.len == 0) return error.SensorNotFound;
    return n;
}

pub fn close(n: *Nvml) void {
    _ = n.api.shutdown();
    n.lib.close();
}

/// Total watts drawn by all GPUs, rounded.
pub fn read(n: Nvml) error{ReadFailed}!u32 {
    var total_mw: u32 = 0;
    for (n.devices[0..n.len]) |device| {
        var mw: c_uint = 0;
        if (n.api.getPowerUsage(device, &mw) != success) return error.ReadFailed;
        total_mw +|= mw;
    }
    return (total_mw + 500) / 1000;
}
