# History: how each step works and what it measured

This file holds what used to be the long middle of `CLAUDE.md`: the
step-by-step design notes, the hardware results and the ideas list, as
they stood when step 15 was built. It is NOT loaded automatically. Read
the part you need (grep for the step or the signal name) when a plan in
`plans/` points here or when you have to change something a step built.
Add to it when a step is finished: one bullet per step, in the same
style. `README.md` is the user-facing version of the same material.

## How the design works (short version; details are in README and comments)

- **Clocks:** one 85-86 MHz clock for everything. The TG68 kernel is
  clock-enabled. `tg68_bus.v` paces it: STEP=4 (kernel step period),
  SETTLE=3 (clocks before the adapter acts on kernel outputs), DIN=1,
  ADDR_SETUP=1, DATA_DELAY=2. The kernel->kernel path needs about 41 ns of
  the 46.5 ns allowed by STEP=4, so STEP=3 is out of reach.
- **Sequencer states (tg68_bus.v):** SETTLE -> DECIDE, then:
  - an internal step;
  - a predicted fetch (step 15), stepped at once like an internal step;
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
  - Cacheable: fast RAM and Kickstart $F80000-$FFFFFF; from step 11 the
    instruction cache also holds Chip RAM code. The data cache never holds
    Chip RAM.
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
- **Games (step 11, known good on hardware at 12x seed 14 and 16x seed 1; released as v1.4 with step 10):** Glen saw Frontier and Gloom
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
    The bug found on hardware: a write whose core DS appears on the AS
    tick (normal branch asserts AS that clock, rt_d_oe <= ~old rt_as_n =
    0) went out undriven, because the sequencer's AS step (which sets
    rt_d_oe) is skipped once AS is down. Fix: the post sets `rt_d_oe <=
    ~rt_as_n | tick_r`, and the rp_pend branch drives it whenever AS is
    down. tb_top: Gary wait-state jitter (not MEMBENCH), a data-drive
    check at every Chip RAM write latch, and phase sweeps at 0x81C4/0x81C8
    (the 81C8 one, fast RAM reads between writes, catches the old bug).
    Switches kept for bisecting: POST_CHIP, CHIP_IC, CACR_CLR, RD11,
    BANK_XOR (all 1).
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
- **Chip RAM write buffer (step 12, known good on hardware, 12x seed 6 and 16x seed 4; released as v1.5):** `CHIP_WB` (top
  level, default 8) entries {a, d, fc, uds/lds} in `wb_*` (storage always
  8 deep, 3-bit pointers; CHIP_WB only limits the fill). `postable` =
  POST_CHIP && core AS low && write && `core_chip_r` (registered
  core_a[23:21]==0) && !int_win_r: the normal AS-low branch is skipped for
  it (`else if (!postable)`), so a chip write never reaches the bus except
  through the buffer (the step 11 race cannot happen). `wb_acc` (DS down,
  !rt_dtack_lo, !wb_full) enqueues and acks, after the branch chain, in
  every state. `wb_busy` (rp_act || cnt) is the chain's first branch:
  the engine loads rt_a/rt_fc/rt_rw/rt_d from the head (one clock), then
  the step 11 sequence (AS tick_r, DS next tick_r, DTACK later tick_r,
  end tick_f, release tick_r: pop, rt_rw/rt_a/rt_fc reloaded from core).
  Any other motherboard cycle waits in that branch until the buffer is
  empty. BRn to the adapter is s_br_n | wb_busy. Sim (12x): wrmix 679
  (depth 1) / 625 (2) / 517 (4) / 445 us (8, the bus floor). Fast RAM
  write queue: measured, not built (copy never waits for the port;
  write bursts wait 3%). Tests: 0x81CC, 0x81D0, CIA order check
  (`ord_chk`), `wb_max`; mutations (no drain wait, rp stuck, accept when
  full, strobes swapped) all caught.
  Timing: 12x seed 6 is the only PASS of seeds 1-8 (+0.25 / +0.06 ns);
  most misses were clkena -> kernel from k_clkena_lw. Kernel change 4
  (branch `kernel-change4-clkena-split`, commit c882be7): port
  clkena_lw2_in, wrapper CLKLW=2, a (* keep *) k_clkena_lw2 copy for the
  ALU and the data-in/address processes; it cut that class's misses from
  -1.2..-3.8 to 0..-1.5 ns on seeds 1-4 but none passed, so it was
  reverted here. Bring it back when a step's seed search stalls on clkena.
- **Run-time clock speed (step 13, branch step13-pll-speed; runs on
  Glen's A500+ at 12x/14x/16x, switching from the CLI):** `clkgen.v`: 12x straight from pin L1, 14x (EHXPLLL 6/7/7)
  and 16x (9/12/6) from it, a fabric glitch-free mux (one enable per
  source, two flops on that source's negedge, on only when the others are
  off) into a DCCA. DCSC was tried (nextpnr places it) but its config
  text had two drivers on one DCS input: not trusted without hardware.
  TG68_X16 builds `clkgen #(.ENABLE(0))` (clk = pin).
  `spd` (0/1/2) drives registers that replaced the X16 ifdefs at run time:
  ph_top/ph_half (11/13/15, 6/7/8), ms_top, spd_hold2 (rt_ hold 2 clocks
  above 12x), spd_lox (SD SCLK low +1 at 16x, shifter `lo_extra`).
  sdram_ctrl (`TG68:`): cfg_req/cfg_cl3 -> PRECHARGE ALL, S_CFG_PRE, LOAD
  MODE, `cl3_now`, `cas_lat_r`; init LOAD MODE uses cl3_now (not reset, so
  the speed survives an Amiga reset; only a power cycle gives 12x).
  turbomem +$F00A (`TG68:`): write $5B0C/$5B0E/$5B10 (+$40 / +$80 force
  the 7M sample edge rising / falling), read {slip, jit_r, jit_f, rise,
  busy, sw_ok, lock16, lock14, mult}; the X16 build reads {slip, 0, 16}.
  Sequencer (top section 13): IDLE -> HOLD (spd_hold, folded into a
  registered `tg_halt_n` for the adapter's HALTn: a separate term at
  DECIDE failed 1T by 0.4 ns; wait 16 clocks of `sp_quiet` = cyc_idle,
  wb empty, both AS high) -> CL (to CL3 for 16x) -> SW (clk_sel, spd,
  spd_unlock; 64 clocks) -> LOCK (8 7M edges) -> CAL -> SETL (8 edges)
  -> CL2 (leaving 16x) -> IDLE. Any keyed write runs it (same speed =
  recalibrate).
  **The mux delays the clock** (~5.5-6.5 ns modelled at 12x; 14x/16x
  differ with the PLL CLKI/CLKFB routes; placement-dependent), which can
  put the falling-edge 7M sample on a transition. So 7M is sampled on
  both edges (`edge_7m_f`, `edge_7m_r`, same flop count: r sees an edge
  the same clock or one later) and a calibration (section 3) counts, per
  stream, edges whose free-running mod-N count `fr` differs from the
  previous one (16-bit, saturating); `smp_r <= jit_f > jit_r` (falling
  kept on a tie: closest to the old grid). Windows: power-up from
  pwrup_cnt bit PWRUP_BIT-1 to bits -1 and -2 (third quarter of the
  hold, ~0.33 s, decides 0.33 s before boot), switch CAL_EDGES = 65536
  (~9 ms; the sim uses 64). Hardware (first build, 2048-edge windows):
  12x cold boot $270C (falling kept, then moved; predicted ~0.5 ns from
  a transition), 14x $070E (clean), 16x $3710 (rising chosen, falling
  moving), `speed 12 rise` through a demo $370C (rising never moved, no
  slip). Hence step 13b's longer windows. Sim: `VLFLAGS=-DCAL_TEST` (clkgen transport delay 6.073 ns, tb
  7M jitter 0-0.4 ns) expects rising at 12x, falling at 14x/16x; a
  mutant that always keeps falling fails (aligner slips). Verilator: a
  delayed continuous assign is inertial and swallowed the 14x/16x
  pulses; use `always @(x) y <= #d x`.
  Aligner fix: the lock compare is `ph == PHASE_OFS - 1` (it compared
  with PHASE_OFS, never locked, re-acquired every edge); same grid,
  SLIP_TOL now works, ph_slip (red LED) cleared by each calibration.
  Also fixed: turbomem's ctrl_wr (MapROM) lacked tm_space (status_hit
  decodes A15:12 only). `sw/speed/`: SPEED 1.1 (68000 asm; `build.sh
  test` builds three vamos fake boards). Sim checks 81D4-81FC, n_switch
  3, n_mrs 3 (X16: $0010, 0, 1), ph_locked, !ph_slip, smp_r.
  check_timing: spd/ph_top/ph_half/ms_top/spd_hold2/spd_lox/clk_sel/
  cas_lat_r are config (4T, changed only in SW with 64+ clocks after);
  cl3_now stays 1T; fm_cfg_* inside g_fastmem.u_fastmem were missing
  from STATIC (a fake 1T fail).
  SDRAM CAS change, after two versions failed 1T on the request decode
  (its own state: 5-bit state; its own IDLE branch, even last): cfg_go
  raises refresh_due, the refresh (precharge-all) sets cfg_ref, REFRESH
  ends in S_INIT_MODE, which loads `cl3_nx` (= cfg_cl3 once init_done).
  IDLE is as in step 12. Timing: seed 12 of 12 passes (+0.24 / +0.45 ns);
  14x needs 1.14x, 16x 1.30x the worst-case model (step 12 x16: 1.35x);
  the --x16 file is seed 7 of 1-8, 1.32x (others 1.37-1.52x).
  LUTs 51% (step 12 48%); misses are step-12-depth paths routed longer.
  Kernel change 4 did worse here (seeds 1-4). Step 13b (longer
  calibration) missed logic -> logic by 1.2-2.1 ns on seeds 1, 5, 9, all
  pwrup_done -> ext_reset OR -> mr_act_d -> dc_wa, so it has two changes
  first tried (and set aside) on step 13: ext_reset registered (one clock
  more reset latency) and rt_hold_done as one register fed from one stage
  earlier (spd_hold2 ? core_as_d2 : core_as_n; the mux missed 0.45 ns into
  the address pins on a step 13 seed). Both touch the x16 build too.
  Then ext_reset (registered) -> mr_act_d -> dc_wa still missed on a
  seed: tg68_bus's flush_trig is now a register too (flush_ev the OR;
  one clock later is safe: every source is >= SETTLE clocks before the
  next DECIDE, fills are blocked during the sweep).
  Seed 12's clock paths (typ): 12x mux +5.3 ns (falling 7M sample ~0.5
  ns from a transition, so calibration should pick rising), 14x +13.4 ns
  (PLL14's CLKI route is 6.7 ns: pin L1 is next to PLL16 only), 16x +6.9.
  YoWASP cannot read files under /tmp: worktrees for parallel seed
  searches go under /home/user.
- **Timing headroom (step 14, branch step14-timing-headroom from 13b
  ca3b4d9; seed 8 build runs on Glen's A500+ at 12x/14x/16x, benchmarks
  as step 13):** 13b passed 0 of 40 seeds (32 main, 8
  with kernel change 4). Ranking the failing classes over those seeds
  showed kernel change 4 removed kernel -> logic / read-data latch
  failures and shrank clkena's, so it is in (cherry-picked c882be7). Then,
  all without adding a clock (identical bench clock counts):
  sdram_ctrl `pre_open/pre_hit/pre_ras` (row decision registered a clock
  early from saddr_r, stable a clock before req; row registers never
  change on an edge into IDLE; pre_ras may only lag), request branch
  before refresh in IDLE gated by `ref_blk` (registered refresh_due &&
  ref_urgent); tg68_bus `cc_want_k/cc_on_k/cc_sel_k` (CCMP compare inputs
  registered from k_addr beside ic_ok_d); top `tg_br_n` (adapter BRn =
  s_br_n | wb_busy, registered); calibration counters 8 bits. Sim-only
  checks `pre_bad` (sdram_ctrl) and `cc_bad` (tg68_bus) fail the benches;
  mutants pre_open=0 (269) and inverted select caught; cc_on_k without
  EI is equivalent (CCMP only via k_look). Not simulated: an external bus
  master (tb ties BR off). Result: seeds 1, 4, 8, 11 of 1-11 pass; seed 8
  +0.43 / +2.53 ns, 14x 1.11x, 16x 1.27x; --x16 seed 9 of 1-12, 1.30x. Remaining misses mostly clkena
  -> kernel (next free step: more clkena_lw copies). Not done (costs
  clocks): eab loaded a clock later (Chip RAM +1 clock).
  Hardware (seed 8): 12x cold boot $070C (falling chosen), later $270C
  (falling moved, rising still); 14x $070E then $470E (rising moved,
  unused); 16x $4710. So (commit 2a7db3f): at 12x `smp_r <= !(jit_r >
  jit_f)` (the mux delays the 12x clock ~T/2 on every seed, so falling
  sits by a 7M edge and drifts as the chip warms); 14x/16x unchanged.
  And `swap_req` (stream in use moved AUTO_N = 4 times, the other 0,
  not forced, pwrup_done, !cal_busy) starts the sequencer with `sp_swp`
  (sp_tgt = spd, no clock change): LOCK sends `swap_go` instead of
  cal_go (no window: a slow drift would pass one and pick the drifting
  stream again); the calibration block flips smp_r and clears the
  counts; `n_swap` at +$F00C (SPEED 1.2 prints it). Sim CAL_DRIFT
  (clkgen delay 0 -> 0.25 ns at 300 us, tb 7M jitter 0.05-0.45 ns): one
  swap, falling at every speed after; no-swap mutant fails; normal and
  CAL_TEST runs assert n_swap == 0. bench chip at 12x 442 -> 369 us with
  rising (the grid sits a clock later against s_dtack_n, so the tb
  Gary's DTACK is caught a 7M cycle sooner; CAL_TEST gives the same, so
  not a zero-delay artefact); data and bus checks pass. Ask Glen for
  xSysInfo Chip RAM at 12x with the rising vs falling sample.
  **Kernel change 4 was never in a build until 9934739**: yosys merged
  k_clkena_lw2 into k_clkena_lw ((* keep *) on a reg keeps the wire, not
  the flop; even setattr keep on the $dff cell did not stop opt_merge).
  Flops with different power-on values or polarity are not merged (tested
  on a toy design; a primitive TRELLIS_FF with (* keep *) also survives).
  So the copy is k_clkena_lw2_n (inverted, power-on 1). With that, seed 8
  of 5-8 passed (+0.14 ns 1T, 14x 1.14x, 16x 1.30x); the remaining clkena
  misses were all k_clkena_lw -> EA_data process -> ea_data (n9819_q),
  and copy 2 reached its loads through an inverter LUT (the kernel is
  synthesized with keep_hierarchy, so the inversion could not fold).
  Kernel change 5 (2b5a57b): ClkenaLW_Ext=3, ports clkena_lw2n_in (low
  active, inverted in the kernel) and clkena_lw3_in (EA_data/data_write
  process); adapter regs k_clkena_lw (0), k_clkena_lw2_n (1, inverted),
  k_clkena_lw3 (power-on 1: only that process, whose Reset branch wins;
  Reset is async-forced while nReset is low). Check a new copy really
  exists: grep the synthesized json for cpu.k_clkena_lw*_TRELLIS_FF_Q.
  Step 14b (2b5a57b + the capture fix, branch step14-timing-headroom,
  bitstreams/step14b_cal): 12x seeds 5 and 8 of 1-8 pass (seed 5 +0.36 /
  +3.28 ns, 14x 1.12x, 16x 1.28x); --x16 seed 3 of 1-4, 1.29x. Not yet
  on hardware.
- **Fetch predictor (step 15, branch step15-fetch-predictor; not yet on
  hardware):** a sequential instruction-cache hit in 4 clocks, not 5.
  `fp_a` = next fetch address, loaded on every DECIDE clock of a fetch
  (`dec_r && k_bs==00 && !k_skip`: k_addr + 1 word, + 2 for a pair
  candidate); `fp_rsel_n` (k_step inverted, own register) switches `ic_ra`
  to fp_a for the clock after a step; E2: `k_din_fp`, `fp_tq`,
  `k_din_psel`; E3: `fp_v` (tag match, no `fp_kill`); DECIDE: `fp_hit0`
  (fp_v, ic_on, fetch, k_addr == `fp_ac`, not a pair candidate) then
  `bus_free` -> step(). `fp_ac` = copy of fp_a for that compare only, a 2T
  source in check_timing (fp_v is cleared on the edge it loads; tb
  assertion; different power-on values keep yosys from merging the two).
  `fp_bad` (ic_we at fp_a's entry) sets fp_kill from the step to E3 and
  clears fp_v after. DECIDE's pf-hit and cycle-start branches clear
  k_din_psel (they may hand the kernel k_din). Nothing of the predictor
  loads in step() (it did: the CCMP-hit step missed 1T on every seed).
  Also: `cnt_ok` (cnt >= STEP-1 as a register), `k_ipl` loaded on k_step,
  `WR4` (posted non-pair write steps at DECIDE; works, +1%, off: puts
  k_fast in the step decision), `S15_DEFAULT` (VLFLAGS=-DS15_DEFAULT=0 =
  step 14 behaviour). Sim: `bench c` (sim/bench_c.c, gcc -O2 -m68020,
  needs gcc-m68k-linux-gnu) 73680 -> 65640 clocks (+12.2%; 62% of steps
  are fetches, 89% of single fetches sequential), copy +5.5%, read +8.5%,
  scatter +9%, wrfast +10%, readoff/chip 0. Tests: `fp_chk_bad`, shadow
  check and stability check on every predicted fetch, smc0-3 (0x8210-
  0x822C; same results with the predictor off); mutants caught except the
  fp_bad -> fp_v clear after E3 (unreachable in the benches). Timing:
  seed 8 of 1-9 passes (+0.60 / +0.40 ns, 14x 1.14x, 16x 1.31x); misses
  are kernel -> logic 0.9-1.7 ns on four seeds (k_addr feeds a second
  31-bit compare ahead of DECIDE's chain; next thing to restructure:
  split DECIDE into fetch and data branches so only fetches see fp_hit0),
  clkena -> kernel, cache RAM outputs. Tried: a carry-chain tag compare
  (x + all-ones carry out) is slower than `==` (5.6 vs 4.7 ns alone).
  Not done: prefetch-buffer hits in 4 clocks (caches off: 1.7% in bench
  coff), dp_req's register clock.
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
| step 11 (race fix, 12x seed 14) | 9690 / 5161 | 15.73 / 8.49 |
| step 11 at 16x (race fix, seed 1) | 12784 / 5992 | 19.97 / 10.39 |
| step 12 (write buffer, 12x seed 6) | 9690 / 5177 | 15.74 / 8.14 |
| step 12 at 16x (seed 4) | 12907 / 5992 | 19.97 / 10.39 |
| step 14 at 12x (seed 8, `speed`) | 9695 / 5205 | 15.74 / 8.31 |
| step 14 at 16x (seed 8, `speed 16`, no board mod) | 12929 / 6441 | 19.97 / 10.53 |
| step 15 at 12x (fetch predictor, seed 8) | 11179 / 5162 | 16.59 / 8.48 |
| step 15 at 16x (seed 8, `speed 16`) | 14925 / 6462 | 21.03 / 10.40 |
| step 15b at 12x (timing margin, seed 10) | 10797 / 4875 | 16.60 / 8.34 |
| step 15b at 16x (seed 10, `speed 16`) | 14412 / 5925 | 21.03 / 10.60 |
| exp-18x at 12x (seed 3) | 10798 / 5162 | 16.60 / 8.29 |
| exp-18x at 16x (seed 3) | 14376 / 5539 | 21.02 / 10.59 |
| exp-18x at 18x (seed 3, experiment) | 16225 / 6596 | 23.58 / 11.67 |
| exp-20x at 12x (seed 10) | 10776 / 4461 | 16.60 / 8.48 |
| exp-20x at 16x (seed 10) | 14379 / 5440 | 21.03 / 10.59 |
| exp-20x at 20x (seed 10, experiment) | 18024 / 7499 | 26.16 / 13.20 |

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
- Step 11 (first files): Kickstart 3.2.3 yellow screen, 1.3 reboot loop /
  green (chip RAM error), all four files; DiagROM fine. Bisect (12x): A
  (POST_CHIP=0) boots both; B, C fail. Cause: a posted write whose DS met
  the AS tick went out with the data bus undriven (rt_d_oe loaded from the
  old rt_as_n; the sequencer then skipped its own AS step). Sims never hit
  that phase; the fastmem fast-read sweep (81C8) reproduces it on the old
  code. Fixed (D). 16x D boots 1.3 and 3.2.3: SysInfo 12784 / 5992,
  AIBB 19.97 / 10.39 MB/s (+26% / +25% on step 10), xSysInfo 22042 /
  12023, fast RAM 29.19 / 26.21, SD 2.2 MB/s. 12x D (seed 1, -0.51 ns)
  reached further but failed at a real 12x clock (1.3 green after the
  white screen, 3.2.3 red); 12x seed 14 (the only timing PASS of seeds
  1-15, +0.06 / +1.78 ns) boots both. Lesson: a 0.5 ns miss can fail on
  hardware; ship only timing-PASS 12x builds. step11_games now holds 12x
  seed 14 and 16x seed 1 of the fixed design. 12x: SysInfo 9690 / 5161,
  AIBB 15.73 / 8.49 (+28% / +29%), xSysInfo 16245 / 8290, fast RAM 23.31 /
  21.15 MB/s.
  Games on 16x D (Glen): run a lot better, close to a 50 MHz 68030 but
  still a little behind.
- Step 12: benchmarks as step 11 (they run from fast RAM and the caches).
  12x xSysInfo 16330 / 9309 Dhrystones, fast RAM 23.33 / 21.15, SD 2.0
  MB/s; 16x xSysInfo 22042 / 11994, 29.18 / 26.20, SD 2.2. Games look
  faster, unmeasured; Glen may start a Frontier timedemo tool as a
  separate project (WHDLoad slave hook on the buffer swap + VBL count).
- Step 15 (fetch predictor, seed 8; includes step 14b): SysInfo caches
  on +15.3% (12x) / +15.4% (16x) on step 14, above the simulation's +12%
  for compiled C; AIBB MemTest +5.4% / +5.3%. xSysInfo 12x 16888 / 9353
  Dhrystones, 9.61 / 5.32 MIPS, fast RAM 23.69 / 21.15 MB/s; 16x 24471 /
  11615, 13.92 / 6.61 MIPS, 29.57 / 26.18; SD 2.0 / 2.2 MB/s. xSysInfo
  caches on +3.9% at 12x but +14.8% at 16x: noisy, as before. Caches off
  should not change (the predictor needs the cache; bench readoff gives
  identical clock counts) and does not at 16x (SysInfo 6462 vs 6441) or
  in xSysInfo at 12x (9353 vs 8698), but SysInfo 12x caches off read
  4800 against step 14's 5205; re-run after a reset: 5162 (-0.8%, within
  SysInfo's run-to-run spread). Caches off is unchanged, as expected. Frontier timedemo (Glen's tool, first
  numbers; caches on): 12x min 9.4 / max 70.7 / average 26.2 fps, 16x
  11.8 / 73.2 / 30.6 fps. `speed` at 12x: $170C (rising sample in use,
  nothing moved): step 14b's 12x fix works; at 16x after the tests $4710
  (falling in use, the unused rising sample moved), as with step 14.
- **v2.0 release** (14.11.2026): main gets steps 13 to 15b and the 20x
  clock; speeds 12x / 16x / 20x (Glen: 14x and 18x not a big enough
  step). The released bitstream is the `exp-20x` seed 10 file Glen
  tested (hours at 20x, stable); the release source rebuilds it byte
  for byte (only comments changed). `speed` 1.4 (12 / 16 / 20). The
  upstream files outside `tg68/` were removed; the old branches stay on
  GitHub.
- 20x experiment (branch `exp-20x`, seed 10, never a release; 20x in
  place of 14x): **runs on Glen's A500+ at 12x, 16x and 20x**, 1.54x the
  worst-case model at 20x. 20x over 16x: SysInfo +25.3% (18024 / 7499,
  18.81 MIPS), AIBB +24.4% (26.16 / 13.20), xSysInfo +18.9% (29009 /
  14486, 16.51 / 8.24 MIPS), fast RAM 36.85 / 32.73 MB/s, SD 2.7 MB/s,
  Frontier timedemo 13.9 / 75.6 / 33.8 fps (+8.7%). SDRAM tRFC + 2
  clocks at 20x. Details and the PLL options for a release
  (16x + 20x share a VCO of 567.5 MHz): plans/exp20x.md.
- 18x experiment (branch `exp-18x`, seed 3, never a release; 18x in
  place of 14x): **runs on Glen's A500+** at 1.42x the worst-case model
  (16x on that build: 1.26x). 18x over 16x: SysInfo +12.9% caches on,
  AIBB +12.2%, xSysInfo +10.8% (27033 / 13918, 15.38 / 7.92 MIPS, fast
  RAM 33.23 / 29.51 MB/s), SD 2.5 MB/s, Frontier timedemo 12.9 / 74.9 /
  32.4 fps (+5.9% average: Chip RAM bound). Only design change beyond
  the clock: SDRAM tRFC + 1 clock at 18x. Details: plans/exp18x.md.
- Step 15b (seed 10: step 15 with the pair test out of the predicted
  fetch and DECIDE split; runs at 12x and 16x): SysInfo caches on 10797 /
  14412 (12x / 16x), 3.4% below step 15 at both speeds, where the sim's
  compiled C lost 0.4%; caches off 4875 / 5925 (-5.6% / -8.3%, but with
  the caches off the 15b changes are idle and the sim is clock-for-clock
  identical, so that is SysInfo's spread, which step 15 itself showed:
  4800 then 5162). AIBB 16.60 / 21.03 (on), 8.34 / 10.60 (off): as step 15.
  xSysInfo 12x 18430 / 9240, 10.48 / 5.25 MIPS, 23.69 / 21.13 MB/s; 16x
  24129 / 11638, 13.73 / 6.62 MIPS, 29.60 / 26.25 MB/s. Frontier
  timedemo 12x 9.4 / 70.3 / 26.1 fps, 16x 11.8 / 73.4 / 30.6 (step 15:
  26.2 / 30.6). SD 2.0 / 2.2 MB/s. `speed` at 12x: no sample moved, at
  boot or later; 16x: the unused rising sample moved, as before. Open:
  whether the SysInfo -3.4% is change A's cost (a predicted fetch is now
  one word, so a sequential 32-bit immediate or abs.L address costs 8
  clocks, not 5; SysInfo's Dhrystone may use many more of those than
  bench c's 75 in 9247 fetches) or spread; a back-to-back run of 15 and
  15b, and the real Dhrystone 2.1 in the sim, would tell.
- Step 14 (seed 8, the switchable build): xSysInfo 12x 16247 / 8698
  Dhrystones, 9.24 / 4.95 MIPS, fast RAM 23.32 / 21.12 MB/s, SD 2.0 MB/s;
  16x (`speed 16`) 21317 / 11621, 12.13 / 6.61 MIPS, 29.17 / 26.18, SD
  2.2. Same as steps 12-13 at the same clock (step 14 changed margins
  only); 16x via the PLL matches the x16 board mod.
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

- Chip RAM write buffer: step 12 (above). Run-time 12x/14x/16x: step 13.
- 18x (Glen's request, after step 14 is tested; experimental, never a
  release): a PLL's outputs all divide one VCO (400-800 MHz), so 16x+18x
  cannot share one (1021 MHz). Plan: PLL A 14x+16x from VCO 794.5 MHz
  (CLKI_DIV 6, CLKFB_DIV 7, CLKOP_DIV 8 = 99.3, CLKOS_DIV 7 = 113.5),
  PLL B 18x (VCO 766, /6 = 127.7); 4-input mux; run-time settings for 18x
  (ph_top 17, ph_half 9, ms_top, rt_ hold, SD SCLK stretch); SDRAM CL3 is
  in spec (tRFC 8 clocks = 62.6 ns >= 60, tRAS 6 = 47 ns >= 42). Timing:
  ~1.43x the worst-case model (16x: 1.27x); likely +8-10% over 16x if the
  chip copes. 20x: ~1.59x, kernel step would need STEP=5 (no gain).
- Fast RAM write queue: measured in step 12 and left out pending Glen's
  decision (the copy bench never waits for the SDRAM port; write bursts
  wait 3%, so it can gain a few percent at most).
- 16x/14x without the board mod, switchable at run time: done in step 13
  (above). As built: 12x is the pin (no PLL), each of 14x and 16x has its
  own PLL, and the switch is a fabric mux, not DCSC.
- SDRAM: 24 of 32 MB mapped (8 MB Z2, 16 MB at $08000000, 1 MB MapROM);
  7 MB spare. Little software would use more.
- Bigger caches: 16 more block RAMs, which would crowd out RTG.
- RTG framebuffer in SDRAM: Glen no longer sees it as a runner.
- USB (Glen's idea, future add-on): the module's USB-C goes to the iCELink
  MCU, not the FPGA; the FPGA only has its UART (TX B9, RX A9) to the
  iCELink's USB serial port. So that socket can give the Amiga a fast
  serial link to a PC (needs an FPGA UART slave and an Amiga driver), not
  USB peripherals. A USB host needs extra hardware: a host chip that
  existing Amiga USB stacks (Poseidon) drive, on spare carrier pins, or a
  soft USB 1.1 host in the FPGA plus a new driver. Mind the module's
  unprotected USB 5 V (README).
- WiFi via an ESP (Glen's idea): an ESP32-S2/S3 (USB host capable) could
  talk to the iCELink's USB serial port, but that depends on the iCELink
  firmware's UART speed and VBUS behaviour (unknown) and the unprotected
  5 V. Cleaner: an ESP on FPGA pins (no spare header on the carrier: J2
  is CFGIN/CFGOUT; needs a mod or revision). Either way the Amiga needs a
  serial.device-compatible driver for an FPGA UART with a FIFO, and the
  ESP needs PPP/SLIP-to-WiFi firmware. Works today with no gateware: an
  ESP WiFi modem on the Amiga's own serial port (~115-230 kbit/s).
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
- 16x clock: merged into main with step 11 (README "16x clock"); releases
  have `_x16` files from step 10 on. Glen switches his board between x12
  and x16 with a jumper on the ICS570B's pin 6. History:
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
- Tried and dropped (branch `exp-kernel-clock-buffer`, never on hardware):
  the kernel on its own global clock buffer (a second DCCA on the speed
  mux's output, `FREQUENCY NET "clk_k" 21.5 MHz`), so nextpnr sees the
  kernel's real 4-clock budget. nextpnr then relaxed kernel -> kernel
  (40 -> 41-43 ns) but the pass rate did not move: 3 of 9 seeds (step 14b:
  2 of 8), same spread of misses. It does not optimise paths between the
  two clock nets at all (kernel -> logic, clkena -> kernel), and the
  buffers' skew (0.27-0.87 ns by seed, kernel early) comes off clkena ->
  kernel. `--tmg-ripup`: 1 of 4. `--placer heap`: cannot route the mux to
  the second DCC. Also measured: nextpnr's target frequency has no effect
  on this flow (clk at 12 (the default since step 13: the lpf constrains
  the pin, not the mux output), 24 or 86 MHz: byte-identical routed
  designs on seeds 1, 2, 5, 8).
- Timing headroom: from step 7 on only ~1 seed in 8 passes every class,
  with a different path missing each time (README "Timing"). A new
  feature will likely need a seed search. A real fix would need fewer
  levels on the adapter's 1T paths, or a lower clock.

## Gotchas (the full list as it stood at step 15; the short list is in CLAUDE.md)

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

