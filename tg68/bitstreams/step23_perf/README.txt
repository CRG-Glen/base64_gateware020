Base64 TG68: STEP 23 MEASUREMENT BUILD (branch step23-burst). Not a release.

This is the exp-22x design (12x / 16x / 20x / 22x, pin-fed PLLs, as
exp_22x) with the step 18 performance counters, now 24 of them. It runs
exactly as exp-22x does: the counters only watch. Use the perf command in
this folder (1.1) and the speed command (1.5).

The four new counters measure whether burst cache fills (step 23) are
worth building. A line fill would bring the whole aligned 4- or 8-word
line from the SDRAM on a cache miss, not just the word asked for:

  20 fetch misses, same 4-word line as last   misses a 4-word fill would
  21 fetch misses, same 8-word line as last   have caught (8-word: 21);
  22 data misses, same 4-word line as last    counters 7 and 8 are all the
  23 data misses, same 8-word line as last    fetch and data misses

(They are a lower bound: they remember only the previous miss's line.)

Copy perf and speed to C:. Then at 20x (speed 20) or 22x, for each
workload, one at a time:

  perf CLEAR
  <the workload>
  perf >RAM:p.txt        (then copy RAM:p.txt somewhere safe)

Workloads:
  1. the Frontier CPU timedemo
  2. AIBB (its benchmarks, and MemTest)
  3. xSysInfo (its speed tests)
  4. SysInfo's speed test
  5. a game or demo of your choice, a few minutes

A game you can only leave with a reset: the counters freeze at the reset
and keep their numbers. Reset, then run perf.

Send back the text files, named after the workload and the speed.

Timing: seed 7 of 16 (all 16 pass at 12x, +1.58 ns). The FPGA has to be
this much faster than its worst-case model:
  16x 1.14x   20x 1.42x   22x 1.57x
(exp_22x seed 15: 1.20x / 1.50x / 1.65x; your board has run 1.60x.)

Files: base64_tg68_full_perf_plain.bit / _fast.bit, timing_full*.txt
(12x, 16x, 20x, 22x), seeds.txt (all 16 seeds), perf (1.1) with
perf_ReadMe.txt, speed (1.5).
