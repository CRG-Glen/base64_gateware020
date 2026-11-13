// EXPERIMENT (branch exp-20x, never a release): the second PLL makes 20x
// (141.88 MHz, x5/3: CLKI_DIV 3, CLKFB_DIV 5, CLKOP_DIV 4, VCO 567.5 MHz) in
// place of 14x (exp-18x had 18x there). The names below still say 14 (c14,
// lock14, u_pll14, speed code 1) to keep the diff small: in this branch
// "14" means 20x.
//
// TG68 step 13: the system clock, switchable between 12x, 14x and 16x the
// Amiga's 7.09 MHz while running.
//
//   12x  85.13 MHz   the ICS570B's clock, straight from the pin (no PLL: at
//                    power-on and after any reset the board runs exactly as
//                    before this step)
//   14x  99.32 MHz   PLL, x7/6  (CLKI_DIV 6, CLKFB_DIV 7, CLKOP_DIV 7, VCO 695)
//   16x 113.51 MHz   PLL, x4/3  (CLKI_DIV 9, CLKFB_DIV 12, CLKOP_DIV 6, VCO 681)
//
// The ratios are exact, so every clock has a whole number of cycles per 7M
// period and the bus bridge's 7M aligner re-locks to it (the switch
// sequencer in the top level clears ph_locked after a switch).
//
// The switch is a glitch-free clock multiplexer in fabric, then a DCCA onto
// the global network. Each source has an enable that changes only on that
// source's falling edge (two-flop synchroniser), and a source is enabled
// only once every other source's enable is seen off: the old clock stops
// low, then the new one starts from low, so no pulse is ever cut short.
// The design simply sees a pause of a few clocks. `sel` comes from the
// system clock domain and only changes while the switch sequencer holds the
// CPU and the buses idle; `cur` reports the source actually running.
//
// ENABLE=0 (the 16x board-mod build, TG68_X16): no PLLs, clk = clk_in.
`default_nettype none
module clkgen #(
    parameter integer ENABLE = 1
)(
    input  wire       clk_in,     // 12x from the ICS570B (pin L1)
    input  wire [1:0] sel,        // 0 12x, 1 14x, 2 16x
    output wire       clk,        // the system clock
    output wire       lock14,
    output wire       lock16,
    output wire [1:0] cur         // the source running now (0 1 2)
);
generate if (ENABLE == 0) begin : g_fixed
    assign clk = clk_in;
    assign lock14 = 1'b0;
    assign lock16 = 1'b0;
    assign cur = 2'd0;
end else begin : g_pll
    wire c12 = clk_in;
    wire c14, c16;
`ifdef YOSYS
    (* FREQUENCY_PIN_CLKI="85.13" *)
    (* FREQUENCY_PIN_CLKOP="141.88" *)
    (* ICP_CURRENT="12" *) (* LPF_RESISTOR="8" *) (* MFG_ENABLE_FILTEROPAMP="1" *) (* MFG_GMCREF_SEL="2" *)
    EHXPLLL #(
        .PLLRST_ENA("DISABLED"), .INTFB_WAKE("DISABLED"), .STDBY_ENABLE("DISABLED"),
        .DPHASE_SOURCE("DISABLED"), .OUTDIVIDER_MUXA("DIVA"), .OUTDIVIDER_MUXB("DIVB"),
        .OUTDIVIDER_MUXC("DIVC"), .OUTDIVIDER_MUXD("DIVD"),
        .CLKI_DIV(3), .CLKOP_ENABLE("ENABLED"), .CLKOP_DIV(4),
        .CLKOP_CPHASE(3), .CLKOP_FPHASE(0), .FEEDBK_PATH("CLKOP"), .CLKFB_DIV(5)
    ) u_pll14 (
        .RST(1'b0), .STDBY(1'b0), .CLKI(c12), .CLKOP(c14), .CLKFB(c14), .CLKINTFB(),
        .PHASESEL0(1'b0), .PHASESEL1(1'b0), .PHASEDIR(1'b1), .PHASESTEP(1'b1),
        .PHASELOADREG(1'b1), .PLLWAKESYNC(1'b0), .ENCLKOP(1'b0), .LOCK(lock14)
    );
    (* FREQUENCY_PIN_CLKI="85.13" *)
    (* FREQUENCY_PIN_CLKOP="113.507" *)
    (* ICP_CURRENT="12" *) (* LPF_RESISTOR="8" *) (* MFG_ENABLE_FILTEROPAMP="1" *) (* MFG_GMCREF_SEL="2" *)
    EHXPLLL #(
        .PLLRST_ENA("DISABLED"), .INTFB_WAKE("DISABLED"), .STDBY_ENABLE("DISABLED"),
        .DPHASE_SOURCE("DISABLED"), .OUTDIVIDER_MUXA("DIVA"), .OUTDIVIDER_MUXB("DIVB"),
        .OUTDIVIDER_MUXC("DIVC"), .OUTDIVIDER_MUXD("DIVD"),
        .CLKI_DIV(9), .CLKOP_ENABLE("ENABLED"), .CLKOP_DIV(6),
        .CLKOP_CPHASE(3), .CLKOP_FPHASE(0), .FEEDBK_PATH("CLKOP"), .CLKFB_DIV(12)
    ) u_pll16 (
        .RST(1'b0), .STDBY(1'b0), .CLKI(c12), .CLKOP(c16), .CLKFB(c16), .CLKINTFB(),
        .PHASESEL0(1'b0), .PHASESEL1(1'b0), .PHASEDIR(1'b1), .PHASESTEP(1'b1),
        .PHASELOADREG(1'b1), .PLLWAKESYNC(1'b0), .ENCLKOP(1'b0), .LOCK(lock16)
    );
`else
    // simulation: N output cycles per 12 input cycles, re-phased every 12
    pll_model #(.N(20)) u_pll14 (.clk_in(c12), .clk_out(c14), .lock(lock14));   // exp-20x: 20x
    pll_model #(.N(16)) u_pll16 (.clk_in(c12), .clk_out(c16), .lock(lock16));
`endif
    // the glitch-free switch: one enable per source, changed on that
    // source's falling edge; on only once the others are seen off
    reg s12 = 1'b1, e12 = 1'b1;   // power-on: 12x
    reg s14 = 1'b0, e14 = 1'b0;
    reg s16 = 1'b0, e16 = 1'b0;
    always @(negedge c12) begin s12 <= (sel == 2'd0) && !e14 && !e16; e12 <= s12; end
    always @(negedge c14) begin s14 <= (sel == 2'd1) && !e12 && !e16; e14 <= s14; end
    always @(negedge c16) begin s16 <= (sel == 2'd2) && !e12 && !e14; e16 <= s16; end
    wire mux = (c12 & e12) | (c14 & e14) | (c16 & e16);
    assign cur = e16 ? 2'd2 : e14 ? 2'd1 : 2'd0;
`ifdef YOSYS
    DCCA u_gbuf (.CLKI(mux), .CE(1'b1), .CLKO(clk));
`elsif CAL_DRIFT
    // sim (tb_top.sv CAL_DRIFT): no delay at first, then 0.25 ns from
    // 300 us on, which moves the rising-edge 7M sample into the tb's
    // 0.05-0.45 ns 7M jitter: the stream in use (rising, at 12x) starts to
    // move and the top level must swap to the falling one by itself
    reg  clk_d = 1'b0;
    real dly   = 0.0;
    initial begin #300000; dly = 0.25; end
    always @(mux) clk_d <= #(dly) mux;
    assign clk = clk_d;
`elsif CAL_TEST
    // sim (tb_top.sv CAL_TEST): an insertion delay of half a 12x period plus
    // 0.2 ns, so at 12x the falling-edge 7M sample lands inside the tb's
    // 0-0.4 ns 7M jitter and the calibration must pick the rising stream
    // (a transport delay: a delayed continuous assign is inertial and would
    // swallow the 14x / 16x half periods, which are shorter than the delay)
    reg clk_d = 1'b0;
    always @(mux) clk_d <= #(6.073) mux;
    assign clk = clk_d;
`else
    assign clk = mux;
`endif
end endgenerate
endmodule

`ifndef YOSYS
// Behavioural PLL for Verilator: N cycles of clk_out for every 12 cycles of
// clk_in, re-phased at the start of each group of 12, so it stays locked to
// the 7M grid exactly as the real PLL does. lock rises after a few groups.
module pll_model #(parameter integer N = 14) (
    input  wire clk_in,
    output reg  clk_out = 1'b0,
    output reg  lock = 1'b0
);
    integer   n_in = 0, groups = 0, k;
    realtime  t0 = 0, half = 0;
    reg       go = 1'b0;
    always @(posedge clk_in) begin
        if (n_in == 0) begin
            if (t0 > 0) begin
                half = ($realtime - t0) / (2.0 * N);
                groups = groups + 1;
                if (groups > 4) lock <= 1'b1;
                go = ~go;
            end
            t0 = $realtime;
        end
        n_in = (n_in == 11) ? 0 : n_in + 1;
    end
    // each group: N cycles, the last low half cut short by the next group
    always @(go) begin
        for (k = 0; k < 2 * N - 1; k = k + 1) begin
            clk_out = ~clk_out;
            #(half);
        end
        clk_out = 1'b0;
    end
endmodule
`endif
`default_nettype wire
