# Step 25: a deeper Chip RAM write buffer (measure first)

Status: **measuring** (28 November 2026). Branch `step25-chip-wbuf`, from
`main` (v2.1). Item 3 of the long plan, first of the smaller items.
Planned and built by the same model.

## Why

Step 23's counters (Glen, Frontier CPU timedemo, 20x): the CPU spends
**5.5% of its clocks waiting because the Chip RAM write buffer is full**
(counter 16: 891M of 16.35G clocks), with 15.1M Chip RAM writes. A write
takes about 4 7 MHz cycles on the Amiga's bus (~80 clocks at 20x), so the
bus was busy writing for ~1.2G clocks and the CPU waited through ~74% of
that. EON: 1.1%. Other workloads: under 0.5%.

A deeper buffer only helps if the writes come in bursts longer than 8
with CPU work between them: then the CPU runs on while the bus drains. If
the writes are one long stream (a screen clear), the bus is the limit and
depth changes nothing. The counters cannot tell these apart, so the test
build lets Glen change the depth at run time and measure.

## Background (base64_tg68_top.sv, "CHIP RAM WRITE BUFFER")

- `wb_a`, `wb_d`, `wb_fc`, `wb_ds` [0:7], pointers `wb_wp` / `wb_rp`
  (3 bits), `wb_cnt` (4 bits), `wb_full = (wb_cnt == WB_N)`, `CHIP_WB` = 8.
- `wb_acc` (a postable write with its strobes down, not full) acks the
  CPU and enqueues; the drain engine (`rp_act`, `rp_ds`, `rp_term`,
  `rp_hold`) runs the head entry on the motherboard with 68000 timing and
  pops it (`wb_pop`).
- Every other motherboard cycle waits for `!wb_busy`: ordering is kept
  whatever the depth. A deeper buffer makes that wait longer when it is
  full: 32 entries is ~18 us at the bus's ~0.56 us a write (8: ~4.5 us),
  so an interrupt acknowledge or a custom chip register access after a
  long burst waits up to 18 us. Still in program order.
- `perf_cw` (counter 16): a postable write that finds the buffer full.

## The change (test builds only, `TG68_PERF`)

1. Storage `WB_S` = 32 with `TG68_PERF`, 8 without; pointers and count
   sized from it. The normal build's logic is unchanged.
2. `wb_lim` (6 bits): with `TG68_PERF` a register, power-on
   `` `WB_LIM_DEFAULT `` (8), set by a keyed write `$5D0n` to +$F00E
   (n = 0: 8, 1: 16, 2: 32; others ignored), taken only while the buffer
   is empty (`!wb_busy`), so the limit never drops under the count;
   without, the constant `CHIP_WB`. `wb_full = (wb_cnt == wb_lim)`.
3. +$F00E's status bits 7:6 (zero today): the depth code in force.
4. Counters 20 and 21 (N = 22): clocks with more than 8 and more than 16
   entries in the buffer.
5. `perf` 1.2: `perf WB 8|16|32`, the depth in the report, names for 20
   and 21.

## Tests

- Regression (bus, top, fastmem; top and fastmem with PERF=0; bench sd):
  every number unchanged at the default depth 8.
- Benches `wrchip`, `wrmix`, `chip` at depth 8, 16 and 32
  (`VLFLAGS=-DWB_LIM_DEFAULT=32`): Chip RAM content checks pass (the tb
  compares Chip RAM with the CPU's writes), clocks reported.
- test_top.s: `$5D02` then a burst of 20 Chip RAM writes and a read-back
  (order kept); a `$5D` write while the buffer is busy is ignored.
- tb: counters 20, 21 against its own count of `wb_cnt`; stat values
  `$1600` / `$5600` / `$9600` / `$1601` (N = 22), with the depth bits.
- Mutant: limit taken while busy (`!wb_busy` dropped) with 32 -> 8 in a
  burst: the tb must catch the count above the limit.

## For Glen (the measurement)

At 20x or 22x, the Frontier CPU timedemo with `perf WB 8`, then `perf WB
16`, then `perf WB 32` (each: `perf CLEAR`, the demo, `perf >RAM:p.txt`,
and the fps). Also a game and the Frontier Amiga timedemo at 8 and 32.

## Decision after it

If 32 gains clearly on Frontier (more than ~1-2%) and nothing breaks: a
normal build with 32 (or 16), with the longer worst-case wait noted. If
not: close the step; the waits are the bus's own speed.

## Log

(the builder writes here)
- RTL and tests (commit on this branch): regression PASS (bus, top,
  fastmem, top and fastmem PERF=0, bench sd); every bench unchanged at
  depth 8. test_top.s: two 20-write bursts at depth 32 read back (the
  buffer reached 11 entries at 12x: the loop outruns the drain by that
  much), back to 8, bad codes ignored. **The "taken once empty" mutant
  cannot fail:** the CPU's write to +$F00E is itself an ordered cycle,
  held until the buffer is empty (tb: every $5D write arrives with 0
  entries), so the guard is a safety net the CPU cannot reach; the tb
  checks every clock that the count never exceeds the limit.
- Benches at depth 8 / 16 / 32 (clocks; chip write waits): wrchip 31,572
  all three; 22,132 / 21,586 / 20,484. wrmix 31,572; 10,288 / 9,716 /
  8,582 (-17%). chip 31,440; 21,238 / 20,681 / 19,564. c, copy unchanged.
  The benches are bound by the Amiga's bus (their time ends with the last
  write drained), so the waits saved come back at the end; Frontier's bus
  is busy ~7% of the time, so only hardware can say.
- **Perf build, seeds 1-32: 0 pass at 22x.** Longest SDRAM pin path
  4.86-6.22 ns (v2.1's netlist: 4.04-5.89): the counters and the 32-deep
  buffer push the readers away from the pins; 4 seeds also miss 1T by
  0.04-0.47 ns. As a 20x-only measurement build (`build.py --pin-setup
  5.01`, new: the longest path that has run at 20x, step 23's seed 7):
  seeds 2 (4.86) and 28 (4.93) pass; shipped **seed 28**, +0.98 ns, 1.21x
  / 1.51x at 16x / 20x, `bitstreams/step25_wbuf_perf/`. A release with a
  deeper buffer would need the pin paths shortened first (step 24's
  structural fallback: no LUT between pin and register).
