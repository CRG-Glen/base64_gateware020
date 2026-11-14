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

## Hardware result (Glen, A500+): **20x works**, at all three speeds

Seed 10, `_fast`, 1.54x the worst-case model at 20x.

| | 12x | 16x | 20x | 20x vs 16x | 20x vs 18x (exp-18x) |
| --- | --- | --- | --- | --- | --- |
| SysInfo caches on | 10776 | 14379 | 18024 | +25.3% | +11.1% |
| SysInfo caches off | 4461 | 5440 | 7499 | +37.9% (spread) | +13.7% |
| AIBB MemTest on / off | 16.60 / 8.48 | 21.03 / 10.59 | 26.16 / 13.20 | +24.4% / +24.6% | +10.9% / +13.1% |
| xSysInfo on | 18430 | 24407 | 29009 | +18.9% | +7.3% |
| xSysInfo off | 9743 | 12117 | 14486 | +19.6% | +4.1% |
| xSysInfo fast RAM on / off MB/s | 23.69 / 21.17 | 29.58 / 26.21 | 36.85 / 32.73 | +24.6% / +24.9% | +10.9% / +10.9% |
| SD (xSysInfo) MB/s | 2.0 | 2.2 | 2.7 | +23% | +8% |
| Frontier timedemo min / max / avg fps | 9.5 / 70.4 / 26.2 | 11.8 / 73.3 / 31.1 | 13.9 / 75.6 / 33.8 | avg +8.7% | avg +4.3% |

20x is 25% faster than 16x on CPU- and fast-RAM-bound work, in line with
the clock (+25%), and +67% over 12x (SysInfo). Frontier, bound by the
7 MHz Chip RAM bus, gains +8.7%. SysInfo caches off at 12x (4461) is its
usual spread (the caches-off logic is clock-for-clock identical to 15b).

## For the planner: a release with the fast speeds

- 20x needs the chip 1.54x faster than the worst-case model, 18x 1.42x;
  both run. 16x+20x can share ONE PLL: VCO 567.5 MHz, CLKOP_DIV 5 =
  113.5 MHz, CLKOS_DIV 4 = 141.9 MHz. The other PLL then gives one of
  14x (VCO 695, /7) or 18x (VCO 766, /6); 14x and 18x cannot share (VCO
  894 MHz, over the 800 MHz limit), nor can a 567.5 MHz VCO make either.
  So two PLLs give at most four speeds: 12x (the pin) + 16x + 20x + 14x
  or 18x. Note: moving 16x onto the shared PLL changes the 16x clock's
  source, which has run on the board since step 13; it needs a test.
- Both experiments needed only tRFC stretched in the SDRAM (+1 at 18x,
  +2 at 20x, for the sim model's 65 ns; the board's -6 part needs 60).
- Not known: long warm runs at 20x, and `speed20` status after one
  (samples moved, swaps). Worth asking before a release.
- Beyond 20x: 22x (156 MHz) would need about 1.70x the model, and the
  SDRAM's 166 MHz limit at CL3 comes close (6.4 ns clock, 5.4 ns access).

