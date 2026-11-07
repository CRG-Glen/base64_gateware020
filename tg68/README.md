# Base64 TG68 — 68020 gateware for the Base64 / iCESugar-Pro

TobiFlex's **TG68K.C** core in **68020 mode**, on JBilander's Base64 carrier,
built with the **open-source** FPGA tools. No Lattice Diamond needed.

This is the fx68k build's `base64_top.sv` with the CPU swapped. Everything
around the CPU comes along: the 7 MHz bus bridge, the cold-boot reset
handling, Zorro II and 32-bit fast RAM, the turbomem DiagArea board, MapROM
and the SD card. An adapter, `tg68_bus.v`, makes TG68K look like fx68k's
ports and adds the caches and the direct SDRAM path. Changes to the fx68k
build's own files are few and marked `TG68:`.

> **Status:** steps 1-6 run on an A500+ (step 6 `full`: 8144 Dhrystones,
> 8.50 MIPS, AIBB MemTest 7.65 MB/s with the caches on, SD card 2.18 MB/s).
>
> **SD card: only the step 4 `full` bitstream reads the card.** Every
> earlier yosys build drove the card's data-out line (MISO) low, so the
> driver loaded but could never talk to the card (HDToolBox: "Drive does
> not support the SCSI inquiry command"). The step 1-3 `full` files still
> have that bug.

The bitstreams are not kept in git: download them from this repository's
**Releases** page (each release has the `bitstreams/` folders below and the
`maprom` command), or build them yourself.

## The bitstreams

| Folder | What changed | Status |
| --- | --- | --- |
| `bitstreams/step6_earlylookup/` | + early cache lookup: every cache hit in 5 clocks, not 7 (replaces the pair buffers) | **Latest. Known good on hardware**, SD card included: 8144 Dhrystones (+21% on step 5), MemTest 7.65 MB/s. `full` only |
| `bitstreams/step5_pairbuf/` | + pair buffers: the other half of a cached pair in 5 clocks, not 7 | **Known good. `full` on hardware**, SD card included: 6720 Dhrystones, MemTest 7.46 MB/s. `min` not run on hardware |
| `bitstreams/step4_dcache/` | + 8 KB data cache, cache hits overlap SDRAM writes; SD card pin fix | **Known good on hardware**, SD card included |
| `bitstreams/step3_direct/` | + direct CPU → SDRAM path for fast RAM, posted writes, word prefetch | **Known good on hardware**: MemTest 6.46 MB/s |
| `bitstreams/step2_icache/` | + 8 KB instruction cache | **Known good on hardware**: 4833 Dhrystones, 5.04 MIPS |
| `bitstreams/step1_no_cache/` | 2 clocks less per bus access (4/3/1/1 pacing) | Simulated and timing-checked |
| `bitstreams_prev/v3_*` | 4/3/2/2 pacing: 2783 Dhrystones on an A500+ | **Known good on hardware** |
| `bitstreams_prev/base64_tg68_fastmem_*` | Fast RAM, no SD, 5/4/3 pacing | Known good, for bring-up |

Each folder has `min` (68020 + motherboard only) and `full` (+ fast RAM:
Zorro II and 16 MB at `$08000000`, + SD card boot). `_plain` files are
packed like Muse Lab's own examples and take ~2 s to load at power-on.
`_fast` files are the same designs, compressed, with single-SPI reads at
38.8 MHz; both work on hardware. (The very first files used the Diamond
build's dual-SPI 62 MHz settings, and the FPGA won't load those on this
module. That was the original no-LED fault.)

The pin-out is the fx68k build's (`fx68k/constraints/base64.lpf`), i.e. the
**Rev C** carrier with the ICS570B ×12 clock. The original TG68 project in
the repo targets Rev B; this one does not.

## Programming

As for the fx68k build: **module out of the Amiga** (the module has no
protection between USB 5 V and the Amiga's 5 V), plug in USB-C, drop the
`.bit` onto the iCELink drive, wait a few seconds.

## Bring-up

### 1. `base64_tg68_min.bit`

Fit the module and power on with a Workbench floppy in DF0:.
The cold boot takes ~1.3 s longer than usual (see *Cold boot* below).

| LED | Meaning |
| --- | --- |
| **Blue** | CPU is out of reset |
| **Green** | Slow blink (~1.5 s) = E clock running. Proves the 7 MHz clock reaches the FPGA |
| **Red** | A bus cycle has waited ~100 ms with no DTACK, **or** the 7 MHz phase aligner slipped |

* **Blue never lights.** The CPU is held in reset. Same diagnosis as the fx68k
  build (something holding /RESET or /HALT).
* **Blue on, red on.** The CPU is stuck in a bus cycle nobody answers. That
  points at the bridge or the address it put out, not at the core.
* **Blue on, red off, black or grey screen.** The CPU runs but the machine
  doesn't boot. Try Ctrl-A-A once. If a warm reset works and a cold boot
  doesn't, that's the cold-boot behaviour below, not the core.

Once it boots, run **SysInfo** or `ShowConfig` and it should report a
**68020**. No fast RAM is expected in this build.

### 2. `base64_tg68_fastmem.bit`

`ShowConfig` should list the 5194/13 fast RAM board and the 5194/14 ROM
board. `AvailMem` should show the Zorro II fast RAM plus the 16 MB at
`$08000000`.

### 3. `base64_tg68_full.bit`

Boots from SD exactly like the fx68k build. Same `Mask` advice applies
(`0x001FFFFE`), and so does the DMA limitation.

## What's different from a real 68020

* **No FPU, no MMU, no coprocessor interface.** F-line opcodes trap to vector
  11. **CALLM/RETM** are missing, as they are on the 68030 and later. Nothing
  on the Amiga uses them.
* **Instruction cache (step 2).** 8 KB, direct-mapped, in block RAM. It
  caches instruction fetches from on-board fast RAM and the Kickstart ROM
  ($F80000–$FFFFFF), never Chip RAM, which DMA writes. Every CPU write to
  a cacheable address invalidates its entry, so self-modifying code and
  program loading work without CacheClearU. CACR's EI bit turns it on and
  off as on a real 68020: off at reset, and Kickstart 2.0+ turns it on;
  FI freezes it. The clear bits (CI/CEI) are ignored because they aren't
  needed. The cache is flushed after every reset. `ICACHE=0` in
  `tg68_bus.v` removes it.
* **Speed.** The adapter steps the core at most once every 4 clocks
  (~21 MHz), samples its outputs 3 clocks after a step, hands it read data
  1+1 clocks before its next step, and puts the address out 1+1 clocks
  before AS (`TG_STEP`, `TG_SETTLE`, `TG_DIN`, `TG_ASU`; the +1s are
  explained in `tg68_bus.v`; see *Timing*). Strobes reach the bus one
  clock after the sequencer decides, so that register can sit next to the
  fast RAM logic (see `tg68_bus.v`). Measured in SysInfo on an A500+:
  8/6/6 pacing 1877 Dhrystones (1.95 MIPS); 5/4/3 pacing 2313 (2.41 MIPS);
  4/3/2/2 pacing 2783 (2.9 MIPS); 4/3/1/1 + cache 4833 (5.04 MIPS), 3208
  with the cache off.
* **Data cache (step 4).** 8 KB, direct-mapped, the same size and layout
  as the instruction cache, for data reads from on-board fast RAM and the
  Kickstart ROM (never Chip RAM). It is write-through: every write still
  goes to memory, a whole-word write to fast RAM also updates the cache,
  and a byte write drops the entry. Nothing but the CPU writes on-board
  fast RAM (the SD card doesn't write memory itself, and nothing on the
  motherboard can reach this RAM), so the cache never goes stale and
  software needs no cache flushing. Both caches are flushed after a reset
  and when MapROM is switched on or off.
  **It is switched with the instruction cache**, by CACR's EI bit, so it is
  on whenever the ICache is on and SysInfo's/`CPU`'s *DCache* switch does
  nothing, as on a real 68020. A real 68020 has no data cache and no CACR
  bit for one; software tells a 68020 from a 68030 by setting the 68030's
  data-cache bit and reading it back, so giving this CPU that bit would
  make it look like a 68030 (and invite MMU code it can't run). To compare
  with and without it, run step 3 against step 4. `DCACHE=0` in
  `tg68_bus.v` removes it.
  Two changes came with it. A fast RAM data read is sent to the SDRAM at
  the same moment as the cache lookup, and the result dropped on a hit,
  so a miss costs no more than before. And a cache hit (instruction or
  data) no longer waits for a posted write or prefetch to finish. In
  simulation: sequential reads 7.29 → 8.03 MB/s, scattered reads
  8.50 → 11.66 MB/s, the 1 KB copy unchanged at 4.85 MB/s.
* **Pair buffers (step 5; replaced by the early lookup in step 6).** A longword is two 16-bit bus cycles and code
  runs word by word, so a cache hit on one word of an aligned pair is nearly
  always followed by a hit on the other. A lookup costs 7 clocks per step; a
  word already sitting in a register costs 5. The cycle that looks the first
  word up also reads its neighbour from the same cache RAMs (no extra
  clock) and, if that is a valid cached word, keeps it in a small buffer,
  one for instruction fetches and one for data reads. If the next cycle asks
  for exactly that word it is answered from the buffer, the way the
  prefetch buffer already answers. Cache size and layout are unchanged. A
  buffered word is dropped by any write to its address (byte writes and
  writes with the caches off included), by a reset, and by the cache flush
  when MapROM switches, and it is only used while its cache is enabled, so
  it can never return what a normal lookup would not. `PAIRBUF=0` in
  `tg68_bus.v` removes it. In simulation, second pass from the caches:
  sequential reads 8.03 → 8.87 MB/s (+10%), scattered reads 11.66 → 13.28
  MB/s (+14%), the 1 KB copy 4.85 → 5.00 MB/s (+3%; it is write-bound).
  On an A500+ (`full`), with the caches on: 6076 → 6720 Dhrystones
  (+11%), AIBB MemTest 7.28 → 7.46 MB/s. With the caches off the run gave
  3717 Dhrystones against step 4's 4007, although the caches-off path is
  unchanged (the same code takes the same number of clocks on step 4 and
  step 5 in simulation) and MemTest with the caches off is identical
  (5.71 MB/s); not yet explained, most likely a difference in test
  conditions. The testbench checks every buffer hit
  against a shadow copy of what the CPU wrote, so a stale buffer shows up in
  any test, not only the ones aimed at it.
* **Early cache lookup (step 6).** After each CPU step the adapter waits
  for the kernel's outputs to settle before acting on them: 3 clocks,
  because the bus state and function codes need nearly that long. The
  address alone is final much sooner (about 21 ns routed, and the cache
  index bits by about 15 ns), so the cache RAMs now read it a clock earlier,
  on the edge into the clock where the adapter decides what the cycle is.
  That clock already loads the looked-up word into a register of its own
  that feeds the CPU's data input, and the tag into the compare register,
  and the next clock compares and, on a hit, steps the CPU. A cache hit costs 5 clocks instead of 7, and a
  miss reaches the bus or the SDRAM a clock sooner. The step 5 pair buffers,
  which only made the second word of a pair cost 5 clocks, gained nothing
  after that and were removed. `check_timing.py` gives the kernel-to-cache-RAM
  paths their own class with one clock less than the other kernel outputs
  (table below). In simulation, second pass from the caches: sequential
  reads 8.87 → 10.64 MB/s (+20%), scattered reads 13.28 → 15.66 MB/s (+18%),
  the 1 KB copy 5.00 → 5.35 MB/s (+7%). On an A500+ (`full`), caches on:
  6720 → 8144 Dhrystones (+21%), 7.01 → 8.50 MIPS, AIBB MemTest 7.46 →
  7.65 MB/s. Caches off: 3813 Dhrystones (step 5's run gave 3717, though
  nothing step 6 changed is used with the caches off, so SysInfo varies by a
  few percent between runs), MemTest 5.71 MB/s as before. Every
  cache hit in every test is checked against a shadow copy of what the CPU
  wrote; the bus bench (random DTACK, bus hand-over) now checks them too.
* **32-bit data path (step 7).** The CPU core is now m1nl's fork of
  TG68K.C, which can move an aligned pair of words in one step instead of
  two. Of its three kinds of pair (longword data, 32-bit immediates,
  absolute-long addresses) only longword data reads are switched on; the
  other two cost more timing in the kernel than it has
  when the memory side agrees. Each cache is split into an even-word and an
  odd-word bank (same total size), so one lookup reads both words of a pair.
  When the core offers a pair and both words hit, the adapter answers
  `long_ack` and hands over both words: the pair costs 5 clocks instead of
  10. If only the asked word hits, it is taken as an ordinary access a clock
  later; a miss goes to memory as before (pairs come only from the caches
  so far; longword writes are still two 16-bit writes). In simulation,
  second pass from the caches: sequential reads 10.64 → 12.59 MB/s (+18%),
  scattered longword reads 15.66 → 20.41 MB/s (+30%), the 1 KB copy
  unchanged at 5.35 MB/s (its source and destination share cache slots, so
  its reads miss). **Not yet run on hardware.** The cache-hit check now
  covers both words of every pair and that `long_ack` is set exactly for
  pair hits, and asserts that `long_ack` never changes in the clock before
  the CPU samples it.
* **MapROM.** The board's boot ROM (`turbomem.mem`, built with
  `DIAG_MAPROM=1`) copies Kickstart into the SDRAM shadow at every boot,
  verifies it and switches over, so it is normally already on. Both caches
  are flushed whenever it is switched. `sw/maprom/` has a command to check
  and control it: `maprom STATUS`, `maprom OFF`, and `maprom` to copy and
  switch on again. The ready-built command is attached to each release;
  copy it to C:.
  It is a 68000-assembly port of the original project's untested
  `maprom.c`, with the same procedure and checks, and builds with GNU
  binutils alone (`sw/maprom/build.sh`). Tested under the vamos emulator
  with a simulated board; not yet on hardware.
* **SD card pins.** The SD controller only reads DAT0 (MISO); DAT1/DAT2
  are unused in SPI mode. The fx68k source releases those pins with a
  constant `1'bz`, which Diamond honours but yosys turns into a constant 0
  driver. So in yosys builds the FPGA held MISO low against the card. They
  are now explicit ECP5 `BB` buffers with the output permanently off (yosys
  only; Diamond keeps the original code), and `build.py` stops with an
  error if any bidirectional pin comes out of synthesis tied to a constant.
  The SDRAM data pins get the same treatment when the build has no fast
  RAM (`min`), where they were driven low before. The only constant bits
  `build.py` accepts are the SD card's MOSI and chip select in a build
  without the SD block.
* **16-bit data bus.** TG68's bus port is 16 bits, so every longword is two
  transfers, as on the 68000.
* **Direct SDRAM path (step 3).** On-board fast RAM (the Zorro II window
  and $08000000) is no longer reached through the 68000-style
  AS/DS/DTACK slave. The adapter decodes it itself, from the fast RAM
  block's own slot assignment, and asks the SDRAM controller directly.
  Writes are posted: the CPU steps on while the SDRAM finishes them.
  After each data read the next word is prefetched into a one-word
  buffer, so the second half of a longword, or the next word of a
  sequential read, needs no SDRAM wait. The buffer is dropped on any
  write to its word, and on reset. Autoconfig and address mapping are
  unchanged. MapROM goes the same way: with MapROM active, ROM reads
  ($F80000/$E00000) come from SDRAM over the direct path, and while it is
  being loaded, writes to those addresses go there too. Everything else
  (Chip RAM, custom chips, the SD card, the turbomem ROM board) keeps the
  old route. The fast RAM block is built with `BUS_RAM=0`, which removes
  its AS-driven RAM slave altogether, and the SDRAM address is formed from
  the CPU's early address one clock before the request, so nothing slow
  sits in the SDRAM controller's command path. `DIRECT=0` in `tg68_bus.v`
  turns the path off (set `BUS_RAM(1'b1)` on the fast RAM block in the
  top level at the same time, or fast RAM disappears). In simulation a fast RAM copy loop runs 33%
  faster: 4.85 MB/s against 3.64 on the old route, which matched the
  hardware MemTest.
* **32-bit addresses.** A 68020 drives A31–A24, and the Amiga bus has only
  24 address lines. Cycles with A31–A24 ≠ 0 that nothing on the FPGA claims
  are answered on-chip with `$FFFF` (`hi_null` in the top level). So
  Kickstart's probe of Zorro III space reads as "no board" instead of
  landing on a mirror of the ROM. CPU-space cycles (FC=7, interrupt
  acknowledge) still go to Gary.

## Cold boot

The fx68k build found that its first boot attempt always double bus faults
and the second, about 0.9 s later, always works. Its retry logic relies on
the core *halting*, which TG68K never does. So this build treats every
attempt as failed until 1.3 s after power-up and resets the machine every
~100 ms until then. `FORCE_RETRY_MS = 0` in `base64_tg68_top.sv` turns this
off, if you want to see whether TG68 needs it at all. Ctrl-A-A always works
either way.

## Building it yourself

1. Install **oss-cad-suite** from
   <https://github.com/YosysHQ/oss-cad-suite-build/releases> (the
   `windows-x64` installer is a self-extracting archive; unpack it to
   `C:\oss-cad-suite`).
2. From this folder:

   ```
   build.bat min            (or fastmem / full)
   build.bat full --seed 9  (start the seed search somewhere else)
   ```

   On Linux/macOS: `python3 scripts/build.py min` with oss-cad-suite's
   `bin` on your PATH, or with the `yowasp-yosys` and
   `yowasp-nextpnr-ecp5` pip packages installed (`build.py` falls back to
   them when plain `yosys` / `nextpnr-ecp5` are missing). A build takes a
   few minutes per seed.
3. The bitstream lands in `build\<config>\base64_tg68_<config>.bit`.
   The design uses ~8.8k (min) to ~10.3k (full) of the FPGA's 24k LUTs,
and 16 (min) or 35 (full) of its 56 block RAMs.

**One trap, already handled in `build.py`:** the TG68 kernel and ALU must
keep their own hierarchy during synthesis (`keep_hierarchy`, then
`flatten` at cell level). Flattened first, yosys turns the GHDL netlist into
~18k LUTs, and nextpnr can't route it. That is very likely what "struggled
to build the TG68K CPU" in the parent README was.

If `build.bat` can't find Python, install it from python.org. The scripts
use only the standard library.

### Timing: why nextpnr says FAIL and why that's expected

TG68K advances one step per `clkena` pulse, and every register in it is
gated by `clkena`. The adapter guarantees that the CPU's inputs are stable
≥ 2 clocks before they're used, its outputs are only read ≥ 3 clocks after
they change, and steps are ≥ 4 clocks apart. So the kernel has 23–46 ns
depending on the path, not 11.6 ns. nextpnr can't be told that (no multicycle constraints) and always
reports ~22–25 MHz "FAIL". That number is the kernel and doesn't matter.

`scripts/check_timing.py` is the real check. It re-times the routed design
from nextpnr's SDF output and gives each path the budget the design
actually provides:

| Path class | Budget | Why |
| --- | --- | --- |
| logic → logic | 1T | Ordinary 86 MHz logic: the bridge, slaves, SDRAM |
| clkena → kernel | 1T | The one genuinely single-cycle path into the CPU |
| bus outputs → … | 2T | Address/FC/R/W/write data (and the slaves' registered decodes of them) change only while AS is high, 3 clocks before AS falls |
| … → read-data latch | 2T | The adapter latches read data (and the cache's fill copy) 2 clocks after DTACK; slaves hold data from DTACK on |
| icache/direct → … | 1T | The cache RAMs and their registers, the direct path's read-data and prefetch registers |
| adapter ctrl → … | 1T | `tg68_bus`'s own state and flags. Split from *logic* because they steer the read-data registers on single-clock transitions, so the slaves' 2T read-data budget must not apply to them |
| … → window decode | 1T | The fast RAM window registers the direct-path decode reads |
| config regs → … | 4T | Autoconfig base/configured, maprom bits, SDRAM `init_done`: quasi-static |
| adapter → kernel | 2T | `TG_DIN`; also `k_long_ack` (step 7), changed ≥ 2 clocks before the CPU samples it (the testbenches assert this) |
| kernel → cache RAM | 2T | `TG_SETTLE`-1: the early lookup reads the cache RAMs on the edge into DECIDE (step 6) |
| kernel → adapter | 3T | `TG_SETTLE` |
| kernel → kernel | 4T | `TG_STEP` |

`build.py` runs it after every place-and-route, tries up to 8 seeds until
it gets `RESULT: PASS`, and writes `timing.txt`. Expect the 1T classes to
pass by fractions of a ns: the same thin margin the fx68k README warns
about, on the same −6 speed grade. The supplied bitstreams:

Step 6 (early lookup) builds as supplied (known good on hardware; `full`
only, as from this step on):

| Build | Seed | Worst 1T slack | Worst multicycle slack |
| --- | --- | --- | --- |
| full | 12 | +0.10 ns | +4.0 ns |

The early read itself has plenty of room: kernel → cache RAM needs 15.1 ns
of its 23.3 ns. The first build failed every seed by 1.5–3.5 ns because the
looked-up word went into `k_din` through its wide input mux; it now has its
own register (`k_din_c`). The second failed on a path from `fm_cfg_match`:
that is fastmem_zii's `addr_match` (static after autoconfig, already in the
checker's config class) under the name of the top-level wire it drives, so
`check_timing.py` now knows that name too.

Step 5 (pair buffers) builds as supplied (`full` known good on hardware):

| Build | Seed | Worst 1T slack | Worst multicycle slack |
| --- | --- | --- | --- |
| min | 12 | +0.21 ns | +3.7 ns |
| full | 2 | +0.22 ns | +3.2 ns |

The pair buffers cost timing at first: the first version failed every seed of
every build. The tag check is now pipelined over three clocks, the cache RAM
outputs go straight into registers, the prefetch hit and the buffer hits
share one branch of the bridge's decision, and `ib_a`/`ib_d`/`db_a`/`db_d`
are classed like `pf_a` in `check_timing.py` (loaded at least 3 clocks before
they are read; the testbench asserts that). The `fastmem` configuration (fast
RAM, no SD card) did not pass in 12 seeds (best -1.36 ns), so no `fastmem`
bitstream is supplied for step 5.

Step 4 (data cache) builds as supplied:

| Build | Seed | Worst 1T slack | Worst multicycle slack |
| --- | --- | --- | --- |
| min | 1 | +0.20 ns | +4.3 ns |
| full | 3 | +0.45 ns | +3.3 ns |

(`full` was rebuilt with the SD pin fix; the first step 4 `full`, seed 1,
had +0.60 ns.)

The data cache's extra block RAM spread the design out, and three paths
that had been borderline since step 3 went over. Each was restructured
rather than seed-hunted: the bridge's "is this cycle internal?" decision
now comes from a register (`int_win_r`), the cache write ports are fed
from registers rather than DECIDE's branch logic, and the cache enables
are registered. `check_timing.py` also gained the *adapter ctrl* class
above, which closes a gap in the earlier checks (the step 3 `full`
build was re-checked against it and still passes).

Step 3 (direct path) builds as supplied:

| Build | Seed | Worst 1T slack | Worst multicycle slack |
| --- | --- | --- | --- |
| min | 2 | +0.19 ns | +2.7 ns |
| full | 13 | +0.24 ns | +3.1 ns |

Step 3 `full` passed on 3 of the 10 seeds tried (1, 13 and 20); the
misses were by 0.04–2.4 ns. Expect to try a handful of seeds (`--seeds 20`) if you
change anything.

Step 2 (cache) builds as supplied:

| Build | Seed | Worst 1T slack | Worst multicycle slack |
| --- | --- | --- | --- |
| min | 5 | +0.72 ns | +4.1 ns |
| full | 8 | +0.30 ns | +4.2 ns |

To pick the best of several seeds rather than the first that passes, run
nextpnr by hand with `--seed N` for a few values and compare each
`check_timing.py` result. `build.py` stops at the first pass.

At 4/3/2/2 pacing the **fastmem** configuration did not close timing on 26
seeds: the fast RAM request path (AS/DS → fast RAM → SDRAM command) misses
by 0.03–3.8 ns. `full` contains the same logic and passed, so it's a
placement problem, not a design one. `bitstreams_prev/` keeps the 5/4/3
fastmem build, which closed and works, for bring-up. If you build fastmem
at this pacing yourself, it will most likely fail the timing check.

Two deliberate differences from the Diamond build's constraints: no
multicycle constraints for fx68k (it isn't there), and AS/VMA aren't in
I/O flops (see the comment at `rt_as_n` in the top level).

## Files

```
build.bat                       Windows entry point
scripts/build.py                yosys -> nextpnr -> timing check -> ecppack
scripts/check_timing.py         multicycle-aware timing check from SDF
scripts/lpf_for_nextpnr.py      Diamond LPF -> nextpnr LPF
scripts/gen_tg68.sh             regenerate the TG68 Verilog (needs GHDL)
scripts/fix_latches.py          used by gen_tg68.sh
constraints/base64_tg68.lpf     generated from base64_diamond.lpf
rtl/base64_tg68/
  base64_tg68_top.sv            fx68k top with the CPU swapped ("TG68:" marks changes)
  tg68_bus.v                    TG68K -> 68000-style bus adapter
rtl/tg68/
  TG68K*.vhd                    TG68K.C sources, unmodified
  tg68_020.vhd                  68020-mode wrapper
  tg68_020_b0.v                 the same, converted to Verilog (what the build uses)
rtl/base64_fx68k/               the fx68k build's slaves; changes marked "TG68:"
                                (fastmem_zii: direct SDRAM port, BUS_RAM; the
                                slaves also export their windows for int_win)
sim/                            test benches (Verilator), see sim/README.md
sw/maprom/                      maprom command (68000 asm) and its build script
```

### Why the CPU is pre-converted Verilog

TG68K.C is VHDL, and yosys only reads VHDL through the GHDL plugin, which
oss-cad-suite's Windows build doesn't reliably ship. `tg68_020_b0.v` is
GHDL's synthesis output for the 68020 configuration. 32-bit MUL/DIV,
bitfields, VBR and 68010+ stack frames are on. The barrel shifter is off:
it saved nothing measurable in LUTs and isn't needed for function.
`scripts/gen_tg68.sh` regenerates it (Linux, needs `ghdl` and `yosys`;
Ubuntu's `ghdl` 4.1.0 package with `YOSYS=yowasp-yosys` reproduces the
committed netlist byte for byte). Its arguments select variants: barrel
shifter, no bitfields, iterative multiply.

From step 7 the VHDL is m1nl's fork of TG68K.C
(<https://github.com/m1nl/TG68K.C>, commit `a8e6f38`), unmodified: upstream
TG68K.C (our kernel was identical to its base) plus a cheaper rotate unit and
the 32-bit data path (`long_cand`/`long_ack`, `data_in_hi`,
`data_write_lo`). The wrapper `tg68_020.vhd` passes those ports through and
sets `DataPath32` with its `DP32` generic. It is 1: longword data reads
only. The fork can also pair 32-bit immediates and absolute-long address
extensions (bits 1 and 2), but either of those put the kernel's clock-enable
paths 2-5 ns over budget on every seed tried (they sit in its program-counter
and fetch logic), while data pairs alone leave the kernel's address timing as
it was.

GHDL turns a handful of VHDL `case ... when others => null` statements into
latches that yosys rejects. `fix_latches.py` neutralises exactly those.
Every one is a case that already lists all 0/1 values, so the default can
only be reached in simulation with X/U inputs.

## Credits

Tobias Gubener (TG68K.C), m1nl (the TG68K.C fork with the 32-bit data path,
and the IcePi Zero Minimig that showed how far this core can go), Alastair M.
Robinson (the parent gateware and its TG68 work), the fx68k build's authors for the whole board-side design,
Niklas Ekström (the SD controller and sfsd.device), and JBilander for the
Base64.

## Licences

The parts keep their own licences: TG68K.C is LGPL-3.0 (headers in
`rtl/tg68/`), the SD controller files are GPL-2.0-only (headers in
`rtl/base64_fx68k/`), and the Base64 hardware is CC BY-SA 4.0. The
base64_gateware sources this build is derived from carry no licence file,
so ask their author before redistributing.
