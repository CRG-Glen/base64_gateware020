Base64 TG68: 7 MHz PLL EXPERIMENT (branch exp-7m-pll). Not a release.

This is v2.0 with one change: the FPGA's two PLLs, which make 16x and 20x,
take their input from the Amiga's own 7.09 MHz clock instead of the
board's 85.13 MHz clock (the ICS570B). 7.09 MHz is below the PLL's rated
minimum input (8 MHz), so this tests whether they lock and run cleanly.

12x is unchanged (it is the ICS570B's clock, from the pin), so the board
always powers on and boots as v2.0 does. If a PLL does not lock, speed
simply will not offer that speed. Benchmarks should match v2.0.

The speed command in this folder is v2.0's (speed 1.4).

Please test, in this order:
 1. Boot. Run "speed": does "Available:" list 12 16 20? (16 and 20
    appear only if their PLL has locked on the 7 MHz clock.)
 2. speed 16, then speed 20, with "speed" after each. Does the switch
    work, and does it stay up?
 3. SysInfo, AIBB and xSysInfo at 16x and 20x, against v2.0's numbers.
 4. A long warm run at 20x (a game, a demo or the Frontier timedemo),
    then "speed" again: any sample moved, any automatic swaps?
 5. Anything odd that v2.0 did not do (glitches, slower, crashes): say
    which speed and when.

Timing (the logic, not the clock source): 20x needs the FPGA about 1.58x
faster than the worst-case model on this build (v2.0's file: 1.54x),
16x 1.26x (v2.0: 1.23x).
