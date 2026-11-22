Base64 TG68: ROUTER1 TEST BUILD (branch exp-router1). Not a release.

The same design as step 17 (a write drops only its own instruction-cache
entry), placed and routed with nextpnr's router1 instead of router2. No
logic change at all: it should behave and benchmark exactly like step 17.
The point is timing margin: all 16 seeds pass at 12x (router2: 2 of 16),
and this one (seed 7) is the best-margin build the design has had:

                      12x slack   16x needs   20x needs (x worst-case model)
  this build, seed 7   +1.53 ns    1.146x      1.433x
  step 17, seed 10     +0.82 ns    1.266x      1.582x
  v2.0,    seed 10     +0.77 ns    1.233x      1.541x

Please test as for step 17:
 1. Boot at 12x; SysInfo, AIBB, xSysInfo; SD card.
 2. The same at 16x and 20x (speed 16, speed 20), and both Frontier
    timedemos.
 3. A long warm run at 20x (an hour or more of a game or demo): the reason
    for this build is more margin at 20x.

If anything behaves differently from step 17, say what: the logic is the
same, so a difference would be the routing.

Files: base64_tg68_full_plain.bit / _fast.bit, timing_full*.txt (12x, 16x,
20x), seeds.txt (all 16 seeds), speed (unchanged from v2.0).
