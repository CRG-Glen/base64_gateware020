# Base64 TG68 — 68020 gateware for the Base64 / iCESugar-Pro

TobiFlex's **TG68K.C** core in **68020 mode**, on JBilander's Base64 carrier,
built with the **open-source** FPGA tools. No Lattice Diamond needed.

This is the fx68k build's `base64_top.sv` with the CPU swapped. Everything
around the CPU comes along: the 7 MHz bus bridge, the cold-boot reset
handling, Zorro II and 32-bit fast RAM, the turbomem DiagArea board, MapROM
and the SD card. An adapter, `tg68_bus.v`, makes TG68K look like fx68k's
ports and adds the caches and the direct SDRAM path. Changes to the fx68k
build's own files are few and marked `TG68:`.

> **Step 13:** the normal bitstream can switch the whole design between
> 12x, 14x and 16x while running, from a Shell (`speed 16`), with no board
> mod; see *Clock speed at run time (step 13)*. It runs on Glen's A500+ at
> all three speeds. **Step 14** (test build) gives the timing check room
> again, at no cost in clocks.
>
> **Status:** steps 1-12 run on an A500+. The latest, step 12 `full`, at
> the stock 12x clock: 9690 Dhrystones (10.11 MIPS), AIBB MemTest 15.74 MB/s,
> xSysInfo fast RAM 23.33 MB/s with the caches on; 5177 Dhrystones and
> 8.14 MB/s with them off. That is about 3.5× the 2783 Dhrystones of the
> first working build. On a board with its clock multiplier rewired to x16
> (see *16x clock*), the `_x16` files give 12907 Dhrystones and 19.97 MB/s.
> Steps 11 and 12 are for games: code that runs from Chip RAM is cached
> (step 11), and Chip RAM writes go through an 8-entry write buffer while
> the CPU carries on (step 12). Frontier and Gloom run much faster with
> the caches on.
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
| `bitstreams/step14_headroom/` | + timing headroom: the paths that limited every build since step 7 restructured, at no cost in clocks (identical clock counts in every bench); step 13b's longer 7 MHz calibration (`speed 12 rise` no longer needed). 12x files (switchable) and `_x16` files | **Test build, not yet run on hardware.** 4 of seeds 1-11 pass at 12x (step 13b: 0 of 40); seed 8: +0.43 ns 1T, +2.53 ns multicycle; 14x / 16x need 1.11× / 1.27× the worst-case model |
| `bitstreams/step13_speed/` | + clock speed switched at run time: `speed 12`, `speed 14` or `speed 16` in a Shell (the `speed` command is in the folder), 12x / 14x / 16x from the FPGA's PLLs, no board mod, power-on default 12x; 7 MHz capture calibration; the 7 MHz aligner's lock fixed. 12x files (switchable) and `_x16` files (board mod, fixed) | **Runs on hardware at 12x, 14x and 16x** (switching from the CLI). 12x seed 12 passes timing; at 14x / 16x it needs the chip 1.14× / 1.30× faster than the worst-case model. At 12x its calibration can keep a falling-edge 7 MHz sample that later moves (`$270C`); `speed 12 rise` after a cold boot avoids it (fixed in step 14) |
| `bitstreams/step12_wbuf/` | + 8-entry Chip RAM write buffer: up to 8 Chip RAM writes (4 longwords) are taken at once and written out in order while the CPU carries on. 12x and 16x files | **Latest known good on hardware**, 12x (seed 6) and 16x (seed 4), SD card included. Benchmarks as step 11 (they run from fast RAM and the caches); games look smoother, not yet measured |
| `bitstreams/step11_games/` | + Chip RAM code in the instruction cache (CACR CI/CEI now flush), posted Chip RAM writes, SDRAM bank permutation, pair prefetch, shorter uncached read. 12x and 16x files | **Known good on hardware**, 12x (seed 14) and 16x (seed 1), Kickstart 1.3 and 3.2.3, SD card included. MemTest 15.73 / 8.49 MB/s at 12x (+28% / +29%), 19.97 / 10.39 at 16x (+26% / +25%), games much faster. Code that DMAs itself into Chip RAM without clearing the cache needs the caches off (see step 11) |
| `bitstreams/step10_ifetch32/` | + instruction prefetch (the next word after an instruction read from SDRAM) and 32-bit instruction-stream pairs (32-bit immediates and absolute-long addresses in one CPU step). 12x and 16x files | **Known good on hardware**, 12x and 16x, SD card included: 9691 / 12936 Dhrystones (12x / 16x, +5% on step 9), caches off 4918 / 5982 (+17% / +15%). Caches-off MemTest 5-7% lower |
| `bitstreams/exp16x_seed9/` (never released) | The first 16x build (step 9 design): for a board whose ICS570B is rewired to x16 (113.5 MHz). Correct Amiga-side timing (bus cycles, E/CIA), SDRAM CL3, SD clock in spec. See *16x clock*. Superseded by the `_x16` files of steps 10 and 11 | **Worked on Glen's x16 board**, Ripple IDE ROM included: 12311 Dhrystones, MemTest 15.81 MB/s |
| `bitstreams/step9_sdram32r/` | + 32-bit SDRAM reads: an aligned longword read that misses the caches is one SDRAM request (two READ commands back to back) and one CPU step | **Known good on hardware**, SD card included: MemTest 12.20 MB/s (+12% on step 8), xSysInfo fast RAM 23.31 MB/s (+42%); SysInfo Dhrystones unchanged (9221). `full` only |
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
  ($F80000–$FFFFFF), and from step 11 also from Chip RAM, as a real
  68020's does (see step 11 for what that means for DMA-loaded code).
  Every CPU write to a cacheable address invalidates its entry, so
  self-modifying code and program loading by the CPU work without
  CacheClearU. CACR's EI bit turns it on and off as on a real 68020: off
  at reset, and Kickstart 2.0+ turns it on; FI freezes it. Up to step 10
  the clear bits (CI/CEI) were ignored; from step 11 either one flushes
  both caches. The cache is flushed after every reset. `ICACHE=0` in
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
* **Instruction prefetch and 32-bit instruction-stream pairs (step 10).**
  Two changes for code that runs from SDRAM, as it does with the caches
  off or on an instruction-cache miss:
  * After an instruction read from SDRAM, the next word is prefetched
    into the one-word buffer, as data reads already did. A following
    fetch of that word takes it from the buffer, and the word fills the
    instruction cache.
  * The CPU core's two instruction-stream pair kinds are on (`DP32 = 7`):
    a 32-bit immediate (MOVE.L #, ADDI/SUBI/CMPI/ANDI/ORI/EORI.L #,
    ADDA/SUBA/CMPA.L #) or an absolute-long address (MOVE, LEA, PEA, TST,
    CLR, ADD/SUB/CMP/AND/OR from abs.L) is taken in one CPU step instead
    of two, from the instruction cache (both banks) or from SDRAM (a step
    9 pair read). In step 7 these modes failed the clock-enable paths by
    2-5 ns on every seed; with step 8's registered `clkena_lw` they now
    cost ~1-2 ns on kernel -> logic.
  The core never fetches opcodes 32 bits at a time, so the pairs only help
  instructions with those operands. In simulation, the caches-off read
  loop (`bench readoff`) goes from 5.06 to 5.42 MB/s at 12x (+7%) and
  6.32 to 6.72 MB/s at 16x; the other benches don't move (their loops have
  no such operands and run from the caches). The prefetch is small because
  the single buffer is shared: a data read in between replaces the
  prefetched instruction word, and a buffer hit doesn't chain the next
  prefetch. The tests count instruction-stream pairs from the cache and
  from SDRAM and check them against the write shadow.

  On the A500+ (step 9, or the first 16x build, → step 10):

  | | 12x | 16x |
  | --- | --- | --- |
  | SysInfo Dhrystones, caches on | 9221 → 9691 (+5%) | 12311 → 12936 (+5%) |
  | SysInfo Dhrystones, caches off | 4202 → 4918 (+17%) | 5180 → 5982 (+15%) |
  | AIBB MemTest, caches on | 12.20 → 12.28 MB/s | 15.81 → 15.91 MB/s |
  | AIBB MemTest, caches off | 6.97 → 6.60 MB/s (−5%) | 8.88 → 8.28 MB/s (−7%) |
  | xSysInfo Dhrystones, caches on / off | 15075 / 7802 → 15363 / 7536 | 19429 / 9496 → 21233 / 10318 |
  | xSysInfo fast RAM, caches on / off | 23.31 / 20.28 → 23.35 / 21.01 MB/s | 29.18 / 25.20 → 29.19 / 25.98 MB/s |

  CPU-bound code gains (the instruction-stream pairs with the caches on,
  both changes with them off). Caches-off MemTest loses 5-7%, most likely
  because an instruction prefetch the loop doesn't use still occupies the
  SDRAM when the next data read wants it. xSysInfo varies by a few percent
  between runs (see step 9). The SD card works on both; 2.2 MB/s in
  xSysInfo at 16x with the caches on.
* **Games and uncached code (step 11).** CPU-heavy games such as
  Frontier and Gloom ran about as fast with the caches off as on. Frontier
  shows why: its executable puts 157 KB of code in a hunk that must load
  into Chip RAM (`HUNK_CODE` with the CHIP flag), and the caches never
  held Chip RAM. Every instruction word from there is a motherboard cycle,
  about 60 clocks, against 4-5 for a cache hit. Fast RAM was not the
  bottleneck. Step 11 changes:
  * **Chip RAM code is cached** in the instruction cache, as on a real
    68020 (the A1200's included). A CPU write to Chip RAM drops its
    entry, as for fast RAM. Writes by DMA (the blitter, the disk) are not
    seen, so code loaded by DMA needs the cache cleared before it runs:
    AmigaOS does that (LoadSeg calls CacheClearU, which sets CACR CI), and
    CI and CEI now flush both caches (kernel change 3: the kernel keeps
    CACR bits 2-3 set for one step after the MOVEC that sets them; they
    always read back 0). An old trackloader that DMAs code into Chip RAM
    and jumps to it without clearing the cache can crash with the caches
    on, as it can on an A1200; turn the caches off for it (SysInfo, or
    `CPU NOCACHE`). The data cache still never holds Chip RAM.
  * **Posted Chip RAM writes.** A CPU write to Chip RAM ($000000-$1FFFFF)
    is acknowledged as soon as the CPU presents it, and the bridge runs
    the motherboard cycle on its own, with 68000 timing (AS at a 7 MHz
    rising edge, the data strobes one edge later, the end on the falling
    edge after DTACK, address and data held to the next rising edge). The
    CPU carries on from the caches and fast RAM meanwhile; its next
    motherboard cycle waits for the posted one to end. Writes to custom
    chip and CIA registers are never posted, so an interrupt clear has
    happened before the next instruction runs. `POST_CHIP = 0` in the
    top level turns it off.
  * **SDRAM bank permutation** (`fastmem_zii.v`). The SDRAM bank came from
    word-address bits 10:9, so code and data a multiple of 4 KB apart
    shared a bank, and every switch between them closed and reopened a
    row (~5 clocks). The bank now also takes two groups of row bits (XOR),
    so blocks 4-32 KB apart sit in different banks. The map is one to one
    and the same for every fast RAM and MapROM address.
  * **Pair prefetch.** A 16-bit read from fast RAM at an even longword
    address that misses the caches is now an SDRAM pair read (step 9),
    and the second word goes to the prefetch buffer; before, the prefetch
    was a second request after the first.
  * **A shorter direct read.** An uncached 16-bit read hands its word to
    the CPU straight from the SDRAM's early data (`k_din_dw`) and steps it
    in DDATA, one state earlier.
  In simulation (12x / 16x; 16x in brackets):

  | Bench | Step 10 | Step 11 |
  | --- | --- | --- |
  | `bench chip`: a loop in Chip RAM writing 1 KB to Chip RAM (a game drawing into its screen) | 1133 µs | 442 µs (2.56×) |
  | `bench readoff`: fast RAM read loop, caches off | 5.42 (6.72) MB/s | 7.61 (9.29) MB/s (+40%) |
  | `bench copy`: fast RAM copy, caches on | 7.38 (9.40) MB/s | 8.63 (10.89) MB/s (+17%) |
  | `bench read`, `bench scatter` | | unchanged |

  `bench chip`'s gain is all from caching the loop: it writes back to
  back, so each write waits for the posted one before it, and posting off
  gives the same 442 µs. With twelve ALU instructions between the writes
  (a variant, not in the tree), posting takes it from 695 to 550 µs
  (1.26×): it pays off where code computes between Chip RAM writes, as a
  chunky-to-planar loop does.
  The tests run code from Chip RAM twice and require cache hits the
  second time, change it by CPU write (the new code must run), change it
  "by DMA" (the test bench rewrites the word behind the CPU: the old code
  must still run, and the new one after CACR CI), and check that posted
  writes land in program order (at least 10 must be posted).

  **The first step 11 files did not boot** (a yellow screen with
  Kickstart 3.2.3, a reset loop or a green Chip RAM error with 1.3;
  DiagROM ran). Test builds with each change switched off found posted
  writes to blame (`POST_CHIP=0` booted both ROMs). When the CPU's data
  strobe for a write arrived on the very clock the bridge asserted AS on
  the motherboard, the bridge's data-enable register was loaded from the
  old AS value and the posted-write sequencer then skipped its own "AS
  down, data out" step, so the write went to Chip RAM with the data bus
  undriven. In the simulation the CPU's cycles never started at that
  phase of the 7M clock; on the Amiga, cached code and DMA shift it all
  the time. The data bus is now driven whenever a posted write's AS is
  down. The test bench gained random wait states, a check that the data
  bus is driven whenever Chip RAM latches a write, and a loop of fast RAM
  reads and Chip RAM writes that starts writes at every phase; it
  reproduces the bug on the old bridge. The switches used to find it stay
  in the source: `POST_CHIP` (top level), `CHIP_IC`, `CACR_CLR`, `RD11`
  (`tg68_bus.v`) and `BANK_XOR` (`fastmem_zii.v`), all on by default.

  On the A500+ (step 10 → step 11, caches on / off):

  | | 12x | 16x |
  | --- | --- | --- |
  | SysInfo Dhrystones | 9691 / 4918 → 9690 / 5161 | 12936 / 5982 → 12784 / 5992 |
  | AIBB MemTest | 12.28 / 6.60 → 15.73 / 8.49 MB/s (+28% / +29%) | 15.91 / 8.28 → 19.97 / 10.39 MB/s (+26% / +25%) |
  | xSysInfo Dhrystones | 15363 / 7536 → 16245 / 8290 (+6% / +10%) | 21233 / 10318 → 22042 / 12023 (+4% / +17%) |
  | xSysInfo fast RAM | 23.35 / 21.01 → 23.31 / 21.15 MB/s | 29.19 / 25.98 → 29.19 / 26.21 MB/s |

  The benchmarks run from fast RAM and the caches, so they show the SDRAM
  changes (MemTest +25%) but not the Chip RAM ones; the games do: Glen
  reports Frontier and Gloom running much better, close to a 50 MHz
  68030. SD card 2.2 MB/s. Kickstart 1.3 and 3.2.3 boot at 12x and 16x.
* **Chip RAM write buffer (step 12).** Step 11 posted one Chip RAM write;
  the next one waited until it was on the bus and done. Step 12 holds up
  to 8 (`CHIP_WB` in the top level, 1-8), as the Cyberstorm and Tsunami
  boards do, so a MOVEM.L of four longwords, or a chunky-to-planar
  routine's burst of output, is taken at once and the CPU carries on with
  its arithmetic while the bridge writes it out. Rules that keep the Amiga
  seeing every access in program order:
  * Only writes to Chip RAM ($000000-$1FFFFF) are buffered, never custom
    chip or CIA registers or the on-FPGA boards.
  * A write to Chip RAM is recognised from its address and R/W, which are
    valid before AS, so the bridge never starts it on the motherboard
    directly: every one goes through the buffer, in order. (That also
    removes the step 11 data-bus race at its root.)
  * Every other motherboard cycle (Chip RAM reads, custom chip and CIA
    registers, interrupt acknowledge) waits until the buffer is empty, so
    a blit started after a screen write sees the write, and a read of a
    buffered address gets the new data.
  * A bus request from another board is not passed to the CPU side while
    the buffer is draining.
  The total Chip RAM write rate is still the Amiga's 7 MHz bus; what the
  buffer removes is the CPU waiting for it. In simulation (12x), a loop
  that writes four longwords and then does 32 instructions of arithmetic,
  about what a chunky-to-planar merge does per burst, takes 679 µs per
  KB with one posted write (step 11), 625 µs with 2 entries, 517 µs with
  4 and 445 µs with 8: as fast as back-to-back writes, so all of the
  arithmetic now overlaps the bus (1.53×). Back-to-back writes gain 4%
  (463 → 445 µs) and `bench chip` nothing (it is bus-bound). New tests: a
  CIA read after four buffered writes must find all four in Chip RAM; a
  read of buffered data; a MOVEM.L longer than the buffer (the CPU must
  wait for room); the benches `wrchip`, `wrmix` and `wrfast`, which count
  the clocks the CPU spends waiting. (Checked against broken versions:
  other cycles not waiting for the buffer, the read pointer stuck, writes
  taken while full, the strobes swapped: all caught.)
  On the A500+ (step 11 → step 12, caches on / off): the benchmarks are
  unchanged within run-to-run variation, as expected, since they run from
  fast RAM and the caches:

  | | 12x | 16x |
  | --- | --- | --- |
  | SysInfo Dhrystones | 9690 / 5161 → 9690 / 5177 | 12784 / 5992 → 12907 / 5992 |
  | AIBB MemTest | 15.73 / 8.49 → 15.74 / 8.14 MB/s | 19.97 / 10.39 → 19.97 / 10.39 MB/s |
  | xSysInfo Dhrystones | 16245 / 8290 → 16330 / 9309 | 22042 / 12023 → 22042 / 11994 |
  | xSysInfo fast RAM | 23.31 / 21.15 → 23.33 / 21.15 MB/s | 29.19 / 26.21 → 29.18 / 26.20 MB/s |

  Frontier and Gloom look faster, but there is no number for that yet (a
  timedemo-style tool is being considered as a separate project).
  A fast RAM write queue was measured first and is not in this step: the
  fast RAM copy bench never waits for the SDRAM port, and a pure write
  burst waits 3% of the time, so a queue there could gain at most a few
  percent.
* **Timing headroom (step 14).** From step 7 on only about one placement
  seed in 8-16 passed the timing check at 12x, and step 13's extra logic
  (51% of the LUTs, up from 48%) made it worse: the step 13b build
  passed on none of 40 seeds. The paths that missed were old ones,
  routed longer on a fuller chip. Step 14 restructures them so that each
  does less work in its one clock, without adding a clock anywhere:
  * Kernel change 4 (from step 12, never shipped): the kernel's
    clkena_lw is two registers with half the loads each.
  * SDRAM: the open-row decision (row open, row hit, tRAS met) is
    registered a clock before the request reaches the controller (the
    address is already stable then), and a request is tested before a
    non-urgent refresh instead of through the refresh decision.
  * Cache hits: the wanted tag, the cache-on term and the word select are
    registered at DECIDE, so CCMP only compares tags.
  * The adapter's BRn (bus request, with the write buffer's busy flag) is
    a register, as HALTn became in step 13; the reset, the address hold
    after AS and the cache flush trigger likewise (step 13b).
  Every bench gives the same clock counts as before. Each precomputed
  value has a simulation-only check that it equals the live one whenever
  it is used (`pre_bad`, `cc_bad`); broken versions are caught. 4 of
  seeds 1-11 now pass at 12x. Not covered by the test benches: another
  bus master on the Amiga (BR), as from a DMA card.
* **Clock speed at run time (step 13).** The normal (12x) bitstream can
  now run the whole design at 12x, 14x or 16x the Amiga's 7.09 MHz,
  switched while the machine runs, with no board mod and no reflash. Type
  `speed 14` or `speed 16` in a Shell (`sw/speed/`, attached to each
  release); `speed` alone shows the clock in force and which speeds are
  available.

  | `speed` | System clock | Source |
  | --- | --- | --- |
  | 12 | 85.13 MHz | the ICS570B, straight from its pin (power-on default) |
  | 14 | 99.32 MHz | FPGA PLL, ×7/6 |
  | 16 | 113.51 MHz | FPGA PLL, ×4/3 |

  The ratios are exact, so each speed has a whole number of fast clocks
  per 7 MHz cycle and everything on the Amiga side (bus cycles, E, the
  CIA timers) stays correct at every speed, as in the `_x16` build. What
  changes with the speed, at run time: the 7M grid's count (12/14/16), the
  address hold after AS (2 clocks above 12x), the SDRAM's CAS latency (3
  at 16x, 2 below: the IS42S16160 needs a 10 ns clock for CL2), the SD
  card clock's low-half stretch (16x), and the 1 ms counter.
  How a switch runs, all in the gateware (`base64_tg68_top.sv` section
  13, `clkgen.v`): the `speed` command writes the new speed to the ROM
  board's register at +$F00A (key $5B, like MapROM's); the adapter stops
  starting bus cycles; once nothing is in flight (the adapter, the SDRAM
  port, the Chip RAM write buffer, AS at the CPU and on the motherboard)
  the SDRAM gets its new CAS latency if needed (a PRECHARGE ALL and a
  LOAD MODE), the clock switches through a glitch-free multiplexer (the
  old clock stops low, the new one starts from low, so no pulse is cut
  short), the 7M aligner re-locks to the new count, and the CPU carries
  on. It takes about 9 ms, nearly all of it the 7 MHz calibration
  below. Chip DMA, interrupts and the CIAs run on through it; the CPU
  just sees one long bus cycle. A speed whose PLL has not locked is
  refused. Asking for the speed already in force recalibrates.
  **7 MHz capture calibration.** The bridge finds the Amiga's 7 MHz phase
  by sampling its clock on the falling edge of the fast clock, half a
  period away from the edges, which the ICS570B makes coincide. The speed
  multiplexer is built in FPGA logic (the chip's own clock selector,
  DCSC, came out of the open tools with a bitstream that could not be
  checked without hardware), and it delays the clock by about 5-6 ns at
  12x, a different amount for each speed and each build. That can put
  the falling-edge sample right on a 7 MHz transition, where it would
  catch the edge a clock early or late at random. So the 7 MHz clock is
  now sampled on both edges, half a clock apart (one of the two is then
  always at least a quarter period from a transition), and a calibration
  watches both: a sample near a transition sees the edge move, a clean
  one never does. The falling-edge sample stays in use unless it moved
  more than the rising-edge one (it is the one closest to the old
  timing). The calibration runs over the third quarter of the power-up
  hold (~0.33 s, ~2.3 million 7 MHz cycles) and for 65536 cycles (~9 ms)
  in every speed switch, with the CPU held. (The first step 13 build
  watched 2048 cycles. On Glen's A500+ at 12x its falling-edge sample,
  about 0.5 ns from a transition, passed that and kept moving now and
  then afterwards, while the rising one, forced with `speed 12 RISE`,
  never moved through a demo; step 13b's longer windows are for that.) `speed` shows which edge is
  in use and whether either sample, or the phase aligner, has moved
  since; `speed 16 RISE` / `FALL` force the edge, for testing.
  Found on the way: the 7 MHz phase aligner (from the fx68k build) never
  locked. It compared its counter with the value it would have one clock
  after an aligned edge, so it re-acquired on every edge. That was
  harmless while the edge never moved, but its tolerance of an odd noisy
  edge (three disagreements in a row before it re-acquires) never
  worked. Fixed; the grid is the same. So the red LED's "aligner
  slipped" now means what it says, and it is cleared by each
  calibration.
  The speed **stays over a reset**; only a power cycle (the FPGA
  reloading) returns to 12x. So a speed that is too fast for a board is
  undone by switching off and on.
  The 14x and 16x speeds are made from the board's 12x clock, so **the
  ICS570B must be strapped for x12** (stock). On a board modded for x16,
  use the `_x16` files as before: they have a fixed clock and `speed`
  says so.
  16x is overclocked exactly as the `_x16` build is (see *16x clock*); 14x
  less so. Test: the `fastmem` sim switches to 16x, to 14x and back to
  12x, with memory traffic (pair writes and reads of fast RAM, a Chip RAM
  write and read, a CIA read) after each switch, then a recalibration
  with the edge forced, and checks the register, that unkeyed or invalid
  writes are ignored, three clock switches, three SDRAM mode loads and
  that the aligner is locked and never slipped. `VLFLAGS=-DCAL_TEST`
  delays the simulated clock by half a 12x period plus 0.2 ns and
  jitters the 7 MHz edges by 0-0.4 ns: the calibration must then pick
  the rising edge at 12x and keep the falling one at 14x and 16x (a
  version that always keeps the falling edge fails it, with the aligner
  slipping). Its SDRAM model returns read data at the CAS
  latency of the last LOAD MODE, so a controller expecting another one
  reads wrong data, and it flags a LOAD MODE with any bank open.
  Found on the way: the ROM board decoded its control registers from
  address bits 15-12 only, so a `$5Axx` write to any address ending in
  `$F008` (in Chip RAM, say) could switch MapROM. Both registers are now
  qualified by the board's own window.
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

## 16x clock (board mod, optional)

From step 10 every release has `_x16` files as well as the normal ones.
They are for a Base64 whose clock multiplier has been rewired from x12 to
x16, and are overclocked (see below). On Glen's board a jumper on the
ICS570B's pin 6 (grounded or not) switches between x12 and x16; flash the
files that match the setting.

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

On Glen's A500+ with the ICS570B rewired to x16 (the `_fast` file), it
works, and a Ripple IDE's boot ROM now runs (its CF card mounts):

| | 12x, step 9 | 16x, step 9 bitstream (12x timing) | 16x, this build |
| --- | --- | --- | --- |
| SysInfo Dhrystones, caches on / off | 9221 / 4202 | 12311 / 5322 | 12311 / 5180 |
| AIBB MemTest, caches on / off | 12.20 / 6.97 MB/s | - | 15.81 / 8.88 MB/s |
| xSysInfo Dhrystones, caches on / off | 15075 / 7802 | 22117 / 10329 | 19429 / 9496 |
| xSysInfo fast RAM, caches on / off | 23.31 / 20.28 MB/s | 31.14 / 27.17 MB/s | 29.18 / 25.20 MB/s |
| SD card, SysInfo / xSysInfo | 2.18 / 1.9 MB/s | - / 2.6 MB/s | 2.18 / 2.1 MB/s |
| Ripple CF card, SysInfo (caches on / off) | ~2.8 MB/s | ROM not run | 3.13 / 2.93 MB/s |

Against the 12x build: SysInfo +34%, MemTest +30%, xSysInfo fast RAM
+25%. Against the 12x bitstream on the x16 board, this build gives up
about 7% on SDRAM-bound work (xSysInfo fast RAM and caches-off figures)
for CAS latency 3, and the SD card's xSysInfo figure falls from 2.6 to
2.1 MB/s with its clock back inside the SD limits. xSysInfo's caches-on
Dhrystones fell 12% (22117 to 19429) while SysInfo's are unchanged, which
CAS latency alone does not obviously explain.

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

The 12x and 16x builds come from the same source; `--x16` only changes
what is under `` `ifdef TG68_X16 ``. From step 11 on, a step's 16x file
is scored the same way as this one: step 11's needs 1.36× and runs on
Glen's board at x16.

## Building it yourself

1. Install **oss-cad-suite** from
   <https://github.com/YosysHQ/oss-cad-suite-build/releases> (the
   `windows-x64` installer is a self-extracting archive; unpack it to
   `C:\oss-cad-suite`).
2. From this folder:

   ```
   build.bat full
   build.bat full --seed 9  (start the seed search somewhere else)
   build.bat full --x16     (for a board rewired to x16, see 16x clock)
   ```

   On Linux/macOS: `python3 scripts/build.py full` with oss-cad-suite's
   `bin` on your PATH, or with the `yowasp-yosys` and
   `yowasp-nextpnr-ecp5` pip packages installed (`build.py` falls back to
   them when plain `yosys` / `nextpnr-ecp5` are missing). A build takes a
   few minutes per seed.
3. The bitstream lands in `build\full\base64_tg68_full.bit`
   (`build\full_x16\` for `--x16`). Step 11 `full` uses ~12k of the
   FPGA's 24k LUTs and 35 of its 56 block RAMs. Expect to try several
   seeds (`--seeds 16`): the timing margins are thin, and only a seed that
   passes `check_timing.py` outright should be used (step 11's seed 1
   missed by 0.5 ns and failed on hardware).

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

Step 14 (timing headroom, with step 13b's longer calibration) builds as
supplied (not yet on hardware):

| Build | Seed | Worst 1T slack | Worst multicycle slack |
| --- | --- | --- | --- |
| full | 8 | +0.43 ns | +2.53 ns |

Seeds 1, 4, 8 and 11 of 1-11 pass (step 13b: none of 40). At 14x the
build needs the chip 1.11× faster than the worst-case model, at 16x
1.27×.

Step 13 (run-time clock speed) builds as supplied (runs on hardware at
all three speeds):

| Build | Seed | Worst 1T slack | Worst multicycle slack |
| --- | --- | --- | --- |
| full | 12 | +0.24 ns | +0.45 ns |

Seed 12 was the first pass of seeds 1-12 on the final design; the others
missed by 0.1-4 ns, mostly on clkena -> kernel and on the SDRAM request
decode. Three earlier versions of the CAS latency change were
restructured on the way, not seed-hunted: its own state (a fifth state
bit lengthened the request decode), its own branch in IDLE (even last
in the chain it merged into the request branch's next-state logic), and
finally a ride on a refresh, which leaves IDLE as it was in step 12. The
speed hold was folded into a registered HALTn (a term of its own at
DECIDE missed by 0.4 ns). Kernel change 4 was tried again (seeds 1-4 of
the final design, and 1-2 of an earlier one) and did worse than without
it. The design is 51% LUTs (step 12: 48%); the paths that miss are as
deep as in step 12, only longer routed. The checker classes the speed
settings (spd and what is registered from it, clk_sel, the SDRAM read
timer's CAS latency) as config registers: they change only in a switch,
with the CPU held and 64+ clocks before anything uses them. Scored as
the 16x files are: at 14x the build needs the chip 1.14× faster than the
worst-case model, at 16x 1.30× (`timing_full_at14x.txt`,
`timing_full_at16x.txt`). The `_x16` file (board mod, fixed clock) is
seed 7, the best of seeds 1-8: 1.32× (step 12's: 1.35×). So on a board
with the clock chip back at x12, `speed 16` runs at least as close to
the model as the `_x16` file does on a modded one.

Step 12 (Chip RAM write buffer) builds as supplied (known good on
hardware, 12x and 16x):

| Build | Seed | Worst 1T slack | Worst multicycle slack |
| --- | --- | --- | --- |
| full | 6 | +0.25 ns | +0.06 ns |

Seed 6 was the only one of seeds 1-8 to pass; the others missed by
0.3-4.5 ns, most often on clkena -> kernel from `k_clkena_lw` (about 330
loads). A kernel change that splits those loads between two identical
registers (the ALU and the data-in and address processes on the second)
cut that class's misses from 1.2-3.8 ns to 0-1.5 ns over seeds 1-4, but
none of those four passed outright, so it is kept on the branch
`kernel-change4-clkena-split` for a later step that needs it.
The 16x file is seed 4 of seeds 1-4: it needs the chip 1.35× faster than
the worst-case model (step 11's 16x file: 1.36×) and runs on Glen's board.

Step 11 (games: Chip RAM code cached, posted Chip RAM writes, faster
uncached reads) builds as supplied (runs on hardware, 12x and 16x):

| Build | Seed | Worst 1T slack | Worst multicycle slack |
| --- | --- | --- | --- |
| full | 14 | +0.06 ns | +1.78 ns |

That is the build with the posted-write fix; seed 14 was the only one of
seeds 1-15 to pass, the others missing by 0.5-2 ns on a different class
each time. **A near miss is not good enough on hardware:** seed 1 of the
same design missed by 0.51 ns and failed on the A500+ at 12x (Kickstart
1.3 reached the boot screen, then a green screen; 3.2.3 a red one),
while seed 14 boots both. The 16x file is seed 1 of the fixed design
(1.36× the worst-case model; it runs on Glen's board). What follows is the
history of the first (broken) step 11 build:

It took four rounds of seeds 1-4. The first two failed in nextpnr's
packer: the posted-write logic read `rt_a`, a pin register with
`syn_useioff`, and a later attempt loaded `rt_a`/`rt_fc` on a different
clock from `rt_rw`, but pin registers sharing an I/O block need the same
enable and reset nets. The paths that missed and were new in step 11 were
then restructured, not seed-hunted: the SDRAM bank bits come straight from
the address (not after the slot decode), the prefetch buffer's data loads
without the SDRAM ack in its enable, the posted-write sequencer uses
`tick_rq` (the 7M rising tick as a register, asserted equal in the test
bench), and the adapter has its own copy of `k_clkena` (`k_step`), so
`k_clkena` drives only the kernel. With those, seed 1 passes; seeds 2-4
miss by 0.5-1.9 ns, the usual spread (see "how close to the edge" below).
The first build's 16x file (`--x16`, seed 1, best of seeds 1-8) needed
the chip 1.34× faster than the worst-case model.
The checker classes the new direct-read registers `k_din_dw`/`k_din_dsel`
as logic (1T): as read-data latches they would have had a 2T budget they
don't have.

Step 10 (instruction prefetch, instruction-stream pairs) builds as supplied
(known good on hardware, 12x and 16x):

| Build | Seed | Worst 1T slack | Worst multicycle slack |
| --- | --- | --- | --- |
| full | 14 | +0.31 ns | +0.50 ns |

Seed 14 was the only one of 16 to pass. Without the pair modes (prefetch
only) seeds 1-4 missed by 0.16-1.79 ns, the usual spread; with them
kernel -> logic missed by 1.3-2 ns on most seeds, because the core's pair
offer for an instruction word now depends on the low address bits, which
come from its address adder, and DECIDE waits for it. The 16x file
(`--x16`, seed 2) needs the chip 1.31× faster than the worst-case model
(see *16x clock*), less than the 1.36× of the 16x build that works on
Glen's board.

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
  TG68K*.vhd                    TG68K.C (m1nl's fork), three changes marked "Base64"
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
(<https://github.com/m1nl/TG68K.C>, commit `a8e6f38`), with three marked
changes (below): upstream
TG68K.C (our kernel was identical to its base) plus a cheaper rotate unit and
the 32-bit data path (`long_cand`/`long_ack`, `data_in_hi`,
`data_write_lo`). The wrapper `tg68_020.vhd` passes those ports through and
sets `DataPath32` with its `DP32` generic. Up to step 9 it was 1: longword
data reads only. The fork can also pair 32-bit immediates and absolute-long
address extensions (bits 1 and 2), but in step 7 either of those put the
kernel's clock-enable paths 2-5 ns over budget on every seed tried (they sit
in its program-counter and fetch logic). From step 10 it is 7, all three:
with `clkena_lw` registered (kernel change 2) the cost fell to ~1-2 ns on
kernel -> logic (see *Timing*). `DP32=1 scripts/gen_tg68.sh` regenerates
the data-only core.

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

3. (step 11) The CACR clear bits, CEI (bit 2) and CI (bit 3), are kept for
one `clkena` step after the MOVEC that sets them, then cleared (they still
read back as 0, as on a real 68020). The adapter flushes both caches when
it sees either, which is how Exec's CacheClearU reaches the caches now that
the instruction cache holds Chip RAM code.

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
