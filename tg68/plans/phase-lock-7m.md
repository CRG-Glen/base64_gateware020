# Phase lock: the fast clock held on the Amiga's 7 MHz edge

Status: **design, waiting for approval**. Branch `v2-clock-dma-compact`
(from `main` = v2.0 plus the strategy commit). First of three items on this
branch (then: DMA access to fast RAM; compacting for an FPU), each with its
own plan file.

## Goal

Every signal the bridge drives to the motherboard changes at a fixed, known
time after the real 7 MHz edge: the same at 12x, 16x and 20x, on every
build (seed) and as the chip warms up. The 7 MHz sample the grid is built
from always sits half a fast clock from a 7 MHz transition.

Not goals: more speed; a change in the number of clocks any cycle takes; a
change at the SDRAM or SD pins.

Would make it a failure: a board that no longer powers on to a working 12x;
a build that only works on some seeds because of the new logic; a clock
that glitches when its phase is moved.

## Background: why the phase is not fixed today

- The frequency is exact: the ICS570B multiplies the 7 MHz clock by 12
  (pin L1, 85.13 MHz) and the two PLLs in `rtl/base64_tg68/clkgen.v`
  multiply that by 5/3 (20x, `u_pll14`) and 4/3 (16x, `u_pll16`).
- The phase is not. The clock reaches the logic through the fabric
  multiplexer and a DCCA in `clkgen.v`. Its delay is 5.3 ns (12x), 6.9 ns
  (16x) and 13.4 ns (the other PLL) on step 13's seed 12
  (`docs/HISTORY.md`, step 13), different on every seed, and it moves with
  temperature. Call the part of it within one fast clock `d`.
- The top level (`base64_tg68_top.sv`, sections 2 and 3) samples `clk_7m`
  on both clock edges (`s_7m_fall`, `s_7m_rise`), a calibration picks the
  stream that does not move (`smp_r`), and `swap_req` swaps streams when
  the one in use starts to move. The grid (`ph`, `tick_r`, `tick_f`) is
  loaded `PHASE_OFS` = 2 clocks after the sampled edge.
- So a grid tick is at `d` plus a whole number of fast clocks after the
  real edge, where the whole number depends on which stream is in use and
  on which side of a clock edge `d` falls. The offset is unknown to about
  1.5 fast clocks (17 ns at 12x, 10 ns at 20x) and jumps by a clock on a
  swap (step 14b saw the grid "a clock later" with the rising stream).
- At 20x a half clock is 3.5 ns, so the better of the two samples is as
  little as 1.8 ns from a transition. That is where it moves first.
- `PHASE_OFS` is a count of fast clocks, so even with `d` fixed the grid
  sits 23.5 ns after the sampled edge at 12x and 14.1 ns at 20x.
- Related: `exp-7m-pll` (on GitHub, waiting for a hardware test) feeds the
  16x and 20x PLLs from pin C7 (7 MHz) to drop the PLL-on-a-PLL. It does
  not fix the phase; this plan works with either reference and keeps the
  ICS570B reference until that test says otherwise.

## Approaches considered

- **A. A servo on the PLLs' dynamic phase inputs (chosen).** A loop steps
  the selected PLL output (1/8 of a VCO period per step, about 0.22 ns)
  until the rising-edge sample of `clk_7m` sits on the 7 MHz transition,
  and keeps it there. The falling-edge sample is then always half a clock
  from the transition. It measures at the flop that matters, so mux,
  routing, pad and temperature are all inside the loop. Cost: 12x must
  come from a PLL too; the tested clocking changes.
- **B. PLL feedback through the clock network.** No stepping logic, but
  the fabric multiplexer is outside the loop, so a few ns of per-seed
  error remain and nothing measures them.
- **C. Adjustable delay on the `clk_7m` pin.** Makes the sample stable but
  leaves the grid and the outputs where they are. Does not meet the goal.

## The design

### 1. Clocks (`clkgen.v`)

- PLL 1 (`u_pll16`): 16x as today (VCO 681 MHz, /6 = 113.51 MHz) plus a
  second output /8 = 85.13 MHz: 12x. Steps of 0.18 ns.
- PLL 2 (`u_pll14`): 20x exactly as tested in v2.0 (VCO 567.5 MHz, /4).
  Steps of 0.22 ns. Every divider stays even (50% duty: the falling-edge
  sample, the mux enables and the SDRAM clock depend on it).
- Loop filter attributes regenerated with `ecppll` for PLL 1.
- The PLL's PHASESEL code is not the output's index (00 CLKOS, 01 CLKOS2,
  10 CLKOS3, 11 CLKOP; a step is taken on PHASESTEP's falling edge with
  PHASESEL / PHASEDIR stable before it): check against FPGA-TN-02200.
- Each PLL's feedback comes from an output that is never stepped (a spare
  output at the same divider), so a phase step moves the clock against
  the reference and the loop does not undo it. `DPHASE_SOURCE="ENABLED"`.
- The multiplexer gets a fourth source: the raw pin clock stays the
  power-on source. In the power-up hold, once PLL 1 is locked, the
  sequencer switches to PLL 12x and the servo acquires (the servo runs on
  the clock it steers, so the switch comes first). If the PLL does not
  lock or the acquire does not end in time, it switches back to the raw
  pin with the rising-edge sample (step 14b's finding for 12x on every seed), boots as today, and
  `speed` reports "phase lock: none".
- If the PLL in use loses lock while running: hold the CPU (the hold
  sequencer), switch to the raw pin (12x, rising sample, CL as for 12x),
  release, and report it in the status. No automatic return.
- New ports: `ph_sel[1:0]`, `ph_dir`, `ph_step` to the PLLs.
- `clk_7m` is sampled by one IDDRX1F on pin C7 (both edges in the pad
  cell, so the two samples see the same data delay on every seed). If the
  pin's other loads rule that out: two placed flops and a check in
  `build.py` that their data delays differ by under 0.3 ns in the sdf.

### 2. The servo (top level, replaces the calibration in section 3)

- Detector: at each 7 MHz rising edge seen by the falling stream, was the
  rising stream already high (early) or still low (late)? A window counts
  both.
- There are two places per clock where the count is mixed: the rising
  sample on the transition (wanted) and the falling sample on it (the
  worst place: there the falling stream's own edge moves by a clock). So
  the free-running counter `fr` and the falling stream's movement count
  (`jit_f`) are kept from the calibration: lock is "late -> early flip
  while stepping in the retard direction AND the falling stream did not
  move in the window". A mixed window with the falling stream moving
  means half a period away: keep stepping.
- Acquire (power-up hold, and where the speed sequencer has `SP_CAL`
  today): windows of 64 edges, step one way until locked as defined
  above, then centre: step until early and late are within 1:3 of each
  other. Worst case one clock period of steps (32 at 20x, 48 at 16x, 64
  at 12x), about 1 ms. CPU held, aligner unlocked, as today.
- Track (running): windows of 65536 edges (9 ms). A window more than 3/4
  one way requests one step (so the lock point stays within about one
  step of the centre of the jitter band: the "fixed" in the goal means
  +/- 0.5 ns). The falling stream moving while tracking is a fault: full
  re-acquire through the sequencer, counted in the status. The step is taken through the existing hold
  sequencer (the `sp_swp` path that swaps streams today): CPU held, buses
  idle for 16 clocks, one step, release. So at most one 0.22 ns move per
  9 ms, never under a CPU step or a bus cycle.
- Deleted: `jit_r`, `cal_*`, `swap_*`, `AUTO_N`, the forced
  edge (`speed 16 RISE/FALL`). `smp_r` becomes "on the raw pin" only.
- Status: `+$F00A` bits 14/13 become servo locked / on the raw pin,
  `+$F00C` becomes {re-acquires, tracking steps since power-up}. `speed`
  (sw/speed) prints them; it becomes version 1.5.

### 3. The grid offset per speed

`PHASE_OFS` becomes a register loaded from `spd`, like `ph_top`, and the
servo's lock point may be the rising or the falling stream per speed (a
half-clock choice). **Measured first** (step 1 of the build): from the
v2.0 release build's sdf, the real edge -> pin time of `cpu_as_n` at 12x.
It is computed with the ICS570B's skew taken as zero (it is a zero-delay
multiplier) and the rising stream in use (v2.0's rule at 12x); the
capture pipeline is counted from the code, not assumed. That is the
tested timing, and the target in ns. 16x and 20x get the `PHASE_OFS` and
half-clock choice nearest to it. The sdf cannot see the ICS570B or the
board, so the number is good to a few ns: a scope reading of 7 MHz edge
to /AS on a v2.0 board at 12x, or its `speed` status line, would replace
the assumption (v2.0 hardware results: `PHASE_OFS` 1 and 2 behaved the
same, so a few ns is inside what the motherboard accepts).
At 12x the cycle counts of every bench must not change; at 16x and 20x
`bench chip` may change by one 7 MHz cycle per access either way (the
grid moves against the DTACK synchroniser) and is reported, not fixed.

### 4. Simulation

- `pll_model` takes the step inputs and keeps a phase offset in real time;
  `clkgen` gets a `MUX_DLY` delay per source (transport delay) for the sim.
- New run `PHASE_TEST` in `tb_top.sv` / the fastmem bench: for mux delays
  of 0, T/4, T/2, 3T/4 at each speed, the servo locks and the measured
  time from the tb's 7 MHz edge to `cpu_as_n` falling is the target
  within one step plus the tb's jitter; identical for all four delays.
- `PHASE_DRIFT` (replaces `CAL_DRIFT`): the mux delay ramps by 1.5 ns over
  the run; the grid never moves, `ph_slip` stays 0, tracking steps > 0.
- PLL never locks (sim define): the board runs on the raw pin, all three
  regression benches pass, status says no phase lock.
- Mutants: detector inverted (acquire never ends: caught); tracking off
  (drift run slips: caught); step taken without the hold (an assertion on
  `ph_step` while `!spd_hold`: caught).
- Removed with the calibration: `CAL_TEST`, `CAL_DRIFT`, the `n_swap`
  asserts.

### 5. Timing classes (`check_timing.py`)

The servo's counters and the PLL control registers are config class (they
change only with the CPU held); the detector's first flops are
synchronisers. Each with a comment and a bench assertion, as rule 2 asks.
The per-speed `PHASE_OFS` register joins `ph_top`'s class.

### 6. Hardware stages (each a test bitstream, in order)

1. **Stepping proof.** v2.0 behaviour kept (calibration still in), PLLs
   regrouped, 12x still raw. `speed` gets a test verb that steps the
   running clock back and forth continuously. Run a memory test at 16x
   and 20x under it. Answers: do the open tools drive the phase inputs,
   is a step glitch-free on this chip in each direction, does the phase
   keep turning past 8 steps (a full clock period and back), does the
   12x output of PLL 1 lock and run.
2. **The servo**, as above, raw-pin fallback kept.
3. Clean-up after stage 2 has run for hours at 20x: only then are the
   calibration's remains removed from the source.

## Numbers that must not move

- 12x: every bench's clock count (`sh sim/run.sh bench c|copy|read|
  scatter|readoff|chip|wrfast|wrmix|sd`), as v2.0.
- 16x / 20x: every bench except `chip` (see 3).
- `check_timing.py` PASS at 12x; 16x / 20x ratios no worse than v2.0's
  seed 10 (1.23x / 1.54x) on the shipped seed.
- LUT4 count not above v2.0's 11,189 (the calibration goes, the servo
  comes).

## Acceptance

Sims and mutants as in 4; a 12x-passing seed; on hardware: stage 1 runs a
memory test at 20x under continuous stepping; stage 2 shows "phase lock"
at all three speeds from a cold boot, no slip and a small step count after
an hour at 20x, benchmarks as v2.0.

## Fallbacks and stop conditions

- The open tools do not support `DPHASE_SOURCE` or the step is not
  glitch-free: stop. Fallback to plan: approach C (stable sample only),
  and say so.
- The 12x PLL does not lock on hardware: 16x and 20x keep the servo, 12x
  stays raw with the fixed rising sample.
- A step with the CPU held still upsets something (SDRAM, SD): steps only
  in the lengthening direction (a full turn instead of one step back,
  aligner unlocked for it).
- Timing: the servo must stay out of `step()` and the bridge's tick paths;
  if a seed budget of 18 gives no pass, report.

## Calls made by the planner (not decisions of the owner)

- The ICS570B stays the PLL reference (tested); 7 MHz reference waits for
  the `exp-7m-pll` hardware result.
- PLL grouping 12x + 16x / 20x (20x unchanged from v2.0, even dividers).
- Lock lost while running: fall back to the raw pin and report.
- "Fixed" means +/- 0.5 ns; the detector centres on a majority count.
- Tracking steps go through the hold sequencer rather than under a running
  CPU.
- The timing target is v2.0's measured 12x timing, not a datasheet 68000.

## Log

- The open tools' chip database has `DPHASE_SOURCE` (ENABLED) and the
  PHASESEL / PHASEDIR / PHASESTEP pins for both PLL sites (checked in
  /usr/share/trellis/database/ECP5/tiledata/PLL1_LR/bits.db).
- A reviewer read the design as a builder; its questions are answered in
  the text (lock-point ambiguity, lock loss, tightness, sample flops,
  PLL grouping).
