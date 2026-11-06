# CLAUDE.md: TG68 (68020) build for the Base64 accelerator

Briefing for Claude Code. Read this first, then `README.md`, which is the
user-facing documentation and holds the details. This folder (`tg68/`) is a
self-contained alternative gateware for jbilander's Base64 Amiga 500
accelerator. It replaces the cycle-exact fx68k 68000 with TobiFlex's TG68K.C
in 68020 mode and keeps the fx68k build's fast RAM, SD card, autoconfig and
MapROM.

## Owner and hardware

- Glen: electrical engineer, Amiga hobbyist, works on **Windows**. He tests
  everything on real hardware and reports SysInfo/AIBB numbers. Nothing
  counts as done until he has run it.
- Target: Base64 Rev C carrier, iCESugar-Pro (Lattice **LFE5U-25F-6BG256C**),
  in an **A500+** (Kickstart 2.04, 3.1, 3.2 and DiagROM all usable).
- Bitstreams are loaded by copying the `.bit` file onto the iCELink USB drive.
  An incomplete copy can boot to lit LEDs but not run. If a bitstream that
  should work does nothing, flash it again first.

## Layout

```
rtl/base64_tg68/   top level (base64_tg68_top.sv) and the bus adapter tg68_bus.v
rtl/tg68/          TG68K.C VHDL (unmodified except tg68_020.vhd wrapper) and
                   tg68_020_b0.v, the GHDL-converted netlist actually built
                   (regenerate with scripts/gen_tg68.sh; needs ghdl+yosys plugin)
rtl/base64_fx68k/  copies of the fx68k build's slaves; every change is
                   marked "TG68:" (fastmem_zii: direct SDRAM port and BUS_RAM;
                   all slaves: *_int_win outputs)
scripts/           build.py (yosys -> nextpnr -> ecppack, seed search),
                   check_timing.py (the real timing sign-off), helpers
constraints/       pin constraints (nextpnr .lpf generated from the Diamond one)
diamond/           fallback Lattice Diamond project constraints (never used
                   on hardware; keep in step but treat as secondary)
sim/               Verilator test benches; see sim/README.md
sw/maprom/         maprom command (68000 asm) + hunk wrapper
bitstreams/        release outputs, NOT in git; they go on GitHub Releases
```

Upstream (jbilander's files outside `tg68/`) is not modified by this work.

## Commands

```
python3 scripts/build.py full --seeds 12      # or min / fastmem; Windows: build.bat full
sh sim/run.sh bus | top | fastmem              # the three regression benches
sh sim/run.sh bench copy|read|scatter|sd       # throughput and SD loopback
python3 scripts/check_timing.py build/full/base64_tg68.sdf --paths 4
sh sw/maprom/build.sh                           # needs binutils-m68k-linux-gnu
```

Toolchain: yowasp-yosys 0.70 and yowasp-nextpnr-ecp5 0.11 (pip), ecppack
from Ubuntu's fpga-trellis, Verilator 5.020, binutils-m68k-linux-gnu, or
oss-cad-suite on Windows (build.bat). `scripts/setup_cloud.sh` installs the
exact versions; with them, `build.py full --seed 3 --seeds 1` reproduces
the released step 4 `full` bitstream bit for bit. `build.py` uses
`yowasp-yosys` / `yowasp-nextpnr-ecp5` by itself when plain `yosys` /
`nextpnr-ecp5` are not on PATH, so no `YOSYS` / `NEXTPNR` variables are
needed (they still override). Synthesis uses `synth_ecp5 -abc9`,
keep_hierarchy on the TG68 modules then flatten, and deletes `$scopeinfo`
cells. nextpnr runs with `--placer static --router router2`.

**ecppack must stay plain by default.** `--spimode dual-spi --freq 62` made
bitstreams that never loaded on this module. `--compress --freq 38.8` works;
that gives the "_fast" files.

## Rules for every change

1. **All three sims pass** (`bus`, `top`, `fastmem`), plus `bench sd` if the
   bus or the slaves were touched. Add a test for any new behaviour; the
   benches check results at fixed addresses (`check(...)` in tb_top.sv).
2. **check_timing.py says PASS.** nextpnr's own FAIL is expected and
   meaningless: it times every path as 1 clock at 86 MHz, but the kernel is
   multicycle. The checker classifies start/end registers and gives each
   pair its real budget (table in README "Timing"). **When you add a
   register, decide its class.** A register named after a port it drives, or
   one changed rarely (config), can be misclassified. Fix the classifier with
   a reason in a comment rather than accepting a fake pass. The checker has
   caught real bugs this way.
3. **Fix structure, don't seed-hunt.** If a path fails by more than about 0.5 ns
   on several seeds, restructure it. Patterns that worked:
   - Register a decode one clock early when its inputs are known to be
     stable (int_win_r, ic_on_r).
   - Load data registers unconditionally and put the conditions only on the
     write enable or the valid bit (cache write ports, k_din at CCMP/LATCH).
   - Move work one clock later from latched registers (pw_upd).
4. **Keep the previous known-good step.** Each step ships in its own
   bitstreams/stepN folder with timing reports. Glen falls back to the last
   step he has confirmed if a new one misbehaves.
5. Changes to rtl/base64_fx68k files are marked `TG68:` with the reason.
6. Update README.md (status, table, feature text, timing table) along with
   the code.

## Working in Claude Code

- **Tools:** if `verilator` or `yowasp-yosys` is missing, run
  `sudo bash tg68/scripts/setup_cloud.sh` (or `bash` as root) before
  anything else.
- **One change per branch and pull request.** Name branches after the
  change, for example `step5-two-word-cache`. Each PR says what changed, the
  sim results, the timing-check result (worst slack per class that moved),
  and what Glen should test on the Amiga.
- **Getting test bitstreams to Glen:** he flashes them from GitHub. Commit
  them to the PR branch under `tg68/bitstreams/stepN_name/` with
  `git add -f` (the folder is gitignored), together with timing.txt. Use
  both `_plain` and `_fast` (`ecppack --compress --freq 38.8`) and
  `full` + `min`. Glen downloads them from the branch on GitHub. PRs are
  squash-merged, and the bitstream commit is dropped before merging, so no
  binaries land in `main`. Released bitstreams go on GitHub Releases, which
  Glen creates by hand.
- **Commit author:** Glen Milford <casualretrogamer@outlook.com>, and end
  commit messages with the Co-Authored-By line for Claude.
- **No force-pushes to `main`**, and no rewriting history that is already
  on GitHub, unless Glen asks for it.
- Glen tests on hardware and reports back. Don't mark anything done, or
  update the results table, until he has.

## How the design works (short version; details are in README and comments)

- **Clocks:** one 85-86 MHz clock for everything. The TG68 kernel is
  clock-enabled. `tg68_bus.v` paces it: STEP=4 (kernel step period),
  SETTLE=3 (clocks before the adapter acts on kernel outputs), DIN=1,
  ADDR_SETUP=1, DATA_DELAY=2. The kernel->kernel path needs about 41 ns of
  the 46.5 ns allowed by STEP=4, so STEP=3 is out of reach.
- **Sequencer states (tg68_bus.v):** SETTLE -> DECIDE, then:
  - an internal step;
  - a prefetch-buffer hit -> FINISH;
  - a cache lookup CLOOK -> CCMP (hit -> FINISH, miss -> DWAIT, CFREE or
    SETUP);
  - a posted write -> FINISH;
  - a direct read -> DWAIT -> DDATA;
  - an old-route Amiga-bus cycle SETUP -> WAIT -> LATCH -> FINISH.
- **Old route:** the 68000-style AS/DS/DTACK bus to the motherboard and the
  on-FPGA slaves (autoconfig, SD, ROM board). The strobes are registered
  copies (as_i -> ASn).
- **Direct path (step 3):** fast RAM (the Zorro II window and $08000000) and
  MapROM go straight to the SDRAM controller through the dp_* port.
  - fastmem_zii is built with BUS_RAM=0, so its AS-driven RAM slave is gone.
  - The SDRAM word address `saddr_r` is formed from the kernel's early
    address and frozen by `dp_hold` while a request is in flight.
  - Writes are posted.
  - Each read prefetches the next word (pf_*, never across a 1 KB boundary).
- **Caches (steps 2 and 4):** two 8 KB direct-mapped caches, one 16-bit word
  per entry, in block RAM.
  - Cacheable: fast RAM and Kickstart $F80000-$FFFFFF. Never Chip RAM.
  - Both share one lookup pipeline (ic_qd/ic_qt).
  - Write-through. The data cache allocates on whole-word writes to fast RAM
    and drops the entry otherwise. The instruction cache drops the entry on
    any write.
  - The CPU is the only writer of fast RAM (the SD controller is CPU-driven,
    no DMA), so no software cache management is needed.
  - Both flush on reset and when MapROM changes state.
- **Cache enable:** both caches follow CACR EI. The data cache must NOT get
  the 68030 CACR bit 8: software tells an 020 from an 030 by setting that bit
  and reading it back, so storing it would make the CPU detect as a 68030 and
  invite MMU code. SysInfo's DCache switch therefore does nothing; that is
  intended.
- **Speculative read and overlap (step 4):**
  - A fast-RAM data read is sent to the SDRAM at DECIDE alongside the
    lookup. On a hit it becomes dp_kind 2 and its data is dropped. This
    relies on the SDRAM never answering in under 3 clocks; the `fastmem`
    bench checks that.
  - Cache lookups may start while a posted write or prefetch is still in
    flight. A miss then waits in CFREE.
- **Bridge:** the "is this cycle internal?" decision uses int_win_r, which
  is the slaves' address windows without the AS term, registered.

## Gotchas already paid for

- **yosys turns a constant `1'bz` on an inout into a constant-0 driver.** The
  SD card's MISO was driven low in every build up to the step 4 rebuild.
  Inputs on inout pins are now ECP5 `BB` buffers with T=1 under `ifdef
  YOSYS`: the SD card's DAT0-2, and `sdram_dq` when there is no fast RAM
  (the `min` build). build.py refuses a netlist with inout bits tied to
  constants. The one allowed exception is `sd_cmd[0]=0` and `sd_d[3]=1` in
  a config without the SD block (real outputs, idle on purpose). A new
  inout that is constant in some config needs a `BB` or an entry in
  `tied_ok` in build.py, with a reason. Verilator honours `1'bz`, so sims
  cannot catch this.
- `syn_useioff` can't go on registers that are also read internally
  (rt_as_n, rt_vma_n): packing fails.
- `pkill -f build.py` from a shell whose command line contains "build.py"
  kills that shell. Kill by PID.
- The original `maprom.c` was never compile-tested. `sw/maprom/maprom.s` is
  an assembly port tested only under amitools' `vamos` with a fake board.
  The board's boot ROM (turbomem.mem, DIAG_MAPROM=1) already enables MapROM
  at every boot.
- Verilator `$display(cond ? "A" : "B")` prints a number. Use if/else.

## Licensing (unresolved; check before publishing anything new)

- TG68K.C: LGPL-3.0 (Tobias Gubener).
- SD controller files (sdcard.v and related): GPL-2.0-only (Niklas Ekström).
- base64_gateware has no top-level licence; ask jbilander.
- Base64 hardware repo: CC BY-SA 4.0.
- GPL-2.0-only together with LGPL-3.0 in one bitstream may be incompatible.
- No licence has been chosen for Glen's own additions yet.

## Results so far (A500+, Kickstart 3.x)

| Build | SysInfo Dhrystones (caches on / off) | AIBB MemTest MB/s (on / off) |
| --- | --- | --- |
| v3 pacing | 2783 | - |
| step 2 (I-cache) | 4833 / 3208 | 4.38 / 3.91 |
| step 3 (direct path) | - | 6.46 / 5.71 |
| step 4 (D-cache) | 6076 / 4007 | 7.28 / 5.71 |

- SD card (sfsd.device 2.4) on step 4: 2.18 MB/s in SysInfo; fx68k gets
  1.76 MB/s.
- SysInfo reports "66 MHz" by timing loops. AIBB: close to a 25 MHz 68030.

## Ideas not yet done (Glen decides the order)

- Two words per cache entry, so sequential hits cost 5 clocks instead of 7
  (est. 10-20%).
- A 2-4 entry write queue (copies are write-bound).
- Bigger caches: 16 more block RAMs, which would crowd out RTG.
- RTG framebuffer in SDRAM: discussed as a future add-on, no design yet.
- A 32-bit TG68 bus: large change inside the kernel; parked.
