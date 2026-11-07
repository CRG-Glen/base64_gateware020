// Testbench: tg68_bus + TG68K kernel on a model asynchronous 68000 bus.
// ROM $0000-$1FFF, RAM $8000-$9FFF, random DTACK latency, an IACK answer
// with autovector 24+level, and protocol checks on every cycle.
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
    reg         dtackn = 1, berrn = 1, brn = 1, bgackn = 1;
    reg  [2:0]  ipl_n = 3'b111;

    tg68_bus dut (
        .clk(clk), .enPhi1(1'b0), .enPhi2(1'b0), .HALTn(1'b1),
        .extReset(ext_reset), .pwrUp(1'b0),
        .oRESETn(oRESETn), .oHALTEDn(oHALTEDn), .E(), .VPAn(1'b1), .VMAn(),
        .ASn(ASn), .eRWn(eRWn), .LDSn(LDSn), .UDSn(UDSn),
        .FC2(FC2), .FC1(FC1), .FC0(FC0),
        .DTACKn(dtackn), .BERRn(berrn), .BRn(brn), .BGn(BGn), .BGACKn(bgackn),
        .IPL2n(ipl_n[2]), .IPL1n(ipl_n[1]), .IPL0n(ipl_n[0]),
        .iEdb(din), .icache_win(icw), .icache_win_k(icw_k), .eab_early(ea),
        .oEdb(dout), .eab(a), .stalled(stalled));

    reg [15:0] rom [0:4095];
    reg [15:0] ram [0:4095];
    initial begin $readmemh("rom.mem", rom); $display("rom[0..3]=%h %h %h %h", rom[0], rom[1], rom[2], rom[3]); end

    wire [31:0] byte_a = {a, 1'b0};
    // Cacheable window, registered one clock behind the address like
    // fastmem_zii's decode: ROM and RAM here both count.
    reg icw = 1'b0;
    always @(posedge clk) icw <= (byte_a < 32'h2000) || (byte_a >= 32'h8000 && byte_a < 32'hA000);
    // ...and the same window from the kernel's early address, unregistered,
    // for the early lookup (tg68_bus decodes the real board's windows itself)
    wire [31:1] ea;
    wire [31:0] early_byte = {ea, 1'b0};
    wire icw_k = (early_byte < 32'h2000) || (early_byte >= 32'h8000 && early_byte < 32'hA000);
    integer fetches = 0;
    always @(negedge ASn) if (fc[1:0] == 2'b10) fetches = fetches + 1;
    wire [2:0]  fc = {FC2, FC1, FC0};
    // Cache-hit oracle (tg68_bus EARLY LOOKUP): every cache hit hands the
    // kernel the word the RAMs read before the tag compare; check it against
    // what the CPU last wrote there (a shadow of every CPU write, byte lane by
    // byte lane). Here that covers the self-modifying-code test under random
    // DTACK and the bus hand-over. Words never written are not checked.
    integer hit_chk = 0, hit_bad = 0;
    reg [17:0] shadow [int unsigned];
    reg [17:0] sh_s; reg [31:1] sh_k; reg [3:0] sh_pq = 0;
    always @(posedge clk) begin
        sh_pq <= dut.q;
        if (sh_pq == 4'd1 && dut.q != 4'd1 && !dut.eRWn) begin
            sh_k = dut.a_r;
            sh_s = shadow.exists(sh_k) ? shadow[sh_k] : 18'd0;
            if (!dut.uds_want) begin sh_s[17] = 1'b1; sh_s[15:8] = dut.oEdb[15:8]; end
            if (!dut.lds_want) begin sh_s[16] = 1'b1; sh_s[7:0]  = dut.oEdb[7:0];  end
            shadow[sh_k] = sh_s;
        end
        if (dut.q == 4'd8 && dut.cc_hit && shadow.exists(dut.a_r)) begin
            hit_chk = hit_chk + 1;
            sh_s = shadow[dut.a_r];
            if ((sh_s[17] && dut.k_dat[15:8] !== sh_s[15:8]) || (sh_s[16] && dut.k_dat[7:0] !== sh_s[7:0])) begin
                $display("FAIL cache hit: stale data at %h: CPU gets %h, last written %h",
                         {dut.a_r, 1'b0}, dut.k_dat, sh_s[15:0]);
                hit_bad = hit_bad + 1;
            end
        end
    end
    integer errors = 0, cycles = 0, iacks = 0, writes = 0;
    integer seed = 1;

    // ---- slave --------------------------------------------------------
    // Address must be stable while AS is low; write data while DS is low.
    reg [31:0] a_at_as;
    always @(negedge ASn) begin
        a_at_as = byte_a;
        cycles = cycles + 1;
    end
    always @(posedge clk) if (!ASn && byte_a != a_at_as) begin
        $display("ERROR %0t: address changed during AS (%h -> %h)", $time, a_at_as, byte_a);
        errors = errors + 1;
    end

    integer lat = 0;
    reg [1:0] sst = 0;
    always @(posedge clk) begin
        case (sst)
        0: if (!ASn) begin
               lat <= 2 + ($urandom % 24);       // 2..25 clocks
               sst <= 1;
           end
        1: if (lat > 0) lat <= lat - 1;
           else if (!UDSn || !LDSn) begin
               if (fc == 3'b111) begin            // IACK -> autovector
                   din <= {8'h00, 8'd24 + {5'd0, a[3:1]}};
                   iacks = iacks + 1;
               end else if (eRWn) begin
                   if (byte_a < 32'h2000)                            din <= rom[byte_a[12:1]];
                   else if (byte_a >= 32'h8000 && byte_a < 32'hA000) din <= ram[byte_a[12:1]];
                   else begin
                       $display("ERROR %0t: read from unmapped %h", $time, byte_a);
                       errors = errors + 1; din <= 16'hFFFF;
                   end
               end else begin
                   if (byte_a >= 32'h8000 && byte_a < 32'hA000) begin
                       if (!UDSn) ram[byte_a[12:1]][15:8] <= dout[15:8];
                       if (!LDSn) ram[byte_a[12:1]][7:0]  <= dout[7:0];
                       writes = writes + 1;
                   end else begin
                       $display("ERROR %0t: write to unmapped %h", $time, byte_a);
                       errors = errors + 1;
                   end
                   if (byte_a == 32'h8FFC) ipl_n <= 3'b111;   // handler acked
               end
               dtackn <= 1'b0;
               sst <= 2;
           end
        2: if (ASn) begin
               dtackn <= 1'b1;
               din <= 16'hFFFF;
               sst <= 0;
           end
        endcase
    end

    // ---- stimulus -------------------------------------------------------
    function [31:0] rd32(input [31:0] ad);
        rd32 = {ram[ad[12:1]], ram[ad[12:1]+1]};
    endfunction

    task check(input [31:0] ad, input [31:0] exp, input [8*24-1:0] what);
        if (rd32(ad) !== exp) begin
            $display("FAIL %-24s @%h = %h, expected %h", what, ad, rd32(ad), exp);
            errors = errors + 1;
        end else
            $display("ok   %-24s @%h = %h", what, ad, rd32(ad));
    endtask

    // trace + global timeout
    integer tr = 0;
    always @(negedge ASn) if (tr < 12) begin
        tr = tr + 1;
        $display("%0t cyc fc=%0d a=%h %s", $time, fc, byte_a, eRWn ? "R" : "W");
    end
    initial begin #20ms; $display("TIMEOUT pc-ish a=%h q=%0d", byte_a, dut.q); $finish; end

    integer i;
    initial begin
        for (i = 0; i < 4096; i = i + 1) ram[i] = 16'h0000;
        repeat (100) @(posedge clk);
        ext_reset = 0;
        // Raise a level-3 interrupt once the program has had time to get
        // to the wait loop (it is masked until then).
        repeat (20000) @(posedge clk);
        ipl_n <= 3'b100;                               // level 3
        // Exercise bus arbitration once, mid-run: request, wait for grant,
        // hold the bus, give it back.
        repeat (3000) @(posedge clk);
        brn = 0;
        while (BGn) @(posedge clk);
        @(posedge clk);
        if (!ASn) begin $display("ERROR: BG while AS low"); errors = errors + 1; end
        bgackn = 0; brn = 1;
        repeat (200) @(posedge clk);
        if (!ASn) begin $display("ERROR: cycle while BGACK held"); errors = errors + 1; end
        bgackn = 1;
        // run to the done marker
        for (i = 0; i < 400000 && rd32(32'h8FF0) != 32'h600DC0DE; i = i + 1)
            @(posedge clk);
        $display("bus cycles %0d (fetches %0d), writes %0d, IACK cycles %0d", cycles, fetches, writes, iacks);
        check(32'h8100, 32'h369D0368, "MULU.L");
        check(32'h8104, 32'h00022E09, "DIVU.L");
        check(32'h8108, 32'h0000000F, "BFEXTU");
        check(32'h810C, 32'hFFFFFF80, "EXTB.L");
        check(32'h8110, 32'h369D5ACD, "byte lanes / MOVE.W");
        check(32'h8114, 32'hA1B2C3D4, "misaligned MOVE.L");
        check(32'h8118, 32'h00007777, "TRAP/RTE");
        check(32'h811C, 32'h00004000, "MOVEC VBR");
        check(32'h8120, 32'h33333333, "IRQ3 autovector");
        check(32'h8130, 32'h00000258, "cached loop");
        check(32'h8134, 32'h00000001, "code before patch");
        check(32'h8138, 32'h00000002, "self-modified code");
        check(32'h8FF0, 32'h600DC0DE, "done marker");
        if (iacks != 1) begin $display("FAIL expected 1 IACK, got %0d", iacks); errors = errors + 1; end
        $display("cache hits checked against the CPU's writes %0d (stale: %0d)", hit_chk, hit_bad);
        if (hit_bad) errors = errors + hit_bad;
        if (hit_chk == 0) begin $display("FAIL cache-hit oracle never used"); errors = errors + 1; end
        if (stalled) begin $display("FAIL stall flag set"); errors = errors + 1; end
        if (errors == 0) $display("PASS");
        else             $display("FAILED with %0d errors", errors);
        $finish;
    end
endmodule
