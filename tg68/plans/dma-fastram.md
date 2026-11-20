# DMA access to fast RAM: another bus master reads and writes our RAM

Status: **plan, waiting for the owner's answers** (section "Questions for
Glen"). Branch `v2-clock-dma-compact`, second of its three items. Written
20 November 2026 from the Base64 hardware repository
(jbilander/Base64 at 834be7f: `KiCad/Base64.kicad_pcb`, `Base64.lib`,
`Base64_revC_schematic.pdf`) and v2.0's RTL. Nothing is built.

## Goal

A DMA bus master on the Amiga's bus (an A590 or another DMA hard disk
controller on the A500+'s side expansion; on a B2000 a DMA card such as
the A2091) can read and write the accelerator's **Zorro II fast RAM**
($200000-$9FFFFF, the slots `fm_cfg_match` says we own), with correct
data, and the CPU never sees stale cached data afterwards.

Not goals: DMA into the 16 MB at $08000000 (a 24-bit master cannot
address it; AmigaOS already keeps 24-bit DMA buffers below 16 MB), DMA
into MapROM or the SD/turbomem ROMs, speed (a DMA transfer is bound by
the 7 MHz bus and the controller, not by us), the CPU running during DMA
(it does not today; see Background 3).

## Background

### 1. What the board can see (from the PCB netlist)

Every 68000 socket signal passes through an SN74CBTD3861 (a passive,
bidirectional 10-bit FET switch; the D type clamps the 5 V side to a
level the 3.3 V FPGA takes). Seven of them:

| part | ~OE | channels (Amiga side) |
| --- | --- | --- |
| U8 | FPGA `cbt_oe_a1_7_n` | A1-A7 |
| U7 | FPGA `cbt_oe_a8_17_n` | A8-A17 |
| U4 | FPGA `cbt_oe_ctl_hi_n` | RW, LDS, UDS, AS, A18-A23 |
| U2 | FPGA `cbt_oe_d0_7_n` | D0-D7 |
| U3 | FPGA `cbt_oe_d8_15_n` | D8-D15 |
| U5 | **GND (always on)** | BGACK, BG, BR, DTACK, VMA, E, VPA, HALT, RESET |
| U6 | **GND (always on)** | BERR, IPL0-2, FC0-2, CFGIN, CFGOUT |

There is nothing else between the socket and the FPGA. So:
- the FPGA **always** sees BR/BG/BGACK and can drive DTACK;
- address, strobes and data reach the FPGA only while their switches are
  closed, and v2.0 opens all five whenever it does not own the bus
  (`bus_enable` in `base64_tg68_top.sv` section 10, from `bus_owned`,
  section 9b). That is the only reason the FPGA is blind during DMA: a
  gateware choice, not the wiring;
- with the switches closed and the FPGA's pins high-impedance, the FPGA
  only listens: electrically the same as every read it does today.

### 2. The pins in the RTL

- `cpu_a[23:1]`, `cpu_as_n`, `cpu_uds_n`, `cpu_lds_n`, `cpu_rw` are
  `output` with `1'bz` when not owned (top level, about line 1439): they
  cannot be read. They must become `inout`, read through ECP5 `BB`
  buffers under `ifdef YOSYS` like the other inouts (gotcha: yosys turns a
  constant `1'bz` on an inout into a 0 driver; `build.py` refuses a
  netlist with tied inout bits, and `tied_ok` must not grow).
- `cpu_d` is already `inout`, driven only when `bus_owned` and `*_d_oe`.
- `cpu_dtack_n` is `input` (2FF `s_dtack_n`): it must become `inout`,
  driven low only for our DMA cycles, high-impedance otherwise
  (motherboard pull-up).

### 3. What the CPU does while another master has the bus

`bus_free` (`tg68_bus.v`, about line 792) is false while BG or BGACK is
low, so the adapter starts no new cycle at DECIDE, cache hits included:
the CPU is stopped for the whole DMA. BG is only granted between cycles
(`!in_cycle`), and the top level hides BR while the Chip RAM write buffer
drains (`tg_br_n`). A posted fast RAM write (`dp_busy`) may still be
finishing in the SDRAM when the master starts. Refresh goes on.

### 4. The fast RAM side

`fastmem_zii.v` is built with `BUS_RAM = 0`: its old 68000-bus slave
(from the fx68k build) is compiled out, and the CPU reaches the SDRAM
only through the direct port (`dp_*`). The Zorro II window is
`fm_cfg_match` (8 bits, one per 1 MB slot $200000-$9FFFFF, static after
autoconfig). The SDRAM controller has one requester (fastmem_zii's
`req`/`saddr`/`wdata`/`byte_en`/`wr_valid`).

### 5. Coherency today

The caches hold fast RAM (`k_z2`) in both the data and the instruction
cache. Nothing outside the CPU writes fast RAM today, so nothing
invalidates on it. AmigaOS 2.0+ drivers call `CachePostDMA`, which on
this core reaches CACR CI/CEI and flushes, but an old driver (the A590's
1.3 `scsi.device`) does not: the hardware must not rely on it.

## The change, in order

### 1. Pins (top level, constraints unchanged)

`cpu_a`, `cpu_as_n`, `cpu_uds_n`, `cpu_lds_n`, `cpu_rw`, `cpu_dtack_n`
become `inout`, each read through a `BB` under `ifdef YOSYS`
(`T` = not driving). New 2FF synchronizers `s_as_n`, `s_uds_n`,
`s_lds_n`, `s_rw` (like `s_dtack_n`); the address is sampled when the
synchronized AS has been low for one clock (the 68000 address is stable
a full 7 MHz half-cycle before AS falls, so no synchronizer on it, the
same argument the bridge uses for its own reads). Check with `build.py`
that no inout bit is tied and `tied_ok` is unchanged.

### 2. Listening (section 9b / 10)

`dma_listen = arb_settled & ~passive & ~bus_owned & fm_cfg_on`: another
master holds the bus, we are not in passive mode (an accelerator that
took the bus for good is not a DMA master), and our RAM is configured.
While `dma_listen`, close U8, U7 and U4 (address, strobes) and U2/U3
(data), drive nothing. `bus_enable` itself is unchanged; the CBT enables
become `~(bus_enable | dma_listen)` plus the existing `fm_active` /
`tm_active` / `sd_space` terms for the data switches, which only apply
while we own the bus.

### 3. The DMA slave (new, top level or a small module `dma_slave.v`)

A 68000-bus slave for the Zorro II window, on the synchronized strobes:
- **decode**: AS low, `a[23:20]` in 2..9, `fm_cfg_match[a[23:20]-2]`;
- **write**: wait for UDS/LDS (data valid), request one SDRAM word write
  (byte enables from UDS/LDS), assert DTACK when the controller has
  taken it;
- **read**: request one SDRAM word read, put the word on `cpu_d`, assert
  DTACK, hold data and DTACK until AS rises (then release DTACK to
  high-impedance first, data a clock later);
- one cycle at a time; no posting, no prefetch (the master is at 7 MHz).

The SDRAM request goes into `fastmem_zii` as a second requester beside
`dp_*`, arbitrated there: the direct port can only have a request in
flight when the master starts (a posted write finishing), never a new
one (Background 3), so the DMA request simply waits for `dp_busy` to
clear. Address mapping as the CPU's Zorro II accesses (the same `saddr`
build).

### 4. Coherency

Stage 1: a register `dma_wrote` is set by any DMA write we answer;
when BGACK rises again (the master gives the bus back) and `dma_wrote`
is set, raise the existing flush trigger (`flush_trig`, as for CACR CI:
both caches swept, `ic_fcnt`), and clear `dma_wrote`. The CPU starts
again with the caches off until the sweep is done (existing behaviour).
Cost: one sweep (2048 clocks per bank) per DMA burst that wrote, small
next to a disk transfer.

Stage 2 (later, a separate step, only if `perf` shows the flushes cost):
drop only the written entries, the step 17 way (the tag check at the
written index), while the CPU is stopped.

### 5. Simulation (`tb_top.sv`, new test in `test_top.s` or a bench)

A bus-master model on the motherboard pins: asserts BR, waits for BG,
asserts BGACK, runs 68000 cycles (S0-S7 at 7 MHz, waiting for DTACK) to
the configured Zorro II window: word and byte writes, reads back,
compares; reads a pattern the CPU wrote; a cycle outside our window
(must get no DTACK from us); releases BGACK. The CPU program then reads
the DMA-written words (they must be the new values although they were
cached before the DMA: the flush) and executes code a DMA write
changed. Checks: data, DTACK never from us outside the window or while
we own the bus, `cpu_d` never driven by us while the master writes, no
contention (our `cpu_*` drivers enabled while `dma_listen` = FAIL).

Mutants: decode ignores `fm_cfg_match` (a DMA cycle to an unowned slot
gets DTACK: caught); no flush (stale cached read after DMA: caught);
DTACK released before data (sim checks data valid while DTACK low:
caught); listening also in passive mode (a test with `passive` forced:
caught).

### 6. Timing classes (`check_timing.py`)

The new registers are ordinary 1T logic fed by 2FF synchronizers; the
DMA slave's SDRAM request joins the existing controller paths. New pins:
`cpu_dtack_n` output register, `cpu_d` output enable for DMA reads. No
new multicycle class.

### 7. Hardware stages (each a test bitstream)

0. **Before any RTL** (owner, with v2.0): with the DMA controller, a
   transfer whose buffer is forced into fast RAM (driver's DMA mask, or
   `Mask`/`MaxTransfer` in the mountlist): note what happens today
   (hang, garbage, or Gary answering). This is what tells whether Gary
   also drives DTACK for $200000-$9FFFFF (Questions, 3).
1. Listening only: switches closed during DMA, nothing answered, an
   on-board count of DMA cycles in our window shown by `speed`/status:
   proves the FPGA sees the master's cycles. No change for the user.
2. Full: reads and writes answered, flush on release. Test: copy large
   files disk <-> fast RAM buffers, compare checksums, repeated; the
   same at 12x, 16x, 20x; SysInfo/AIBB unchanged.

## Numbers that must not move

All benches' clocks (no DMA in them): c, coff, copy, read, scatter,
chip, wrfast, wrmix, op as on the base branch. `bus`, `top`, `fastmem`,
`bench sd` PASS. LUT4 growth under about 400; no new block RAM. 12x
timing PASS on some seed (`check_timing.py`).

## Acceptance

Sims and the new DMA test pass with every mutant caught; a 12x seed
passes; hardware stage 2 passes the copy-and-compare test at all three
speeds with a real DMA controller, and nothing changes without one.

## Fallbacks and stop conditions

- **Stop and report** if stage 0 shows Gary (or another motherboard
  part) drives DTACK for the Zorro II range during DMA: our DTACK would
  then race it, and a read would latch data before we drive it. Options
  then are the owner's (a board change, or no DMA to fast RAM).
- Stop if closing the switches while not owning the bus disturbs
  anything (stage 1 shows any change on a machine without a DMA device:
  it must not).
- If the BB conversion of the address/strobe pins costs timing that a
  seed budget does not fix: read them on a separate set of registers
  outside the bridge's paths; stop if that fails too.
- If `fastmem_zii`'s requester mux is the problem, the DMA request may
  use the controller's port only while the CPU is stopped (it always is
  during DMA), through a plain 2:1 mux on `bus_owned`.

## Questions for Glen

1. Which DMA device can you test with on the A500+ (A590, GVP Series II,
   other), and with which Kickstart and driver?
2. Is this for the A500+ only, or also a B2000 (where Buster and /BOSS
   change the arbitration; section 9b already handles a takeover)?
3. Stage 0 above: what does a DMA transfer into fast RAM do on v2.0
   today?

## Log

(the builder writes here)
