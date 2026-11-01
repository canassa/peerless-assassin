const std = @import("std");
const Io = std.Io;

const pa = @import("peerless_assassin");

const log = std.log;

const usage =
    \\usage: peerless_assassin <command> [--temp C] [--mhz N] [--watts W] [--disk PCT]
    \\
    \\  preview   draw the display in the terminal
    \\  show      keep sending the display to the cooler until interrupted
    \\
    \\A reading left out shows as dashes.
    \\
;

/// The display blanks if frames stop for about 0.5 s.
const frame_interval: Io.Duration = .fromMilliseconds(250);
const reconnect_interval: Io.Duration = .fromSeconds(2);

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len < 2) fail("{s}", .{usage});

    const reading = parseReading(args[2..]);
    const frame = pa.display.render(reading);

    if (std.mem.eql(u8, args[1], "preview")) {
        var stdout_buffer: [4096]u8 = undefined;
        var stdout_file_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
        const stdout = &stdout_file_writer.interface;
        try pa.preview.draw(stdout, &frame);
        try stdout.flush();
    } else if (std.mem.eql(u8, args[1], "show")) {
        try show(io, &frame);
    } else fail("unknown command: {s}\n{s}", .{ args[1], usage });
}

/// Sends `frame` forever, reopening the device whenever it goes away.
fn show(io: Io, frame: *const [pa.protocol.led_count]pa.protocol.Rgb) Io.Cancelable!void {
    while (true) {
        const device = pa.Device.open(io) catch |err| {
            log.warn("cannot open the display: {t}; retrying", .{err});
            try io.sleep(reconnect_interval, .awake);
            continue;
        };
        defer device.close(io);
        log.info("display found", .{});

        while (true) {
            device.send(io, frame) catch |err| {
                log.warn("lost the display: {t}; reconnecting", .{err});
                break;
            };
            try io.sleep(frame_interval, .awake);
        }
        try io.sleep(reconnect_interval, .awake);
    }
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
