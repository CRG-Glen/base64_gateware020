Base64 TG68: STEP 23 MEASUREMENT BUILD, SEED 4 (branch step23-burst).
Not a release. A 22x diagnosis build.

The same design as step23_perf (same netlist, same 24 counters, PLLs fed
from the board's own 12x clock, not the Amiga's 7 MHz), routed with seed 4
instead of seed 7. Seed 7 crashes at once at 22x on Glen's board; the
exp_22x build (seed 15) runs there.

The two seeds differ where the timing check does not look: the SDRAM data
pins go straight into the FPGA's logic, and the path from each pin to its
register is routed differently by every seed. It is not part of the
timing check. At 22x the window is tight:

               pin -> register (ns)   mean   worst
  exp_22x seed 15 (runs at 22x)        3.93   4.79
  step23 seed 7  (crashes at 22x)      4.40   5.01
  step23 seed 4  (this one)            4.19   4.79

On the checked logic, seed 4 is WORSE than seed 7 (1.61x against 1.57x at
22x). So:
  seed 4 runs at 22x  -> the SDRAM pin timing is what broke seed 7
  seed 4 crashes too  -> something else (the logic, or the counters)

Test: speed 22, then a quick SysInfo and AIBB MemTest; and speed 20 as
before. perf and speed as in step23_perf.

Timing (checked logic): 12x passes (+1.30 ns); 16x 1.17x, 20x 1.47x,
22x 1.61x.
