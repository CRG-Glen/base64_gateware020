# Step 23: burst cache fills (line fills on a fast RAM miss)

Status: **measuring** (27 November 2026). Branch `step23-burst`, from
`exp-22x`. Glen's choice after the 22x experiment.

## Idea

Today a fast RAM miss brings one word or one aligned pair (32 bits) from
the SDRAM, and after a single-word read a one-word prefetch. A line fill
would bring the whole aligned line of 4 or 8 words (an SDRAM burst; the
two cache banks take two words a clock) while the CPU carries on with the
word it asked for.

## Measured (tb model: `VLFLAGS="-DBURST_MEASURE -DBURST_L=4|8"`)

A shadow of each cache's tags follows every real cache write and, on each
real fast RAM miss, takes the rest of the aligned line. In the timed pass
it counts real misses the shadow held ("would hit") and real hits the
extra fills had evicted ("would lose"). The SDRAM time of longer fills is
not modelled.

| bench | real misses | 4 words: would hit / lose | 8 words: would hit / lose |
| --- | --- | --- | --- |
| c (compiled C, 63,900 clocks) | 17 fetch + 52 data | 15 / 0 | 15 / 0 (~0.1%) |
| copy (9,372) | 256 data | 132 / 0 (5.6%) | 194 / 0 (8.2%) |
| read, scatter | 0 (their 1 KB stays cached) | - | - |
| op | 7 fetch | 2 / 0 | 3 / 0 |
| **bigread** (new: 16 KB sum, misses every pass; 120,288) | 4096 data | 2048 / 0 | 3072 / 0 |

bigread costs 29.4 clocks a longword against 24.2 for the same loop from
the cache (`read`), so a miss turned into a hit saves ~5.2 clocks:
4 words **~-9%**, 8 words **~-13%** on a sequential read through more than
the cache. No hit was lost in any bench. Compiled C gains nothing (it
runs from the caches).

What the simulator cannot say: how sequential real programs' misses are
(Frontier's CPU timedemo: 54M fetch and 42M data misses, ~5% of its
time, step 18).

## Next

1. Measure on hardware: a `perf` build with counters for misses that fall
   in the same 4- and 8-word line as the previous miss of the same kind
   (fetch / data); Glen runs the Frontier CPU timedemo, AIBB, xSysInfo
   and a game.
2. Then decide line length and write the design: the SDRAM controller's
   burst, filling both banks while the CPU runs on, a write to the line
   during its fill, a read of a word of the line not yet filled, the
   prefetch buffer (which a line fill would replace).
