# Study: the caches and the Chip RAM write buffer (sizes, layout, where they matter)

Asked for on 19 November 2026 (backlog item). Measured in simulation on
step 17's RTL (`step17-icache-tag-drop`, commit 602ad96), 12x, macOS
toolchain (`plans/README.md`). No hardware: the baseboard is not here yet.
This is a study for the planner, not a step: nothing here is built.

## 1. What there is now

- **Instruction cache and data cache**, each 8 KB, direct-mapped, one
  16-bit word per entry with its own tag, two banks (even/odd word) so an
  aligned longword is one lookup. Write-through. `IC_AW` (tg68_bus.v)
  sizes both together: 12 = 4096 words = 8 KB.
- Tag (`TAGW` = 1 valid + 2 region + a[23:IC_AW+1]) = 14 bits at 8 KB.
  Because there is one tag per word, **the tags take as many block RAMs as
  the data**: each cache is 4 EBR data + 4 EBR tags.
- **Chip RAM write buffer** (top level, step 12): `CHIP_WB` = 8 entries of
  address, data, FC, strobes, in fabric registers (storage fixed at 8, the
  pointers 3 bits). The CPU goes on while it drains onto the 7 MHz bus.

Block RAM (v2.0, from the synthesized netlist, 35 of 56):

| user | EBR |
| --- | --- |
| instruction cache (data e/o, tags e/o) | 8 |
| data cache (data e/o, tags e/o) | 8 |
| SD boot ROM (`sd_subsystem.v`, 32 KB) | 15 |
| fast RAM board ROM (`turbomem_zii.v`, 8 KB, 227 words used) | 4 |

Branch `sdrom-trim` (built from `main`, waiting for a build and Glen's
test) cuts the SD ROM to 18 KB = 9 EBR: its image was 16,532 bytes of
content and 0xFF padding. That leaves 29 used, **27 free**. The turbomem
ROM could go from 4 EBR to 1 the same way (227 words in an 8 KB array):
not done, not asked.

## 2. Cache size: what the simulator can and cannot say

`IC_AW` swept 10 to 13 (2 to 16 KB, both caches), clocks of each bench's
timed pass:

| bench | 2 KB | 4 KB | 8 KB (now) | 16 KB |
| --- | --- | --- | --- | --- |
| c | 64992 | 64992 | 64992 | 64992 |
| coff (caches off) | 119976 | 119976 | 119976 | 119976 |
| copy | 9384 | 9384 | 9384 | **7836** (-16.5%) |
| read | 6204 | 6204 | 6204 | 6204 |
| scatter | 3756 | 3756 | 3756 | 3756 |
| chip | 31356 | 31356 | 31440 | 31668 |
| wrfast | 6732 | 6732 | 6732 | 6732 |
| op | **23940** | 21468 | 21468 | 21468 |

- Every bench's working set fits in 2 to 4 KB, so **size barely moves
  them**. The exception is `copy`: source and destination are 8 KB apart
  and evict each other in an 8 KB direct-mapped data cache (a conflict,
  not a capacity, miss); 16 KB separates them.
- The caches themselves are worth 1.85x on compiled C (`c` 64,992 vs
  `coff` 119,976).
- **Where size really matters cannot be measured with these benches.**
  Real programs' code and data are far bigger than 8 KB: Frontier's CODE
  hunk is 157 KB in Chip RAM, where every instruction-cache miss costs
  about 50 clocks at 12x and 80 at 20x against 4 for a hit
  (`strategy-after-v2.md` 1.2). That is where 16 KB (or more) of
  instruction cache would pay; a fast RAM miss costs far less (a direct
  SDRAM read, about 8 to 10 clocks).
- So the order of value is: **instruction cache for Chip RAM code** >>
  instruction cache for fast RAM code > data cache. Step 17 (a write no
  longer evicts unrelated code) already removes the worst waste.

Two ways to get real numbers, both before building step 20:

1. **Step 18's `perf` counters on the hardware** (already planned):
   hit/miss counts per region from real programs. Needs the baseboard.
2. **A trace-driven cache model** (can be done now, no hardware):
   `machine68k` (installed in the venv, a 68020 emulator with memory
   hooks) runs compiled C or Amiga CLI programs under `amitools`' vamos;
   log every fetch and data access; replay the log through a Python model
   of the caches with any size, layout, line length and associativity,
   costed with the sim's clocks per hit/miss. Gives the miss-rate curves
   in minutes. Limits: no Chip RAM DMA, no games (vamos is CLI only), so
   it ranks options rather than predicting SysInfo numbers.

## 3. Layout options (block RAM budget, at most 27 EBR free after the SD trim)

| layout | I-cache | D-cache | EBR for caches | total EBR | notes |
| --- | --- | --- | --- | --- | --- |
| now: tag per word | 8 KB | 8 KB | 16 | 29 | |
| tag per word, `IC_AW` = 13 | 16 KB | 16 KB | 32 | 45 | step 20 as planned; no new logic; tag 1 bit shorter |
| tag per word, I 16 KB, D 8 KB | 16 KB | 8 KB | 24 | 37 | needs separate `IC_AW` / `DC_AW` (small change) |
| **tag per 4-word line + 4 valid bits** (sector cache) | 16 KB | 16 KB | 20 | 33 | tag RAM 2048 x 17 bits = 2 EBR per cache |
| sector cache | 32 KB | 16 KB | 30 | 43 | the biggest instruction cache that fits |

- **Tag per word wastes half the cache's block RAM.** A sector layout (one
  tag per 4 words, a valid bit per word) keeps today's word-by-word fill
  and drop behaviour but needs a read-modify-write of the tag entry on
  every fill and drop (the other words' valid bits). The step 17 lookup
  already reads the tags at DECIDE for every write; fills would need the
  same. That is new logic on the cache write side, not in the hit path.
- **Associativity (2-way)** would cure conflicts like `copy`'s, but puts a
  second tag compare and a way select in the cache-hit -> `step()` path,
  the tightest 1T path in the design (step 17's 16 failing seeds all fail
  around it). Bigger direct-mapped is the cheaper cure. Not recommended
  before the trace model says conflicts matter.
- Longer fills (a burst of 4 words per miss, filling a line) would only
  pay with a sector layout and the SDRAM's burst reads; the SDRAM side is
  `sdram_ctrl.v`'s pair reads today.

## 4. The Chip RAM write buffer

`CHIP_WB` swept (`wrmix`: 4-longword MOVEM bursts with C2P-like arithmetic
between them; `wrmix8`: 8-longword bursts, same arithmetic; `wrchip`: 4-
longword bursts back to back). Depths above 8 used a widened buffer (32
storage entries, 5-bit pointers) in a scratch worktree only.

| depth | wrchip | wrmix | wrmix8 |
| --- | --- | --- | --- |
| 1 | 33084 | 51492 | |
| 2 | 31572 | 47652 | |
| 4 | 31572 | 39972 | 71460 |
| 8 (now) | 31572 | **31572** | **62292** |
| 16 | 31572 | 31572 | 62292 |
| 32 | 31572 | 31572 | 62292 |

- At depth 8 every one of these runs at the **7 MHz bus limit**: about 62
  clocks per word at 12x (`wrchip` 512 words in 31,572; `wrmix8` 1024
  words in 62,292). Nothing deeper can help a program that writes Chip
  RAM faster than the bus drains it.
- A deeper buffer helps only bursts longer than 8 words **followed by
  enough computation to drain them** (more than about 62 clocks per
  buffered word). Such programs exist (a C2P that writes a whole plane
  row, then computes the next), but the bus caps the gain at the bus
  time those bursts would otherwise wait.
- **Recommendation: keep 8.** If step 18's counters show Chip RAM write
  waits (`cw` in the sim) as a large share on real programs, a 16-entry
  buffer costs about 350 more registers (or one EBR as a FIFO) and no
  change to the protocol.

## 5. Suggested order (for the planner)

1. `sdrom-trim` (done, needs a build and Glen's SD test): frees 6 EBR.
2. Step 18 (`perf`) as planned, plus the trace-driven model (section 2),
   which can be done without hardware.
3. Then pick between: 16 KB both caches by `IC_AW` (simplest, 45 EBR), a
   separate 16 KB I / 8 KB D (37 EBR), or the sector layout (33 to 43
   EBR, more logic). The model's miss curves decide.
4. Leave the write buffer at 8 unless the counters say otherwise.
