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

The branches stack (13 -> 14 -> 15 -> tooling-build-seeds). New work
branches from `tooling-build-seeds`. Nothing is merged or released until Glen says.

## Queue, in order

1. ~~`tooling-build-seeds.md`~~ **done** on branch `tooling-build-seeds`
   (from `step15-fetch-predictor`): `build.py full --seed 1 --seeds 9`
   now runs 4 seeds at a time and prints a table. Build step 15b from
   this branch.
2. **`step15b-predictor-timing.md`** (ready to build). Get step 15's
   kernel -> logic margin back and more seeds passing, with no change in
   behaviour. Three small changes, measured one at a time.
3. Anything in **`backlog.md`** needs a plan written first (by the
   planning model, with Glen choosing the order).

## Open questions for Glen (from the step 15 test)

- (Settled: SysInfo 12x caches off re-run after a reset gave 5162,
  step 14 5205; within the spread.)
- 14x was not reported; `speed 14` is worth one boot and benchmark.
- `speed` 1.2 (prints the automatic swap count) is in the bitstream
  folders but not yet on the Amiga.
- What next: step 15b (timing margin, no speed change) or something from
  `backlog.md`.

