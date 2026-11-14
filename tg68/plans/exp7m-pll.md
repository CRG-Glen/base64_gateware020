# Experiment: the FPGA's PLLs fed from the Amiga's 7 MHz clock (stage 1)

Status: planned and built in one session on Glen's request. Branch
`exp-7m-pll`, from `main` (v2.0). **Experimental: never a release.**

## Goal

Find out whether the ECP5's PLLs lock and run cleanly on the Amiga's 7.09
MHz clock (pin C7, `clk_7m`, buffered by a 74LVC1G17), which is below the
PLL's rated 8 MHz minimum input. Today they are fed from the ICS570B's
85.13 MHz (pin L1), itself a x12 PLL on the 7 MHz clock: a PLL driving a
PLL. Stage 1 moves only 16x and 20x; 12x stays on the ICS570B pin, so the
board always powers on and boots as v2.0 does, and a PLL that does not
lock just makes `speed` refuse that speed (the sequencer already checks
the lock bits, `sp_ok`).

Expected: no speed change (the clock frequencies are identical), possibly
less jitter. Unknown: lock below spec, and the 7 MHz clock's quality.

## Change

1. `clkgen.v`: new input `clk_7m`. Both PLLs take CLKI from it:
   - 20x (`u_pll14`): CLKI_DIV 1, CLKFB_DIV 20, CLKOP_DIV 4 (VCO 567.5
     MHz, PFD 7.09 MHz).
   - 16x (`u_pll16`): CLKI_DIV 1, CLKFB_DIV 16, CLKOP_DIV 5 (VCO 567.5).
   - `FREQUENCY_PIN_CLKI="7.094"`. Other attributes unchanged.
   - Sim model: groups of 12 input cycles (as now), N x 12 output cycles
     per group (`pll_model` gets a per-group count parameter).
2. Top level: `.clk_7m(clk_7m)` on `u_clkgen`. The pin also keeps its
   fabric loads (the 7 MHz sampling).
3. Nothing else: the mux, the speed sequencer and the calibration are as
   in v2.0. 12x is unchanged.

## Tests

- bus, top, fastmem, CAL_TEST, CAL_DRIFT, bench sd and the 12x benches
  as v2.0 (identical clock counts at 12x); copy / read / scatter / c at
  20x and 16x with no SDRAM violation.
- The tools accept the PLL settings (nextpnr, ecppack). If they reject the
  7 MHz input, stop and report.

## Build and deliverable

18 seeds, keep the sdf; ship the 12x-passing seed with the lowest 20x
ratio. `bitstreams/exp7m_pll/` with `_plain`, `_fast`, `speed` (v2.0's
1.4, unchanged: the speed codes are the same), timing at 12x/16x/20x and
a README. Glen's tests: does `speed` show 16 and 20 available (both PLLs
locked)? Switch to each; benchmarks against v2.0; a long warm run at 20x;
`speed` status after it (samples moved, swaps). If a PLL does not lock,
`speed` will list only 12 (and the other speed if that PLL locked).

## Stage 2 (not built)

12x from a PLL too (16x and 20x on one PLL, VCO 567.5 /5 and /4; 12x on
the other, VCO 510.8 /6), so the ICS570B is no longer used. Riskier: if
the 12x PLL does not lock, the board does not start (re-flash v2.0).

## Log

(build)
