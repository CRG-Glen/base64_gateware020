# Base64 020: 68020 gateware for jbilander's Base64

A **68020** for the Amiga 500, on jbilander's
[Base64](https://github.com/jbilander/Base64) accelerator. Tobias Gubener's
**TG68K.C** core (in m1nl's fork with a 32-bit data path) runs in 68020
mode on the board's iCESugar-Pro (Lattice ECP5), built entirely with the
**open-source** FPGA tools. It keeps everything the original gateware
offers: fast RAM, SD card boot, autoconfig and MapROM, and adds caches and
a clock you can change while the Amiga runs.

**The design, the build and the test benches are in [`tg68/`](tg68/README.md).**

> **If you use this build, read the
> [original project's README](https://github.com/jbilander/base64_gateware#readme)
> as well.** It covers the Base64 hardware, the iCESugar-Pro module and
> programming it.

| | |
| --- | --- |
| CPU | TG68K.C, 68020 mode, 32-bit longword reads and writes (caches and fast RAM) |
| Clock | **12x, 16x or 20x** the Amiga's 7.09 MHz (85, 113.5, 141.9 MHz), switched at run time with the `speed` command; power-on 12x. No board mod |
| Caches | 8 KB instruction (fast RAM, Kickstart and Chip RAM code) + 8 KB data (fast RAM and Kickstart), write-through; sequential instruction fetches predicted |
| Fast RAM | up to 8 MB Zorro II + 16 MB at `$08000000`, direct SDRAM path |
| Also | 8-entry Chip RAM write buffer, SD card boot (sfsd.device), MapROM (Kickstart in SDRAM), autoconfig |
| Not included | MMU, FPU |

Measured on an A500+ (Kickstart 3.x), v2.0, caches on / off:

| | 12x | 16x | 20x |
| --- | --- | --- | --- |
| SysInfo Dhrystones | 10776 / 4461 | 14379 / 5440 | **18024 / 7499** (18.81 MIPS) |
| AIBB MemTest | 16.60 / 8.48 MB/s | 21.03 / 10.59 MB/s | **26.16 / 13.20 MB/s** |
| xSysInfo Dhrystones | 18430 / 9743 | 24407 / 12117 | **29009 / 14486** |
| xSysInfo fast RAM | 23.69 / 21.17 MB/s | 29.58 / 26.21 MB/s | **36.85 / 32.73 MB/s** |
| SD card (xSysInfo) | 2.0 MB/s | 2.2 MB/s | 2.7 MB/s |
| Frontier timedemo (min / max / average fps) | 9.5 / 70.4 / 26.2 | 11.8 / 73.3 / 31.1 | 13.9 / 75.6 / 33.8 |

Games that keep their code in Chip RAM (Frontier, Gloom) run from the
instruction cache, and their screen writes go through the write buffer
while the CPU carries on. Kickstart runs from fast RAM via MapROM. Chip
RAM itself is the Amiga's own 7 MHz bus and does not get faster with the
clock, which is why Frontier gains less from 20x than the benchmarks do.

## Getting it running

1. Download the newest release from the
   [Releases](https://github.com/CRG-Glen/base64_gateware020/releases)
   page and unzip it. It has two bitstreams (the same design, packed two
   ways: `_fast` loads faster at power-on, `_plain` is the fallback if a
   board will not load `_fast`), the `speed` and `maprom` commands, and a
   `ReadMe.txt`.
2. **With the module out of the Amiga** (see the warning below), plug it
   into your PC by USB-C and copy the `.bit` file onto the iCELink drive it
   shows up as. Wait a few seconds while it writes the flash. If a
   bitstream that should work does nothing (LEDs lit, no boot), copy it
   again: an incomplete copy can look like that.
3. Fit the module and boot. It starts at 12x. ShowConfig should list the
   Base64 boards, and SysInfo reports a 68020.
4. Copy `speed` and `maprom` to `C:` (or anywhere in your path).

> ### Program the module OUT of the Amiga
>
> Nothing on the module protects its 5V rail from USB 5V. If you plug in
> USB while the module is fitted, the Amiga's 5V and your PC's 5V are tied
> together directly, and whichever is higher back-drives the other (usually
> your PC ends up powering the Amiga). Program the module before seating it
> in the socket.
>
> If USB must stay connected while the module is fitted, use a **data-only
> cable** with the 5V wire cut, keeping D+, D- and GND.

## The `speed` command

```
speed             show the clock in force and the 7 MHz capture status
speed 12          85.1 MHz, the board's own clock (power-on default)
speed 16          113.5 MHz
speed 20          141.9 MHz
speed 20 RISE     force the 7 MHz sample to the rising clock edge
speed 20 FALL     ... or to the falling edge (normally calibrated)
```

- The switch happens at once, while the Amiga runs: the board waits for the
  buses to go idle, changes the clock, recalibrates how it samples the
  Amiga's 7 MHz clock (about 9 ms) and carries on.
- The speed **stays over a reset**. Switching the Amiga off and on always
  returns to 12x, so a speed that is too fast for a board is undone by a
  power cycle.
- To start at 20x every time, add `speed 20` near the top of
  `S:Startup-Sequence` (or to `S:User-Startup`).
- `speed` with no argument also says which edge samples the 7 MHz clock and
  whether anything has moved since the last calibration. "The rising-edge
  sample has moved" at 16x or 20x is harmless: that sample is not the one
  in use at those speeds.
- 16x and 20x run the FPGA past its worst-case timing model (20x: about
  1.5x). They run on the developer's A500+, including hours at 20x, but
  every board is different: if one is unstable, use a lower speed.
- The ICS570B clock chip must be strapped for x12 (stock).

## The `maprom` command

The board's boot ROM copies Kickstart into SDRAM and runs it from there
(MapROM) at every boot, so ROM code runs at fast RAM speed and is cached.
`maprom` is for checking it and comparing:

```
maprom            copy Kickstart into SDRAM and switch over
maprom OFF        switch back to the motherboard ROM
maprom STATUS     report only
```

`maprom STATUS` normally reports "active". MapROM always clears on a reset,
and the boot ROM sets it again.

## Status

v2.0 runs on the developer's A500+ at 12x, 16x and 20x, including hours
of use at 20x. The design notes in [`tg68/README.md`](tg68/README.md)
describe every step of the speed-up work, and
[`tg68/docs/HISTORY.md`](tg68/docs/HISTORY.md) has the measurements. The
old step-by-step branches (each with its test bitstreams) are still on
GitHub.
[`tg68/CLAUDE.md`](tg68/CLAUDE.md) and [`tg68/plans/`](tg68/plans/README.md)
hold the working rules and plans.

## Credits and licences

- **Glen Milford**: this 68020 gateware project, its testing on real
  hardware, and the direction of the work.
- **Claude** (Anthropic's AI model, through Claude Code): design and
  implementation of the speed-up steps, the simulation benches and the
  timing method, working with Glen.
- **Tobias Gubener** (TobiFlex): the TG68K.C core (LGPL-3.0).
- **m1nl**: the TG68K.C fork with the 32-bit data path (LGPL-3.0), and the
  IcePi Zero Minimig that showed how fast this core can go.
- **jbilander**: the Base64 hardware (CC BY-SA 4.0) and the fx68k gateware
  this build is derived from.
- **Alastair M. Robinson**: the original Base64 gateware and its TG68 work.
- **Niklas Ekström**: the SD controller (GPL-2.0-only) and sfsd.device.

The parts keep their own licences. The base64_gateware sources carry no
licence file, so the terms for the parts derived from them are still to be
agreed with their author.

This repository started as a fork of
[jbilander/base64_gateware](https://github.com/jbilander/base64_gateware).
From v2.0 it holds only the 68020 build (`tg68/`): the original gateware
and jbilander's fx68k build are in that repository.
