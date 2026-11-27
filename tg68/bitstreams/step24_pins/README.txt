Base64 TG68: STEP 24, SDRAM PIN-CHECKED 22x BUILD (branch step24-sdram-io).
Not a release yet: the v2.1 candidate if it passes.

The design is exactly exp-22x (12x / 16x / 20x / 22x in one bitstream,
PLLs fed from the board's own 12x clock, no performance counters). What is
new is how the seed was chosen: the timing check now also times the paths
from the SDRAM data pins into the FPGA, the ones that decided which step 23
builds ran at 22x, with limits taken from your four 22x results:

  SDRAM data pins   longest (limit 4.50 ns)   shortest (limit 1.55 ns)
  this build        4.42                      2.23
  exp_22x_7m s12    4.47  (ran for hours)     1.60
  exp_22x s15       4.79  (ran the benchmarks)
  step23 seed 4     4.79  (froze in Frontier)
  step23 seed 7     5.01  (froze on the switch)

Only 3 of 32 seeds passed the pins. This is seed 26. Its logic needs the
FPGA this much faster than its worst-case model:
  16x 1.21x   20x 1.51x   22x 1.66x
(exp_22x seed 15: 1.20x / 1.50x / 1.65x; exp_22x_7m: 1.17x / 1.47x / 1.60x.)

Use the speed command in this folder (1.5, the same as exp_22x's).

Please test:
 1. 12x, 16x, 20x: the usual set (they should match exp-22x).
 2. 22x: the Frontier CPU timedemo all the way through, AIBB MemTest,
    then 30 minutes warm (a game or demo).

If it fails at 22x, the pin limit is not tight enough (or the logic is the
limit): say where it failed and how long it ran.

Files: base64_tg68_full_plain.bit / _fast.bit, timing_full*.txt (12x,
16x, 20x, 22x; the two "sdram data pins" rows are new), seeds.txt (all 32
seeds), speed (1.5).
