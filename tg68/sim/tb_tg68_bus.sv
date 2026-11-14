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
        .extReset(ext_reset), .pwrUp(1'b0), .cyc_idle(),
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
    integer long_hits = 0;               // pair hits (32-bit data path)
    // k_long_ack and k_din_sel feed the kernel and are classed adapter ->
    // kernel (2 clocks) by check_timing.py: neither may change in the clock
    // just before the kernel samples (the clkena clock).
    reg clw3_armed = 1'b0;   // kernel change 5 check (below)
    integer ks_cyc = 0, ks_chg = -10, ks_bad = 0; reg ks_la = 0, ks_ds = 0, ks_hs = 0, ks_dd = 0;
    reg [31:1] ks_fac = 0; reg ks_ps = 0; reg [15:0] ks_fp = 0; integer ks_fchg = -10; reg fpp = 0; integer fp_chk = 0;   // step 15: fetch predictor
    integer rd_pairs = 0;                // pair reads from the SDRAM (step 9)
    integer n_clw = 0;                   // steps with clkena_lw (kernel change 2)
    always @(posedge clk) begin
        ks_cyc = ks_cyc + 1;
        if (dut.k_long_ack !== ks_la || dut.k_din_sel !== ks_ds || dut.k_din_hsel !== ks_hs || dut.k_din_dsel !== ks_dd || dut.k_din_psel !== ks_ps) ks_chg = ks_cyc;
        // step 15: the predicted word must be 2 clocks old when the kernel
        // samples it, and equal to what the CPU last wrote there
        if (dut.k_din_fp !== ks_fp) ks_fchg = ks_cyc;
        ks_ps = dut.k_din_psel; ks_fp = dut.k_din_fp;
        if (dut.k_clkena && fpp) begin
            fp_chk = fp_chk + 1;
            if (ks_cyc - ks_fchg < 2 || dut.k_dat !== dut.k_din_fp) begin
                $display("FAIL predicted fetch: word changed %0d clocks before the kernel sampled it, data_in %h, predicted %h", ks_cyc - ks_fchg, dut.k_dat, dut.k_din_fp);
                ks_bad = ks_bad + 1; hit_bad = hit_bad + 1;
            end
            chk_word(dut.k_addr[31:1], dut.k_dat);
        end
        // fp_ac (the compare copy of the predicted address) is classed a
        // 2-clock source: it must never have just changed while fp_v is set
        if (dut.fp_ac !== ks_fac && dut.fp_v) begin
            $display("FAIL fp_ac changed on the edge into a clock with fp_v set");
            ks_bad = ks_bad + 1; hit_bad = hit_bad + 1;
        end
        ks_fac = dut.fp_ac;
        // cnt_ok is cnt >= STEP-1 as a register (step 15)
        if (!dut.extReset && dut.q != 4'd0 && dut.cnt_ok !== (dut.cnt >= 3)) begin
            $display("FAIL cnt_ok %b with cnt %0d (q %0d)", dut.cnt_ok, dut.cnt, dut.q);
            ks_bad = ks_bad + 1; hit_bad = hit_bad + 1;
        end
        fpp = (dut.q == 4'd1) && !dut.internal_step && dut.fp_hit && !dut.extReset;
        ks_la = dut.k_long_ack; ks_ds = dut.k_din_sel; ks_hs = dut.k_din_hsel; ks_dd = dut.k_din_dsel;
        // The kernel's l1 <= long_ack (Base64 change, was long_ack AND cand)
        // relies on this: long_ack only ever answers an offered pair.
        if (dut.k_long_ack && !dut.k_long_cand) begin
            $display("FAIL long_ack high without long_cand");
            ks_bad = ks_bad + 1; hit_bad = hit_bad + 1;
        end
        if (dut.dec_r !== (dut.q == 4'd1)) begin
            $display("FAIL dec_r out of step with q (q=%0d dec_r=%b)", dut.q, dut.dec_r);
            ks_bad = ks_bad + 1; hit_bad = hit_bad + 1;
        end
        // k_clkena_lw3 too (kernel change 5), from the first edge on (it
        // powers on at 1 so that yosys keeps it a separate register)
        if (clw3_armed && dut.k_clkena_lw3 !== dut.k_clkena_lw) begin
            $display("FAIL k_clkena_lw3 %b, k_clkena_lw %b", dut.k_clkena_lw3, dut.k_clkena_lw);
            ks_bad = ks_bad + 1; hit_bad = hit_bad + 1;
        end
        clw3_armed = 1'b1;
        // k_clkena_lw2 is an identical copy of k_clkena_lw (kernel change 4)
        if (dut.k_clkena_lw2 !== dut.k_clkena_lw) begin
            $display("FAIL k_clkena_lw2 %b, k_clkena_lw %b", dut.k_clkena_lw2, dut.k_clkena_lw);
            ks_bad = ks_bad + 1; hit_bad = hit_bad + 1;
        end
        // k_step is the adapter's copy of k_clkena: always equal
        if (dut.k_step !== dut.k_clkena) begin
            $display("FAIL k_step %b, k_clkena %b", dut.k_step, dut.k_clkena);
            ks_bad = ks_bad + 1; hit_bad = hit_bad + 1;
        end
        // Kernel change 2: the registered clkena_lw must equal what the
        // kernel computed itself, clkena AND (NOT longword OR long_ack), on
        // every clock (kernel outputs read live).
        if (dut.k_clkena_lw !== (dut.k_clkena && (!dut.k_longword || dut.k_long_ack))) begin
            $display("FAIL k_clkena_lw %b, kernel formula %b", dut.k_clkena_lw,
                     dut.k_clkena && (!dut.k_longword || dut.k_long_ack));
            ks_bad = ks_bad + 1; hit_bad = hit_bad + 1;
        end
        if (dut.k_clkena) n_clw = n_clw + dut.k_clkena_lw;
        if (dut.k_clkena && ks_cyc - ks_chg < 1) begin
            $display("FAIL long_ack/k_din_sel changed in the clock before the kernel sampled them");
            ks_bad = ks_bad + 1; hit_bad = hit_bad + 1;
        end
    end
    reg        hp_pend = 0, hp_long = 0; reg [31:1] hp_a = 0;
    reg [17:0] cw_s;
    task chk_word(input [31:1] wa, input [15:0] got);
        if (shadow.exists(wa)) begin
            hit_chk = hit_chk + 1;
            cw_s = shadow[wa];
            if ((cw_s[17] && got[15:8] !== cw_s[15:8]) || (cw_s[16] && got[7:0] !== cw_s[7:0])) begin
                $display("FAIL cache hit: stale data at %h: CPU gets %h, last written %h", {wa, 1'b0}, got, cw_s[15:0]);
                hit_bad = hit_bad + 1;
            end
        end
    endtask
    reg [17:0] shadow [int unsigned];
    reg [17:0] sh_s; reg [31:1] sh_k; reg [3:0] sh_pq = 0;
    always @(posedge clk) begin
        sh_pq <= dut.q;
        if (dut.cyc_start && !dut.eRWn) begin
            sh_k = dut.a_r;
            sh_s = shadow.exists(sh_k) ? shadow[sh_k] : 18'd0;
            if (!dut.uds_want) begin sh_s[17] = 1'b1; sh_s[15:8] = dut.oEdb[15:8]; end
            if (!dut.lds_want) begin sh_s[16] = 1'b1; sh_s[7:0]  = dut.oEdb[7:0];  end
            shadow[sh_k] = sh_s;
            // a pair write (32-bit SDRAM, step 8: direct path only, so not
            // made in this bench, which has no fast RAM) writes the next word
            if (dut.k_long_ack) shadow[sh_k + 31'd1] = {2'b11, dut.dp_wdata_lo};
        end
        // A hit is recorded in CCMP and checked on the clock the kernel
        // samples it (k_clkena): data_in (k_dat), and for a pair hit also
        // data_in_hi (k_din_ce) and long_ack. Checked first, then recorded.
        // A pair read from the SDRAM (step 9: k_long_ack on a read that is
        // not a cache hit, k_din_sel low): both words against the shadow.
        if (dut.k_clkena && dut.k_long_ack && dut.eRWn && !dut.k_din_sel) begin
            rd_pairs = rd_pairs + 1;
            chk_word(dut.a_r, dut.k_din_hmux);
            chk_word(dut.a_r + 31'd1, dut.k_dat);
        end
        if (hp_pend && dut.k_clkena) begin
            hp_pend = 0;
            if (dut.k_long_ack !== hp_long) begin
                $display("FAIL cache hit at %h: long_ack %b, expected %b", {hp_a, 1'b0}, dut.k_long_ack, hp_long);
                hit_bad = hit_bad + 1;
            end
            if (hp_long) begin
                long_hits = long_hits + 1;
                chk_word(hp_a, dut.k_din_hmux);
                chk_word(hp_a + 31'd1, dut.k_dat);
            end else
                chk_word(hp_a, dut.k_dat);
        end
        if (dut.q == 4'd8 && (dut.cc_long || dut.cc_hit)) begin
            hp_pend = 1; hp_long = dut.cc_long; hp_a = dut.a_r;
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
        $display("cache hits checked against the CPU's writes %0d (stale: %0d); pair hits %0d; clkena_lw steps %0d", hit_chk, hit_bad, long_hits, n_clw);
        if (hit_bad) errors = errors + hit_bad;
        if (hit_chk == 0) begin $display("FAIL cache-hit oracle never used"); errors = errors + 1; end
        if (stalled) begin $display("FAIL stall flag set"); errors = errors + 1; end
        if (dut.fp_chk_bad) begin $display("FAIL: %0d predicted fetches differed from the cache's own lookup", dut.fp_chk_bad); errors = errors + 1; end
        $display("predicted fetches %0d (checked at the kernel's sample clock: %0d)", dut.fp_hits, fp_chk);
        if (dut.cc_bad) begin $display("FAIL: %0d CCMP compares used registered inputs that differ from a_r", dut.cc_bad); errors = errors + 1; end
        if (errors == 0) $display("PASS");
        else             $display("FAILED with %0d errors", errors);
        $finish;
    end
endmodule
