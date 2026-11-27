Base64 TG68: STEP 25 MEASUREMENT BUILD, the Chip RAM write buffer's depth
(branch step25-chip-wbuf). Not a release. **20x at most: do not use 22x.**

This is v2.1 plus the performance counters, with the Chip RAM write
buffer able to hold 32 entries. Its depth is set at run time:

  perf WB 8      as v2.1 (the power-on depth)
  perf WB 16
  perf WB 32

The change takes effect once the buffer is empty (at once, in practice).
perf's report shows the depth in force, and two new counters: 20 and 21
are the clocks with more than 8 and more than 16 entries waiting.

The question: in the Frontier CPU timedemo, 5.5% of the time went on
waiting for a full buffer (step 23's counters). Does a deeper buffer give
that time back, or is the Amiga's bus simply the limit?

Copy perf (1.2) and speed to C:. At 20x (speed 20), for each depth:

  perf WB 8          (then 16, then 32)
  perf CLEAR
  the Frontier CPU timedemo
  perf >RAM:p.txt    (and note the fps)

Then, if you can, the Frontier Amiga timedemo and a game at depth 8 and
32. Send the text files and the fps, named by depth.

Why 20x only: the extra logic pushes the SDRAM data pin paths out (none
of 32 seeds met the 22x limit, 4.50 ns). This seed's longest is 4.93 ns;
the longest that has run at 20x on your board is 5.01 (the step 23
counter build). Timing: seed 28, 12x +0.98 ns; 16x 1.21x, 20x 1.51x.

Files: base64_tg68_full_perf_plain.bit / _fast.bit, timing_full*.txt,
seeds.txt (all 32), perf (1.2) with perf_ReadMe.txt, speed (1.5).
