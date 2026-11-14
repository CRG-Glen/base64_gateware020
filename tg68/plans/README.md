# Plans: what is in progress, what is next

Start every session here. One model plans a step, another builds it (see
`CLAUDE.md`, "How we work"). A plan file gives the change, the tests, the
numbers that must not move, the acceptance criteria, the fallbacks and
when to stop and report. Results go in the plan's own log section.

## State (updated at the v2.0 release)

- `main` = **v2.0**: steps 13 to 15b plus the 20x clock (run-time 12x /
  16x / 20x). Runs on Glen's A500+ at all three speeds, hours at 20x.
  Released bitstream = the `exp-20x` build, seed 10.
- The old step and experiment branches are still on GitHub, with their
  test bitstreams (archiving them as tags is Glen's to do: this
  session's git access cannot push tags or delete branches).
- New work branches from `main`. The entries below are the history of
  how v2.0 was reached; the backlog (`backlog.md`) is what is left.

## Queue, in order

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

## Open questions for Glen (from the step 15 test)

- (Settled: SysInfo 12x caches off re-run after a reset gave 5162,
  step 14 5205; within the spread.)
- 14x was not reported; `speed 14` is worth one boot and benchmark.
- `speed` 1.2 (prints the automatic swap count) is in the bitstream
  folders but not yet on the Amiga.
- What next: step 15b (timing margin, no speed change) or something from
  `backlog.md`.

