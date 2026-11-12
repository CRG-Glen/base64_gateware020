# Step 15b: timing margin for the fetch predictor

Status: ready to build. Branch: `step15b-predictor-timing`, from
`step15-fetch-predictor` (after `tooling-build-seeds` if that is done:
branch from it then). No change in behaviour is intended except the one
named in change A.

## Goal

Step 15 passes timing on 1 seed of 9, and its kernel -> logic class (3T,
34.9 ns allowed) went from 31.6 ns in step 14b to 34.1 ns on the passing
seed and up to 36.6 ns on others. Get that class back to about 32 ns and
at least 3 of seeds 1-9 passing, so the step is safe at 14x and 16x and
the next feature has room.

## Background

Read in `rtl/base64_tg68/tg68_bus.v`: the block comment "FETCH PREDICTOR
(step 15)", the wires `fp_hit0` / `fp_hit` / `k_pcand`, the predictor
pipeline at the top of the big `always` block, and the `Q_DECIDE` case.
`docs/HISTORY.md` has the step 15 bullet.

How DECIDE decides today (one priority chain):

```
if (internal_step)      step
else if (fp_hit0)       predicted fetch: step if bus_free
else if (k_pf_ok)       prefetch-buffer hit -> FINISH
else if (bus_free && ack_idle && (!dp_busy || (k_look && !pf_wait)))
                        start a cycle: a_r, fc_r, eRWn, dp_fast, q, ...
                          k_look            -> CCMP (+ speculative read for data)
                          k_fast && !k_nwr  -> posted write (pw_upd, ...)
                          k_fast            -> direct read
                          else              -> SETUP (old-route bus cycle)
```

`fp_hit0` is `fp_v && ic_on && k_bs==00 && !k_skip && k_addr[31:1]==fp_ac
&& !k_pcand`. Everything after it in the chain is gated by "not fp_hit0",
so every register DECIDE loads now waits for:

- a second 31-bit compare on the kernel's address (the first is
  `k_pf_hit`, against `pf_a`);
- **`k_pcand` = `k_long_cand && !k_addr[1]`**. `long_cand` is the kernel's
  latest output (it waits for the address's low bits; kernel -> logic got
  1.3-2 ns worse when step 10 turned it on for instruction fetches).
  Before step 15 it only fed data registers (`k_long_ack`, `dp_pair`,
  `rp_go`); now it gates `q`, `pw_upd`, `dp_fast`, `fc_r`, `k_din`.

The failing kernel -> logic paths on four seeds all run kernel address ->
... -> `q` / `pw_upd` / `dp_fast` / `fc_r`. The planner's reading is that
`k_pcand` in the chain is the main cause and the second compare the rest.
That is a hypothesis: the changes below are ordered so the measurements
say which is true.

### Baseline (step 15, commit 3c13c05, seeds from one synthesis)

| Seed | Worst 1T slack | Worst multicycle slack | Worst failing class |
| --- | --- | --- | --- |
| 1 | -0.84 | +1.21 | adapter ctrl -> logic (q -> ic_wt) |
| 2 | -0.67 | -0.87 | kernel -> logic (-> pw_upd) |
| 3 | -0.21 | +1.52 | clkena -> kernel |
| 4 | +0.39 | -1.53 | kernel -> logic (-> q, pw_upd) |
| 5 | -0.45 | -1.73 | kernel -> logic (-> pw_upd, dp_fast, fc_r) |
| 6 | -1.37 | -0.18 | adapter ctrl -> logic (dp_busy -> q) |
| 7 | -0.62 | +1.06 | icache/direct -> logic (ic_qt_e -> dp_req_i) |
| 8 | +0.60 | +0.40 | PASS; kernel -> logic 34.06 ns |
| 9 | -1.64 | -0.89 | clkena -> kernel |

Numbers that must not move unless a change below says so (clocks of the
timed pass, `sh sim/run.sh bench <name>`):

| c | copy | read | scatter | readoff | chip | wrfast | wrmix |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 65640 | 9432 | 6204 | 3744 | 11316 | 31440 | 7464 | 31572 |

## The changes, one at a time

Do A, build and measure nine seeds; then B on top, measure; then C on
top, measure. Record each table in the log. Commit each separately.

### A. Take the pair test out of the predicted fetch

1. `fp_hit0`: delete `&& !k_pcand`. A fetch the kernel offers as a pair
   is then answered by the predictor as a single word, with `k_long_ack`
   left at 0, and the kernel fetches the second word as its next step (the
   kernel runs the ordinary 16-bit sequence when a pair is not
   acknowledged; this is what happens today on every cache miss in ROM).
2. The address load in the pipeline: `k_addr[31:1] + (k_pcand ? 31'd2 :
   31'd1)` becomes `k_addr[31:1] + 31'd1` for both `fp_a` and `fp_ac`.
3. Update the comment block (the sentence "A fetch the kernel offers as a
   pair is left to the normal lookup") and README's step 15 text to say
   that a predicted fetch is always a single word and that pairs still
   come from the normal lookup when the prediction misses.

Behaviour change: instruction-stream pairs (32-bit immediates, abs.L)
that follow sequentially are fetched as two predicted words (8 clocks)
and no longer as one pair (5 clocks). Expected cost: bench c about +225
clocks (65640 -> about 65865, 0.3%); the other benches should not move
(check; if one moves by more than 1%, stop and report).

Tests: all sims and benches pass. `fastmem` prints "instruction-stream
pairs: N from the cache, M from the SDRAM" (6 and 2 today); N is not
checked and will fall, because sequential pair words are now predicted
singles. Record the new line in the log. The `fn32` result checks
(0x8194) must still pass: they prove a 32-bit immediate and an abs.L
address arrive intact whichever way they are fetched.

### B. Split DECIDE into a fetch branch and a data branch

Purpose: registers that only data cycles load must not depend on
`fp_hit0`, and the fetch branch must not carry data-only terms.

Rewrite the `Q_DECIDE` case as below. The statements inside each branch
are today's, moved, not changed; put the shared "start a cycle"
assignments in a Verilog `task` (as `step` is) so they are not written
twice.

```
oRESETn <= k_nresetout;
if (internal_step) begin
    if (cnt_ok) step();
end else if (k_bs == 2'b00) begin
    // ---- instruction fetch ----
    if (fp_hit0)       begin if (bus_free && cnt_ok) step(); end
    else if (k_pf_ok)  <prefetch-buffer hit, as today>
    else if (bus_free && ack_idle && (!dp_busy || (k_look && !pf_wait))) begin
        cyc_begin();                      // a_r, fc_r, eRWn, tmr, dp_fast, cyc_start, dec_r, dp_spec, k_din_psel
        if (k_look)        <lookup: q <= CCMP, k_din_sel, k_long_ack; NO speculative read (that is for k_bs == 10)>
        else if (k_fast)   <direct read>
        else               q <= Q_SETUP;
    end
end else begin
    // ---- data read or write ----
    if (k_pf_ok)       <prefetch-buffer hit, as today>
    else if (bus_free && ack_idle && (!dp_busy || (k_look && !pf_wait))) begin
        cyc_begin();
        if (k_look)                 <lookup, with the speculative read>
        else if (k_fast && !k_nwr)  <posted write, as today, WR4 code included>
        else if (k_fast)            <direct read>
        else                        q <= Q_SETUP;
    end
end
```

Notes:
- A fetch is never a write, so the fetch branch has no posted-write arm.
  Keep the `k_din_psel` clear exactly as it is today (its condition
  mentions WR4; in the fetch branch it is simply `k_din_psel <= 1'b0`).
- `fp_hit` (with the bus-state terms) stays as a wire: the test benches
  and the `fp_chk_bad` check use it.
- This must be cycle-for-cycle identical: every bench clock count as
  after change A, and the `top`/`fastmem`/`bus` output lines unchanged.

### C. `dp_fast` under `dec_r`

`dp_fast <= k_fast` is loaded in the cycle-start assignments. Move it to
the block that loads on every DECIDE clock (`if (dec_r) begin oEdb <=
...`, where `rp_go` and `rp_al` already are), outside the `!dp_busy`
condition. It is read only in CCMP and CFREE, by the cycle that DECIDE
started, so the last DECIDE clock's value is the right one; a predicted
fetch, a prefetch hit and an internal step never reach CCMP. Add a
sim-only assertion in the `ifndef YOSYS` block at the end of the module,
in the style of `cc_bad`: in CCMP and CFREE, `dp_fast` must equal what
the old code would hold. Do that with a shadow register `dp_fast_ref`
(sim only) loaded exactly where `dp_fast` was loaded before, and count
mismatches in `dpf_bad`; make both test benches fail on it (next to the
`cc_bad` line).

## Measuring

For each of A, A+B, A+B+C: synthesize once in a git worktree under
/home/user, run seeds 1-9 (`build.py full --seed 1 --seeds 9` once the
tooling plan is done; otherwise nextpnr and check_timing by hand into one
folder per seed, four at a time), and record seed, worst 1T slack, worst
multicycle slack, worst class. Check each new or changed register exists
in the synthesized json when it is meant to be a copy (none are added
here).

## Acceptance criteria

- All three sims, `bench sd` and the eight benches pass; bench clock
  counts as in the table above, except bench c after change A (about
  +0.3%).
- The step 15 mutants still fail the benches (re-run at least: no
  `fp_bad` kill in the clock after the step; word from the wrong bank;
  `fp_v` not cleared when the address loads). `docs/HISTORY.md`, step 15
  bullet, and the commit messages on `step15-fetch-predictor` describe
  them.
- At least 3 of seeds 1-9 pass `check_timing.py` at 12x, and on the
  passing seeds kernel -> logic is 33 ns or less.
- Choose the passing seed with the largest worst-1T slack; score it at
  14x and 16x. Package `bitstreams/step15b_fpred/` as CLAUDE.md
  describes, update README (bitstream table row, the step 15 text, the
  timing section) and `plans/README.md`, and give Glen the links with
  the same test list as step 15.

## Fallbacks, in this order

1. If A alone meets the criteria, still do B and C if they are neutral or
   better; drop either one that makes the seed table worse (revert that
   commit, say so in the log).
2. If kernel -> logic is fixed but fewer than 3 seeds pass because of
   other classes (clkena -> kernel, adapter ctrl -> logic into `q`),
   run seeds 10-18 as well. If at least 3 of 18 pass, package the best
   and report the pass rate; that is as good as steps 12-14 were.
3. If kernel -> logic is still above 34 ns after A+B+C on most seeds,
   stop and report with the three tables and the worst path of each
   failing seed (start register, end register, and the names it passes
   through). Do not try further restructuring on your own.

## Stop and report if

- a bench clock count moves that the plan says must not;
- a sim fails in a way these changes do not explain;
- the `fn32` checks fail after change A.

## Log

(build model: record the seed tables and what was kept here)
