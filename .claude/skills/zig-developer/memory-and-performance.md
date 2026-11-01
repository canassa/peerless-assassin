# Memory & performance (Zig 0.17)

peerless-assassin is a small daemon that runs forever and does the same thing
a few times a second: read sensors, render, write a frame. The right shape for
that is **allocate at startup, then zero allocation per tick.** It is not
performance-critical, but it must not leak, fragment or stall over weeks of
uptime.

Check every signature below against the installed std (`zig env` →
`std_dir`); see [`zig-0.17-changes.md`](zig-0.17-changes.md).

## The rules

1. **Everything sized by the protocol is a fixed array.** 128 LEDs, a
   0x180-byte payload, 64-byte reports: `[128]Rgb`, `[64]u8`. No allocator.
2. **Set up once.** Open the device, resolve sensor paths (hwmon index,
   cpufreq files), parse config — at startup, with an arena that is freed or
   kept for the program's life.
3. **Per tick: no `alloc`/`free`.** Read sysfs into a stack buffer
   (`[64]u8`), parse in place, format digits without allocating. If a tick
   genuinely needs scratch, give it an `ArenaAllocator` and
   `reset(.retain_capacity)` each tick — after the first tick it never asks
   the OS for memory again.
4. **Keep files open where it helps.** sysfs/`/proc` attributes can be re-read
   with a positional read at offset 0 instead of reopening each tick.
5. **Use a checking allocator in debug and tests.** Leaks fail the test run.

## Allocators (0.17)

All in `$STD/heap/`. Read the source before using.

| Allocator | Use for |
|---|---|
| `std.heap.SafeAllocator` (replaces deprecated `DebugAllocator`) | Debug builds and tests: leak and double-free detection. Its `deinit` reports leaks. |
| `std.heap.smp_allocator` | Release root allocator. |
| `std.heap.ArenaAllocator` | Startup/config parsing; per-tick scratch with `reset(.retain_capacity)`. |
| `std.heap.FixedBufferAllocator` | Bounded scratch over a stack `[N]u8` when an API insists on an allocator. |
| `std.testing.allocator` | Tests. |

Traps:

- `std.BoundedArray` is gone — use `[N]T` + `len`, or `ArrayList` with
  `initCapacity` + `*AssumeCapacity`.
- `std.ArrayList` is unmanaged: the allocator is passed per call.
- `std.fmt.allocPrint(a, ...)` → `a.print(...)` in 0.17. For per-tick text,
  prefer `std.fmt.bufPrint` into a stack buffer.

## Small and exact

- Smallest types that fit: `u8` colour channels, `u4` digits, `enum(u8)` for
  segments and indicators.
- Use `extern struct` or explicit byte arrays for anything that goes on the
  wire, and lock it: `comptime { std.debug.assert(@sizeOf(Header) == 20); }`.
  Write multi-byte fields with `std.mem.writeInt(u16, buf, v, .little)`, not
  `@bitCast` (its semantics changed in 0.17).
- Lookup tables (digit → segment mask, LED index tables) are `const` arrays
  built at comptime.

## Measure only if it matters

It almost never will at a few Hz. If CPU use shows up in `top`, look first for
reopened files, re-scanned directories or allocation per tick:
`perf stat -e task-clock,page-faults ./zig-out/bin/peerless_assassin`.
