perf 1.0 -- Base64 TG68 performance counters (step 18 test builds only)

  perf              print the counters; if they were running they run on
  perf CLEAR        zero them and start them
  perf FREEZE       stop them
  perf RUN          start them again (without zeroing)
  perf >RAM:p.txt   the same, into a file

Only the perf test bitstreams (base64_tg68_full_perf*.bit) have the
counters; with any other gateware perf says so and does nothing. They
count, from the moment you start them:

   0 clocks                         every clock of the FPGA's system clock
   1 CPU steps                      every step of the TG68 core; 2-6 split
   2   instruction fetches            them by kind (a data read or write
   3     predicted (4 clocks)         is a step too: steps - fetches -
   4     from the instruction cache   internal steps)
   5   data reads from the data cache
   6   internal steps
   7 SDRAM fetches (cache misses)   fast RAM / MapROM reads that missed
   8 SDRAM data reads (cache misses)
   9-14 bus fetches / reads / writes, Chip RAM or elsewhere: cycles on the
        68000-style bus (the motherboard, custom chips, CIAs, slow RAM,
        the board's own registers)
  15 clocks in bus cycles           how long those took altogether
  16 clocks waiting: Chip write buffer full
  17 clocks waiting: fast RAM write (the SDRAM was busy)
  18 code dropped by writes         instruction-cache entries holding code
                                    that a CPU write threw out
  19 instruction-cache fills

Typical use:

  1. perf CLEAR
  2. run the program you want to measure (a benchmark, a game, a demo)
  3. perf >RAM:p.txt

An Amiga reset (Ctrl-Amiga-Amiga, or a program rebooting) freezes the
counters and keeps their numbers, so a game you can only leave with a
reset can still be measured: reset, then run perf. Switching off clears
them.

The counters are 40 bits: at 20x they run for over two hours before the
clock count wraps.
