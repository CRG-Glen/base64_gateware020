Base64 TG68: 20x EXPERIMENT (branch exp-20x). Not a release.

This bitstream is step 15b with the 14x clock replaced by 20x (141.9 MHz).
It answers one question: does your board run at 20x?

  speed20          show the clock in force
  speed20 16       113.5 MHz (as step 15b)
  speed20 20       141.9 MHz (the experiment)
  speed20 12       85.1 MHz (power-on default)

There is no 14x or 18x in this build. Use speed20 (in this folder), not the
normal speed command or speed18. The board always powers on at 12x: a power
cycle undoes any speed. For normal use, go back to step 15b.

Timing: at 20x the design needs the FPGA about 1.54x faster than the
worst-case model (16x needs 1.23x on this build). The 18x experiment ran
at 1.42x. Nobody knows whether 1.54x works.

Please test in this order, and stop at the first failure and say what
you saw:
 1. Boot at 12x. speed20 (status), then speed20 16, and a quick SysInfo:
    16x must behave as step 15b.
 2. speed20 20. Does the machine survive the switch? Then speed20 again.
 3. SysInfo, AIBB (caches on and off), xSysInfo, including its fast RAM
    test or AIBB MemTest (the SDRAM at 7.05 ns).
 4. SD card read; a game or the Frontier timedemo for ten minutes (heat).
 5. If it fails only when warm, or only in one test, say which.

If 20x fails only in fast RAM tests, the first suspect is the SDRAM read
data capture at the pins (5.4 ns access time in a 7.05 ns clock), which
the simulation cannot check. If it fails at once on the switch, the
likeliest cause is plain logic timing (1.54x the model).
