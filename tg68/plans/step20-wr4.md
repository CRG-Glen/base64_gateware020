# Step 20: word and byte writes to fast RAM in 4 clocks (WR4 on)

Status: **built, see log** (22 November 2026, planned and built by the same model
now that the planning model is no longer available). Branch
`step20-wr4`, from `step19-barrel`. The 16 KB caches that
`strategy-after-v2.md` called step 20 are shelved (step 18's numbers: at
most 1-2.5%); this takes the number.

## Goal

A posted word or byte write to fast RAM steps the CPU in the DECIDE clock
(4 clocks from the last step) instead of going on to FINISH (5 clocks).
Nothing else changes.

## Background

- `tg68_bus.v`, parameter `WR4` (0 since step 15). DECIDE's data branch,
  posted write: `if ((WR4 != 0) && !k_wpair && cnt_ok) step(); else q <=
  Q_FINISH;`. A pair write keeps FINISH: its `k_long_ack` is set on the
  DECIDE edge and must be 2 clocks old when the kernel samples it.
- The predictor's select: `if (!((WR4 != 0) && !k_look && k_fast &&
  !k_nwr && !k_wpair && cnt_ok)) k_din_psel <= 1'b0;` (a write that steps
  on this edge keeps the select: nothing may change in the clock before a
  step, tb-asserted by the `ks_chg` check).
- Step 15 built and tested it: correct, +1% on bench c, switched off
  because it puts the fast RAM decode `k_fast` (a kernel -> logic path)
  into the step decision, which then missed 1T under router2. Router1
  (exp-router1, step 19) has given every build 1-1.5 ns more 12x slack.
- Steps 17 and 19 since: step 17's drop decision (`pw_upd`, one clock
  after DECIDE) uses registers loaded at DECIDE (`iw_t_*`, `a_r`); with
  WR4 the kernel steps on the DECIDE edge, so in `pw_upd`'s clock the
  RAMs read the predictor's address (`fp_rsel_n`), which `iw_t_*` no
  longer depend on. `fp_bad` still kills a prediction the drop hits.
- Measured (planning, this branch's netlist with WR4 = 1): bench c 64,920
  -> 64,188 clocks (-1.13%), op 18,804 -> 18,720, wrfast unchanged (pair
  writes), fastmem PASS. Frontier CPU timedemo (step 18's counters):
  writes and buffer reads are 9.5% of its time at 5 clocks, so at most
  ~1.9%, less the pair writes.

## The change

1. `WR4` defaults to a macro, `` `WR4_DEFAULT `` (1), as `S15_DEFAULT`
   does for the step 15 switches: `VLFLAGS=-DWR4_DEFAULT=0` simulates
   the step 19 behaviour. No other RTL change.
2. Timing: `build.py full --seed 1 --seeds 16` (router1). The new 1T
   paths are kernel -> `k_fast` -> step decision; classes as before
   (kernel -> logic 3T into `k_fast`'s decode, 1T from its registered
   inputs).

## Tests

- Regression with WR4 on: bus, top, fastmem (with PERF=0 for top too),
  CAL_TEST, CAL_DRIFT, S15_DEFAULT=0, S17_DEFAULT=0, every bench, bench
  c / copy at 20x; and with `WR4_DEFAULT=0` the three sims (the old
  behaviour still passes).
- The existing checks that cover a write stepping at DECIDE: the shadow
  check of every cache hit against the CPU's writes (`hit_bad`), the
  "long_ack / k_din_sel / k_din_psel changed in the clock before the
  kernel sampled them" check (`ks_chg`), the predicted-fetch checks
  (`fp_chk_bad`), step 17's `iw_skip_bad`, step 18's counters against the
  tb (counter 17 counts writes waiting for the port, unchanged by WR4).
- New: bench c must show single writes in 4 clocks (`sk_w4` > 0 with WR4,
  0 without); the tb fails a bench c run with WR4 on and `sk_w4` = 0.
- Mutants: (a) WR4 steps pair writes too (`!k_wpair` dropped): the
  `ks_chg` check must fail (k_long_ack set on the step's own edge);
  (b) the select clear not gated (`k_din_psel <= 0` on a WR4 step): the
  `ks_chg` check must fail.

## Numbers

bench c -1.1% (64,920 -> 64,188), op -0.45%; every other bench unchanged.

## Acceptance

Sims pass; a 12x seed passes; the 20x ratio is reported and no worse than
1.55x; Glen: the usual benchmarks at three speeds, both Frontier
timedemos, a warm run at 20x.

## Fallbacks and stop conditions

- If no seed in 16 passes and the misses are on `k_fast` -> step
  decision: register `k_fast` a clock earlier is not possible (the
  address is final only at DECIDE); report and leave WR4 off.
- Stop if any existing check fails with WR4 on.

## Log

(the builder writes here)
