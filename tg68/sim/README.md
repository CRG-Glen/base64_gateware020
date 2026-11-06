# Test benches

`run.sh bus | top | fastmem` (Linux: verilator 5, binutils-m68k-linux-gnu).

* **bus**: `tg68_bus` + TG68K on a model asynchronous 68000 bus with random
  DTACK latency (2-25 clocks). `test020.s` checks MULU.L, DIVU.L, BFEXTU,
  EXTB.L, byte lanes, a misaligned MOVE.L, TRAP/RTE, MOVEC VBR, an
  autovectored interrupt and a BR/BG/BGACK hand-over mid-run, plus protocol
  checks (address stable through AS).
* **top**: the whole `base64_tg68_top` (bridge, 7M grid, cold reset, hi_null)
  on a crude motherboard: Gary-style DTACK, VPA for CIA space and IACK, ROM,
  Chip RAM. `test_top.s` adds a CIA read through the VPA/E cycle and a read
  of `$FF000000` that must come back `$FFFF` without reaching the
  motherboard.
* **fastmem**: as top with `ENABLE_FASTMEM=1` and the fx68k build's
  timing-checked SDRAM model. Writes and reads `$08000000` and `$08FFFFFC`,
  runs code copied into fast RAM, and checks the direct path's prefetch
  buffer, MapROM, and the data cache: hits, word and byte writes, two
  addresses on one cache slot, writes made with the caches off, ROM data,
  and a two-pass sum. It also checks the SDRAM never answers a direct
  request in under 3 clocks, which the speculative read relies on.
* **bench copy | read | scatter | sd**: fast RAM throughput, timed on a second
  pass with the loop running from the instruction cache. `copy` copies
  1 KB, `read` sums 1 KB sequentially, `scatter` reads four longs in
  different SDRAM rows round and round.
* **bench sd**: the SD controller with MOSI looped back to MISO: register
  read-back, 16 bytes shifted out and back in, and a single byte. (The
  simulator honours `1'bz`, so the pin bug fixed in step 4b could not show
  here; `build.py` now checks the netlist for it instead.)

Each ends with `PASS` or a list of what failed.
