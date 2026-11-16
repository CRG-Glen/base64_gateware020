Base64 TG68: STEP 17 TEST BUILD (branch step17-icache-tag-drop). Not a release.

What changed against v2.0: a CPU write no longer throws out instruction-
cache code at other addresses. Up to v2.0, a write to any address dropped
the cached code at every address 8 KB away (the cache is 8 KB, direct-
mapped): a pushed return address, a screen being filled or cleared, could
empty code out of the cache. Now only the written address's own entry
goes (and its Chip RAM mirrors). Self-modifying code and program loading
work as before. Same three speeds: speed 12 / 16 / 20 (the speed command
is in this folder, unchanged from v2.0).

What to expect: benchmarks about as v2.0 (the simulator's compiled C is
0.1% faster, fast RAM write bursts up to 10%). Games and programs that
draw with the CPU while running cached code may gain; nobody knows how
much yet. The run-to-run spread of SysInfo may get smaller.

Timing: seed 10, 12x passes (+0.82 / +1.43 ns). 16x needs the FPGA 1.27x
faster than the worst-case model, 20x 1.58x (v2.0: 1.23x / 1.54x).

Please test:
 1. Boot at 12x; SysInfo, AIBB, xSysInfo (caches on and off).
 2. The same at 16x and 20x (speed 16, speed 20).
 3. The Frontier timedemo at all three speeds.
 4. A game with self-modifying or trackloaded code (the ones used for
    step 11): it must behave exactly as with v2.0.
 5. SysInfo three or four times in a row at one speed: is the spread
    smaller than with v2.0?

Files: base64_tg68_full_plain.bit / _fast.bit (the same design, packed
two ways), timing_full*.txt (12x, and scored at 16x and 20x), seeds.txt
(all 16 seeds built), speed.
