# Experiment: a 20x clock (141.88 MHz), in place of 14x

Status: **built**, test bitstream `bitstreams/exp20x/` (seed 10), waiting for Glen's test. Built on Glen's request after 18x worked (no separate plan: the
same change as `exp18x.md`, one speed higher). Branch `exp-20x`, from
`exp-18x`. **Experimental: never a release, never merged.**

## What changed against exp-18x

- `clkgen.v`: the second PLL x5/3 (CLKI_DIV 3, CLKFB_DIV 5, CLKOP_DIV 4,
  VCO 567.5 MHz, PFD 28.4 MHz); sim model N = 20.
- Top level, speed code 1: `ph_top` 19, `ph_half` 10, `ms_top` 141858;
  `ms_top` / `ms_div` widened to 18 bits (141858 does not fit in 17).
  Register multiplier 20. `spd_hold2`, `spd_lox`, CL3 as at 18x.
- `turbomem_zii.v` (TG68:): key `$5B14` = 20x; 14 and 18 not taken.
- `sdram_ctrl.v` (TG68:): tRFC + **2** clocks at 20x (`rfc_long`). The
  model reported tRFC only (as at 18x): 6 + overhead = 56.4 ns, +1 =
  63.4 (enough for the board's -6 part, 60 ns, not for the model's 65),
  +2 = 70.5 ns. No other SDRAM parameter was flagged.
- `speed` 1.4x: 12 / 20 / 16; bench programs' SPEED18 option now
  switches to 20x.

## Sims

bus, top, fastmem (12x -> 16x -> 20x -> 12x, 81E0 = $0714), CAL_TEST,
CAL_DRIFT, bench sd, the eight 12x benches (unchanged from 15b) all pass.
At 20x, timed-pass clocks (clk12 ticks, so time) and against 18x: copy
6168 (18x 6780, +9.9%), read 4032 (4416, +9.5%), scatter 2556 (2772,
+8.5%), c 39804 (44160, +10.9%); no SDRAM model violation.

## Risks (for Glen)

- Timing: about 1.58x the worst-case model at 20x (18x worked at 1.42x).
- SDRAM read data at the pins: 5.4 ns access time in a 7.05 ns clock.
- The kernel's step: 4 clocks = 28.2 ns at 20x for paths of ~40 ns in
  the worst-case model (1.42x; the worst class is higher).
- SD card SCLK is faster again (the software's divider is unchanged).

## Log

- Seeds 1-18 (`--keep-sdf`): **4 pass at 12x**: 6 (+0.36 / +1.40), 9
  (+0.50 / +1.47), 10 (+0.77 / +2.19), 16 (+0.26 / +1.14). Scored at 16x /
  20x: 6 1.279x / 1.599x, 9 1.264x / 1.580x, **10 1.233x / 1.541x**
  (icache/direct -> logic), 16 1.291x / 1.613x. Shipped seed 10: the
  lowest 20x ratio, and also the most 12x slack and the lowest 16x ratio
  of any build so far.
- `bitstreams/exp20x/`: `_plain`, `_fast`, `speed20` (speed 1.4x),
  `README.txt`, timing at 12x, 16x and 20x.
