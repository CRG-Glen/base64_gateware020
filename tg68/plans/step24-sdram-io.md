# Step 24: SDRAM read data captured in the I/O cells

Status: **planned** (27 November 2026). Branch `step24-sdram-io`, from
`exp-22x` (not from `step23-burst`: its counters are a test build).
Planned by the building model. Glen asked for it after step 23's 22x
crashes.

## Goal

Make 22x independent of the seed. The SDRAM's read data is sampled by a
register in each data pin's I/O cell, at a fixed point in the data's valid
window, so no routing change can move it out of the window again. 12x, 16x
and 20x keep today's timing and speed.

## What step 23 found (the evidence)

`sdram_ctrl.v`: `rdata_live = sdram_dq`. The pins go straight into fabric
registers (`k_din_dw`, `dp_q`, `pf_d`, and `rdata` in S_RD_DONE) on the
edge the controller is in S_RD_DONE (call it E). Nothing times these
paths: `check_timing.py` starts only at registers. Measured with
`scripts/sdram_pins.py` (pad -> FF D + setup, per pin):

| build | at 22x on Glen's board | pins mean / worst | pins > 4.5 ns |
| --- | --- | --- | --- |
| exp_22x_7m seed 12 | ran for a long time | 3.49 / 4.47 | 0 |
| exp_22x seed 15 | ran the benchmarks | 3.93 / 4.79 | 3 |
| step23 seed 4 | froze halfway through Frontier | 4.20 / 4.79 | 6 |
| step23 seed 7 | froze on the switch | 4.40 / 5.01 | 7 |

The checked logic does not order these builds (1.60x, 1.65x, 1.61x,
1.57x); the pin paths do. So at 22x, warm, the data becomes valid at the
pads about **4.5-4.8 ns before E**: a pin whose path is longer than that
samples too early.

## The window (22x, T = 6.41 ns)

- The SDRAM clock leaves through `u_sdram_clk` (ODDRX1F, D0 = 0, D1 = 1):
  the chip's rising edge comes at our **falling** edge, half a clock
  after the commands leave.
- IS42S16160J-6 at CL3 (datasheet values to confirm while building):
  tAC 5.4 ns max, tOH 2.5 ns min. A word is valid at the chip from
  edge + 5.4 to next edge + 2.5: **3.6 ns** at 22x (4.3 ns at 20x,
  6.9 ns at 16x; 12x runs CL2, wider still).
- Put together with the measurement: valid at the pads from about
  E - 4.7 to about E - 1.1 ns (the end is the start + 3.6, so it carries
  the same uncertainty).
- **Our falling edge before E, at E - 3.2 ns, is near the middle.** A
  register in the I/O cell sampling there (input-buffer delay ~0.5-1 ns,
  so effectively E - 2.5 to E - 2.7) has about 1-2 ns either side,
  whatever the routing.
- Sampling at E itself (rising edge) would come after the window ends:
  not an option without moving the SDRAM clock.

## The change, in order

1. **Input registers.** In the top level, an `IDDRX1F` on each
   `sdram_dq` pin (SCLK = `clk`), under `ifdef YOSYS`; a behavioural model
   for the sims (Q0: sample at the rising edge; Q1: sample at the
   falling edge before it, both presented after that rising edge, as the
   primitive does). The pin's tristate buffer (`BB`, today's
   `sdram_dq` inout) stays; the IDDR takes its input.
2. **One more clock on reads, at 22x only.** A run-time setting `spd_rdl`
   (loaded from `spd` like `spd_xl`, on at speed code 3 only). With it,
   `sdram_ctrl` waits one more clock before S_RD_DONE (`timer <=
   cas_lat_r + spd_rdl`, also for the pair read's second word and the
   prefetch read), and every reader of `rdata_live` (and `rdata`) takes
   the IDDR's Q1 instead of the pin. The CPU side keys off `ack_early`,
   which moves with S_RD_DONE, so the adapter needs no change; the sims
   say whether that is true. Mark it `TG68:` in `sdram_ctrl.v`.
3. **The select is a multiplexer in front of those registers:**
   `rd_data = spd_rdl ? iddr_q1 : sdram_dq`. Both inputs are final a
   whole clock before E, so it adds nothing timed at 12x-20x beyond
   today's pin path, and at 22x the path is IDDR -> fabric, an ordinary
   1T register path that `check_timing.py` sees.
4. **A test switch for the sample phase.** +$F00C write key `$5D` (in
   `turbomem_zii.v`, next to the speed key `$5B`): bit 0 = use Q0 (the
   rising-edge sample, one clock later still) instead of Q1; bit 1 = use
   the IDDR at every speed (to test it at 20x). Both power on 0. Read
   back in +$F00C's status. `speed` 1.6: `speed RDPHASE RISE|FALL` and
   `speed RDLATE ON|OFF`, printed by plain `speed`. Not for users: it is
   there so Glen can test the other phase without a rebuild.
5. `scripts/check_timing.py`: the IDDR's outputs as starts (class
   "logic", 1T); a test that they are found (grep the SDF for the IDDR
   cells; the checker fails if `sdram_dq` has fewer than 16).
   `build.py` runs `sdram_pins.py` after each seed and adds the worst pin
   to `seeds.txt` (it still matters at 12x-20x, where the pin is used).

## Tests

- **The SDRAM model drives real timing.** `sim/sdram_model_checked.v`
  presents each read word tAC (5.4 ns) after its clock edge and holds it
  only tOH (2.5 ns) after the next one, then drives X. Today it drives on
  the edge, so no sampling phase can fail in the sim. With it: 22x with
  Q1 must pass every bench; **22x with the IDDR off (today's design)
  must read X** at the pin in some cases, or this model is not doing its
  job (it has no routing delay, so maybe not: say which); 22x with Q0
  (rising) must fail (the word is gone at E). Write `$display` of the
  margin each phase has in the model.
- All three sims; `bench sd`; every bench at 12x unchanged (spd_rdl is
  off): c 63,900, copy 6,120, and the rest as in exp22x.md; c, copy, read,
  bigread at 16x and 20x unchanged; at 22x the new counts (each SDRAM
  read +1 clock: bench c 35,232 -> about +0.1%, bigread and copy more;
  coff, the caches-off bench, shows the worst case).
- Mutants: `spd_rdl` timer shift dropped (the controller hands over the
  word a clock early: the read checks fail); Q1 and Q0 swapped (22x
  fails); the 22x settings loaded at 20x (the 20x counts move: the tb
  compares them).
- The `$5D` key: test_top.s writes it, reads the status back, reads
  fast RAM with each setting at 22x.

## Numbers that must not move

12x, 16x and 20x: every bench clock count. 22x: only the SDRAM read
latency (+1 clock a read; +1 for the second word of a pair is the same
clock, so pairs are +1 too).

## Expected cost at 22x

From Glen's step 23 counters (20x): cache misses are 5.2% of the time in
the Frontier CPU timedemo at ~9 clocks each, so +1 clock is about
**-0.6%**; SysInfo, xSysInfo, AIBB under 0.3%; EON (caches off, 44% of
its time in SDRAM fetches) about **-5%**. 22x still beats 20x by 4-9%.

## Acceptance

- Sims pass; 12x passes on some seed of 16 (router1); 20x ratio no
  worse than 1.50x.
- nextpnr's log shows 16 IOLOGIC cells on `sdram_dq` (the IDDRs were
  placed in the I/O cells, not in the fabric).
- Glen, at 22x: the Frontier CPU timedemo all the way through, AIBB
  MemTest, 30 minutes warm. Then **a second seed of the same netlist**,
  chosen for the worst `sdram_pins.py` numbers of the 16, also at 22x:
  that is the proof that the seed no longer matters.
- 12x / 16x / 20x: Glen's usual set, unchanged.

## Fallbacks and stop conditions

- If nextpnr cannot feed one pin both to the IDDR and to the fabric
  (today's path, kept for 12x-20x): use the IDDR at every speed with
  `spd_rdl` at every speed. That costs the +1 clock at 12x-20x too:
  stop and ask Glen before building that.
- If Q1 fails at 22x on the board and Q0 works (or neither): the window
  is not where step 23's numbers put it. Try the other phase with the
  `$5D` switch first. If neither works, the next tool is the input
  delay (`DELAYF` in the I/O cell, fixed steps of ~25 ps): report
  before building it.
- If the IDDR -> fabric path misses 1T at 12x on most seeds: register
  the select a clock earlier is not possible (the data is the data); the
  multiplexer goes behind one landing register at every speed instead
  (+1 clock everywhere): stop and ask.

## Step 24b (after 24 runs): the outputs

The command, address, DQM and write data registers (`sdram_a`,
`sdram_ba`, the command bits, `sdram_dqm`, `dq_out`, `dq_oe`) are also in
the fabric, 1.5-4.3 ns from their pins, also unchecked and seed-dependent
(step 23: write data mean 2.62 / 2.73 ns in the builds that ran, 3.15 /
3.17 in the two that crashed). With the chip's clock at our falling edge,
a command has half a clock less its route to reach the chip before tIS
(1.5 ns): at 22x that leaves 1.7 ns minus the route, so 24b moves these
registers into the I/O cells (`syn_useioff`, as the Amiga bus pins have
since v1.0: none of them may be read inside the design, and the ones in
one I/O block must share CE / LSR). It changes when commands reach the
SDRAM (earlier, by the route), so it is its own step, planned in detail
after 24.

## Log

(the builder writes here)
