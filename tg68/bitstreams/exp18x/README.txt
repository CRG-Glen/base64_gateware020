Base64 TG68: 18x EXPERIMENT (branch exp-18x). Not a release.

This bitstream is step 15b with the 14x clock replaced by 18x (127.7 MHz).
It answers one question: does your board run at 18x?

  speed18          show the clock in force
  speed18 16       113.5 MHz (as step 15b)
  speed18 18       127.7 MHz (the experiment)
  speed18 12       85.1 MHz (power-on default)

There is no 14x in this build. Use speed18 (in this folder), not the normal
speed command. The board always powers on at 12x: a power cycle undoes any
speed. For normal use, go back to step 15b.

Timing: at 18x the design needs the FPGA about 1.42x faster than the
worst-case model (16x needs 1.26x on this build; builds at up to 1.31x
have run on your board at 16x). Nobody knows whether 1.42x works.

Please test in this order, and stop at the first failure and say what
you saw:
 1. Boot at 12x. speed18 (status), then speed18 16, and a quick SysInfo:
    16x must behave as step 15b.
 2. speed18 18. Does the machine survive the switch? Then speed18 again.
 3. SysInfo, AIBB (caches on and off), xSysInfo, including its fast RAM
    test or AIBB MemTest (the SDRAM at 7.83 ns).
 4. SD card read; a game or the Frontier timedemo for ten minutes (heat).
 5. If it fails only when warm, or only in one test, say which.

If 18x fails only in fast RAM tests, the first suspect is the SDRAM read
data capture at the pins (5.4 ns access time in a 7.83 ns clock), which
the simulation cannot check.
