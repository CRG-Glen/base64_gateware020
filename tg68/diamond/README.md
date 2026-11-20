# Building with Lattice Diamond (Windows or Linux)

Use this if the open-source flow can't route the design. Diamond's free
licence covers the LFE5U-25F. Synplify reads the TG68K.C VHDL directly (no
GHDL step), packs it more tightly than yosys, and, unlike nextpnr, is told
about the multicycle paths, so its timing report is the real one.

## Project

File > New > Project, as in `fx68k/BUILD.md`:

* Device **LFE5U-25F-6BG256C**, synthesis **Synplify Pro** (not LSE)
* Top-level unit: **`base64_tg68_top`**

Sources, all from this kit:

```
rtl/base64_tg68/base64_tg68_top.sv     (System Verilog)
rtl/base64_tg68/tg68_bus.v
rtl/tg68/TG68K_Pack.vhd
rtl/tg68/TG68K_ALU.vhd
rtl/tg68/TG68KdotC_Kernel.vhd
rtl/tg68/tg68_020.vhd
rtl/base64_fx68k/autoconfig_zii.v   fastmem_zii.v   turbomem_zii.v
rtl/base64_fx68k/sd_subsystem.v     sdcard.v        sdram_ctrl.v
rtl/base64_fx68k/fifo.v  shifter.v  rx_cpu_buf.v    tx_cpu_buf.v
diamond/base64_tg68.fdc                (Synplify constraints)
diamond/base64_tg68_diamond.lpf        (pinout + TRACE multicycle)
```

Do **not** add `rtl/tg68/tg68_020_b0.v`. That's the GHDL-converted copy
for the open-source flow, and Diamond uses the VHDL instead.

`turbomem.mem` and `sfsd.mem` (in `rtl/base64_fx68k/`) must be **project
members** and present in `impl1/`, exactly as `fx68k/BUILD.md` explains.
Diamond's Clean deletes them.

## Which configuration

Set the two parameters at the top of `base64_tg68_top.sv`:

| Build | `ENABLE_FASTMEM` | `ENABLE_SD` |
| --- | --- | --- |
| min (first test) | `1'b0` | `1'b0` |
| fastmem | `1'b1` | `1'b0` |
| full | `1'b1` | `1'b1` |

## Strategy

Start from the fx68k build's settings (Path-based Placement **off**,
placement effort 5, and so on, from `fx68k/BUILD.md`).

## Checks after the build

Everything in `fx68k/BUILD.md`'s "Check the build log" list applies:
111/111 pins locked, `CONFIG_MODE SPI_DUAL`, no CG371/CS101/BN105, and the
block RAM count (0 for min, 4 for fastmem, about 20 for full; the open flow gets 19 because the top half of the SD boot ROM is all $FF). Then the `.twr`:

* **Hold errors 0, setup errors 0.** With the multicycle preferences in
  place, any remaining setup failure is a real single-cycle path.
* If the `.twr` shows thousands of failures inside `cpu/core/...`, the
  MULTICYCLE block at the end of `base64_tg68_diamond.lpf` wasn't applied.
  Check that the LPF in the project is this one, not the fx68k one.

The constraint values assume the default adapter pacing (`TG_STEP=4`,
`TG_SETTLE=3`, `TG_DIN=1`, `TG_ASU=1`). If you lower those, lower the numbers in both
constraint files to match.
