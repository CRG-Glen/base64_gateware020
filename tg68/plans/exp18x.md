# Experiment: an 18x clock (127.7 MHz), in place of 14x

Status: ready to build. Branch: `exp-18x`, from `step15b-predictor-timing`.
**Experimental: never a release, never merged.** It answers one question
on Glen's board: does the design run at 18x, and so how much real margin
does the silicon have over the worst-case timing model?

## Why this, and why now (the planner's reasoning, agreed with Glen)

- Margin work has stopped paying. Step 16 (two more restructures) made
  things worse; placement noise is now larger than what a restructure
  gains. Step 15b ships with 5 of 18 seeds passing, and `build.py` runs
  18 seeds in 80 minutes, so new features can still be built.
- What is left to gain per CPU step is small (data-cache hits in 4
  clocks: 2.3%; word writes: 1%). A faster clock gains on everything
  that is not bound by the 7 MHz bus: 18x is +12.5% over 16x.
- The timing model is the slow corner (hot, low voltage). Glen's board
  runs builds that need 1.29-1.31x the model at 16x. 18x needs about
  1.45x. Nobody knows if that works; one bitstream tells, at no risk
  (a power cycle returns to 12x).
- Either result is useful: if 18x runs, margin is not the limit we
  thought; if not, we know where the board stops and 16x stays the top.

## Design: the smallest change that gets an 18x clock

The LFE5U-25F has two PLLs, used for 14x and 16x. One PLL cannot make
both 16x and 18x (one VCO, 400-800 MHz). The full four-speed version
needs the 14x and 16x outputs moved onto one PLL (VCO 794.5 MHz, at the
top of its range), which risks the two speeds that work. So for the
experiment **18x replaces 14x**: the 14x PLL is reprogrammed, the mux
stays three-way, speed code 1 means 18x. `speed 18` works; `speed 14`
does not exist in this build. 12x and 16x are untouched.

Read first: `rtl/base64_tg68/clkgen.v` (whole file), the top level's
speed settings (`spd`, `ph_top`, about line 340-380), the switch
sequencer (section 13, about line 1750-1870), `docs/HISTORY.md` "Run-time
clock speed (step 13)".

### Changes

1. `clkgen.v`: the PLL `u_pll14` becomes 18x: `CLKI_DIV(2)`,
   `CLKFB_DIV(3)`, `CLKOP_DIV(6)` (85.13 x 3/2 = 127.69 MHz, VCO 766
   MHz), `FREQUENCY_PIN_CLKOP="127.69"`; leave the other attributes
   (`ICP_CURRENT`, `LPF_RESISTOR`, `CLKOP_CPHASE`...) as they are unless
   nextpnr or ecppack rejects them: then stop and report. Sim model:
   `pll_model #(.N(18))`. Keep the instance and net names (`c14`,
   `lock14`); add a comment at the top of the file that in this branch
   "14" means 18x. Do not rename ports: the diff must stay small.
2. Top level, where `spd == 2'd1` chooses settings: `ph_top` 17,
   `ph_half` 9, `ms_top` 17'd127695, `spd_hold2` 1 (already, for any
   speed above 12x), `spd_lox` 1 (as 16x). Check the widths: `ph`,
   `fr`, `ph_top`, `ph_half` are 5 bits (17 fits), `ms_top` 17 bits
   (127695 fits). Search for every other use of `spd` and of constants
   13 / 7 / 99318 and decide each one; list them in the log.
3. Sequencer: CAS latency 3 is needed at 18x as at 16x. Wherever the
   sequencer tests `sp_tgt == 2'd2` to go to CL3 or `sp_tgt != 2'd2` to
   leave it, the test becomes "target is not 12x" / "target is 12x".
4. Speed register (`spd_stat`): the multiplier byte reads 18 for speed
   code 1. `turbomem_zii.v` (`TG68:` comment): a keyed write of 18
   (`$5B12`) selects code 1; 14 is no longer accepted.
5. `sw/speed/speed.s`: accept 12, 16, 18 (not 14); the help and status
   text say 18x; bump the version to "1.3x (18x experiment)". Run its
   vamos tests (`sw/speed/build.sh test`).
6. `scripts/check_timing.py` needs no change; score with
   `--freq 127.69`. `build.py`'s 14x score line can stay (it will print
   a 99 MHz ratio nobody uses); add the 18x ratio by hand to the timing
   file header.

### SDRAM at 7.83 ns

IS42S16160J-6: CL3 is good to 166 MHz. The controller's counts
(`sdram_ctrl.v` parameters: T_RCD 2, T_RP 2, T_RAS 5, T_RFC 6) were
"in spec at 16x by controller overhead". **Do not reason about it: the
SDRAM model in the sim checks every timing in ns** (`u_sdram.n_err`,
which fails the benches). Run `fastmem` and `bench copy` at 18x. If the
model reports a violation, add the one missing clock for that parameter
when the speed is 18x (a run-time flag from `spd`, like `spd_hold2`;
mark `TG68:`), re-run, and record which parameter needed it. If more
than two parameters need it, stop and report.
Not checkable in the sim: read data capture at the pins (tAC 5.4 ns of
a 7.83 ns clock). If 18x fails on hardware in fast RAM only, this is
the first suspect; say so to Glen.

### Tests

- The `fastmem` bench switches 12x -> 16x -> 14x -> 12x and checks the
  register after each (0x81D4-0x81FC, `n_switch`, `n_mrs`, the CAL_TEST
  and CAL_DRIFT variants). Change the 14x leg to 18x: the write is
  `$5B12`, the expected register's low byte `$12`, and the mode-register
  count `n_mrs` rises (18x needs CL3: work out the new count from the
  sequence and say so in a comment). `test_top.s` and `tb_top.sv` both
  change. The tb's 7 MHz clock and its PLL model must give 18 clocks per
  7M period; the aligner must lock (`ph_locked`, `!ph_slip`).
- All three sims pass; `bench sd` passes; the other benches are
  unchanged at 12x (same clock counts as step 15b: c 65892, copy 9432,
  read 6204, scatter 3756, readoff 11316, chip 31440, wrfast 7464,
  wrmix 31572).
- CAL_TEST and CAL_DRIFT runs (`VLFLAGS=-DCAL_TEST`, `-DCAL_DRIFT`) pass
  with expectations updated for 18x where the 14x leg was. If the
  calibration picks a different sample at 18x than the tb expects,
  record what it picks and why (the clock delay model against 7.83 ns);
  both samples are valid if the aligner locks and nothing slips.

### Build

`python3 scripts/build.py full --seed 1 --seeds 18`. The netlist differs
from 15b only in the PLL and a few constants, so expect about the same
5 of 18. Take every seed that passes at 12x, score each at 18x
(`check_timing.py <sdf> --freq 127.69`; use `--keep-sdf`), and ship the
one with the **lowest 18x ratio**, not the most 12x slack. Record 16x
and 18x ratios for all passing seeds.

### Deliverable

`bitstreams/exp18x/`: `_plain`, `_fast`, `speed` (the experimental one,
named `speed18`) and its ReadMe, `timing_full.txt`,
`timing_full_at16x.txt`, `timing_full_at18x.txt`, and a short
`README.txt`: experimental; `speed18 18` to try, `speed18 16`, `speed18
12`; no 14x in this build; a power cycle returns to 12x; go back to
step 15b for normal use.

Ask Glen to test, in this order, and to stop at the first failure and
say what he saw:

1. Boot at 12x; `speed18` (status); `speed18 16`; SysInfo quickly: 16x
   must behave as step 15b.
2. `speed18 18`. Does the machine survive the switch? `speed18` status.
3. SysInfo, AIBB (caches on and off), xSysInfo; fast RAM test in
   xSysInfo or AIBB MemTest (this exercises the SDRAM at 7.83 ns).
4. SD card read; a game or the Frontier timedemo for ten minutes (heat).
5. If it fails only when warm, or only in one test, say which.

## Acceptance criteria (for the build; the experiment's result is Glen's)

- Sims and benches as above, at 12x, 16x and 18x.
- A 12x-passing seed, with its 16x ratio no worse than 1.31x.
- The bitstream folder and the test list delivered.

## Stop and report if

- the PLL parameters are rejected by the tools, or the 18x PLL does not
  lock in the sim model's terms;
- the SDRAM model needs more than two parameters stretched;
- the 12x or 16x legs of any sim change behaviour (bench counts, switch
  test results);
- no seed passes at 12x in 18.

## If it works on hardware (not part of this build)

The planner then writes the four-speed version (14x and 16x on one PLL,
18x on the other, a four-way mux, `speed 14|16|18`) as a real step, and
looks at 20x only if 18x shows no sign of trouble.

## Log

- Built on `exp-18x` (commit 8fac65f) as planned. Every other use of
  `spd` checked: `ph_top`/`ph_half`/`ms_top` (17 / 9 / 127695, widths
  fine), `spd_hold2` (already "not 12x"), `spd_lox` now "not 12x" (16x
  and 18x), the sequencer's two CL tests now "not 12x" / "12x", the
  register's multiplier byte (18), `smp_r`'s 12x rule unchanged. No other
  13 / 7 / 99318 constants. `sp_ok` uses `pll_lock14` = the 18x PLL.
- **SDRAM model at 18x: one parameter, tRFC.** Every refresh: "command
  issued too soon after REFRESH" (8 clocks = 62.6 ns; the model checks a
  -7 part's 65 ns; the board's -6 part needs 60). Fixed per the plan:
  `sdram_ctrl` input `rfc_long` (TG68:, from `spd_rfc` = speed code 1, a
  config register in check_timing), T_RFC + 1 on all four refresh
  timer loads. No other violation in any bench at 18x.
- Benches can now run at 18x: `BENCH_ASD="--defsym SPEED18=1" sh
  sim/run.sh bench copy|read|scatter|c` (add `--defsym SPEED16=1` for a
  16x control). The write and chip benches (test_wr.s, test_chip.s) do
  not switch. Timed-pass clocks (clk12 ticks, so time) at 12x / 16x /
  18x: copy 9432 / 7536 / 6780, read 6204 / 4884 / 4416, scatter 3756 /
  3048 / 2772, c 65892 / 49644 / 44160. 18x over 16x: copy +11%, read
  +11%, scatter +10%, c +12.4%.
- Sims: bus, top, fastmem pass; the fastmem switch test's 14x leg is
  18x ($0712 at 81E0; mode loads still 3: CL3 at 16x, kept at 18x, CL2
  at 12x). CAL_TEST and CAL_DRIFT pass with the 18x expectations (falling
  sample at 18x; CAL_DRIFT one swap, as before). 12x benches unchanged
  from 15b. bench sd passes.
- `speed` 1.3x: 12 / 18 / 16, 14 rejected; vamos fake-board runs give
  the expected text for every case.
