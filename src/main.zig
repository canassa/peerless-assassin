const std = @import("std");
const Io = std.Io;

const pa = @import("peerless_assassin");

const log = std.log;

const usage =
    \\usage: peerless_assassin run
    \\       peerless_assassin preview --live
    \\       peerless_assassin preview|show [--temp C] [--mhz N] [--watts W] [--disk PCT]
    \\
    \\  run       show live sensor readings on the cooler until interrupted
    \\  preview   draw the display in the terminal
    \\  show      keep sending the given readings to the cooler until interrupted
    \\
    \\A reading left out shows as dashes.
    \\
;

/// The display blanks if frames stop for about 0.5 s.
const frame_interval: Io.Duration = .fromMilliseconds(250);
const sample_interval: Io.Duration = .fromSeconds(1);
const reconnect_interval: Io.Duration = .fromSeconds(2);

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len < 2) fail("{s}", .{usage});
    const command = args[1];
    const options = args[2..];

    if (std.mem.eql(u8, command, "run")) {
        if (options.len != 0) fail("{s}", .{usage});
        var sensors: pa.Sensors = .open(io);
        defer sensors.close(io);
        try drive(io, .{ .live = &sensors });
    } else if (std.mem.eql(u8, command, "show")) {
        try drive(io, .{ .fixed = parseReading(options) });
    } else if (std.mem.eql(u8, command, "preview")) {
        const reading = if (options.len == 1 and std.mem.eql(u8, options[0], "--live"))
            try liveReading(io)
        else
            parseReading(options);
        try preview(io, reading);
    } else fail("unknown command: {s}\n{s}", .{ command, usage });
}

const Source = union(enum) {
    fixed: pa.display.Reading,
    live: *pa.Sensors,

    fn sample(s: Source, io: Io) pa.display.Reading {
        return switch (s) {
            .fixed => |r| r,
            .live => |sensors| sensors.read(io),
        };
    }
};

/// Sends frames forever, re-sampling live sensors every `sample_interval`
/// and reopening the device whenever it goes away.
fn drive(io: Io, source: Source) Io.Cancelable!void {
    var frame = pa.display.render(source.sample(io));
    var sampled_at: Io.Timestamp = .now(io, .awake);

    while (true) {
        const device = pa.Device.open(io) catch |err| {
            log.warn("cannot open the display: {t}; retrying", .{err});
            try io.sleep(reconnect_interval, .awake);
            continue;
        };
        defer device.close(io);
        log.info("display found", .{});

        while (true) {
            if (source == .live and sampled_at.untilNow(io, .awake).nanoseconds >= sample_interval.nanoseconds) {
                frame = pa.display.render(source.sample(io));
                sampled_at = .now(io, .awake);
            }
            device.send(io, &frame) catch |err| {
                log.warn("lost the display: {t}; reconnecting", .{err});
                break;
            };
            try io.sleep(frame_interval, .awake);
        }
        try io.sleep(reconnect_interval, .awake);
    }
}

/// Samples twice, a second apart, so CPU power has something to compare.
fn liveReading(io: Io) Io.Cancelable!pa.display.Reading {
    var sensors: pa.Sensors = .open(io);
    defer sensors.close(io);
    _ = sensors.read(io);
    try io.sleep(sample_interval, .awake);
    return sensors.read(io);
}

fn preview(io: Io, reading: pa.display.Reading) !void {
    var stdout_buffer: [4096]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const stdout = &stdout_file_writer.interface;
    const frame = pa.display.render(reading);
    try pa.preview.draw(stdout, &frame);
    try stdout.flush();
}

fn parseReading(args: []const [:0]const u8) pa.display.Reading {
    var reading: pa.display.Reading = .{};
    var i: usize = 0;
    while (i < args.len) : (i += 2) {
        const field: *?u32 = if (std.mem.eql(u8, args[i], "--temp"))
            &reading.cpu_temp_c
        else if (std.mem.eql(u8, args[i], "--mhz"))
            &reading.cpu_mhz
        else if (std.mem.eql(u8, args[i], "--watts"))
            &reading.power_w
        else if (std.mem.eql(u8, args[i], "--disk"))
            &reading.disk_used_pct
        else
            fail("unknown option: {s}\n{s}", .{ args[i], usage });
        if (i + 1 >= args.len) fail("{s} needs a value\n", .{args[i]});
        field.* = std.fmt.parseInt(u32, args[i + 1], 10) catch
            fail("{s}: not a number: {s}\n", .{ args[i], args[i + 1] });
    }
    return reading;
}

fn fail(comptime fmt: []const u8, args: anytype) noreturn {
    std.debug.print(fmt, args);
    std.process.exit(2);
}
