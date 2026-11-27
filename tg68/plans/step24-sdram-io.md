# Step 24: the SDRAM data pins in the timing check

Status: **revised plan, Glen's choice (option 2)** (27 November 2026).
Branch `step24-sdram-io`, from `exp-22x`. The first version of this plan
(IDDR input registers in the I/O cells) is in the log below with why it
was dropped: nextpnr allows an IDDR only as a pin's sole load, so it would
have cost one clock on every SDRAM read at every speed (caches-off code
-7 to -8%). Glen: no performance hit; a harder seed search is acceptable.

## Goal

No 4-speed build ships whose SDRAM data pin paths could break 22x. The
pin -> register paths, which `check_timing.py` has never timed, get two
limits taken from Glen's hardware results; a seed passes only if they
hold, and the best seed is chosen by the lowest 22x ratio. No RTL change:
the design is exactly exp-22x's.

## Background

- `sdram_ctrl.v`: `rdata_live = sdram_dq`; `fastmem_zii.v`: `dp_rdata =
  ack_early ? rdata_live : rdata`. Each pin goes through that LUT to
  `cpu.k_din_dw`, `cpu.dp_q`, `cpu.pf_d` (loaded on the clock `ack_early`
  is high, the pin's value), and straight to `g_sdram.u_sdram.rdata`
  (only used by the 68000-bus side, compiled out with BUS_RAM = 0: not
  counted for the hold limit).
- Step 23, `scripts/sdram_pins.py` on four builds (pad buffer output ->
  FF D, with setup, max corner):

  | build | 22x on Glen's board | longest | shortest (cpu.*) |
  | --- | --- | --- | --- |
  | exp_22x_7m seed 12 | ran for a long time | 4.47 | 1.60 |
  | exp_22x seed 15 | ran the benchmarks | 4.79 | 2.16 |
  | step23 seed 4 | froze halfway through Frontier | 4.79 | 2.47 |
  | step23 seed 7 | froze on the switch | 5.01 | 3.04 |

- The data's window at the pads, relative to the read edge E: it opens
  1.5 T - X before E and closes 0.5 T - Y before E (the SDRAM clock rises
  at our falling edge; X = clock-out + tAC + board, Y = clock-out + tOH +
  board, both in ns, fixed). A path of length D samples the pad at E - D,
  so: **setup D <= 1.5 T - X, hold D >= 0.5 T - Y.** Setup binds at the
  fastest clock (22x), hold at the slowest (12x).
- Calibration: setup limit at 22x **4.50 ns** (4.47 runs for hours; 4.79
  failed warm on seed 4; seed 15's 4.79 ran but is counted as marginal),
  so X = 5.11 ns. Hold limit at 12x **1.55 ns** (seed 12: 1.5996, the shortest path in a
  build that runs; no failure seen, so this is a bound from evidence, not
  a measured edge), so Y >= 4.27 ns: the data stays valid well past E.

## The change, in order

1. `scripts/sdram_pins.py`: a function (`pin_paths(edges, setup,
   clkpin)`) giving, per `sdram_dq` pin, the longest path to any register
   and the shortest to a `cpu.*` register; the command line prints them
   as now.
2. `scripts/check_timing.py`: after the class table, two rows (not in the
   `nT` format, so `build.py`'s parser ignores them):
   `sdram data pins, setup (22x limit 4.50 ns)` and `..., hold (12x limit
   1.55 ns)`, worst value, slack, the pin; `<-- FAIL` and RESULT FAIL
   when either limit is broken, **at every --freq** (a 4-speed bitstream
   runs all four speeds, so the limits do not scale with --freq).
   `--pin-setup` / `--pin-hold` override them, `--no-pins` drops them
   (for the old --x16 build). A comment gives the calibration table and
   says the limits are to be tightened or relaxed only from hardware
   results.
3. `scripts/build.py`: a seed passes only if `check_timing.py` (12x)
   passes, pins included. The best seed is the passing seed with the
   **lowest 22x ratio** (computed from the 12x report: each class's
   budget minus slack over its budget at 22x; rule 4 says pick it, until
   now that was done by hand). `seeds.txt` gets the 22x ratio and the
   two pin values; the best seed gets `timing_at22x.txt` beside the 16x
   and 20x ones.

## Tests

- `check_timing.py` on the four step 23 SDFs: seed 12 (7 MHz build)
  PASS on pins, seeds 15, 4 and 7 FAIL on setup. That is the test: the
  rule must sort the four builds the way the hardware did.
- A seed's 22x ratio from `build.py` against `check_timing.py --freq
  156.07` on its SDF (equal to 0.001).
- No RTL change: the sims are not affected (run `bus`, `top`, `fastmem`
  once to show the branch is the exp-22x design).

## Numbers that must not move

All benches (no RTL change).

## Acceptance

- 16 seeds of the exp-22x netlist (pin-fed PLLs): at least one passes
  12x and the pins; more seeds (17-32, `--skip-synth`) if none do.
- Glen: the usual set at 12x / 16x / 20x, and at 22x the Frontier CPU
  timedemo all the way through, AIBB MemTest, 30 minutes warm.
- This build is then the v2.1 candidate (step 2 of the long plan).

## Fallbacks and stop conditions

- If no seed of 32 passes the pins: the next tool is structural and costs
  no clock: take `k_din_dw` / `dp_q` / `pf_d` from `rdata_live` directly
  (the `dp_rdata` multiplexer only matters for loads nothing uses), which
  removes one LUT from every pin path. It also makes the shortest paths
  shorter than the 1.60 ns hold evidence, so it needs a 12x test on
  hardware. Report before building it.
- If a seed that passes the pins still fails at 22x: the setup limit is
  wrong. Lower it to below that seed's value and report.
- The SDRAM outputs (address, command, write data) are not checked here
  (no failure seen, so nothing to calibrate against). `sdram_pins.py`
  can report them for the record; step 24b stays in the backlog.

## Log

- First version (IDDR, dropped): tiny yosys / nextpnr designs on the real
  pins showed an `IDDRX1F` packs into an `sdram_dq` pin's I/O cell, also
  with the pin driving write data, but **nextpnr refuses an IDDR whose
  pin also feeds the fabric** ("D input must be connected only to a top
  level input"). A falling-edge register in the I/O cell packs too, but
  its output must reach the fabric in half a clock (today's routes
  3.1-5.0 ns: only 12x has that). So the capture costs one more clock on
  every read at every speed. Simulated (reads wait one more clock, the
  word from a register of the pin), 12x / 20x: c +0.23% / +0.31%; coff
  (caches off) +8.3% / +7.6%; copy +3.3% / +2.0%; readoff +7.0% / +6.2%;
  read, scatter, wrmix 0. All PASS. Glen chose this plan instead.
- Hold evidence: shortest `cpu.*` pin paths 1.60 (seed 12, 7 MHz build),
  2.16, 2.47, 3.04 ns; all four builds run at 12x.
- Checker on the four step 23 SDFs: seed 12 (7 MHz build) PASS, seeds
  15, 4, 7 FAIL on setup (3, 6, 6 pins over 4.50). Seed 12's shortest is
  1.5996 ns, so the hold limit is 1.55 (1.60 failed it on rounding).
  build.py's 22x ratio from the 12x report against check_timing.py
  --freq 156.07: 1.6119 / 1.6118 (seed 4). Sims bus, top, fastmem PASS.
- **Build, exp-22x netlist (pin-fed), router1, seeds 1-32: 3 pass**
  (7: pins 4.04, 22x 1.726x; 19: 4.20, 1.720x; 26: 4.42, 1.662x). The
  longest pin path ranges 4.04-5.89 ns over the 32 seeds; 28 fail on it,
  1 (22) on logic. Seed 15 reproduces exp_22x (4.79, 1.646x). Shipped
  **seed 26**: pins 4.42 / 2.23, 1.21x / 1.51x / 1.66x at 16x / 20x /
  22x (exp_22x seed 15: 1.20 / 1.50 / 1.65). `bitstreams/step24_pins/`.
  One in ten seeds passing is the cost of the check; if later steps make
  it worse, the plan's structural fallback (no LUT on the pin path) is
  next.
