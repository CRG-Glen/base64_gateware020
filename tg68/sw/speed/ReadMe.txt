speed 1.4 -- Base64 TG68 system clock (v2.0 gateware)

  speed             show the clock in force
  speed 12          85.1 MHz, the board's own clock (power-on default)
  speed 16         113.5 MHz
  speed 20         141.9 MHz
  speed 20 RISE     the same, 7 MHz sampled on the rising clock edge
  speed 20 FALL     ... or on the falling edge (normally calibrated)

The change happens at once, while running: the gateware waits for the
buses to go idle, switches, recalibrates its 7 MHz capture (~9 ms) and
carries on. Asking for the speed already in force just recalibrates.
The speed stays over a reset; switching the Amiga off and on returns to
12. So if a speed is too fast for a board, a power cycle undoes it.

To start at a higher speed every time, put "speed 20" (or 16) near the
top of S:Startup-Sequence, or in S:User-Startup.

"speed" also reports which clock edge samples the 7 MHz clock, whether
either sample or the phase aligner has moved since the calibration, and
how often the board has switched to the other sample on its own because
the one in use drifted. "The rising-edge sample has moved" at 16x or 20x
is harmless: that sample is not the one in use there.

16x and 20x run the FPGA past its worst-case timing model (20x: about
1.5x). They run on the developer's A500+, but every board is different:
if one is unstable, use a lower speed.

Needs the ICS570B clock chip strapped for 12x (stock). This version is
for the v2.0 gateware: with older gateware (14x) it reports the wrong
speeds; use the speed command that came with that gateware.
