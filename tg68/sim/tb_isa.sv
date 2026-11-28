// Testbench for the differential instruction test (step 26a): tg68_bus +
// the TG68K kernel on a flat 4 MB memory with a fixed DTACK, running
// isa_test.s (made by gen_isa.py) to its done marker. Then it writes the
// result area to isa_out.hex and the kernel steps of every case to
// isa_steps.txt. run.sh isa compares isa_out.hex with isa_ref.hex
// (isa_cmp.py).
//
// The program tells the bench where it is: a write to $3FFFF8 starts case
// n (the long written), a write of $600DC0DE to $3FFFF0 is the end.
`timescale 1ns/1ps
module tb;
    reg clk = 0;
    always #5.875 clk = ~clk;          // 85.1 MHz

    reg        ext_reset = 1;
    wire       ASn, eRWn, UDSn, LDSn, BGn, oRESETn, oHALTEDn, stalled;
    wire       FC2, FC1, FC0;
    wire [31:1] a;
    wire [15:0] dout;
    reg  [15:0] din = 16'hFFFF;
    reg         dtackn = 1;
    wire [2:0]  fc = {FC2, FC1, FC0};

    // the whole memory is cacheable, as fast RAM is on the board
    wire [31:1] ea;
    reg icw = 1'b0;
    always @(posedge clk) icw <= 1'b1;
    tg68_bus dut (
        .clk(clk), .enPhi1(1'b0), .enPhi2(1'b0), .HALTn(1'b1),
        .extReset(ext_reset), .pwrUp(1'b0), .cyc_idle(),
        .oRESETn(oRESETn), .oHALTEDn(oHALTEDn), .E(), .VPAn(1'b1), .VMAn(),
        .ASn(ASn), .eRWn(eRWn), .LDSn(LDSn), .UDSn(UDSn),
        .FC2(FC2), .FC1(FC1), .FC0(FC0),
        .DTACKn(dtackn), .BERRn(1'b1), .BRn(1'b1), .BGn(BGn), .BGACKn(1'b1),
        .IPL2n(1'b1), .IPL1n(1'b1), .IPL0n(1'b1),
        .iEdb(din), .icache_win(icw), .icache_win_k(1'b1), .eab_early(ea),
        .oEdb(dout), .eab(a), .stalled(stalled));

    localparam integer MW = 1 << 21;   // 2M words = 4 MB
    reg [15:0] mem [0:MW-1];
    integer i;
    initial begin
        for (i = 0; i < MW; i = i + 1) mem[i] = 16'h0000;
        $readmemh("isa.mem", mem);
    end
    wire [31:0] byte_a = {a, 1'b0};

    // ---- slave: DTACK 2 clocks after the strobes, the same every cycle ----
    integer errors = 0, cycles = 0;
    integer lat = 0;
    reg [1:0] sst = 0;
    integer cas = -1, n_case = 0;
    reg done = 0;
    reg [15:0] wl_hi = 0;
    reg [31:0] cas_next = 0;
    reg        cas_go = 0;
    always @(posedge clk) begin
        case (sst)
        0: if (!ASn) begin lat <= 2; sst <= 1; cycles = cycles + 1; end
        1: if (lat > 0) lat <= lat - 1;
           else if (!UDSn || !LDSn) begin
               if (fc == 3'b111) begin
                   $display("ERROR %0t: interrupt acknowledge (none was raised)", $time);
                   errors = errors + 1; din <= 16'h0018;
               end else if (byte_a >= 32'h00400000) begin
                   $display("ERROR %0t case %0d: %s outside the 4 MB at %h", $time, cas, eRWn ? "read" : "write", byte_a);
                   errors = errors + 1; din <= 16'hFFFF;
               end else if (eRWn) din <= mem[byte_a[21:1]];
               else begin
                   if (!UDSn) mem[byte_a[21:1]][15:8] <= dout[15:8];
                   if (!LDSn) mem[byte_a[21:1]][7:0]  <= dout[7:0];
                   if (byte_a == 32'h003FFFF8) wl_hi <= dout;
                   if (byte_a == 32'h003FFFFA) begin cas_next <= {wl_hi, dout}; cas_go <= 1'b1; end
                   if (byte_a == 32'h003FFFF2 && dout == 16'hC0DE) done <= 1'b1;
               end
               dtackn <= 1'b0;
               sst <= 2;
           end
        2: if (ASn) begin dtackn <= 1'b1; din <= 16'hFFFF; sst <= 0; end
        endcase
    end

    // ---- kernel steps per case ----------------------------------------
    integer steps = 0, case_steps = 0, clocks = 0;
    integer stp [0:16383];
    initial for (i = 0; i < 16384; i = i + 1) stp[i] = 0;
    always @(posedge clk) begin
        clocks = clocks + 1;
        if (dut.k_clkena) begin steps = steps + 1; case_steps = case_steps + 1; end
        if (cas_go) begin
            cas_go <= 1'b0;
            if (cas >= 0 && cas < 16384) stp[cas] = case_steps;
            cas = cas_next; case_steps = 0; n_case = n_case + 1;
        end
    end

    // ---- run -----------------------------------------------------------
    integer fd, k;
    initial begin
        repeat (100) @(posedge clk);
        ext_reset = 0;
        for (k = 0; k < 400000000 && !done; k = k + 1) @(posedge clk);
        if (!done) begin $display("FAIL: no done marker (last case %0d, a=%h, q=%0d)", cas, byte_a, dut.q); errors = errors + 1; end
        // the end marker is case n (= the number of cases): the result area
        // is n blocks of 200 bytes (100 words) from $200000
        n_case = cas;
        fd = $fopen("isa_out.hex", "w");
        for (k = 32'h200000 >> 1; k < (32'h200000 >> 1) + n_case * 100; k = k + 1) $fwrite(fd, "%h\n", mem[k]);
        $fclose(fd);
        fd = $fopen("isa_steps.txt", "w");
        for (k = 0; k < n_case && k < 16384; k = k + 1) $fwrite(fd, "%0d %0d\n", k, stp[k]);
        $fclose(fd);
        $display("cases %0d, kernel steps %0d, clocks %0d, bus cycles %0d", n_case, steps, clocks, cycles);
        if (stalled) begin $display("FAIL stall flag set"); errors = errors + 1; end
        if (errors == 0) $display("RAN"); else $display("FAILED with %0d errors", errors);
        $finish;
    end
endmodule
