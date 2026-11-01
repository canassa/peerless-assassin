---
name: zig-developer
description: Use when writing, reviewing, debugging, or answering questions about Zig code in peerless-assassin (a Linux driver for the Thermalright Peerless Assassin cooler's segment display, written in Zig). Provides a Zig 0.16-to-0.17 change summary, an offline 0.16 language reference, and memory doctrine for a small long-running daemon. Check the installed Zig 0.17 standard library for exact APIs rather than relying on memory.
---

# Zig developer for peerless-assassin

peerless-assassin drives the segment display on a Thermalright Peerless
Assassin CPU cooler from Linux. It reads system sensors (CPU/GPU temperature,
clock, power, load), renders them onto the display's 144 LEDs, and writes
frames to the device over hidraw. The wire protocol and LED map are in
[`README.md`](../../../README.md) — read it before touching anything that
builds or sends a frame.

Zig breaks API between releases, so **never answer Zig questions from memory** —
look it up:

- **Installed std library source — THE GOLD STANDARD.** Not just API docs: it
  is the reference for how to *write* Zig — naming, error handling, allocator
  threading, doc comments, test placement. Before writing a non-trivial module,
  find an analogous std module and mirror its conventions. `zig env` locates it;
  it prints **ZON, not JSON** — do not pipe it to `jq`:

  ```sh
  STD=$(zig env | sed -n 's/.*\.std_dir = "\(.*\)".*/\1/p')
  grep -n "pub fn ioctl" "$STD/os/linux.zig"
  ```

  Useful starting points: `os/linux.zig` (raw syscalls, `ioctl`, `IOCTL`
  encoding), `Io.zig` and `Io/` (files, timers, sleeping), `fs/`, `fmt.zig`,
  `heap/`.
- **Zig 0.16 → 0.17:** [`zig-0.17-changes.md`](zig-0.17-changes.md). Read this
  before trusting anything in the language reference.
- **Language reference (offline, split by section):** `zig-langref/` (in this
  skill directory) — one Markdown file per top-level section, converted from
  <https://ziglang.org/documentation/0.16.0/>. It describes 0.16, so it is
  historical: pick only the relevant section from its `README.md` index; never
  load the whole thing.
- **Memory doctrine:** [`memory-and-performance.md`](memory-and-performance.md)
  — allocate at startup, then zero allocation per tick.

## House rules

- **The protocol lives in one place.** Frame layout, chunking and the LED map
  are encoded once (constants and a pure frame builder) and tested against the
  README. Rendering code works in terms of digits, glyphs and indicators, never
  raw LED numbers.
- **Frame building is pure.** `fn` from a display state to `[N]u8` bytes, no
  I/O — so it is unit-testable without hardware. Lock sizes with
  `comptime { std.debug.assert(...) }` (144 LEDs, 0x1B0 payload bytes,
  64-byte reports).
- **Hardware and sensors sit behind thin boundaries.** The hidraw writer and
  each sensor source (hwmon, `/proc/stat`, cpufreq, GPU) are small modules the
  core never reaches past, so tests can feed fake readings.
- **Keep frames flowing.** The display blanks if writes stop for ~0.5 s. The
  main loop must never block on a slow sensor; a failed reading shows a blank
  or dash, it doesn't stall the frame.
- **Survive the device going away.** Unplug, suspend/resume and permission
  errors are expected: log, back off, reopen. Never panic on I/O.
- **Panics mean bugs.** Nothing read from sysfs, `/proc` or the device may
  reach a panic or `unreachable`; parse defensively and return errors.
- **No global mutable state.** Config, open handles and buffers hang off one
  struct created in `main`.

## Commands

The toolchain is pinned: `flake.nix` + `.envrc` (`use flake`) provide Zig
**0.17.0** from nixpkgs (`zig_0_17`). ZLS is absent: nixpkgs has none for 0.17
yet. Direnv puts Zig on `PATH`; outside a direnv shell, prefix with
`direnv exec .`.

```sh
zig build                    # install zig-out/bin/peerless_assassin
zig build run -- <args>      # build and run
zig build test               # unit tests
zig fmt --check build.zig src
```

Talking to the real device needs the udev rule from the README (or root).
Don't assume the device is present in tests.

For a toolchain upgrade: bump `zig_0_17` in `flake.nix`, read the release notes,
fix what breaks, and update `zig-0.17-changes.md` and this file.
