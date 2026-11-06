# Base64 020: 68020 gateware for jbilander's Base64

A **68020** for the Amiga 500, on jbilander's
[Base64](https://github.com/jbilander/Base64) accelerator. Tobias Gubener's
**TG68K.C** core runs in 68020 mode on the board's iCESugar-Pro (Lattice
ECP5), built entirely with the **open-source** FPGA tools. It keeps
everything the fx68k gateware offers: fast RAM, SD card boot, autoconfig
and MapROM.

**The 68020 build is in [`tg68/`](tg68/README.md).** It covers the design,
how to build it, the timing method and the test benches.

| | |
| --- | --- |
| CPU | TG68K.C, 68020 mode, about 25 MHz 68030 class in AIBB |
| Caches | 8 KB instruction + 8 KB data, write-through, invisible to software |
| Fast RAM | up to 8 MB Zorro II + 16 MB at `$08000000`, direct SDRAM path |
| Also | SD card boot (sfsd.device), MapROM (Kickstart in SDRAM), autoconfig |
| Not included | MMU, FPU |

Measured on an A500+ (Kickstart 3.x):

| | Caches on | Caches off |
| --- | --- | --- |
| SysInfo Dhrystones | 6076 (6.34 MIPS) | 4007 |
| AIBB Dhrystone | 11712 | 7638 |
| AIBB MemTest | 7.28 MB/s | 5.71 MB/s |
| SD card (SysInfo) | 2.18 MB/s | |

## Getting it running

1. Download the bitstreams from the
   [Releases](https://github.com/CRG-Glen/base64_gateware020/releases) page.
   For normal use, take `bitstreams/step4_dcache/base64_tg68_full_plain.bit`.
   `min` is a cut-down build for diagnosing faults: it has no fast RAM and
   no SD card.
2. **With the module out of the Amiga** (see the 5V warning below), copy
   the `.bit` file onto the iCELink USB drive the module shows up as.
3. Fit the module and boot. ShowConfig should list the Base64 boards, and
   SysInfo reports a 68020.

The release also has `maprom`, a Shell command for checking and switching
MapROM (the board's boot ROM already turns it on at every boot).

## Status

Steps 1-4 of the speed-up work run on real hardware. See the
[bitstream table](tg68/README.md#the-bitstreams) for what each step added.
Earlier steps stay in the releases as fallbacks. Work happens on branches,
one reviewed change at a time. [`tg68/CLAUDE.md`](tg68/CLAUDE.md) holds the
working notes and the rules every change has to pass (simulation and
timing check).

## Credits and licences

- **Tobias Gubener** (TobiFlex): the TG68K.C core (LGPL-3.0).
- **jbilander**: the Base64 hardware (CC BY-SA 4.0) and the fx68k gateware
  this build is derived from.
- **Alastair M. Robinson**: the original Base64 gateware and its TG68 work.
- **Niklas Ekström**: the SD controller (GPL-2.0-only) and sfsd.device.

The parts keep their own licences. The base64_gateware sources carry no
licence file, so the terms for the parts derived from them are still to be
agreed with their author.

This repository is a fork of
[jbilander/base64_gateware](https://github.com/jbilander/base64_gateware).
Everything outside `tg68/` is upstream's, unchanged. Its README follows.

---

# Gateware for jbilander's Base64 MC68000 accelerator project
by Alastair M. Robinson
making use of the TG68k CPU core by Tobias Gubener

> **This fork also contains a second, independent gateware implementation
> built around the fx68k cycle-accurate 68000 core, in
> [`fx68k/`](fx68k/README.md).** It targets the same hardware and is a
> separate design rather than a modification of the one described below,
> which is unchanged and still builds as documented here.
>
> The fx68k build boots AmigaOS from SD card on Kickstart 1.3 and above with
> fast RAM in both Zorro II and 32-bit CPU space. See
> [fx68k/README.md](fx68k/README.md) for its architecture, autoconfig
> layout, build notes and current status.

## Hardware

The Base64 is a carrier board that fits the MC68000 socket and hosts an
[iCESugar-Pro](https://github.com/wuxx/icesugar-pro) FPGA module by Muse Lab.
The module is open hardware, with the schematic published as a PDF in that
repository, and carries:

* a Lattice **LFE5U-25F-6BG256C** ECP5 in DDR2 SODIMM form factor, 106 usable IOs
* **32MB SDRAM** (IS42S16160B)
* 32MB SPI flash (W25Q256JV)
* a 25MHz crystal, a micro-SD slot and an RGB LED

Modules can be bought from Muse Lab's store on AliExpress, Tindie or Amazon.

Carrier board design, schematics and gerbers:
[github.com/jbilander/Base64](https://github.com/jbilander/Base64)

## Programming the module

Bitstreams go on over the module's USB-C connector. The on-board iCELink
debugger appears as a virtual disk — drop the `.bit` file onto it and wait a
few seconds while it writes the SPI flash. No adapter, no drivers, no extra
tools.

> ### Do this with the module OUT of the Amiga
>
> Program it before seating it in the SO-DIMM socket.
>
> There is **no protection on the module between its 5V rail and USB 5V**, so
> plugging in USB while it is installed ties the Amiga's 5V to the host's with
> nothing in between, and whichever is higher back-drives the other. In
> practice USB is closer to a true 5.0V while the Amiga usually sits nearer
> 4.9V, so what happens is your PC powering the Amiga's 5V rail rather than
> the reverse — which is not what you want either. Two unprotected supplies
> tied together is not a state to leave a machine in, whichever way the
> current flows.
>
> If USB has to stay attached while the module is installed, use a **data-only
> cable** with the 5V conductor cut, leaving D+, D- and GND.

Building from source is covered below for this implementation, and in
[fx68k/BUILD.md](fx68k/BUILD.md) for the fx68k one. The external-JTAG route —
needed only for Reveal Analyzer, and requiring the iCELink to be disabled by a
hardware modification — is described there too.

## General structure:
The prj directory contains subprojects which can be built using their respective Makefiles.

### Clock recovery:
The Rev B board provides a clock-doubled version of the incoming 7MHz Amiga clock,
in order to supply a synchronous clock fast enough for the ECP5's PLLs.
The Rev C board supplies a x12 version of the clock, around 85MHz, synchronous 
with the 7MHz clock. This project doesn't currently use the faster clocks.

Instead, a high-frequency internal clock is generated from the IceSugar-Pro's
own 25MHz clock, then _pos and _neg strobe signals are generated to mark the 
rising and falling edges of the 7MHz clock.

### MC68000 bus state machine
Has responsibility for the 24-bit address space
Handles communication with the motherboard
Can intercept Autoconfig accesses in order to configure 32-bit Fast RAM and potentially
other devices such as SD card.
  
### CPU Wrapper
A shim around TG68K which does basic address decoding, directing addresses in 24-bit space
to the bus state machine, and addresses in 32-bit space to the SDRAM controller / cache.
Potentially reserve some RAM space for a kickstart ROM, in which case some of the 24-bit address
will have to be decoded too.
  
### SDRAM controller and cache
SDRAM controller will run in burst mode - either 4 words or 8 words

## Building

There are a few paths that need to be set so that the project can find the
required tools - this is done by copying the "site.template" file to "site.mk"
then editing site.mk to set the paths.

The following tools are required to build this project:

### Lattice Diamond
To build bitstreams for the FPGA you'll need Lattice Diamond. Version 3.11 is
recommended (newer versions may work, but have been known to cause problems
with the Minimig core on ECP5-based boards, so 3.11 is the safest option.)

Lattice Diamond is provided as a .rpm file, which is a bit awkward to install
on .deb-based distributions such as Ubuntu or Mint (or Debian, of course!) -
some information on the subject can be found at
https://retroramblings.net/?p=1917

### openFPGALoader
You can use whichever tool you like to load bitstreams onto the FPGA, but the
makefiles expect to use openFPGALoader.

### Verilator
Makefiles with a "sim" target will expect to use Verilator for simulation. It
will need to be at least version 5.
In order to build with verilator, it's necessary to set the path to
Verilator's  includes in the site.mk file.  (If Verilator is installed 
systemwide this will probably be /usr/share/verilator/include - or if you're
using oss-cad-suite,  it will likely be
/path/to/oss-cad-suite/share/verilator/include

### OpenOCD
Some projects are able to capture data from the running design over JTAG.
This is done using OpenOCD.

The easiest way to obtain openFPGALoader, Verilator and OpenOCD (if your
distro of choice doesn't supply new enough versions) is to install
oss-cad-suite from https://github.com/YosysHQ/oss-cad-suite-build

### Open-source tooling
While yosys and nextpnr have mature and dependable support for the Lattice
ECP5 FPGAs, the last time I checked they struggled to build the TG68K CPU,
which is why this project uses Diamond.

