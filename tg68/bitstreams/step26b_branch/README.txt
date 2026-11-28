Base64 TG68: STEP 26b TEST BUILD, faster branches (branch step26b-branch).
Not a release. All four speeds: 12x / 16x / 20x / 22x.

This is v2.1 with one change inside the 68020 core (TG68K.C): a taken
short branch (Bcc.s / bra.s, the most common instruction in compiled
code) now takes 2 CPU steps instead of 3. While the core waits for the
flags to test the condition, it fetches the branch target, so it can go
straight on when the branch is taken. A branch that is not taken runs
exactly as in v2.1.

In simulation: compiled C 4.9% faster at every speed; every one of the
1,820 instruction tests gives exactly v2.1's results (registers, flags,
memory, exceptions). Frontier and the other benchmarks: unknown until you
run them.

This is the first change to the CPU core's own behaviour since v2.0, so
please test broadly, not only the benchmarks:
 1. Boot (Kickstart 3.x and 1.3), Workbench, at 12x then 20x / 22x.
 2. The usual set: SysInfo, AIBB, xSysInfo, the Frontier timedemo and the
    Frontier CPU timedemo, at 12x, 16x, 20x and 22x.
 3. Software with plenty of branches and odd code: games (Frontier,
    Gloom), demos (EON, Desert Dreams), anything self-modifying or
    trackloaded you used before.
Any crash, wrong output or difference from v2.1: say what and at which
speed. v2.1 is the fallback.

Timing: seed 10 of 32 (3 pass, the SDRAM pin check included), 12x
+1.47 ns; the FPGA has to be this much faster than its worst-case model:
16x 1.18x, 20x 1.47x, 22x 1.62x (v2.1: 1.21x / 1.51x / 1.66x). SDRAM data
pins 4.13 / 1.59 ns (limits 4.50 / 1.55).

Use the speed command in this folder (1.5, as v2.1).
