# Study: compacting for an FPU (where the logic goes, what an FPU could fit)

Asked for on 19 November 2026 ("see what can be done, judge after"), third
item of `v2-clock-dma-compact`. Measured 20 November 2026 on macOS
(toolchain in `README.md` here; GHDL 4.1.0 from the official Ubuntu 22.04
build, run in Docker: it regenerates `rtl/tg68/tg68_020_b0.v` **byte for
byte**, so the variants below are exact). A study for the planner, not a
step: nothing is built or committed except this file.

## 1. Where v2.0's logic goes

v2.0 (seed 10): 11,116 LUT4, 629 CCU2C, 2,647 FF, 35 of 56 EBR, 10 of 28
MULT18X18D. **Placed: 12,985 of 24,288 logic cells (53 %).** A design of
about 18k cells did not route (handoff), so the practical ceiling is
about 17-18k: **about 4.5-5k cells of headroom**, before timing (12x is
already marginal; see step 19's log on `step19-barrel`).

| block | LUT4 | FF | notes |
| --- | --- | --- | --- |
| TG68 kernel (`tg68kdotc_kernel`) | 4,271 | 776 | decode, microsequencer, register file (LUT RAM), EA |
| TG68 ALU (`tg68k_alu`) | 4,046 | 190 | + 10 DSP |
| adapter (`tg68_bus.v`, caches' logic) | ~1,040 | ~640 | caches themselves are block RAM |
| top level (bridge, write buffer, speed, misc) | ~570 | ~420 | |
| SD controller | ~440 | ~210 | + 8-15 EBR |
| SDRAM controller | ~280 | ~200 | |
| fast RAM / autoconfig | ~150 | ~130 | |
| turbomem ROM board | ~130 | ~85 | + 4 EBR |

(kernel and ALU from yosys's hierarchy stats; the rest by cell-name prefix
in the flattened netlist, +/- a few %.)

**The CPU core is 75 % of the design.** Inside the ALU (standalone
synthesis with the hierarchy kept, which reproduces the build's 4,271 /
4,046 exactly):

| ALU part | LUT4 | how measured |
| --- | --- | --- |
| 32-bit divider (DIVx.L) | ~640 (557 ALU + 79 kernel) | `DIV_Mode => 3` |
| multiply logic around the DSPs | ~430 net | `MUL_Mode => 3` |
| the rest: add/sub, logic, 1-bit shifter, BCD, bitfield datapath, flags, result mux | ~3,000 | |

## 2. The kernel generics (whole design, seed 10)

| core | LUT4 | cells | DSP | 12x seed 10 | cost |
| --- | --- | --- | --- | --- | --- |
| b0 (v2.0) | 11,116 | 12,985 | 10 | PASS | |
| b1 (barrel shifter) | 11,189 | 13,058 | 10 | FAIL (-0.85 multicycle) | step 19 |
| no bitfields | 10,967 | 12,752 | 10 | FAIL | BFxxx trap as illegal |
| soft multiplier | 11,347 | 13,164 | **0** | PASS | MULU.W 4 -> 68 clocks, .L 8 -> 136; `bench c` +3.7 % |
| both | 10,888 | 12,621 | 0 | PASS | both of the above |

(One seed each: the PASS/FAIL column is placement noise, not a verdict.)

## 3. Findings

- **There is no big compaction.** v2.0 already uses the no-barrel core.
  Everything removable is small and costs compatibility or speed: no
  bitfields -149 LUT4 (68020 software using BFxxx breaks), no divider
  ~-640 (DIVx.L breaks: not an option). The adapter, bridge and slaves are
  ~2.7k together and all needed.
- **Block RAM is not the limit**: 21 free in v2.0, 28 with `sdrom-trim`,
  31 if the turbomem ROM is trimmed too (227 words in 4 EBR -> 1).
- **DSPs are not the limit**: 18 of 28 free. The soft multiplier would
  free 10 more for +231 LUT4 and a 17x slower MULU: not worth it.
- **So an FPU has to fit in the ~4.5-5k cells of headroom**, and stay out
  of the CPU's tight paths. Steps 18-20 will take a little of it (perf
  counters a few hundred; step 20's bigger caches are block RAM).

## 4. How an FPU could attach

TG68K.C has **no coprocessor interface**: every F-line opcode traps to
vector 11 (README "What's different from a real 68020"). So a drop-in
68881/68882 (coprocessor bus cycles in CPU space) would need the kernel
itself changed: VHDL in the 4-clock multicycle kernel, the riskiest place
in the design. Three ways, cheapest first:

**A. Software only (no gateware).** An F-line trap handler (loaded like
`speed`/`maprom`) decodes FPU instructions and does them in integer code,
sets `AttnFlags` AFF_68881/68882 so programs and exec use it (exec then
issues FSAVE/FRESTORE on task switches: the handler must do those too).
At 12x-20x the integer core is fast enough that this may already be
usable for the programs that need an FPU at all. Zero logic, zero timing
risk; measures demand before any gateware is spent.

**B. Software trap + a memory-mapped FP unit.** The same handler, but the
arithmetic (FADD/FSUB/FMUL/FDIV/FSQRT/FCMP and the int/single/double/
extended conversions) is done by a hardware unit in the FPGA at a fixed
address (in the board's autoconfig space or CPU space), 80-bit extended
internally. The unit is a slave on the adapter's direct/fast path, with
registers at its boundary: **its timing is its own**, multicycle inside,
never in `step()`'s cone. Transcendentals (FSIN, FETOX, FLOGN, ...) stay
in software on top of it, the way the 68040's FPSP does them. Size: to be
measured; a planner's estimate for an iterative extended-precision unit
(DSP multiplier, radix-2/4 divide and square root, normalise/round) is
**3-5k LUT4**, which is the whole headroom. The trap costs tens of clocks
per instruction; at 85-140 MHz still far faster than a real 68881.

**C. A coprocessor interface in the kernel + the same FP unit.** Full
68881 protocol (FSAVE/FRESTORE frames, FPU exceptions, mid-instruction
interrupts). Most compatible, most work, and it changes the kernel. Only
if A/B show compatibility problems that matter.

## 5. Recommendation (for the planner)

1. Do not compact the CPU for this: there is nothing worth taking out.
2. Start with **A** (software): it answers "which programs, how much FP
   time" on Glen's machine with no gateware change. Write it as a plan
   with the test programs Glen cares about.
3. If A is too slow for those programs, plan **B**: first a synthesis-only
   trial of the FP unit to replace the 3-5k estimate with a number, then
   decide whether it fits beside steps 18-20.
4. Independent of the FPU: `sdrom-trim` and a turbomem ROM trim free
   block RAM for step 20.

## Questions for Glen

1. Which programs do you want an FPU for (renderers, demos, games with
   68881 versions, benchmarks)? That decides A vs B.
2. Is a 68881-compatible result enough, or must FSAVE/FRESTORE frames
   look like a real 68882's (some programs check)?

## 6. Reproducing these numbers

GHDL in Docker (`ubuntu:22.04`, `linux/amd64`, the release tarball
`ghdl-gha-ubuntu-22.04-mcode.tgz` of v4.1.0), the same commands as
`scripts/gen_tg68.sh` with `-gBARREL/-gBITFIELD/-gMULHW`, then
`fix_latches.py` with yowasp-yosys on the Mac. The DIV/MUL measurements
edit `MUL_Mode`/`DIV_Mode` in a scratch copy of `tg68_020.vhd` only.
Standalone ALU/kernel: `synth_ecp5 -abc9 -noflatten -top tg68_020; stat`.
