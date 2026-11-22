Base64 TG68: STEP 21 TEST BUILD, 32-bit operands as one pair again
(branch step21-fpair). Not a release.

What changed against step 20: when the CPU fetches a 32-bit immediate or
absolute address that is long-aligned in memory, it gets both words in
one 5-clock step again, not two 4-clock predicted words (8 clocks). This
is how step 15 worked; step 15b took it out to gain timing margin, and
SysInfo lost about 3% then. With router1 there is margin to spare, so it
is back. Nothing else changed.

What to expect: SysInfo is the number this is for (step 15 at 12x / 16x:
11179 / 14925; step 20: 11117 / 14838 even with the barrel shifter's
+3%). The simulator's compiled C is 0.45% faster.

Timing: seed 14, 12x passes (+1.28 ns); 16x needs 1.18x the worst-case
model, 20x 1.47x (step 20: 1.19x / 1.49x). 15 of 16 seeds pass.

Please test as before: SysInfo (a few runs at each speed, it is the one
to watch), AIBB, xSysInfo, SD, both Frontier timedemos, a warm run at 20x.

Files: base64_tg68_full_plain.bit / _fast.bit, timing_full*.txt (12x,
16x, 20x), seeds.txt (all 16 seeds), speed (unchanged).
