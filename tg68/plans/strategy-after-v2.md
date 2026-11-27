# Strategy after v2.0: where the remaining speed is, and the steps to get it

Written by the planning model on 16 November 2026, for the build model.
`main` is v2.0 (12x / 16x / 20x, fetch predictor). This document says
what was measured, what is worth doing, in what order, and gives each
step in enough detail to build. Steps marked **ready** can be built from
this document. Steps marked **needs a plan** must not be built until the
planner has written `plans/<step>.md` (the section here says what that
plan has to settle).

Rules as always (`CLAUDE.md`): one step per branch from `main` (branches
stack while Glen's hardware test is pending), all three sims pass, 12x
passes `check_timing.py`, a test for every new behaviour and a mutant
that the test catches, results in the step's log section **in this
file** (each step below has one), stop and report instead of
improvising.

## 1. What was measured for this document

Tools added on branch `strategy-post-v2` (in the sim only, no RTL
change):

- **`sh sim/run.sh bench op`**: the cost of single instructions, in
  clocks and kernel steps, from fast RAM with the caches on
  (`sim/gen_op.py` writes the program and the table). Add a line to its
  list `T` to measure another instruction.
- **False-eviction counters** in `sim/tb_top.sv` (every `bench` prints
  the line "instruction cache (whole run): ..."): valid instruction-cache
  entries dropped by a write, how many of those held another address,
  and how many were then fetched again.

### 1.1 Cost per instruction (12x, caches on, v2.0)

A kernel step is 4 clocks (5 for a cache lookup or a posted write).
Selected rows of `bench op`; the last column is the same bench with the
kernel's barrel shifter switched on (section 3, step 19).

| instruction | clocks | steps | barrel on |
| --- | --- | --- | --- |
| nop, move.l Dn,Dn, add.l, cmp.l, moveq, ext.l, mulu.w | 4 | 1 | same |
| lsl.l #1,d1 | 4 | 1 | 4 |
| lsl.l #2,d1 | 8 | 2 | 4 |
| lsr.w #4,d1 | 16 | 4 | 4 |
| lsl.l #8,d1, asr.l #8, rol.l #8 | 32 | 8 | 4 |
| lsl.l d3,d1 (count 17) | 72 | 18 | 4 |
| mulu.l / muls.l | 8 | 2 | same |
| divu.w / divs.w | 72 | 18 | same |
| divu.l / divs.l | 144 | 36 | same |
| btst #n,d1 | 8 | 2 | same |
| bfextu d6{4:8},d1 | 12 | 3 | same |
| move.l (a0),d1 | 9 | 2 | same |
| move.l 4(a0),d1 | 13 | 3 | same |
| move.l (a0,d3.w*4),d1 | 17 | 4 | same |
| move.l $abs.l,d1 | 17 | 4 | same |
| move.l #imm32,d1 | 12 | 3 | same |
| move.l d1,(a0) | 9.3 | 2 | same |
| clr.l (a0), addq.l #1,(a0), move.l (a0),4(a0) | 18 | 4 | same |
| lea 4(a0),a1 | 12 | 3 | same |
| push + pop a long | about 25 | 4 | same |
| movem.l 15 registers out and back | 197 | 38 | same |
| beq.s not taken | 4 | 1 | same |
| a taken branch (bra.s, bne.s, dbra) | 13 | 3 | same |
| bsr.s + rts | about 27 | 6 | same |
| jsr (a2) + rts | 32 | 7 | same |

What the table says:

1. **Every shift costs one kernel step per bit.** The kernel is built
   with `BarrelShifter => 0`. TG68K.C has a barrel shifter; it only needs
   switching on. With it every shift and rotate is one step. `bench c`
   (compiled C): 65,892 -> 64,932 clocks (-1.5%); code that shifts by
   more than one bit (fixed-point 3D maths, multiply by a constant) gains
   far more. A trial build is in section 3, step 19.
2. **A 32-bit immediate or absolute address costs 12 clocks of fetch**
   (three single-word fetches) since step 15b took pairs out of the
   predicted fetch; with a pair it would be 9. AmigaOS programs that are
   not base-relative use absolute addresses for every global and every
   call. This is the likely cause of step 15b's -3.4% in SysInfo.
3. **A taken branch is 3 steps** (the branch, a wasted fetch of the next
   word, the target), and the target fetch is the unpredicted kind
   (5 clocks). Calls and returns are 6 to 7 steps.
4. **Divide is 1 bit per step** (18 steps for 16 bits, 36 for 32).
5. **Anything with a memory destination has a fourth step**, and `clr`
   reads before it writes (as a 68000 does).
6. **Back-to-back longword writes wait for the SDRAM port**: movem moves a
   long in about 6.5 clocks, not 5; push + pop is 25 clocks for steps
   that add up to 18.

### 1.2 The instruction cache loses code to unrelated writes

`tg68_bus.v`, the posted-write update (`pw_upd`, `pw_upd2`) and the old
route's `Q_LATCH`: **every CPU write to fast RAM, the MapROM area or Chip
RAM drops the instruction-cache entry at its index, whatever address that
entry holds** (`ic_wt <= 0`, or valid = `eRWn`). It was built that way so
that the write path needs no tag compare. The effect:

- The cache is direct-mapped, 8 KB. A write to address X drops the cached
  code at every address that equals X modulo 8 KB.
- `bench op` hit this three times by accident before its stack and data
  were moved: 73 valid entries dropped, all of them other addresses,
  38 fetched again. A `bsr` whose return address is pushed at an index
  that holds the code after the `bsr` misses on every call.
- A program that fills or clears 8 KB or more of memory (a screen
  bitplane is 8,000 to 10,240 bytes) empties the whole instruction cache.
  For code in Chip RAM (Frontier: a 157 KB CODE hunk in Chip RAM,
  `docs/HISTORY.md` step 11) every lost word comes back over the 7 MHz
  bus at about 50 clocks at 12x and 80 at 20x, against 4.
- Where a program's stack and data land is different on every run, so
  this also adds run-to-run spread to the benchmarks (SysInfo's spread is
  up to 8%).

`bench c` does not show it (its code, data and stack do not collide: 7
such drops), but `bench copy` (51 dropped, 21 fetched again) and
`bench wrfast` (39, 29) do. The size of the effect on real programs is not known; it
could be nothing on Dhrystone and well over 10% on a game that draws
with the CPU. It is the first step below because the fix is small and
cannot make anything slower.

### 1.3 Where the clocks go (`bench c`, v2.0, 12x)

65,892 clocks, 15,040 kernel steps: fetches 9,322 (8,307 predicted in 4
clocks, 986 unpredicted in 5, no pairs), data reads 2,009 (1,534 single
cache hits in 5 clocks, 411 pairs), writes 1,513 (1,030 single in 5, 420
pairs), internal steps 2,196 (4 clocks; 228 of them are shift steps).
Fast RAM writes wait 340 clocks for the SDRAM port (0.5%).

### 1.4 What limits the design now

- **4 clocks per kernel step.** The kernel's own paths are 41.7 to 43.4
  ns in the timing model against 46.5 ns (4 clocks at 12x). At 20x the
  same paths run in 28.2 ns on Glen's board.
- **The 68000 bus.** `bench chip`: about 4.1 7 MHz clocks per Chip RAM
  cycle. That is the bus's own minimum. Chip RAM work only gets faster by
  avoiding cycles (caching code) or by letting the CPU run on while
  writes drain (the write buffer).
- **Placement noise.** 4 of 18 seeds pass at 12x for v2.0. Steps that add
  logic need 16 seeds, sometimes more.
- **Real margin.** v2.0 runs at 20x for hours at 1.54x the worst-case
  model.

## 2. Not worth doing (so that nobody works it out again)

- **STEP = 3** (a kernel step every 3 clocks). At 12x that is 35.2 ns,
  the kernel stress of 16x; at 16x it is 26.4 ns, just past 20x's
  28.2 ns. So it could give at most about 5% over 20x, and it changes
  every multicycle class in the adapter (SETTLE, the early cache read,
  the predictor). The clock is the cheaper way to spend the same margin.
- **More timing-margin restructuring** for its own sake (step 16: 0 seeds
  passed). Restructure only what a new step breaks.
- **14x and 18x** (Glen's decision), a second kernel clock buffer,
  nextpnr's target frequency, a carry-chain tag compare (all measured,
  `CLAUDE.md` gotchas).
- **A shorter Chip RAM bus cycle, or Chip RAM in the data cache** (DMA and
  the blitter write it; the bus cycle is at the 68000 minimum).
- **24x** (170 MHz): past the SDRAM's 166 MHz rating.

## 3. The steps, in order

| # | step | gain expected | risk | status |
| --- | --- | --- | --- | --- |
| 17 | instruction cache: a write drops only its own entry | unknown: 0 to 10%+, games most; steadier benchmarks | low | **ready** |
| 18 | `perf`: counters in a test build, read from the Amiga | no speed; decides 20 and section 4 | low | **ready** |
| 19 | barrel shifter | 1.5% compiled C, much more on shift-heavy code | medium: timing (trial: 0 of 16 seeds) | **ready** |
| 20 | 16 KB caches | depends on 18's numbers (Frontier: possibly large) | medium, timing | **ready after 18's numbers** |
| X22 | experiment: 22x in place of 16x | +10% CPU-bound if the board runs it | may not run; SDRAM read window | **ready**, Glen's call |
| 21+ | section 4, ordered by 18's numbers | 0.5 to 4% each | varies | **needs a plan** each |

Build 17, 18 and 19 one after another without waiting (stacked
branches, a test bitstream each; 19 may fail on timing, see its
fallback). Glen tests each; 20 waits for 18's
numbers from his machine. X22 can be built at any point Glen asks for
it; build it on top of the newest step he has passed.

For every step: the numbers that must not move, unless the step says
so, are section 5's baseline table (clocks of each bench at 12x).

---

### Step 17: the instruction cache drops an entry only when its tag matches

Branch `step17-icache-tag-drop`, from `main`. **Ready.**

**Goal.** A CPU write to address X drops the instruction-cache entry at
X's index only if that entry holds X. Code at other addresses with the
same index stays cached. Coherency is unchanged: a write to cached code
still drops it (self-modifying code, LoadSeg).

**Background** (`rtl/base64_tg68/tg68_bus.v`).

- The cache RAMs are read every clock from `ic_ra` (the kernel's address;
  the predicted address in the clock after a step, `fp_rsel_n`). Outputs:
  `ic_tq_e`, `ic_tq_o` (tags, both banks). The read that counts is on
  the edge into DECIDE.
- `ic_qt_e/o` (registered every clock) hold the **data** cache's tags
  for a data cycle (`(k_bs == 2'b00) ? ic_tq_e : dc_tq_e`), so they
  cannot be used here.
- Drops happen in three places: `pw_upd` (first word of a posted write,
  one clock after DECIDE), `pw_upd2` (second word of a pair, one clock
  later), and `Q_LATCH` on the old route (`ic_wt[TAGW-1] <= eRWn`, under
  `ic_okf && !ic_flush && !eRWn`).
- `ic_want` is the tag of `a_r` (stable from DECIDE on); `tag_of()` gives
  the tag of any address.
- `fp_bad` kills a prediction when `ic_we` hits the predicted address;
  keep that as it is.

**The change, in order.**

1. Two new registers `iw_t_e`, `iw_t_o` (`TAGW` bits each), loaded from
   `ic_tq_e`, `ic_tq_o` on every clock in which `q == Q_DECIDE` and held
   otherwise, exactly as `k_din_ce/co` are (the last DECIDE clock is the
   one that counts; no other enable in the RAM -> register path).
   `ic_ra` should be the kernel's address throughout DECIDE
   (`fp_rsel_n` is low only in the clock after a step): confirm it in
   the code and with a test bench assertion (in every DECIDE clock of a
   write cycle, `ic_ra == k_addr[IC_AW:2]`).
2. A sticky register `iw_dirty`: set in any clock with `ic_we` high,
   cleared in the clock `iw_t_e/o` load (set wins if both happen). It
   says "the instruction cache was written since the tags were looked
   up", in which case the looked-up tags prove nothing.
3. `iw_keep_e = iw_t_e[TAGW-1] && (iw_t_e[TAGW-2:0] != ic_want[TAGW-2:0])
   && !iw_dirty`, and the same for `_o`. In words: the entry is valid,
   it holds another address, and nothing has been written since. Only
   then is the drop skipped.
4. In `pw_upd`: `ic_we <= !keep` for the bank `a_r[1]` selects. In
   `pw_upd2` (always the odd bank): `ic_we <= !iw_keep_o`. Note that
   the first word's drop sets `iw_dirty` in the clock `pw_upd2` is
   handled: make `iw_dirty` not count the write's own first-word drop
   (for example compute `keep2` in the `pw_upd` clock and carry it in a
   register), and say in a comment why that is safe (the two words are
   different entries).
5. In `Q_LATCH`: the write half of the `ic_we` condition gets
   `&& !keep` for the bank `a_r[1]` selects. An old-route cycle is many
   clocks long and a prefetch fill can land during it; `iw_dirty` covers
   that.
6. Timing class: `iw_t_*` are "cache RAM -> register" like `ic_qt_*`;
   the compare ends in `ic_we` (adapter control -> logic, 1T) and is
   **not** in `step()`. Add them to `check_timing.py`'s classifier if
   they do not fall into the right class by name, with a comment.

**Why it is safe (write this argument into the code comment).** The drop
is skipped only when the entry at the write's index was read as valid
with a different tag and no cache write happened between that read and
the decision. So at the decision the entry holds another address, and a
write to X cannot make it stale. In every other case the drop happens as
today.

**Tests.**

- Existing: the shadow checks (`hit_bad`, `fp_chk_bad`, "stale 0") and
  the self-modifying code tests in `test_top.s` (smc0 to smc3) must pass
  unchanged. They are the proof that true matches still drop.
- New, in `test_top.s` (fastmem): code at `$08007000`-style address A is
  run (cached), then a write to A + 8 KB and to the same index in Chip
  RAM; assert in the test bench that the entry for A is still valid
  afterwards and that running A again is a cache hit (no new fill).
  Then write A itself and assert the entry is gone and the new code
  runs.
- New: a pair write (aligned `move.l`) where only the second word's
  index holds cached code of another address; and one where the second
  word **is** cached code (must drop).
- `bench op`: "held another address" was 73 with 38 refills; after the
  step the count of entries actually dropped that held another address
  must be 0 unless `iw_dirty` forced it. Change the test bench counter
  to count real drops (it already looks at `ic_we`).
- Mutants: (a) `keep` always 1: the smc tests and the shadow check must
  fail; (b) the compare ignores the two region bits: a new test (write
  Chip RAM `$004100`, code cached at `$08004100`... and the reverse)
  must show the difference; (c) `iw_dirty` stuck at 0: write a directed
  test in which a prefetch fill of the written address lands between
  the lookup and the drop. If no such sequence can be produced in the
  sim, say so in the log and explain from the code why not.

**Numbers that must not move.** Section 5's table, except that `copy`,
`wrfast`, `read` and `scatter` (which do drop other addresses' entries)
may get a little faster; record the new values. `bench op`'s rows are unchanged (its
data no longer collide with its code).

**Acceptance.** Sims and benches pass; a 12x seed passes
`check_timing.py`; the new registers exist in the synthesized json;
Glen's test: SysInfo, AIBB, xSysInfo at 12x / 16x / 20x, the Frontier
timedemo at all three, a game with self-modifying or trackloaded code
(the ones he used for step 11), a few SysInfo runs in a row to see the
spread.

**Fallbacks.** If the compare misses timing: register `keep` one clock
earlier (compare in the last DECIDE clock against `cc_want_k`, which is
the same tag from `k_addr`) or one clock later (the drop one clock
later; the next lookup is at least SETTLE clocks after DECIDE, check
`fp_bad` still covers the predictor). If the old-route half is awkward,
ship the posted-write half alone and say so: Chip RAM writes are then
still index drops.

**Stop and report if** any existing coherency test fails in a way that
is not a plain bug in the new code; or the predictor's read
(`fp_rsel_n`) turns out to share a DECIDE clock of a write cycle.

**Log.**

- Built on branch `step17-icache-tag-drop` (from `main` at 59ff2a7).
- **One addition to the plan: Chip RAM mirrors.** The motherboard repeats
  Chip RAM through $000000-$1FFFFF (an A500+'s 1 MB shows twice, 512 KB
  four times), so `$104100` and `$004100` can be the same word. The index
  drop covered that by accident (every mirror distance is a multiple of
  8 KB); a plain tag compare would keep stale code. So for a write in the
  Chip RAM window, tags that differ only in address bits 19-20 count as
  the same address (`iw_msk`, `IW_MIR`) and the drop happens. Strictly
  more conservative than the plan; no other cacheable window repeats.
  Flagged for the planner, since it is a coherency point the plan did not
  mention.
- RTL (`tg68_bus.v`, IC KEEP comment): `iw_t_e/o` loaded under `dec_r`
  from `ic_tq_e/o`; `iw_dirty` loads `ic_we || iw_we_d` in DECIDE (the
  RAMs read before they write, so a write landing on the read's edge is
  not in the tags) and is set by any later `ic_we`; `iw_keep` also needs
  `!ic_we` (a write landing before the drop would) and `!pf_fill`;
  `iw_k2` carries the odd bank's keep from `pw_upd` to `pw_upd2`, where
  only an odd-bank write in that clock (`ic_we && ic_wa[0]`) can still
  spoil it. Address and tag loads stay unconditional, the keep is only
  on `ic_we`. Switch `ICKEEP` (`-DS17_DEFAULT=0` = v2.0). All new
  registers class as adapter ctrl (1T) by name: no classifier change.
  All exist in the synthesized json (`iw_t_e/o` 14 bits each,
  `iw_dirty`, `iw_we_d`, `iw_k2`).
- Sim checks (`tg68_bus.v`, `ifndef YOSYS`): `iw_ra_bad` (the RAMs' read
  on the edge into every DECIDE clock used `k_addr`'s row: 0 in every
  sim, so `fp_rsel_n` never shares a DECIDE read), `iw_skip_bad` (two
  clocks after a skipped drop the entry must not hold the written
  address or a mirror of it), `iw_skips`, `iw_forced`.
- Tests (`test_top.s`, fastmem, markers at $8F50, results $8230-$8254;
  `tb_top.sv` looks at the entries when the marker write starts): (1)
  code at $08005100 kept over a pair write 8 KB up and a Chip RAM write
  at its index, run again with no fill, then a write to its immediate
  drops it; (2) pair writes: second word at cached code's index kept,
  second word = the code dropped; (3) fast $08009100 vs chip $9100 (tags
  differ only in the region bits), both ways; (4) a write through the
  mirror ($109104) drops chip $9104 (the tb's Chip RAM now repeats at
  $108000 and its write shadow folds bit 20); (5) a fill on the lookup's
  edge: smc1 at $08005400, its +8..+12 evicted by code 8 KB up, so the
  storing run's fetch of +8 misses as a pair read whose fill of +10
  lands on the edge the store's lookup reads; (6) a fill in the decision
  clock: smc1 at $08005502, the nop after the store an odd word, whose
  single read's prefetch of the store's target the posted store waits
  for in DECIDE. 14 entry checks, 10 value checks.
- Mutants (fastmem):
  | mutant | caught by |
  | --- | --- |
  | (a) keep always 1 | smc tests, stale-hit oracle, `iw_skip_bad` (27), markers 5 and 9 (22 errors) |
  | (b) compare ignores the region bits | markers 6, 7, 8 (test 3) |
  | (c) `iw_dirty` stuck at 0 | test 5: storing run 5 not 2, stale hit, `iw_skip_bad` |
  | (d) no mirror mask | test 4: marker 9, result 8244, stale hit |
  | (e) `iw_dirty` without `iw_we_d` (the read-edge write) | test 5, as (c) |
  | (f) no `!ic_we` in `iw_ok` | test 6 (before test 6 it passed) |
  | (g) no `!pf_fill` | **not testable**: a fill cannot start in a drop's decision clock. A posted write's DECIDE needs the port idle, so no ack can come in DECIDE or the two clocks after (`pf_fill` needs an ack, DDATA2 or `pf_fill_d`, the last two only in the sequencer's own read states); an old-route write also starts with the port idle and issues no request until LATCH. Kept as a guard; `iw_skip_bad` would see it. |
  | step 17 off (`-DS17_DEFAULT=0`) | with the keep checks enabled, 8 errors (every "kept" check); the tb now skips those checks when `ICKEEP` is 0, so the v2.0 reference passes |
- Regression, all PASS: bus, top, fastmem; fastmem with `CAL_TEST` and
  `CAL_DRIFT`; bus/top/fastmem with `S15_DEFAULT=0` and with
  `S17_DEFAULT=0`; benches c, coff, copy, read, scatter, readoff, chip,
  wrchip, wrfast, wrmix, sd, op; c, copy, read, scatter at 20x. No SDRAM
  model violation, no stale hit, `iw_ra_bad` and `iw_skip_bad` 0.
- Numbers (12x, timed-pass clocks, against section 5):
  | bench | v2.0 | step 17 | |
  | --- | --- | --- | --- |
  | c | 65892 | 65808 | -0.13% |
  | coff | 120948 | 120948 | |
  | copy | 9432 | 9384 | -0.5% |
  | read | 6204 | 6204 | |
  | scatter | 3756 | 3756 | |
  | readoff | 11316 | 11316 | |
  | chip | 31440 | 31440 | |
  | wrfast | 7464 | 6732 | **-9.8%** |
  | wrmix | 31572 | 31572 | |
  | op | 21600 | 21468 | -0.6%, see below |
  **bench op's rows moved, against the plan's expectation, all of them
  down**: push + pop of a long 25.88 -> 18.88 clocks, tst.l 5.25 -> 4.75,
  clr.l (a0) 18.56 -> 18.00, addq.l #1,(a0) 18.62 -> 18.56, movem.l
  196.88 -> 196.50; every other row identical. The planner moved the
  bench's data and stack, but the stack's top ($080307FC) still shares an
  index with the bench's own code ($080047FC): each push dropped a code
  word. That is the case step 17 removes.
  Entries of another address dropped: 0 everywhere except bench op (5,
  all forced by `iw_dirty`: the previous write's drop of an invalid
  entry dirties the next write's lookup; conservative). `read` and
  `scatter` kept their 3 entries but did not get faster (the code was not
  run again after). At 20x (step 17 off / on): c 39804 / 39816 (+12
  ticks, one 7 MHz bus cycle at the end marker: the timed window is cut
  by Chip RAM marker writes), copy 6168 / 6120 (-0.8%), read 4032 /
  4032, scatter 2556 / 2556.
- Timing (`build.py full --seed 1 --seeds 16 --keep-sdf`, netlist of
  3de9d71): **2 of 16 pass**, seed 6 (+0.05 / +0.21 ns) and seed 10
  (+0.82 / +1.43). v2.0 passed 4 of 18. The failures are in v2.0's
  classes: kernel -> logic on 8 seeds (to -2.55 ns), logic -> logic on 4
  (to -1.47), adapter ctrl -> logic on 2 (to -0.18), kernel -> read-data
  latch on 1. No failing path goes through `iw_*`; the worst path that
  does is +0.41 ns (seed 15, `iw_t_o` -> adapter ctrl -> logic), the
  rest have >= 2.7 ns. So nothing to restructure (rule 3). Scored:
  seed 10 1.266x (16x) / **1.582x (20x)**, seed 6 1.314x / 1.643x.
  Shipped seed 10: `bitstreams/step17_ickeep/` (`_plain`, `_fast`,
  timing at 12x / 16x / 20x, `seeds.txt`, `speed`, `README.txt` with the
  test list). Utilisation 11,285 LUT4, 2,678 FF, 35 DP16KD.
- **Glen's hardware test (seed 10): runs at 12x, 16x and 20x**, SD card
  included. Caches on as v2.0 within 1% (SysInfo 10804 / 14411 / 18029,
  AIBB 16.69 / 21.13 / 26.32, Frontier timedemo 26.4 / 30.9 / 34.1 fps),
  which is what the sim said (the benchmarks do not collide). Caches-off
  numbers moved both ways by up to 7% / 19%, where step 17 cannot change
  anything: spread. New test from Glen, the Frontier "CPU" timedemo: 31.1
  / 41.2 / 57.1 fps average (12x / 16x / 20x), a far bigger spread between
  speeds than the Amiga-side one; the baseline for the next steps.
  Test item 4 (code the CPU writes and then runs), from ADF under
  Kickstart 3.x: Eon (The Black Lotus) runs fine. Hardwired (Crionics &
  The Silents) stops at "this demo don't like axel" on step 17 and on
  v2.0 alike: the demo's own accelerator check, so no test either way.
  Desert Dream (Kefrens) runs on both; on both, the 3D ship at the start
  shows small polygon errors (the same on v2.0, so not step 17; likely
  the demo's timing on a fast CPU, to be narrowed down by Glen: speed 12
  vs 20, and under Kickstart 1.3, which leaves the caches off). Glen:
  worse at 20x than at 12x; correct under Kickstart 1.3. That does not
  separate speed from caches: with the caches off, code in Chip RAM runs
  at about 68000 speed (every word over the 7 MHz bus). Worse at 20x
  points at a CPU/blitter race. **A real 68030 accelerator shows the same
  ship errors**: the demo's own behaviour on fast CPUs, not this design.
- Possible refinement, not done: an invalid entry needs no drop either
  (skip on `!valid` too). It would remove bench op's 5 forced drops;
  behaviour otherwise identical. Left as the plan wrote it.

---

### Step 18: `perf`, counters in a test build

Branch `step18-perf`, from step 17. **Ready.** No speed change; a test
build only, never released.

**Goal.** Know where a real program's time goes on Glen's machine:
the Frontier timedemo, SysInfo, a game. Every later step is chosen from
these numbers.

**The change.**

1. `build.py full --perf` defines `TG68_PERF` for yosys; output folder
   `build/full_perf/`, files `base64_tg68_full_perf*.bit`. Without the
   option the netlist must be unchanged: **the default build's bitstream
   is byte-identical to step 17's** for the same seed (check with
   `cmp`).
2. Under `` `ifdef TG68_PERF `` (and in the sim under a `PERF` define
   that `run.sh` always sets for the benches), a counter block in
   `tg68_bus.v` or a new small module beside it. Each counter
   increments from a **registered one-clock event flag**, so that no
   counter logic hangs on a path of the sequencer. Counters hold through
   a kernel reset. Events (the test bench's own counters under
   `MEMBENCH` in `sim/tb_top.sv` define them exactly; use the same
   expressions):
   - clocks (must not wrap for 30 minutes at 20x: 40 bits or more);
   - kernel steps; fetch steps; predicted fetches; cache-hit steps
     (instruction, data, separately); internal steps;
   - instruction fetches served by the SDRAM (misses in fast RAM or
     MapROM); instruction fetches over the old route with the address in
     Chip RAM (`a_r[31:21] == 0`); the same over the old route
     elsewhere (ROM without MapROM, slow RAM);
   - old-route data reads, split Chip RAM / other (custom registers,
     CIA); old-route writes, the same split;
   - clocks with an old-route cycle in progress (`~as_i`), 40 bits;
   - clocks a Chip RAM write waits because the write buffer is full
     (`st_cw`'s expression), clocks a fast RAM write waits for the port
     (`st_fw`), 40 bits each;
   - instruction-cache entries dropped by a write (after step 17: real
     drops only), instruction-cache fills.
3. Registers in `turbomem_zii.v` (TG68:), next to +$F00A / +$F00C; pick
   free offsets and document them in the file's register list:
   - control, write with a key byte like the speed register: select a
     counter by number, freeze, run, clear all; reads back the state
     and the number of counters;
   - data: the selected counter, as 16-bit words, read-only.
   The counters **freeze by themselves when the Amiga resets** and stay
   frozen until `perf RUN` or `perf CLEAR`, so a game that can only be
   left by a reset still leaves its numbers behind (the speed register
   already survives a reset the same way).
4. `sw/perf/perf.s` and `build.sh`, modelled on `sw/speed/`: `perf`
   (freeze, print every counter with its name as a decimal number,
   run again unless it was frozen by a reset), `perf CLEAR` (clear and
   run), `perf FREEZE`, `perf RUN`. Print the speed in force too. Plain
   68000 code.
5. Test bench: at the end of every bench, compare each hardware counter
   with the test bench's own count of the same event (they already
   exist: `n_step`, `n_int`, `n_hit`, `n_dir`, `n_bus`, `sk_*`,
   `st_*`); a `test_top.s` case reads two counters through the
   registers, freezes, checks they stop, clears, checks zero.
   Mutant: drop one increment; the comparison must fail.
6. `check_timing.py`: the counters are ordinary 1T logic; the read
   multiplexer into the register read path gets the class the speed
   status has (config registers). Say which in a comment.

**Acceptance.** Default build byte-identical to step 17; the perf build
passes 12x timing on some seed (it need not be a good 20x seed, but
report its ratios; Glen will want to profile at 20x); sims pass.

**What Glen runs** (put this list in the bitstream folder's README):
for each of 12x and 20x: `perf CLEAR`, the workload, `perf >RAM:p.txt`
(or reset, then `perf`). Workloads: SysInfo's speed test; AIBB MemTest;
the Frontier timedemo; one more game of his choice; a Workbench
session.

**What the numbers decide** (the builder writes the table into the log;
the planner or Glen reads it):

- Chip RAM instruction fetches x the clocks an old-route cycle takes,
  as a share of all clocks = the most a bigger instruction cache
  (step 20) or Chip code prefetch (4.6) can give. Above 5% in Frontier:
  build step 20.
- Write-buffer-full clocks as a share = the most a deeper write buffer
  (4.5) can give.
- Old-route data reads in Chip RAM as a share: nothing can speed these
  up; it bounds everything else for that program.
- Entries dropped by writes against fills: what is left of 1.2.
- Fast RAM write waits: 4.2.

**Stop and report if** the default build is not byte-identical with the
option off (the ifdef leaks).

**Log.**

- Built on branch `step18-perf` (from `step17-icache-tag-drop`).
- RTL, all under `` `ifdef TG68_PERF ``: `rtl/base64_tg68/perf_cnt.v`
  (20 counters x 40 bits; power-on frozen and zero; `slave_reset` freezes
  them and sets "frozen by a reset" if they were running; select / freeze /
  run / clear). **One change to the plan's command set: clear does not
  start the counters** (`perf CLEAR` sends clear, then run), so a frozen
  set can be zeroed and checked. Read multiplexer in two registered
  stages (the one-stage version missed 1T by up to 1.1 ns on the first
  build). `tg68_bus.v` makes events 1-15 and 17-19 as registered flags
  from registers and the kernel's step-time outputs (no load on any
  sequencer decision); counter 18 counts drops of entries that held code
  when DECIDE looked them up (`pv_dv`, set beside the drop's `ic_we`), not
  every drop write (1933 in bench c, nearly all of them empty entries).
  Top level: counter 16 = `postable && wb_full` (a Chip RAM write waiting
  for buffer room), registered. `turbomem_zii.v`: +$F00E control (key
  $5C) / stat, +$F010-$F014 the selected counter (A4 decoded only with
  TG68_PERF). `build.py --perf`: `-DTG68_PERF`, adds `perf_cnt.v`,
  `build/full_perf/`.
- Counters: 0 clocks, 1 steps, 2 fetch steps, 3 predicted fetches, 4
  instruction-cache hit steps, 5 data-cache hit steps, 6 internal steps,
  7 / 8 direct SDRAM reads (fetch / data), 9-14 old-route cycles (fetch,
  read, write x Chip RAM / elsewhere), 15 clocks with an old-route cycle
  in progress, 16 Chip RAM write waits, 17 fast RAM write waits for the
  port (`st_fw`'s expression), 18 drops of code, 19 instruction-cache
  fills.
- `sw/perf/perf.s` (68000, `build.sh`, `ReadMe.txt`): `perf` (freeze,
  print all with names in decimal, run on if it was running), CLEAR /
  FREEZE / RUN; reports "no counters" on any other gateware. Tested under
  vamos with a fake board (`build.sh test`): running, frozen by a reset,
  no counters, usage, a 40-bit value.
- Sims: `run.sh` builds with the counters by default (`PERF=0` without).
  test_top.s (fastmem) reads them through the registers: power-on frozen
  $1400, steps over a 50-turn loop (153), clocks unchanged while frozen,
  an Amiga reset (a sim-only pulse on perf_cnt's reset) freezes and flags
  ($5400), run clears the flag ($9400), clear zeroes, a $5D key is
  ignored. Every bench at 12x compares 13 counter groups with the tb's own
  counts (n_clk, n_step, sk_f, sk_f4, n_hit, sk_i, n_dir, n_bus, st_cw,
  st_fw, and new tb counts of old-route clocks, code drops and fills):
  **all exact** (tolerance 2 allowed for the window's edges, never used).
  At 16x / 20x the tb's counters tick on the 12x clock and describe
  nothing, so only the clock count is checked there (window x 20/12 or
  16/12: exact).
- Mutants: counter 2's increment removed: bench c fails (0 against
  9322). The reset flag not set: fastmem fails (8274 = $1400).
- Regression, all PASS: bus, top, fastmem with PERF=1 and PERF=0;
  fastmem CAL_TEST and CAL_DRIFT; S15_DEFAULT=0 and S17_DEFAULT=0; benches
  c, coff, copy, read, scatter, readoff, chip, wrchip, wrfast, wrmix,
  sd, op; c and copy with PERF=0; c, copy, read, scatter at 20x; c at 16x.
  Clock counts identical to step 17 (the counters only watch).
- **Default build byte-identical to step 17**: `build.py full --seed 10
  --seeds 1` without `--perf` gives the same plain and `_fast` files as
  `bitstreams/step17_ickeep/` (`cmp`).
- Perf build, first netlist (one-stage read multiplexer), seeds 1-12: 7
  of 12 failed to route (all on the same net, `u_clkgen.g_pll.u_gbuf_CLKI`:
  the clock multiplexer's output into the DCCA), the other 5 failed
  timing: the counters' read multiplexer (logic -> logic, to -1.06 ns),
  and the design's usual tightest 1T paths (`cc_want_k` / `ic_qt_*` ->
  step decision, `fp_rsel_n` -> cache RAMs, to -3.3 ns). Utilisation
  12,009 LUT4 (+724), 3,557 FF (+879), 1,029 CCU2C (+400), 35 DP16KD.
- Second netlist (two-stage read multiplexer), seeds 1-16: **all 16 failed
  to route** on the same net. The timing report of a router1 diagnostic
  showed why the multiplexer was slow: yosys built the variable
  part-select `flat[sel*W +: W]` with a multiplier (4 extra MULT18X18D,
  19 ns). Rewritten with constant indices (a loop of compares): 10
  MULT18X18D as the normal build, 12,022 LUT4, 3,757 FF.
- Third netlist, router2, seeds 1-16: 12 failed to route (all on
  `u_gbuf_CLKI`), 4 failed timing in the usual classes (clkena -> kernel
  to -2.10, kernel -> logic -1.19, icache/direct -> logic -0.67). So the
  multipliers were not what blocked router2.
- **router1** (new `ROUTER` override in build.py, default still router2;
  normal builds unchanged), same netlist, seeds 1-16: **all route, 14 of
  16 pass** (3 and 5 fail: icache/direct -> logic -0.64 / -0.17).
  Worst 1T slack +0.16 to +1.43 ns, multicycle +2.9 to +6.4 ns. Scored at
  16x / 20x: seed 2 1.158x / **1.447x** (the lowest; v2.0's seed 10 was
  1.233x / 1.541x, step 17's 1.266x / 1.582x), 10 1.179 / 1.474, 15
  1.188 / 1.485, 12 1.205 / 1.507, ... 8 1.302 / 1.627. Shipped seed 2:
  `bitstreams/step18_perf/` (`_plain`, `_fast`, timing at 12x / 16x /
  20x, `seeds.txt`, `perf`, `perf_ReadMe.txt`, `speed`, `README.txt` with
  Glen's workload list).
- **Glen's first runs** (seed 2; one session per speed, all workloads in
  a row, ended by a reset): 12x 537 s, 20x 373 s. Shares (counter values
  in the files Glen sent; `perf_an`-style arithmetic, clocks per kind as
  4 / 5 / ~9 / measured):

  | | 12x | 20x |
  | --- | --- | --- |
  | steps: fetch / internal / data | 46.8 / 35.7 / 17.5% | 45.1 / 38.6 / 16.3% |
  | fetches: predicted / icache / SDRAM / buffer / bus | 83.5 / 9.6 / 4.1 / 2.8 / 0.0001% | 82.7 / 10.8 / 3.8 / 2.7 / 0.0001% |
  | time: predicted fetches | 28.0% | 25.5% |
  | time: internal steps | 25.6% | 26.3% |
  | time: cache hits (instruction + data) | 10.3% | 10.3% |
  | time: posted writes, buffer reads | 7.4% | 6.3% |
  | time: SDRAM misses (fetch + data) | 4.9% | 4.0% |
  | time: bus cycles (measured) + their setup | 19.7% | 23.4% |
  | model total | 95.9% | 95.9% |
  | bus cycles: chip reads / chip writes / other reads, clocks each | 62M / 95M / 32M, 43 | 61M / 85M / 21M, 69 |
  | Chip write buffer full | 2.64% | 3.84% |
  | fast RAM write waits | 0.53% | 0.51% |
  | code dropped by writes, of fills | 2.5% | 2.5% |

  What they decide, by the plan's rules:
  - **Chip RAM code over the bus: 4,800 fetches in 9 minutes, 0.0005% of
    the time.** Chip RAM code ran from the instruction cache (or Frontier
    in this session was not running from Chip RAM; ask Glen). So step 20's
    Chip RAM case does not apply. What a 16 KB cache could still remove
    is part of the SDRAM misses: at most ~4-5% of the time, realistically
    1-2%. **Below the plan's 5% threshold: do not build step 20 now.**
  - Deeper Chip write buffer (4.5): at most 2.6% (12x) / 3.8% (20x).
  - Fast RAM write waits (4.2): 0.5%. Drops of code (what is left of 1.2):
    2.5% of fills, about 0.1% of the time.
  - The two big shares are the core's own steps: predicted fetches (26-28%,
    already the 4-clock floor) and internal steps (26%). **Caveat: a
    stopped TG68 counts as internal steps** (the kernel's STOP keeps
    stepping with state "01": `TG68KdotC_Kernel.vhd`, `stop`), and busy
    wait loops (polling custom registers: 32M "other" bus reads) look like
    work too. These runs mix idle Workbench time, waits and real work, so
    how much of the 26% the barrel shifter (step 19) or fewer kernel steps
    (4.8) could take cannot be read off them.
  - Next measurements (asked of Glen): the Frontier CPU timedemo alone, and
    SysInfo alone, each between `perf CLEAR` and `perf`, at 20x; and a
    Workbench idle minute alone (how much of "internal" is STOP).
  - A possible counter for a later perf build: steps while stopped
    (kernel `stop`), so idle time separates from work.
- **Glen's per-workload runs (20x, seed 2):**

  | | Frontier CPU timedemo | Frontier WHDLoad, intro | SysInfo (with idle) | Workbench idle |
  | --- | --- | --- | --- | --- |
  | length | 124 s | 239 s | 33 s | 73 s |
  | clocks per step | 5.10 | 9.65 | 4.71 | 4.03 |
  | steps: fetch / internal / data | 52.8 / 27.7 / 19.6% | 45.4 / 38.3 / 16.3% | 11.5 / 86.0 / 2.5% | 0.3 / 99.6 / 0.1% |
  | fetches: predicted / icache / SDRAM / buffer | 84.2 / 10.8 / 3.0 / 2.1% | 1.6 / 0.2 / 57.4 / 40.5% | 90.4 / 8.1 / 0.9 / 0.6% | |
  | time: predicted fetches | 34.8% | 0.3% | 8.8% | 0.2% |
  | time: internal steps | 21.7% | 15.9% | 73.1% | 98.8% |
  | time: cache hits (i + d) | 13.5% | 0.1% | 2.5% | |
  | time: posted writes etc. | 9.5% | 3.6% | 0.6% | |
  | time: SDRAM misses (est. 9 clocks) | 4.9% | 30.8% | 0.3% | |
  | time: bus cycles + setup | 9.8% | 17.3% | 14.3% | 0.6% |
  | Chip write buffer full | **5.47%** | 1.76% | 0.43% | 0 |
  | fast RAM write waits | 0.96% | 0.50% | 0.03% | |
  | Chip RAM code over the bus | 2,301 fetches | 5.0M (0.3% of fetches) | 9 | 9 |
  | model total | 95.3% | 77.5% | 99.6% | 99.9% |

  - **Workbench idle is 99.6% internal steps: a stopped TG68 counts as
    internal steps**, as the kernel source says. SysInfo's 33 s include
    its idle window, so its split says little; the Frontier CPU timedemo
    is the clean CPU workload.
  - **Frontier WHDLoad (the intro) ran with the caches effectively off**:
    6M data-cache reads against 245M SDRAM data reads, 5.9M instruction
    fills against 915M SDRAM fetches, 9.65 clocks a step against 5.10 for
    the timedemo. CACR EI off (or FI set) under WHDLoad or its slave, not a
    gateware matter; Glen can look for a cache option. (The model's 9
    clocks per uncached fetch is low for this case: total 77.5%.)
  - **Frontier CPU timedemo**, what each item could give at most:
    a deeper Chip RAM write buffer (4.5) **5.5%** (16.3M Chip writes, 78
    clocks each on the bus: Frontier draws with the CPU); bigger caches
    (step 20) part of the 4.9% of SDRAM misses (instruction fills 5.9% of
    fetches), realistically 1.5-2.5%: **still below the 5% rule, step 20
    not now**; the barrel shifter (step 19) part of 21.7% of internal
    steps (how much is shifts is not measured; the timedemo itself will
    show it); fast RAM write waits 1%.
  - Chip RAM code over the bus is ~0 in every run except WHDLoad's intro
    (0.3% of fetches).
- **Router1 on the normal design** (branch `exp-router1`; the step 18
  normal netlist, which is step 17 byte for byte under router2):
  **16 of 16 seeds pass** at 12x (router2: 2 of 16), worst 1T +0.36 to
  +1.53 ns, 20x ratios 1.433 to 1.599 (median ~1.50). Seed 7: +1.53 ns,
  1.146x / **1.433x**, the best margin this design has had (v2.0 1.541x,
  step 17 1.582x). Test bitstreams `bitstreams/exp_router1/` (seed 7),
  waiting for Glen's run. If it behaves as step 17, router1 becomes the
  default (build.py, CLAUDE.md) and step 19 is built with it.
- **For the planner: router1 may be the better router for every build.**
  On this netlist it routed what router2 could not and gave margins no
  router2 build of this design has had (14 of 16 seeds passing, against
  2 of 16 for step 17 and 4 of 18 for v2.0; best 20x ratio 1.447x). It has
  not been tried on the normal netlist, and the four earlier router1
  trials (with the multipliers) also passed every CPU class. A normal
  build with `ROUTER=router1` on 16 seeds is a cheap experiment; whether
  to ship a router1 build is Glen's and the planner's call (it would
  change the reference flow in CLAUDE.md).

---

### Step 19: the kernel's barrel shifter

Branch `step19-barrel`, from step 18. **Ready**, with a known timing risk
(the trial below).

**Goal.** Every shift and rotate in one kernel step.

**Background.** `rtl/tg68/tg68_020.vhd` passes `BarrelShifter => BARREL`;
`scripts/gen_tg68.sh 1` writes `rtl/tg68/tg68_020_b1.v`
(`YOSYS=yowasp-yosys sh scripts/gen_tg68.sh 1`, ghdl 4.1.0, 15 seconds).
`scripts/build.py` has `core = 'tg68_020_b0.v'`; `sim/run.sh` has
`CORE=${CORE:-tg68_020_b0}`. No VHDL change.

**Trial by the planner** (v2.0 RTL with the b1 netlist; nothing of it
is committed, the two commands above reproduce it):

- `bench op`: section 1.1's last column. `bench c`: 64,932 clocks
  (65,892), internal steps 1,968 (2,196), checksums correct.
- yosys: 11,189 LUT4 (11,067), 2,647 FF, 629 CCU2C, 35 DP16KD.
- kernel -> kernel: 41.7 and 43.4 ns on the two seeds looked at (budget
  46.5 ns): the shifter fits in the kernel's 4 clocks.
- **Seeds 1 to 16: none passes at 12x** (v2.0: seeds 6, 9, 10 and 16 of
  the same sixteen). All are near misses: 3 (+0.46 / -0.06 ns), 4
  (-0.17 / -0.01), 9 (-0.12 / -0.16), 6 (-0.28 / +1.00), 10 (+0.26 /
  -0.85). The classes that miss are the ones that miss in v2.0
  (kernel -> logic on 4 seeds, adapter ctrl -> logic on 5, icache/direct
  on 3), and the failing paths do not go through the shifter (seed 7:
  register file -> `addr_out` -> the adapter's address decode; seed 15:
  kernel state -> `longword` -> `cnt`). So the shifter itself is not
  slow; a kernel 122 LUTs bigger places a little worse.

**The change.**

1. Generate `tg68_020_b1.v`; make it the default core in `build.py`,
   `sim/run.sh`, `build.bat` and anywhere else `tg68_020_b0` is named
   (grep). Keep `tg68_020_b0.v` in the repository for one step as the
   fallback, then remove it in the step after Glen has passed this one.
2. `sim/test020.s` (bus bench) and `test_top.s`: add a shift and rotate
   test that covers what the barrel shifter does differently from the
   bit-by-bit one. For each of asl, asr, lsl, lsr, rol, ror, roxl, roxr,
   in byte, word and long size: counts 0, 1, 2, 7, 8, 15, 16, 31, 32, 33
   and 63 from a register, and immediate counts 1 and 8, on at least two
   data values, checking the result **and the flags** (X, N, Z, V, C;
   ASL's V is the hard one, ROXL/ROXR's X with count 0 the other).
   Memory shifts (`asl (a0)`, one bit, word) too. Write the expected
   values from a reference, not from this core: run the same program on
   the b0 netlist (`CORE=tg68_020_b0`), which has been on hardware since
   v1.0, and require identical results from b1. The test program
   computes a checksum over all results and flags; the bench compares
   b0's and b1's.
3. Run the whole regression with both cores.

**Numbers.** `bench c` becomes 64,932 clocks at 12x (record the others;
only benches that shift move).

**Acceptance.** Shift test identical on b0 and b1 over the whole
matrix; sims pass; a 12x seed passes; ratios at 16x and 20x reported.
Seed budget: 48 seeds on the step's own netlist (steps 17 and 18 change
it, so the trial's seeds say nothing about which ones pass). Glen's test: the usual benchmarks, the
Frontier timedemo, games.

**Fallbacks.** If no seed in 48 passes: commit the test and the tools,
leave `b0` the default, and report the table of classes that miss. Do
not restructure the adapter for it without a plan. The step then waits
for something that frees margin, and step 20 stacks on step 18. If the flags
differ between b0 and b1 in any case: stop, report the case (it would be
a TG68K.C bug in one of the two shifters; a real 68020's result decides
which; WinUAE in 68020 mode, or any real 68020 machine, can run the one
case).

**Log.** (the builder writes here)

Built 20 November 2026 on macOS (from a second collaborator's Mac; the
v2.0 seed 10 build reproduces byte for byte there), branch
`step19-barrel` from `step18-perf`. **Result: the fallback.** No 12x
seed passed, so `b0` stays the default; the `b1` netlist, the shift
matrix and the tools are committed.

- **Netlist.** GHDL 4.1.0 (the official `ghdl-gha-ubuntu-22.04-mcode`
  build in Docker, `ubuntu:22.04`, `linux/amd64`) + `fix_latches.py`
  with yowasp-yosys: regenerates `tg68_020_b0.v` **byte for byte**, and
  writes `tg68_020_b1.v` (the VHDL is unchanged since v2.0). +73 LUT4 on
  v2.0.
- **Shift matrix** (`sim/shift_test.inc`, called from `test020.s` and
  `test_top.s`; code at ROM $1100, so $1000-$10FF stays zero for the
  MapROM tests' real-ROM reads at $F81000/2; results at $9E00): asl asr
  lsl lsr rol ror roxl roxr x byte/word/long x counts 0 1 2 7 8 15 16 31
  32 33 63 from a register and #1, #8, on two values (flags all clear /
  all set on entry), plus one-bit memory shifts; every result and its
  X N Z V C go into a MULU/ADD checksum, one per op and size (25 values),
  checked against b0's. **b0 and b1 identical in all 25, in `bus`, `top`
  and `fastmem`.** Mutant: X and C left out of the checksum -> all 25
  fail. (Not in `bench *`: those share tb_top's MEMBENCH result block,
  and their programs do not run the matrix.)
- **Benches with b1** (`CORE=tg68_020_b1`, PERF=0): **op 21,468 ->
  18,804 (-12.4 %)**, c 64,992 -> 64,092 (-1.4 %), coff 119,976 ->
  119,052; copy, read, scatter, chip, wrfast, wrmix unchanged.
- **Timing with b1: 0 of 48 seeds pass** at 12x. Built on step 18 with two
  margin changes under it (below), 11,158 LUT4. Near misses: seed 11
  (-0.02 / -0.01 ns), 30 (-0.03 / +0.76), 16 (-0.09 / +2.58), 3 (-0.14 /
  -0.08). Failing seeds by class: kernel -> logic 17, icache/direct ->
  logic 13, adapter ctrl -> logic 7, clkena -> kernel 3, adapter ctrl ->
  cache RAM 3, others 5. kernel -> kernel (where the shifter is) is not
  among them. Fallback taken as the plan says; not restructured.
- **The margin changes tried under it** (not pushed; local branches
  `old-step17b-on18`, `old-step17c-on18`):
  (17b) CCMP's 14-bit tag compare done a clock earlier: the edge into
  CCMP registers two half-tag matches per bank and per cache from the tag
  RAMs' outputs and the live `k_addr` tag (kernel -> logic, SETTLE), so
  CCMP keeps an AND and the selects before `step()`; sim check: the
  precompare equals the old compare in every CCMP. (17c) `sdram_ctrl`'s
  direct ACTIVATE records `open_row`/`ras_timer` a clock later from
  `cur_bank`/`cur_row`, out of IDLE's request decision; sim checks from
  the SDRAM pins (the row each ACTIVE opened = `open_row` for every open
  bank while IDLE; PRECHARGE >= T_RAS after ACTIVE). Both cycle-identical
  (every bench unchanged), mutants caught. **On an independent local
  step 17 they raised the pass rate from 1 of 32 to 6 of 32 (best 1.576x
  at 20x), and with b1 on top 5 of 48 passed (best 1.586x). On this step
  17 they do not help: 17b + 17c alone 2 of 32 (seed 19 +0.37 ns,
  1.301x / 1.627x; seed 8 +0.07, 1.312x / 1.640x), against step 17's own
  2 of 16 at 1.582x.** Their new paths (tag RAM -> the half matches, 47
  failing paths; the half matches -> `cnt`, 30) land just outside 1T
  here. So they are not offered; noted for the planner as tried.
- **Note (not this step):** on `step18-perf`, `sim/run.sh top` with the
  default PERF=1 does not compile (`tb_top.sv` reads
  `dut.g_fastmem.u_perf`, and the `top` bench has no fast RAM).
  `PERF=0 sim/run.sh top` passes.

**For the planner:** b1 is ready and verified; it needs margin that
neither the trial nor these two changes found.

**Rebuilt with router1** (after `exp-router1` made router1 the default;
`exp-router1` merged into this branch, b1 the default core again in
`build.py` and `sim/run.sh`):
- Regression, all PASS (b1 unless said): bus, top, fastmem; top PERF=0;
  bus/top/fastmem with b0; fastmem CAL_TEST, CAL_DRIFT; S15_DEFAULT=0,
  S17_DEFAULT=0; benches c, coff, copy, read, scatter, readoff, chip,
  wrchip, wrfast, wrmix, sd, op; c and copy at 20x. The shift matrix's 25
  checksums identical everywhere. Benches: c 65,808 -> 64,920 (-1.3%),
  op 21,468 -> 18,804 (-12.4%), copy unchanged; c at 20x 39,816 ->
  39,240 (-1.4%). 11,358 LUT4, 2,678 FF, 10 MULT18X18D.
- **Timing: 14 of 16 seeds pass** (router2: 0 of 48). 5 and 8 miss by
  0.12 / 0.06 ns. Seed 2: +1.48 / +4.03 ns, **1.167x / 1.459x** at 16x /
  20x (exp-router1's seed 7: 1.146x / 1.433x); then 9 (1.489x), 6
  (1.504x), 12 (1.513x) ... 15 (1.648x). Shipped seed 2:
  `bitstreams/step19_barrel/`, waiting for Glen's test (the Frontier CPU
  timedemo against exp-router1, back to back). The failing classes are
v2.0's (kernel -> logic: the register file -> the fast RAM address
decode and `k_din`; icache/direct -> logic), not the shifter.


---

### Step 20: 16 KB caches

Branch `step20-cache16`, from step 19. **Ready once step 18's numbers
from Glen's machine say it is worth it** (Chip RAM or fast RAM
instruction misses above about 5% of the clocks in a program he cares
about). Glen decides.

**Goal.** Instruction and data cache 16 KB each (8,192 words), so a
program with more hot code than 8 KB stops refetching it. Frontier's
code is 157 KB in Chip RAM, where a miss is 50 to 80 clocks.

**Background.** `tg68_bus.v`: `parameter IC_AW = 12` (log2 of the cache
words) sizes both caches, the tag (`TAGW = 1 + 2 + (23 - IC_AW)`), the
flush sweep (`ic_fcnt`, `IC_AW` bits: the sweep takes twice as long) and
the predictor's index. Block RAM: 35 of 56 DP16KD used; each cache is
two banks of 2,048 x 30 bits = 8 DP16KD; at `IC_AW = 13` each bank is
4,096 x 29 bits. A DP16KD has a 4,096 x 4 mode, so a bank is 8 block
RAMs **with no multiplexer after them**; 2 caches = 32, total 51 of 56.
"Ideas not yet done" kept the block RAMs for RTG; Glen has dropped RTG.

**The change.**

1. `IC_AW = 13` (a parameter of `tg68_bus.v`, default 12). Find every
   place that assumes 12: grep `IC_AW`, `[12:`, `4096`, `8 KB`, and the
   test benches' shadow arrays.
2. Synthesize first, before anything else: `utilisation.txt` must show
   51 DP16KD, and the json must show the cache RAMs mapped without a
   LUT multiplexer on their outputs (count the LUT4s between a
   `DP16KD` data output and `ic_tq_*` / `ic_dq_*`: none before, none
   after). If yosys picks 2,048 x 9 with a multiplexer, find the
   `memory_libmap` / `ram_style` way to get 4,096 x 4; if there is
   none, stop and report.
3. The flush sweep now takes 8,192 clocks: check every place that
   waits for it (reset, MapROM switch, CACR clear) still works; the
   sims' reset timing may need a longer wait.
4. A bench that shows the gain, `sh sim/run.sh bench bigcode`: 12 KB of
   straight-line code (generated, as `gen_op.py` does) in Chip RAM, run
   three times, the third timed. With 8 KB the third pass misses on
   two thirds of it; with 16 KB it must be all cache hits. The same
   from fast RAM.
5. Tests: the existing ones with the bigger caches; a directed alias
   test at the new distance (two addresses 16 KB apart share an entry;
   8 KB apart no longer do); mutant: tag one bit too narrow (the alias
   test must catch it).

**Numbers.** Section 5's table must not get worse; `bench bigcode`
improves as above.

**Acceptance.** Sims pass; a 12x seed passes in 32 seeds; its 20x ratio
is no worse than 1.60x. Glen's test: the benchmarks (expect no change),
the Frontier timedemo and games (expect the gain), a `perf` build of
this step to see the misses fall.

**Fallbacks, in this order.** (a) Instruction cache only at 16 KB (a
separate `DC_AW`; 43 DP16KD). (b) If timing fails on the RAM address or
output paths on most seeds: report with the classes; do not ship a
build that fails 12x.

**Stop and report if** step 2's mapping cannot be had, or the pass rate
is 0 in 32 seeds.

**Log.** (the builder writes here)

---

### Experiment X22: a 22x clock (156.07 MHz) in place of 16x

Branch `exp-22x`, from the newest step Glen has passed. **Ready; build
only when Glen asks.** Experimental, never merged as it is: if it
works, Glen decides what the three speeds of the next release are.

**Goal.** Find out whether Glen's board runs at 22x. 20x runs at 1.54x
the worst-case model; 22x will be about 1.70x. If it runs: +10% on
CPU-bound work.

**The recipe is `plans/exp20x.md`** (and `exp18x.md` before it): the
same list of changes, one speed higher, with 22x taking 16x's PLL and
speed code so that one bitstream has 12x, 20x and 22x.

- `clkgen.v`, `u_pll16`: x11/6 from the 85.13 MHz pin: `CLKI_DIV 6`,
  `CLKFB_DIV 11`, `CLKOP_DIV 4` (PFD 14.19 MHz, VCO 624.3 MHz, inside
  400 to 800). Sim model `N` to match.
- Top level, that speed code: `ph_top` 21, `ph_half` 11, `ms_top` by
  the same formula the 20x value came from (it fits in 18 bits), the
  register multiplier 22, `spd_hold2` / `spd_lox` as at 20x unless the
  sims say otherwise.
- SDRAM (`sdram_ctrl.v`, IS42S16160J-6, 6.41 ns clock): CL3 (rated to
  166 MHz). Work out every parameter in clocks from the data sheet
  (tRCD and tRP 18 ns = 3 clocks; tRAS 42 ns = 7; tRFC 60 ns = 10;
  tWR), compare with what the controller's `T_*` parameters give at
  20x, and add run-time settings where 22x needs one more
  clock, as `rfc_long` did. `sdram_model_checked.v` must report no
  violation in `bench copy | read | scatter | c` at 22x.
- **The read-data window is the real risk**: access time 5.4 ns in a
  6.41 ns clock leaves 1.0 ns before the next edge (1.65 ns at 20x),
  less the board's delays. Read how the SDRAM clock pin and the input
  registers are timed in the top level, write the arithmetic into the
  log, and if the design has a setting that moves the capture point
  (clock polarity or phase at the pin), say what it is and whether 22x
  wants it changed. Do not change it on a guess: report the options.
- `turbomem_zii.v`: key `$5B16` = 22x. `speed` (a test copy named
  `speed22`): 12 / 20 / 22.
- Sims: the fastmem switch test 12x -> 22x -> 20x -> 12x; the benches at
  22x (`BENCH_ASD`).

**Acceptance for the build.** 12x passes timing; seed chosen by the
lowest ratio at 22x (`check_timing.py --freq 156.07`); report the
ratios at 20x and 22x and the classes that are worst.

**What Glen tests.** At 22x: does it boot and run; a fast RAM memory
test first (wrong read data is the likely failure); SysInfo, AIBB,
xSysInfo; the SD card; `speed` with no argument (the 7 MHz capture
status); then a warm run. A crash is undone by a power cycle.

**Stop and report if** the SDRAM model reports a violation that a
longer timer does not fix.

**Log.** (the builder writes here)

## 4. Smaller items, to be ordered by step 18's numbers

Each **needs a plan** from the planner before it is built. What is
known, and what the plan must settle:

1. **32-bit operands in one fetch again.** 12 clocks -> 9 for every
   32-bit immediate and absolute address (1.1 point 2). Step 15b's log
   has why the pair test left the predicted fetch (`long_cand` in the
   kernel-step decision). First measure how common these are in real
   code: add the Dhrystone 2.1 source to the sim as `bench dhry`, built
   as `bench c` is but with absolute addressing as Amiga compilers do
   it (`-fno-pic`, no base register), and count fetch steps with
   `long_cand` high. The two banks could deliver any two consecutive
   words, not just an aligned pair, if each bank had its own read
   address; whether the kernel accepts an unaligned pair is the first
   thing to find out.
2. **Fast RAM writes that wait for the SDRAM port** (340 clocks in
   `bench c`, 0.5%; movem and call-heavy code more). Two causes to
   separate with counters: the write before is still in the
   controller, and a speculative read started beside a data-cache hit
   holds the port. A second posted write, or not starting the
   speculative read when a write follows, are the candidates. "Fast RAM
   write queue" in `docs/HISTORY.md` has the step 12 measurement.
3. **Data-cache hits, word and byte writes, prefetch-buffer hits in 4
   clocks** (`backlog.md`, speed items 1 to 3: 2.3%, 1.1%, less).
4. **One clock off every SDRAM request** (`backlog.md`, speed item 4).
5. **A deeper Chip RAM write buffer** (8 entries now), only if step
   18 shows clocks lost to a full buffer.
6. **Chip RAM code: read the next word after a miss** while the kernel
   works, only if step 18 shows Chip RAM fetch misses still matter after
   steps 17 and 20.
7. **A 2-bits-per-step divider** (18 -> 10 steps, 36 -> 20): a sixth
   marked kernel change. Low value unless a program Glen cares about
   divides a lot; no counter sees it, so count `divu` / `divs` in the
   program's code or time a divide loop.
8. **Fewer kernel steps for common instructions** (`clr` without the
   read, the fourth step of memory-destination instructions, `lea`,
   the wasted fetch after a short branch): changes to TG68K.C's state
   machine. Only with an instruction-level test suite in the sim first
   (final register and memory state for every instruction against a
   reference), and only if Glen wants to go that far. The largest
   remaining gain for compiled code, and the largest risk.
9. **SD card throughput** (2.0 to 2.7 MB/s): driver and SPI clock work,
   and the licence question in `CLAUDE.md`; a separate track.
10. **7 MHz PLL, stage 2** (`exp-7m-pll` branch): not a speed item;
    waiting for Glen's test of stage 1.

## 5. Baseline (v2.0, `main`, 12x): numbers that must not move

From `sh sim/run.sh bench <name>` on branch `strategy-post-v2`
(tools only, RTL = v2.0).

| bench | clocks (timed pass) | kernel steps | instruction-cache entries of another address dropped / fetched again (whole run) | clocks a fast RAM write waits | clocks a Chip RAM write waits |
| --- | --- | --- | --- | --- | --- |
| c | 65892 | 15040 | 7 / 5 | 340 | 0 |
| coff | 120948 | 14988 | 0 / 0 | 981 | 0 |
| copy | 9432 | 1560 | 51 / 21 | 0 | 0 |
| read | 6204 | 1302 | 3 / 3 | 0 | 0 |
| scatter | 3756 | 737 | 3 / 3 | 0 | 0 |
| readoff | 11316 | 1302 | 0 / 0 | 0 | 0 |
| chip | 31440 | 1814 | 0 / 0 | 0 | 21238 |
| wrfast | 7464 | 1362 | 39 / 29 | 235 | 0 |
| wrmix | 31572 | 6226 | 0 / 0 | 0 | 1702 |

`bus`, `top`, `fastmem` and `bench sd` pass. `bench op`: section 1.1
(the full table is the bench's output). Step 17 is expected to bring the
fourth column to 0 and so to lower `copy`, `wrfast`, `read` and
`scatter` a little; nothing else may move in steps 17 and 18.

## 6. For Glen: what each step needs from you

- Steps 17 and 19: the usual test of a bitstream each (benchmarks at
  three speeds, Frontier timedemo, games). For 17, a few SysInfo runs
  in a row at one speed: the spread should shrink.
- Step 18: run the `perf` build as its README says and send back the
  text files. No speed change to look for.
- Step 20 and X22: your decision, after 18's numbers (20) and whenever
  you want to try it (X22).
- Section 4: tell the planner which programs matter most to you; the
  order follows from that and from 18's numbers.
