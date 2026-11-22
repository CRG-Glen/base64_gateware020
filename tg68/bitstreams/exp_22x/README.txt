Base64 TG68: 22x EXPERIMENT, four speeds (branch exp-22x). Not a release.

This is step 21 (the build you have) with a fourth speed, 22x (156.1
MHz), and the clocks rearranged so that one bitstream has all four:

  speed 12     85.1 MHz   the board's own 12x clock (power-on default)
  speed 16    113.5 MHz   PLL A
  speed 20    141.9 MHz   PLL A (16x and 20x now share one PLL)
  speed 22    156.1 MHz   PLL B (the experiment)

Use the speed command in this folder (1.5: it knows 22). A power cycle
always returns to 12x, so if 22x crashes, switch off and on.

Timing: seed 15, 12x passes (+1.08 ns). The FPGA has to be this much
faster than its worst-case model:
  16x 1.20x   20x 1.50x   22x 1.65x
Your board has run builds at up to 1.58x (step 17 at 20x). 22x is past
that: nobody knows whether it runs.

Please test in this order, and stop at the first failure and say what
you saw:
 1. Boot at 12x. "speed": it should list 12 16 20 22. Then speed 16 and
    speed 20 with a quick SysInfo each: they must behave as step 21 (16x
    now comes from the 20x PLL; that is the change to check).
 2. speed 22. Does the machine survive the switch? Then "speed" again.
 3. A fast RAM test first (AIBB MemTest, xSysInfo's fast RAM test): the
    SDRAM is the most likely thing to fail at 22x (its data arrives about
    1 ns before the FPGA samples it).
 4. SysInfo, AIBB, xSysInfo, the SD card (its clock is 10% faster too),
    both Frontier timedemos.
 5. A warm run at 22x (a game or demo for half an hour).

If 22x fails only in fast RAM tests, the first suspect is the SDRAM read
data. If it fails at once on the switch, plain logic timing (1.65x).

A second build of the same design takes its PLLs' input from the Amiga's
7 MHz clock instead of the board's 12x clock: exp_22x_7m, when it is
ready.

Files: base64_tg68_full_plain.bit / _fast.bit, timing_full*.txt (12x,
16x, 20x, 22x), seeds.txt (all 16 seeds), speed (1.5).
