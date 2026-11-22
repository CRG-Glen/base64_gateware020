# Experiment: 22x (156.07 MHz), and 12x / 16x / 20x / 22x in one build

Status: **built, waiting for Glen's test**. Branch `exp-22x`, from `step21-fpair`. Planned and
built by the same model. Glen: "If 22x works I'd ideally like to package
12x, 16x, 20x and 22x", from the current clock or from the Amiga's 7 MHz.

## The clocks

The LFE5U-25F has two PLLs; each has one VCO (400-800 MHz) and up to four
outputs dividing it. From the 12x pin (85.13 MHz, as now):

| PLL | CLKI_DIV / CLKFB_DIV | VCO | outputs |
| --- | --- | --- | --- |
| A (`u_pll14`) | 3 / 5 (feedback CLKOP) | 567.5 MHz | CLKOP /4 = 20x (as now), **CLKOS /5 = 16x** |
| B (`u_pll16` -> `u_pll22`) | 6 / 11 (feedback CLKOP) | 624.3 MHz | CLKOP /4 = **22x** |
| none | | | 12x = the pin |

16x moves from its own PLL to PLL A's second output, which frees PLL B
for 22x. From the Amiga's 7 MHz instead (a later build, same RTL with a
define, as `exp-7m-pll`): A x80 (CLKI_DIV 1, CLKFB_DIV 20 on 20x), B x88
(CLKFB_DIV 22 on 22x).

## The change

1. `clkgen.v`: PLL A gets CLKOS (16x); PLL B is 22x; a fourth source in the
   glitch-free multiplexer (`sel` 3 = 22x); `lock22`; sim model N = 22.
   16x's lock is PLL A's lock.
2. Top level: speed code 3 = 22x. `ph_top` 21, `ph_half` 11, `ms_top`
   156070, `spd_hold2` and `spd_lox` on, CL3, `spd_rfc` at 20x and 22x
   (more if the SDRAM model asks). `sp_ok` checks the 22x PLL's lock.
   `spd_stat` multiplier 22; `+$F00C` bit 8 = 22x PLL locked (its high
   byte was free).
3. `sdram_ctrl.v` (TG68:): whatever extra clocks the model reports at 22x
   (IS42S16160J-6 at 6.41 ns: tRCD/tRP 18 ns, tRAS 42 ns, tRFC 60 ns).
4. `turbomem_zii.v`: `$5B16` = 22x (speed code 3).
5. `sw/speed`: `speed 22`, 1.5; "Available" from the lock bits.
6. Sims: the fastmem switch test visits 22x as well; the benches run at
   22x (`BENCH_ASD="--defsym SPEED22=1"`) with no SDRAM model violation.

## Risks (for Glen)

- Logic timing: about 1.60x the worst-case model at 22x (step 21's 1.47x
  at 20x scaled); step 17 ran at 1.58x at 20x.
- **SDRAM read data**: 5.4 ns access time in a 6.41 ns clock, ~1 ns
  before the capture edge less the board's delays. If 22x fails, the
  first suspect is fast RAM tests.
- A power cycle always returns to 12x.

## Acceptance

Sims pass at every speed; 12x passes timing; 16x / 20x / 22x ratios
reported (seed chosen by the lowest 22x ratio). Glen: does 22x run; then
the usual set at all four speeds.

## Log

- clkgen: PLL A CLKOS /5 = 16x, PLL B = 22x (`u_pll22`, `lock22`); a fourth
  source in the switch. Top: speed code 3; `+$F00C` bit 8 = 22x locked.
  turbomem: `$5B16`. speed 1.5 (vamos: with and without a 22x lock).
- **SDRAM at 22x**: the model reported tRFC (64.1 ns against its 65) and
  tRP (19.2 against 20) violations; the -6 part needs 60 and 18, but as
  at 20x the model's limits are met: `spd_xl` (new run-time setting,
  config class in check_timing.py) gives tRP + 1 and tRFC + 1 more at 22x
  only. No violation after, in any bench at any speed.
- Regression, all PASS: bus, top, fastmem (switch test 12 -> 16 -> 20 ->
  22 -> 12: 4 switches, 3 mode loads), top PERF=0, CAL_TEST, CAL_DRIFT,
  every bench at 12x, c/copy/read/scatter at 16x, 20x and 22x, coff at
  22x. bench c 63,900 / 48,204 / 38,676 / **35,232** (12x / 16x / 20x /
  22x, clk12 ticks): 22x is 8.9% faster than 20x; copy 6,120 -> 5,628.
- `--pll7m` (TG68_PLL7M): both PLLs from the Amiga's 7 MHz pin (A x80,
  B x88), as `exp-7m-pll` did. Sims pass (fastmem's 22x status shows the
  unused rising 7M sample moving, bit 14: masked for this build only);
  bench c at 22x 35,220.
- Timing (pin build, router1): **16 of 16 pass** at 12x. Scored at 22x
  (156.07 MHz): seed 15 **1.646x** (16x 1.198x, 20x 1.497x, 12x +1.08 ns),
  3 1.652x, 9 1.659x. The head (after `--pll7m` was added) synthesizes to
  the same netlist (17,956 cells, identical). Shipped seed 15:
  `bitstreams/exp_22x/`.
