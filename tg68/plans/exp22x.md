# Experiment: 22x (156.07 MHz), and 12x / 16x / 20x / 22x in one build

Status: **both builds run at 22x on Glen's A500+**, benchmarked; they behave the same (the 7M sample note applies to both). Branch `exp-22x`, from `step21-fpair`. Planned and
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
- `--pll7m` build (same netlist otherwise), seeds 1-16: **16 of 16 pass**.
  Seed 12: +1.41 ns, 1.161x / 1.451x / **1.596x** at 16x / 20x / 22x; 4
  1.631x; 11 1.638x. Shipped seed 12: `bitstreams/exp_22x_7m/`.
- **Glen: the 7 MHz-fed build (seed 12, 1.596x at 22x) has run
  successfully for some time at 22x.** So 22x works on his board (the
  furthest past the worst-case model yet: 1.60x, against 1.58x before),
  and the PLLs run from the Amiga's 7.09 MHz, below their rated 8 MHz
  input (the question exp-7m-pll was built for). Benchmarks at the four
  speeds, and the pin-fed build, not reported yet.
- **Glen's benchmarks, 7 MHz-fed build, seed 12** (caches on / off):

  | | 12x | 16x | 20x | 22x |
  | --- | --- | --- | --- | --- |
  | SysInfo | 11526 / 5223 | 15379 / 6528 | 19238 / 8145 | **21165 / 9032** |
  | AIBB MemTest MB/s | 16.69 / 8.33 | 21.13 / 10.39 | 26.32 / 12.94 | 28.90 / 13.86 |
  | xSysInfo | 18958 / 9949 | 25115 / 12141 | 31336 / 15252 | 34472 / 15929 |
  | xSysInfo fast RAM MB/s | 23.71 / 21.17 | 29.58 / 26.22 | 36.87 / 32.78 | 40.36 / 35.74 |
  | SD MB/s | 2.0 | 2.2 | 2.7 | 3.0 |
  | Frontier timedemo avg fps | 27.8 | 32.1 | 35.0 | 36.1 |
  | Frontier CPU timedemo avg fps | 33.8 | 44.8 | 56.0 | 61.4 |

  12x / 16x / 20x equal step 21's (16x from the shared PLL and the 7 MHz
  input change nothing); 22x over 20x: SysInfo +10.0%, CPU timedemo
  +9.6%, fast RAM +9.5%, SD +11%, Amiga timedemo +3.1%.
- **Open point:** `speed` after the 22x benchmarks reported both 7M
  samples moved since the calibration (bits 14 and 13; bit 13 is the
  falling sample, the one in use), bit 15 (aligner slip) clear. The
  register was $6716 (Glen confirmed; "22x 156.1 MHz"). No automatic
  swap line: the stream in use moved, but never the AUTO_N (4) times
  that trigger a swap, so only occasionally. Asked:
  the pin-fed build at 22x for comparison (is the movement the 7 MHz
  PLL input's jitter at x88, or 22x's own thinner capture margin).
- **Pin-fed build (seed 15) at 22x** (Glen): SysInfo 21163 / 22.09 MIPS
  (the 7 MHz-fed build: 21165); after a demo `speed` reports the same as
  the 7 MHz-fed build: both 7M samples moved, $6716, no slip, no swap.
  So the occasional movement of the sample in use is 22x's own (3.2 ns
  between the system clock's edges), not the 7 MHz PLL input: the two
  clock sources behave the same. The PLL also runs from 7.09 MHz, below
  its rated 8 MHz input, with no visible difference.
- **7 MHz-fed build at 22x, a longer session** (Glen; first written here
  as the pin-fed build, corrected): `speed` reported one automatic swap
  since power-on (the sample in use moved AUTO_N = 4 times; step 14's
  swap then moved to the other stream), no slip, the machine fine. None
  reported on the pin-fed build's shorter run. So no evidence either way
  between the two clock sources: at 22x the sample in use drifts now and
  then on both, and the swap handles it as designed.
