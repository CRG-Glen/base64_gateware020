# Step 16: clock-enable copies without the inverter, a fourth copy, and the data cache's own read address

Status: ready to build. Branch: `step16-clkena-copies`, from
`step15b-predictor-timing`. **No change in behaviour**: every bench clock
count and every sim output line stays as in step 15b. The gain is timing
margin only (Glen's priority: margin over speed).

## Goal

After step 15b, 5 of 18 seeds pass timing. The commonest miss is
clkena -> kernel: negative on 8 of 18 seeds (2, 3, 6, 7, 12, 14, 15, 17),
worst -1.94 ns. Get that class non-negative on at least 15 of 18 seeds
and the pass rate to at least 7 of 18, and take one known 1T path off the
fetch predictor.

## Background: what was measured (step 15b netlist, 18 seeds)

The kernel's registers are enabled by `clkena_in` and by `clkena_lw`
(= clkena AND (NOT longword OR long_ack)). `tg68_bus.v` supplies both
from registers it sets on the step edge. `clkena_lw` has three copies so
far (kernel changes 2, 4, 5; `docs/HISTORY.md`, steps 8, 12, 14):

| Adapter register | Kernel port | Kernel signal | Feeds | Direct loads |
| --- | --- | --- | --- | --- |
| `k_clkena` | `clkena_in` | `clkena_in` | 7 32-bit registers and more | 96 |
| `k_clkena_lw` (power-on 0) | `clkena_lw_in` | `clkena_lw` | regfile, the opcode/PC/exec process, micro_state, SVmode, MOVEC, sndOPC | **199** (114 FF enables, 85 LUTs) |
| `k_clkena_lw2_n` (inverted, power-on 1) | `clkena_lw2n_in` | `clkena_lw2` = NOT port | the ALU (its `clkena_lw` port), data_read, the MEM_IO process | 3 LUTs, then ~130 registers |
| `k_clkena_lw3` (power-on 1) | `clkena_lw3_in` | `clkena_lw3` | the EA_data / data_write process | 6 |

Where the worst clkena -> kernel paths end, over the 18 seeds:

- **`k_clkena_lw2_n` -> ALU `result_div`** (and `nozero`, `op1_sign`):
  among the worst paths on 10 of 18 seeds, to -1.26 ns. The path is
  register -> **an inverter LUT** (`alu_clkena_lw`) -> the register's own
  LUT. The inverter exists because the copy is stored inverted (the only
  way found in step 14 to stop yosys merging it with `k_clkena_lw`), and
  the kernel and the ALU are separate kept-hierarchy modules, so the
  inversion cannot fold into the ALU's logic. It costs a LUT and a
  routing hop on ~130 one-clock paths.
- **`k_clkena_lw` -> `last_opc_pc`, `exe_pc`, `alu_bf_shift`,
  `alu_bf_loffset`, `alu_bf_ffo_offset`**: to -1.94 ns, on seeds 2, 4, 5,
  7, 9, 12, 14, 17. All of these are assigned in the first
  `IF clkena_lw='1' THEN` block of the kernel's opcode/PC process (the
  process that begins `PROCESS (clk, IPL, setstate, addrvalue, state,
  exec_write_back, ...`, about line 1177 of `TG68KdotC_Kernel.vhd`; the
  block starts about line 1285 and assigns `interrupt`, `decodeOPC`,
  `endOPC`, `execOPC`, `last_opc_pc`, the `alu_bf_*` registers,
  `exe_pc`). That copy has twice the loads of any other.

**A way to keep copies apart without inverting them** (tested by the
planner on a toy design with `synth_ecp5 -abc9`: three registers
survive, a plain fourth merges): give each copy its own output as a
term of its input,

```
k_clkena_lw2 <= X && !k_clkena_lw2;
```

The term is always true when the register is set (a copy is never high
in the clock before a step: steps are at least STEP = 4 clocks apart, in
reset too), so the copy still equals `k_clkena_lw` in every clock; but
no two copies have the same input logic, so yosys cannot merge them, and
it cannot prove the term redundant. So every copy can be active high
with power-on value 0.

One more 1T path, from the fetch predictor (step 15): `fp_rsel_n` -> the
cache RAMs' read address multiplexer `ic_ra` -> the read/write collision
logic of the **data** cache's RAMs (-1.38 ns on seed 15, near zero on 5
and 16). The data cache shares `ic_ra` with the instruction cache, but
the predictor only reads the instruction cache; the data cache's read at
the predicted address is never used.

## The changes

### A. Kernel change 6: active-high copies and a fourth copy

Before editing anything, check the tools: `YOSYS=yowasp-yosys sh
scripts/gen_tg68.sh` must reproduce `rtl/tg68/tg68_020_b0.v` byte for
byte (`git status` clean). If it does not, stop and report.

1. `rtl/tg68/TG68KdotC_Kernel.vhd` (mark each edit `-- Base64 change 6`):
   - new port `clkena_lw4_in : in std_logic := '0';` after
     `clkena_lw3_in`; new signal `clkena_lw4`;
   - generic `ClkenaLW_Ext` gains the value 4. Replace the three
     assignments with:
     ```
     clkena_lw2 <= clkena_lw2_in WHEN ClkenaLW_Ext=2 OR ClkenaLW_Ext=4 ELSE
                   NOT clkena_lw2n_in WHEN ClkenaLW_Ext=3 ELSE clkena_lw;
     clkena_lw3 <= clkena_lw3_in WHEN ClkenaLW_Ext>=3 ELSE clkena_lw;
     clkena_lw4 <= clkena_lw4_in WHEN ClkenaLW_Ext=4 ELSE clkena_lw;
     ```
     and extend the comment above them (4 = change 6: copy 2 active high
     on `clkena_lw2_in` again, and a fourth copy on `clkena_lw4_in` for
     the first block of the opcode/PC process);
   - in the opcode/PC process, the **first** `IF clkena_lw='1' THEN`
     (the block described above) becomes `IF clkena_lw4='1' THEN`. The
     two later tests in the same process (`ELSIF clkena_lw='1'` for
     `PCbase`, `IF clkena_lw='1'` for `exec <= set`) stay on `clkena_lw`.
2. `rtl/tg68/tg68_020.vhd`: generic `CLKLW` default 4; port
   `clkena_lw4_in`, passed to the kernel; extend the header comment.
3. Regenerate `tg68_020_b0.v` with `gen_tg68.sh`.
4. `rtl/base64_tg68/tg68_bus.v`:
   - registers, all `(* keep *)`, all power-on 0: `k_clkena_lw` (as
     now), `k_clkena_lw2`, `k_clkena_lw3`, `k_clkena_lw4`. Delete
     `k_clkena_lw2_n` and the wire `k_clkena_lw2`;
   - defaults at the top of the clocked block: all four `<= 1'b0`;
   - at the two step sites (the reset branch and `task step`), with
     `X = !k_longword || k_long_ack`:
     ```
     k_clkena_lw  <= X;
     k_clkena_lw2 <= X && !k_clkena_lw2;
     k_clkena_lw3 <= X && !k_clkena_lw3;
     k_clkena_lw4 <= X && !k_clkena_lw4;
     ```
   - ports: `.clkena_lw2_in(k_clkena_lw2)`, `.clkena_lw2n_in(1'b1)`,
     `.clkena_lw3_in(k_clkena_lw3)`, `.clkena_lw4_in(k_clkena_lw4)`;
   - rewrite the comments on these registers: why copies exist, the
     self term and why it is always true, that the inverted copy and the
     power-on-1 copy of step 14 are gone.
5. Test benches (`sim/tb_top.sv`, `sim/tb_tg68_bus.sv`): replace the
   kernel change 4/5 checks with one check, on every clock from the
   first: `k_clkena_lw2`, `k_clkena_lw3` and `k_clkena_lw4` each equal
   `k_clkena_lw` (the `clw3_armed` delay is no longer needed: nothing
   powers on at 1). Keep the existing check of `k_clkena_lw` against the
   kernel's own formula.
6. `scripts/check_timing.py`: the `CLKENA` pattern already matches any
   name containing `k_clkena` or `clkena_lw`; confirm in a routed design
   that paths from `k_clkena_lw4` are listed under clkena -> kernel.
7. After synthesis, check the json: four separate registers
   `cpu.k_clkena_lw*_TRELLIS_FF_Q` exist, and count each one's direct
   loads (cells with an input on the register's Q net). Record the
   counts. Expect `k_clkena_lw2` to drive registers and LUTs directly
   (no `alu_clkena_lw` inverter), and `k_clkena_lw` + `k_clkena_lw4`
   to share the old 199.
   **One rebalancing is allowed:** if `k_clkena_lw` still has more than
   130 direct loads and `k_clkena_lw4` fewer than 70, also move the
   `exec <= set` test of the same process to `clkena_lw4`, regenerate,
   and use that.

Mutant (must fail the benches): at the step sites set
`k_clkena_lw4 <= 1'b0`.

### B. The data cache reads at the kernel's address only

In `tg68_bus.v` the data cache's RAMs read `ic_ra`. Give them
`wire [IC_AW-2:0] dc_ra = k_addr[IC_AW:2];` and use it for the four
`dc_*[...]` reads in the `g_dcache` block. `ic_ra` (with the predictor's
multiplexer) then feeds the instruction cache only. Comment: the
predictor never reads the data cache, and the data cache's output is
used only from the read on the edge into DECIDE, when `ic_ra` is the
kernel's address anyway. No test bench change; every result must be
identical.

## Numbers that must not move

Bench clocks (timed pass), as step 15b:

| c | copy | read | scatter | readoff | chip | wrfast | wrmix |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 65892 | 9432 | 6204 | 3756 | 11316 | 31440 | 7464 | 31572 |

`bus`, `top` and `fastmem` output: identical line for line to step 15b's
(run 15b's in a second worktree and `diff`, ignoring the `- ...$finish`
lines, as the step 15b log describes).

## Measuring

Baseline, step 15b (commit f615054), worst 1T / worst multicycle, with
the clkena -> kernel slack where it is negative:

| Seed | Result | Seed | Result |
| --- | --- | --- | --- |
| 1 | -0.09 / -0.25 | 10 | **PASS +0.37 / +0.75** |
| 2 | -0.22 / +2.42 (clkena -0.22) | 11 | -0.92 / +0.91 |
| 3 | -0.82 / +1.88 (clkena -0.82) | 12 | -1.26 / -1.03 (clkena -1.26) |
| 4 | -0.01 / +1.00 | 13 | -1.82 / -0.07 |
| 5 | -1.02 / +1.71 | 14 | -1.94 / +0.85 (clkena -1.94) |
| 6 | -0.29 / +0.20 (clkena -0.07) | 15 | -1.38 / +1.22 (clkena -0.54) |
| 7 | -0.48 / +1.16 (clkena -0.48) | 16 | **PASS +0.22 / +0.22** |
| 8 | **PASS +0.20 / +0.84** | 17 | -0.36 / +0.24 (clkena -0.36) |
| 9 | **PASS +0.30 / +0.22** | 18 | **PASS +0.35 / +2.53** |

Build A and B together (one synthesis), `python3 scripts/build.py full
--seed 1 --seeds 18` in a worktree under /home/user (about 1.5 hours).
Record the table (`seeds.txt`) and, per seed, the clkena -> kernel slack
and its worst start register. If the result is worse than the baseline,
build A alone (revert B) on seeds 1-9 to see which change did it.

## Acceptance criteria

- All three sims, `bench sd` and the eight benches pass with the numbers
  above; sim output identical to 15b; the mutant fails.
- The four clock-enable registers exist in the json; load counts
  recorded.
- clkena -> kernel is negative on at most 3 of 18 seeds and never below
  -0.6 ns.
- At least 7 of 18 seeds pass. The best (largest worst-1T slack) scores
  no worse than 1.13x / 1.29x at 14x / 16x.
- Package `bitstreams/step16_clkena/` (CLAUDE.md, "Test bitstreams"),
  update README (bitstream row; the kernel changes list in "Why the CPU
  is pre-converted Verilog": six marked changes; the timing section) and
  CLAUDE.md's Layout line ("FIVE marked changes" -> SIX), write the log
  below, update `plans/README.md`, and give Glen the links. His test
  list is the usual one; the expectation is **no change** in any
  benchmark against step 15b.

## Fallbacks

1. clkena -> kernel meets its criterion but fewer than 7 seeds pass:
   package the best passing seed anyway if at least 5 pass (no worse
   than 15b), and report the table and the classes that now miss; they
   are the next plan's input.
2. clkena -> kernel does not meet its criterion: record which copy and
   which kernel registers the worst paths end in (the timing report
   names them; map `nNNNN_q` names to signals with the
   `assign <signal> = nNNNN_q; // (signal)` lines in `tg68_020_b0.v`),
   and stop and report. Do not add further copies on your own.
3. Fewer than 5 seeds pass: do not package; stop and report.

## Stop and report if

- `gen_tg68.sh` does not reproduce the current netlist before the edit;
- any bench count or sim output line changes;
- the copies are merged in the json (fewer than four registers);
- a copy differs from `k_clkena_lw` in any clock of any sim.

## Log

(build model: record the load counts, the seed table and what was kept)
