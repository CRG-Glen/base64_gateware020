# Step 23: burst cache fills (line fills on a fast RAM miss)

Status: **measuring** (27 November 2026). Branch `step23-burst`, from
`exp-22x`. Glen's choice after the 22x experiment.

## Idea

Today a fast RAM miss brings one word or one aligned pair (32 bits) from
the SDRAM, and after a single-word read a one-word prefetch. A line fill
would bring the whole aligned line of 4 or 8 words (an SDRAM burst; the
two cache banks take two words a clock) while the CPU carries on with the
word it asked for.

## Measured (tb model: `VLFLAGS="-DBURST_MEASURE -DBURST_L=4|8"`)

A shadow of each cache's tags follows every real cache write and, on each
real fast RAM miss, takes the rest of the aligned line. In the timed pass
it counts real misses the shadow held ("would hit") and real hits the
extra fills had evicted ("would lose"). The SDRAM time of longer fills is
not modelled.

| bench | real misses | 4 words: would hit / lose | 8 words: would hit / lose |
| --- | --- | --- | --- |
| c (compiled C, 63,900 clocks) | 17 fetch + 52 data | 15 / 0 | 15 / 0 (~0.1%) |
| copy (9,372) | 256 data | 132 / 0 (5.6%) | 194 / 0 (8.2%) |
| read, scatter | 0 (their 1 KB stays cached) | - | - |
| op | 7 fetch | 2 / 0 | 3 / 0 |
| **bigread** (new: 16 KB sum, misses every pass; 120,288) | 4096 data | 2048 / 0 | 3072 / 0 |

bigread costs 29.4 clocks a longword against 24.2 for the same loop from
the cache (`read`), so a miss turned into a hit saves ~5.2 clocks:
4 words **~-9%**, 8 words **~-13%** on a sequential read through more than
the cache. No hit was lost in any bench. Compiled C gains nothing (it
runs from the caches).

What the simulator cannot say: how sequential real programs' misses are
(Frontier's CPU timedemo: 54M fetch and 42M data misses, ~5% of its
time, step 18).

## Next

1. Measure on hardware: a `perf` build with counters for misses that fall
   in the same 4- and 8-word line as the previous miss of the same kind
   (fetch / data); Glen runs the Frontier CPU timedemo, AIBB, xSysInfo
   and a game.
2. Then decide line length and write the design: the SDRAM controller's
   burst, filling both banks while the CPU runs on, a write to the line
   during its fill, a read of a word of the line not yet filled, the
   prefetch buffer (which a line fill would replace).

## Log

- Counters 20-23 (commit 2caca29; perf 1.1): a cached fast RAM /
  MapROM miss in the same aligned 4- (20 fetch, 22 data) or 8-word line
  (21, 23) as the previous miss of its kind, on a word no cache write
  with another tag has hit since (8 per-word bits per kind, cleared by a
  conflicting fill, a drop, the flush). A first version without the
  per-word bits counted repeated conflict misses (bench c: 12 of 17
  fetch misses alternate between a word and a Kickstart word 8 KB away)
  and a version that forgot the whole line on any overwrite missed
  copy's (its destination writes land on the source's index). Against
  the tb model (would hit, 4 / 8 words): bigread 2048 / 3072 (model
  2048 / 3072), copy 128 / 192 (132 / 194), c fetch 2 / 3 (2 / 3), c data
  4 / 4 (10 / 12: the counter remembers one line, so it is a lower
  bound). tb compares each with its own count; mutants (no word check;
  no data overwrite tracking) fail bench c. Regression PASS: bus, top,
  fastmem, top and fastmem with PERF=0.
- What to read from Glen's runs: counter 20 / 7 and 21 / 7 are the shares
  of fetch misses a 4- / 8-word fill would catch, 22 / 8 and 23 / 8 for
  data. Each caught miss saves ~4-5 clocks; against counter 0 that gives
  the time.
- Build (`build.py full --perf`, router1, seeds 1-16): **16 of 16 pass**
  at 12x. Ratios from each seed's 12x report (budget minus slack, so
  setup included; the "worst ns" column leaves setup out and ranked seed 4
  wrongly at first): best seed 7, +1.58 ns, 1.14x / **1.42x** / 1.57x at
  16x / 20x / 22x (exp_22x seed 15: 1.20x / 1.50x / 1.65x). Shipped:
  `bitstreams/step23_perf/`. Waiting for Glen's numbers.
- **Glen's runs (20x)**, misses a 4 / 8-word fill catches (fetch; data),
  and time saved at ~5 clocks a caught miss: Frontier CPU timedemo 41 /
  62%; 14 / 21% -> 0.8 / 1.3%; xSysInfo 38 / 57%; 46 / 69% -> 0.4 /
  0.65%; AIBB 40 / 61%; 24 / 38% -> 0.2 / 0.3%; SysInfo ~0; EON (Black
  Lotus) ~0: it runs with the caches off (3.6G fetches, 2.1G SDRAM
  fetches, 44% of its time in misses). Even counting every miss as caught,
  Frontier gains at most ~3% (misses are 5.2% of its time). **Line fills
  are not worth the design (SDRAM bursts, fills while the CPU runs on,
  writes into a line being filled) for 1-1.5%.** Recommend parking step
  23.
- **22x crashes on this build (seed 7)**, at once on the switch; 20x
  runs. It is pin-fed (no --pll7m), like exp_22x seed 15, which runs at
  22x. The checked logic is better than seed 15's (1.57x against 1.65x).
  Not checked by check_timing.py: SDRAM data pin -> register (rdata_live
  = sdram_dq straight into k_din_dw / dp_q / cache data, no input
  register at the pin). Measured from the SDF (pad output -> FF D +
  setup, max over the FFs each pin reaches): seed 15 mean 3.93 / worst
  4.79 ns; seed 7 4.40 / 5.01; seed 4 4.19 / 4.79. A diagnosis build from
  seed 4 (worse logic, 1.61x, better pins): `bitstreams/step23_perf_seed4/`.
  If it runs at 22x the pin paths are the cause, and the fix is
  structural: the pin paths need a class in the checker (with the SDRAM's
  tAC / tOH and the clock-out delay) or an input register in the I/O
  cell.
- **Glen: seed 4 runs at 22x** (seed 7, same netlist, crashed at once).
  Seed 4's checked logic is worse (1.61x against 1.57x), its SDRAM pins
  better: the SDRAM data pin -> register paths decide 22x. Seed 7 has
  five pins above 4.79 ns (worst 5.01); seed 4 and exp_22x seed 15 have
  none. `scripts/sdram_pins.py` measures them from the SDF. Until the
  checker covers them, a 22x build's seed is picked by this too (and
  build.py keeps only the best seed's SDF: rebuild a seed with
  --skip-synth to measure it). Next: a plan for the pin paths (see
  plans/README.md).
- **Seed 4 crashed too**, halfway through the Frontier CPU timedemo at
  22x (screen froze; a reset recovers). Compared with the two exp_22x
  builds (both rebuilt byte for byte; the RTL differs only by the
  counters, +2,300 LUTs, 52% -> 61%):

  | build | at 22x on Glen's board | logic ratio | SDRAM read pins mean / worst | pins > 4.5 ns | write data out mean / worst |
  | --- | --- | --- | --- | --- | --- |
  | exp_22x_7m seed 12 | ran for a long time | 1.60x | 3.49 / 4.47 | 0 | 2.73 / 3.54 |
  | exp_22x seed 15 | ran the benchmarks | 1.65x | 3.93 / 4.79 | 3 | 2.62 / 3.10 |
  | step23 seed 4 | crashed mid-Frontier | 1.61x | 4.20 / 4.79 | 6 | 3.17 / 3.65 |
  | step23 seed 7 | crashed on the switch | 1.57x | 4.40 / 5.01 | 7 | 3.15 / 3.81 |

  The checked logic does not order them; the SDRAM read pin paths do,
  exactly. Address / command outputs: no pattern (seed 15 worst 3.64,
  seed 4 3.10). Conclusion: 22x is limited by the unregistered SDRAM read
  data paths, which vary 1 ns from seed to seed; any change to the design
  re-rolls them. Fix structurally (input registers in the I/O cells),
  not by picking seeds.
