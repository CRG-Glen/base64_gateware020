# Report for the planner: where things stand after step 15b

Written by the build model at the end of step 15b, for the next planning
session. Facts and measurements first, then open questions and options;
the choice of what comes next is Glen's, with the planner. Details are in
the files named; nothing here needs re-measuring before planning.

## Glen's direction

- **Timing margin is worth a small speed loss.** On step 15b's SysInfo
  drop (below) he said: "not overly concerned with the minor drop if it
  gives us more room for future advances." Plan with that weight.
- One build for every speed (12x / 14x / 16x via `speed`); no `_x16`.
- He tests every step on his A500+ with SysInfo, AIBB, xSysInfo, a
  Frontier timedemo (new since step 15), games and demos, and `speed`.
- 18x was on his list after step 14 (experimental, never a release).

## What runs on hardware

| Branch | Step | On hardware |
| --- | --- | --- |
| `main` | 12 (released v1.5) | yes |
| `step13-pll-speed` | 13: run-time 12x/14x/16x | yes, all three |
| `step14-timing-headroom` | 14, 14b: timing restructures, 7 MHz capture fix, kernel change 5 | yes |
| `step15-fetch-predictor` | 15: fetch predictor | yes, 12x and 16x |
| `tooling-build-seeds` | build.py: parallel seeds, table | PC side only |
| `step15b-predictor-timing` | 15b: predictor timing margin | yes, 12x and 16x |

Branches stack in that order. Nothing after step 12 is merged or
released. Each step's test bitstreams are in its branch under
`tg68/bitstreams/stepN_name/`, in commits marked "Drop this commit before
merging". 14x has not been benchmarked since step 14 (it booted and ran
then).

### Benchmarks (caches on / off)

| Build | SysInfo Dhrystones | AIBB MemTest MB/s | xSysInfo Dhrystones | Frontier avg fps |
| --- | --- | --- | --- | --- |
| step 14, 12x | 9695 / 5205 | 15.74 / 8.31 | 16247 / 8698 | - |
| step 15, 12x | 11179 / 5162 | 16.59 / 8.48 | 16888 / 9353 | 26.2 |
| step 15b, 12x | 10797 / 4875 | 16.60 / 8.34 | 18430 / 9240 | 26.1 |
| step 14, 16x | 12929 / 6441 | 19.97 / 10.53 | 21317 / 11621 | - |
| step 15, 16x | 14925 / 6462 | 21.03 / 10.40 | 24471 / 11615 | 30.6 |
| step 15b, 16x | 14412 / 5925 | 21.03 / 10.60 | 24129 / 11638 | 30.6 |

- Step 15 gained 15.3% / 15.4% SysInfo caches on (the sim predicted
  about 12% for compiled C).
- **Step 15b vs 15: SysInfo caches on -3.4% at both speeds.** Possibly
  real: 15b's change A makes a predicted fetch always one word, so a
  sequential 32-bit immediate or abs.L operand costs 8 clocks instead of
  a 5-clock pair. bench c has only 75 such pairs in 9,247 fetches (sim
  cost 0.4%); SysInfo's Dhrystone may have far more. Possibly spread:
  AIBB, Frontier and xSysInfo 16x did not move, xSysInfo 12x rose 9%,
  and SysInfo caches off (where 15b changes nothing and the sim is
  clock-for-clock identical) moved by -5.6% / -8.3%. Step 15 alone gave
  4800 and 5162 on two caches-off runs. **Not settled.** Two cheap ways:
  a back-to-back SysInfo run of 15 and 15b; or the real Dhrystone 2.1
  compiled into the sim (`sim/bench_c.c` shows how: gcc -O2 -m68020,
  `run.sh bench c`), run with step 15 and 15b. Glen accepts the loss
  either way.
- SysInfo's run-to-run spread is up to about 8%; xSysInfo's is larger.
  Compare like with like, back to back, before acting on a few percent.
- `speed` at 12x: rising sample, clean at boot and warm (14b's fix
  works). At 16x the unused rising sample is reported as moved; the
  falling one in use is stable. Harmless, unchanged since step 14.

## Timing now (step 15b, `docs/HISTORY.md` and the plan logs have the tables)

- Shipped: seed 10, +0.37 ns worst 1T, +0.75 ns worst multicycle; 14x
  needs the chip 1.130x faster than the worst-case model, 16x 1.292x.
  Builds up to 1.14x / 1.31x have run on Glen's board.
- Pass rate: 5 of 18 seeds (8, 9, 10, 16, 18). Step 15: 1 of 9; step
  14b: 2 of 8; step 14: 4 of 11.
- Utilisation (yosys): 11,067 LUT4, 2,646 FF, 629 CCU2C, 35 of 56 DP16KD,
  10 MULT18X18D.
- **What misses on the 13 failing seeds** (worst class each):
  clkena -> kernel on 6 (to -1.94 ns), logic -> logic on 3 (to -1.82),
  adapter ctrl -> logic on 2 (to -0.92), adapter ctrl -> cache RAM on 1
  (-1.38), kernel -> logic on 1 (-0.25). kernel -> logic is negative on
  4 of 18 (to -0.25 ns); step 15 had it on 4 of 9 (to -1.73). On the
  passing seeds it is 32.3-34.3 ns of 34.9 (step 14b: 31.6).
- **clkena -> kernel is the most common miss again.** It is the clock
  enable fan-out into the kernel: `k_clkena` (~90 loads) and the three
  `k_clkena_lw*` copies (~1,150 loads, kernel changes 2, 4, 5). Kernel
  change 5's split was the last fix; a fourth copy, or moving more
  kernel processes to a copy, is the obvious next lever. The kernel is
  synthesized with keep_hierarchy, so a copy only helps if the kernel's
  own process takes it as a port (as change 5 did).
- logic -> logic misses seen this step run through the SDRAM controller
  (`ref_blk` -> `pre_ras` -> `ras_timer` -> `open_row`) and the bridge
  (`ASn` -> `core_chip_r` -> `rt_rw` -> data pins). Both are step 13-14
  logic, routed longer as the chip fills.
- Tried and dropped in 15b: loading `dp_fast` on every DECIDE clock (made
  kernel -> logic worse on 3 seeds, to -2.42 ns). Earlier and still true:
  nextpnr's target frequency has no effect; a second clock buffer for the
  kernel gave nothing; a carry-chain tag compare is slower than `==`.
- Seed 18 of 15b (+0.35 / +2.53 ns, kernel -> logic 32.3 ns) was not
  scored at 14x/16x (its .sdf was not kept). It may score better than
  seed 10 at 16x: `build.py full --skip-synth --seed 18 --seeds 1 --keep-sdf`
  on f615054 (the json is reproducible: a full synthesis gives the same
  bitstream).

## Where the clocks go (sim, bench c, step 15; 15b differs by 0.4%)

Timed pass 65,640 clocks, 14,965 kernel steps: fetches 9,247 (8,156
predicted in 4 clocks, 986 unpredicted in 5, 75 pairs), data reads 2,009
(1,534 single cache hits in 5 clocks, 411 pairs), writes 1,513 (1,035
single in 5, 420 pairs), internal steps 2,196 (4 clocks). The floor is 4
clocks a step: the kernel's own paths need about 40 of the 46.5 ns
STEP = 4 allows, so STEP = 3 is out of reach without a faster clock-to-
clock kernel.

## Options for the next step (see `plans/backlog.md` for detail)

Margin first, as Glen asked:

1. **clkena -> kernel fan-out** (margin). The commonest miss. Measure the
   loads per copy in the routed design, and which kernel processes the
   worst paths end in, before choosing a split (kernel changes 4 and 5
   in `docs/HISTORY.md` show the method and the yosys merge trap).
2. **SDRAM refresh/row path and bridge data-pin path** (margin). The two
   logic -> logic misses above; both have been restructured before
   (`pre_open/pre_hit/pre_ras`, `rt_hold_done`), so they are known
   territory.
3. **Seed 18 scoring** (no RTL change): if it scores better at 14x/16x,
   ship it instead of seed 10.

Speed, if margin allows:

4. **Data-cache hits in 4 clocks**: the largest remaining item (1,534
   steps, about 2.3% of bench c's clocks). No address to predict; no
   design yet.
5. **Pairs back into the predictor without `long_cand` in the decision**
   (would recover 15b's possible 3.4%). For example, decide "this fetch
   may be a pair" from registers (the predicted address's alignment is
   known a step early; whether the kernel offers a pair is not).
   Needs the Dhrystone measurement first to know if it is worth it.
6. **WR4** (word/byte writes in 4 clocks): built in step 15, off, worth
   1.1% of bench c; needs `k_fast` out of the step decision.
7. **18x**: facts in `backlog.md`. About 1.43x the worst-case model at
   today's margins, against 1.29x at 16x now; better done after 1 and 2.

Housekeeping Glen may ask for at any time: pull requests to merge steps
13 to 15b into `main` and a release (one PR per step, squash-merged,
bitstream commits dropped first; the stacked branches will need
rebasing in order).
