# CLAUDE.md: TG68 (68020) build for the Base64 accelerator

Briefing for Claude Code, loaded in full at the start of every session and
again each time it is edited. **Keep it short.** Step history lives in
`docs/HISTORY.md`, work in progress in `plans/`, user documentation in
`README.md`. Read those in parts (grep for the step or the signal), never
whole, and do not copy results into this file.

This folder (`tg68/`) is a self-contained alternative gateware for
jbilander's Base64 Amiga 500 accelerator. It replaces the fx68k 68000 with
TobiFlex's TG68K.C in 68020 mode and keeps the fx68k build's fast RAM, SD
card, autoconfig and MapROM. Everything outside `tg68/` is upstream and is
not modified.

## Owner and hardware

- Glen: electrical engineer, Amiga hobbyist, works on **Windows**. He tests
  everything on real hardware and reports SysInfo / AIBB / xSysInfo
  numbers. Nothing counts as done until he has run it.
- Target: Base64 Rev C carrier, iCESugar-Pro (Lattice
  **LFE5U-25F-6BG256C**), in an **A500+** (Kickstart 1.3, 2.04, 3.1, 3.2,
  DiagROM). SDRAM: IS42S16160J-6.
- Bitstreams load by copying the `.bit` file onto the iCELink USB drive. An
  incomplete copy can boot to lit LEDs but not run: if a build that should
  work does nothing, flash it again first.

## How we work: one model plans, another builds

Glen uses a larger model to **plan** each step and a smaller one to
**build** it.

- **`plans/README.md` is the index**: what is in progress, what is next,
  what is waiting for Glen. Start every session there.
- **Building (the usual session).** Follow the step's plan file. It gives
  the change, the files, the tests to add, the numbers that must not move
  and the acceptance criteria. Do what it says, in its order. Record
  results in the plan file's log section as you go (seed tables, bench
  numbers, what was tried), not in this file.
- **Stop and report to Glen, do not improvise, when:** an acceptance
  criterion cannot be met after the fallbacks the plan lists; a test fails
  in a way the plan does not explain; the fix would change behaviour the
  plan did not mention (bus timing, cache coherency, anything on the
  Amiga's pins); or the plan is wrong. Say what you found and what the
  options are. A redesign is the planner's job.
- **Planning.** Write `plans/<step>.md` in the same form as the existing
  ones: goal, background (with file and signal names), the change in
  order, tests and mutants, numbers that must not move, acceptance
  criteria, fallbacks, stop conditions. Measure before designing: the sim
  has counters for most questions (`sh sim/run.sh bench c`).
- When a step is finished and Glen has run it: add its bullet to
  `docs/HISTORY.md`, its row to the results table there and in
  `README.md`, and update `plans/README.md`. Only then change the short
  "Current state" list below.

## Layout

```
rtl/base64_tg68/   top level (base64_tg68_top.sv), bus adapter (tg68_bus.v),
                   clock generator (clkgen.v)
rtl/tg68/          TG68K.C VHDL (m1nl's fork, a8e6f38) with FIVE marked
                   changes, the tg68_020.vhd wrapper, and tg68_020_b0.v, the
                   GHDL-converted netlist that is actually built (regenerate:
                   YOSYS=yowasp-yosys sh scripts/gen_tg68.sh, ghdl 4.1.0)
rtl/base64_fx68k/  copies of the fx68k build's slaves; every change is
                   marked "TG68:" with the reason
scripts/           build.py (yosys -> nextpnr -> ecppack), check_timing.py
                   (the real timing sign-off), setup_cloud.sh
constraints/       pin constraints (nextpnr .lpf)
sim/               Verilator benches and test programs; sim/README.md
sw/                maprom and speed commands (68000 asm)
docs/HISTORY.md    how every step works, results, ideas (read on demand)
plans/             the current plan, the queue, the backlog
bitstreams/        test and release outputs, NOT in git (see below)
```

## Commands

```
sudo bash tg68/scripts/setup_cloud.sh          # if verilator / yowasp-yosys / m68k gcc are missing
sh sim/run.sh bus | top | fastmem              # the three regression benches
sh sim/run.sh bench c|copy|read|scatter|readoff|chip|wrfast|wrmix|sd
VLFLAGS=-DS15_DEFAULT=0 sh sim/run.sh ...      # the same with step 15 switched off
python3 scripts/build.py full --seed 1 --seeds 8   # 4 seeds at a time, build/full/seed<N>/, table in seeds.txt
python3 scripts/build.py full --skip-synth --seed 9 --seeds 8   # more seeds, same netlist
python3 scripts/check_timing.py build/full/base64_tg68.sdf --paths 4 [--freq 99.32|113.51]
```

Toolchain: yowasp-yosys 0.70, yowasp-nextpnr-ecp5 0.11, ecppack
(fpga-trellis), Verilator 5.020, binutils and gcc for m68k-linux-gnu.
Synthesis: `synth_ecp5 -abc9`, keep_hierarchy on the TG68 modules, then
flatten. nextpnr: `--placer static --router router2`.
**ecppack stays plain by default**; `--compress --freq 38.8` gives the
`_fast` files. `--spimode dual-spi --freq 62` never loaded on this module.

## Rules for every change

1. **All three sims pass** (`bus`, `top`, `fastmem`), plus `bench sd` if
   the bus or the slaves were touched. Add a test for new behaviour, and
   break the new logic on purpose to see the test catch it.
2. **`check_timing.py` says PASS at 12x.** nextpnr's own FAIL is expected:
   it times every path as one clock, and the kernel is multicycle. The
   checker gives each start/end register class its real budget (table in
   README "Timing"). **When you add a register, decide its class**; fix
   the classifier with a reason in a comment and a test bench assertion
   that proves the budget, never accept a fake pass.
3. **Fix structure, don't seed-hunt.** A path that misses by more than
   about 0.5 ns on several seeds gets restructured. What has worked:
   register a decode a clock early when its inputs are stable; load data
   registers unconditionally and put conditions only on enables or valid
   bits; keep new registers out of the kernel-step decision (`step()` in
   tg68_bus.v), which is the tightest 1T path in the design.
4. **Ship only 12x builds that pass timing.** A 0.5 ns miss failed on
   hardware once (step 11). Score the same build at 14x (99.32 MHz) and
   16x (113.51 MHz) by the worst delay/budget ratio; it cannot pass there.
   Builds at up to 1.14x / 1.31x have run on Glen's board.
5. **Keep the previous known-good step.** Each step's bitstreams go in
   their own `bitstreams/stepN_name/` folder with timing reports.
6. Changes to `rtl/base64_fx68k/` files are marked `TG68:` with the reason.
7. **One build, every speed.** The 12x build switches to 14x and 16x at
   run time (`speed`). The `--x16` board-mod build is no longer built,
   simulated or shipped; its `ifdef TG68_X16` code stays, frozen at step
   14b. Clock-dependent logic goes into the run-time speed settings (`spd`
   and the registers loaded from it), not an ifdef.
8. Update `README.md` (status, bitstream table, feature text, timing
   table) with the code.

## Git and GitHub

- **One change per branch**, named after it (`step15-fetch-predictor`).
  Branches stack while earlier steps wait for a hardware test.
- **Commit author:** Glen Milford <casualretrogamer@outlook.com>. **No
  Co-Authored-By or other attribution lines** (Glen's instruction).
- **No pull request, merge or release unless Glen asks.** No force-push
  to `main`, no rewriting history that is on GitHub.
- **Test bitstreams:** commit them to the step's branch under
  `tg68/bitstreams/stepN_name/` with `git add -f` (the folder is
  gitignored), as their own commit whose message says "Drop this commit
  before merging". `_plain` and `_fast`, `timing_full.txt`,
  `timing_full_at14x.txt`, `timing_full_at16x.txt`, and the `speed`
  command. Give Glen the direct links
  (`https://github.com/CRG-Glen/base64_gateware020/raw/<branch>/tg68/bitstreams/...`).
- Commit and push finished work before ending a turn; the session's
  container is temporary.

## The design in one page (details: docs/HISTORY.md, README.md)

- **One clock** (85.13 MHz at 12x; 14x and 16x from two PLLs through a
  glitch-free fabric mux in `clkgen.v`, switched at run time by the
  sequencer in the top level). The TG68 kernel is clock-enabled and
  **multicycle**: `tg68_bus.v` steps it at most every STEP = 4 clocks and
  reads its outputs SETTLE = 3 clocks after a step.
- **Adapter sequencer (tg68_bus.v):** SETTLE -> DECIDE, then one of: an
  internal step (4 clocks); a predicted fetch (step 15, 4 clocks); a
  prefetch-buffer hit (FINISH, 5); a cache lookup (CCMP: a hit steps
  there, 5; a miss goes on to the SDRAM or the bus); a posted fast RAM
  write (FINISH, 5); a direct SDRAM read (DWAIT, DDATA); an old-route
  68000-style bus cycle (SETUP, WAIT, LATCH, FINISH).
- **Caches:** two 8 KB direct-mapped caches (instruction, data), one
  16-bit word per entry, two banks each (even and odd words) so an aligned
  longword is one read. Fast RAM and Kickstart are cacheable; the
  instruction cache also holds Chip RAM code. Write-through; both follow
  CACR EI; CACR CI/CEI, reset and a MapROM change flush both. The cache
  RAMs are read from the kernel's address on the edge into DECIDE.
- **Direct path:** fast RAM and MapROM go straight to `sdram_ctrl` through
  the `dp_*` port: posted writes, pair (32-bit) reads and writes,
  next-word prefetch, a speculative read alongside a data-cache lookup.
- **Bridge (top level):** retimes old-route cycles onto the 7 MHz grid for
  the motherboard; Chip RAM writes go through an 8-entry write buffer.
  The 7 MHz clock is sampled on both edges with a calibration that picks
  the stable one.
- **Timing classes** are in `scripts/check_timing.py`; the tightest are
  the 1T paths into the step decision (cache tag compare -> `step()`), and
  kernel -> logic (3T) since step 15.

## Gotchas already paid for

- **yosys turns a constant `1'bz` on an inout into a 0 driver.** Inputs on
  inout pins are ECP5 `BB` buffers under `ifdef YOSYS`; build.py refuses a
  netlist with inout bits tied to constants (`tied_ok` lists the two
  allowed ones). Verilator honours `1'bz`, so sims cannot catch this.
- **yosys merges identical registers**, `(* keep *)` or not. A deliberate
  copy needs a different power-on value or polarity (`k_clkena_lw2_n`,
  `fp_ac`, `fp_rsel_n`). Check that it exists: grep the synthesized json.
- **nextpnr's target frequency changes nothing** in this flow (12, 24 and
  86 MHz gave byte-identical routed designs). Only the netlist and the
  seed matter. A second clock buffer for the kernel was tried and dropped
  (branch `exp-kernel-clock-buffer`).
- **YoWASP cannot read files under /tmp**: worktrees and build folders go
  under /home/user.
- Do not run two sims at once in the same `sim/` folder (shared obj_dir).
  Use a git worktree for a build while you edit and simulate.
- `syn_useioff` cannot go on registers that are also read internally;
  pin registers in one I/O block must share CE/LSR nets.
- `pkill -f build.py` from a shell whose command line contains "build.py"
  kills that shell. Kill by PID.
- Verilator: `$display(cond ? "A" : "B")` prints a number (use if/else); a
  delayed continuous assign is inertial (use `always @(x) y <= #d x`);
  `defparam` into the DUT does not work (use a `` `define `` default, as
  `S15_DEFAULT`).
- A carry-chain equality compare is slower than `==` here (5.6 vs 4.7 ns).

## Current state (details and numbers: plans/README.md, docs/HISTORY.md)

- `main` = step 12 (released as v1.5), known good on hardware.
- Step 13 (run-time 12x/14x/16x, `speed`) and step 14 (timing headroom):
  run on Glen's A500+ at all three speeds. Not merged.
- Step 14b (7 MHz capture fix, kernel change 5) and step 15 (fetch
  predictor): **run on hardware** at 12x and 16x (SysInfo +15% caches
  on). Not merged.
- Branches stack: `step13-pll-speed` -> `step14-timing-headroom` ->
  `step15-fetch-predictor` -> `tooling-build-seeds`. New work starts from
  the newest one.

## Licensing (unresolved; check before publishing anything new)

TG68K.C: LGPL-3.0. SD controller files: GPL-2.0-only (possibly
incompatible with LGPL-3.0 in one bitstream). base64_gateware has no
top-level licence (ask jbilander). Base64 hardware: CC BY-SA 4.0. No
licence chosen for Glen's own additions yet.
