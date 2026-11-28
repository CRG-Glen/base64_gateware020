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
- **Where compiled C spends its steps** (`VLFLAGS=-DOPHIST sh sim/run.sh
  bench c`, `sim/ophist.py`; new: tb_top prints every instruction of the
  timed pass with its kernel steps and clocks, split at `decodeopc`):
  7,379 instructions, 2.00 steps and 8.62 clocks each. Largest shares of
  the clocks: **Bcc 20.6%** (1,145: taken .s 769 x 3 steps, 13.0 clocks;
  not taken .s 364 x 2 steps, 8.2 clocks), move.b mem->reg 12.1%, move.l
  reg->mem 7.0%, move.l mem->reg 5.3%, move.l mem->mem 4.8% (5.4 steps),
  jsr 3.6% (abs.l 6 steps, (An) 4), rts 2.6% (3 steps), lea idx(An) 2.4%
  (4 steps), movem 3.9% (7.2 steps for ~4 registers), addq mem 1.9%
  (7.7 steps).
- Why a branch costs 2-3 steps (`TG68KdotC_Kernel.vhd`, "0110" and
  `bra1`): the decode step sets `setstate "01"` (no fetch) and goes to
  `bra1`, where `exe_condition` is first valid (the previous
  instruction's flags are only final then); taken: `TG68_PC_brw`, then
  `nop` fetches the target. So: decode, condition, target. A taken .s
  branch at 2 steps would save ~769 x 4-5 clocks, **~5.5% of bench c**; a
  not-taken one at 1 step ~2.3%. 26b: read the kernel's prefetch and
  flag timing first, then plan the change (likely candidates: evaluate
  the condition at decode when the previous instruction did not write
  the flags; or fetch the next word in `bra1` when not taken).

## 26b: taken short branches in 2 steps (planned 28 November 2026)

Branch `step26b-branch`, from `step26-kernel-tests`.

### How a Bcc.s runs today (TG68KdotC_Kernel.vhd)

Edges E0, E1, E2, E3 are kernel steps; `state` is the bus cycle that runs
between two edges (set from `setstate` at the earlier one).

- E0 (end of the previous instruction): `setopcode`, `opcode <=
  data_read` (the Bcc word); `state <= 00`: the cycle E0-E1 fetches
  Bcc+2 (`TG68_PC` = the address being fetched).
- E1 (decode, `micro_state` idle): the "0110" branch sets `setstate
  "01"` (no bus cycle) and `next_micro_state <= bra1`; `last_opc_read <=`
  the Bcc+2 word, `TG68_PC <=` Bcc+4. The previous instruction's ALU
  writes `Flags` at this same edge, and `exe_opcode <= opcode`.
- E2 (`bra1`): `exe_condition` (from `exe_opcode` and the registered
  `Flags`) is first right. Not taken: nothing; `setopcode` with `state`
  01 takes `opcode <= last_opc_read` (Bcc+2): **2 steps**. Taken:
  `TG68_PC_brw` (PC = target), `next_micro_state <= nop`.
- E3 (`nop`): the cycle E2-E3 fetched the target; `setopcode`,
  `opcode <= data_read`: **3 steps**.

The condition cannot move to E1: the flags it needs are written at E1
by the ALU, on v2.1's worst kernel path (register file -> ALU -> flag
register, 36.7 ns of 46.5); putting the condition and the PC adder behind
it would cost 20x / 22x their margin.

### The change: fetch the target in the condition step

The cycle E1-E2 is idle today. The target is known at E1 (`TG68_PC` +
the 8-bit displacement), whatever the condition. So:

1. Kernel (a sixth marked change, `-- Base64 26b`): at E1, for a Bcc.s
   (not bra/bsr, not .w/.l) with no trace bit and no pending bus error:
   `br_tgt <= TG68_PC + sext(opcode(7:0))` (a new adder, from registers),
   `brspec <= 1`, and the address for the E1-E2 cycle (`memaddr_delta_rega`)
   = that target. `state` stays 01, so everything the kernel does at E2
   is as today when the branch is not taken.
2. Kernel output `br_fetch` (micro_state = bra1 and brspec): the adapter
   reads the instruction cache at the address during the idle cycle and,
   on a hit, puts the word on `data_in` (as for a cached fetch) and raises
   a new kernel input `br_ok`. On a miss nothing is fetched (no SDRAM or
   Chip RAM access for a branch that may not be taken).
3. Kernel at E2 (`bra1`), taken AND `br_ok`: as if the cycle had been a
   fetch of the target: `next_micro_state` idle (decode next), `opcode
   <= data_in`, `last_opc_read <= data_in`, `last_opc_pc` and `exe_pc <=
   br_tgt`, `TG68_PC <= br_tgt + 2` and the next fetch address the same;
   an interrupt waits one instruction (setopcode wins at this boundary).
   Taken without `br_ok`: today's path. Not taken: today's path.
4. Adapter (tg68_bus.v): a DECIDE branch for an internal step with
   `br_fetch`: the cache lookup as for a fetch (CCMP), a hit steps with
   the word and `br_ok`; a miss steps as an internal step. The fetch
   predictor follows the target (the next fetch is target+2 when taken).
   `br_ok` is an adapter -> kernel input: it must be stable 2 clocks
   before the kernel samples it (tb assertion, as `ks_chg`).

### Expected (bench c, 12x)

Taken .s: 13 -> ~9 clocks (769 of them); not taken: 8.2 -> ~9-10 (the
lookup is CCMP's 5 clocks, and the predictor then points at the target):
**about -3.7% clocks** (63,900 -> ~61,500). Frontier unknown: a perf
counter for taken branches goes into the test build.

### Tests

`sh sim/run.sh isa` against the v2.1 reference (0 differ; branch cases
fewer steps), and gen_isa additions: a not-taken and a taken Bcc.s
followed by a trapping instruction (illegal, divide by zero, trap) so
the stacked PC after each path is compared; Bcc.s to a target that is
not cached (first pass) and cached (second pass); a branch to itself.
The three regression sims, every bench (bench c must fall by about the
amount above, `bench op` taken bra.s 13 -> 9), `bench sd`. Mutants:
`br_ok` ignored (garbage opcode on a miss: isa must fail), the target
off by 2, the not-taken path taking `data_in`.

### Stop conditions

- Timing: the new adder and the E2 overrides are kernel -> kernel (4T);
  if the 22x ratio rises by more than ~0.03x, report before going on.
- Anything in the isa suite that differs.
- **26b, as built** (the plan's design, simplified): no adapter change
  and no new ports. In bra1 of a Bcc.s whose condition holds (`br_take`),
  the kernel's `busstate` output says fetch, `addr_out` is the target
  (set at the decode, `br_tgt`), and the data strobes go low; the
  adapter does an ordinary fetch (cache, SDRAM or the bus), so there is
  no `br_ok` and no question of a miss. Not taken: the cycle stays
  internal, exactly as v2.1. The kernel's own `state` stays 01 either
  way; at E2 `br_take` loads `opcode`, `last_opc_read` from `data_in`,
  `exe_pc` / `last_opc_pc` from `br_tgt`, `TG68_PC <= br_tgt + 2`, and an
  interrupt waits one instruction.
- First version failed the new isa cases: a taken branch to a target not
  in the cache hung (case 1711, `bpl.s` to an `illegal`): the bus fetch's
  data strobes followed the kernel's idle-cycle memmask, so the slave
  never answered. bench c and the regression sims had passed because all
  their branch targets were cached. Fix: `nUDS` / `nLDS` low while
  `br_take` (outputs only). gen_isa.py gained `bcc.s+trap` (a taken or
  not-taken branch, then illegal / trap / divide by zero / chk on each
  path: the stacked PC compared) and `bcc.s loop` (uncached first, then
  cached); 1,820 cases; the reference remade on the v2.1 core
  (`git show 4158f10~1:tg68/rtl/tg68/tg68_020_b1.v >
  rtl/tg68/tg68_020_v21.v; CORE=tg68_020_v21 ISA_REF=1 sh sim/run.sh
  isa`). **isa: 0 of 1,820 differ, 47 cases with fewer steps.** Mutants:
  the PC after the target +4 instead of +2 (13 differ, then lost) and
  `br_take` without the condition (5 differ, then lost): both FAIL.
  tb_isa's timeout cut to 60M clocks (a lost program now fails in ~2
  minutes, not 10).
- Benches (first version; all targets cached there, so the same with the
  fix, rechecked below): bench c 63,900 -> **60,792 (-4.9%)**, at 20x
  38,676 -> 36,816, at 22x 35,232 -> 33,564; coff 120,024 -> 117,048
  (-2.5%); copy, read, scatter, readoff, chip, wrchip, wrfast, wrmix, sd
  unchanged. bench op: bra.s / bne.s taken 2 steps, 8 clocks (13 before);
  beq.s not taken 2 steps, 8 clocks (as before).
- Regression with the fix: bus, top, fastmem (and PERF=0, CAL_TEST) PASS;
  isa 0 of 1,820 differ; every bench as the first version (bench c
  60,792, coff 117,048; the rest unchanged); bench sd PASS.
