# Tooling: build.py keeps every seed and runs seeds in parallel

Status: **done** (branch `tooling-build-seeds`). Ready to build: was. Branch: `tooling-build-seeds`, from
`step15-fetch-predictor`. No RTL change, no hardware risk.

## Goal

Today `scripts/build.py full --seeds N` runs nextpnr one seed at a time in
one folder, stops at the first seed that passes, and overwrites each
seed's files with the next. To compare seeds (every step needs it) the
planner ran nextpnr by hand into one folder per seed. Make build.py do
that itself.

## Background (read `scripts/build.py`, 167 lines, first)

- Synthesis writes `build/<name>/base64_tg68.json` once; `--skip-synth`
  reuses it. `<name>` is `full`, `min`, or with `--x16` `full_x16`.
- Each seed: nextpnr (`--placer static --router router2 --seed S`, lpf,
  `--timing-allow-fail`) writes `.config` and `.sdf`; then
  `check_timing.py` on the sdf (exit status 0 = PASS) writes `timing.txt`.
- One nextpnr run takes 10-15 minutes and one core; the cloud machine has
  4 cores and 15 GB. YoWASP tools cannot read files under /tmp.
- nextpnr's result depends only on the json and the seed (the target
  frequency was shown to change nothing).

## The change

1. New option `--jobs J` (default: the smaller of 4 and the CPU count).
   Seeds `--seed S .. S+N-1` run J at a time as separate processes.
2. Each seed writes into `build/<name>/seed<S>/`: `base64_tg68.config`,
   `base64_tg68.sdf`, `nextpnr.log`, `report.json`, `timing.txt` (from
   `check_timing.py ... --paths 6`). The json stays in `build/<name>/`
   and is passed by path. Do not stop at the first pass: run them all.
   (New option `--first-pass` keeps the old behaviour: stop starting new
   seeds once one has passed.)
3. When all are done, print one table, sorted by seed: seed, PASS/FAIL,
   worst 1T slack, worst multicycle slack, and for failures the worst
   class with its slack. Write the same table to
   `build/<name>/seeds.txt`. Parse the class rows of `timing.txt`: the
   budget column is the field matching `[1234]T`, the slack is two fields
   after it (lines of failing classes end in `<-- n FAIL`, so do not
   count fields from the end).
4. Pick the best seed: among the PASS seeds, the one with the largest
   worst-1T slack. For it, also run `check_timing.py` with
   `--freq 99.32` and `--freq 113.51` into `timing_at14x.txt` and
   `timing_at16x.txt` in its seed folder, and print the worst
   delay/budget ratio for each: for every class row,
   `(n*T - slack) / (n*T)` with `T = 1000/freq` ns; the ratio is the
   maximum. Then run ecppack twice on its config into `build/<name>/`:
   plain `base64_tg68_<name>.bit` (as now) and
   `base64_tg68_<name>_fast.bit` (`--compress --freq 38.8`). Keep
   honouring `ECPPACK_OPTS` for the plain file.
5. If no seed passes: print the table, exit status 2, pack nothing (as
   now, where the last seed's bitstream was still packed: do not pack a
   failing 12x build any more). `--x16` keeps its special case (it can
   never pass): leave that code path working as it is, single job is
   fine.
6. Free disk as you go: an `.sdf` is 23 MB. After a seed's timing files
   are written, delete its sdf unless it is the best seed or
   `--keep-sdf` was given.
7. `build.bat` (Windows, oss-cad-suite) calls build.py: check it still
   passes its arguments through and document `--jobs` in its header
   comment and in README "Building it yourself". subprocess-based
   parallelism works on Windows; do not use `os.fork`.

## Checks (acceptance criteria)

- `python3 scripts/build.py full --seed 8 --seeds 1` on
  `step15-fetch-predictor`'s RTL gives a plain bitstream **byte-identical**
  to `bitstreams/step15_fpred/base64_tg68_full_plain.bit`, and a `_fast`
  one identical to the `_fast` file there (`cmp`).
- `python3 scripts/build.py full --skip-synth --seed 5 --seeds 4 --jobs 4`
  finishes, leaves `seed5..seed8` folders, prints the table with seed 8
  PASS (+0.60 / +0.40 ns) and seeds 5-7 FAIL with the slacks in
  `step15b-predictor-timing.md`'s baseline table, and reports ratios
  1.142 (14x) and 1.305 (16x) for seed 8.
- The inout-tied-to-constant check and `--skip-synth` still work.
- README "Building it yourself" and `CLAUDE.md`'s Commands block and the
  "build.py keeps only the last seed" gotcha are updated (delete the
  gotcha).

## Stop and report if

- the seed 8 bitstream is not byte-identical (something in the flow is
  not deterministic, or the options changed);
- parallel runs give different results from serial ones for the same seed.

## Log

- build.py: `--jobs` (default min(4, CPUs)), `--first-pass`, `--keep-sdf`;
  each seed in `build/<cfg>/seed<N>/` (config, nextpnr.log, nextpnr.out =
  nextpnr's stdout, report.json, timing.txt with `--paths 6`); threads
  running subprocesses (no fork, so Windows works); table printed and
  written to `seeds.txt`; best = PASS seed with the largest worst-1T
  slack, scored at 14x/16x into `timing_at14x.txt` / `timing_at16x.txt`
  in its seed folder, packed plain (honours ECPPACK_OPTS) and `_fast`
  into `build/<cfg>/`; no pass = nothing packed, exit 2. The `--x16` path
  keeps the old serial loop in `build/<cfg>_x16/` (refactored to share the
  nextpnr command; not re-run: frozen and no longer shipped).
- Checks, all passed:
  - `--skip-synth --seed 5 --seeds 4 --jobs 4` on the 3c13c05 netlist:
    seeds 5/6/7 FAIL (-0.45/-1.73, -1.37/-0.18, -0.62/+1.06), seed 8 PASS
    (+0.60/+0.40), ratios 1.142 / 1.305: the same as the serial runs in
    `step15b-predictor-timing.md`'s baseline, so parallel = serial.
    Plain and `_fast` byte-identical to `bitstreams/step15_fpred/`.
  - Full synthesis + seed 8, at 3c13c05 and at the branch head (b384161,
    a comment edit in tg68_bus.v): both byte-identical to
    `step15_fpred` (so line numbers in comments do not change the
    result).
  - `--first-pass --jobs 1 --seed 7 --seeds 3`: seeds 7 and 8 run, 9 not
    started; seed 8 packed.
  - `--seed 5 --seeds 1` (no pass): exit 2, no .bit written.
  - Only the best seed keeps its .sdf (failed seeds' folders ~6 MB).
- Docs: README "Building it yourself", build.bat's header, CLAUDE.md's
  Commands; the "build.py keeps only the last seed" gotcha removed.
- Note: a seed folder from an earlier run stays until that seed is run
  again; `seeds.txt` lists only the run that wrote it.
