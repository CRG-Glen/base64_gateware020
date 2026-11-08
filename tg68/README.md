# Base64 TG68 — 68020 gateware for the Base64 / iCESugar-Pro

TobiFlex's **TG68K.C** core in **68020 mode**, on JBilander's Base64 carrier,
built with the **open-source** FPGA tools. No Lattice Diamond needed.

This is the fx68k build's `base64_top.sv` with the CPU swapped. Everything
around the CPU comes along: the 7 MHz bus bridge, the cold-boot reset
handling, Zorro II and 32-bit fast RAM, the turbomem DiagArea board, MapROM
and the SD card. An adapter, `tg68_bus.v`, makes TG68K look like fx68k's
ports and adds the caches and the direct SDRAM path. Changes to the fx68k
build's own files are few and marked `TG68:`.

> **Status:** steps 1-9 run on an A500+. The latest, step 9 `full`: 9221
> Dhrystones, 9.62 MIPS, AIBB MemTest 12.20 MB/s with the caches on,
> xSysInfo fast RAM 23.31 MB/s, SD card 2.18 MB/s (sfsd.device). That is
> about 3.3× the 2783 Dhrystones of the first working build.
>
> **SD card: every `full` bitstream from step 4 on reads the card.** The
> step 1-3 `full` files drove the card's data-out line (MISO) low, so the
> driver loaded but could never talk to the card (HDToolBox: "Drive does
> not support the SCSI inquiry command"). Don't use them with an SD card.

The bitstreams are not kept in git: download them from this repository's
**Releases** page (each release has that step's `bitstreams/` folder and the
`maprom` command), or build them yourself.

## The bitstreams

| Folder | What changed | Status |
| --- | --- | --- |
| `bitstreams/exp16x_seed9/` (branch `exp-16x-clock` only) | **Experimental, overclocked**: for a board whose ICS570B is rewired to x16 (113.5 MHz). Correct Amiga-side timing (bus cycles, E/CIA), SDRAM CL3, SD clock in spec. See *16x clock* | Simulated; not timing-signed (needs the chip ~36% faster than the worst-case model); **not yet run on hardware** |
| `bitstreams/step9_sdram32r/` | + 32-bit SDRAM reads: an aligned longword read that misses the caches is one SDRAM request (two READ commands back to back) and one CPU step | **Latest. Known good on hardware**, SD card included: MemTest 12.20 MB/s (+12% on step 8), xSysInfo fast RAM 23.31 MB/s (+42%); SysInfo Dhrystones unchanged (9221). `full` only |
| `bitstreams/step8_sdram32w/` | + 32-bit SDRAM writes: an aligned longword write to fast RAM is one CPU step and one SDRAM request (two WRITE commands back to back) | **Known good on hardware**, SD card included: 9226 Dhrystones (+6% on step 7), MemTest 10.93 MB/s (+43%). `full` only |
| `bitstreams/step7_datapath32/` | + 32-bit data path: aligned longword reads from the caches in one CPU step (m1nl's TG68K.C fork, banked caches) | **Known good on hardware**, SD card included: 8728 Dhrystones (+7% on step 6), MemTest 7.65 MB/s. `full` only |
| `bitstreams/step6_earlylookup/` | + early cache lookup: every cache hit in 5 clocks, not 7 (replaces the pair buffers) | **Known good on hardware**, SD card included: 8144 Dhrystones (+21% on step 5), MemTest 7.65 MB/s. `full` only |
| `bitstreams/step5_pairbuf/` | + pair buffers: the other half of a cached pair in 5 clocks, not 7 | **Known good. `full` on hardware**, SD card included: 6720 Dhrystones, MemTest 7.46 MB/s. `min` not run on hardware |
| `bitstreams/step4_dcache/` | + 8 KB data cache, cache hits overlap SDRAM writes; SD card pin fix | **Known good on hardware**, SD card included |
| `bitstreams/step3_direct/` | + direct CPU → SDRAM path for fast RAM, posted writes, word prefetch | **Known good on hardware**: MemTest 6.46 MB/s |
| `bitstreams/step2_icache/` | + 8 KB instruction cache | **Known good on hardware**: 4833 Dhrystones, 5.04 MIPS |
| `bitstreams/step1_no_cache/` | 2 clocks less per bus access (4/3/1/1 pacing) | Simulated and timing-checked |
| `bitstreams_prev/v3_*` | 4/3/2/2 pacing: 2783 Dhrystones on an A500+ | **Known good on hardware** |
| `bitstreams_prev/base64_tg68_fastmem_*` | Fast RAM, no SD, 5/4/3 pacing | Known good, for bring-up |

From step 6 on only `full` is built and released: the 68020 with fast RAM
(Zorro II and 16 MB at `$08000000`) and SD card boot. Steps 1-5 also had
`min` (68020 + motherboard only); `min` and `fastmem` still build
(`build.py min`), but they are no longer timing-checked or tested. `_plain` files are
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

Flash `base64_tg68_full_plain.bit`, fit the module and power on. With an SD
card prepared as for the fx68k build it boots from the card (same `Mask`
advice, `0x001FFFFE`, and the same DMA limitation); without one, use a
Workbench floppy in DF0:. The cold boot takes ~1.3 s longer than usual (see
*Cold boot* below).

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
  doesn't, that's the cold-boot behaviour below, not the core. If a
  bitstream that should work does nothing at all, copy it to the iCELink
  drive again: an incomplete copy can light the LEDs without running.

Once it boots, **SysInfo** should report a **68020**, `ShowConfig` should
list the 5194/13 fast RAM board, the 5194/14 ROM board and the SD card
board, and `AvailMem` should show the Zorro II fast RAM plus the 16 MB at
`$08000000`.

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
  with the cache off. The caches and the direct path that followed took it
  to 9226 Dhrystones (9.63 MIPS) by step 8; each step below has its
  numbers.
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
  absolute-long addresses) only longword data reads are switched on, when
  the memory side agrees; the other two cost more timing in the kernel than
  it has (see *Why the CPU is pre-converted Verilog*). Each cache is split into an even-word and an
  odd-word bank (same total size), so one lookup reads both words of a pair.
  When the core offers a pair and both words hit, the adapter answers
  `long_ack` and hands over both words: the pair costs 5 clocks instead of
  10. If only the asked word hits, it is taken as an ordinary access a clock
  later; a miss goes to memory as before (pairs come only from the caches
  so far; longword writes are still two 16-bit writes). In simulation,
  second pass from the caches: sequential reads 10.64 → 12.59 MB/s (+18%),
  scattered longword reads 15.66 → 20.41 MB/s (+30%), the 1 KB copy
  unchanged at 5.35 MB/s (its source and destination share cache slots, so
  its reads miss). On an A500+ (`full`), caches on: 8144 → 8728
  Dhrystones (+7%), 8.50 → 9.11 MIPS. AIBB MemTest is unchanged at
  7.65 MB/s: like the copy bench, it works through more memory than the
  8 KB data cache, so its reads miss and go to the SDRAM as two 16-bit
  reads, and writes are still two 16-bit writes. Pairs on writes and on
  misses are the follow-ups for that. Caches off: 3940 Dhrystones (step 6:
  3813; nothing step 7 changed is used with the caches off), MemTest 5.71
  MB/s. The cache-hit check now
  covers both words of every pair and that `long_ack` is set exactly for
  pair hits, and asserts that `long_ack` never changes in the clock before
  the CPU samples it.
* **32-bit SDRAM writes (step 8).** An aligned longword write to fast RAM
  (the Zorro II window, $08000000) now goes as a pair as well: the adapter
  answers `long_ack` for it, the CPU steps once, and the write is posted
  to the SDRAM controller as one request carrying both words. The
  controller issues two WRITE commands on consecutive clocks to the open
  row (column even, then odd; the chip allows a new command every clock),
  so the pair costs the SDRAM one clock more than a single word, instead
  of a second request (precharge, activate, write). Both words go into the
  data cache, one clock apart, and are dropped from the instruction cache
  as before; the prefetch buffer is dropped if it holds either word.
  Misaligned longwords, byte and word writes, and writes to Chip RAM or the
  Amiga bus are unchanged (16-bit). In simulation the 1 KB copy goes from
  5.35 to 6.45 MB/s (+21%); reads are unchanged (sequential 12.59 MB/s,
  scattered longwords 20.35 MB/s). The write shadow in the test benches
  records both words of a pair, the SDRAM model's timing checker now fails
  the run on any violation, and the `fastmem` bench requires pair writes
  to happen and checks a pair written over cached words, a pair read back
  from the SDRAM after eviction, and a misaligned longword. Reads from the
  SDRAM are still two 16-bit reads (a pair read on a cache miss is the
  next step). Timing needed a second small kernel change (a registered
  clock enable, see *Why the CPU is pre-converted Verilog*). On an A500+
  (`full`), caches on: 8728 → 9226 Dhrystones (+6%), 9.11 → 9.63 MIPS,
  AIBB MemTest 7.65 → 10.93 MB/s (+43%: its writes are longwords). Caches
  off: 3982 Dhrystones (step 7: 3940), MemTest 5.71 → 6.15 MB/s (+8%;
  pair writes don't depend on the caches). SD card 2.18 MB/s as before.
  xSysInfo (first measured on this step): 15711 Dhrystones, 8.94 MIPS,
  fast RAM 16.38 MB/s, Chip RAM 2.39 MB/s, ROM 16.38 MB/s (the same as
  fast RAM: Kickstart runs from the MapROM copy in SDRAM), SD card
  1.9 MB/s.
* **32-bit SDRAM reads (step 9).** An aligned longword read from fast RAM
  that misses the caches (or with the caches off) is now one SDRAM request
  as well: the controller issues two READ commands on consecutive clocks
  (column even, then odd) and the two words arrive one clock apart, so the
  pair costs one clock more than a single word. The CPU then steps once
  with both (`long_ack`; first word on `data_in_hi` from `k_din`, second on
  `data_in` from its own register `k_din_lo`). Before, the second word came
  from the one-word prefetch, a separate request, and took a second CPU
  step. Both words fill the data cache (the second through the prefetch
  fill path). No prefetch follows a pair read. Misaligned longwords and
  word or byte reads are unchanged. In simulation the 1 KB copy goes from
  6.45 to 7.33 MB/s (+14%); the read benches are timed on a pass from the
  caches and don't move. The tests check both words of every pair read
  against the write shadow, require pair reads to happen, check that a
  pair read fills both cache words (a re-read must be a pair hit), and
  read a pair on a miss, from the cache and with the caches off.
  Timing: the sequencer state `q` is now one-hot (see *Timing*). On an
  A500+ (`full`), caches on: AIBB MemTest 10.93 → 12.20 MB/s (+12%),
  xSysInfo fast RAM 16.38 → 23.31 MB/s (+42%), SysInfo 9221 Dhrystones
  (step 8: 9226, unchanged: Dhrystone runs from the caches). Caches off:
  SysInfo 3982 → 4202 Dhrystones (+6%), MemTest 6.15 → 6.97 MB/s (+13%),
  xSysInfo 7802 Dhrystones, fast RAM 20.28 MB/s. xSysInfo's caches-on
  Dhrystones went 15711 → 15075 (−4%), which SysInfo does not show; not
  explained yet (one candidate: a speculative read is now a pair read, so
  one dropped on a cache hit holds the SDRAM a clock longer). SD card
  2.18 MB/s as before.
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
* **16-bit data bus.** TG68's bus port is 16 bits, so a longword is two
  transfers, as on the 68000, except an aligned longword read that hits
  the data cache (step 7), an aligned longword write to fast RAM (step 8)
  and an aligned longword read from fast RAM on a cache miss (step 9),
  each handed over in one step. The SDRAM chip on the iCESugar-Pro is 16
  bits wide as well; steps 8 and 9 move a pair as two back-to-back WRITE
  or READ commands in one request.
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

## 16x clock (experimental, branch `exp-16x-clock`)

The Base64's ICS570B multiplies the Amiga's 7.09 MHz clock by 12 (85.13
MHz). Rewired to multiply by 16, it gives 113.50 MHz. On such a board a
normal (12x) bitstream boots and runs about a third faster, but its Amiga
side runs at the wrong speed. The bus bridge builds its 7 MHz grid from a
fixed count of 12 fast clocks, so it thinks the Amiga clock is 9.46 MHz.
Its lock check doesn't notice, because the count matches again every third
cycle. The effects:

* bus cycles to the motherboard are 25% short and mostly off phase, so a
  slow device reads wrong: a Ripple IDE's boot ROM was found but never run;
* E, which clocks the CIAs, runs at 946 kHz instead of 709 kHz, so every
  CIA-timed delay (timer.device microseconds, floppy stepping, driver
  timeouts) is 25% short.

`build.py full --x16` builds a bitstream for an x16 board. Everything that
differs is under `` `ifdef TG68_X16 ``:

* the 7M grid counts 16 fast clocks (`CLK_MULT`), so bus cycles, E and the
  CIA timers are correct again; `PHASE_OFS` stays 2 (it mostly cancels the
  7M capture pipeline, which is a fixed number of fast clocks);
* the address, R/W and write data are held 2 fast clocks (17.6 ns) after
  AS rises instead of 1;
* the SDRAM runs at CAS latency 3 (the IS42S16160 -7 needs a 10 ns clock
  for CL2). Its other timings were already in spec at 113.5 MHz, because
  the controller adds state-machine clocks to each count; the fastmem
  bench's SDRAM model, which checks them in ns, reports no violation;
* the SD card's clock holds its low half one clock longer, so the fastest
  settings give 37.8 / 22.7 MHz (within SD's 50 / 25 MHz) instead of
  56.8 / 28.4 MHz;
* the 1 ms counter and the SDRAM controller's start-up wait use 113.5 MHz.

In simulation (`VLFLAGS=-DTG68_X16 sh sim/run.sh ...`) every test passes
at 113.5 MHz, with no SDRAM timing violations. Against the 12x build: copy
7.33 → 9.31 MB/s, read 12.59 → 16.22, scatter 20.35 → 25.67.

**It is overclocked.** The FPGA's timing is signed off against a worst-case
model (slowest chip, hot, low supply). At 113.5 MHz no seed comes close to
passing it, and none could without a much faster design. The kernel's
paths alone need the chip to be ~28% faster than the model. It works
because real chips at room temperature usually are: the 12x step 9
bitstream ran on Glen's x16 board, and by the same check it needs 1.28×.
For each 16x seed, `timing.txt` (checked at 113.6 MHz) shows how far past
the model it is. The test bitstream, seed 9, needs 1.36×: the best of
15 seeds, but more than the 1.28× of the 12x bitstream that ran on the x16
board, because that 12x seed was an unusually good placement (it is the
one seed in eight that passes at 12x). So it may be less stable on the
same board; more seeds can be tried if it is. nextpnr's clock target makes
no difference (seeds placed for 114 MHz came out identical), so `--x16`
keeps 86 MHz.

On this branch the 12x build is logically the same as main (the sims match
it clock for clock), but not bit-identical: with this yosys even text that
an `` `ifdef `` skips changes its internal numbering, and with it nextpnr's
placement. 12x releases are built from main.

## Building it yourself

1. Install **oss-cad-suite** from
   <https://github.com/YosysHQ/oss-cad-suite-build/releases> (the
   `windows-x64` installer is a self-extracting archive; unpack it to
   `C:\oss-cad-suite`).
2. From this folder:

   ```
   build.bat full
   build.bat full --seed 9  (start the seed search somewhere else)
   ```

   On Linux/macOS: `python3 scripts/build.py full` with oss-cad-suite's
   `bin` on your PATH, or with the `yowasp-yosys` and
   `yowasp-nextpnr-ecp5` pip packages installed (`build.py` falls back to
   them when plain `yosys` / `nextpnr-ecp5` are missing). A build takes a
   few minutes per seed.
3. The bitstream lands in `build\full\base64_tg68_full.bit`. Step 9
   `full` uses ~10.5k of the FPGA's 24k LUTs and 35 of its 56 block RAMs.
   Expect to try several seeds (`--seeds 12`): the timing margins are thin.

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
| clkena → kernel | 1T | The one genuinely single-cycle path into the CPU (`k_clkena`, and from step 8 `k_clkena_lw`) |
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

`build.py` runs it after every place-and-route, tries up to 8 seeds
(`--seeds N` for more) until it gets `RESULT: PASS`, and writes `timing.txt`. Expect the 1T classes to
pass by fractions of a ns: the same thin margin the fx68k README warns
about, on the same −6 speed grade. The supplied bitstreams:

Step 9 (32-bit SDRAM reads) builds as supplied (known good on hardware):

| Build | Seed | Worst 1T slack | Worst multicycle slack |
| --- | --- | --- | --- |
| full | 7 | +0.36 ns | +1.16 ns |

**How close to the edge the design is.** From step 7 on, only about one
seed in eight passes every class, and which path misses on the other
seeds changes from seed to seed. Step 8, known good on hardware, passed
on seed 3 only of seeds 1-8; the others missed by 0.1 to 2.5 ns, each on a
different class. Step 9's variants did the same. Restructuring the paths
that failed moved the misses elsewhere rather than removing them:

* The step 9 logic itself was taken out of the critical paths. The pair
  flag for the next request loads in CCMP/CFREE whenever the port is free
  (not per branch), a miss sets `k_long_ack` from one registered flag
  (`rp_go`), the second word has its own register instead of another
  `k_din` load, and it fills the cache through the prefetch fill instead
  of a new cache write source. In the controller the pair-read flags are
  set with the request, not in the read branches.
* The sequencer state `q` lost its initial value, so yosys recodes it
  one-hot (an initial value stops yosys treating a register as a state
  machine). That shortens the 1T paths from `q` through the step decision,
  which failed on most binary-`q` seeds. The kernel -> DECIDE paths grow
  instead, and fail on most other seeds. Seed 7 is the cleanest build
  found in all variants. `q` needs no power-up value: `extReset` is held
  through the power-up hold and loads it.
* Not kept: flag registers for the step decision (no better), and nextpnr
  without timing-driven placement (`--no-tmdriv`: kernel -> kernel failed
  by 3-4 ns). nextpnr has no multicycle constraints (its SDC support is
  `create_clock` and single-object `set_false_path`), so its placer
  optimises for a one-clock kernel that doesn't exist.

Step 8 (32-bit SDRAM writes) builds as supplied (known good on hardware):

| Build | Seed | Worst 1T slack | Worst multicycle slack |
| --- | --- | --- | --- |
| full | 3 | +0.37 ns | +1.70 ns |

Both margins are wider than step 7's. Getting there took two structural
changes. First, the pair-write flags (`dp_pair`, and the cache update's copy
of it) load on every DECIDE clock with the other port data instead of in
the posted-write branch: set inside the branch they added fan-out to the
DECIDE decode, and kernel → logic failed by 1-2 ns on most seeds. Second,
kernel change 2 above (the registered `clkena_lw`). Of seeds 1-4, seed 3
passes everything; the others miss by 0.1-0.8 ns, the same spread as step 7.

Step 7 (32-bit data path) builds as supplied (known good on hardware):

| Build | Seed | Worst 1T slack | Worst multicycle slack |
| --- | --- | --- | --- |
| full | 4 | +0.06 ns | +0.86 ns |

Both margins are thin: the multicycle one (kernel → logic, the kernel's
outputs into DECIDE) was +4 ns in step 6. With pairs live the kernel keeps
its pair logic, which slows its address (~21 → ~25 ns with every pair kind
on) and its clock enable. Getting here took: data pairs only (`DP32=1`); the
adapter's cycle data registers (`oEdb`, strobes, posted-write data) loading
on every DECIDE clock, out of the address decode, from their own enable
register (`dec_r`); the one-line kernel change above; and two classifier
fixes (kernel-internal registers named after `nReset`; `k_long_ack` is an
adapter → kernel input).

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

(Historical, steps 1-2:) at 4/3/2/2 pacing the **fastmem** configuration did not close timing on 26
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
  TG68K*.vhd                    TG68K.C (m1nl's fork), two changes marked "Base64"
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
(<https://github.com/m1nl/TG68K.C>, commit `a8e6f38`), with two marked
changes (below): upstream
TG68K.C (our kernel was identical to its base) plus a cheaper rotate unit and
the 32-bit data path (`long_cand`/`long_ack`, `data_in_hi`,
`data_write_lo`). The wrapper `tg68_020.vhd` passes those ports through and
sets `DataPath32` with its `DP32` generic. It is 1: longword data reads
only. The fork can also pair 32-bit immediates and absolute-long address
extensions (bits 1 and 2), but either of those put the kernel's clock-enable
paths 2-5 ns over budget on every seed tried (they sit in its program-counter
and fetch logic), while data pairs alone leave the kernel's address timing as
it was.

**The changes to the fork** (`TG68KdotC_Kernel.vhd`, marked "Base64"):

1. (step 7) `l1 <= long_ack AND cand` became `l1 <= long_ack`. `l1` is part of the
kernel's `clkena_lw`, which gates most of its registers, and with the AND that
path failed timing on 11 of 12 seeds (by up to 5 ns); without it it passed on
every seed tried (+0.3 to +1.8 ns). The AND is redundant here: the adapter
raises `long_ack` only for a pair the kernel offered on `long_cand` (which,
with data pairs only, is `cand`), and `cand` is decoded from kernel registers
that cannot change before the step. Both test benches assert that `long_ack`
is never high without `long_cand`.

2. (step 8) A generic `ClkenaLW_Ext` and an input `clkena_lw_in`: with the
generic at 1 (the wrapper's `CLKLW`), `clkena_lw` comes from that input
instead of being computed as `clkena_in AND (memmaskmux(3) OR l1)`. The
adapter supplies it from a register, `k_clkena_lw`, set on the same edge as
`k_clkena` to `NOT longword OR long_ack`. Both inputs are settled there:
`longword` (the kernel's existing output, `NOT memmaskmux(3)`) is final
SETTLE clocks after a step, and `long_ack` never changes on a step edge.
`clkena_lw` has about 320 loads; computed in the kernel it put a LUT and a
second high-fanout hop on every clkena → kernel path. Step 8's first builds
failed that path on 11 of 12 seeds (−0.5 to −3.4 ns) on a kernel netlist
identical to step 7's, and so did a build with the pair writes switched off,
so the path was simply fragile under any change elsewhere. With the register
it gets +0.3 to +1.7 ns on three of four seeds. Both test benches check on
every clock that `k_clkena_lw` equals the kernel's original formula.

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
