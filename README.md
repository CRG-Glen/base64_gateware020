# Base64 020: 68020 gateware for jbilander's Base64

A **68020** for the Amiga 500, on jbilander's
[Base64](https://github.com/jbilander/Base64) accelerator. Tobias Gubener's
**TG68K.C** core (in m1nl's fork with a 32-bit data path) runs in 68020
mode on the board's iCESugar-Pro (Lattice ECP5), built entirely with the
**open-source** FPGA tools. It keeps
everything the fx68k gateware offers: fast RAM, SD card boot, autoconfig
and MapROM.

**The 68020 build is in [`tg68/`](tg68/README.md).** It covers the design,
how to build it, the timing method and the test benches.

> **If you use this build, read the
> [original project's README](https://github.com/jbilander/base64_gateware#readme)
> as well.** It covers the Base64 hardware, the iCESugar-Pro module,
> programming it, and the other two gateware designs this one builds on.

| | |
| --- | --- |
| CPU | TG68K.C, 68020 mode, 32-bit longword reads from the cache and writes to fast RAM |
| Caches | 8 KB instruction + 8 KB data, write-through, invisible to software |
| Fast RAM | up to 8 MB Zorro II + 16 MB at `$08000000`, direct SDRAM path |
| Also | SD card boot (sfsd.device), MapROM (Kickstart in SDRAM), autoconfig |
| Not included | MMU, FPU |

Measured on an A500+ (Kickstart 3.x), step 8:

| | Caches on | Caches off |
| --- | --- | --- |
| SysInfo Dhrystones | 9226 (9.63 MIPS) | 3982 |
| AIBB MemTest | 10.93 MB/s | 6.15 MB/s |
| SD card (SysInfo) | 2.18 MB/s | |

xSysInfo, caches on: 15711 Dhrystones (8.94 MIPS), fast RAM 16.38 MB/s,
Chip RAM 2.39 MB/s, ROM 16.38 MB/s (Kickstart runs from fast RAM via
MapROM), SD card 1.9 MB/s.


## Getting it running

1. Download the bitstreams from the
   [Releases](https://github.com/CRG-Glen/base64_gateware020/releases) page.
   Take the newest release's `base64_tg68_full_plain.bit` (step 8:
   `bitstreams/step8_sdram32w/`). From step 6 on only this `full` build
   is released; the older releases also have `min`, a cut-down build with
   no fast RAM and no SD card, for diagnosing faults.
2. **With the module out of the Amiga** (see the warning below), plug it
   into your PC by USB-C and copy the `.bit` file onto the iCELink drive it
   shows up as. Wait a few seconds while it writes the flash.
3. Fit the module and boot. ShowConfig should list the Base64 boards, and
   SysInfo reports a 68020.

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

The release also has `maprom`, a Shell command for checking and switching
MapROM (the board's boot ROM already turns it on at every boot).

## Status

Steps 1-7 of the speed-up work run on real hardware. See the
[bitstream table](tg68/README.md#the-bitstreams) for what each step added.
Earlier steps stay in the releases as fallbacks. Work happens on branches,
one reviewed change at a time. [`tg68/CLAUDE.md`](tg68/CLAUDE.md) holds the
working notes and the rules every change has to pass (simulation and
timing check).

## Credits and licences

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

This repository is a fork of
[jbilander/base64_gateware](https://github.com/jbilander/base64_gateware).
Everything outside `tg68/` apart from this README is upstream's,
unchanged: Alastair M. Robinson's
original gateware at the top level and jbilander's fx68k build in
[`fx68k/`](fx68k/README.md).
