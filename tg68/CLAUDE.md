# CLAUDE.md: TG68 (68020) build for the Base64 accelerator

Briefing for Claude Code. Read this first, then `README.md`, which is the
user-facing documentation and holds the details. This folder (`tg68/`) is a
self-contained alternative gateware for jbilander's Base64 Amiga 500
accelerator. It replaces the cycle-exact fx68k 68000 with TobiFlex's TG68K.C
in 68020 mode and keeps the fx68k build's fast RAM, SD card, autoconfig and
MapROM.

## Owner and hardware

- Glen: electrical engineer, Amiga hobbyist, works on **Windows**. He tests
  everything on real hardware and reports SysInfo/AIBB numbers. Nothing
  counts as done until he has run it.
- Target: Base64 Rev C carrier, iCESugar-Pro (Lattice **LFE5U-25F-6BG256C**),
  in an **A500+** (Kickstart 2.04, 3.1, 3.2 and DiagROM all usable).
- Bitstreams are loaded by copying the `.bit` file onto the iCELink USB drive.
  An incomplete copy can boot to lit LEDs but not run. If a bitstream that
  should work does nothing, flash it again first.

## Layout

```
rtl/base64_tg68/   top level (base64_tg68_top.sv) and the bus adapter tg68_bus.v
rtl/tg68/          TG68K.C VHDL: m1nl's fork (github.com/m1nl/TG68K.C, a8e6f38,
                   32-bit data path) with TWO marked changes (l1 <= long_ack;
                   clkena_lw from the clkena_lw_in port, see README), + the
                   tg68_020.vhd wrapper;
                   tg68_020_b0.v is the GHDL-converted netlist actually built
                   (regenerate: YOSYS=yowasp-yosys sh scripts/gen_tg68.sh, needs
                   Ubuntu's ghdl 4.1.0; reproduces the netlist byte for byte)
rtl/base64_fx68k/  copies of the fx68k build's slaves; every change is
                   marked "TG68:" (fastmem_zii: direct SDRAM port and BUS_RAM;
                   all slaves: *_int_win outputs)
scripts/           build.py (yosys -> nextpnr -> ecppack, seed search),
                   check_timing.py (the real timing sign-off), helpers
constraints/       pin constraints (nextpnr .lpf generated from the Diamond one)
diamond/           fallback Lattice Diamond project constraints (never used
                   on hardware; keep in step but treat as secondary)
sim/               Verilator test benches; see sim/README.md
sw/maprom/         maprom command (68000 asm) + hunk wrapper
bitstreams/        release outputs, NOT in git; they go on GitHub Releases
```

Upstream (jbilander's files outside `tg68/`) is not modified by this work.

## Commands

```
python3 scripts/build.py full --seeds 12      # Windows: build.bat full (only full is released/timed since step 6)
sh sim/run.sh bus | top | fastmem              # the three regression benches
sh sim/run.sh bench copy|read|scatter|sd       # throughput and SD loopback
python3 scripts/check_timing.py build/full/base64_tg68.sdf --paths 4
sh sw/maprom/build.sh                           # needs binutils-m68k-linux-gnu
```

Toolchain: yowasp-yosys 0.70 and yowasp-nextpnr-ecp5 0.11 (pip), ecppack
from Ubuntu's fpga-trellis, Verilator 5.020, binutils-m68k-linux-gnu, or
oss-cad-suite on Windows (build.bat). `scripts/setup_cloud.sh` installs the
exact versions; with them, `build.py full --seed 3 --seeds 1` reproduces
the released step 4 `full` bitstream bit for bit. `build.py` uses
`yowasp-yosys` / `yowasp-nextpnr-ecp5` by itself when plain `yosys` /
`nextpnr-ecp5` are not on PATH, so no `YOSYS` / `NEXTPNR` variables are
needed (they still override). Synthesis uses `synth_ecp5 -abc9`,
keep_hierarchy on the TG68 modules then flatten, and deletes `$scopeinfo`
cells. nextpnr runs with `--placer static --router router2`.

**ecppack must stay plain by default.** `--spimode dual-spi --freq 62` made
bitstreams that never loaded on this module. `--compress --freq 38.8` works;
that gives the "_fast" files.

## Rules for every change

1. **All three sims pass** (`bus`, `top`, `fastmem`), plus `bench sd` if the
   bus or the slaves were touched. Add a test for any new behaviour; the
   benches check results at fixed addresses (`check(...)` in tb_top.sv).
2. **check_timing.py says PASS.** nextpnr's own FAIL is expected and
   meaningless: it times every path as 1 clock at 86 MHz, but the kernel is
   multicycle. The checker classifies start/end registers and gives each
   pair its real budget (table in README "Timing"). **When you add a
   register, decide its class.** A register named after a port it drives, or
   one changed rarely (config), can be misclassified. Fix the classifier with
   a reason in a comment rather than accepting a fake pass. The checker has
   caught real bugs this way.
3. **Fix structure, don't seed-hunt.** If a path fails by more than about 0.5 ns
   on several seeds, restructure it. Patterns that worked:
   - Register a decode one clock early when its inputs are known to be
     stable (int_win_r, ic_on_r).
   - Load data registers unconditionally and put the conditions only on the
     write enable or the valid bit (cache write ports, k_din at CCMP/LATCH).
   - Move work one clock later from latched registers (pw_upd).
4. **Keep the previous known-good step.** Each step ships in its own
   bitstreams/stepN folder with timing reports. Glen falls back to the last
   step he has confirmed if a new one misbehaves.
5. Changes to rtl/base64_fx68k files are marked `TG68:` with the reason.
6. Update README.md (status, table, feature text, timing table) along with
   the code.
7. **Keep both clocks working (Glen's decision after the 16x test).** The
   16x build needs a board mod (ICS570B rewired to x16), so every change
   must work in both the 12x and 16x (`TG68_X16`) builds. Run the sims at
   both (`VLFLAGS=-DTG68_X16` for 16x), sign off 12x with check_timing as
   usual, score the 16x build at 113.6 MHz (worst delay/budget ratio; it
   cannot pass the worst-case model), and give Glen test bitstreams for
   both. Anything clock-dependent goes under `ifdef TG68_X16`.

## Working in Claude Code

- **Tools:** if `verilator` or `yowasp-yosys` is missing, run
  `sudo bash tg68/scripts/setup_cloud.sh` (or `bash` as root) before
  anything else.
- **One change per branch and pull request.** Name branches after the
  change, for example `step5-two-word-cache`. Each PR says what changed, the
  sim results, the timing-check result (worst slack per class that moved),
  and what Glen should test on the Amiga.
- **Getting test bitstreams to Glen:** he flashes them from GitHub. Commit
  them to the PR branch under `tg68/bitstreams/stepN_name/` with
  `git add -f` (the folder is gitignored), together with timing.txt. Use
  both `_plain` and `_fast` (`ecppack --compress --freq 38.8`) and
  `full` + `min`. Glen downloads them from the branch on GitHub. PRs are
  squash-merged, and the bitstream commit is dropped before merging, so no
  binaries land in `main`. Released bitstreams go on GitHub Releases, which
  Glen creates by hand.
- **Commit author:** Glen Milford <casualretrogamer@outlook.com>, and end
  commit messages with the Co-Authored-By line for Claude.
- **No force-pushes to `main`**, and no rewriting history that is already
  on GitHub, unless Glen asks for it.
- Glen tests on hardware and reports back. Don't mark anything done, or
  update the results table, until he has.

## How the design works (short version; details are in README and comments)

- **Clocks:** one 85-86 MHz clock for everything. The TG68 kernel is
  clock-enabled. `tg68_bus.v` paces it: STEP=4 (kernel step period),
  SETTLE=3 (clocks before the adapter acts on kernel outputs), DIN=1,
  ADDR_SETUP=1, DATA_DELAY=2. The kernel->kernel path needs about 41 ns of
  the 46.5 ns allowed by STEP=4, so STEP=3 is out of reach.
- **Sequencer states (tg68_bus.v):** SETTLE -> DECIDE, then:
  - an internal step;
  - a prefetch-buffer hit -> FINISH;
  - a cache lookup -> CCMP (hit steps the kernel there; miss -> DWAIT,
    CFREE or SETUP);
  - a posted write -> FINISH;
  - a direct read -> DWAIT -> DDATA;
  - an old-route Amiga-bus cycle SETUP -> WAIT -> LATCH -> FINISH.
- **Old route:** the 68000-style AS/DS/DTACK bus to the motherboard and the
  on-FPGA slaves (autoconfig, SD, ROM board). The strobes are registered
  copies (as_i -> ASn).
- **Direct path (step 3):** fast RAM (the Zorro II window and $08000000) and
  MapROM go straight to the SDRAM controller through the dp_* port.
  - fastmem_zii is built with BUS_RAM=0, so its AS-driven RAM slave is gone.
  - The SDRAM word address `saddr_r` is formed from the kernel's early
    address and frozen by `dp_hold` while a request is in flight.
  - Writes are posted.
  - Each read prefetches the next word (pf_*, never across a 1 KB boundary).
- **Caches (steps 2 and 4):** two 8 KB direct-mapped caches, one 16-bit word
  per entry, in block RAM.
  - Cacheable: fast RAM and Kickstart $F80000-$FFFFFF. Never Chip RAM.
  - Both share one lookup pipeline: the RAMs read the kernel's address on
    the edge into DECIDE, DECIDE loads the word into k_din_c and the tag
    into ic_qt, CCMP compares (EARLY LOOKUP, step 6).
  - Write-through. The data cache allocates on whole-word writes to fast RAM
    and drops the entry otherwise. The instruction cache drops the entry on
    any write.
  - The CPU is the only writer of fast RAM (the SD controller is CPU-driven,
    no DMA), so no software cache management is needed.
  - Both flush on reset and when MapROM changes state.
- **Early lookup (step 6, known good on hardware):** the kernel's
  address is final ~21 ns after its registers move (the cache index bits
  ~15 ns), well inside 2 clocks, while busstate and FC need nearly 3. So the
  cache RAMs read on the edge INTO DECIDE; DECIDE loads `k_din_c` (the
  word, its own register: the RAM output through k_din's wide mux failed
  timing by ~2 ns on every seed) and ic_qt from the RAM outputs, and sets
  `k_din_sel` so the kernel's data input (`k_dat`) takes k_din_c; CCMP
  compares (`cc_hit`) and a hit calls step() right there. A miss clears
  k_din_sel; so does the end of the clkena clock. Hit: 5 clocks (was 7). check_timing.py class
  "kernel -> cache RAM" gets SETTLE-1 = 2T. CCMP uses `ic_ok_d` (window
  decode of k_addr registered at DECIDE), not `ic_ok`: `icache_win` lags
  a_r by a clock and is stale in CCMP (breaking that collapses D-cache hits
  in the fastmem bench). `icache_win_k` lets a test bench supply its own
  window (the top ties it to 0). The step 5 pair buffers gained nothing
  after this (also 5 clocks) and were removed. tb_top.sv and
  tb_tg68_bus.sv check every cache hit's data against a shadow of the
  CPU's writes.
- **32-bit data path (step 7, known good on hardware):** core = m1nl's
  TG68K.C fork, `DP32=1` (data pairs only: immediate and absolute-address
  pairs made clkena -> kernel fail every seed by 2-5 ns); `k_long_cand`
  offers an aligned pair. Each cache is two banks
  (`*_e` even words, `*_o` odd words, row = addr[12:2]); DECIDE registers both
  banks' words (`k_din_ce/k_din_co`) and tags (`ic_qt_e/o`). `k_long_ack` is
  set at DECIDE (pair offered, aligned) and resolved in CCMP: both words hit
  (`cc_long`) -> step with the pair (data_in_hi = k_din_ce, data_in =
  k_din_co); only the asked word hits -> drop k_long_ack and step via FINISH
  (so the drop is 2 clocks old); miss -> drop. It never changes in the clock
  before the kernel samples (tb assertion), so check_timing.py classes it
  adapter -> kernel. `DP32_ACK=0` turns pairs off. Pairs only from cache hits
  so far; writes stay 16-bit. Kernel change: `l1 <= long_ack` (was AND cand;
  clkena -> kernel failed 11/12 seeds with it); valid only while the adapter
  acks offered pairs only (tb asserts long_ack implies long_cand). DECIDE's
  data registers (oEdb, uds/lds_want, cyc_fetch, dp_we/wdata/be) load on every
  DECIDE clock under `dec_r` (= q is DECIDE, tb-asserted); `cyc_start` marks a
  real cycle start for the tb write shadow. Timing margins are thin (seed 4:
  +0.06 ns 1T, +0.86 ns kernel -> logic).
- **32-bit SDRAM writes (step 8, known good on hardware):** `DP32_WR=1`.
  `k_wpair` = pair offered, aligned, both strobes. Only `k_long_ack` is
  set in the posted-write branch (fast RAM only). `dp_pair` (= k_wpair) and
  `dp_wdata_lo` (the kernel's `data_write_lo`) load under `dec_r` with the
  other port data; sdram_ctrl (`TG68:`) latches `cur_pair = pair && we`,
  so reads ignore dp_pair. S_WR2: a second WRITE at col|1 the clock after
  the first (tCCD=1, same open row). Cache: pw_upd writes the even word,
  then pw_upd2 (<= dp_pair, held while the port is busy) the odd word a
  clock later. The prefetch drop compares k_addr[31:2] (either word).
  First version set dp_pair/pw_pair inside the DECIDE branches: kernel ->
  logic failed by ~1-2 ns on most seeds (decode fan-out); moving them out
  fixed that class. clkena -> kernel then failed 11/12 seeds on an
  identical kernel netlist, and with DP32_WR=0 too: the path was fragile.
  Kernel change 2 fixed it: `k_clkena_lw` (set with k_clkena to
  `!k_longword || k_long_ack`) drives the kernel's clkena_lw (~320 loads)
  through `clkena_lw_in` (wrapper generic CLKLW=1, kernel generic
  ClkenaLW_Ext). Both tbs assert it equals the kernel's own formula every
  clock. check_timing's CLKENA pattern includes `clkena_lw` (yosys could
  name the register after the port). Seed 3: +0.37 ns 1T, +1.70 ns
  multicycle; seeds 1, 2, 4 miss by 0.1-0.8 ns. Tests: tb shadow records both words
  (`wr_pairs`), fastmem FAILs on `wr_pairs < 4` or any SDRAM model
  violation (`u_sdram.n_err`), directed tests at 0x819C/0x81A0/0x81A4;
  mutations (2nd column, no pw_upd2, masked 2nd write) all caught.
- **32-bit SDRAM reads (step 9, known good on hardware):** `DP32_RD=1`.
  `k_rpair`/`k_dpair` (dp_pair now carries read or write pairs; sdram_ctrl
  latches `cur_pair = pair` for both). Controller: rd2_pend/rd2_left set
  at request acceptance; second READ at col|1 in the first S_RD_WAIT
  clock; S_RD_DONE held one more clock, so ack_early/rdata_live give word
  1 then word 2. Adapter: `rp_go` (aligned pair read in fast RAM,
  registered at DECIDE); a CCMP miss sets `k_long_ack <= rp_go`; dp_pair
  loads in CCMP/CFREE when the port is free; direct (caches-off) reads set
  `k_long_ack <= k_rpair` at DECIDE. DWAIT: word 1 -> dp_q, no dp_inc.
  DDATA: k_din <= word 1, dp_q <= dp_rdata (word 2), pf_a/pf_dc set, no
  prefetch request, -> Q_DDATA2 (code 7). DDATA2: `k_din_lo <= dp_q`,
  `k_din_hsel <= 1` (switches data_in to k_din_lo and data_in_hi to
  k_din; cleared after the step), pf_fill <= pf_dc (fills word 2: pf_a is
  2 clocks old by then, its 2T class). `q` has no initial value so yosys
  recodes it one-hot. Tests: miss pairs checked against the shadow
  (`rd_pairs` >= 4), a pair hit at 0x08004F00 required (`hit_4f00`),
  checks at 0x81A8/0x81AC/0x81B0; mutations (2nd column, S_RD_DONE not
  held, select off, wrong word, no fill) all caught. Timing: seed 7
  +0.36 / +1.16 ns; ~1 seed in 8 passes, as step 8 (README "Timing").
- **Instruction prefetch and instruction-stream pairs (step 10, known good
  on hardware, 12x and 16x):** after an instruction read the DDATA prefetch runs for
  fetches too (`pf_ic` = the buffered word is an instruction word: pf_fill
  then writes the instruction cache, `pf_dc` holds its fill conditions);
  k_pf_hit takes fetches (`!k_bs[0]`). Core regenerated with DP32=7
  (wrapper and gen_tg68.sh default 7; `DP32=1` for data only): 32-bit
  immediates and abs.L addresses as pairs. The adapter needed nothing for
  them: the cache-hit pair logic and step 9's pair read are kind-agnostic,
  and the prefetch change gave the fetch pair's second word its icache
  fill. Tests: `ipair_hit`/`ipair_rd` counters (fn32 in test_top.s gives 2
  of each), `bench readoff` (caches off). Gains in sim are small (readoff
  +7%); hardware will tell for Dhrystone-type code. Timing: 1 seed in 16
  passed (seed 14: +0.31 / +0.50 ns); kernel -> logic is 1.3-2 ns worse
  with DP32=7 (long_cand now waits for addr[1:0]). Possible follow-up: a
  separate instruction prefetch buffer that chains (each hit issues the
  next prefetch), since a data read in between replaces the shared buffer.
- **Games (step 11, not yet on hardware):** Glen saw Frontier and Gloom
  run the same with caches on and off. Frontier's executable has a 157 KB
  CODE hunk with the CHIP flag: its code runs from Chip RAM, ~60 clocks
  per instruction word, never cached. Changes:
  - The icache also holds Chip RAM code (`ic_chip`, `ic_okf` = window for
    the LATCH fill/invalidate; `ic_ok_d` includes addr[31:21]==0). DMA
    writes are invisible, so CACR CI/CEI now flush both caches
    (`flush_trig`). Kernel change 3: CACR bits 2-3 stay set for one
    clkena step after the MOVEC (`elsif clkena_in='1' then CACR(3 downto
    2) <= "00"`), so the adapter sees them; they read back 0. Same
    behaviour as a real 68020 (A1200): old trackloaders that DMA code and
    jump without CacheClearU need caches off. Data cache: still no chip.
  - Posted Chip RAM writes in the top level's RETIME bridge (`POST_CHIP`,
    `rp_pend/rp_ds/rp_term/rp_hold`): a chip RAM write ($000000-$1FFFFF
    only, never custom/CIA registers: interrupt-clear ordering) gets
    `rt_dtack_lo` at once and the bridge runs AS/DS/DTACK on the 7M grid
    itself; the next core cycle waits; BRn is held off while posting.
    `rt_chip` is its own register loaded with rt_a (rt_a is syn_useioff:
    reading it inside the FPGA failed packing). The sequencer uses
    `tick_rq`, tick_r as a register (tb-asserted equal), so the pin
    registers' enables skip the phase compare (failed 1T by 0.5 ns).
    Pin registers in one I/O block must share CE/LSR nets: loading rt_a/
    rt_fc a clock later than rt_rw (tried) failed packing. The bridge's
    clear of the stale ack is backed up by the adapter's `ack_idle` (a
    mutant without it passes). `k_step` (keep) is the adapter's copy of
    k_clkena, so k_clkena drives only the kernel (tb-asserted equal).
  - SDRAM bank = word bits [10:9] ^ [12:11] ^ [14:13] (fastmem_zii.v,
    `TG68:`): code and data 4-32 KB apart no longer share a bank.
  - Pair prefetch: an aligned 16-bit fast RAM read miss is a pair read
    (`rp_al`), word 2 -> prefetch buffer (`pf_fill_d`), no second request.
  - Shorter direct read: `k_din_dw`/`k_din_dsel` (word straight from
    dp_rdata at DWAIT), DDATA steps the kernel itself. check_timing class
    'O' (1T) for those endpoints (KDW rule), not 'D'.
  - Tests: chip code run twice (`chip_ihit` >= 2), CPU patch, "DMA" patch
    via the tb mailbox at $8F10 then CACR CI (0x81B4/B8/BC), posted write
    order at 0x81C0, `n_posted` >= 10, `bench chip`. Sim: bench chip 1133
    -> 442 us, readoff +40%, copy +17%, read/scatter unchanged.
- **Cache enable:** both caches follow CACR EI. The data cache must NOT get
  the 68030 CACR bit 8: software tells an 020 from an 030 by setting that bit
  and reading it back, so storing it would make the CPU detect as a 68030 and
  invite MMU code. SysInfo's DCache switch therefore does nothing; that is
  intended.
- **Speculative read and overlap (step 4):**
  - A fast-RAM data read is sent to the SDRAM at DECIDE alongside the
    lookup. On a hit it becomes dp_kind 2 and its data is dropped. This
    relies on the SDRAM never answering in under 3 clocks; the `fastmem`
    bench checks that.
  - Cache lookups may start while a posted write or prefetch is still in
    flight. A miss then waits in CFREE.
- **Bridge:** the "is this cycle internal?" decision uses int_win_r, which
  is the slaves' address windows without the AS term, registered.

## Gotchas already paid for

- **yosys turns a constant `1'bz` on an inout into a constant-0 driver.** The
  SD card's MISO was driven low in every build up to the step 4 rebuild.
  Inputs on inout pins are now ECP5 `BB` buffers with T=1 under `ifdef
  YOSYS`: the SD card's DAT0-2, and `sdram_dq` when there is no fast RAM
  (the `min` build). build.py refuses a netlist with inout bits tied to
  constants. The one allowed exception is `sd_cmd[0]=0` and `sd_d[3]=1` in
  a config without the SD block (real outputs, idle on purpose). A new
  inout that is constant in some config needs a `BB` or an entry in
  `tied_ok` in build.py, with a reason. Verilator honours `1'bz`, so sims
  cannot catch this.
- `syn_useioff` can't go on registers that are also read internally
  (rt_as_n, rt_vma_n): packing fails.
- `pkill -f build.py` from a shell whose command line contains "build.py"
  kills that shell. Kill by PID.
- The original `maprom.c` was never compile-tested. `sw/maprom/maprom.s` is
  an assembly port tested only under amitools' `vamos` with a fake board.
  The board's boot ROM (turbomem.mem, DIAG_MAPROM=1) already enables MapROM
  at every boot.
- Verilator `$display(cond ? "A" : "B")` prints a number. Use if/else.

## Licensing (unresolved; check before publishing anything new)

- TG68K.C: LGPL-3.0 (Tobias Gubener).
- SD controller files (sdcard.v and related): GPL-2.0-only (Niklas Ekström).
- base64_gateware has no top-level licence; ask jbilander.
- Base64 hardware repo: CC BY-SA 4.0.
- GPL-2.0-only together with LGPL-3.0 in one bitstream may be incompatible.
- No licence has been chosen for Glen's own additions yet.

## Results so far (A500+, Kickstart 3.x)

| Build | SysInfo Dhrystones (caches on / off) | AIBB MemTest MB/s (on / off) |
| --- | --- | --- |
| v3 pacing | 2783 | - |
| step 2 (I-cache) | 4833 / 3208 | 4.38 / 3.91 |
| step 3 (direct path) | - | 6.46 / 5.71 |
| step 4 (D-cache) | 6076 / 4007 | 7.28 / 5.71 |
| step 5 (pair buffers, `full`) | 6720 / 3717 | 7.46 / 5.71 |
| step 6 (early lookup, `full`) | 8144 / 3813 | 7.65 / 5.71 |
| step 7 (32-bit data path, `full`) | 8728 / 3940 | 7.65 / 5.71 |
| step 8 (32-bit SDRAM writes, `full`) | 9226 / 3982 | 10.93 / 6.15 |
| step 9 (32-bit SDRAM reads, `full`) | 9221 / 4202 | 12.20 / 6.97 |
| step 10 (instruction prefetch + pairs, `full`) | 9691 / 4918 | 12.28 / 6.60 |
| step 10 at 16x (board mod) | 12936 / 5982 | 15.91 / 8.28 |

- AIBB MemTest did not move from step 6 to step 7 (pairs only come from
  cache hits; MemTest's reads miss and its writes are 16-bit). Step 8's
  pair writes took it to 10.93 MB/s (+43%), and to 6.15 with the caches
  off (pair writes work without them). Step 9's pair reads on a miss:
  12.20 / 6.97 (+12% / +13%). The write queue is what would move it next.
- Step 10: caches-off Dhrystones +17% (12x) / +15% (16x), cached +5%;
  caches-off MemTest -5% / -7% (likely unused instruction prefetches
  holding the SDRAM ahead of data reads). xSysInfo 12x caches on / off
  15363 / 7536, fast RAM 23.35 / 21.01; 16x 21233 / 10318, 29.19 / 25.98.
  SD works on both (2.2 MB/s xSysInfo, 16x, caches on).
- SD card (sfsd.device 2.4): 2.18 MB/s in SysInfo on steps 4 to 9
  (2184533 bytes/s each time); fx68k gets 1.76 MB/s.
- xSysInfo (Glen's test suite from step 8): 15711 Dhrystones, 8.94 MIPS,
  fast RAM 16.38 MB/s, Chip RAM 2.39 MB/s, ROM 16.38 MB/s (= fast RAM, so
  MapROM is active), SD card 1.9 MB/s. Its Dhrystone figure is on a
  different scale from SysInfo's; compare xSysInfo with xSysInfo only.
  Step 9, caches on / off: 15075 / 7802 Dhrystones, 8.57 / 4.44 MIPS,
  fast RAM 23.31 / 20.28 MB/s. The caches-on Dhrystones are 4% below step
  8's 15711 while SysInfo's are unchanged; unexplained. Candidate: the
  speculative read at DECIDE is now a pair read, so one dropped on a hit
  keeps the SDRAM a clock longer and a following posted write or miss
  waits. Re-run xSysInfo on steps 8 and 9 back to back to see if it is
  real before changing anything.
- Step 5 caches-off Dhrystones (3717) are below step 4's (4007), but the
  caches-off logic is unchanged: identical clock counts for both in the
  read and copy benches with CACR=0. Step 6's caches-off run gave 3813,
  though nothing step 6 changed is active with the caches off: SysInfo
  varies by a few percent between runs. Probably different test conditions;
  re-run steps 4 to 6 back to back on the same setup to settle it.
- SysInfo reports "66 MHz" by timing loops. AIBB: close to a 25 MHz 68030.

## Ideas not yet done (Glen decides the order)

- A 2-4 entry write queue (copies are write-bound).
- Bigger caches: 16 more block RAMs, which would crowd out RTG.
- RTG framebuffer in SDRAM: discussed as a future add-on, no design yet.
- References for speed-ups and tweaks (reviewed during step 11):
  - Emu68 (68k JIT for PiStorm), https://github.com/michalsc/Emu68: the
    one usable tip is software, the VBR (vector table) in fast RAM.
  - The Amiga Bootcamp guide, https://arisamiga.github.io/amiga-bootcamp/
    (fetched in full, 254 pages): a general AmigaOS developer reference,
    unreliable in detail. Its 68030 CACR table is wrong, and it says
    CacheClearU is a no-op on a 68020; Exec's 020/030 version sets CACR
    CI|CD ($0808), which step 11's chip code flush relies on (as far as
    known without a ROM to disassemble: hardware will tell). Nothing in it
    for the gateware. It prompted a check of posted chip writes against
    68000 timing (AS S2, DS S4, end S7, next AS S2): the bridge matches;
    the 6-clock period in `bench chip` is the tb Gary's late DTACK.
- Not pursued (Glen's decision): faking a 68EC030 (only CachePreDMA/
  PostDMA change; MMU probes would trap), and watching BLTSIZE/DSKLEN
  writes to flush code the blitter or disk DMA overwrites. Stale cached
  chip code after DMA is the same risk as on an A1200, and Glen has never
  met it in practice.
- Possible small idea: cache code fetches from A500 trapdoor slow RAM
  ($C00000-$D7FFFF; no DMA reaches it). Instruction cache only: with no
  RAM fitted that range mirrors the custom chips, and the data cache's
  write allocate would fool Kickstart's memory probe.
- 16x clock: branch `exp-16x-clock` (not merged; README "16x clock").
  Glen's board is rewired x16 (113.5 MHz); a 12x bitstream there runs the
  bridge's 7M grid at 9.46 MHz (CLK_MULT fixed at 12: bus cycles short,
  E/CIA 33% fast, a Ripple IDE's ROM not run). `build.py full --x16`
  defines TG68_X16: CLK_MULT 16, CPU_MULT 8, MS_TOP, 2-clock rt_ hold
  after AS, SDRAM CL3 (other counts already in spec: controller overhead),
  SD SCLK low half +1 clock (shifter LO_EXTRA). PHASE_OFS stays 2 (3 broke
  the sim: Gary missed AS negations). Sims: `VLFLAGS=-DTG68_X16`. Not
  timing-signed: build.py checks at 113.6 MHz and does not fail on it;
  score seeds by the worst delay/budget ratio (the 12x step 9 seed 7 that
  ran on Glen's x16 board needs 1.28x). The 12x build on this branch is
  logically identical to main but not bit-identical (yosys numbering moves
  even for ifdef'd-out text), so 12x releases come from main.
  Hardware (exp16x_seed9 `_fast`, Glen's x16 board): works; the Ripple
  IDE's ROM now runs (CF 3.13 / 2.93 MB/s caches on / off). SysInfo
  12311 / 5180 Dhrystones, AIBB MemTest 15.81 / 8.88 MB/s, xSysInfo
  19429 / 9496 Dhrystones, fast RAM 29.18 / 25.20 MB/s, SD 2.18 MB/s
  (SysInfo) / 2.1 (xSysInfo). Vs the 12x bitstream on the same board:
  ~7% less on SDRAM-bound work (CL3), xSysInfo caches-on Dhrystones -12%
  (22117 -> 19429) with SysInfo unchanged: not explained yet. CL2 at
  113.5 MHz is in spec only if the SDRAM is a -6 (or faster) part:
  check the chip marking before trying it. Glen's chip is an
  IS42S16160J-6BLI: ISSI's key timing table (Rev. C3) gives -6 a 10 ns
  minimum tCK at CL2 (100 MHz), so CL3 stays at 16x.
  Hardware: E clock 709379 Hz, a real floppy reads fine. Glen is
  stress-testing it on the bench.
- Timing headroom: from step 7 on only ~1 seed in 8 passes every class,
  with a different path missing each time (README "Timing"). A new
  feature will likely need a seed search. A real fix would need fewer
  levels on the adapter's 1T paths, or a lower clock.
