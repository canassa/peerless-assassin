//! Used space on a filesystem, computed the way `df` does.

const std = @import("std");
const linux = std.os.linux;

/// `struct statfs` for 64-bit Linux.
const Statfs = extern struct {
    type: i64,
    bsize: i64,
    blocks: u64,
    bfree: u64,
    bavail: u64,
    files: u64,
    ffree: u64,
    fsid: [2]i32,
    namelen: i64,
    frsize: i64,
    flags: i64,
    spare: [4]i64,
};

comptime {
    std.debug.assert(@sizeOf(usize) == 8);
    std.debug.assert(@sizeOf(Statfs) == 120);
}

pub fn usedPercent(path: [*:0]const u8) error{StatfsFailed}!u32 {
    var s: Statfs = undefined;
    const rc = linux.syscall2(.statfs, @intFromPtr(path), @intFromPtr(&s));
    if (linux.errno(rc) != .SUCCESS) return error.StatfsFailed;
    return percent(s.blocks, s.bfree, s.bavail);
}

/// Like `df`: space reserved for root counts as neither used nor available,
/// and the result rounds up.
fn percent(blocks: u64, bfree: u64, bavail: u64) u32 {
    const used = blocks -| bfree;
    const total = used + bavail;
    if (total == 0) return 0;
    return @intCast(std.math.divCeil(u64, used * 100, total) catch unreachable);
}

test percent {
    try std.testing.expectEqual(29, percent(1000, 715, 715));
    try std.testing.expectEqual(1, percent(1000, 999, 999));
    try std.testing.expectEqual(100, percent(1000, 0, 0));
    try std.testing.expectEqual(0, percent(0, 0, 0));
    // 5% reserved for root: used / (used + available), not used / blocks.
    try std.testing.expectEqual(53, percent(1000, 500, 450));
}

test usedPercent {
    const pct = try usedPercent("/");
    try std.testing.expect(pct <= 100);
}
