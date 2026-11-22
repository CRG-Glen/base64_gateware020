Base64 TG68: STEP 20 TEST BUILD, word and byte writes in 4 clocks
(branch step20-wr4). Not a release.

What changed against step 19 (the barrel shifter build you tested): a
word or byte write to fast RAM now lets the CPU carry on one clock
sooner (4 clocks instead of 5). Longword writes were already one fast
pair write and are unchanged. Nothing else changed.

What to expect: small. The simulator's compiled C is 1.1% faster;
Frontier spends about 10% of its time on fast RAM writes, so at most
about 2% there, probably less.

Timing: seed 11, 12x passes (+1.24 ns); 16x needs 1.19x the worst-case
model, 20x 1.49x (step 19: 1.17x / 1.46x). All 16 seeds pass.

Please test as for step 19: the usual benchmarks at 12x, 16x and 20x,
both Frontier timedemos, a game or two and a warm run at 20x.

Files: base64_tg68_full_plain.bit / _fast.bit, timing_full*.txt (12x,
16x, 20x), seeds.txt (all 16 seeds), speed (unchanged).
