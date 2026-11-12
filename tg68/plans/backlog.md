# Backlog: ideas that need a plan before anyone builds them

Glen chooses the order. Each item says what is known and what the plan
must still work out. The older ideas list (RTG, USB, WiFi, bigger caches,
slow RAM code cache and why each was or was not pursued) is in
`docs/HISTORY.md`, "Ideas not yet done".

## Speed

Where the clocks go now (bench c, step 15, timed pass, 65,640 clocks,
14,965 kernel steps): instruction fetches 9,247 (8,156 predicted in 4
clocks, 986 unpredicted single in 5, 75 pairs), data reads 2,009 (1,534
single cache hits in 5 clocks, 411 pairs), writes 1,513 (1,035 single in
5, 420 pairs), internal steps 2,196 (4 clocks). The floor is 4 clocks a
step (the kernel's own paths need about 40 of the 46.5 ns).

1. **Data-cache hits in 4 clocks.** The largest thing left: 1,534 steps,
   about 2.3% of the clocks. There is no address to predict, so it needs
   a different idea (for example a second look at whether the tag compare
   can move into DECIDE for the data cache only). Unplanned; may not be
   possible. The cache RAM's clock-to-output plus one multiplexer is
   already 10 ns, so nothing can be computed from a RAM output in the
   same clock.
2. **Word and byte writes in 4 clocks (`WR4`).** Built and tested in step
   15, switched off: it puts the fast RAM address decode (`k_fast`) into
   the kernel-step decision. Worth 1.1% on bench c. A plan would need a
   way to decide "this is a postable non-pair write" from registers.
3. **Prefetch-buffer hits in 4 clocks.** Matters with the caches off
   (bench coff: 2,115 such fetches, 1.7% of the clocks) and for code not
   yet cached. Mechanism: as the predictor, the buffered word selected in
   advance (`k_din_psel`-style) so the step can happen at DECIDE. Low
   value.
4. **One clock off every SDRAM request** (`dp_req` is `dp_req_i` one
   clock later, for placement). About 10% on uncached fast RAM reads.
   Risky: step 14's `pre_open/pre_hit/pre_ras` in `sdram_ctrl.v` rely on
   the address being stable a clock before the request. Needs a careful
   plan and probably a different way to give the placer what the extra
   register gives it now.
5. **18x clock (experimental, never a release; Glen asked for it after
   step 14).** Facts collected: one PLL cannot make 16x and 18x (one VCO,
   400-800 MHz). PLL A: 14x and 16x from VCO 794.5 MHz (CLKI_DIV 6,
   CLKFB_DIV 7, CLKOP_DIV 8 = 99.3 MHz, CLKOS_DIV 7 = 113.5 MHz). PLL B:
   18x (VCO 766 MHz, /6 = 127.7 MHz). A 4-input glitch-free mux in
   `clkgen.v`; run-time settings for 18x (`ph_top` 17, `ph_half` 9,
   `ms_top`, the rt_ hold, SD SCLK stretch); SDRAM stays CL3 (tRFC 8
   clocks = 62.6 ns, tRAS 6 = 47 ns: in spec); `speed 18` in
   `sw/speed/speed.s` and the +$F00A register. Timing: about 1.43x the
   worst-case model (16x: 1.27-1.31x), so it may simply not run. Step
   15's thinner kernel -> logic margin makes it less likely; do step 15b
   first. The plan must work out the mux for four sources, the PLL
   attributes, the calibration's behaviour at 18x and the sim model.

## Housekeeping

- **Merge and release steps 13 to 15** once Glen has run them and asks.
  One PR per step, squash-merged, bitstream commits dropped first. `main`
  is at step 12. The stacked branches will need rebasing in order.
- **Dead code:** the `ifdef TG68_X16` paths (frozen at step 14b) and the
  bisect switches (POST_CHIP, CHIP_IC, CACR_CLR, RD11, BANK_XOR, DP32_*)
  cost nothing in the FPGA. Removing them is tidiness only; ask Glen.
- **README.md** is 1,300 lines. Its per-step timing section could move to
  `docs/` if Glen wants a shorter front page.
- **xSysInfo oddities never explained** (step 9: caches-on Dhrystones 4%
  below step 8; 16x: -12% against the 12x file on the same board): see
  `docs/HISTORY.md`, results notes. Re-run back to back before any work.
