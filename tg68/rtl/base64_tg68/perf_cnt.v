// ============================================================================
// perf_cnt -- performance counters (TG68 step 18). Test builds only:
// build.py --perf defines TG68_PERF and adds this file; without it nothing
// here is read and the netlist is the normal one.
//
// N counters of W bits. Each counts the clocks in which its event flag is
// high, while running. The event flags are registered one-clock pulses made
// in tg68_bus.v and the top level from registers only, so no counter hangs
// on a path of the CPU sequencer. Counter 0 counts clocks (its flag is tied
// high).
//
// Control (turbomem_zii +$F00E, write $5Cxx, cmd = xx):
//   cmd[7:6] 0   select counter cmd[5:0] for the data words
//            1   freeze
//            2   run
//            3   clear all (running or frozen stays as it was; perf
//                CLEAR then sends run)
// Reads: +$F00E = stat, +$F010 / +$F012 / +$F014 = the selected counter's
// bits 15:0, 31:16, 39:32 (q, registered every clock: freeze before reading,
// or the words may come from different counts).
//
// Power-on: frozen, all zero. An Amiga reset (slave_reset: the external reset
// or the /RESET pin, which the RESET instruction pulls too) freezes the
// counters and, if they were running, sets frz, so a program that can only
// be left with a reset still leaves its numbers behind. The counters keep
// their values through any reset; only CLEAR or a power cycle zeroes them.
// ============================================================================
`default_nettype none
module perf_cnt #(
    parameter integer N = 20,
    parameter integer W = 40
)(
    input  wire          clk,
    input  wire          amiga_reset,
    input  wire [N-1:0]  ev,
    input  wire          cmd_wr,     // one clock: a keyed write
    input  wire [7:0]    cmd,
    output reg  [W-1:0]  q = {W{1'b0}},
    output wire [15:0]   stat        // {run, frz, N, 2'b00, sel}
);
    reg       run = 1'b0;
    reg       frz = 1'b0;
    reg       clr = 1'b0;
    reg [5:0] sel = 6'd0;
    assign stat = {run, frz, N[5:0], 2'b00, sel};

`ifndef YOSYS
    reg  sim_reset = 1'b0;    // sim only: the tb pulses it (test_top.s)
    wire rst = amiga_reset || sim_reset;
`else
    wire rst = amiga_reset;
`endif
    always @(posedge clk) begin
        clr <= 1'b0;
        if (rst) begin
            if (run) frz <= 1'b1;
            run <= 1'b0;
        end else if (cmd_wr) begin
            case (cmd[7:6])
            2'd0: sel <= cmd[5:0];
            2'd1: run <= 1'b0;
            2'd2: begin run <= 1'b1; frz <= 1'b0; end
            2'd3: clr <= 1'b1;
            endcase
        end
    end

    wire [N*W-1:0] flat;
    genvar g;
    generate for (g = 0; g < N; g = g + 1) begin : gc
        reg [W-1:0] v = {W{1'b0}};
        always @(posedge clk)
            if (clr)              v <= {W{1'b0}};
            else if (run && ev[g]) v <= v + {{(W-1){1'b0}}, 1'b1};
        assign flat[g*W +: W] = v;
    end endgenerate

    always @(posedge clk)
        q <= (sel < N) ? flat[sel*W +: W] : {W{1'b0}};
endmodule
`default_nettype wire
