//! Reading integer attributes from sysfs. Attribute files are opened once and
//! re-read from offset 0, which makes the kernel produce a fresh value.

const std = @import("std");
const Io = std.Io;

pub const ReadError = Io.File.ReadPositionalError || error{InvalidValue};

pub fn readInt(io: Io, file: Io.File) ReadError!u64 {
    var buf: [32]u8 = undefined;
    const n = try file.readPositional(io, &.{&buf}, 0);
    return parseInt(buf[0..n]);
}

pub fn parseInt(text: []const u8) error{InvalidValue}!u64 {
    const trimmed = std.mem.trim(u8, text, " \n");
    return std.fmt.parseInt(u64, trimmed, 10) catch error.InvalidValue;
}

/// Reads a small text attribute, such as a hwmon `name`, without the newline.
pub fn readText(io: Io, dir: Io.Dir, path: []const u8, buf: []u8) ?[]const u8 {
    const text = dir.readFile(io, path, buf) catch return null;
    return std.mem.trimEnd(u8, text, "\n");
}

test parseInt {
    try std.testing.expectEqual(45250, try parseInt("45250\n"));
    try std.testing.expectError(error.InvalidValue, parseInt(""));
    try std.testing.expectError(error.InvalidValue, parseInt("-1\n"));
    try std.testing.expectError(error.InvalidValue, parseInt("abc"));
}
