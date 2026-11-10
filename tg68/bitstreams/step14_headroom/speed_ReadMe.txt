speed 1.1 -- Base64 TG68 system clock (step 13 gateware and later)

  speed             show the clock in force
  speed 12          85.1 MHz, the board's own clock (power-on default)
  speed 14          99.3 MHz
  speed 16         113.5 MHz
  speed 16 RISE     the same, 7 MHz sampled on the rising clock edge
  speed 16 FALL     ... or on the falling edge (normally calibrated)

The change happens at once, while running: the gateware waits for the
buses to go idle, switches, recalibrates its 7 MHz capture (~9 ms) and
carries on. Asking for the speed already in force just recalibrates.
The speed stays over a reset; switching the Amiga off and on returns to
12. So if a speed is too fast for a board, a power cycle undoes it.

"speed" also reports which clock edge samples the 7 MHz clock and
whether either sample, or the phase aligner, has moved since the
calibration (for testing; nothing should move).

Needs the ICS570B clock chip strapped for 12x (stock). The x16 board-mod
bitstreams (_x16) have a fixed clock and report "cannot change".
