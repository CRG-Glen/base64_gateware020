// ============================================================================
// tg68_bus.v -- TG68K.C kernel (68020 mode) behind an fx68k-shaped port list
//
// base64_top was written around fx68k, which looks to the rest of the design
// like a real 68000: AS/UDS/LDS/RW out, DTACK/BERR in, address held for the
// whole cycle. Everything downstream -- the RETIME bridge to the motherboard,
// fast RAM, the turbomem ROM board, the SD card -- is an ordinary
// asynchronous 68000 slave. This module makes TG68K look the same, so none
// of that has to change.
//
// TG68K is not a bus master. It is a state machine that advances one step
// per clkena pulse and tells you, via busstate, what it wants next:
//   00 fetch, 10 read, 11 write  -> run a bus cycle, then pulse clkena with
//                                   the read data on data_in
//   01 internal                  -> just pulse clkena
// (busstate 00 with skipFetch=1 is also internal, as in TG68K.vhd.)
//
// TIMING MODEL -- READ THIS BEFORE CHANGING THE PARAMETERS
// Every register inside the kernel is gated by clkena (checked: Kernel and
// ALU, all processes). So kernel-internal paths have STEP master clocks to
// settle, not one. The adapter keeps that true at the interface as well:
//   * kernel OUTPUTS are only looked at SETTLE clocks after a clkena
//   * kernel INPUTS (data_in, IPL, berr, nReset) only change on a clkena
//     edge or at least DIN_SETUP clocks before the next one
// so no path through the kernel is single-cycle. nextpnr cannot express
// that (no multicycle constraints) and will report the kernel as failing
// 85 MHz; that report is expected. What has to be true is that each class
// of kernel path fits its budget -- scripts/check_timing.py checks this on
// the routed design: internal paths < STEP, outputs < SETTLE, inputs <
// DIN_SETUP clocks. Routed they are ~42, ~32 and ~14 ns.
//
// The adapter itself, the bridge and the slaves are normal single-cycle
// logic and must meet 85 MHz for real.
//
// BUS SHAPE (master clocks of ~11.75 ns)
//   address/FC/RW/data out ..ADDR_SETUP.. AS low (+DS for reads)
//   writes: DS follows AS by WDS_DELAY (a 68000 asserts write DS at S4)
//   DTACK or BERR seen ..DATA_DELAY.. latch read data, AS/DS high
//   address/RW/data held until the next cycle is set up (>= SETTLE clocks)
// AS-high time between cycles is always >= DIN_SETUP+SETTLE+ADDR_SETUP.
// ============================================================================
`default_nettype none
// step 15 switches' default (sim: VLFLAGS=-DS15_DEFAULT=0 runs the adapter as
// it was in step 14, for reference results)
`ifndef S15_DEFAULT
`define S15_DEFAULT 1
`endif

module tg68_bus #(
    parameter integer STEP       = 4,  // min clocks between clkena pulses
    parameter integer SETTLE     = 3,  // clocks after clkena before sampling
    parameter integer DIN_SETUP  = 1,  // read data -> clkena. The kernel
                                       // samples on the clock AFTER clkena is
                                       // set, so data_in gets DIN_SETUP+1.
    parameter integer ADDR_SETUP = 1,  // address valid -> AS; the port AS is a
                                       // further clock later (strobe pipeline),
                                       // so slaves see ADDR_SETUP+1 = 2, which
                                       // is what their registered decodes need
                                       // and what fx68k at 6x gives them.
    parameter integer WDS_DELAY  = 2,  // AS -> DS on writes
    parameter integer DATA_DELAY = 2,  // DTACK -> data latch / AS negate
    parameter integer ICACHE     = 1,  // instruction cache, see ICACHE below
    parameter integer DIRECT     = 1,  // direct SDRAM path, see DIRECT below
    parameter integer DCACHE     = 1,  // data cache, see DCACHE below
    parameter integer DP32_ACK   = 1,  // answer aligned word pairs from the caches
                                       // (32-BIT DATA PATH; 0 = 16-bit only)
    parameter integer DP32_WR    = 1,  // post aligned longword writes to fast RAM
                                       // as one pair (32-BIT SDRAM, step 8)
    parameter integer DP32_RD    = 1,  // read aligned longwords from fast RAM as
                                       // one pair on a cache miss (step 9)
    parameter integer IC_AW      = 12, // log2(cache words): 12 = 4096 = 8 KB
    // Step 11 switches (1 = on; 0 = as step 10), for bisecting on hardware:
    parameter integer CHIP_IC    = 1,  // instruction cache holds chip RAM code
    parameter integer CACR_CLR   = 1,  // CACR CI/CEI flush both caches
    parameter integer RD11       = 1,  // pair prefetch + one-clock-shorter direct read
    // Step 15 switches (1 = on; 0 = as step 14):
    parameter integer FPRED      = `S15_DEFAULT,  // FETCH PREDICTOR: a sequential fetch hit in 4 clocks
    parameter integer WR4        = `S15_DEFAULT,  // a posted word/byte write steps at DECIDE (4 clocks)
    parameter integer BARREL     = 0   // documentation only: which netlist
)(
    input  wire        clk,
    input  wire        enPhi1,     // unused, kept for drop-in compatibility
    input  wire        enPhi2,     // unused
    input  wire        HALTn,      // external HALT: holds off new cycles
    input  wire        extReset,   // core reset (RESET+HALT, power-up)
    // TG68 step 13: cyc_idle = no cycle in progress and the SDRAM port
    // free, for the speed switch (which holds the CPU through HALTn)
    output wire        cyc_idle,
    input  wire        pwrUp,      // unused, extReset already covers it
    output reg         oRESETn,    // RESET instruction
    output wire        oHALTEDn,   // TG68 has no double-fault halt: always 1
    output wire        E,          // unused by base64_top
    input  wire        VPAn,       // unused: the bridge owns 6800 cycles
    output wire        VMAn,
    output reg         ASn,       // see "STROBE PIPELINE" below
    output reg         eRWn,
    output reg         LDSn,
    output reg         UDSn,
    output wire        FC2, FC1, FC0,
    input  wire        DTACKn,
    input  wire        BERRn,
    input  wire        BRn,
    output reg         BGn,
    input  wire        BGACKn,
    input  wire        IPL2n, IPL1n, IPL0n,
    input  wire [15:0] iEdb,
    input  wire        icache_win, // registered: eab is in on-board fast RAM
    input  wire        icache_win_k, // the same, decoded from eab_early (the
                                   // kernel's address) without a register. The
                                   // adapter decodes the board's own windows
                                   // itself (k_z2/k_cpuw/k_rom), so the top
                                   // level ties this to 0; test benches with
                                   // another memory map drive it (EARLY LOOKUP)
    // direct SDRAM path (to fastmem_zii's dp_* port)
    input  wire        fm_on,      // fast RAM block is built and configured
    input  wire [7:0]  fm_match,   //   ... and owns these Zorro II slots
    input  wire        cpu_win_en, // the $08000000 window exists
    input  wire        mr_load,    // MapROM: writes to the ROM banks -> SDRAM
    input  wire        mr_active,  // MapROM: reads from the ROM banks <- SDRAM
    output reg         dp_req,
    output reg         dp_inc,     // a prefetch of the next word is about to
                                   // be requested (see DIRECT)
    output wire [31:1] eab_early,  // the kernel's address, final at DECIDE
    output wire        dp_hold,    // a direct request is outstanding
    output reg         dp_we,
    output reg  [15:0] dp_wdata,
    output reg  [1:0]  dp_be,
    output reg         dp_pair,    // 32-BIT SDRAM: this posted write is an aligned
                                   // pair, dp_wdata to the word, dp_wdata_lo to +2
    output reg  [15:0] dp_wdata_lo,
    input  wire        dp_ack,
    input  wire [15:0] dp_rdata,
    output reg  [15:0] oEdb,
    output wire [31:1] eab,
    // diagnostics
    output reg         stalled     // a bus cycle has waited ~100 ms for DTACK
);

    assign oHALTEDn = 1'b1;
    assign E        = 1'b0;
    assign VMAn     = 1'b1;

    // ------------------------------------------------------------------
    // Kernel
    // ------------------------------------------------------------------
    reg         k_clkena = 1'b0;
    // k_step: a copy of k_clkena for the adapter's own uses (the clears at
    // the end of a step, nReset), so k_clkena drives only the kernel and
    // can sit among its ~90 loads (clkena -> kernel is 1T and mostly
    // routing). keep: yosys would merge the two identical registers.
    (* keep *) reg k_step = 1'b0;
    // The kernel's long-word clock enable, clkena AND (NOT longword OR
    // long_ack), set on the same edge as k_clkena from settled inputs:
    // longword is a kernel output, final SETTLE clocks after a step, and
    // k_long_ack never changes on a step edge (tb-asserted). As a register it
    // takes a LUT and a high-fanout hop off every clkena -> kernel path
    // (kernel change 2, see TG68KdotC_Kernel.vhd).
    reg         k_clkena_lw = 1'b0;
    // kernel change 4 (step 12): a copy for the ALU and the kernel's
    // data-in and address registers, so each drives about half of the
    // loads. Step 14: stored INVERTED, with power-on value 1. As a plain
    // copy, (* keep *) or not, yosys merged it into k_clkena_lw: every
    // build had one register for all ~1150 loads (seen in the routed
    // design, where k_clkena_lw2 did not exist). A flop with a different
    // power-on value is not merged; inverted, it still means "off" at
    // power-on, and the inversion is free (LUT inputs, CE polarity).
    (* keep *) reg k_clkena_lw2_n = 1'b1;
    wire        k_clkena_lw2 = !k_clkena_lw2_n;   // (for the test benches)
    // kernel change 5: k_clkena_lw2_n goes to the kernel's low-active port
    // (the inversion folds into the loads there; inverted out here it cost
    // a LUT in front of every load), and a third copy, k_clkena_lw3, takes
    // the kernel's EA_data/data_write process off k_clkena_lw. It powers on
    // at 1 so yosys cannot merge it with k_clkena_lw (same function, a
    // different power-on value); that first clock is harmless, see the
    // kernel.
    (* keep *) reg k_clkena_lw3 = 1'b1;
    wire        k_longword;
    reg         k_nreset = 1'b0;
    reg  [15:0] k_din    = 16'hFFFF;
    // EARLY LOOKUP (step 6): a cache hit's word goes to the kernel from its
    // own register, k_din_ce/co, loaded in DECIDE from the RAM output through a
    // 2-way mux only; k_din_sel picks it. Loading the RAM output into k_din
    // itself put it through k_din's wide input mux (-2 ns on every seed).
    // Both feed the kernel as k_din does (adapter -> kernel budget), and both
    // are stable from the DECIDE edge, two clocks before the kernel samples.
    // (step 7: one register per cache bank, k_din_ce/k_din_co; the word the
    // cycle asked for is chosen after them by address bit 1.)
    reg  [15:0] k_din_ce = 16'hFFFF, k_din_co = 16'hFFFF;
    reg         k_din_sel = 1'b0;
    // 32-BIT SDRAM READS (step 9): a pair read from the SDRAM hands the
    // kernel its first word from k_din (loaded in DDATA, as for any direct
    // read) on data_in_hi and its second from k_din_lo (its own register,
    // loaded in DDATA2, so k_din gains no load enable) on data_in; k_din_hsel
    // switches both muxes. Adapter -> kernel registers like k_din: set in
    // DDATA2, two clocks before the kernel samples (tb-asserted), the select
    // cleared after.
    reg  [15:0] k_din_lo = 16'hFFFF;
    reg         k_din_hsel = 1'b0;
    // DIRECT READ, ONE CLOCK SHORTER (step 11): a direct read's word goes to
    // the kernel from k_din_dw, loaded with dp_q at the controller's ack
    // (DWAIT), so the kernel steps at the end of DDATA instead of FINISH.
    // An adapter -> kernel register like k_din: set two clocks before the
    // kernel samples; k_din_dsel picks it and is cleared after the step.
    reg  [15:0] k_din_dw = 16'hFFFF;
    reg         k_din_dsel = 1'b0;
    // FETCH PREDICTOR (step 15, see below): the predicted word, in its own
    // adapter -> kernel register like k_din_ce; k_din_psel picks it. Both
    // are loaded two clocks after a kernel step, so they are stable for 3
    // clocks before the earliest next step; the select is dropped at DECIDE
    // by every cycle that hands the kernel k_din (>= 2 clocks before its
    // step). The selects above it in k_dat's mux take priority.
    reg  [15:0] k_din_fp = 16'hFFFF;
    reg         k_din_psel = 1'b0;
    wire [15:0] k_dat;                 // assigned below a_r
    wire [15:0] k_din_hmux;            // data_in_hi: k_din_ce, or k_din (step 9)
    reg  [2:0]  k_ipl    = 3'b111;
    reg         k_berr   = 1'b0;

    wire [31:0] k_addr;
    wire [15:0] k_dout;
    wire        k_nwr, k_nuds, k_nlds, k_nresetout, k_skip;
    // 32-BIT DATA PATH (step 7, m1nl's TG68K.C fork): the kernel offers an
    // aligned word pair on k_long_cand; answering k_long_ack at the step
    // moves both words at once (reads: k_din_hi = word at the address,
    // data_in = word at +2; writes: k_dout, then k_dout_lo).
    wire        k_long_cand;
    wire [15:0] k_dout_lo;
    // k_long_ack is set at DECIDE when the kernel offers an aligned pair for
    // a cache lookup (a guess: CCMP finds out whether both words hit) and is
    // only ever changed >= 2 clocks before the kernel samples it, like
    // data_in: a pair hit steps at once; a hit on the asked word alone drops
    // it and steps a clock later (FINISH); a miss drops it. The word at the
    // address goes to data_in_hi straight from the even bank's register.
    reg         k_long_ack = 1'b0;
    wire [1:0]  k_bs;
    wire [2:0]  k_fc;
    wire [3:0]  k_cacr;            // 68020 CACR: 0 EI, 1 FI, 2 CEI, 3 CI
                                   // (EI also enables the data cache)

    tg68_020 core (
        .clk        (clk),
        .nreset     (k_nreset),
        .clkena_in  (k_clkena),
        .clkena_lw_in (k_clkena_lw),
        .clkena_lw2_in (k_clkena_lw2),   // (unused with CLKLW=3)
        .clkena_lw2n_in (k_clkena_lw2_n),
        .clkena_lw3_in (k_clkena_lw3),
        .data_in    (k_dat),
        .data_in_hi (k_din_hmux),
        .long_ack   (k_long_ack),
        .ipl        (k_ipl),
        .berr       (k_berr),
        .addr_out   (k_addr),
        .data_write (k_dout),
        .data_write_lo (k_dout_lo),
        .long_cand  (k_long_cand),
        .longword   (k_longword),
        .nwr        (k_nwr),
        .nuds       (k_nuds),
        .nlds       (k_nlds),
        .busstate   (k_bs),
        .nresetout  (k_nresetout),
        .fc         (k_fc),
        .skipfetch  (k_skip),
        .cacr       (k_cacr)
    );

    // ------------------------------------------------------------------
    // Bus-side registers (held for the whole cycle)
    // ------------------------------------------------------------------
    reg [31:1] a_r  = 31'd0;
    reg [2:0]  fc_r = 3'b110;
    reg        uds_want = 1'b1, lds_want = 1'b1;
    assign eab = a_r;
    assign k_dat = !k_din_sel ? (k_din_hsel ? k_din_lo : (k_din_dsel ? k_din_dw : (k_din_psel ? k_din_fp : k_din)))
                              : ((a_r[1] | k_long_ack) ? k_din_co : k_din_ce);
    assign k_din_hmux = k_din_hsel ? k_din : k_din_ce;
    assign {FC2, FC1, FC0} = fc_r;

    // ------------------------------------------------------------------
    // Sequencer
    // ------------------------------------------------------------------
    localparam [3:0] Q_SETTLE = 4'd0,  // waiting for kernel outputs to settle
                     Q_DECIDE = 4'd1,  // internal step or bus cycle?
                     Q_SETUP  = 4'd2,  // address out, waiting to assert AS
                     Q_WDS    = 4'd3,  // write: AS out, waiting to assert DS
                     Q_WAIT   = 4'd4,  // waiting for DTACK/BERR
                     Q_LATCH  = 4'd5,  // DTACK seen, counting to data latch
                     Q_FINISH = 4'd6,  // data latched, counting to clkena
                     Q_DDATA2 = 4'd7,  // pair read: second word captured (step 9)
                     // 4'd7 unused (was CLOOK, before step 6)
                     Q_CCMP   = 4'd8,  // cache: compare tag, hit steps the CPU
                     Q_DWAIT  = 4'd9,  // direct SDRAM access in progress
                     Q_DDATA  = 4'd10, // direct SDRAM data captured
                     Q_CFREE  = 4'd11; // cache miss: waiting for the SDRAM port

    // No initial value, on purpose (step 9): with one, yosys will not treat
    // q as a state machine ("Register has an initialization value") and
    // keeps it as four binary bits, so every state test costs a decode LUT
    // on the 1T paths through the step decision. Without it yosys recodes q
    // one-hot. It needs no power-up value: extReset is held through the
    // power-up hold (~pwrup_done in base64_tg68_top) and loads Q_SETTLE on
    // every clock of it.
    reg [3:0] q;

    // ------------------------------------------------------------------
    // ICACHE -- instruction cache
    //
    // Direct-mapped, one 16-bit word per entry, 2^IC_AW entries in block
    // RAM. Only instruction fetches (busstate 00) are looked up or filled,
    // and only from memory nothing but this CPU can change:
    //   * on-board fast RAM (Zorro II window and $08000000), as reported by
    //     fastmem_zii's registered window decode (icache_win). DMA into it
    //     is not supported at all (see the fx68k README), so the CPU is the
    //     only writer;
    //   * the Kickstart ROM, $F80000-$FFFFFF.
    // Chip RAM is never cached: the blitter and disk DMA write it.
    //
    // Coherency: every CPU write to a cacheable address invalidates its
    // entry, whatever CACR says. So self-modifying code and LoadSeg work
    // without CacheClearU, and CACR's clear bits (CI/CEI) are not needed:
    // they are ignored. TG68 also latches CI rather than self-clearing it,
    // so it could not be used as a clear strobe reliably anyway.
    // CACR EI (bit 0) enables the cache, as on a real 68020 (off at reset;
    // Kickstart 2.0+ turns it on). FI (bit 1) freezes it: hits, no fills.
    // The whole cache is invalidated after any reset, because autoconfig
    // may give the Zorro II RAM a different address next time.
    //
    // Timing: the cache RAM's read address is the kernel's own address
    // output, read on the edge INTO DECIDE (EARLY LOOKUP, step 6: a kernel
    // -> cache RAM path with SETTLE-1 clocks). DECIDE registers the RAM
    // output (word into k_din_ce/co, tag into ic_qt_e/o) and CCMP compares, so the
    // hit decision and the hit data are ordinary single-cycle paths. A hit
    // costs 5 clocks from one kernel step to the next, against 7+ for fast
    // RAM and ~45 for the ROM over the 7M bus.
    // ------------------------------------------------------------------
    localparam integer IC_N  = 1 << IC_AW;
    localparam integer TAGW  = 1 + 2 + (23 - IC_AW);     // valid, region, a[23:IC_AW+1]

    // TG68: each cache is two banks, even words (address bit 1 = 0) and odd
    // words, half as deep: the same RAM, but one read gives both words of an
    // aligned pair (32-BIT DATA PATH, step 7). Writes and the flush sweep go
    // to the bank their word index's bit 0 selects.
    localparam integer IC_NB = IC_N / 2;
    (* ram_style = "block" *) reg [15:0]     ic_data_e [0:IC_NB-1];
    (* ram_style = "block" *) reg [15:0]     ic_data_o [0:IC_NB-1];
    (* ram_style = "block" *) reg [TAGW-1:0] ic_tag_e  [0:IC_NB-1];
    (* ram_style = "block" *) reg [TAGW-1:0] ic_tag_o  [0:IC_NB-1];
    integer ic_i;
    initial for (ic_i = 0; ic_i < IC_NB; ic_i = ic_i + 1) begin
        ic_data_e[ic_i] = 16'd0; ic_data_o[ic_i] = 16'd0;
        ic_tag_e[ic_i]  = {TAGW{1'b0}}; ic_tag_o[ic_i] = {TAGW{1'b0}};
    end

    // TG68: the RAMs read the kernel's address on every clock. The read
    // that counts is the one on the edge INTO DECIDE (EARLY LOOKUP, step 6),
    // two clocks after the kernel's registers moved: check_timing.py gives
    // kernel -> cache RAM paths SETTLE-1 clocks for this.
    // (step 15: in the clock after a kernel step, when the kernel's address
    // is changing anyway, the RAMs read the predicted next fetch address)
    reg  [31:1]      fp_a = 31'd0;
    wire [IC_AW-2:0] ic_ra = ((FPRED != 0) && k_step) ? fp_a[IC_AW:2]
                                                      : k_addr[IC_AW:2];   // row: both banks
    reg  [15:0]      ic_dq_e, ic_dq_o;
    reg  [TAGW-1:0]  ic_tq_e, ic_tq_o;
    reg              ic_we = 1'b0;
    reg  [IC_AW-1:0] ic_wa;
    reg  [15:0]      ic_wd;
    reg  [TAGW-1:0]  ic_wt;
    always @(posedge clk) begin
        ic_dq_e <= ic_data_e[ic_ra]; ic_dq_o <= ic_data_o[ic_ra];
        ic_tq_e <= ic_tag_e[ic_ra];  ic_tq_o <= ic_tag_o[ic_ra];
        if (ic_we && !ic_wa[0]) begin
            ic_data_e[ic_wa[IC_AW-1:1]] <= ic_wd;
            ic_tag_e[ic_wa[IC_AW-1:1]]  <= ic_wt;
        end
        if (ic_we && ic_wa[0]) begin
            ic_data_o[ic_wa[IC_AW-1:1]] <= ic_wd;
            ic_tag_o[ic_wa[IC_AW-1:1]]  <= ic_wt;
        end
    end

    reg  [TAGW-1:0]  ic_qt_e, ic_qt_o; // the looked-up tags (both banks), at DECIDE
    // The cacheable-window test for the lookup, registered at DECIDE from the
    // kernel's address (k_rom/k_z2/k_cpuw, the same windows as ic_ok below).
    // ic_ok itself uses icache_win, which is one clock behind a_r and so is
    // not valid yet in CCMP, which is now the clock right after DECIDE.
    reg              ic_ok_d = 1'b0;
    reg              ic_flush = 1'b1;  // sweeping all entries invalid
    reg  [IC_AW-1:0] ic_fcnt = {IC_AW{1'b0}};
    reg              cyc_fetch = 1'b0; // current bus cycle is a fetch

    // Cacheability and tag of the cycle in a_r (stable from DECIDE on).
    wire ic_rom  = (a_r[31:19] == 13'h001F);              // $F80000-$FFFFFF
    wire ic_ok   = (ICACHE != 0) && (ic_rom || icache_win);
    // CHIP RAM CODE (step 11): the instruction cache also holds code fetched
    // from chip RAM ($000000-$1FFFFF), as a real 68020's does; the data
    // cache never holds chip RAM (DMA and the blitter rewrite it). ic_okf
    // is the instruction cache's window: fills on a fetch, and drops the
    // entry on any CPU write. DMA writes are invisible here, so software
    // must clear the cache after loading code, as on a 68020 (CACR CI/CEI,
    // which flush both caches: flush_trig below; Exec's CacheClearU).
    wire ic_chip = (ICACHE != 0) && (CHIP_IC != 0) && (a_r[31:21] == 11'd0);
    wire ic_okf  = ic_ok || ic_chip;
    wire [TAGW-1:0] ic_want = {1'b1, (a_r[31:24] == 8'h08), (a_r[31:24] == 8'h00),
                               a_r[23:IC_AW+1]};
    // ic_on/dc_on are registered (they sit at the head of DECIDE's whole
    // decision tree). They use the flush flag's NEXT value, so they are
    // exactly "EI and not flushing" in every clock; only CACR is a clock
    // late, and the next DECIDE is >= SETTLE clocks after the MOVEC step.
    reg  mr_act_d = 1'b0;  // MapROM state last clock (flush on change)
    // (step 11: also CACR CEI/CI, bits 2-3, which the kernel holds for one
    // step after the MOVEC that sets them, kernel change 3)
    // (step 13b: registered. As a combinational OR it sat in front of the
    // caches' write-address muxes, from ext_reset, and missed 1T on seeds.
    // One clock later is safe for every source: a reset holds the CPU; the
    // RESET instruction and a CACR clear are kernel steps, a MapROM switch
    // is a bus write, and the next DECIDE, where a lookup starts, is >=
    // SETTLE clocks after either; fills during the sweep are blocked and
    // the sweep clears every entry anyway.)
    wire flush_ev   = extReset || !oRESETn || (mr_active != mr_act_d)
                    || ((CACR_CLR != 0) && (k_cacr[3] || k_cacr[2]));
    reg  flush_trig = 1'b0;
    always @(posedge clk) flush_trig <= flush_ev;
    wire flush_nxt  = flush_trig || (ic_flush && !(&ic_fcnt));
    reg  ic_on_r = 1'b0, dc_on_r = 1'b0;
    wire ic_on   = ic_on_r;

    // ------------------------------------------------------------------
    // DCACHE -- data cache
    //
    // Same geometry, tags and cacheable area as the instruction cache
    // (2^IC_AW 16-bit words, direct-mapped; on-board fast RAM and the
    // Kickstart ROM), in its own block RAM, for data reads (busstate 10).
    // It shares the lookup pipeline (EARLY LOOKUP below): both RAMs are read
    // from the kernel's address on the edge into DECIDE, DECIDE loads the
    // word of the kind this cycle uses into k_din_ce/co and its tag into ic_qt_e/o,
    // and CCMP compares.
    //
    // Write-through. Every CPU write reaches memory as before. A whole-word
    // write to fast RAM also writes the cache entry (allocate), so a value
    // just stored reads back from the cache; a byte write, or any write to
    // a cacheable address that is not plain fast RAM (MapROM loading),
    // invalidates the entry instead. The CPU is the only writer of on-board
    // fast RAM (the SD card does not write memory, and nothing else on the
    // motherboard can reach this RAM), so that keeps the cache exact.
    // Filled on a data read miss, and by the next-word prefetch, so a
    // sequential read caches every word, not every other one.
    //
    // ENABLE: there is no data cache on a real 68020, and its CACR has no
    // data cache bits. Exec, SysInfo and most CPU checks tell a 68020 from
    // a 68030 by setting the 68030's data-cache enable bit (CACR bit 8) and
    // reading it back, so storing it would make this CPU look like a 68030
    // (and invite MMU code). So the data cache follows EI (CACR bit 0): it is
    // on whenever the instruction cache is. SysInfo's/CPU's "data cache"
    // switch does nothing, exactly as on a real 68020. FI freezes only the
    // instruction cache. DCACHE=0 removes the data cache from the build.
    //
    // Both caches are flushed after any reset and whenever MapROM is
    // switched on or off, since the ROM addresses then return other data.
    // ------------------------------------------------------------------
    wire [15:0]      dc_dq_e, dc_dq_o;
    wire [TAGW-1:0]  dc_tq_e, dc_tq_o;
    reg              dc_we = 1'b0;
    reg  [IC_AW-1:0] dc_wa;
    reg  [15:0]      dc_wd;
    reg  [TAGW-1:0]  dc_wt;
    generate if (DCACHE != 0) begin : g_dcache
        (* ram_style = "block" *) reg [15:0]     dc_data_e [0:IC_NB-1];
        (* ram_style = "block" *) reg [15:0]     dc_data_o [0:IC_NB-1];
        (* ram_style = "block" *) reg [TAGW-1:0] dc_tag_e  [0:IC_NB-1];
        (* ram_style = "block" *) reg [TAGW-1:0] dc_tag_o  [0:IC_NB-1];
        reg [15:0]     dq_e, dq_o;
        reg [TAGW-1:0] tq_e, tq_o;
        integer i;
        initial for (i = 0; i < IC_NB; i = i + 1) begin
            dc_data_e[i] = 16'd0; dc_data_o[i] = 16'd0;
            dc_tag_e[i]  = {TAGW{1'b0}}; dc_tag_o[i] = {TAGW{1'b0}};
        end
        always @(posedge clk) begin
            dq_e <= dc_data_e[ic_ra]; dq_o <= dc_data_o[ic_ra];
            tq_e <= dc_tag_e[ic_ra];  tq_o <= dc_tag_o[ic_ra];
            if (dc_we && !dc_wa[0]) begin
                dc_data_e[dc_wa[IC_AW-1:1]] <= dc_wd;
                dc_tag_e[dc_wa[IC_AW-1:1]]  <= dc_wt;
            end
            if (dc_we && dc_wa[0]) begin
                dc_data_o[dc_wa[IC_AW-1:1]] <= dc_wd;
                dc_tag_o[dc_wa[IC_AW-1:1]]  <= dc_wt;
            end
        end
        assign dc_dq_e = dq_e; assign dc_dq_o = dq_o;
        assign dc_tq_e = tq_e; assign dc_tq_o = tq_o;
    end else begin : g_no_dcache
        assign dc_dq_e = 16'd0; assign dc_dq_o = 16'd0;
        assign dc_tq_e = {TAGW{1'b0}}; assign dc_tq_o = {TAGW{1'b0}};
    end endgenerate

    wire dc_on   = dc_on_r;
    // the tag an address would have (same layout as ic_want)
    function [TAGW-1:0] tag_of(input [31:1] ad);
        tag_of = {1'b1, (ad[31:24] == 8'h08), (ad[31:24] == 8'h00), ad[23:IC_AW+1]};
    endfunction
    wire k_rom   = (k_addr[31:19] == 13'h001F);           // $F80000-$FFFFFF
    reg  pf_dc   = 1'b0;   // the prefetch in flight may fill a cache
    // INSTRUCTION PREFETCH (step 10): an instruction read from the SDRAM is
    // followed by a prefetch of the next word too, not only a data read.
    // pf_ic: the prefetched word is an instruction word, so it fills the
    // instruction cache (pf_dc then holds the instruction cache's fill
    // conditions); the buffer itself serves a fetch or a data read alike.
    reg  pf_ic   = 1'b0;
    reg  pf_fill = 1'b0;   // prefetched word arrived: write it to the cache
    // A posted write updates the caches one clock after DECIDE, from the
    // registers DECIDE latched (a_r, dp_wdata), so none of DECIDE's branch
    // logic reaches the cache write ports. The next lookup is >= SETTLE
    // clocks away. Instruction cache: entry dropped. Data cache: a whole
    // word in plain fast RAM is written in (write-through, allocate);
    // anything else drops the entry.
    reg  pw_upd = 1'b0;
    reg  pw_dc  = 1'b0;    // ...and the data-cache entry becomes valid
    // 32-BIT SDRAM (step 8): a pair write updates the second word's entries
    // one clock after the first (pw_upd2, from dp_wdata_lo); still >= 1
    // clock before the next lookup's early read.
    reg  pw_upd2 = 1'b0;
    //
    // OVERLAP. A cache lookup does not need the SDRAM, so it may start while
    // a posted write, a prefetch or a discarded read is still finishing in
    // the background (only a miss then waits, in CFREE). Before, every
    // access waited for the port to go idle, instruction-cache hits included.
    // The one exception: a data read of the very word being prefetched waits
    // in DECIDE, as before, and takes it from the buffer.
    //
    // SPECULATIVE READ. A data read from fast RAM is sent to the SDRAM at
    // DECIDE, alongside the lookup, so a miss costs nothing extra. On a hit
    // the read is left to finish in the background and its data dropped
    // (it becomes dp_kind 2, like a posted write). The controller cannot
    // answer before CCMP: its quickest request->ack is 3 clocks, CCMP is 1
    // (the test bench checks this).
    reg  dp_spec = 1'b0;   // this lookup has a speculative read in flight
    wire k_look  = ((ICACHE != 0) && k_bs == 2'b00 && ic_on)
                 || ((DCACHE != 0) && k_bs == 2'b10 && dc_on && (k_fast || k_rom));
    wire pf_wait = (dp_kind == 2'd3) && (k_addr[31:1] == pf_a);

    // ------------------------------------------------------------------
    // EARLY LOOKUP (step 6)
    //
    // The kernel's address is final about 21 ns after its registers move
    // (routed, slow corner), inside two clocks, while the bus-state and
    // function-code outputs need nearly three. So the cache RAMs are read on
    // the edge into DECIDE, a clock before DECIDE's own decision, and DECIDE
    // already has both caches' word and tag for the address:
    //   * DECIDE loads the word of this cycle's kind into k_din_ce/co (its own
    //     register, through a 2-way mux only, whatever the compare will say:
    //     data registers load unconditionally) and its tag into ic_qt_e/o, and
    //     sets k_din_sel so the kernel's data input takes k_din_ce/co;
    //   * CCMP, the next clock, compares, and a hit steps the kernel there
    //     and then: k_din_ce/co has been stable for a clock, which is all
    //     DIN_SETUP asks. A miss sets k_din_sel back to k_din.
    // A hit costs 5 clocks from one step to the next instead of 7 (3 settle,
    // DECIDE, CCMP), the same as a prefetch hit. That made the step 5 pair
    // buffers, which bought 5 clocks for the second word of a pair, worth
    // nothing, so they are gone. A miss also goes on to the bus or the SDRAM
    // a clock sooner.
    // Both banks' tags are compared; the word the cycle asked for (a_r[1])
    // decides a narrow hit.
    // Step 14: the compare's other inputs are registered from the kernel's
    // address beside ic_ok_d (every clock, so in CCMP they hold DECIDE's
    // address, the one a_r loaded): the wanted tag, the cache-on term and
    // the word select. Decoding them from a_r in CCMP put two 8-bit
    // compares and a mux in front of the tag compare, on a 1T path into the
    // next state that missed on seeds. cc_on_k samples ic_on/dc_on in
    // DECIDE, a clock before cc_on did: every flush trigger and CACR EI
    // change >= SETTLE clocks before a DECIDE, so it is the same value,
    // except at the end of a flush sweep, where it can only say "off" (one
    // lookup misses; never a false hit). Sim-only check: cc_bad.
    reg [TAGW-1:0] cc_want_k = {TAGW{1'b0}};
    reg            cc_on_k = 1'b0, cc_sel_k = 1'b0;
    wire cc_hit_e = (ic_qt_e == cc_want_k);
    wire cc_hit_o = (ic_qt_o == cc_want_k);
    wire cc_on    = cc_on_k;
    wire cc_hit   = cc_on && (cc_sel_k ? cc_hit_o : cc_hit_e);
    // ...and a pair hit (k_long_ack is only set for aligned pairs) needs both
    wire cc_long  = k_long_ack && cc_on && cc_hit_e && cc_hit_o;

    // ------------------------------------------------------------------
    // FETCH PREDICTOR (step 15)
    //
    // A cache hit costs 5 clocks because the kernel's address is only good
    // for the RAM read 2 clocks after a step. But most fetches are of the
    // word after the last one fetched, and that address is known at the
    // step. So after every kernel step the instruction cache is read at the
    // predicted next fetch address fp_a (the last fetch + 1 word, + 2 after
    // a pair), from the adapter's own registers:
    //   DECIDE         fp_a <= this fetch's address + 1 word (+ 2 if the
    //                  kernel offers a pair), on every DECIDE clock of a
    //                  fetch, whatever DECIDE decides: its enable is dec_r
    //                  and the kernel's bus state, not the step decision
    //                  (as fp_a's enable that decision missed 1T by 1.4 ns)
    //   step edge E0   (fp_a is at least a clock old, or loads on this edge)
    //   E1             the RAMs read fp_a's row (k_step is high: ic_ra)
    //   E2             word -> k_din_fp, tag -> fp_tq, k_din_psel set
    //   E3             fp_v <= the tag matches (and no write to that entry)
    //   E3..E4 DECIDE  a fetch at fp_a with fp_v set steps the kernel at
    //                  once, like an internal step: 4 clocks, not 5
    // The prediction is only ever a cache entry whose tag matches, so it is
    // exactly the word a normal lookup of that address would return. An
    // entry is valid only if its address was cacheable when it was filled,
    // and every change of the windows flushes the caches, so no window
    // decode is needed here. Any instruction-cache write to the predicted
    // entry between the read and the step (a fill, a posted write's
    // invalidate, the flush sweep) drops the prediction: fp_kill from the
    // read on, fp_v after. The flush also turns ic_on off at once.
    // Anything else DECIDE does with a bus or data cycle drops fp_v and the
    // select; the next step reads the same fp_a again. A fetch the kernel
    // offers as a pair is left to the normal lookup (2 words in 5 clocks).
    // fp_ac is a second copy of fp_a for the address compare in fp_hit
    // alone. fp_v is cleared on the edge the two load and is set again no
    // sooner than 3 clocks later (E3 of the next step), so fp_ac has two
    // clocks to reach the step decision: check_timing.py classes it so
    // (tb-asserted: fp_ac never changes on the edge into a clock with fp_v
    // set). fp_a itself feeds the RAM address a clock after it loads (a
    // predicted fetch steps on the loading edge). The copies have different
    // power-on values so that yosys keeps them apart (see k_clkena_lw2_n).
    // Sim-only check: fp_chk_bad (below).
    reg  [TAGW-1:0] fp_tq;
    reg         fp_s1 = 1'b0, fp_s2 = 1'b0;   // k_step, one and two clocks on
    reg         fp_v = 1'b0, fp_kill = 1'b0;
    wire        fp_bad  = ic_we && (ic_wa == fp_a[IC_AW:1]);
    wire        k_pcand = (DP32_ACK != 0) && k_long_cand && !k_addr[1];
    (* keep *) reg [31:1] fp_ac = 31'h7FFFFFFF;
    wire        fp_hit  = (FPRED != 0) && fp_v && ic_on && (k_bs == 2'b00) && !k_skip
                          && (k_addr[31:1] == fp_ac) && !k_pcand
                          && BGn && BGACKn && BRn && HALTn;

    // ------------------------------------------------------------------
    // DIRECT -- direct SDRAM path for on-board fast RAM
    //
    // A fast RAM access through the 68000-style slave costs ~17 clocks, of
    // which the SDRAM needs ~5: the rest is address setup, the strobe
    // register, DTACK and the data-latch delay. Here the adapter decides
    // "this is fast RAM" itself and asks the SDRAM controller directly
    // through fastmem_zii's dp_* port. No AS/DS is driven, so neither the
    // motherboard nor any other slave sees the cycle.
    //
    // The decision is made from the kernel's address at DECIDE, so it is a
    // kernel -> logic path (SETTLE budget), using the fast RAM block's
    // static slot assignment. Exactly fastmem_zii's own window: Zorro II
    // slots it owns, and $08000000-$08FFFFFF. MapROM and everything else
    // keep the old route.
    //
    // dp_req_i is the decision; dp_req is a plain copy one clock later, so
    // the register that feeds the SDRAM command logic can sit beside it
    // (the same reason as the strobe pipeline). fastmem_zii's saddr_r tracks
    // a_r one clock behind, so it is valid by the time the controller sees
    // the request. Read data is captured into dp_q before it goes to the
    // kernel, so no new path into k_din is longer than one clock from a
    // register.
    // ------------------------------------------------------------------
    wire [3:0] k_reg  = k_addr[23:20];
    wire [2:0] k_slot = k_reg[2:0] - 3'd2;
    wire k_z2    = fm_on && (k_addr[31:24] == 8'h00) && (k_reg >= 4'h2) && (k_reg <= 4'h9)
                   && fm_match[k_slot];
    wire k_cpuw  = cpu_win_en && (k_addr[31:24] == 8'h08);
    // MapROM banks, exactly fastmem_zii's mr_win: $F80000-$FFFFFF and
    // $E00000-$E7FFFF. Reads go to the shadow when ACTIVE, writes when LOAD;
    // otherwise these addresses take the old route to the motherboard.
    wire k_mrwin = (k_addr[31:24] == 8'h00)
                   && (k_addr[23:19] == 5'b11111 || k_addr[23:19] == 5'b11100);
    wire k_mr    = k_mrwin && (k_nwr ? mr_active : mr_load);
    wire k_fast  = (DIRECT != 0) && (k_z2 || k_cpuw || k_mr);
    //
    // Two things keep the CPU from waiting on the SDRAM at all:
    //   * POSTED WRITES. A fast RAM write is handed to the controller and
    //     the CPU steps on at once; the write completes while the kernel
    //     settles its next step.
    //   * NEXT-WORD PREFETCH. After a fast RAM data read of word A, the
    //     controller is immediately asked for A+2 (same row, so cheap) into
    //     a one-word buffer. The second half of a longword, or the next word
    //     of a sequential read, is then answered from the buffer.
    // Only one request is ever in flight (dp_busy). Nothing that needs the
    // SDRAM -- a direct access, or an old-route cycle that fastmem_zii
    // might serve (MapROM) -- starts until it has finished. The CPU is the
    // only writer of fast RAM, so the buffer stays correct by dropping it
    // on any write to its word, and on reset.
    reg         dp_req_i = 1'b0;
    reg         dp_fast  = 1'b0;   // current cycle is a fast RAM cycle
    reg  [15:0] dp_q;
    reg         dp_busy  = 1'b0;   // a request is in flight
    reg  [1:0]  dp_kind  = 2'd0;   // 1 read (sequencer), 2 posted write, 3 prefetch
    reg         pf_valid = 1'b0;
    reg  [31:1] pf_a;      // written only when a prefetch is issued (DDATA);
                           // every use is >= 4 clocks later (next DECIDE,
                           // or the fill after its ack): a 2T source
    reg  [15:0] pf_d;
    always @(posedge clk) begin
        dp_req <= dp_req_i;
    end
    // dp_inc is raised the clock BEFORE dp_req_i for a prefetch (at the
    // read's ack), so fastmem_zii's SDRAM address register holds the next
    // word for two clocks before the controller samples it; it drops when
    // the prefetch is acknowledged. eab_early lets that register follow the
    // kernel's address, which is final at DECIDE, rather than eab.
    assign eab_early = k_addr[31:1];
    // fastmem_zii freezes its SDRAM address while a request is outstanding:
    // after a posted write or a prefetch is issued the kernel steps on and
    // its address moves, and the controller may accept the request late
    // (refresh). dp_busy is set on the very edge the address is captured.
    assign dp_hold = dp_busy;
    // k_fast too: if MapROM was switched off after a shadow word was
    // prefetched, that address now belongs to the motherboard ROM again.
    // a data read or (step 10) an instruction fetch: k_bs 10 or 00
    wire k_pf_hit = (DIRECT != 0) && pf_valid && !k_bs[0] && k_nwr
                    && (k_addr[31:1] == pf_a) && k_fast;
    wire k_pf_ok  = k_pf_hit && !dp_busy;
    // 32-BIT SDRAM (step 8): a longword write the kernel offers as an aligned
    // pair, both bytes of the word strobed (a pair is always a whole longword)
    wire k_wpair  = (DP32_WR != 0) && k_long_cand && !k_addr[1] && !k_nuds && !k_nlds;
    // 32-BIT SDRAM READS (step 9): the same for a read. dp_pair carries
    // either to the controller (it latches pair with the request).
    wire k_rpair  = (DP32_RD != 0) && k_long_cand && !k_addr[1] && !k_nuds && !k_nlds;
    // PAIR PREFETCH (step 11): every read of an even word from fast RAM is
    // a pair read, whether or not the kernel takes the pair: the second word
    // goes to the prefetch buffer with no request of its own (it used to be
    // a separate SDRAM request, which the next read then queued behind)
    wire k_ralg   = (RD11 != 0) ? ((DP32_RD != 0) && !k_addr[1]) : k_rpair;
    wire k_dpair  = k_nwr ? k_ralg : k_wpair;
    // rp_go: this cycle is an aligned pair read from fast RAM (registered at
    // DECIDE). A cache miss keeps k_long_ack = rp_go whichever way it goes
    // on (the read is a pair read exactly then), and CCMP/CFREE issue their
    // request with dp_pair = rp_go.
    reg  rp_go = 1'b0;
    reg  rp_al = 1'b0;     // step 11: an even-word read from fast RAM (pair request)
    reg  pf_fill_d = 1'b0; // step 11: fill the pair's second word a clock later

    // ------------------------------------------------------------------
    // STROBE PIPELINE
    // The sequencer drives as_i/uds_i/lds_i; the ports are those, one clock
    // later. Every bus consumer (motherboard bridge, fast RAM, turbomem, SD,
    // hi_null) sees the same delayed strobes, so their relative timing is
    // unchanged. The point is placement: this register can sit next to the
    // slaves, where DS feeds the fast RAM request and the SDRAM command
    // logic within one 86 MHz clock, instead of beside the CPU core on the
    // far side of the chip. Costs one clock per bus cycle. The sequencer
    // already waits for DTACK, so a slave answering a clock later needs no
    // change, and read data is latched while the port AS is still low.
    reg as_i = 1'b1, uds_i = 1'b1, lds_i = 1'b1;
    always @(posedge clk) begin
        ASn  <= as_i;
        UDSn <= uds_i;
        LDSn <= lds_i;
    end
    reg [5:0] cnt  = 6'd0;   // clocks since last clkena (saturating)
    reg [5:0] tmr  = 6'd0;   // per-state timer
    reg       bus_berr = 1'b0;
    // dec_r is 1 exactly while q is Q_DECIDE: set on the way in (SETTLE),
    // cleared on every way out. It enables DECIDE's bulk data loads from a
    // register of its own: decoding q for ~55 enables put that decode in the
    // data-cache write-port path (-3 ns, step 7).
    reg       dec_r = 1'b0;
    reg       cyc_start = 1'b0;   // a cycle was set up on the last edge (a_r and
                                  // the bus registers belong to it; for the
                                  // test benches' write shadow)

    // Watchdog for the stall LED: ~2^23 clocks = ~98 ms
    reg [23:0] wd = 24'd0;

    // Registered "previous cycle's DTACK/BERR have gone": only a guard
    // before starting a cycle, so one clock stale is fine, and it keeps the
    // slaves' combinational DTACK out of the bus-output register enables.
    reg  ack_idle = 1'b1;
    always @(posedge clk) ack_idle <= DTACKn & BERRn;

    wire internal_step = (k_bs == 2'b01) || (k_bs == 2'b00 && k_skip);
    assign cyc_idle = (q == Q_DECIDE || q == Q_SETTLE) && !dp_busy;
    wire bus_free      = BGn && BGACKn && BRn && HALTn;
    // CLOOK/CCMP count: a miss goes straight on to a bus cycle.
    wire in_cycle      = (q == Q_SETUP) || (q == Q_WDS) || (q == Q_WAIT)
                       || (q == Q_LATCH) || (q == Q_CCMP)
                       || (q == Q_DWAIT) || (q == Q_DDATA) || (q == Q_DDATA2) || (q == Q_CFREE)
                       || ~as_i || ~ASn;

    always @(posedge clk) begin
        k_clkena <= 1'b0;
        k_step   <= 1'b0;
        k_clkena_lw <= 1'b0; k_clkena_lw2_n <= 1'b1; k_clkena_lw3 <= 1'b0;
        ic_we    <= 1'b0;
        dc_we    <= 1'b0;
        cyc_start <= 1'b0;
        // EARLY LOOKUP: loaded every clock (only the DECIDE edge counts,
        // and CCMP is always the clock straight after it), so no enable sits
        // in the RAM -> register path.
        ic_qt_e  <= (k_bs == 2'b00) ? ic_tq_e : dc_tq_e;
        ic_qt_o  <= (k_bs == 2'b00) ? ic_tq_o : dc_tq_o;
        // Loaded on every DECIDE clock (the last one counts) and then HELD:
        // re-reading after DECIDE could hand the kernel a word that a fill
        // put there after the tag was checked.
        if (q == Q_DECIDE) begin
            k_din_ce <= (k_bs == 2'b00) ? ic_dq_e : dc_dq_e;
            k_din_co <= (k_bs == 2'b00) ? ic_dq_o : dc_dq_o;
        end
        // The kernel samples data_in at the end of the clkena clock; the
        // select goes back to k_din on that same edge.
        if (k_step) begin k_din_sel <= 1'b0; k_long_ack <= 1'b0; k_din_hsel <= 1'b0; k_din_dsel <= 1'b0; end
        // (step 11: chip RAM too; only fetches look it up, k_look)
        ic_ok_d  <= (ICACHE != 0) && (k_rom || k_z2 || k_cpuw || icache_win_k
                                      || ((CHIP_IC != 0) && (k_addr[31:21] == 11'd0)));
        // step 14: the rest of CCMP's compare inputs, from the same address
        cc_want_k <= {1'b1, (k_addr[31:24] == 8'h08), (k_addr[31:24] == 8'h00),
                      k_addr[23:IC_AW+1]};
        cc_sel_k  <= k_addr[1];
        cc_on_k   <= (ICACHE != 0) && (k_rom || k_z2 || k_cpuw || icache_win_k
                                      || ((CHIP_IC != 0) && (k_addr[31:21] == 11'd0)))
                     && ((k_bs == 2'b00) ? ic_on : dc_on);
        mr_act_d <= mr_active;
        ic_on_r  <= (ICACHE != 0) && k_cacr[0] && !flush_nxt;
        dc_on_r  <= (DCACHE != 0) && k_cacr[0] && !flush_nxt;
        if (cnt != 6'h3F) cnt <= cnt + 6'd1;
        if (tmr != 6'h3F) tmr <= tmr + 6'd1;

        // FETCH PREDICTOR pipeline (see above). fp_bad before the sequencer:
        // a step on this edge starts a new read and clears fp_kill.
        fp_s1 <= k_step;
        fp_s2 <= fp_s1;
        if (fp_s1) begin
            k_din_fp   <= fp_a[1] ? ic_dq_o : ic_dq_e;
            fp_tq      <= fp_a[1] ? ic_tq_o : ic_tq_e;
            k_din_psel <= (FPRED != 0);
        end
        if (fp_s2) fp_v <= (fp_tq == tag_of(fp_a)) && !fp_kill;
        if (fp_bad) begin fp_kill <= 1'b1; fp_v <= 1'b0; end
        // the next fetch address, from every DECIDE clock of a fetch (the
        // kernel's outputs are final there); fp_v goes with it
        if (dec_r && k_bs == 2'b00 && !k_skip) begin
            fp_a  <= k_addr[31:1] + (k_pcand ? 31'd2 : 31'd1);
            fp_ac <= k_addr[31:1] + (k_pcand ? 31'd2 : 31'd1);
            fp_v  <= 1'b0;
        end

        // ---- bus arbitration (68000 rules, between cycles only) ------
        if (!BGACKn)                BGn <= 1'b1;   // new master has it
        else if (!BRn && !in_cycle) BGn <= 1'b0;
        else if (BRn)               BGn <= 1'b1;

        if (extReset) begin
            // Hold the kernel in reset, but keep stepping it: its internal
            // synchronous Reset only advances on clkena.
            k_nreset <= 1'b0;
            k_din_sel <= 1'b0; k_long_ack <= 1'b0; k_din_hsel <= 1'b0; k_din_dsel <= 1'b0;
            dec_r    <= 1'b0;
            as_i  <= 1'b1; uds_i <= 1'b1; lds_i <= 1'b1; eRWn <= 1'b1;
            oRESETn  <= 1'b1;
            k_berr   <= 1'b0;
            dp_req_i <= 1'b0;
            dp_busy  <= 1'b0; dp_kind <= 2'd0;
            dp_inc   <= 1'b0;
            pf_valid <= 1'b0;
            pf_fill  <= 1'b0; pf_dc <= 1'b0; pf_ic <= 1'b0; pf_fill_d <= 1'b0;
            pw_upd   <= 1'b0; pw_upd2 <= 1'b0;
            dp_pair  <= 1'b0;
            dp_spec  <= 1'b0;
            fp_v <= 1'b0; k_din_psel <= 1'b0;
            stalled  <= 1'b0;
            wd       <= 24'd0;
            q        <= Q_SETTLE;
            if (cnt >= STEP - 1) begin
                k_clkena <= 1'b1;
                k_step   <= 1'b1;
                k_clkena_lw <= !k_longword || k_long_ack; k_clkena_lw2_n <= !(!k_longword || k_long_ack); k_clkena_lw3 <= !k_longword || k_long_ack;
                cnt      <= 6'd0;
                k_ipl    <= {IPL2n, IPL1n, IPL0n};
            end
        end else begin
            // The prefetched word goes into the data cache one clock after
            // it arrives (from pf_d, a register). Written before the case so
            // any cache write the sequencer makes on this edge (a posted
            // write to the same word, say) wins; a lost fill is only a miss.
            // (dp_q holds the prefetched word too, so every data-cache fill
            // takes its data from dp_q or iEdb.) pf_fill and pw_upd never
            // fall on the same clock: a posted write needs the port idle at
            // DECIDE, which is at the earliest the clock pf_fill is set.
            if (pf_fill_d) begin
                pf_fill_d <= 1'b0;
                pf_fill   <= pf_dc;             // step 11: the pair's second word
            end
            if (pf_fill) begin
                pf_fill <= 1'b0;
                dc_wa <= pf_a[IC_AW:1]; dc_wt <= tag_of(pf_a); dc_wd <= dp_q;
                if (dc_on && !pf_ic) dc_we <= 1'b1;
                // step 10: an instruction word fills the instruction cache
                // (same rule: loads regardless, the condition on the enable)
                ic_wa <= pf_a[IC_AW:1]; ic_wt <= tag_of(pf_a); ic_wd <= dp_q;
                if (ICACHE != 0 && pf_ic && ic_on && !ic_flush) ic_we <= 1'b1;
            end
            if (pw_upd) begin
                pw_upd <= 1'b0;
                // dp_pair still holds this write's flag: the port is busy
                // with it, so DECIDE has not reloaded it
                pw_upd2 <= dp_pair;
                if (ICACHE != 0 && !ic_flush) begin
                    ic_we <= 1'b1; ic_wa <= a_r[IC_AW:1]; ic_wt <= {TAGW{1'b0}};
                end
                if (DCACHE != 0) begin
                    dc_we <= 1'b1; dc_wa <= a_r[IC_AW:1];
                    dc_wt <= ic_want; dc_wt[TAGW-1] <= pw_dc;
                    dc_wd <= dp_wdata;
                end
            end
            if (pw_upd2) begin
                // the pair's second word (a_r is the first, an even word; the
                // same tag; a pair is always a whole longword)
                pw_upd2 <= 1'b0;
                if (ICACHE != 0 && !ic_flush) begin
                    ic_we <= 1'b1; ic_wa <= {a_r[IC_AW:2], 1'b1}; ic_wt <= {TAGW{1'b0}};
                end
                if (DCACHE != 0) begin
                    dc_we <= 1'b1; dc_wa <= {a_r[IC_AW:2], 1'b1};
                    dc_wt <= ic_want; dc_wt[TAGW-1] <= pw_dc;
                    dc_wd <= dp_wdata_lo;
                end
            end
            // Data registers that only matter for a cycle that starts load
            // on EVERY DECIDE clock (dec_r), whatever DECIDE decides, so the
            // decision tree (the kernel's address) stays out of their
            // enables. Each is used only by the cycle set up there, and
            // DECIDE comes no sooner after the last cycle than a new cycle
            // would, so old values are held as long as before. The port's
            // write data belong to a request still in flight, if there is one.
            if (dec_r) begin
                oEdb      <= k_dout;
                uds_want  <= k_nuds;
                lds_want  <= k_nlds;
                cyc_fetch <= (k_bs == 2'b00);
                rp_go     <= k_nwr && k_rpair && k_fast;
                rp_al     <= k_nwr && k_ralg && k_fast;
                if (!dp_busy) begin
                    dp_we    <= ~k_nwr;
                    dp_wdata <= k_dout;
                    dp_wdata_lo <= k_dout_lo;
                    dp_be    <= ~{k_nuds, k_nlds};
                    // 32-BIT SDRAM: a pair write (step 8) or read (step 9)
                    dp_pair  <= k_dpair;
                end
            end
            case (q)
            // ----------------------------------------------------------
            Q_SETTLE: if (cnt >= SETTLE - 1) begin q <= Q_DECIDE; dec_r <= 1'b1; end
            // ----------------------------------------------------------
            Q_DECIDE: begin
                // nResetOut is combinational in the kernel; only trust it
                // here, after the outputs have settled. A glitch would
                // reset every peripheral on the motherboard.
                oRESETn <= k_nresetout;
                if (internal_step) begin
                    if (cnt >= STEP - 1) step();
                end else if (fp_hit) begin
                    // FETCH PREDICTOR: the word is in k_din_fp, selected
                    // since two clocks after the last step
                    if (cnt >= STEP - 1) step();
                end else if (k_pf_ok) begin
                    // second half of a longword / next sequential word:
                    // already fetched, no SDRAM access at all
                    dec_r    <= 1'b0;
                    // (step 15: this cycle hands the kernel k_din, so the
                    // predictor's select goes, 2 clocks before the step)
                    k_din_psel <= 1'b0; fp_v <= 1'b0;
                    k_din    <= pf_d;
                    bus_berr <= 1'b0;
                    tmr      <= 6'd0;
                    q        <= Q_FINISH;
                end else if (bus_free && ack_idle && (!dp_busy || (k_look && !pf_wait))) begin
                    a_r      <= k_addr[31:1];
                    fc_r     <= k_fc;
                    eRWn     <= k_nwr;          // RW valid before AS, like S1
                    tmr      <= 6'd0;
                    dp_fast   <= k_fast;
                    cyc_start <= 1'b1;
                    dec_r     <= 1'b0;
                    dp_spec  <= 1'b0;
                    // step 15: a bus or data cycle may hand the kernel k_din:
                    // the predictor's select goes here, >= 2 clocks before
                    // its step (a write that steps on this edge keeps it:
                    // nothing may change in the clock before a step, and a
                    // write takes no data)
                    fp_v <= 1'b0;
                    if (!((WR4 != 0) && !k_look && k_fast && !k_nwr && !k_wpair && cnt >= STEP - 1))
                        k_din_psel <= 1'b0;
                    // The cache RAMs read on this edge used k_addr already.
                    if (k_look) begin
                        q <= Q_CCMP;             // look in the cache first
                        // EARLY LOOKUP: the RAMs read this address on the
                        // edge into DECIDE; k_din_ce/co take the words on this
                        // edge (see below), CCMP decides
                        k_din_sel <= 1'b1;
                        // 32-BIT DATA PATH: take the pair if both words hit
                        // (CCMP decides; see k_long_ack)
                        k_long_ack <= (DP32_ACK != 0) && k_long_cand && !k_addr[1];
                        if (k_bs == 2'b10 && k_fast && !dp_busy) begin
                            dp_req_i <= 1'b1;    // speculative read
                            dp_busy  <= 1'b1; dp_kind <= 2'd1;
                            dp_spec  <= 1'b1;
                        end
                    end else if (k_fast && !k_nwr) begin
                        // posted write: issue it and step on. An aligned
                        // longword the kernel offers as a pair goes as ONE
                        // request: the controller writes both words back to
                        // back (32-BIT SDRAM). k_long_ack is set on this edge
                        // and the kernel steps at the end of FINISH, so it is
                        // 2 clocks old when sampled, like a cache pair.
                        dp_req_i <= 1'b1;
                        dp_busy  <= 1'b1; dp_kind  <= 2'd2;
                        k_long_ack <= k_wpair;   // (dp_pair: loaded under dec_r)
                        // drop the prefetched word if this writes it: compared
                        // by longword, which covers a pair's second word too
                        if (pf_valid && k_addr[31:2] == pf_a[31:2])
                            pf_valid <= 1'b0;
                        // the caches are updated on the next clock (pw_upd)
                        pw_upd <= 1'b1;
                        pw_dc  <= dc_on && !k_nuds && !k_nlds && (k_z2 || k_cpuw);
                        bus_berr <= 1'b0;
                        tmr      <= 6'd0;
                        // step 15: a write that is not a pair needs nothing
                        // back and leaves k_long_ack alone, so the kernel
                        // steps now (a pair's k_long_ack must be 2 clocks old)
                        if ((WR4 != 0) && !k_wpair && cnt >= STEP - 1) step();
                        else q   <= Q_FINISH;
                    end else if (k_fast) begin
                        dp_req_i <= 1'b1;   // direct read
                        dp_busy  <= 1'b1; dp_kind  <= 2'd1;
                        k_long_ack <= k_rpair;   // a pair read (step 9; dp_pair: dec_r)
                        q        <= Q_DWAIT;
                    end else
                        q <= Q_SETUP;
                end
            end
            // ----------------------------------------------------------
            // EARLY LOOKUP: ic_qt_e/o and k_din_ce/co were loaded on the edge into
            // this state. ic_ok_d is the window decode of this cycle's
            // address (icache_win is not valid yet, see ic_ok_d).
            Q_CCMP: begin
                tmr <= 6'd0;
                dp_spec <= 1'b0;
                // k_din_ce/k_din_co already hold the looked-up word (loaded in DECIDE)
                // and k_din_sel picks it, so a hit steps the kernel now. On a
                // miss the select goes back to k_din, which the miss path
                // loads before the kernel steps.
                if (cc_long || (cc_hit && !k_long_ack)) begin
                    // hit (a pair hit if k_long_ack): no bus cycle at all
                    bus_berr <= 1'b0;
                    if (cnt >= STEP - 1 && DIN_SETUP <= 1) step();
                    else q   <= Q_FINISH;
                    if (dp_spec) dp_kind <= 2'd2;   // drop the speculative read
                end else if (cc_hit) begin
                    // the asked word hit but not its pair partner: take it
                    // as a narrow access, a clock later, so that dropping
                    // k_long_ack also reaches the kernel >= 2 clocks early
                    bus_berr   <= 1'b0;
                    k_long_ack <= 1'b0;
                    q          <= Q_FINISH;
                    if (dp_spec) dp_kind <= 2'd2;
                end else begin
                    // miss. 32-BIT SDRAM READS (step 9): an aligned pair in
                    // fast RAM goes on as a pair read (the speculative read
                    // already is one: dp_pair = rp_go then), so k_long_ack
                    // stays for it; anything else drops it.
                    k_long_ack <= rp_go;
                    k_din_sel <= 1'b0;
                    if (dp_spec)
                        q        <= Q_DWAIT; // the read is already out
                    else if (dp_busy)
                        q        <= Q_CFREE; // port still busy
                    else if (dp_fast) begin
                        dp_req_i <= 1'b1;    // miss in fast RAM: direct
                        dp_busy  <= 1'b1; dp_kind <= 2'd1;
                        dp_we    <= 1'b0;
                        q        <= Q_DWAIT;
                    end else
                        q        <= Q_SETUP; // address is already out
                end
                // the next request's pair flag, whenever the port is free
                // (the request issued here, or none: every request site
                // sets it); while busy it belongs to the request in flight
                if (!dp_busy) dp_pair <= rp_al;
            end
            // A miss that found the port busy. fastmem_zii's SDRAM address
            // follows the kernel's address again from the clock after the
            // port frees, so issuing here gives it the same two clocks as
            // a request from DECIDE.
            Q_CFREE: if (!dp_busy) begin
                if (dp_fast) begin
                    dp_req_i <= 1'b1;
                    dp_busy  <= 1'b1; dp_kind <= 2'd1;
                    dp_we    <= 1'b0;
                    dp_pair  <= rp_al;
                    q        <= Q_DWAIT;
                end else
                    q        <= Q_SETUP;
            end
            // ----------------------------------------------------------
            Q_DWAIT: if (dp_ack) begin
                dp_q     <= dp_rdata;
                k_din_dw   <= dp_rdata;            // step 11 (not for a kernel pair)
                k_din_dsel <= (RD11 != 0) && !k_long_ack;
                dp_req_i <= 1'b0;
                dp_busy  <= 1'b0; dp_kind <= 2'd0;
                // a data read will be followed by a prefetch: point the
                // SDRAM address at the next word now (not after a pair
                // read, step 9: it already brings the next word)
                if ((a_r[9:1] != 9'h1FF) && !k_long_ack && !dp_pair) dp_inc <= 1'b1;   // (step 10: fetches too; step 11: not after a pair)
                q        <= Q_DDATA;
            end
            Q_DDATA: begin
                // Cache fills (only reads come here: writes are posted).
                // Address, tag and data load regardless; the conditions
                // only drive the write enables.
                ic_wa <= a_r[IC_AW:1]; ic_wt <= ic_want; ic_wd <= dp_q;
                if (ic_ok && !ic_flush && cyc_fetch && ic_on && !k_cacr[1])
                    ic_we <= 1'b1;
                // data-cache fill (address/tag/data loaded regardless; only
                // the write enable depends on the conditions)
                dc_wa <= a_r[IC_AW:1]; dc_wt <= ic_want; dc_wd <= dp_q;
                if (DCACHE != 0 && ic_ok && eRWn && !cyc_fetch && dc_on)
                    dc_we <= 1'b1;
                k_din    <= dp_q;
                bus_berr <= 1'b0;
                tmr      <= 6'd0;
                // 32-BIT SDRAM READS (step 9): a pair read's second word is
                // on dp_rdata now (the controller's second ack clock)
                dp_q     <= dp_rdata;
                // step 11: a plain direct read steps the kernel now (its
                // word is in k_din_dw since DWAIT), FINISH if cnt says wait
                if ((RD11 != 0) && !k_long_ack && cnt >= STEP - 1 && DIN_SETUP <= 1) step();
                else q   <= k_long_ack ? Q_DDATA2 : Q_FINISH;
                // Data read: fetch the next word while the kernel settles,
                // unless that would leave this 1 KB (row/slot boundaries).
                // A pair read (step 9) already has it: no request, but the
                // same pf_a/pf_dc, so that DDATA2 can fill the second word
                // into the data cache through pf_fill (pf_valid stays 0:
                // the buffer is not used for it).
                // Step 10: after an instruction read as well, filling the
                // instruction cache (pf_ic); the pair-read second word of an
                // instruction-stream pair takes the same route.
                // Step 11: a pair read the kernel did not take (an even word,
                // dp_pair) brings the next word now: it goes straight to the
                // prefetch buffer, and to its cache two clocks later (pf_a
                // two clocks old, its 2T class), with no request of its own.
                // pf_valid/pf_d outside the boundary test: dp_pair means an
                // even word, never the last of a 1 KB block, and pf_d loads
                // in every DDATA (and every clock of a prefetch, below), so
                // its enable is two registers (q, dp_kind) and no dp_ack:
                // the old enable failed 1T by 0.1 ns (rule 3: conditions on
                // the valid bit, not the data register).
                pf_valid <= dp_pair && !k_long_ack;
                pf_d     <= dp_rdata;
                if (a_r[9:1] != 9'h1FF) begin
                    pf_a     <= a_r + 31'd1;
                    pf_fill_d <= dp_pair && !k_long_ack;
                    pf_ic    <= cyc_fetch;
                    pf_dc    <= cyc_fetch ? ((ICACHE != 0) && ic_ok && ic_on && !k_cacr[1])
                                          : ((DCACHE != 0) && ic_ok && dc_on);
                    if (!k_long_ack && !dp_pair) begin
                        dp_req_i <= 1'b1;
                        dp_busy  <= 1'b1; dp_kind  <= 2'd3;
                        dp_we    <= 1'b0;
                        dp_pair  <= 1'b0;
                    end
                end
            end
            // 32-BIT SDRAM READS (step 9): the pair's second word (dp_q)
            // goes to k_din_lo (the first is in k_din, from DDATA). It fills
            // its data-cache entry (the odd bank) through the prefetch fill,
            // on the next clock: pf_a/pf_dc were set in DDATA, so pf_a is two
            // clocks old when pf_fill uses it (its 2T class in
            // check_timing.py), and the cache write ports gain no source.
            Q_DDATA2: begin
                k_din_lo   <= dp_q;
                k_din_hsel <= 1'b1;
                pf_fill    <= pf_dc;
                tmr      <= 6'd0;
                q        <= Q_FINISH;
            end
            // ----------------------------------------------------------
            Q_SETUP: if (tmr >= ADDR_SETUP - 1) begin
                as_i <= 1'b0;
                tmr <= 6'd0;
                if (eRWn) begin                 // read: DS with AS
                    uds_i <= uds_want;
                    lds_i <= lds_want;
                    q    <= Q_WAIT;
                end else begin
                    q    <= Q_WDS;
                end
            end
            // ----------------------------------------------------------
            Q_WDS: if (tmr >= WDS_DELAY - 1) begin
                uds_i <= uds_want;
                lds_i <= lds_want;
                q    <= Q_WAIT;
            end
            // ----------------------------------------------------------
            Q_WAIT: begin
                if (!DTACKn || !BERRn) begin
                    bus_berr <= ~BERRn & DTACKn;
                    tmr      <= 6'd0;
                    q        <= Q_LATCH;
                end
            end
            // ----------------------------------------------------------
            Q_LATCH: begin
                // The data registers load on every LATCH clock; the last
                // load, on the edge that leaves LATCH, is the one that
                // counts. Only the write enables and the state change wait
                // for the timer, which keeps its compare out of their paths.
                ic_wd <= iEdb;
                ic_wa <= a_r[IC_AW:1]; ic_wt <= ic_want;
                ic_wt[TAGW-1] <= eRWn;   // a write only invalidates
                dc_wa <= a_r[IC_AW:1]; dc_wt <= ic_want; dc_wd <= iEdb;
                dc_wt[TAGW-1] <= eRWn;   // a write only invalidates
                k_din <= bus_berr ? 16'hFFFF : iEdb;
                if (tmr >= DATA_DELAY - 1) begin
                    // Cache fill on a fetch miss; invalidate on any write.
                    // (step 11: ic_okf, so chip RAM code fills it and a CPU
                    // write to chip RAM drops the entry)
                    if (ic_okf && !ic_flush
                        && (!eRWn || (cyc_fetch && ic_on && !k_cacr[1] && !bus_berr)))
                        ic_we <= 1'b1;
                    // Data cache: invalidate on a write; fill on a whole-
                    // word read (a byte read over the motherboard bus need
                    // not drive the other byte).
                    if (DCACHE != 0 && ic_ok
                        && (!eRWn || (!cyc_fetch && dc_on && !bus_berr && !uds_want && !lds_want)))
                        dc_we <= 1'b1;
                    k_berr <= bus_berr;   // seen by the clkena that ends the cycle
                    as_i   <= 1'b1;
                    uds_i  <= 1'b1;
                    lds_i  <= 1'b1;
                    tmr   <= 6'd0;
                    q     <= Q_FINISH;
                end
            end
            // ----------------------------------------------------------
            // R/W, address and write data stay where they are: a slave may
            // latch a write on the AS rising edge, and the bridge holds the
            // motherboard copy for one more clock. They change only when
            // the next cycle is set up, >= SETTLE clocks from now.
            Q_FINISH: if (tmr >= DIN_SETUP - 1 && cnt >= STEP - 1) step();
            default: q <= Q_SETTLE;
            endcase

            // Posted writes and prefetches complete in the background. (A
            // read's second ack pulse, one clock after the first, arrives
            // with dp_kind already 0 and is ignored.)
            if (dp_ack && dp_kind == 2'd2) begin
                dp_req_i <= 1'b0; dp_busy <= 1'b0; dp_kind <= 2'd0;
            end
            // pf_d follows the SDRAM data all through a prefetch (pf_valid
            // is 0 until its ack, the last load); DDATA loads it as well
            if (dp_kind == 2'd3) pf_d <= dp_rdata;
            if (dp_ack && dp_kind == 2'd3) begin
                dp_req_i <= 1'b0; dp_busy <= 1'b0; dp_kind <= 2'd0;
                dp_inc   <= 1'b0;
                pf_valid <= 1'b1;
                dp_q <= dp_rdata;          // for the data-cache fill
                pf_fill <= pf_dc;
            end

            // Stall watchdog (diagnostic only): a cycle no slave answers.
            if (q == Q_WAIT || q == Q_DWAIT || q == Q_CFREE) begin
                if (!wd[23]) wd <= wd + 24'd1;
                else         stalled <= 1'b1;
            end else begin
                wd <= 24'd0;
                stalled <= 1'b0;
            end
        end

        // Cache flush: after any reset (external, or the RESET instruction,
        // which re-runs autoconfig). Takes 2^IC_AW clocks (~48 us at 8 KB);
        // the cache is simply off meanwhile. Flush writes win the RAM port:
        // fills are already blocked, and an invalidate lost here is covered
        // by the sweep.
        // Both caches share the sweep. MapROM switching on or off changes
        // what the ROM addresses return, so it flushes too.
        if (flush_trig) begin
            ic_flush <= 1'b1;
            ic_fcnt  <= {IC_AW{1'b0}};
        end else if (ic_flush) begin
            ic_we   <= 1'b1;
            ic_wa   <= ic_fcnt;
            ic_wt   <= {TAGW{1'b0}};
            dc_we   <= 1'b1;
            dc_wa   <= ic_fcnt;
            dc_wt   <= {TAGW{1'b0}};
            ic_fcnt <= ic_fcnt + 1'b1;
            if (&ic_fcnt) ic_flush <= 1'b0;
        end

        // nReset is released on a clkena edge so it is stable for the
        // kernel's next STEP clocks.
        if (!extReset && k_step) k_nreset <= 1'b1;
    end

    // One kernel step. IPL is re-sampled on the same edge so it is stable
    // for the next STEP clocks; base64_top already debounces it on the 7M
    // grid. berr is held for exactly the step that consumes it.
    task step;
        begin
            k_clkena <= 1'b1;
            k_step   <= 1'b1;
            k_clkena_lw <= !k_longword || k_long_ack; k_clkena_lw2_n <= !(!k_longword || k_long_ack); k_clkena_lw3 <= !k_longword || k_long_ack;
            cnt      <= 6'd0;
            k_ipl    <= {IPL2n, IPL1n, IPL0n};
            k_berr   <= 1'b0;     // the kernel samples the old value here
            q        <= Q_SETTLE;
            dec_r    <= 1'b0;
            // FETCH PREDICTOR: the cache is read at fp_a next (ic_ra takes
            // it while k_step is high)
            fp_v     <= 1'b0;
            fp_kill  <= 1'b0;
        end
    endtask



    initial begin
        ASn = 1'b1; UDSn = 1'b1; LDSn = 1'b1; eRWn = 1'b1;
        BGn = 1'b1; oRESETn = 1'b1; oEdb = 16'd0; stalled = 1'b0;
        dp_inc = 1'b0; dp_pair = 1'b0; dp_wdata_lo = 16'd0;
    end

`ifndef YOSYS
    // step 15, sim only: on a predicted fetch, the RAMs' own read of the
    // kernel's address (on the edge into DECIDE, as for a normal lookup)
    // must show a matching tag and the same word, in a cacheable window
    // (ic_ok_d decodes the kernel's address every clock)
    integer fp_chk_bad = 0, fp_hits = 0;
    always @(posedge clk)
        if (!extReset && q == Q_DECIDE && !internal_step && fp_hit) begin
            fp_hits = fp_hits + 1;
            if ((k_addr[1] ? ic_tq_o : ic_tq_e) != tag_of(k_addr[31:1])
                || (k_addr[1] ? ic_dq_o : ic_dq_e) != k_din_fp || !k_din_psel
                || k_din_sel || k_din_hsel || k_din_dsel || k_long_ack) begin
                fp_chk_bad = fp_chk_bad + 1;
                if (fp_chk_bad <= 5) $display("%0t: tg68_bus: predicted fetch at %h differs from the cache", $time, {k_addr[31:1], 1'b0});
            end
        end
    // step 14, sim only: in CCMP the registered compare inputs must equal
    // what a_r and the cache-on registers give (cc_on_k may only be 0 where
    // the live term is 1); the benches fail if cc_bad is not 0
    integer cc_bad = 0;
    wire    cc_on_live = ic_ok_d && (cyc_fetch ? ic_on : dc_on);
    always @(posedge clk)
        if (q == Q_CCMP && (cc_want_k != ic_want || cc_sel_k != a_r[1]
                            || (cc_on_k && !cc_on_live))) begin
            cc_bad = cc_bad + 1;
            if (cc_bad <= 5) $display("%0t: tg68_bus: CCMP compare inputs differ from a_r", $time);
        end
`endif
endmodule

`default_nettype wire
