# Plans: what is in progress, what is next

Start every session here. One model plans a step, another builds it (see
`CLAUDE.md`, "How we work"). A plan file gives the change, the tests, the
numbers that must not move, the acceptance criteria, the fallbacks and
when to stop and report. Results go in the plan's own log section.

## State (updated at the end of step 15)

| Step | Branch | State |
| --- | --- | --- |
| 12 | `main` | Released (v1.5), known good on hardware |
| 13 run-time speed | `step13-pll-speed` | Runs on Glen's A500+ at 12x / 14x / 16x. Not merged |
| 14 timing headroom | `step14-timing-headroom` | Seed 8 build runs on hardware. Not merged |
| 14b capture fix, kernel change 5 | same branch, `bitstreams/step14b_cal/` | In step 15, which runs: 12x `speed` reads $170C (rising sample, clean) |
| 15 fetch predictor | `step15-fetch-predictor`, `bitstreams/step15_fpred/` | **Runs on hardware** at 12x and 16x: SysInfo +15% caches on (numbers in docs/HISTORY.md). Not merged |
| tooling | `tooling-build-seeds` | Done (PC side only) |
| 15b predictor timing | `step15b-predictor-timing`, `bitstreams/step15b_fpred/` | **Runs on hardware** at 12x and 16x; 5 of 18 seeds pass, 14x / 16x 1.13x / 1.29x. SysInfo caches on 3.4% below step 15 at both speeds (AIBB, Frontier, xSysInfo 16x unchanged): spread or change A's cost, open |

The branches stack (13 -> 14 -> 15 -> tooling-build-seeds -> step15b).
New work branches from `step15b-predictor-timing`. Nothing is merged or released until Glen says.

**For the planner: read `report-after-15b.md` first.** It summarises the
hardware results, the timing picture after step 15b, Glen's direction
(margin over small speed losses) and the options for the next step.

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
5. Anything in **`backlog.md`** needs a plan written first (by the
   planning model, with Glen choosing the order).

## Open questions for Glen (from the step 15 test)

- (Settled: SysInfo 12x caches off re-run after a reset gave 5162,
  step 14 5205; within the spread.)
- 14x was not reported; `speed 14` is worth one boot and benchmark.
- `speed` 1.2 (prints the automatic swap count) is in the bitstream
  folders but not yet on the Amiga.
- What next: step 15b (timing margin, no speed change) or something from
  `backlog.md`.

