# Step 26: fewer kernel steps per instruction (test suite first)

Status: **26a done; 26b next** (28 November 2026). Branch
`step26-kernel-tests`, from `main` (v2.1). Item 4 of the long plan,
brought forward by Glen. Planned and built by the same model.

## Why

Step 23's counters (Frontier CPU timedemo, 20x): the core's own steps,
4 clocks each, are **79% of the time**. Everything around the core (the
caches, the SDRAM path, the write buffer) is close to what it can do;
steps 23 and 25 measured the last memory-side ideas at ~1% and 0%. The
remaining lever is the number of steps TG68K.C takes per instruction.
`strategy-after-v2.md` 1.1 lists the known costs (12x, `bench op`): a
taken branch 3 steps (one wasted fetch), `bsr` + `rts` 6, `jsr` + `rts`
7, a memory-destination instruction a fourth step, `clr` reads before it
writes, `lea d16(An)` 3, `movem` ~2.5 steps a register, divide 1 bit a
step.

## The parts

- **26a: the instruction test suite** (this branch, no RTL change).
- 26b onwards: one kernel change at a time, each its own branch and
  bitstream, each passing 26a against the v2.1 core, measured with
  `bench op` and `bench c`, chosen by what real code spends steps on.

## 26a: the differential instruction test

The v2.1 core (`rtl/tg68/tg68_020_b1.v`) has run Glen's software at all
four speeds: it is the reference. A changed core must give **the same
architectural result for every instruction**: registers, flags, memory,
exceptions. (Where TG68K.C differs from a real 68020, the difference is
kept; fixing it is not this step.)

1. `sim/gen_isa.py` (seeded, deterministic) writes `sim/isa_test.s`:
   cases, each
   - copy a 64-byte random pattern to the scratch area;
   - load D0-D7 / A0-A6 from the case's table (address registers point
     into the scratch area, index registers small), CCR from the table;
   - the instruction under test;
   - store D0-D7 / A0-A7, SR and the 64 scratch bytes into the case's
     result block; an exception handler (all vectors) records the vector
     and the stacked PC and returns past the instruction.
   Coverage: every integer instruction TG68K.C implements in 68020 mode,
   each size, each addressing mode it takes (the 68000 ones, the 020
   index scale, base and memory-indirect modes), immediates and counts
   at their edges (0, 1, the size's top bit, -1, the shift counts 0, 1,
   8, 31, 32, 63), condition codes for every Bcc / Scc / DBcc taken and
   not taken, `bsr` / `jsr` / `rts` / `rtd` / `rtr`, `link` / `unlk`,
   `movem` lists, BCD, bitfields, `chk` / `chk2` / `cmp2`, `cas`, `pack`
   / `unpk`, divide by zero.
2. `sim/tb_isa.sv`: the kernel and `tg68_bus.v` on a flat 1 MB memory
   with a fixed DTACK, caches on (as on the board), running
   `isa_test.s` to its done marker, then writing the result area to
   `isa_out.hex`.
3. `sh sim/run.sh isa`: builds and runs it with `CORE` (default the v2.1
   core) and compares `isa_out.hex` with the committed reference
   `sim/isa_ref.hex`; prints the first differing cases with the
   instruction's source line, PASS or FAIL. `ISA_REF=1` writes the
   reference.
4. **The test's own test:** the bit-by-bit shifter core (`tg68_020_b0`)
   must PASS (same results, more steps), and a deliberately broken core
   must FAIL (one changed flag in one instruction in the VHDL, generated
   to a scratch netlist, not committed).

## Acceptance (26a)

The suite runs in minutes, covers the list above (the generator prints a
count by instruction), the b0 core passes, a broken core fails, and the
three regression sims are untouched.

## Then (26b, planned after 26a)

Which change first is decided by measurement: a sim histogram of steps by
instruction kind over `bench c` and `bench op`, and on hardware a perf
build counting the steps of a few instruction classes (taken branches,
memory-destination ALU, `movem`, calls). The candidates in order of
expected value: the wasted fetch after a taken branch; the fourth step of
memory-destination instructions; `bsr` / `jsr` / `rts`; `clr`; `lea`.

## Log

(the builder writes here)
- **26a built** (`sim/gen_isa.py`, `sim/tb_isa.sv`, `sim/isa_cmp.py`,
  `sh sim/run.sh isa`): 180 instruction forms x 10 variants = 1,800 cases
  (seed 1), every addressing mode of the 68020 the forms take (the 68000
  ones, index scale, base displacement, memory indirect pre- and
  post-indexed, PC-relative, immediate), edge values, exceptions (divide
  by zero, chk, trap, trapv, trapcc, illegal). 12.2M clocks, ~36 s.
  Reference: `sim/isa_ref.hex` (+ `isa_ref_steps.txt`) from the v2.1 core
  (`tg68_020_b1.v`), kept in git because 26b changes that netlist in
  place. Checks of the test itself: the same core PASSes against itself
  (deterministic); the bit-by-bit shifter core b0 PASSes (0 differ, 233
  cases with more steps: the shifts, +0.23%); nine simple cases
  recomputed in Python match; **two broken cores FAIL**: the multiply's V
  flag forced to 0 (every overflowing mulu.l / muls.l case, SR 2710 vs
  2712), the BCD add's carry forced to 0 (every nbcd / abcd case). The
  regeneration flow (`YOSYS=yowasp-yosys sh scripts/gen_tg68.sh 1`)
  reproduces the committed b1 netlist byte for byte. Generator fixes on
  the way: a second operand never uses a base register the first one
  moved ((An)+ / -(An)), no An source for data-only operations; run.sh
  stops if the program does not assemble.
