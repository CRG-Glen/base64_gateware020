# Plans: what is in progress, what is next

Start every session here. One model plans a step, another builds it (see
`CLAUDE.md`, "How we work"). A plan file gives the change, the tests, the
numbers that must not move, the acceptance criteria, the fallbacks and
when to stop and report. Results go in the plan's own log section.

## Branch `v2-clock-dma-compact` (handoff, 19 November 2026)

Three items, in this order, each with its own plan file. Nothing is built
yet; no RTL has changed on this branch.

1. **Phase lock to the 7 MHz edge**: `phase-lock-7m.md`. Design written
   and reviewed, **waiting for the owner's approval**. Open question to
   the owner: is there an oscilloscope on a v2.0 board (7 MHz edge to /AS
   at 12x)? If not, the `speed` status line from that board will do. Next
   after approval: the build plan, then hardware stage 1 (stepping proof).
2. **DMA access to fast RAM** (another bus master, e.g. a DMA disk
   controller, reading and writing the accelerator's fast RAM): plan
   written, `dma-fastram.md`, **waiting for the owner's answers** (which
   DMA device, A500+ only or B2000 too, what v2.0 does today). From the
   Base64 PCB: the FPGA controls the address, strobe and data switches and
   always sees BR/BG/BGACK and can drive DTACK, so the board allows it; it
   is blind during DMA today only because the gateware opens the switches.
3. **Compacting for an FPU**: studied, `study-fpu-compact.md`. v2.0 is
   12,985 of 24,288 placed cells (about 4.5-5k of headroom before the
   size that did not route); the CPU core is 75 % of it and nothing worth
   removing. Recommendation: no compaction; an FPU first as an F-line
   trap handler in software, then (if needed) a memory-mapped FP unit of
   an estimated 3-5k LUT4. **Questions to the owner** in the study.

**Settled (19 November 2026): the baseline reproduces on a Mac** (Apple
silicon, macOS; venv with the pinned yowasp-yosys 0.70.0.0.post1259 and
yowasp-nextpnr-ecp5 0.11.1.0.post826, Python 3.15.2; ecppack from
Homebrew prjtrellis 1.4). `build.py full --seed 10 --seeds 1` on this
branch: 11,116 LUT4, 2,647 FF, PASS, worst 1T +0.77 ns, multicycle +2.19
ns, 1.233x / 1.541x; the plain .bit is **byte-identical** to
`bitstreams/exp20x/base64_tg68_full_plain.bit` (SHA1 946fa459...). So
11,116 LUT4 is v2.0's count (11,067 was step 15b's), and the container's
result below was its environment, not the source. Sims on the same Mac
(Verilator 5.054, Homebrew m68k-elf binutils/gcc 16.2 under
m68k-linux-gnu-* names): bus, top, fastmem, bench sd PASS.

Was an open problem: **the v2.0 baseline did not reproduce** in the session's
container. `build.py full --seed 10` from `/root/work/base64_gateware020`
gave 10,772 LUT4 (documented 11,067) and FAIL at 12x (adapter ctrl ->
logic -1.71 ns); same pinned tool versions. Suspected: synthesis depends
on the repository's path: **ruled out**, a rebuild from
`/home/user/base64_gateware020` gave exactly the same (10,772 LUT4, -1.71
ns). Also ruled out: an RTL difference (`a8c9678` to `main` changes
comments only). Environment: Python 3.12.3, wasmtime 47.0.1,
yowasp-runtime 1.96, Verilator 5.020. Cause unknown. Settle this before
changing RTL: on the new machine, build seed 10 first and compare with
`bitstreams/exp20x/` on branch `exp-20x` (its timing report says +0.77 ns
worst 1T; LUT count, the .bit itself).

4. **Cache and write-buffer study** (asked 19 November):
   `study-caches.md`. Sizes, layout and the Chip RAM write buffer measured
   in sim; the SD ROM trim it found is built on branch `sdrom-trim`.

Not pushed: this branch exists only in the local clone (the session had
no GitHub credentials). `git push -u origin v2-clock-dma-compact`.

## State (updated 16 November 2026, after v2.0)

- `main` = **v2.0**: steps 13 to 15b plus the 20x clock (run-time 12x /
  16x / 20x). Runs on Glen's A500+ at all three speeds, hours at 20x.
  Released bitstream = the `exp-20x` build, seed 10.
- **What to build next is in `strategy-after-v2.md`**: the measurements
  behind it, the steps in order (17: instruction cache drops only its
  own entry; 18: `perf` counters; 19: barrel shifter; 20: 16 KB caches;
  X22: a 22x experiment) and the smaller items after them. Steps marked
  "ready" there are built from that file; each has its own log section.
- Waiting for Glen: the hardware test of `exp-7m-pll` (the PLLs fed from
  the Amiga's 7 MHz clock, stage 1; bitstreams in
  `tg68/bitstreams/exp7m_pll/` on that branch).
- The old step and experiment branches are still on GitHub, with their
  test bitstreams (archiving them as tags is Glen's to do: this
  session's git access cannot push tags or delete branches).
- New work branches from `main`. The numbered entries below are the
  history of how v2.0 was reached.

## Next, in order (details: `strategy-after-v2.md`)

(This branch was started from `main` before steps 17 and 18 were
pushed; **the current queue is the plans index on `step18-perf`**.
Updated 20 November 2026 to point there.)

1. **Step 17**, `step17-icache-tag-drop` (Glen's): runs on the A500+ at
   12x, 16x and 20x; see that branch.
2. **Step 18**, `step18-perf` (Glen's): built, first perf runs done; see
   that branch.
3. **Step 19**, `step19-barrel` (from `step18-perf`): built 20 November
   2026, **fallback**: the b1 netlist and a shift/rotate matrix (b0 = b1
   in all 25 groups; `op` -12 %, `c` -1.4 % with b1) are committed, but no
   12x seed in 48 passed, so b0 stays the default. Two margin changes tried
   under it (tag precompare, SDRAM row record) helped on an independent
   step 17 but not on Glen's. Details in its log.
4. **Step 20**, 16 KB caches: after Glen's `perf` numbers.
5. **X22**, 22x experiment: when Glen asks.
6. The smaller items (section 4 there, and `backlog.md`): each needs a
   plan from the planner first.

## How v2.0 was reached (history)

1. ~~`tooling-build-seeds.md`~~ **done** on branch `tooling-build-seeds`
   (from `step15-fetch-predictor`): `build.py full --seed 1 --seeds 9`
   now runs 4 seeds at a time and prints a table. Build step 15b from
   this branch.
2. ~~`step15b-predictor-timing.md`~~ **built** (A and B kept, C reverted;
   see its log). Waiting for Glen's test. Get step 15's
   kernel -> logic margin back and more seeds passing, with no change in
   behaviour. Three small changes, measured one at a time.
3. ~~`step16-clkena-copies.md`~~ **built, not shipped**: no seed passes
   (15b: 5 of 18). Findings in its log, for the planner. Step 15b stays
   current. Was: Timing margin only, no
   change in behaviour: the kernel's clock-enable copies become active
   high (no inverter in front of the ALU), a fourth copy takes half of
   the busiest one's loads, and the data cache stops sharing the
   predictor's read address. Needs GHDL (`setup_cloud.sh` installs it):
   the kernel netlist is regenerated.
4. **`exp18x.md`** **18x works on Glen's A500+** (seed 3, 1.42x the
   worst-case model): SysInfo +12.9%, AIBB +12.2%, xSysInfo +10.8% over
   16x, Frontier timedemo +5.9%. Results in its log. Next, for the
   planner: the real four-speed step (12x/14x/16x/18x, 14x+16x on one
   PLL). Was: an experimental bitstream with 18x
   in place of 14x, to find out on Glen's board how much real margin
   there is. The planner's view after step 16: margin restructuring has
   stopped paying (placement noise is larger than the gains); 5 of 18
   seeds passing is enough to keep building; a faster clock is the
   biggest speed-up left.
5. **`exp20x.md`** **20x works on Glen's A500+** (branch `exp-20x`, seed
   10, 1.54x the worst-case model): SysInfo 18024 (+25% over 16x, +67%
   over 12x), xSysInfo fast RAM 36.85 MB/s, Frontier +8.7% over 16x.
   **Glen's decision: release with 12x, 16x and 20x only** (14x and 18x
   are not a big enough step). `exp-20x` already is that design (16x on
   its own PLL as since step 13, 20x on the other), so the release step
   is a clean-up and rename of this branch; see the end of its log.
6. Anything in **`backlog.md`** needs a plan written first (by the
   planning model, with Glen choosing the order).
