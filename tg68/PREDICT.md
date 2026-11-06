# Next-address prediction (TG68_PREDICT)

An experimental speed-up of the cache hit path in `rtl/base64_tg68/tg68_bus.v`,
behind a define. It is off unless you build with
`python3 scripts/build.py full --predict`.

## Why

A cache hit costs 7 clocks: SETTLE x3, DECIDE, CLOOK, CCMP, FINISH. The cache
RAMs sit idle during SETTLE while the kernel's address settles. Counting
every cache lookup in simulation, with each benchmark marked:

- close to every kernel step waits on an instruction fetch;
- over 90% of cache hits, fetches and data alike, are to the previous
  access of the same kind plus one word.

Removing CLOOK+CCMP from those hits saves 15-25% of all clocks. For
comparison, two words per entry (the "Ideas" list) would save 7-13%, because
only every second sequential word benefits.

## How

1. Each access remembers the next word for its kind: `pr_f` for
   instruction fetches, `pr_d` for data reads.
2. During SETTLE the cache RAMs read at those addresses (`pr_rs` steers the
   read port, so the select is one register, not a decode of `q`). Data and
   tag are registered at SETTLE-2 and the tag compared at SETTLE-1
   (`pr_fh`, `pr_dh`).
3. At DECIDE, if the kernel's address equals the prediction and the
   speculative lookup hit, the access goes straight to FINISH, exactly like
   a prefetch-buffer hit. A hit costs 5 clocks. Otherwise the normal lookup
   runs, at no extra cost.
4. Any write to a predicted word cancels that prediction (`pr_fk`,
   `pr_dk`), so self-modifying code stays exact. With the current pacing a
   write's cache update always lands before the next speculative read, so
   this is a safety net. The tests below never trigger it.

It is a define, not a parameter, because even dead code shifts yosys's
internal names and with them nextpnr's placement. Without the define the
file is the original text. Checked: with the pinned tools,
`build.py full --seed 3 --seeds 1` is still identical to
`step4_dcache/base64_tg68_full_plain.bit`.

## Timing

`check_timing.py` changes, each with its reason in a comment:
- `pr_f/pr_d/pr_fk/pr_dk` are classed like `pf_a` (bus outputs): written
  only at DECIDE, next used >= 2 clocks later.
- `g_fastmem.u_fastmem.fm_cfg_match` is fastmem_zii's `addr_match`, named
  after its port, which is commented "(static)". It is now in the static
  class.
- `pwrup_done` is in the static class too: it rises once, while cold_armed
  still holds ext_reset.
- `--strip PREFIX` is new and only for a design that wraps the top one
  level deeper (the default is unchanged).

Step 4 still passes, unchanged. `full --predict`: seed 29 passes, worst slack
+0.43 ns (step 4: +0.45 ns). Seeds 1-28 missed by 0.02-3 ns, never on a
prediction path: the misses were the SDRAM controller's open_row ->
sdram_a, the bridge's ph -> cpu_a, and the kernel clkena fan-out. The
multicycle table for seed 29 is in
`bitstreams/step5_predict/timing_full_predict.txt`.

## Results

### Simulation, `sim/run.sh` with `VLFLAGS=-DTG68_PREDICT`

- bus, top, fastmem and bench sd: PASS, with and without prediction.
- tb_top's data-cache hit counter now also counts predicted hits: 144 hits
  either way.

| bench | off | on |
| --- | --- | --- |
| copy | 4.85 MB/s | 5.16 MB/s |
| read | 8.03 MB/s | 9.91 MB/s |
| scatter | 11.66 MB/s | 13.86 MB/s |

### Hardware: iCESugar-Pro on its own, no Amiga

This was measured with a test harness that runs the whole
`base64_tg68_top` on a bare iCESugar-Pro: a motherboard model in the FPGA,
a serial program loader, and C tests. It is on the `devboard-tg68-harness`
branch of stefanskotte/base64_gateware020 and changes nothing in the real
build. It uses 12x, caches on, and the module's own SDRAM. 38/38 checks
pass, including two added for this change: code patching an instruction
just ahead of the PC, and a data loop that writes the next word and reads
it back. Patching at distances 0-4 words gives the same result with and
without prediction. At distance 0 the old instruction runs, because of the
kernel's own prefetch, as on a real 68020.

| benchmark | before | predict | gain |
| --- | --- | --- | --- |
| CRC32 bitwise, 4 KB | 39908 us | 29873 us | 1.34x |
| 3 KB straight-line code | 9777 us | 7504 us | 1.30x |
| sum 4 KB table | 22957 us | 17602 us | 1.30x |
| sieve to 8192 | 33634 us | 26523 us | 1.27x |
| memtest 15 MB random | 12233 ms | 9607 ms | 1.27x |
| fast RAM write 64 KB | 12263 us | 9817 us | 1.25x |
| CRC32 table-driven | 32521 us | 26395 us | 1.23x |
| fast RAM read / copy 64 KB | | | 1.18x / 1.18x |
| Chip RAM read (model Gary) | 2011 us | 1868 us | 1.08x |

With the caches off nothing changes, as expected.
