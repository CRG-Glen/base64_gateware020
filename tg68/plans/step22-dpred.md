# Step 22: data-cache hits in 4 clocks (a data-read predictor)

Status: **planned** (23 November 2026). Branch `step22-dpred`, from
`step21-fpair`. Planned by the building model (no planner any more).

## Goal

A single-word data read from the data cache steps the CPU in 4 clocks
instead of 5 when its address is the one predicted: the word after the
last data read (+1 word, +2 after a pair). The same trick as the fetch
predictor (step 15), for data.

## Measured first (bench c, step 21, 63,900 clocks)

| 5-clock cache hits | count | predictable by | caught | saving |
| --- | --- | --- | --- | --- |
| data reads | 1,534 | last data read + 1 word (+2 after a pair) | 758 (49%) | ~1.2% |
| data reads | | the same word again | 156 (10%) | ~0.2% |
| fetches after a jump | 986 | 64-entry branch-target table | 882 (89%) | 1.4% gained, 0.6% lost: **net 0.8%** |

The branch-target table is worse than it looks: the instruction cache can
read one predicted address per step, so predicting a jump target gives up
the sequential prediction, and 378 sequential fetches would have been
redirected wrongly (each 1 clock lost). A wrong data prediction costs
nothing (the normal lookup still runs, as with the fetch predictor). So
the data side first; the branch-target table is not planned.

On hardware (step 18's counters, Frontier CPU timedemo at 20x): 278M
data-cache hit steps; at half predicted, ~0.8% of the time. **Expected
gain: about 1%** (bench c 1.2%; Frontier ~0.8%; SysInfo unknown).

## Background (tg68_bus.v)

- The fetch predictor: `fp_a` / `fp_ac` loaded under `dec_r` on a fetch;
  in the step clock (`fp_rsel_n` low) the RAMs read `fp_a`; E2:
  `k_din_fp`, `fp_tq`, `k_din_psel`; E3: `fp_v` (tag match, no
  `fp_kill`); DECIDE: `fp_hit0` (`k_addr == fp_ac`) -> `step()`.
- **The data cache RAMs read at `ic_ra`**, the instruction cache's
  address: in the step clock that is `fp_a`. A data prediction needs the
  data cache to read its own predicted address then: `dc_ra =
  !fp_rsel_n ? dp_a : k_addr`. **Step 16 gave the data cache its own read
  address (`dc_ra`) and kernel -> logic got much worse (0 of 18 seeds
  under router2).** That is this step's main timing risk; router1 has
  1.2-1.5 ns more slack than step 16 had.
- The kernel has one `data_in`. The predicted fetch word reaches it
  through `k_din_psel` (set at E2, two clocks before any step that uses
  it). At E2 the adapter does not know whether the next cycle is a fetch
  or a data read, so a data prediction needs its own word register
  (`k_din_dp`) and the choice between the two must not change in the
  clock before the kernel samples (tb check `ks_chg`). Choose by the
  kernel's bus state `k_bs` (fetch 00, read 10): a kernel output, final
  SETTLE clocks after a step and unchanged until the next one, so
  `k_bs -> data_in mux -> kernel` is a kernel -> kernel path (4T).

## The change, in order

1. `DPRED` parameter, `` `DPRED_DEFAULT `` (1).
2. `dp_a` / `dp_ac` (compare copy, different power-on value): loaded
   under `dec_r && k_bs == 2'b10`: `k_addr + (k_rpair ? 2 : 1)`.
   `dp_v`, `dp_kill`, `dp_tq`, `k_din_dp` as the fetch predictor's.
   `dp_bad = dc_we && dc_wa == dp_a's index` (any data-cache write to
   the predicted entry: a posted write's update, a fill, the flush).
3. `dc_ra` as above, own register select copy if needed (`fp_rsel_n`
   style, a different power-on value).
4. The kernel's data_in: where `k_din_psel` selects `k_din_fp` today,
   select `k_bs[1] ? k_din_dp : k_din_fp`.
5. DECIDE data branch: `dp_hit0 = DPRED && dp_v && dc_on && k_bs ==
   2'b10 && k_addr[31:1] == dp_ac && !k_rpair` (a pair read keeps the
   normal lookup, as step 21 does for fetches); then `bus_free && cnt_ok
   -> step()`. Everything else as today: any other DECIDE outcome drops
   `dp_v` and the select.
6. Timing classes: `dp_ac` 2T like `fp_ac` (tb assertion: it never
   changes on the edge into a clock with `dp_v` set).

## Tests

- A sim check like `fp_chk_bad`: on every predicted data read, the RAMs'
  own read of `k_addr` on the edge into DECIDE must show the same tag and
  word; and the shadow check (every word the kernel gets against the
  CPU's writes) covers predicted words too (`chk_word` at the step).
- test_top.s: a loop reading an array (predicted), a read after a write
  to the predicted word (must see the new value), a pair read, a byte
  read, reads across a cache-line alias.
- bench c: predicted data reads > 0 with DPRED, 0 without.
- Mutants: no `dp_kill` (a write between the prediction and the step:
  stale data); `k_bs` select inverted; `!k_rpair` dropped.

## Numbers

bench c about -1.2% (63,900 -> ~63,150); op and copy small; others
unchanged.

## Acceptance

Sims pass; 12x passes on some seed of 16 (router1); 20x ratio <= 1.55x;
Glen's usual set, with SysInfo and the Frontier CPU timedemo the ones to
watch.

## Fallbacks and stop conditions

- If timing fails through `dc_ra` (step 16's failure): keep the shared
  `ic_ra` and predict only when the fetch predictor has nothing to read
  (no: it always does). So the fallback is to stop and report.
- Stop on any stale-data report from the shadow check.

## Log

(the builder writes here)
