Base64 TG68: STEP 18 PERFORMANCE COUNTER TEST BUILD (branch step18-perf).
Not a release, never one. It is step 17 plus 20 counters that the perf
command reads (perf_ReadMe.txt says what each counts). It runs exactly as
step 17 does: the counters only watch.

Copy perf and speed to C: (or anywhere in your path). Then, for each of
12x and 20x (speed 12 / speed 20):

  perf CLEAR
  <the workload>
  perf >RAM:p.txt        (then copy RAM:p.txt somewhere safe)

Workloads, one at a time, each with its own perf CLEAR and perf:
  1. SysInfo's speed test
  2. AIBB MemTest
  3. the Frontier timedemo (the Amiga one, and the CPU one)
  4. one more game of your choice
  5. ten minutes of normal Workbench use

A game you can only leave with a reset: the counters freeze at the reset
and keep their numbers. Reset, then run perf.

Send back the text files (name each after the workload and the speed).
They show where the time goes: Chip RAM code fetches, cache hits and
misses, time on the Amiga's bus, write-buffer waits. They decide whether
bigger caches (step 20) are worth building.

Timing: seed 2, 12x passes (+1.43 / +4.88 ns); 16x needs 1.16x the
worst-case model, 20x 1.45x (step 17: 1.27x / 1.58x). This build was
routed with nextpnr's router1 (router2 could not route its clock).
