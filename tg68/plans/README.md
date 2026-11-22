# Plans: what is in progress, what is next

Start every session here. One model plans a step, another builds it (see
`CLAUDE.md`, "How we work"). A plan file gives the change, the tests, the
numbers that must not move, the acceptance criteria, the fallbacks and
when to stop and report. Results go in the plan's own log section.

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

1. ~~Step 17~~, `step17-icache-tag-drop`: **runs on Glen's A500+ at
   12x, 16x and 20x** (seed 10, `tg68/bitstreams/step17_ickeep/` on that
   branch). Benchmarks as v2.0, as the sim predicted. One addition to
   the plan (Chip RAM mirrors), see its log. Eon (trackloaded demo)
   runs; Hardwired refuses accelerators on v2.0 too. New baseline: Glen's Frontier
   "CPU" timedemo (31.1 / 41.2 / 57.1 fps).
2. **Step 18**, `step18-perf` (counters in a test build and the `perf`
   command): **built and run** (per-workload numbers in its log: Frontier
   CPU timedemo bound by the Chip write buffer 5.5%, cache misses 4.9%,
   internal steps 21.7%; step 20 not worth it now) (`tg68/bitstreams/
   step18_perf/` on that branch, seed 2, routed with router1). Its log
   has a finding for the planner: router1 passed 14 of 16 seeds where
   router2 could not route this build at all.
3. **`exp-router1`**: step 17's design routed with router1: 16 of 16
   seeds pass, seed 7 1.433x at 20x (best yet). **Runs on Glen's board at
   all speeds, hours at 20x; router1 is now the default flow.**
4. **Step 19**, `step19-barrel` (the barrel shifter; built by a second
   collaborator, 0 of 48 seeds with router2, fallback taken; then
   `exp-router1` merged in and rebuilt with router1): **14 of 16 seeds
   pass**, seed 2 1.459x at 20x. **Runs on Glen's board at all speeds**:
   SysInfo +3%, Frontier CPU timedemo +7% at every speed; long run to come
   (`tg68/bitstreams/step19_barrel/`). Step 20 and a deeper write buffer:
   not worth it (step 18's log).
5. **Step 20**, `step20-wr4` (`step20-wr4.md`): word and byte writes to
   fast RAM in 4 clocks. Built, 16 of 16 seeds pass, seed 11 1.491x at
   20x; **runs on Glen's board at all speeds** (Frontier CPU timedemo
   +1.2 to +1.6%). (The 16 KB caches that the strategy
   called step 20 are shelved: step 18's numbers.) Next of the small
   CPU-side items: 32-bit operands as one pair again (backlog speed 5 /
   strategy 4.1), then data-cache hits in 4 clocks.
6. **Step 21**, `step21-fpair` (`step21-fpair.md`): 32-bit operands as
   one pair again (step 15's predictor behaviour, which 15b removed for
   timing). bench c -0.45%; SysInfo is the number it is for. 15 of 16
   seeds pass, seed 14 1.470x at 20x; **runs on Glen's board at all
   speeds: SysInfo +3.6%** (15b's loss was real).
7. **Step 22** (`step22-dpred.md`): data-cache hits in 4 clocks by
   predicting the next data address (the word after the last read).
   Measured: about 1% (bench c 1.2%). A branch-target table for jumps
   nets only 0.8% (it costs the sequential prediction) and is not
   planned. **Parked** (Glen: about 1% is not worth the timing risk).
8. **`exp-22x`** (`exp22x.md`): 22x (156 MHz), and four speeds in one
   build (12x pin; 16x and 20x sharing one PLL; 22x on the other).
   Built: 16 of 16 seeds pass, seed 15 1.646x at 22x; **waiting for
   Glen's test**, with the 7 MHz-fed build (`--pll7m`, seed 12, 1.596x
   at 22x) beside it.
9. **Next step after Glen's 22x test: burst cache fills** (Glen's choice).
   A miss fills a line of 4 or 8 words (SDRAM burst, both cache banks a
   clock) while the CPU carries on with the first word; today a miss
   brings one pair (32 bits) and a one-word prefetch. Expected: sequential
   fast RAM reads (AIBB MemTest, xSysInfo fast RAM, new code) perhaps
   +20-40%; Frontier perhaps 2-3% (its misses cost ~5%, step 18). Nothing
   with the caches off or for Chip RAM. **Measure first** (how many misses
   a 4- or 8-word line would turn into hits, bench c and the memory
   benches), then plan: SDRAM controller bursts, writes during a fill, an
   access to the line while it fills. The fast RAM path is already
   synchronous (the direct port, step 3); the Amiga's bus cannot be. Then the same from the Amiga's 7 MHz clock (`exp-7m-pll`
   stage 1 was built from v2.0 and never tested).
10. The smaller items (section 4 there, and `backlog.md`): each needs a
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
