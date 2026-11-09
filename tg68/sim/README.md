# Test benches

`run.sh bus | top | fastmem` (Linux: verilator 5, binutils-m68k-linux-gnu).

* **bus**: `tg68_bus` + TG68K on a model asynchronous 68000 bus with random
  DTACK latency (2-25 clocks). `test020.s` checks MULU.L, DIVU.L, BFEXTU,
  EXTB.L, byte lanes, a misaligned MOVE.L, TRAP/RTE, MOVEC VBR, an
  autovectored interrupt and a BR/BG/BGACK hand-over mid-run, plus protocol
  checks (address stable through AS).
* **top**: the whole `base64_tg68_top` (bridge, 7M grid, cold reset, hi_null)
  on a crude motherboard: Gary-style DTACK, VPA for CIA space and IACK, ROM,
  Chip RAM. `test_top.s` adds a CIA read through the VPA/E cycle and a read
  of `$FF000000` that must come back `$FFFF` without reaching the
  motherboard.
* **fastmem**: as top with `ENABLE_FASTMEM=1` and the fx68k build's
  timing-checked SDRAM model. Writes and reads `$08000000` and `$08FFFFFC`,
  runs code copied into fast RAM, and checks the direct path's prefetch
  buffer, MapROM, and the data cache: hits, word and byte writes, two
  addresses on one cache slot, writes made with the caches off, ROM data,
  and a two-pass sum. It also checks the SDRAM never answers a direct
  request in under 3 clocks, which the speculative read relies on.
  Four cases land a write on a word right after a cache hit on its
  neighbour (a word write, a byte write, a write with the caches off) or
  switch MapROM with a shadow word cached. Beyond those, every cache hit in
  every test (benches included) is checked against a shadow copy of what
  the CPU wrote, byte lane by byte lane, and the run fails on any
  difference: the early lookup (step 6) hands the CPU the word before the
  tag compare, so this is the check that matters. `bus` runs the same check
  under random DTACK and the bus hand-over. (Checked against deliberately
  broken versions: DECIDE not loading the word is caught by both benches;
  a compare using the late `icache_win` collapses the data-cache hits.)
  Step 7 (32-bit data path): a routine in fast RAM with an aligned 32-bit
  immediate and an absolute-long address runs twice, the second time as
  pairs from the caches; and a longword whose second word was dropped from
  the cache must not be taken as a pair. The oracle checks both words of
  every pair, that `long_ack` is set exactly for pair hits, and that
  `long_ack`/`k_din_sel` never change in the clock before the CPU samples
  them. (Checked against broken versions: a pair hit ignoring the second
  word's tag, the wrong word on `data_in_hi`, stepping with `long_ack`
  still set, and dropping it a clock too late: all caught.)
  Step 8 (32-bit SDRAM writes): the shadow records both words of a pair
  write; the run fails if fewer than 4 pair writes happen or if the SDRAM
  model reports any timing violation (in every `top`-based run, benches
  included). Three cases: a pair written, evicted and read back from the
  SDRAM; a misaligned longword (no pair); a pair written over two cached
  words. Both benches also check on every clock that the registered
  `k_clkena_lw` equals the kernel's own `clkena_lw` formula (kernel change
  2). (Checked against broken versions: the second WRITE to the wrong
  column, the second word's byte enables off, no cache update for the
  second word, and `k_clkena_lw` ignoring `long_ack`: all caught.)
  Step 9 (32-bit SDRAM reads): every pair read from the SDRAM is checked
  word by word against the shadow at the CPU's sample clock; the run fails
  on fewer than 4 pair reads, or if the re-read at 0x08004F00 is not a
  pair hit (the pair read must fill both cache words). Directed: a pair
  read on a miss, the same pair from the cache, and with the caches off.
  (Checked against broken versions: the second READ to the wrong column,
  `S_RD_DONE` not held, the data-input select never set, the second word
  replaced by the first, and no fill of the second word: all caught.)
  Step 11 (games): `top` copies a routine to Chip RAM at $9800 and runs
  it twice; the second run must hit the instruction cache (`chip_ihit`
  >= 2, check at 0x81B4). The CPU then patches it (the new code must run,
  0x81B8); then the test bench rewrites the word behind the CPU's back, as
  DMA would (mailbox at $8F10): the cached old code must still run, and
  the new code after `MOVEC CACR` with CI set (0x81BC). Posted Chip RAM
  writes: a run of byte, word and longword writes to one place must land
  in program order (0x81C0), and at least 10 writes must be posted
  (`n_posted`). (Checked against broken versions: no chip fill, no
  invalidate on a CPU write, no flush on CI, a posted write's byte lanes
  swapped: all caught.)
* **bench chip**: a loop in Chip RAM writes 1 KB to fast RAM, timed on the
  second pass (Chip RAM code from the instruction cache).
* **bench copy | read | scatter | sd**: fast RAM throughput, timed on a second
  pass with the loop running from the instruction cache. `copy` copies
  1 KB, `read` sums 1 KB sequentially, `scatter` reads four longs in
  different SDRAM rows round and round.
* **bench readoff**: the `read` loop with the caches off, so every
  instruction fetch and data read goes to the SDRAM (step 10's instruction
  prefetch). The fastmem bench also counts step 10's instruction-stream
  pairs (from the cache and from SDRAM; `fn32` makes two of each).
* **bench sd**: the SD controller with MOSI looped back to MISO: register
  read-back, 16 bytes shifted out and back in, and a single byte. (The
  simulator honours `1'bz`, so the pin bug fixed in step 4b could not show
  here; `build.py` now checks the netlist for it instead.)

Each ends with `PASS` or a list of what failed.

`VLFLAGS=-DTG68_X16 sh sim/run.sh top` (or `fastmem`, `bench ...`) runs the
same tests on the 16x build (branch `exp-16x-clock`): 113.5 MHz, clk_7m =
/16, the RTL's TG68_X16 settings and the SDRAM model at CL3. The model
checks the SDRAM timings in ns, so it covers the 16x clock too.
