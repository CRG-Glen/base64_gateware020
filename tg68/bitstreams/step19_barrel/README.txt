Base64 TG68: STEP 19 TEST BUILD, the barrel shifter (branch step19-barrel).
Not a release.

What changed against the router1 build you tested (exp-router1, step 17):
the CPU core is built with its barrel shifter. Every shift and rotate
(LSL, LSR, ASL, ASR, ROL, ROR, ROXL, ROXR) now takes one CPU step,
whatever the count; before, it took one step per bit (lsl.l #8 was 8
steps, a shift by 17 was 18). Nothing else changed. The results and
flags of every shift and rotate were checked against the old core on a
matrix of all eight operations, three sizes and counts 0 to 63.

What to expect: the simulator's compiled C is 1.3% faster, the
instruction mix bench 12.4%. Code that shifts a lot (3D maths: Frontier)
should gain more: the Frontier CPU timedemo is the test.

Timing: seed 2, 12x passes (+1.48 ns); 16x needs 1.17x the worst-case
model, 20x 1.46x (exp-router1: 1.15x / 1.43x). 14 of 16 seeds pass.

Please test:
 1. Boot at 12x; SysInfo, AIBB, xSysInfo; SD card.
 2. The same at 16x and 20x, and both Frontier timedemos at all three
    speeds. The CPU timedemo at 20x a few times, and the exp-router1
    build's the same way, back to back, so the two can be compared.
 3. A game or demo or two (anything that would show a wrong shift: 3D
    graphics, decrunching), and a warm run at 20x.

Files: base64_tg68_full_plain.bit / _fast.bit, timing_full*.txt (12x,
16x, 20x), seeds.txt (all 16 seeds), speed (unchanged).
