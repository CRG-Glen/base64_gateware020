// Full-top simulation: base64_tg68_top on a crude Amiga motherboard model.
//   clk_12x 85.13 MHz, clk_7m = /12 (as the ICS570B gives)
//   "Gary": DTACK 2 7M clocks after AS for ROM/RAM; VPA for $BFxxxx (CIA)
//           and for FC=7 (IACK); open-drain /RESET and /HALT with pull-ups
//   ROM $000000-$001FFF (overlay), RAM $008000-$009FFF, CIA reads $A5
`timescale 1ns/1ps
module tb;
    // -DTG68_X16 (VLFLAGS=-DTG68_X16 sh sim/run.sh ...): the 16x build,
    // 113.5 MHz and clk_7m = /16, the SDRAM model at CL3 (the RTL takes its
    // 16x settings from the same define)
`ifdef TG68_X16
    localparam integer CM = 16;
    reg clk12 = 0;
    always #4.405 clk12 = ~clk12;
`else
    localparam integer CM = 12;
    reg clk12 = 0;
    always #5.873 clk12 = ~clk12;
`endif
    reg [3:0] div = 0;
    reg clk7_0 = 0;
    always @(posedge clk12) begin
        div <= (div == CM - 1) ? 0 : div + 1;
        if (div == 0)      clk7_0 <= 1;
        if (div == CM / 2) clk7_0 <= 0;
    end
`ifdef CAL_TEST
    // step 13: 7M edges 0-0.4 ns late at random, with the clock delayed in
    // clkgen.v, to test the 7M capture calibration
    reg clk7 = 0;
    always @(clk7_0) begin
        #($urandom_range(0, 400) * 0.001);
        clk7 = clk7_0;
    end
`elsif CAL_DRIFT
    // step 14: 7M edges 0.05-0.45 ns late; clkgen.v delays the clock by
    // 0.25 ns from 300 us on (drift onto the rising-edge sample)
    reg clk7 = 0;
    always @(clk7_0) begin
        #($urandom_range(50, 450) * 0.001);
        clk7 = clk7_0;
    end
`else
    wire clk7 = clk7_0;
`endif

    wire [23:1] a;
    wire [15:0] d;
    wire as_n, uds_n, lds_n, rw, vma_n, e, bg_n;
    wire [2:0] fc;
    reg  dtack_n = 1, vpa_n = 1;
    reg  [2:0] ipl_n = 3'b111;
    wire reset_n, halt_n;
    pullup (reset_n);
    pullup (halt_n);
    wire led_r, led_g, led_b, cfgout_n;

    reg  [15:0] mb_q = 16'hFFFF;
    reg         mb_drive = 0;
    assign d = mb_drive ? mb_q : 16'bz;

    base64_tg68_top #(
        .PWRUP_BIT(12), .CAL_EDGES(64), .COLD_RETRY(1'b0), .FORCE_RETRY_MS(0),
`ifdef SDTEST
        .PASSIVE_EN(1'b0), .ENABLE_SD(1'b1),
`else
        .PASSIVE_EN(1'b0), .ENABLE_SD(1'b0),
`endif
`ifdef FASTMEM
        .ENABLE_FASTMEM(1'b1)
`else
        .ENABLE_FASTMEM(1'b0)
`endif
    ) dut (
        .clk_7m(clk7), .clk_12x(clk12),
        .cpu_a(a), .cpu_d(d), .cpu_as_n(as_n), .cpu_uds_n(uds_n),
        .cpu_lds_n(lds_n), .cpu_rw(rw), .cpu_fc(fc), .cpu_vma_n(vma_n),
        .cpu_e(e), .cpu_bg_n(bg_n), .cpu_dtack_n(dtack_n), .cpu_vpa_n(vpa_n),
        .cpu_berr_n(1'b1), .cpu_br_n(1'b1), .cpu_bgack_n(1'b1),
        .cpu_ipl_n(ipl_n), .cpu_reset_n(reset_n), .cpu_halt_n(halt_n),
        .cfgin_n(1'b0), .cfgout_n(cfgout_n),
        .cbt_oe_d0_7_n(), .cbt_oe_d8_15_n(), .cbt_oe_ctl_hi_n(),
        .cbt_oe_a8_17_n(), .cbt_oe_a1_7_n(),
        .sdram_a(sa), .sdram_ba(sba), .sdram_dq(sdq), .sdram_dqm(sdqm), .sdram_clk(sclk),
        .sdram_cke(scke), .sdram_ras_n(sras), .sdram_cas_n(scas), .sdram_we_n(swe),
        .sdram_cs_n(scs), .sd_clk(), .sd_cmd(sd_cmd_w), .sd_d(sd_d_w),
        .led_r(led_r), .led_g(led_g), .led_b(led_b));

    // SD pins: MOSI looped back to MISO, so every byte shifted out is
    // shifted back in (the SD test checks the whole SPI data path)
    wire sd_cmd_w; wire [3:0] sd_d_w;
    assign sd_d_w[0] = sd_cmd_w;
    wire [12:0] sa; wire [1:0] sba, sdqm; wire [15:0] sdq;
    wire sclk, scke, sras, scas, swe, scs;
`ifdef FASTMEM
    sdram_model_checked #(.CAS_LAT(CM == 16 ? 3 : 2), .ADDR_BITS(24)) u_sdram (
        .clk(sclk), .a(sa), .ba(sba), .dq(sdq), .dqm(sdqm),
        .cke(scke), .cs_n(scs), .ras_n(sras), .cas_n(scas), .we_n(swe));
`endif
    reg [15:0] rom [0:4095];
    reg [15:0] ram [0:4095];
    integer i;
    initial begin
        `ifdef MEMBENCH
        $readmemh("rom_mem.mem", rom);
`elsif FASTMEM
        $readmemh("rom_top_fm.mem", rom);
`else
        $readmemh("rom_top.mem", rom);
`endif
        for (i = 0; i < 4096; i = i + 1) ram[i] = 0;
    end
    wire [23:0] ba = {a, 1'b0};

    // ---- Gary, on the 7M grid -------------------------------------------
    integer cycles = 0, iacks = 0, cia = 0, errors = 0, unmapped = 0, romf = 0;
    // shortest request -> ack time on the direct port, in clocks
    integer dp_t = 0, dp_min = 99; reg dp_prev = 0;
    always @(posedge dut.clk) begin
        dp_prev <= dut.cpu.dp_req_i;
        if (dut.cpu.dp_req_i && !dp_prev) dp_t = 0; else dp_t = dp_t + 1;
        if (dut.cpu.dp_ack && dut.cpu.dp_busy && dp_t < dp_min) dp_min = dp_t;
    end
    // data-cache hits (CCMP on a data read that hits)
    integer dc_hits = 0;
    always @(posedge dut.clk)
        if (dut.cpu.q == 4'd8 && !dut.cpu.cyc_fetch && dut.cpu.cc_hit) dc_hits = dc_hits + 1;
    // ---- cache-hit oracle (tg68_bus EARLY LOOKUP) ---------------------------
    // A cache hit hands the CPU the word the RAMs read on the edge into
    // DECIDE, before the tag compare. Every hit, in every test (benches
    // included), is checked against what the CPU last wrote to that word: a
    // shadow copy records every CPU write, byte lane by byte lane. Words the
    // CPU never wrote (ROM, untouched RAM) have no shadow and are not checked.
    // The shadow is dropped when MapROM switches, which changes what the ROM
    // addresses return.
    integer hit_chk = 0, hit_bad = 0;
    integer long_hits = 0;               // pair hits (32-bit data path)
    integer wr_pairs = 0;                // pair writes (32-bit SDRAM)
    integer hit_4f00 = 0;                // pair hits at 0x08004F00 (step 9)
    integer ipair_hit = 0, ipair_rd = 0; // instruction-stream pairs (step 10)
    integer chip_ihit = 0;               // instruction-cache hits on chip RAM (step 11)
    integer n_posted = 0;                // buffered chip writes (steps 11, 12)
    integer wb_max = 0;                  // most entries ever in the buffer
    always @(posedge dut.clk) begin
        if (dut.wb_acc) n_posted = n_posted + 1;
        if (dut.wb_cnt > wb_max) wb_max = dut.wb_cnt;
    end
    // step 12 ordering: the program writes four words to $8E90-$8E96 and
    // then reads a CIA register; by the time that read reaches the
    // motherboard, all four writes must be in chip RAM
    integer ord_chk = 0, ord_bad = 0;
    always @(negedge as_n) if (ba[23:16] == 8'hBF && ram[12'h748] == 16'h1111) begin
        ord_chk = ord_chk + 1;
        if (ram[12'h749] !== 16'h2222 || ram[12'h74A] !== 16'h3333 || ram[12'h74B] !== 16'h4444) begin
            ord_bad = ord_bad + 1;
            $display("FAIL: CIA cycle ran before the buffered chip writes: %h %h %h %h",
                     ram[12'h748], ram[12'h749], ram[12'h74A], ram[12'h74B]);
        end
    end
    reg     hp_f = 0;
    // k_long_ack and k_din_sel feed the kernel and are classed adapter ->
    // kernel (2 clocks) by check_timing.py: neither may change in the clock
    // just before the kernel samples (the clkena clock).
    reg clw3_armed = 1'b0;   // kernel change 5 check (below)
    integer ks_cyc = 0, ks_chg = -10, ks_bad = 0; reg ks_la = 0, ks_ds = 0, ks_hs = 0, ks_dd = 0;
    reg [31:1] ks_fac = 0; reg ks_ps = 0; reg [15:0] ks_fp = 0; integer ks_fchg = -10; reg fpp = 0; integer fp_chk = 0;   // step 15: fetch predictor
    integer rd_pairs = 0;                // pair reads from the SDRAM (step 9)
    integer n_clw = 0;                   // steps with clkena_lw (kernel change 2)
    always @(posedge dut.clk) begin
        ks_cyc = ks_cyc + 1;
        if (dut.cpu.k_long_ack !== ks_la || dut.cpu.k_din_sel !== ks_ds || dut.cpu.k_din_hsel !== ks_hs || dut.cpu.k_din_dsel !== ks_dd || dut.cpu.k_din_psel !== ks_ps) ks_chg = ks_cyc;
        // step 15: the predicted word must be 2 clocks old when the kernel
        // samples it, and equal to what the CPU last wrote there
        if (dut.cpu.k_din_fp !== ks_fp) ks_fchg = ks_cyc;
        ks_ps = dut.cpu.k_din_psel; ks_fp = dut.cpu.k_din_fp;
        if (fpp && !dut.cpu.k_clkena) begin
            $display("FAIL predicted fetch in DECIDE not followed by a kernel step");
            ks_bad = ks_bad + 1; hit_bad = hit_bad + 1;
        end
        if (dut.cpu.k_clkena && fpp) begin
            fp_chk = fp_chk + 1;
            if (ks_cyc - ks_fchg < 2 || dut.cpu.k_dat !== dut.cpu.k_din_fp) begin
                $display("FAIL predicted fetch: word changed %0d clocks before the kernel sampled it, data_in %h, predicted %h", ks_cyc - ks_fchg, dut.cpu.k_dat, dut.cpu.k_din_fp);
                ks_bad = ks_bad + 1; hit_bad = hit_bad + 1;
            end
            chk_word(dut.cpu.k_addr[31:1], dut.cpu.k_dat);
            if (dut.cpu.k_addr[31:1] >= 31'h4000 && dut.cpu.k_addr[31:1] < 31'h5000) chip_ihit = chip_ihit + 1;
        end
        // fp_ac (the compare copy of the predicted address) is classed a
        // 2-clock source: it must never have just changed while fp_v is set
        if (dut.cpu.fp_ac !== ks_fac && dut.cpu.fp_v) begin
            $display("FAIL fp_ac changed on the edge into a clock with fp_v set");
            ks_bad = ks_bad + 1; hit_bad = hit_bad + 1;
        end
        ks_fac = dut.cpu.fp_ac;
        // cnt_ok is cnt >= STEP-1 as a register (step 15)
        if (!dut.cpu.extReset && dut.cpu.q != 4'd0 && dut.cpu.cnt_ok !== (dut.cpu.cnt >= 3)) begin
            $display("FAIL cnt_ok %b with cnt %0d (q %0d)", dut.cpu.cnt_ok, dut.cpu.cnt, dut.cpu.q);
            ks_bad = ks_bad + 1; hit_bad = hit_bad + 1;
        end
        fpp = (dut.cpu.q == 4'd1) && !dut.cpu.internal_step && dut.cpu.fp_hit && !dut.cpu.extReset;
        ks_la = dut.cpu.k_long_ack; ks_ds = dut.cpu.k_din_sel; ks_hs = dut.cpu.k_din_hsel; ks_dd = dut.cpu.k_din_dsel;
        // The kernel's l1 <= long_ack (Base64 change, was long_ack AND cand)
        // relies on this: long_ack only ever answers an offered pair.
        if (dut.cpu.k_long_ack && !dut.cpu.k_long_cand) begin
            $display("FAIL long_ack high without long_cand");
            ks_bad = ks_bad + 1; hit_bad = hit_bad + 1;
        end
        if (dut.cpu.dec_r !== (dut.cpu.q == 4'd1)) begin
            $display("FAIL dec_r out of step with q (q=%0d dec_r=%b)", dut.cpu.q, dut.cpu.dec_r);
            ks_bad = ks_bad + 1; hit_bad = hit_bad + 1;
        end
        // tick_rq is tick_r as a register (posted chip writes): always equal
        if (dut.tick_rq !== dut.tick_r) begin
            $display("FAIL tick_rq %b, tick_r %b", dut.tick_rq, dut.tick_r);
            ks_bad = ks_bad + 1; hit_bad = hit_bad + 1;
        end
        // k_clkena_lw3 too (kernel change 5), from the first edge on (it
        // powers on at 1 so that yosys keeps it a separate register)
        if (clw3_armed && dut.cpu.k_clkena_lw3 !== dut.cpu.k_clkena_lw) begin
            $display("FAIL k_clkena_lw3 %b, k_clkena_lw %b", dut.cpu.k_clkena_lw3, dut.cpu.k_clkena_lw);
            ks_bad = ks_bad + 1; hit_bad = hit_bad + 1;
        end
        clw3_armed = 1'b1;
        // k_clkena_lw2 is an identical copy of k_clkena_lw (kernel change 4)
        if (dut.cpu.k_clkena_lw2 !== dut.cpu.k_clkena_lw) begin
            $display("FAIL k_clkena_lw2 %b, k_clkena_lw %b", dut.cpu.k_clkena_lw2, dut.cpu.k_clkena_lw);
            ks_bad = ks_bad + 1; hit_bad = hit_bad + 1;
        end
        // k_step is the adapter's copy of k_clkena: always equal
        if (dut.cpu.k_step !== dut.cpu.k_clkena) begin
            $display("FAIL k_step %b, k_clkena %b", dut.cpu.k_step, dut.cpu.k_clkena);
            ks_bad = ks_bad + 1; hit_bad = hit_bad + 1;
        end
        // Kernel change 2: the registered clkena_lw must equal what the
        // kernel computed itself, clkena AND (NOT longword OR long_ack), on
        // every clock (kernel outputs read live).
        if (dut.cpu.k_clkena_lw !== (dut.cpu.k_clkena && (!dut.cpu.k_longword || dut.cpu.k_long_ack))) begin
            $display("FAIL k_clkena_lw %b, kernel formula %b", dut.cpu.k_clkena_lw,
                     dut.cpu.k_clkena && (!dut.cpu.k_longword || dut.cpu.k_long_ack));
            ks_bad = ks_bad + 1; hit_bad = hit_bad + 1;
        end
        if (dut.cpu.k_clkena) n_clw = n_clw + dut.cpu.k_clkena_lw;
        if (dut.cpu.k_clkena && ks_cyc - ks_chg < 1) begin
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
    reg [17:0] pb_s; reg [31:1] pb_k;      // {known hi, known lo, data}
    reg [17:0] shadow [int unsigned];
    // step 11: the program asks the tb to rewrite its chip RAM routine
    // behind the CPU, as disk or blitter DMA would (the shadow follows)
    always @(posedge uds_n) if (!rw && ba == 24'h8F10) begin
        ram[12'hC00] = 16'h7803;                  // $9800: moveq #3,%d4
        shadow[31'h4C00] = {2'b11, 16'h7803};
    end
    reg [3:0]  pb_pq = 0; reg pb_mr = 0;
    always @(posedge dut.clk) begin
        pb_pq <= dut.cpu.q;
        pb_mr <= dut.cpu.mr_active;
        if (dut.cpu.mr_active !== pb_mr) shadow.delete();
        // a write cycle has just been set up (cyc_start): a_r, oEdb and the
        // strobes belong to it. (oEdb and the strobes now load on every
        // DECIDE clock, so only a real cycle start may be recorded.)
        if (dut.cpu.cyc_start && !dut.cpu.eRWn) begin
            pb_k = dut.cpu.a_r;
            pb_s = shadow.exists(pb_k) ? shadow[pb_k] : 18'd0;
            if (!dut.cpu.uds_want) begin pb_s[17] = 1'b1; pb_s[15:8] = dut.cpu.oEdb[15:8]; end
            if (!dut.cpu.lds_want) begin pb_s[16] = 1'b1; pb_s[7:0]  = dut.cpu.oEdb[7:0];  end
            shadow[pb_k] = pb_s;
            // a pair write (32-bit SDRAM, step 8) also writes the next word
            if (dut.cpu.k_long_ack) begin
                shadow[pb_k + 31'd1] = {2'b11, dut.cpu.dp_wdata_lo};
                wr_pairs = wr_pairs + 1;
            end
        end
        // A hit is recorded in CCMP and checked on the clock the kernel
        // samples it (k_clkena): data_in (k_dat), and for a pair hit also
        // data_in_hi (k_din_ce) and long_ack. Checked first, then recorded.
        // A pair read from the SDRAM (step 9: k_long_ack on a read that is
        // not a cache hit, k_din_sel low): both words against the shadow.
        if (dut.cpu.k_clkena && dut.cpu.k_long_ack && dut.cpu.eRWn && !dut.cpu.k_din_sel) begin
            rd_pairs = rd_pairs + 1;
            if (dut.cpu.cyc_fetch) ipair_rd = ipair_rd + 1;
            chk_word(dut.cpu.a_r, dut.cpu.k_din_hmux);
            chk_word(dut.cpu.a_r + 31'd1, dut.cpu.k_dat);
        end
        if (hp_pend && dut.cpu.k_clkena) begin
            hp_pend = 0;
            if (hp_f && hp_a >= 31'h4000 && hp_a < 31'h5000) chip_ihit = chip_ihit + 1;   // tb RAM $8000-$9FFF
            if (dut.cpu.k_long_ack !== hp_long) begin
                $display("FAIL cache hit at %h: long_ack %b, expected %b", {hp_a, 1'b0}, dut.cpu.k_long_ack, hp_long);
                hit_bad = hit_bad + 1;
            end
            if (hp_long) begin
                long_hits = long_hits + 1;
                if (hp_f) ipair_hit = ipair_hit + 1;
                // step 9: the re-read at 0x08004F00 (test_top.s) must be a
                // pair hit, i.e. the pair read filled the second word too
                if (hp_a == 31'h04002780) hit_4f00 = hit_4f00 + 1;
                chk_word(hp_a, dut.cpu.k_din_hmux);
                chk_word(hp_a + 31'd1, dut.cpu.k_dat);
            end else
                chk_word(hp_a, dut.cpu.k_dat);
        end
        if (dut.cpu.q == 4'd8 && (dut.cpu.cc_long || dut.cpu.cc_hit)) begin
            hp_pend = 1; hp_long = dut.cpu.cc_long; hp_a = dut.cpu.a_r; hp_f = dut.cpu.cyc_fetch;
        end
    end
    always @(negedge as_n) if (ba[23:19] == 5'b11111) romf = romf + 1;
    reg [2:0] w = 0;
    reg       busy = 0;
    // Random wait states (0-2 7M clocks per cycle), as DMA contention gives
    // a real Gary, so CPU cycles land at every phase of the 7M grid (a fixed
    // DTACK let the step 11 posted-write data-enable race hide). Not in the
    // throughput benches, which need fixed timing.
    reg [2:0] xw = 0;
    integer   jit_seed = 1;
    always @(posedge clk7) begin
        if (as_n) begin
            dtack_n <= 1; vpa_n <= 1; mb_drive <= 0; busy <= 0; w <= 0;
        end else if (!busy) begin
            busy <= 1; cycles = cycles + 1; w <= 0;
`ifndef MEMBENCH
            xw <= $unsigned($random(jit_seed)) % 3;
`endif
            if (fc == 3'b111) begin vpa_n <= 0; iacks = iacks + 1; end
            else if (ba[23:16] == 8'hBF) begin vpa_n <= 0; cia = cia + 1; end
        end else if (vpa_n) begin
            w <= w + 1;
            if (w == 3'd1 + xw) begin
                if (rw) begin
                    if (ba < 24'h2000 || ba[23:19] == 5'b11111) mb_q <= rom[ba[12:1]];
                    else if (ba >= 24'h8000 && ba < 24'hA000)  mb_q <= ram[ba[12:1]];
                    else begin mb_q <= 16'hFFFF; unmapped = unmapped + 1;
                        $display("unmapped read %h fc=%0d", ba, fc); end
                    mb_drive <= 1;
                end
                dtack_n <= 0;
            end
        end
        // CIA data while VMA is low and E high
        if (!as_n && !vpa_n && fc != 3'b111 && rw) begin
            mb_q <= 16'hA5A5; mb_drive <= 1;
        end
    end
    // writes land on the DS rising edge, like Agnus
    // ...and the CPU side must be driving the data bus when they do
    integer undriven = 0;
    localparam integer POST_WB = 8;   // the bridge's CHIP_WB
    always @(posedge uds_n or posedge lds_n)
        if (!rw && dut.bus_owned && !dut.rt_d_oe) begin   // (AS may rise on the same edge)
            undriven = undriven + 1;
            if (undriven <= 5) $display("FAIL: write to %h latched with the data bus not driven", ba);
        end
    always @(posedge uds_n) if (!rw && ba >= 24'h8000 && ba < 24'hA000) ram[ba[12:1]][15:8] = d[15:8];
    always @(posedge lds_n) if (!rw && ba >= 24'h8000 && ba < 24'hA000) ram[ba[12:1]][7:0]  = d[7:0];
    always @(posedge uds_n) if (!rw && ba == 24'h8F80) ipl_n = 3'b111;
`ifdef FASTMEM
    // step 13: the turbomem board as if autoconfigured at $EA0000, so the
    // program can use its speed register (+$F00A) for real
    initial begin
        #100;
        force dut.g_fastmem.u_turbomem.configured = 1'b1;
        force dut.g_fastmem.u_turbomem.base = 8'hEA;
    end
    integer n_switch = 0; reg [1:0] cur_d = 0;
    always @(posedge dut.clk) begin
        // (only arrivals at the selected source: between two PLL clocks the
        // switch has a moment with neither on, which cur shows as 12x)
        if (dut.clk_cur != cur_d && dut.clk_cur == dut.clk_sel) begin
            n_switch = n_switch + 1;
            $display("%0t: system clock now %0s", $time,
                     dut.clk_cur == 2'd2 ? "16x" : dut.clk_cur == 2'd1 ? "14x" : "12x");
        end
        cur_d <= dut.clk_cur;
    end
    // MapROM control, as the turbomem board's $F008 register would set it
    always @(posedge uds_n) if (!rw && ba == 24'h8F40) begin
        if (d[15:8] == 8'd1) force dut.g_fastmem.u_turbomem.mr_ctrl = 2'b01;
        if (d[15:8] == 8'd2) force dut.g_fastmem.u_turbomem.mr_ctrl = 2'b10;
        if (d[15:8] == 8'd3) force dut.g_fastmem.u_turbomem.mr_ctrl = 2'b00;
    end
`endif
    always @(negedge as_n) if (!rw && !(ba >= 24'h8000 && ba < 24'hA000) && ba[23:16] != 8'hBF) begin
        $display("unmapped write %h", ba); unmapped = unmapped + 1; end

`ifdef MEMBENCH
    // time between the start/end markers, and per-phase accounting of
    // fast RAM cycles: AS(core) low -> DTACK(core) -> AS high -> next AS
    real t0 = 0, t1 = 0;
    always @(posedge uds_n) if (!rw && ba == 24'h8F00) begin
        if (d[15:8] == 8'd1) t0 = $realtime; else t1 = $realtime;
    end
    integer n_fm = 0; real t_as = 0, sum_as2dt = 0, sum_dt2up = 0, sum_up2as = 0, t_dt = 0, t_up = 0;
    always @(negedge dut.core_as_n) if (t0 > 0 && t1 == 0) begin
        if (t_up > 0) sum_up2as = sum_up2as + ($realtime - t_up);
        t_as = $realtime;
    end
    integer n_rd = 0, n_wr = 0; real s_rd = 0, s_wr = 0;
    integer n_step = 0, n_int = 0, n_hit = 0, n_dir = 0, n_bus = 0, n_clk = 0;
    // stalls (step 12): a fast RAM write waiting in DECIDE for the SDRAM
    // port, a read waiting in CFREE, a Chip RAM write waiting behind a
    // posted one
    integer st_fw = 0, st_fr = 0, st_cw = 0;
    always @(posedge clk12) if (t0 > 0 && t1 == 0) begin
        if (dut.cpu.q == 1 && !dut.cpu.internal_step && !dut.cpu.k_pf_ok && dut.cpu.dp_busy
            && dut.cpu.k_fast && !dut.cpu.k_nwr) st_fw = st_fw + 1;
        if (dut.cpu.q == 11) st_fr = st_fr + 1;
        if (!dut.core_as_n && !dut.core_rw && dut.core_a[23:21] == 3'd0 && !dut.cpu.k_fast
            && !dut.int_win_r && dut.wb_full) st_cw = st_cw + 1;
    end
    always @(posedge clk12) if (t0 > 0 && t1 == 0) begin
        n_clk = n_clk + 1;
        if (dut.cpu.k_clkena) n_step = n_step + 1;
        if (dut.cpu.q == 1 && dut.cpu.internal_step && dut.cpu.cnt >= 3) n_int = n_int + 1;
        if (dut.cpu.q == 8 && dut.cpu.cc_hit) n_hit = n_hit + 1;
        if (dut.cpu.q == 9 && dut.cpu.dp_ack) n_dir = n_dir + 1;
        if (dut.cpu.q == 4 && (!dut.core_dtack_n)) n_bus = n_bus + 1;
    end
    // step 15: what each kernel step was and how long it took (gap = clocks
    // from the previous step). The kernel's outputs still show the cycle
    // being ended in the clock k_clkena is high.
    integer gap = 0, sk_f = 0, sk_f5 = 0, sk_f5seq = 0, sk_f4 = 0, sk_fpair = 0, sk_w = 0, sk_w5 = 0, sk_w4 = 0, sk_wpair = 0,
            sk_r = 0, sk_r5 = 0, sk_rpair = 0, sk_i = 0, sk_i4 = 0;
    reg [31:1] f_next = 0;
    wire sk_fetch = (dut.cpu.k_bs == 2'b00) && !dut.cpu.k_skip;
    always @(posedge clk12) begin
        gap <= dut.cpu.k_clkena ? 1 : gap + 1;
        if (dut.cpu.k_clkena && sk_fetch)
            f_next <= dut.cpu.k_addr[31:1] + (dut.cpu.k_long_ack ? 31'd2 : 31'd1);
        if (dut.cpu.k_clkena && t0 > 0 && t1 == 0) begin
            if (sk_fetch) begin
                sk_f = sk_f + 1;
                if (dut.cpu.k_long_ack) sk_fpair = sk_fpair + 1;
                else if (gap == 5) begin
                    sk_f5 = sk_f5 + 1;
                    if (dut.cpu.k_addr[31:1] == f_next) sk_f5seq = sk_f5seq + 1;
                end else if (gap == 4) sk_f4 = sk_f4 + 1;
            end else if (dut.cpu.k_bs == 2'b11) begin
                sk_w = sk_w + 1;
                if (dut.cpu.k_long_ack) sk_wpair = sk_wpair + 1;
                else if (gap == 5) sk_w5 = sk_w5 + 1;
                else if (gap == 4) sk_w4 = sk_w4 + 1;
            end else if (dut.cpu.k_bs == 2'b10) begin
                sk_r = sk_r + 1;
                if (dut.cpu.k_long_ack) sk_rpair = sk_rpair + 1;
                else if (gap == 5) sk_r5 = sk_r5 + 1;
            end else begin
                sk_i = sk_i + 1;
                if (gap == 4) sk_i4 = sk_i4 + 1;
            end
        end
    end
    always @(negedge dut.core_dtack_n) if (t0 > 0 && t1 == 0) begin t_dt = $realtime; sum_as2dt = sum_as2dt + (t_dt - t_as); n_fm = n_fm + 1;
        if (dut.core_a[31:24] == 8'h08) begin
        if (dut.core_rw) begin n_rd = n_rd + 1; s_rd = s_rd + (t_dt - t_as); end else begin n_wr = n_wr + 1; s_wr = s_wr + (t_dt - t_as); end end end
    always @(posedge dut.core_as_n) if (t0 > 0 && t1 == 0 && t_dt > 0) begin t_up = $realtime; sum_dt2up = sum_dt2up + (t_up - t_dt); end
`endif
    function [31:0] rd32(input [23:0] ad);
        rd32 = {ram[ad[12:1]], ram[ad[12:1]+1]};
    endfunction
    // the same, comparing only the bits set in mask
    task checkm(input [23:0] ad, input [31:0] exp, input [31:0] mask, input [8*24-1:0] what);
        if ((rd32(ad) & mask) !== (exp & mask)) begin
            $display("FAIL %-24s @%h = %h, expected %h (mask %h)", what, ad, rd32(ad), exp, mask);
            errors = errors + 1;
        end else $display("ok   %-24s @%h = %h", what, ad, rd32(ad));
    endtask
    task check(input [23:0] ad, input [31:0] exp, input [8*24-1:0] what);
        if (rd32(ad) !== exp) begin
            $display("FAIL %-24s @%h = %h, expected %h", what, ad, rd32(ad), exp);
            errors = errors + 1;
        end else $display("ok   %-24s @%h = %h", what, ad, rd32(ad));
    endtask

`ifdef SDTEST
    // the SD board as if autoconfigured at $E90000
    initial begin
        #100;
        force dut.g_sd.u_sd_autoconfig.configured = 1'b1;
        force dut.g_sd.u_sd_autoconfig.base_sd = 8'hE9;
    end
`endif
    reg irq_raised = 0;
    initial begin
        // The core leaves reset after the power-up hold + cold pulse; the
        // interrupt is raised once the test is waiting for it.
        wait (led_b);
        $display("%0t core out of reset", $time);
        for (i = 0; i < 2000000 && rd32(24'h8FF0) != 32'h600DC0DE; i = i + 1) begin
            @(posedge clk12);
`ifdef FASTMEM
            if (rd32(24'h812C) == 32'h0000BEEF && !irq_raised) begin
`else
            if (rd32(24'h811C) == 32'hFFFFFFFF && !irq_raised) begin
`endif
                ipl_n = 3'b100; irq_raised = 1;
            end
        end
`ifdef MEMBENCH
        $display("kernel steps %0d: internal %0d, cache hits %0d, direct %0d, bus %0d; clocks %0d",
                 n_step, n_int, n_hit, n_dir, n_bus, n_clk);
        $display("cache hits checked against the CPU's writes (whole run) %0d, stale %0d; pair hits %0d; pair writes %0d; pair reads %0d; SDRAM violations %0d; clkena_lw steps %0d", hit_chk, hit_bad, long_hits, wr_pairs, rd_pairs, u_sdram.n_err, n_clw);
        if (u_sdram.n_err) errors = errors + 1;
        if (hit_bad) errors = errors + 1;
        $display("steps by kind: fetch %0d (pairs %0d, single in 4 clocks %0d, in 5 clocks %0d of which sequential %0d); write %0d (pairs %0d, single in 4 %0d, in 5 %0d); read %0d (pairs %0d, single in 5 %0d); internal %0d (in 4 clocks %0d)",
                 sk_f, sk_fpair, sk_f4, sk_f5, sk_f5seq, sk_w, sk_wpair, sk_w4, sk_w5, sk_r, sk_rpair, sk_r5, sk_i, sk_i4);
        $display("1 KB: %0.1f us -> %0.2f MB/s; %0d CPU bus cycles", (t1-t0)/1000.0, 1024.0/((t1-t0)/1000.0), n_fm);
        $display("stall clocks: fast write waits for the port %0d, read waits (CFREE) %0d, chip write waits %0d", st_fw, st_fr, st_cw);
        $display("per cycle, in 11.75 ns clocks: AS->DTACK %0.1f, DTACK->AS up %0.1f, AS up->next AS %0.1f",
                 sum_as2dt/n_fm/11.746, sum_dt2up/n_fm/11.746, sum_up2as/n_fm/11.746);
        $display("AS->DTACK reads %0d avg %0.1f clk, writes %0d avg %0.1f clk", n_rd, s_rd/n_rd/11.746, n_wr, s_wr/n_wr/11.746);
`ifdef SDTEST
        check(24'h8100, 32'h00000055, "SD clkdiv 55");
        check(24'h8104, 32'h000000AA, "SD clkdiv AA");
        check(24'h8108, 32'h00000001, "SD slave sel 1");
        check(24'h810C, 32'h00000000, "SD slave sel 0");
        check(24'h8110, 32'h000000AA, "SD clkdiv again");
        check(24'h8114, 32'h00000000, "SPI loopback mismatches");
        check(24'h8118, 32'h00000102, "SPI loopback first word");
        check(24'h811C, 32'h000000F1, "SPI loopback bytes");
`elsif BENCH_C
        check(24'h8100, 32'h05364511, "C workload checksum, pass 1");
        check(24'h8104, 32'h61FEF797, "C workload checksum, pass 2");
`elsif BENCH_COPY
        check(24'h8100, 32'h000000FF, "first copied long");
        check(24'h8104, 32'h00000000, "last copied long");
        check(24'h8108, 32'h00000000, "copy mismatches");
`elsif BENCH_CHIP
        check(24'h8100, 32'h000002FD, "last chip long written");
`elsif BENCH_WRCHIP
        check(24'h8100, 32'h000000FF, "last chip long written");
`elsif BENCH_WRFAST
        check(24'h8100, 32'h000000FF, "last fast long written");
`else
        check(24'h8100, 32'h00007F80, "sum");
`endif
        check(24'h8FF0, 32'h600DC0DE, "done marker");
        if (dut.cpu.fp_chk_bad) begin $display("FAIL: %0d predicted fetches differed from the cache's own lookup", dut.cpu.fp_chk_bad); errors = errors + 1; end
        $display("predicted fetches %0d (checked at the kernel's sample clock: %0d)", dut.cpu.fp_hits, fp_chk);
        if (dut.cpu.cc_bad) begin $display("FAIL: %0d CCMP compares used registered inputs that differ from a_r", dut.cpu.cc_bad); errors = errors + 1; end
        if (errors) $display("FAILED"); else $display("PASS");
        $finish;
`else
        $display("%0t: MB cycles %0d, IACK %0d, CIA %0d, unmapped %0d, ROM-range cycles %0d", $time, cycles, iacks, cia, unmapped, romf);
        check(24'h8100, 32'h369D0368, "MULU.L");
        check(24'h8104, 32'h00022E09, "DIVU.L");
        check(24'h8108, 32'h0000000F, "BFEXTU");
        check(24'h810C, 32'h369D5ACD, "byte lanes / MOVE.W");
        check(24'h8110, 32'hA1B2C3D4, "misaligned MOVE.L");
        check(24'h8114, 32'h00007777, "TRAP/RTE");
        check(24'h8118, 32'h000000A5, "CIA (VPA/E) read");
        check(24'h811C, 32'hFFFFFFFF, "32-bit null space");
        check(24'h81B4, 32'h00000001, "chip code: from cache");
        check(24'h81B8, 32'h00000002, "chip code: CPU write");
        check(24'h81BC, 32'h00000003, "chip code: CACR CI");
        $display("instruction-cache hits on chip RAM code: %0d", chip_ihit);
        if (chip_ihit < 2) begin $display("FAIL: chip RAM code never came from the cache"); errors = errors + 1; end
        check(24'h81C0, 32'h12341256, "posted writes, order");
        check(24'h81C4, 32'h00000468, "posted writes, all phases");
        check(24'h81CC, 32'h33334444, "write buffer: read after buffered writes");
        check(24'h81D0, 32'h00000024, "write buffer: a burst longer than the buffer");
        $display("posted chip writes: %0d", n_posted);
        if (n_posted < 10) begin $display("FAIL: chip RAM writes were not posted"); errors = errors + 1; end
        $display("write buffer: at most %0d entries; CIA order checks %0d", wb_max, ord_chk);
        if (POST_WB > 1 && wb_max < 2) begin $display("FAIL: the write buffer never held two writes"); errors = errors + 1; end
        if (ord_chk < 1) begin $display("FAIL: the write-order test did not run"); errors = errors + 1; end
        errors = errors + ord_bad;
        if (undriven > 0) begin $display("FAIL: %0d writes latched with the data bus not driven", undriven); errors = errors + 1; end
`ifdef FASTMEM
        check(24'h81C8, 32'h0000005F, "posted writes after fast RAM reads");
`ifdef TG68_X16
        // board-mod build: fixed 16x, the register reads $0010, writes do nothing
        check(24'h81D4, 32'h00000010, "speed: fixed 16x (board mod)");
        check(24'h81D8, 32'h00000010, "speed: write ignored (16)");
        check(24'h81DC, 32'hACF1E135, "speed: memory traffic");
        check(24'h81E0, 32'h00000010, "speed: write ignored (14)");
        check(24'h81E4, 32'hACF1E135, "speed: memory traffic");
        check(24'h81E8, 32'h00000010, "speed: write ignored (12)");
        check(24'h81EC, 32'hACF1E135, "speed: memory traffic");
        check(24'h81F0, 32'h00000010, "speed: unkeyed / invalid writes ignored");
        check(24'h81F4, 32'h00000010, "speed: write ignored (12, rising)");
        check(24'h81F8, 32'h00000010, "speed: write ignored (invalid select)");
        check(24'h81FC, 32'hACF1E135, "speed: memory traffic");
        $display("clock switches: %0d; SDRAM mode loads: %0d", n_switch, u_sdram.n_mrs);
        if (n_switch != 0) begin $display("FAIL: the clock switched in the fixed 16x build"); errors = errors + 1; end
        if (u_sdram.n_mrs != 1) begin $display("FAIL: expected 1 SDRAM mode load"); errors = errors + 1; end
`else
`ifdef CAL_DRIFT
        // step 14: rising chosen at power-up (12x, both clean), then the
        // clock drifts onto it at 300 us: the top level must swap to the
        // falling stream by itself (n_swap). Later calibrations at every
        // speed find the rising one moving and keep the falling one. Bit 15
        // (aligner slip) is not compared: the forced-rising test at 81F4
        // runs on the drifting stream on purpose.
        $display("automatic 7M stream swaps: %0d", dut.n_swap);
        if (dut.n_swap < 1) begin $display("FAIL: the drifting 7M stream was never swapped out"); errors = errors + 1; end
        checkm(24'h81D4, 32'h0000470C, 32'h00007FFF, "speed: 12x after the drift");
        checkm(24'h81D8, 32'h00004710, 32'h00007FFF, "speed: 16x, falling stream");
        checkm(24'h81E0, 32'h00004714, 32'h00007FFF, "speed: 20x, falling stream");   // exp-20x
        checkm(24'h81E8, 32'h0000470C, 32'h00007FFF, "speed: back to 12x, falling");
        checkm(24'h81F0, 32'h0000470C, 32'h00007FFF, "speed: unkeyed / invalid ignored");
        checkm(24'h81F4, 32'h0000570C, 32'h00007FFF, "speed: 12x, rising forced");
        checkm(24'h81F8, 32'h0000570C, 32'h00007FFF, "speed: invalid select ignored");
        if (dut.smp_r !== 1'b0) begin $display("FAIL: the drifting stream is still in use"); errors = errors + 1; end
`elsif CAL_TEST
        // at 12x the falling sample sits in the 7M jitter: the power-up
        // calibration and each one at 12x must pick the rising stream (bit
        // 12) and report the falling one moving (bit 13); at 14x and 16x
        // both are clean and the falling stream stays
        check(24'h81D4, 32'h0000370C, "speed: 12x at power-on, rising 7M stream");
        check(24'h81D8, 32'h00000710, "speed: 16x, falling stream");
        check(24'h81E0, 32'h00000714, "speed: 20x, falling stream");   // exp-20x
        check(24'h81E8, 32'h0000370C, "speed: back to 12x, rising stream");
        check(24'h81F0, 32'h0000370C, "speed: unkeyed / invalid writes ignored");
        check(24'h81F4, 32'h0000370C, "speed: 12x, rising forced");
        check(24'h81F8, 32'h0000370C, "speed: invalid sample select ignored");
        if (dut.smp_r !== 1'b1) begin $display("FAIL: the calibration left the jittery stream in use"); errors = errors + 1; end
        if (dut.n_swap != 0) begin $display("FAIL: %0d 7M stream swaps (the stream in use is clean)", dut.n_swap); errors = errors + 1; end
`else
        // step 14: at 12x the rising stream unless it moved more (both are
        // clean here); at 14x and 16x the falling one; no swap ever
        check(24'h81D4, 32'h0000170C, "speed: 12x at power-on, rising");
        check(24'h81D8, 32'h00000710, "speed: 16x");
        check(24'h81E0, 32'h00000714, "speed: 20x");   // exp-20x
        check(24'h81E8, 32'h0000170C, "speed: back to 12x, rising");
        check(24'h81F0, 32'h0000170C, "speed: unkeyed / invalid writes ignored");
        check(24'h81F4, 32'h0000170C, "speed: 12x, rising 7M stream forced");
        check(24'h81F8, 32'h0000170C, "speed: invalid sample select ignored");
        if (dut.smp_r !== 1'b1) begin $display("FAIL: the calibration left the rising stream at 12x"); errors = errors + 1; end
        if (dut.n_swap != 0) begin $display("FAIL: %0d 7M stream swaps with nothing drifting", dut.n_swap); errors = errors + 1; end
`endif
        check(24'h81DC, 32'hACF1E135, "speed: memory traffic at 16x");
        check(24'h81E4, 32'hACF1E135, "speed: memory traffic at 20x");
        check(24'h81EC, 32'hACF1E135, "speed: memory traffic at 12x");
        check(24'h81FC, 32'hACF1E135, "speed: memory traffic after a recalibration");
        // step 15: code that overwrites the instruction 0, 1 or 2 words
        // after the store (test_top.s smc0-2). The storing run's result
        // is what the kernel's own prefetch gives (the same with the
        // predictor off, VLFLAGS=-DS15_DEFAULT=0); the run after it must
        // see the new instruction.
        check(24'h8210, 32'h00000005, "smc +0: the storing run");
        check(24'h8214, 32'h00000002, "smc +0: the run after");
        check(24'h8218, 32'h00000002, "smc +1: the storing run");
        check(24'h821C, 32'h00000002, "smc +1: the run after");
        check(24'h8220, 32'h00000002, "smc +2: the storing run");
        check(24'h8224, 32'h00000002, "smc +2: the run after");
        check(24'h8228, 32'h00000002, "smc pair: the storing run");
        check(24'h822C, 32'h00000002, "smc pair: the run after");
        if (dut.ph_slip) begin $display("FAIL: the 7M aligner slipped"); errors = errors + 1; end
        if (!dut.ph_locked) begin $display("FAIL: the 7M aligner is not locked"); errors = errors + 1; end
        $display("clock switches: %0d; SDRAM mode loads: %0d", n_switch, u_sdram.n_mrs);
        if (n_switch != 3) begin $display("FAIL: expected 3 clock switches"); errors = errors + 1; end
        // exp-18x: 12x -> 16x loads CL3, 16x -> 18x keeps it, 18x -> 12x loads
        // CL2: still 3 (step 13: 16x -> 14x loaded CL2, 14x -> 12x none)
        if (u_sdram.n_mrs != 3) begin $display("FAIL: expected 3 SDRAM mode loads (init, CL3, CL2)"); errors = errors + 1; end
`endif
        check(24'h8120, 32'h13579BDF, "fast RAM $08000000");
        check(24'h8124, 32'h2468ACE0, "fast RAM $08FFFFFC");
        check(24'h8128, 32'h0000FA57, "code run from fast RAM");
        check(24'h812C, 32'h0000BEEF, "patched code (cache)");
        check(24'h8150, 32'h11112222, "long via prefetch");
        check(24'h8154, 32'h00003333, "prefetch vs write");
        check(24'h8158, 32'h00006644, "prefetch vs byte write");
        check(24'h815C, 32'h00008E90, "sequential word reads");
        check(24'h8160, 32'hCAFEBABE, "MapROM shadow read");
        check(24'h8164, 32'h00000000, "MapROM off: real ROM");
        check(24'h8168, 32'h0BADF00D, "dcache: long hit");
        check(24'h816C, 32'h0000005A, "dcache: byte write");
        check(24'h8170, 32'h00005678, "dcache: word write");
        check(24'h8174, 32'h110F4444, "dcache: same index");
        check(24'h8178, 32'h00002222, "dcache: write while off");
        check(24'h817C, 32'h02040608, "dcache: ROM data");
        check(24'h8180, 32'h00002F40, "dcache: two-pass sum");
        check(24'h8184, 32'h00007777, "cache: word write");
        check(24'h8188, 32'h0000BBCC, "cache: byte write");
        check(24'h818C, 32'h00001515, "cache: write, caches off");
        check(24'h8190, 32'h00000000, "cache: MapROM flush");
        check(24'h8194, 32'h8AACCEF0, "pair: imm32 + abs.L");
        check(24'h8198, 32'h31323399, "pair: partner not cached");
        check(24'h819C, 32'h51525354, "pair write, from SDRAM");
        check(24'h81A0, 32'h61626364, "misaligned long write");
        check(24'h81A4, 32'h81828384, "pair write over cache");
        check(24'h81A8, 32'h91929394, "pair read, miss");
        check(24'h81AC, 32'h91929394, "pair read, then hit");
        check(24'h81B0, 32'h91929394, "pair read, caches off");
        $display("pair reads from the SDRAM: %0d; instruction-stream pairs: %0d from the cache, %0d from the SDRAM", rd_pairs, ipair_hit, ipair_rd);
        if (rd_pairs < 4) begin $display("FAIL: pair reads (32-bit SDRAM) barely used"); errors = errors + 1; end
        if (hit_4f00 < 1) begin $display("FAIL: a pair read did not fill both words of the data cache"); errors = errors + 1; end
        $display("pair writes: %0d; SDRAM model timing violations: %0d", wr_pairs, u_sdram.n_err);
        if (wr_pairs < 4) begin $display("FAIL: pair writes (32-bit SDRAM) barely used"); errors = errors + 1; end
        if (u_sdram.n_err) begin $display("FAIL: SDRAM model timing violations"); errors = errors + 1; end
        if (dut.g_sdram.u_sdram.pre_bad) begin $display("FAIL: %0d SDRAM requests used a stale open-row decision", dut.g_sdram.u_sdram.pre_bad); errors = errors + 1; end
        $display("data cache hits: %0d; hits checked against the CPU's writes %0d (stale: %0d); pair hits %0d; shortest direct request->ack %0d clocks",
                 dc_hits, hit_chk, hit_bad, long_hits, dp_min);
        if (long_hits < 4) begin $display("FAIL: pair hits (32-bit data path) barely used"); errors = errors + 1; end
        if (hit_bad) errors = errors + 1;
        if (hit_chk < 64) begin $display("FAIL: cache-hit oracle barely used"); errors = errors + 1; end
        // tg68_bus's speculative read relies on no answer before CCMP
        if (dp_min < 3) begin $display("FAIL: SDRAM answered in %0d clocks", dp_min); errors = errors + 1; end
        if (dc_hits < 64) begin $display("FAIL: data cache barely used"); errors = errors + 1; end
        check(24'h8130, 32'h33333333, "IRQ3 via VPA autovec");
`else
        check(24'h8120, 32'h33333333, "IRQ3 via VPA autovec");
        $display("cache hits checked against the CPU's writes %0d (stale: %0d); pair hits %0d", hit_chk, hit_bad, long_hits);
        if (hit_bad) errors = errors + 1;
`endif
        check(24'h8140, 32'h00000055, "ROM code via cache");
        check(24'h8FF0, 32'h600DC0DE, "done marker");
        if (iacks != 1) begin $display("FAIL IACK count %0d", iacks); errors = errors + 1; end
        if (unmapped)   begin $display("FAIL %0d unmapped accesses reached the MB", unmapped); errors = errors + 1; end
        if (led_r)      begin $display("FAIL red LED (stall)"); errors = errors + 1; end
        if (dut.cpu.fp_chk_bad) begin $display("FAIL: %0d predicted fetches differed from the cache's own lookup", dut.cpu.fp_chk_bad); errors = errors + 1; end
        $display("predicted fetches %0d (checked at the kernel's sample clock: %0d)", dut.cpu.fp_hits, fp_chk);
        if (dut.cpu.cc_bad) begin $display("FAIL: %0d CCMP compares used registered inputs that differ from a_r", dut.cpu.cc_bad); errors = errors + 1; end
        if (errors) $display("FAILED, %0d errors", errors); else $display("PASS");
        $finish;
`endif
    end
    initial begin #40ms; $display("TIMEOUT"); $finish; end
endmodule

// Behavioural stand-in for the ECP5 output DDR primitive.
module ODDRX1F (input D0, D1, SCLK, RST, output Q);
    assign Q = SCLK ? D0 : D1;
endmodule
