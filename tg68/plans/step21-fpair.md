# Step 21: 32-bit operands as one pair again (the predictor stands aside)

Status: **built, see log**. Branch `step21-fpair`, from `step20-wr4`.
Planned and built by the same model.

## Goal

When the CPU core offers an aligned 32-bit pair on an instruction fetch
(a 32-bit immediate or absolute address, `k_long_cand && !k_addr[1]`),
the fetch predictor leaves it to the normal cache lookup, which answers
both words in one 5-clock step, against two predicted 4-clock words; and
the next prediction is 2 words on. This is step 15's behaviour, which
step 15b took out for timing (its change A).

## Background

- `tg68_bus.v`: `fp_hit0` (the predicted-fetch test) and the `fp_a` /
  `fp_ac` loads under `dec_r`. Step 15 had `&& !k_pcand` in `fp_hit0` and
  `+ (k_pcand ? 2 : 1)` in the loads; 15b's change A removed both because
  `k_long_cand`, the kernel's slowest output, then gated every register
  DECIDE loaded (kernel -> logic missed on 4 of 9 seeds).
- Since then: 15b's change B split DECIDE into a fetch and a data branch,
  so `fp_hit0` gates only the fetch branch; router1 (exp-router1) gives
  1-1.5 ns more 12x slack (step 20: +1.24 ns, 16 of 16 seeds).
- Evidence the loss is real on hardware: SysInfo 12x / 16x step 15 11179
  / 14925; 15b 10797 / 14412; step 20 (with the barrel shifter's +3%)
  11117 / 14838, still below step 15.

## The change

1. `FPAIR` parameter, default `` `FPAIR_DEFAULT `` (1); `-DFPAIR_DEFAULT=0`
   simulates step 20.
2. `k_pcand = FPAIR && DP32_ACK && k_long_cand && !k_addr[1]`;
   `fp_hit0 ... && !k_pcand`; `fp_a` / `fp_ac` `<= k_addr + (k_pcand ? 2 :
   1)`.

## Tests

- bench c fails if FPAIR and "instruction-stream pairs" (`sk_fpair`)
  disagree, or if any sequential fetch is not predicted (`sk_f5seq`).
- The existing checks: `fn32` (8194: a 32-bit immediate and an abs.L
  operand arrive intact), the predicted-fetch checks, the shadow check.
- Mutants: (a) `!k_pcand` out of `fp_hit0`; (b) `fp_a` + 1 after a pair.

## Acceptance

Sims pass; a 12x seed passes (router1); 20x ratio reported; Glen: SysInfo
at three speeds (the number this is for), the usual set.

## Fallback

If no seed in 16 passes with misses through `k_long_cand` -> `fp_hit0`:
leave FPAIR off and report; the next idea is deciding "may be a pair"
from registers a step earlier.

## Log

- bench c 64,188 -> **63,900** (-0.45%): 75 instruction-stream pairs, 0
  sequential fetches unpredicted. FPAIR=0 gives step 20's 64,188.
  fastmem: "instruction-stream pairs: 6 from the cache, 2 from the SDRAM"
  (as step 15; 15b's change A had lowered the 6), `fn32` passes.
- Mutants: (a) bench c FAIL: 0 pairs, 75 sequential fetches unpredicted;
  (b) bench c FAIL: 75 pairs, 75 unpredicted.
- Regression: bus, top, fastmem; top PERF=0; CAL_TEST, CAL_DRIFT;
  S15_DEFAULT=0, S17_DEFAULT=0, FPAIR_DEFAULT=0 (each bus, top, fastmem);
  benches c, coff, copy, read, scatter, readoff, chip, wrchip, wrfast,
  wrmix, sd, op; c and copy at 20x: all PASS once the new bench c check
  was limited to 12x with the caches on. (As first written it failed
  bench coff, where the predictor is off, and bench c at 20x, where the
  tb's step-gap counters tick on the 12x clock. The design was right.)
