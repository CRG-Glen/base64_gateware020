speed 1.0 -- Base64 TG68 system clock (step 13 gateware and later)

  speed             show the clock in force
  speed 12          85.1 MHz, the board's own clock (power-on default)
  speed 14          99.3 MHz
  speed 16         113.5 MHz

The change happens at once, while running: the gateware waits for the
buses to go idle, switches, and carries on. The speed stays over a
reset; switching the Amiga off and on returns to 12. So if a speed is
too fast for a board, a power cycle undoes it.

Needs the ICS570B clock chip strapped for 12x (stock). The x16 board-mod
bitstreams (_x16) have a fixed clock and report "cannot change".
