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
| 14b capture fix, kernel change 5 | same branch, `bitstreams/step14b_cal/` | **Waiting for Glen's test** |
| 15 fetch predictor | `step15-fetch-predictor`, `bitstreams/step15_fpred/` | **Waiting for Glen's test** |

The branches stack (13 -> 14 -> 15). New work branches from
`step15-fetch-predictor`. Nothing is merged or released until Glen says.

## Queue, in order

1. **`tooling-build-seeds.md`** (ready to build, no hardware risk).
   build.py keeps every seed's files and runs seeds in parallel. Do this
   first: step 15b needs nine-seed runs and they are tedious by hand.
2. **`step15b-predictor-timing.md`** (ready to build). Get step 15's
   kernel -> logic margin back and more seeds passing, with no change in
   behaviour. Three small changes, measured one at a time.
3. Anything in **`backlog.md`** needs a plan written first (by the
   planning model, with Glen choosing the order).

## Waiting for Glen (do not chase; act when he reports)

He was asked to test `step14b_cal` and `step15_fpred`:

- boot and general use on his Kickstarts at 12x, 14x and 16x;
- SysInfo, AIBB and xSysInfo, caches on and off, at 12x and 16x
  (expected for step 15: caches-on Dhrystones about +10% over step 14,
  caches-off unchanged);
- games and demos, especially ones that decrunch or patch their own code;
- `speed` after a cold boot and after running a while at each speed
  (step 14b: at 12x it should report the rising-edge sample, and the
  "switched on its own" count should be 0, perhaps 1 at 12x when warm);
- xSysInfo Chip RAM at 12x after `speed 12 rise` and after `speed 12 fall`.

When he reports:

- **Works:** add the numbers to the results table in `docs/HISTORY.md`
  and `README.md`, mark the step "runs on hardware" in both and in the
  table above, and change "Current state" in `CLAUDE.md`. Ask Glen
  whether he wants pull requests for steps 13 to 15 (each PR's bitstream
  commits are dropped before merging; they are the commits whose message
  says so).
- **Step 15 misbehaves:** ask him to flash step 14b to tell the two
  apart. If 14b is fine, the predictor is the suspect: build a bisect
  file with `FPRED = 0` (tg68_bus parameter; `S15_DEFAULT` sets its
  default) from the same commit and seed search as usual; that leaves
  `cnt_ok`, the IPL sampling and the `fp_*` registers idle. Report what
  each file does before changing any logic.
- **Step 14b misbehaves but step 14 (seed 8, `step14_headroom`) is
  fine:** the difference is kernel change 5 and the capture change
  (12x rising sample, automatic swap). `speed 12 fall` forces the old
  sample; if that cures it, the capture change is the suspect.
