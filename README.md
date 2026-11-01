# Thermalright Peerless Assassin — segment display protocol

Reverse-engineered notes for the cooler's digital display, and a small Zig
program that drives it from Linux: CPU temperature, CPU clock, CPU + GPU
power and used disk space.

## Usage

```sh
nix run github:canassa/peerless-assassin -- run              # live readings to the cooler
nix run github:canassa/peerless-assassin -- preview --live   # same, drawn in the terminal
```

On NixOS, the module runs it as a service, gives it access to the display and
makes the CPU energy counter readable for the power figure:

```nix
{
  inputs.peerless-assassin.url = "github:canassa/peerless-assassin";

  # in the system's modules:
  imports = [ inputs.peerless-assassin.nixosModules.default ];
  services.peerless-assassin.enable = true;
}
```

GPU power comes from NVML, so it needs the NVIDIA driver; without it the
power figure is the CPU alone.

## Device

- USB `0416:8001`, "Nuvoton HID Transfer" (`hid-generic` → `/dev/hidrawN`)
- Vendor-defined HID: 64-byte IN/OUT interrupt reports, no report ID
- The device never sends anything back
- Root-only by default. NixOS udev rule:

  ```
  SUBSYSTEM=="hidraw", ATTRS{idVendor}=="0416", ATTRS{idProduct}=="8001", GROUP="input", MODE="0660"
  ```

  (`TAG+="uaccess"` doesn't work from `services.udev.extraRules`: it lands in
  `99-local.rules`, after `73-seat-late.rules` has applied the ACLs.)

## Frame

```
da db dc dd | 00 x12 | len (u16 LE) | 00 ff | RR GG BB × 144
```

- `len` is the payload size in bytes: `0x01B0` for 144 LEDs. A 128-LED
  frame (`0x0180`) also displays, but leaves LEDs 128–143 dark. Some wrong
  lengths garble the display and make the corner flash; a longer 160-LED
  frame (`0x01E0`) doesn't, and LEDs past 143 light nothing.
- Split into 64-byte chunks, each written as a report with a leading `0x00`
  (report ID), with the last chunk zero-padded.
- Every LED has its own colour. `000000` = off.
- **The display blanks if frames stop.** Resend about every 0.5 s.

## LED map

| LEDs | Element |
|---|---|
| 0–9 | bottom-right corner stripes |
| 10 | `%` |
| 11–17, 18–24 | % digits: right, left |
| 25, 26 | leading `1` of 100% (segments b, c) |
| 27 | `MHz` |
| 28–34, 35–41, 42–48, 49–55 | MHz digits, right → left |
| 56–69 | two divider lines, left → right; each LED lights the same spot on both lines |
| 70 | `W` |
| 71–77, 78–84, 85–91 | top-right digits, right → left |
| 92, 93 | `°C`, `°F` |
| 94–99 + 101 | top-left right digit: segments c, d, e, g, b, a, then f = 101 (LED 100 sits inside it) |
| 100 | `GPU` |
| 102–108, 109–115 | top-left middle and left digits |
| 116 | `CPU` |
| 117–128 | stripes left of the logo (order not yet mapped) |
| 129–143 | stripes right of the logo (order not yet mapped) |

Within a digit, the LEDs are ordered **c, d, e, g, b, a, f**. These are the
standard segment names: a = top, b = upper-right, c = lower-right,
d = bottom, e = lower-left, f = upper-left, g = middle.

```
 aaa
f   b
 ggg
e   c
 ddd
```

## Layout

```
////// LOGO //////         (117–128 | 129–143)
GPU 888 °C°F        888 W
──────────────────────────  (56–69, left → right,
──────────────────────────   both lines together)
8888 MHz   188 %     //
                 //////     (0–9)
```
