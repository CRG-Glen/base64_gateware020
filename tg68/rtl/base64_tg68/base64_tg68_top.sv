// ============================================================================
// base64_tg68_top.sv — Base64 carrier + iCESugar-Pro with the TG68K.C core in
// 68020 mode, for the open-source flow (yosys + nextpnr-ecp5).
//
// This is base64_top.sv from the fx68k build with the CPU swapped. The bus
// bridge, cold-boot handling, fast RAM, turbomem ROM board and SD card are
// unchanged; tg68_bus.v makes TG68K look like fx68k's port list. Changes
// against the fx68k file are all marked "TG68:".
//
//   TG68: ENABLE_FASTMEM / ENABLE_SD  build-time switches for the slaves
//   TG68: hi_null                     answers 32-bit space nobody decodes
//   TG68: FORCE_RETRY_MS              cold-boot retry without a halt signal
//   TG68: led_r                       also lights if a bus cycle stalls
//
// --- original fx68k header follows ---
// base64_top_6x.sv — Base64 carrier + iCESugar-Pro, TURBO MODE (6x = 42.6 MHz)
//
// fx68k runs at CPU_MULT x the motherboard 7M rate. Every cycle that has to
// reach the Amiga is re-issued by a BUS BRIDGE (BIU) that reproduces a real
// 68000 S0..S7 bus cycle on the 7M grid. The core is held in wait states
// (DTACK withheld) until the bridge completes.
//
// ARCHITECTURAL NOTE — THIS IS NOT A CLOCK DOMAIN CROSSING.
//   There is exactly ONE clock in this design: clk_12x. The 7M "domain" is a
//   set of clock enables derived from a divide-by-12 counter that is phase-
//   locked to the motherboard 7M. The fast CPU "domain" is another set of
//   enables (clk/2). Handshakes between them are ordinary synchronous logic:
//   no metastability, no gray coding, no request/ack synchronisers. The only
//   true asynchronous inputs are the motherboard pins (DTACK/VPA/BERR/BR/
//   BGACK/IPL/RESET/HALT and the 7M clock itself), which are the only places
//   that need 2FF synchronisers.
//
// WHAT CHANGED vs THE 1x BUILD (all of these silently break at 6x):
//   1. E is generated HERE at 7M/10 (6 low / 4 high). The core's own E runs
//      CPU_MULT times too fast and is discarded.
//   2. VPA/VMA 6800-style cycles are run by the bridge against OUR E, not by
//      the core. The core's VPAn is tied deasserted.
//   3. IACK cycles terminate with DTACK + autovector number (24+level), which
//      is behaviourally identical to a VPA autovector but needs no E timing.
//   4. The RESET instruction is stretched to >=124 * 141 ns. At 6x the core
//      only holds oRESETn for ~2.9 us, which is too short to reset the CIAs.
//   5. IPL is re-sampled on the 7M grid with a 2-of-2 filter. At 6x the
//      core's own two-sample debounce window shrinks to 47 ns and would latch
//      Paula's INTREQ update glitches.
//   6. BG is retimed onto the 7M grid.
//   7. The bridge, not the core, owns the physical pins (latched address /
//      data / strobes), because the core moves on as soon as it is acked.
//   8. VMA is held past E's FALLING edge (VMA_HOLD). A 6800 peripheral
//      latches write data on that edge with chip select still asserted, and
//      a real 68000 negates VMA in S7, after E is already low. Dropping VMA
//      on the same clock edge E falls leaves zero hold and makes the write
//      depend on Gary's VMA->CS delay versus the E path to the CIA, i.e. on
//      board layout. See section 10b.
//
// PHASE_OFS is KEPT and now has a physical meaning: it aligns our internal
// notion of the 7M rising edge with the real one at Gary/Agnus, absorbing the
// 74LVC1G17 delay, the FPGA input path, the capture pipeline and the output
// path. See DESIGN_NOTES_6x.md for the budget.
//
// Pairs with base64_6x.fdc. Toolchain: Diamond / Synplify Pro.
// fx68k ports match UPSTREAM ijor/fx68k (no E_rise/E_fall, eab[23:1]).
// SDRAM, the turbomem ROM board and the SD card device are all live. The
// autoconfig chain is cfgin -> fastmem -> turbomem -> SD -> cfgout.
// ============================================================================
`default_nettype none

module base64_tg68_top #(
    // TG68: build options ------------------------------------------------
    // ENABLE_FASTMEM: SDRAM fast RAM (Zorro II + 16 MB at $08000000) and the
    //   turbomem DiagArea board that AddMemList()s the 16 MB.
    // ENABLE_SD: SD card autoconfig board + sfsd boot ROM.
    // With both 0 the CPU sees only the motherboard: Chip RAM, Kickstart,
    // custom chips -- the simplest possible bring-up.
    parameter         ENABLE_FASTMEM = 1'b0,
    parameter         ENABLE_SD      = 1'b0,
    // TG68 never halts on a double bus fault, so the cold-boot retry in
    // section 7b could never fire. Instead the first boot attempts are
    // treated as failed until this many ms after the power-up hold. On the
    // fx68k build a reset released > ~0.9 s after power-up always boots.
    // 0 disables. Ctrl-A-A always works regardless.
    parameter integer FORCE_RETRY_MS = 1300,
    // TG68 bus adapter pacing, in 85 MHz clocks (see tg68_bus.v)
    // Set from the routed timing: kernel internal paths ~42 ns, kernel ->
    // adapter ~32 ns, adapter -> kernel ~14 ns. If you change these, change
    // check_timing.py's defaults and the Diamond constraints to match.
    parameter integer TG_STEP    = 4,
    parameter integer TG_SETTLE  = 3,
    parameter integer TG_DIN     = 1,   // read data -> step (+1: see tg68_bus)
    parameter integer TG_ASU     = 1,   // address -> AS (+1 strobe register)
    // ---- speed ----------------------------------------------------------
    // 12 master clocks per 7M period. CPU_MULT must divide 12 evenly:
    //   6 -> 2 master clocks/CPU clock (42.6 MHz)  <-- target
    //   4 -> 3, 3 -> 4, 2 -> 6, 1 -> 12 (bit-identical to the old build)
    // See DESIGN_NOTES: only CPU_MULT<=3 relaxes the fx68k Fmax requirement.
`ifdef TG68_X16
    // TG68: 16x build (see CLK_MULT below). Unused by the TG68 core (fx68k's
    // phase enables); 8 keeps MC4 = CLK_MULT / CPU_MULT whole.
    parameter integer CPU_MULT   = 8,
`else
    parameter integer CPU_MULT   = 6,
`endif

    // ---- 7M grid alignment ----------------------------------------------
    // Larger PHASE_OFS moves our S-state grid EARLIER relative to the real
    // 7M edge, in 11.75 ns steps. Calibrate once (see notes), then leave it.
    // PWRUP_BIT sets both the power-up hold AND the cold-boot reset pulse.
    //   23 = ~98 ms   24 = ~197 ms   25 = ~394 ms   26 = ~788 ms
    // Raised to 25 while chasing the cold-boot double bus fault: the core was
    // being started before something on the motherboard could answer, and a
    // reset applied later by hand (Ctrl-A-A) always works. Sweep it downwards
    // once the real cause is known -- every step doubles the time from power
    // on to a usable machine.
    parameter integer PWRUP_BIT  = 25,   // sim override only
    // TG68 step 13: 7M edges per speed-switch calibration window (section
    // 3; the power-up window is set by PWRUP_BIT); the sim shortens it
    parameter integer CAL_EDGES  = 65536,
    parameter         COLD_RESET = 1'b1, // FPGA drives /RESET+/HALT at
                                         // power-up; see section 1b
    parameter         COLD_RETRY = 1'b1, // reset again if the core double
                                         // bus faults; see section 7b
    parameter         PASSIVE_EN = 1'b1, // hand the bus over to another
                                         // accelerator holding /BR; see 9b
    parameter [4:0]   PHASE_OFS  = 5'd2,

    // Master clocks between the nominal S4 falling edge and the instant we
    // read the 2FF-synchronised DTACK/VPA/BERR. Set equal to the synchroniser
    // depth (2) so the value we act on is the pin value AT the S4 falling
    // edge — i.e. exactly the sample point of a real 68000.
    // DTACK_LAT positions the sample point. SMP_N master clocks after the
    // S5 tick we read s_dtack_n[1], which lags the pin by 2 -- so DTACK_LAT=2
    // acts on the pin value exactly AT S5, a real 68000's sample point.
    //
    // But a real 68000 drives AS straight off its internal grid, whereas our
    // AS goes out through a pin register, the output buffer (SLEWRATE=SLOW)
    // and a CBTD FET: measured 35.2 ns, i.e. 3 master clocks. Gary's DTACK
    // comes back that much later, so our sample point has to move with it.
    // Hence 2 (synchroniser) + 3 (our AS output delay) = 5, and 4 already
    // recovers the clock in simulation.
    //
    // This is the knob PHASE_OFS cannot substitute for: PHASE_OFS slides the
    // whole grid, moving AS and the sample point together, which is exactly
    // why PHASE_OFS 1 and 2 measured identically on hardware. DTACK_LAT is
    // the only parameter that moves the sample point RELATIVE to AS.
    //
    // Sweep 2..6 and watch LAT_DEBUG: 5 blinks = losing a clock, 4 = fixed.
    // Do not exceed 6 -- the sample must land before the S6 tick.
    parameter integer DTACK_LAT  = 4,

    // Master clocks by which the core's DTACK leads the bridge's data-latch
    // edge. 1 is derived in the notes; 2 buys margin for back-to-back cycles
    // at the cost of nothing. MUST be >=1 and <=5.
    parameter integer ACK_LEAD   = 2,
    // EXPERIMENTAL, DEFAULT OFF -- acking the core the moment DTACK is
    // stable rather than at tick_ack. This is the right IDEA (see the
    // ST_S6 comment) but this implementation is WRONG: Verilator against
    // the real core drops from 50 loop iterations to 1, i.e. the core goes
    // off the rails. Acking this early makes the core negate AS while the
    // bridge is still in S6/S7, and the ack-clear path then races the
    // FSM. Needs the request/ack handshake reworked, not a parameter.
    // EARLY_ACK: DEAD END, leave at 0. Measured, not guessed.
    //
    // The idea was to ack the core as soon as DTACK is stable so it could
    // turn its next cycle around inside our S5/S6/S7. It works in a model
    // where the slave drives read data for the whole of AS-low, and it
    // green-screens real hardware, because real slaves assert DTACK BEFORE
    // the data is on the bus. A 68000 tolerates that: it latches at S7,
    // ~141 ns after DTACK. Acking early collapses that margin to a few
    // master clocks -- at 6x we destroy the exact safety margin the 68000
    // bus protocol is built around.
    //
    // Simulated against the real core, with DTACK at AS+294 ns (as
    // captured on hardware) and data valid only at AS+400 ns:
    //     EARLY_ACK=0 -> 50 loop iterations, clean
    //     EARLY_ACK=1 ->  0 loop iterations, dead
    // Restricting it to writes only is safe but measured no gain at all
    // (34 iterations either way), so it is not worth the complexity.
    // RETIME: 0 = bridge (re-synthesised S0..S7), 1 = SF2000-style
    // pass-through with the core's strobes gated onto the 7M grid.
    parameter         RETIME     = 1'b1,
    // TG68: POSTED CHIP WRITES (step 11). 1 = a CPU write to chip RAM
    // ($000000-$1FFFFF) is acknowledged as soon as it is on the motherboard
    // bus; the bridge finishes it while the CPU carries on, and holds the
    // CPU's next motherboard cycle until it is done (so order is kept).
    // Custom chip and CIA registers are never posted. RETIME=1 only.
    parameter         POST_CHIP  = 1'b1,
    // chip RAM write buffer depth, 1-8 (step 12; 1 = step 11's one posted write)
    parameter integer CHIP_WB    = 8,
    parameter         EARLY_ACK  = 1'b0,
    parameter         DBG_BUNDLE = 1'b0,   // debug done -- keep 0 now

    // e_cnt value at which VMA is asserted during a 6800 cycle. E is low for
    // e_cnt 0..5, high for 6..9, so 1 gives ~700 ns of VMA setup before E
    // rises. Anything in 0..3 is safe.
    parameter [3:0]   E_VMA_AT   = 4'd1,

    // Hold VMA (and therefore AS/DS/RW/data, because the core cannot negate
    // AS before it sees DTACK) for one half 7M period -- 70 ns -- past E's
    // FALLING edge, instead of dropping it on the same clock edge.
    //
    // WHY THIS EXISTS. An 8520 latches a write on E's falling edge with its
    // chip select still asserted. Gary gates CIAA/CIAB CS with VMA, so if
    // VMA is removed on the edge E falls, whether the write lands at all is
    // decided by Gary's VMA->CS propagation against the E distribution path
    // -- a race whose sign changes with board layout and chip lot. A real
    // 68000 negates VMA in S7, with E already low, and has no such race;
    // that is why the fault below appears with this board in the socket and
    // not with the DIP CPU.
    //
    // Symptom it was added for: on remake A500/A500+ boards (A500++,
    // Raemixx500) AmigaTestKit 1.21's CIA Timer Test reported every tick
    // count correct and every IRQ count zero. The only register write that
    // test performs is the CIA ICR mask; lose it and the timers keep
    // counting while the CIA never raises /IRQ, which is exactly that
    // screenshot. Passed on original Commodore Rev 8A and Rev 6A boards.
    //
    // 0 restores the previous behaviour, for A/B testing. Costs 70 ns on a
    // cycle that already takes ~1.4 us, so there is no reason to turn it off
    // other than to reproduce the fault.
    parameter         VMA_HOLD   = 1'b1,

    // Length of the /RESET pulse we drive for a RESET instruction, in 7M
    // clocks. The 68000 spec is 124 (~17.5 us) and 132 is a small margin on
    // top. A parameter so it can be swept on hardware: some expansion boards
    // (DMAC-based controllers, IDE CPLDs) want a longer pulse than the CPU
    // itself does, and the counter is now wide enough to go to ~144 us.
    //
    // Note this is NOT the fix for a machine that drops to the insert-disk
    // screen after a warm reset -- see slave_reset in section 10c for that.
    parameter integer RST_HOLD_7M = 132,

    // 1 = terminate IACK cycles internally with 24+level (recommended).
    parameter         IACK_AV    = 1'b1,

    // 1 = green LED blinks the shortest observed external cycle length in 7M
    // clocks (4 = no wait states, 5 = one wait state, ...).
    parameter         LAT_DEBUG  = 1'b0
)(
    // Clocks from carrier
    input  wire        clk_7m,        // C7  buffered motherboard 7M (74LVC1G17)
    input  wire        clk_12x,       // L1  ICS570B x12 (85.1 MHz, PLL-locked)

    // 68000 socket (3.3V side of the CBTD switches)
    output wire [23:1] cpu_a,
    inout  wire [15:0] cpu_d,
    output wire        cpu_as_n,
    output wire        cpu_uds_n,
    output wire        cpu_lds_n,
    output wire        cpu_rw,        // 1 = read
    output wire [2:0]  cpu_fc,
    output wire        cpu_vma_n,
    output wire        cpu_e,         // free-running E, never tri-stated
    output wire        cpu_bg_n,
    input  wire        cpu_dtack_n,
    input  wire        cpu_vpa_n,
    input  wire        cpu_berr_n,
    input  wire        cpu_br_n,
    input  wire        cpu_bgack_n,
    input  wire [2:0]  cpu_ipl_n,
    inout  wire        cpu_reset_n,   // open-drain bidirectional
    inout  wire        cpu_halt_n,    // open-drain bidirectional

    // Autoconfig daisy chain (J2). CFGIN jumpered to GND = first in chain.
    input  wire        cfgin_n,
    output wire        cfgout_n,

    // CBT switch output enables (active low = connected). U5/U6 hardwired on.
    output wire        cbt_oe_d0_7_n,
    output wire        cbt_oe_d8_15_n,
    output wire        cbt_oe_ctl_hi_n,
    output wire        cbt_oe_a8_17_n,
    output wire        cbt_oe_a1_7_n,

    // Idled in turbo bring-up (ports kept so base64.lpf is unchanged)
    output wire [12:0] sdram_a,   // driven by sdram_ctrl
    output wire [1:0]  sdram_ba,
    inout  wire [15:0] sdram_dq,
    output wire [1:0]  sdram_dqm,
    output wire        sdram_clk,
    output wire        sdram_cke,
    output wire        sdram_ras_n,
    output wire        sdram_cas_n,
    output wire        sdram_we_n,
    output wire        sdram_cs_n,
    output wire        sd_clk,
    inout  wire        sd_cmd,
    inout  wire [3:0]  sd_d,

    output wire        led_r,
    output wire        led_g,
    output wire        led_b
);

    // TG68 step 13: the system clock is 12x, 14x or 16x the 7M, switched at
    // run time by the speed sequencer (section 13, below) through a
    // glitch-free switch (clkgen.v). Power-on: 12x, the pin's own clock. The
    // 16x board-mod build (TG68_X16) has no PLLs: clk is the pin.
    reg  [1:0] clk_sel = 2'd0;
    wire       pll_lock14, pll_lock16;
    wire [1:0] clk_cur;
    wire       clk;
    clkgen #(
`ifdef TG68_X16
        .ENABLE(0)
`else
        .ENABLE(1)
`endif
    ) u_clkgen (.clk_in(clk_12x), .sel(clk_sel), .clk(clk),
                .lock14(pll_lock14), .lock16(pll_lock16), .cur(clk_cur));

    // Master clocks per emulated CPU clock period, and the phi2 offset.
    // Sized localparams throughout: part-selecting an `integer` parameter is
    // legal SV but not portable across synthesis front ends.
    // CLK_MULT is the ICS570B multiplier on the incoming 7M. It is a
    // parameter only so the 24x experiment is a one-line change -- but read
    // DESIGN_NOTES_6x.md before raising it: doubling the master clock does
    // NOT buy fx68k any settling time, it only makes STA harder. The real
    // lever is the multicycle constraints in base64_6x.fdc.
`ifdef TG68_X16
    // TG68: EXPERIMENTAL 16x build (build.py --x16 defines TG68_X16), for a
    // board whose ICS570B is rewired from x12 to x16: 113.50 MHz. A 12x
    // bitstream on such a board runs this bridge's 7M grid at 9.46 MHz (bus
    // cycles 25% short and mostly off phase, E and so the CIA timers 33%
    // fast). Everything 16x-specific is under TG68_X16, so the 12x build is
    // the same text for yosys and stays bit-identical (even dead code or a
    // default-valued parameter moves yosys's names and nextpnr's placement).
    // At 16x: PHASE_OFS stays 2 (it mostly cancels the 7M capture pipeline,
    // ~3 master clocks at any rate; 3 put our AS edges on the 7M edge and
    // the simulated Gary missed AS negations), DTACK_LAT/ACK_LEAD are only
    // used by the RETIME=0 bridge, the address/data hold after AS is 2
    // clocks, the SDRAM runs CL3 and the SD clock's low half is stretched.
    localparam integer CLK_MULT = 16;
`else
    localparam integer CLK_MULT = 12;
`endif
    localparam [4:0] PH_TOP = CLK_MULT[4:0] - 5'd1;      // counter wrap
    localparam [4:0] PH_HALF= CLK_MULT[4:0] / 5'd2;      // "falling edge"
    // TG68 step 13: what depends on the clock multiplier, as registers set
    // from the speed in force (spd: 0 12x, 1 14x, 2 16x). They change only
    // in the speed switch, with the CPU held and both buses idle, so their
    // paths are quasi-static (check_timing.py class STATIC). The 16x
    // board-mod build has fixed 16x values.
    reg  [1:0]  spd = 2'd0;
    reg         spd_unlock = 1'b0;   // keep the 7M aligner re-acquiring (switch)
    reg         cal_go     = 1'b0;   // sequencer: calibrate the 7M capture
    reg         swap_go    = 1'b0;   // step 14: sequencer: use the other 7M stream
    wire        swap_req;            // step 14: the stream in use drifts (below)
    wire [7:0]  n_swap;              // step 14: automatic stream swaps so far
    localparam integer AUTO_N = 4;   // moves of the stream in use that trigger a swap
    wire        cal_busy, cal_clr;
    wire [1:0]  spd_smp;             // speed register: 0 auto, 1 rise, 2 fall
    reg         spd_hold   = 1'b0;   // hold the CPU's bus cycles (switching)
    wire        cpu_cyc_idle;        // the adapter: no cycle, SDRAM port free
    wire        spd_wr;              // turbomem +$F00A: a keyed speed write
    wire [1:0]  spd_val;
    wire [15:0] spd_stat;
    reg         sdram_cfg_req = 1'b0, sdram_cfg_cl3 = 1'b0;
    wire        sdram_cl3;           // the SDRAM's CAS latency in force is 3
`ifdef TG68_X16
    wire [4:0]  ph_top    = PH_TOP;
    wire [4:0]  ph_half   = PH_HALF;
    wire [16:0] ms_top    = 17'd113500;
    wire        spd_hold2 = 1'b1;      // 2-clock rt_ hold after AS
    wire        spd_lox   = 1'b0;      // (the SD stretch is SD_LO_EXTRA there)
    wire        spd_rfc   = 1'b0;
`else
    reg  [4:0]  ph_top    = 5'd11;
    reg  [4:0]  ph_half   = 5'd6;
    reg  [16:0] ms_top    = 17'd85129;
    reg         spd_hold2 = 1'b0;
    reg         spd_lox   = 1'b0;
    reg         spd_rfc   = 1'b0;   // exp-18x
    always @(posedge clk) begin
        // exp-18x: speed code 1 is 18x (was 14x: 13 / 7 / 99318)
        ph_top    <= (spd == 2'd2) ? 5'd15 : (spd == 2'd1) ? 5'd17 : 5'd11;
        ph_half   <= (spd == 2'd2) ? 5'd8  : (spd == 2'd1) ? 5'd9  : 5'd6;
        // 1 ms: 85.13 / 99.32 / 113.51 MHz
        ms_top    <= (spd == 2'd2) ? 17'd113507 : (spd == 2'd1) ? 17'd127695 : 17'd85129;
        // address/data hold past AS: 1 clock (11.75 ns) at 12x, 2 above
        spd_hold2 <= (spd != 2'd0);
        // SD clock: stretch the low half at 16x (see shifter.v)
        spd_lox   <= (spd != 2'd0);     // exp-18x: 16x and 18x
        spd_rfc   <= (spd == 2'd1);     // exp-18x: SDRAM tRFC + 1 clock at 18x
    end
`endif
    localparam [4:0] MC4    = CLK_MULT[4:0] / CPU_MULT;      // 2,3,4,6,12
    localparam [4:0] MCH4   = (CLK_MULT[4:0] / CPU_MULT) / 5'd2;
    localparam [4:0] PH_ACK = PH_HALF - ACK_LEAD;
    localparam [2:0] SMP_N  = DTACK_LAT;
    // CPU_MULT must divide CLK_MULT evenly and give an even MC4.

    // ========================================================================
    // 1. Power-up hold
    // ========================================================================
    // ~98 ms after configuration before the core's first fetch: rails,
    // ICS570B lock and the Amiga's own POR are all settled. Runs once per
    // FPGA configuration; warm resets are unaffected.
    // PWRUP_BIT is a parameter so simulation can shorten the hold, and so the
    // cold-boot pulse length can be swept. It also sets the pulse length.
    //
    // THE COUNTER IS SIZED FROM THE PARAMETER, deliberately. It used to be a
    // fixed reg [23:0], and raising PWRUP_BIT to 25 selected a bit that does
    // not exist. Verilog returns constant 0 for an out-of-range bit select,
    // so pwrup_done never asserted, ext_reset was stuck asserted, fx68k
    // constant-folded away, and the FPGA held /RESET and /HALT low forever --
    // a 29-SLICE bitstream and a machine that could not even be rescued by
    // Ctrl-A-A. Synplify says so plainly and it is easy to miss:
    //
    //   WARNING - CS101 : Index 25 is out of range for variable pwrup_cnt
    //
    // Treat CS101 as fatal in any build check, alongside CG371 and BN105.
    reg  [PWRUP_BIT:0] pwrup_cnt = 0;
    wire               pwrup_done = pwrup_cnt[PWRUP_BIT];
    always @(posedge clk)
        if (!pwrup_done) pwrup_cnt <= pwrup_cnt + 1'b1;

    // ========================================================================
    // 1b. Cold-boot reset pulse — the FPGA is the reset SOURCE
    // ========================================================================
    // THE PROBLEM. On a cold start the Amiga's power-on reset finishes while
    // the ECP5 is still loading its bitstream from SPI flash. The motherboard
    // then sits for a few hundred milliseconds with no CPU at all, and when
    // fx68k finally comes out of the power-up hold it is stepping into a
    // machine whose CIAs and custom chips were reset long ago and were never
    // released in step with a CPU. Warm reset (Ctrl-A-A) works precisely
    // because everything is reset TOGETHER.
    //
    // THE FIX. Drive /RESET and /HALT low for the whole power-up hold, then
    // release. The machine is then reset by us, with the CPU present, which
    // is the same condition a warm reset produces. Costs no extra state: the
    // hold already exists and pwrup_done latches high for good, so this runs
    // exactly once per FPGA configuration and a later Ctrl-A-A or RESET
    // instruction cannot re-trigger it.
    //
    // BOTH lines are required. The 68000 takes an external reset only when
    // /RESET and /HALT are asserted together — /RESET alone is what a RESET
    // instruction does, and would reset the peripherals but not us. This is
    // the one place we legitimately drive /HALT, and it is a machine reset,
    // not a consequence of a halt, so it does not violate the independence
    // rule stated in section 7.
    //
    // The release is self-timed and needs no ordering logic. ext_reset is
    // built from the SYNCHRONISED pins, so when we stop driving, fx68k stays
    // in reset until the real bus lines have actually risen through the
    // motherboard's pull-ups. The core cannot start before the machine does.
    //
    // The CBT question is settled: base64.lpf line 163 records /RESET and
    // /HALT on U5, whose OE is hardwired to GND. The pulse reaches the bus.
    //
    // Set COLD_RESET = 1'b0 to bisect this back out in one line.
    wire cold_rst = COLD_RESET & ~pwrup_done;

    // ------------------------------------------------------------------
    // ...and do not let the core start until the machine has ACTUALLY come
    // out of reset.
    //
    // Releasing the pulse is not the same as the bus being released. The
    // Amiga's own power-on reset can outlast our hold, and on this board
    // /HALT is pulled up and driven by nothing except us -- so the moment we
    // stop driving, /HALT goes high while /RESET may still be held low by
    // the motherboard. ext_reset's normal term needs BOTH low, so it would
    // deassert and the core would start into a machine that is still in
    // reset: ROM fetches work, every custom chip and CIA does not.
    //
    // cold_armed holds the core until both lines have been observed high at
    // least once after the hold. It is a ONE-SHOT and latches off for good,
    // because after this a RESET instruction drives /RESET alone for ~17.5 us
    // (rst_stretch) and must never be able to reset the core.
    //
    // No deadlock: if something else holds /RESET low forever the core waits,
    // but so would a real 68000, and a Ctrl-A-A still clears it.
    // ------------------------------------------------------------------
    reg cold_armed = 1'b1;

    // ========================================================================
    // 2. Asynchronous input synchronisers (the ONLY real CDC in the design)
    // ========================================================================
    reg [1:0] s_dtack_n, s_vpa_n, s_berr_n, s_br_n, s_bgack_n;
    reg [1:0] s_reset_n, s_halt_n, s_cfgin_n, s_7m;
    reg [2:0] s_ipl_a, s_ipl_b;

    // 7M capture hardening: the ICS570B is a zero-delay multiplier, so 7M
    // edges arrive coincident with clk_12x edges. Sampling on the FALLING
    // edge puts the sample 5.86 ns away from that coincidence — far outside
    // routing variation — making the captured cycle deterministic across
    // builds and seeds. (This is why PHASE_OFS stopped moving between builds.)
    reg s_7m_fall;
    always @(negedge clk) s_7m_fall <= clk_7m;
    // TG68 step 13: a second stream sampled on the RISING edge. The clock now
    // reaches the flops through the speed multiplexer (clkgen.v), whose
    // fabric delay (~5-6 ns modelled at 12x, different for each source and
    // placement) moves the falling-edge sample by up to half a period, onto
    // a 7M transition. The two samples are half a clock apart, so one of
    // them is always >= T/4 from a transition; the calibration below picks
    // one that is stable.
    reg       s_7m_rise;
    reg [1:0] s_7m_r;
    reg       s_7m_rd;
    always @(posedge clk) s_7m_rise <= clk_7m;

    reg s_7m_d;
    always @(posedge clk) begin
        s_dtack_n <= {s_dtack_n[0], cpu_dtack_n};
        s_vpa_n   <= {s_vpa_n[0],   cpu_vpa_n};
        s_berr_n  <= {s_berr_n[0],  cpu_berr_n};
        s_br_n    <= {s_br_n[0],    cpu_br_n};
        s_bgack_n <= {s_bgack_n[0], cpu_bgack_n};
        s_reset_n <= {s_reset_n[0], cpu_reset_n};
        s_halt_n  <= {s_halt_n[0],  cpu_halt_n};
        s_cfgin_n <= {s_cfgin_n[0], cfgin_n};
        s_7m      <= {s_7m[0],      s_7m_fall};
        s_7m_r    <= {s_7m_r[0],    s_7m_rise};
        s_7m_rd   <= s_7m_r[1];
        s_ipl_a   <= cpu_ipl_n;
        s_ipl_b   <= s_ipl_a;
        s_7m_d    <= s_7m[1];

        if (cold_armed && pwrup_done && s_reset_n[1] && s_halt_n[1])
            cold_armed <= 1'b0;
    end
    // The rising stream has the same flops after its sample, so it sees a
    // 7M edge in the same clock as the falling one or one clock later.
    wire edge_7m_f = s_7m[1] & ~s_7m_d;
    wire edge_7m_r = s_7m_r[1] & ~s_7m_rd;
    reg  smp_r = 1'b0;                  // step 13: the stream in use (below)
    wire edge_7m = smp_r ? edge_7m_r : edge_7m_f;

    // ========================================================================
    // 3. 7M grid: divide-by-12, phase-locked, GLITCH IMMUNE
    // ========================================================================
    // The old code reloaded ph_cnt on EVERY 7M edge. With a locked ICS570B
    // that reload is a no-op, but a single jittery or noisy edge would jump
    // the counter — and if the CPU phases were derived from it, that jump
    // would emit two consecutive enPhi1 (or swallow one) and corrupt fx68k.
    // Here the counter free-runs and only hard-reloads after SLIP_TOL
    // consecutive disagreements, i.e. a genuine PLL slip rather than noise.
    // The CPU phase generator (section 4) is independent of it regardless.
    localparam integer SLIP_TOL = 3;

    reg [4:0] ph        = 5'd0;
    reg [1:0] slip_cnt  = 2'd0;
    reg       ph_locked = 1'b0;
    reg       ph_slip   = 1'b0;     // sticky, for LED/Reveal

    always @(posedge clk) begin
        ph <= (ph == ph_top) ? 5'd0 : ph + 5'd1;
        if (edge_7m) begin
            // TG68 step 13: the reload below makes ph PHASE_OFS in the clock
            // AFTER the edge, so an aligned edge finds ph = PHASE_OFS - 1.
            // This compared with PHASE_OFS, never matched, and the aligner
            // re-acquired on every edge (harmless while the edge never
            // moves, but SLIP_TOL's noise immunity never worked). Same grid.
            if (ph == PHASE_OFS - 5'd1) begin
                slip_cnt  <= 2'd0;
                ph_locked <= 1'b1;
            end else begin
                if (!ph_locked) begin
                    ph <= PHASE_OFS;                 // initial acquisition
                end else if (slip_cnt == SLIP_TOL[1:0]) begin
                    ph       <= PHASE_OFS;           // real slip: re-acquire
                    slip_cnt <= 2'd0;
                    ph_slip  <= 1'b1;
                end else begin
                    slip_cnt <= slip_cnt + 2'd1;     // noise: ignore
                end
            end
        end

        // DO NOT LOCK UNTIL THE CLOCK IS TRUSTWORTHY.
        //
        // This block used to lock on the first matching 7M edge after
        // configuration -- within a couple of microseconds, long before the
        // ICS570B is guaranteed settled. Lock to a bad phase and every
        // motherboard cycle is sampled off the 7M grid: DTACK lands in the
        // wrong place, the reset vector reads garbage, and the core takes an
        // address error inside exception processing, which is a double bus
        // fault. That is exactly the cold-boot failure.
        //
        // The evidence it really happens: ph_slip is sticky, and a cold boot
        // was observed reaching a working desktop with red lit -- the core
        // was not halted, so that red could only be ph_slip. The aligner had
        // locked wrongly, then re-acquired once the clock settled.
        //
        // Keeping ph_locked clear through the hold means it re-acquires on
        // every 7M edge and only latches once pwrup_done says the clock has
        // been stable for PWRUP_BIT worth of time. Clearing ph_slip here too
        // makes it mean what the LED claims: a slip AFTER the clock was
        // trusted. Placed last so its assignments win over the block above.
        // TG68 step 13: after a clock switch the period count changed, so the
        // phase is acquired again (ph_slip is not touched: not a slip)
        if (spd_unlock) ph_locked <= 1'b0;   // held through switch + calibration
        if (cal_clr)    ph_slip   <= 1'b0;
        if (!pwrup_done) begin
            ph_locked <= 1'b0;
            ph_slip   <= 1'b0;
            slip_cnt  <= 2'd0;
        end
    end

    // ------------------------------------------------------------------
    // TG68 step 13: 7M capture calibration. A stream that samples near a 7M
    // transition sees the edge one clock early or late at random; a stable
    // one sees it at the same count of a free-running mod-(ph_top+1)
    // counter every time. A window counts, for both streams, the edges whose
    // count differs from the previous one; then the falling stream is used
    // unless it moved more than the rising one (so it stays the choice
    // wherever it is clean: closest to the old grid). The speed register
    // can force either.
    //   power-up: one window over the third quarter of the power-up hold
    //     (~0.33 s, ~2.3M 7M edges; the first half is left to the ICS570B
    //     to settle), deciding ~0.33 s before the CPU starts
    //   speed switch: CAL_N edges (65536, ~9 ms) while the sequencer holds
    //     the CPU and keeps the aligner re-acquiring
    // Step 13's first build used 2048-edge windows: on hardware at 12x the
    // falling sample (~0.5 ns from a transition) passed one and moved
    // later, while the rising one never moved. After a window,
    // cal_jf/cal_jr stay as sticky flags of any later movement, for the
    // speed register (diagnosis).
    // ------------------------------------------------------------------
`ifdef TG68_X16
    // board-mod build: the clock is the pin, the falling sample is centred
    assign cal_busy = 1'b0;
    assign cal_clr  = 1'b0;
    wire   cal_jf = 1'b0, cal_jr = 1'b0;
    assign swap_req = 1'b0;
    assign n_swap   = 8'd0;
`else
    localparam integer CAL_N = CAL_EDGES;   // 65536: 9.2 ms at 7M
    // the power-up window: from half to three quarters of the hold
    wire        pw_beg = pwrup_cnt[PWRUP_BIT-1];
    wire        pw_end = pwrup_cnt[PWRUP_BIT-1] & pwrup_cnt[PWRUP_BIT-2];
    reg         pw_beg_d = 1'b0;
    reg  [4:0]  fr     = 5'd0;
    reg  [4:0]  fr_f   = 5'd0, fr_r = 5'd0;
    reg  [16:0] cal_n  = 17'd0;
    reg  [7:0]  jit_f  = 8'd0, jit_r = 8'd0;   // saturating (step 14: 8 bits)
    reg         cal_on = 1'b0, cal_sp = 1'b0, cal_pr = 1'b0;
    reg         cal_jf = 1'b0, cal_jr = 1'b0;
    reg         cal_st = 1'b0;          // start a window (registered)
    reg  [7:0]  n_swap_r = 8'd0;        // step 14: automatic swaps since power-up
    wire        cal_end = cal_sp ? (edge_7m_f && cal_n == CAL_N[16:0])
                                 : (pw_end || pwrup_done);
    always @(posedge clk) begin
        fr       <= (fr == ph_top) ? 5'd0 : fr + 5'd1;
        pw_beg_d <= pw_beg;
        cal_st   <= cal_go || (pw_beg && !pw_beg_d && !pwrup_done);
        if (edge_7m_f) begin
            fr_f <= fr;
            if (fr != fr_f) begin
                if (cal_pr && jit_f != 8'hFF) jit_f <= jit_f + 8'd1;
                if (cal_pr) cal_jf <= 1'b1;
            end
        end
        if (edge_7m_r) begin
            fr_r <= fr;
            if (fr != fr_r) begin
                if (cal_pr && jit_r != 8'hFF) jit_r <= jit_r + 8'd1;
                if (cal_pr) cal_jr <= 1'b1;
            end
        end
        // step 14: the sequencer swaps streams (CPU held, aligner
        // re-acquiring) when the one in use has drifted onto a 7M edge; the
        // movement counts and flags restart for the new choice
        if (swap_go) begin
            smp_r  <= !smp_r;
            jit_f  <= 8'd0;   jit_r  <= 8'd0;
            cal_jf <= 1'b0;   cal_jr <= 1'b0;
            if (n_swap_r != 8'hFF) n_swap_r <= n_swap_r + 8'd1;
        end
        if (cal_st) begin
            cal_on <= 1'b1;
            cal_sp <= pwrup_done;           // started by the sequencer
            cal_n  <= 17'd0;
            cal_pr <= 1'b0;
            jit_f  <= 8'd0;   jit_r  <= 8'd0;
            cal_jf <= 1'b0;   cal_jr <= 1'b0;
        end else if (cal_on) begin
            if (edge_7m_f && !cal_n[16]) cal_n <= cal_n + 17'd1;
            if (edge_7m_f && cal_n == 17'd2) cal_pr <= 1'b1;  // both streams seen once
            if (cal_end) begin
                cal_on <= 1'b0;
                // step 14: at 12x the rising sample unless it moved more:
                // the speed mux delays the 12x clock by ~5-6 ns on every
                // build, about half a period, which puts the falling sample
                // next to a 7M edge (on hardware it passed the power-up
                // window and drifted later, $270C; rising forced never
                // moved). 14x/16x: the falling one unless it moved more.
                smp_r  <= (spd_smp == 2'd1) ? 1'b1
                        : (spd_smp == 2'd2) ? 1'b0
                        : (spd == 2'd0) ? !(jit_r > jit_f)
                        : (jit_f > jit_r);
            end
        end
    end
    assign cal_busy = cal_on || cal_st;
    assign cal_clr  = cal_st;
    assign n_swap   = n_swap_r;
    // step 14: the stream in use has moved AUTO_N times since the last
    // calibration or swap and the other has not moved at all (drift, e.g.
    // as the FPGA warms up; not forced from the speed register)
    assign swap_req = pwrup_done && !cal_busy && cal_pr && (spd_smp == 2'd0)
                   && (smp_r ? (jit_r >= AUTO_N[7:0] && jit_f == 8'd0)
                             : (jit_f >= AUTO_N[7:0] && jit_r == 8'd0));
`endif

    // The two 7M half-clock ticks, and the early tick used to lead the ack.
    wire tick_r   = (ph == 5'd0);      // "rising edge of 7M"  -> S0,S2,S4,S6
    // TG68: tick_rq = tick_r as a register (ph's next value is 0: it wraps
    // and no 7M edge re-acquires it; PHASE_OFS is never 0). The posted-write
    // sequencer (POST_CHIP) uses it, so the pin registers it loads (address,
    // FC, R/W, strobes) don't wait on the 5-bit phase compare: that path
    // failed 1T by 0.5 ns. The top tb asserts tick_rq == tick_r every clock.
    reg  tick_rq  = 1'b1;               // ph starts at 0
    always @(posedge clk)
        tick_rq <= (ph == ph_top) && !(edge_7m && (!ph_locked || slip_cnt == SLIP_TOL[1:0]));
    wire tick_f   = (ph == ph_half);      // "falling edge of 7M" -> S1,S3,S5,S7
    wire tick_ack = (ph == PH_ACK);    // tick_f minus ACK_LEAD master clocks

    // ========================================================================
    // 4. CPU phase generator — FREE RUNNING, decoupled from the 7M resync
    // ========================================================================
    // Exactly clk/MC, so the emulated CPU clock is exactly CPU_MULT x 7M.
    // Deliberately NOT reloaded by edge_7m: the core does not need to be
    // phase-aligned to the bus any more (the bridge is), and a reload could
    // break the strict phi1/phi2 alternation fx68k requires.
    reg [4:0] cpu_ph = 5'd0;
    always @(posedge clk)
        cpu_ph <= (cpu_ph == MC4 - 5'd1) ? 5'd0 : cpu_ph + 5'd1;

    wire en_phi1 = (cpu_ph == 4'd0);
    wire en_phi2 = (cpu_ph == MCH4);

    // ========================================================================
    // 5. E clock — 7M/10, six low then four high. NEVER tri-stated.
    // ========================================================================
    reg  [3:0] e_cnt = 4'd0;
    reg        e_pin = 1'b0;
    wire [3:0] e_nxt = (e_cnt == 4'd9) ? 4'd0 : e_cnt + 4'd1;
    always @(posedge clk) if (tick_r) begin
        e_cnt <= e_nxt;
        e_pin <= (e_nxt >= 4'd6);
    end
    wire e_fall_tick = tick_r & (e_cnt == 4'd9);   // E goes low on this tick

    // ========================================================================
    // 6. IPL: re-pace onto the 7M grid with a 2-of-2 stability filter
    // ========================================================================
    reg [2:0] ipl_g1 = 3'b111, ipl_g2 = 3'b111, ipl_out = 3'b111;
    always @(posedge clk) if (tick_r) begin
        ipl_g1 <= s_ipl_b;
        ipl_g2 <= ipl_g1;
        if (ipl_g1 == ipl_g2) ipl_out <= ipl_g1;
    end

    // ========================================================================
    // 7. Reset / halt
    // ========================================================================
    wire core_oreset_n, core_ohalted_n;

    // Stretch the RESET instruction to >=124 real 7M clocks (~17.5 us).
    // Length is the RST_HOLD_7M parameter; the counter is 10 bits so it can
    // be raised well past the default without another edit here.
    reg        rst_stretch = 1'b0;
    reg  [9:0] rst_cnt     = 10'd0;
    always @(posedge clk) begin
        if (!pwrup_done) begin
            rst_stretch <= 1'b0;
            rst_cnt     <= 10'd0;
        end else if (!core_oreset_n) begin
            rst_stretch <= 1'b1;
            rst_cnt     <= 10'd0;
        end else if (rst_stretch && tick_r) begin
            if (rst_cnt >= RST_HOLD_7M[9:0]) rst_stretch <= 1'b0;
            else                             rst_cnt <= rst_cnt + 10'd1;
        end
    end

    // ------------------------------------------------------------------
    // /RESET and /HALT are SEPARATE nets on this board, which lets us use
    // real 68000 semantics and delete two hacks that the shared-net
    // assumption had forced:
    //
    //   * The 68000 resets from outside ONLY when /RESET and /HALT are
    //     asserted TOGETHER. A RESET instruction drives /RESET alone, so it
    //     cannot reset us -- no "ignore external reset while we drive it"
    //     guard is needed, and the old we_drive_rst mask is gone. If the
    //     user hits Ctrl-A-A midway through our stretch, /HALT goes low too
    //     and we reset, which is exactly correct.
    //
    //   * The halt watchdog is deleted. It existed to catch a missed cold
    //     boot; warm boot is the agreed bring-up path for now. Nothing
    //     auto-resets the machine any more, so a genuine double bus fault
    //     now HALTS and stays halted -- which is what a real 68000 does and
    //     is far easier to debug than a box that silently reboots itself.
    //     The red LED reports it (section 12).
    // ------------------------------------------------------------------
    // TG68 step 13: registered. As a combinational OR of four registers it
    // put two LUT levels in front of a fan-out to most of the design, and
    // its 1T paths missed on several seeds once step 13 had grown the
    // chip. One clock more reset latency is nothing next to a reset.
    wire ext_reset_c = (~s_reset_n[1] & ~s_halt_n[1]) | ~pwrup_done | cold_armed;
    reg  ext_reset = 1'b1;
    always @(posedge clk) ext_reset <= ext_reset_c;

    // Open-drain, and strictly independent: we never drive /HALT because of
    // a RESET instruction, and never drive /RESET because of a halt.
    // ========================================================================
    // 7b. Cold-boot retry
    // ========================================================================
    // WHAT WE KNOW FOR CERTAIN, and it is the only solid fact left: a reset
    // applied by hand AFTER the core has halted always works. Cold boot never
    // does. Elapsed time is NOT the variable -- the power-up hold was taken
    // from ~98 ms to ~394 ms with no change whatsoever.
    //
    // So this reproduces the one thing that works. If the core double bus
    // faults, wait, drive /RESET and /HALT low again, and let it try once
    // more. Up to RETRY_MAX attempts, ~788 ms apart.
    //
    // This is a WORKAROUND, not a diagnosis, and it is also an experiment
    // whose outcome is informative either way:
    //
    //   boots on attempt 1 or 2   the requirement is simply "another reset,
    //                             later" -- and since 394 ms was not enough,
    //                             the threshold is somewhere above that.
    //   never boots, any number   our reset is NOT equivalent to a keyboard
    //   of attempts               reset. That is a much bigger clue and it
    //                             moves the search to what Ctrl-A-A does
    //                             that driving the CPU socket does not.
    //
    // It disarms permanently once the core has run for ~1.6 s without
    // halting, so a genuine double bus fault later in a session is left
    // alone and still shows as a steady red LED, exactly as before. Watch
    // the blue LED: each attempt is a visible blink.
    //
    // COLD_RETRY = 1'b0 removes it entirely.
    // ========================================================================
    // 788 ms was a guess made before there was any data -- "comfortably
    // longer than any plausible settle". There is data now: the first attempt
    // always fails and the second always succeeds, at 886 ms after the hold,
    // which is exactly RTRY_WAIT + RTRY_PULSE. All that tells us is that the
    // threshold lies somewhere in (394, 1280] ms. Far too coarse.
    //
    // Shortening the wait makes the retry a MEASURING INSTRUMENT: boot_ms
    // then reports the threshold to within one attempt period instead of
    // rounding it up to the next 886 ms. It also answers the question the
    // coarse setting cannot:
    //
    //   boot_ms collapses to ~100 ms   the machine just needs resetting a
    //                                  SECOND time. Not a wall-clock wait at
    //                                  all, and cold boot gets ~1.2 s faster.
    //   boot_ms stays near 886 ms      it really is a time requirement, and
    //                                  now we know it to +/-104 ms.
    //
    // ~104 ms per attempt, 15 attempts, so it reaches ~1.95 s -- past the
    // 1.28 s we know works, with margin.
    localparam integer RTRY_WAIT  = 23;   // ~98 ms between attempts
    localparam integer RTRY_PULSE = 19;   // ~6 ms of asserted reset; the CIAs
                                          // and custom chips need microseconds
    localparam [3:0]   RTRY_MAX   = 4'd15;

    reg [27:0] rtry_cnt = 28'd0;
    reg [3:0]  rtry_n   = 4'd0;
    reg        rtry_rst = 1'b0;
    reg        boot_ok  = 1'b0;

    // TG68: see FORCE_RETRY_MS. ms_cnt (section 7c) counts from the end of
    // the power-up hold. Only the retry logic sees force_fail: it is not
    // driven onto /HALT and does not light the red LED.
    wire [15:0] ms_now;
    wire force_fail  = (FORCE_RETRY_MS != 0) && !boot_ok
                       && (ms_now < FORCE_RETRY_MS[15:0]);
    wire core_halted = ~core_ohalted_n | force_fail;

    always @(posedge clk) begin
        if (!pwrup_done || !COLD_RETRY) begin
            rtry_cnt <= 28'd0;
            rtry_n   <= 4'd0;
            rtry_rst <= 1'b0;
            boot_ok  <= 1'b0;
        end else if (!boot_ok) begin
            rtry_cnt <= rtry_cnt + 28'd1;
            if (rtry_rst) begin
                if (rtry_cnt[RTRY_PULSE]) begin       // pulse done
                    rtry_rst <= 1'b0;
                    rtry_cnt <= 28'd0;
                end
            end else if (core_halted) begin
                if (rtry_cnt[RTRY_WAIT] && rtry_n != RTRY_MAX) begin
                    rtry_rst <= 1'b1;                 // try again
                    rtry_n   <= rtry_n + 4'd1;
                    rtry_cnt <= 28'd0;
                end
            end else begin
                if (rtry_cnt[RTRY_WAIT + 1]) boot_ok <= 1'b1;   // it lives
            end
        end
    end

    // ========================================================================
    // 7c. Boot statistics
    // ========================================================================
    // Counting LED blinks is a poor way to measure a boot, so the numbers are
    // published where software can read them: four read-only words in the
    // turbomem board's window at offset $F000. The ROM is 8 KB mirrored
    // through a 64 KB window, so the top 4 KB is spare and expansion.library
    // never looks above $4000.
    //
    //   $F000  magic $544D ("TM"), so a reader can tell it is really there
    //   $F002  {13'b0, ph_slip, boot_ok, core_halted}
    //   $F004  {13'b0, retries}   how many resets it took
    //   $F006  milliseconds from the end of the power-up hold to the reset
    //          release that finally worked. Add the hold itself (PWRUP_BIT)
    //          for the figure from power-on.
    //
    // `make cfgdump` prints them. Log a few dozen cold starts and the delay
    // question answers itself with numbers instead of blink-counting.
    // (1 ms: ms_top, set by the speed in force, step 13)

    reg [16:0] ms_div  = 17'd0;
    reg [15:0] ms_cnt  = 16'd0;
    reg [15:0] boot_ms = 16'd0;
    assign ms_now = ms_cnt;
    reg        ext_reset_d = 1'b1;

    always @(posedge clk) begin
        ext_reset_d <= ext_reset;
        if (!pwrup_done) begin
            ms_div <= 17'd0;
            ms_cnt <= 16'd0;
        end else if (ms_div == ms_top) begin
            ms_div <= 17'd0;
            ms_cnt <= ms_cnt + 16'd1;
        end else begin
            ms_div <= ms_div + 17'd1;
        end
        // Latch on each release of the core; the last one to stick is the
        // one that booted.
        if (ext_reset_d && !ext_reset) boot_ms <= ms_cnt;
    end

    wire [63:0] tm_status = { boot_ms,                                 // $F006
                              {12'd0, rtry_n},                         // $F004
                              {12'd0, passive, ph_slip, boot_ok,
                                       core_halted},                     // $F002
                              16'h544D };                              // $F000

    assign cpu_reset_n = (~core_oreset_n | rst_stretch | cold_rst | rtry_rst)
                         ? 1'b0 : 1'bz;
    assign cpu_halt_n  = (~core_ohalted_n | cold_rst | rtry_rst)
                         ? 1'b0 : 1'bz;

    // ========================================================================
    // 8. fx68k core
    // ========================================================================
    wire        core_rw, core_as_n, core_lds_n, core_uds_n;
    wire        core_e_unused, core_vma_n_unused;
    wire        core_fc0, core_fc1, core_fc2;
    wire        core_bg_n;
    wire [15:0] core_dout;
    // Full 32-bit internal address. The fork drives eab[31:1]; the previous
    // [23:1] declaration silently DISCARDED A24..A31, which is fine for a
    // 68000 socket (it has no such pins) but makes anything above 16 MB --
    // Zorro III space, a mapROM shadow region -- impossible to decode.
    //
    // Everything bound for the physical bus still truncates to [23:1], which
    // is exactly what a real 68000 does. Only the INTERNAL decode sees the
    // full width.
    wire [31:1] core_a;

    reg         core_dtack_lo = 1'b0;
    reg         core_berr_lo  = 1'b0;
    reg  [15:0] rd_data       = 16'hFFFF;
    reg         av_valid      = 1'b0;
    reg  [7:0]  av_num        = 8'd0;

    // REATTACH: internal slaves (autoconfig / SD / fastmem) mux in here.
    wire [15:0] core_iedb  =
          fm_ac_oe ? {fm_ac_dout, 12'hFFF}
        : tm_ac_oe ? {tm_ac_dout, 12'hFFF}
        : sd_ac_oe ? {sd_ac_dout, 12'hFFF}
        : fm_space ? fm_dout
        : tm_space ? tm_dout
        : sd_space ? sd_dout
        : hi_space ? 16'hFFFF                         // TG68: nothing there
        : RETIME   ? (rt_av ? {8'h00, av_num} : rt_rd)
                   : (av_valid ? {8'h00, av_num} : rd_data);
    wire        int_dtack_lo  = ~fm_dtack_n | ~fm_ac_dtack_n
                              | ~tm_dtack_n | ~tm_ac_dtack_n
                              | ~sd_dtack_n | ~sd_ac_dtack_n
                              | hi_space;                   // TG68
    wire        core_dtack_n = ~((RETIME ? rt_dtack_lo : core_dtack_lo)
                                 | int_dtack_lo);
    wire        core_berr_n  = ~core_berr_lo;

    // TG68: TG68K.C in 68020 mode behind an fx68k-compatible bus.
    wire tg_stalled;
    wire        dp_req, dp_inc, dp_we, dp_ack;  // TG68: direct SDRAM path
    wire [31:1] core_a_early;
    wire        dp_hold;
    wire [15:0] dp_wdata, dp_rdata;
    wire [1:0]  dp_be;
    wire        dp_pair;                        // TG68: 32-bit SDRAM pair write
    wire [15:0] dp_wdata_lo;                    //   ...and its second word
    wire        fm_cfg_on;
    wire [7:0]  fm_cfg_match;
    // TG68 step 13: HALT to the adapter as one register, with the speed
    // switch's hold folded in (both only stop new cycles at DECIDE, through
    // bus_free). A separate !spd_hold term there put one more LUT level on
    // the DECIDE decision and failed 1T by 0.4 ns; as a register this path
    // is shorter than before step 13 (the OR is gone too). One clock more
    // latency: external HALT is already two flops deep, and the sequencer
    // waits 16 quiet clocks after raising spd_hold.
    reg tg_halt_n = 1'b1;
    reg tg_br_n = 1'b1;     // step 14: the adapter's BRn, loaded by the write buffer (below)
    always @(posedge clk) tg_halt_n <= (s_halt_n[1] | ~core_ohalted_n) & ~spd_hold;
    tg68_bus #(.STEP(TG_STEP), .SETTLE(TG_SETTLE), .DIN_SETUP(TG_DIN),
               .ADDR_SETUP(TG_ASU)) cpu (
        .clk      (clk),
        .enPhi1   (en_phi1),
        .enPhi2   (en_phi2),
        .HALTn    (tg_halt_n),
        .extReset (ext_reset),
        .cyc_idle (cpu_cyc_idle),
        .pwrUp    (~pwrup_done),
        .oRESETn  (core_oreset_n),
        .oHALTEDn (core_ohalted_n),
        .E        (core_e_unused),
        .VPAn     (1'b1),               // bridge owns all 6800 cycles
        .VMAn     (core_vma_n_unused),
        .ASn      (core_as_n),
        .eRWn     (core_rw),
        .LDSn     (core_lds_n),
        .UDSn     (core_uds_n),
        .FC2      (core_fc2),
        .FC1      (core_fc1),
        .FC0      (core_fc0),
        .DTACKn   (core_dtack_n),
        .BERRn    (core_berr_n),
        // TG68: no bus grant while a posted chip write is still on the bus
        .BRn      (tg_br_n),
        .BGn      (core_bg_n),
        .BGACKn   (s_bgack_n[1]),
        .IPL2n    (ipl_out[2]),
        .IPL1n    (ipl_out[1]),
        .IPL0n    (ipl_out[0]),
        .iEdb     (core_iedb),
        .icache_win(fm_win),            // TG68: cache only on-board RAM (+ROM)
        .icache_win_k(1'b0),            // TG68: tg68_bus decodes fm_win's windows itself
        // TG68: direct SDRAM path to fast RAM
        .fm_on    (fm_cfg_on),
        .fm_match (fm_cfg_match),
        .cpu_win_en(ENABLE_FASTMEM[0]),
        .mr_load  (maprom_load),
        .mr_active(maprom_active),
        .dp_req   (dp_req),
        .dp_inc   (dp_inc),
        .eab_early(core_a_early),
        .dp_hold  (dp_hold),
        .dp_we    (dp_we),
        .dp_wdata (dp_wdata),
        .dp_be    (dp_be),
        .dp_pair  (dp_pair),
        .dp_wdata_lo (dp_wdata_lo),
        .dp_ack   (dp_ack),
        .dp_rdata (dp_rdata),
        .oEdb     (core_dout),
        .eab      (core_a),
        .stalled  (tg_stalled)
    );

    wire [2:0] core_fc = {core_fc2, core_fc1, core_fc0};

    // ========================================================================
    // 9. Bus ownership
    // ========================================================================
    reg  bg_pin_n = 1'b1;
    always @(posedge clk) if (tick_r) bg_pin_n <= core_bg_n;   // retime to 7M

    reg  p_as_n = 1'b1;
    wire bx_idle;
    // A real 68000 asserts /BG when /BR arrives but KEEPS USING THE BUS
    // until the requester asserts /BGACK. The old condition also released
    // on (~bg_pin_n & p_as_n & bx_idle), i.e. as soon as /BG went out and
    // we happened to be idle. Verified in Verilator against the real core:
    // holding /BR low with that condition deadlocks the bridge completely
    // -- zero bus cycles, machine dead, not merely slow. Any device that
    // parks /BR low, or a floating /BR, would hang the accelerator.
    // ------------------------------------------------------------------
    // 9b. Passive mode -- another accelerator takes the bus for good
    //
    // An SF2000 on the A500 expansion edge takes over by asserting and
    // HOLDING /BR. It deliberately avoids /BGACK, because Gary adds a wait
    // state to chip RAM cycles while /BGACK is asserted. On a B2000 it
    // asserts /BOSS and Buster tri-states the CPU slot instead.
    //
    // With release conditioned on /BGACK alone we would keep driving the
    // address, data and control lines into whatever the other accelerator is
    // driving. That is contention, not a difference of opinion, and it is
    // why this worked under the old 7 MHz firmware and does not now: that
    // firmware released on /BG, and the note above records exactly why that
    // was removed.
    //
    // Both behaviours are right, for different situations, so the
    // discriminator is DURATION. A DMA requester asserts /BR for the length
    // of a transfer; a takeover holds it from power-up and never lets go. We
    // look once, over a window after the power-up hold, and commit.
    //
    // The CBTs stay OPEN for the whole decision window (bus_enable is gated
    // on arb_settled), so there is no interval in which both boards drive.
    // Deciding once and latching also means a later DMA burst cannot push us
    // off the bus mid-session.
    //
    // /BR has a 10k pull-up and PULLMODE=UP, so a floating or absent signal
    // reads negated and we take the bus normally -- the failure the note
    // above warns about cannot happen by accident. PASSIVE_EN = 1'b0 removes
    // the mechanism entirely.
    // ------------------------------------------------------------------
    localparam integer PASSIVE_BIT = 17;      // ~1.5 ms decision window

    reg [17:0] arb_cnt     = 18'd0;
    reg        arb_settled = 1'b0;
    reg        passive     = 1'b0;
    reg        br_all      = 1'b1;   // /BR held for the whole window so far

    always @(posedge clk) begin
        if (!pwrup_done) begin
            arb_cnt     <= 18'd0;
            arb_settled <= 1'b0;
            passive     <= 1'b0;
            br_all      <= 1'b1;
        end else if (!arb_settled) begin
            if (s_br_n[1]) br_all <= 1'b0;          // /BR let go at some point
            if (arb_cnt[PASSIVE_BIT]) begin
                arb_settled <= 1'b1;
                passive     <= PASSIVE_EN & br_all & ~s_br_n[1];
            end else begin
                arb_cnt <= arb_cnt + 18'd1;
            end
        end
    end

    wire bus_released = ~s_bgack_n[1] | passive;
    wire bus_owned    = ~bus_released;

    // ========================================================================
    // 10. THE BRIDGE (BIU)
    // ========================================================================
    // Reproduces a real 68000 bus cycle on the 7M grid:
    //   S0 (r) FC + R/W high        S1 (f) address valid
    //   S2 (r) AS low, read DS low  S3 (f) write data driven
    //   S4 (r) write DS low         S5 (f) <- DTACK/VPA/BERR sample point
    //   S6 (r)                      S7 (f) latch read data, AS/DS high
    // Wait states loop S5<->S6 in whole 7M periods, exactly like Sw pairs.
    // Cycles chain S7->S0 with no bubble, so external throughput is identical
    // to a stock 68000; only the CPU's internal states run CPU_MULT faster.
    localparam [3:0] ST_IDLE = 4'd0,  ST_S0   = 4'd1,  ST_S1   = 4'd2,
                     ST_S2   = 4'd3,  ST_S3   = 4'd4,  ST_S4   = 4'd5,
                     ST_S5   = 4'd6,  ST_S6   = 4'd7,  ST_S7   = 4'd8,
                     ST_VPAW = 4'd9,  ST_VPAE = 4'd10, ST_VPAH = 4'd11,
                     ST_VPAX = 4'd12;

    reg [3:0] st = ST_IDLE;
    assign bx_idle = (st == ST_IDLE);

    // Latched shadow of the core's cycle
    reg [23:1] bx_a;
    reg [2:0]  bx_fc;
    reg        bx_rw, bx_uds_n, bx_lds_n, bx_iack;

    // Physical pin registers (pack these into IOB — see .fdc / LPF notes)
    reg [23:1] p_a     = 23'd0;
    reg [2:0]  p_fc    = 3'd0;
    reg        p_rw    = 1'b1;
    reg        p_uds_n = 1'b1;
    reg        p_lds_n = 1'b1;
    reg        p_vma_n = 1'b1;
    reg [15:0] p_d     = 16'd0;
    reg        p_d_oe  = 1'b0;

    // Sample machinery
    reg [2:0] smp_cnt = 3'd0;
    reg       term    = 1'b0;   // this cycle may complete
    reg       sync_go = 1'b0;   // ... as a 6800 (VPA) cycle instead
    reg       berr_go = 1'b0;

    // ---- Request tracking ----------------------------------------------
    // bx_req is a LEVEL on the core's AS, and the address/FC/RW snapshot is
    // taken from the core's live outputs when the bridge starts the cycle.
    // That is safe only because the core is still stalled waiting for our
    // DTACK at that moment.
    //
    // An edge-captured 1-deep request queue was tried, to allow acking the
    // core early. It was REVERTED: R/W goes low at S2 and the data strobes
    // at S4, so a snapshot taken on the AS falling edge is stale and writes
    // go out as reads -- a green screen on the Chip RAM test. If you revisit
    // this, capture R/W and UDS/LDS continuously, not once.

    // One ack per BRIDGE cycle. core_dtack_lo alone is not enough: the core
    // negates AS (clearing it), re-asserts for its next cycle, and the early
    // ack condition would then fire again while the bridge is still finishing
    // the PREVIOUS cycle -- acking a request it has not started, with garbage
    // read data. Cleared at consume, not at the core's AS edge.
    reg        bx_acked = 1'b0;
    reg        bx_taken = 1'b0;

    wire bx_req   = ~core_as_n & ~bx_taken;
    wire bx_start = tick_r & bx_req & bus_owned;

    wire [7:0] av_of_level = 8'd24 + {5'd0, core_a[3:1]};

    always @(posedge clk) begin
        if (ext_reset) begin
            st       <= ST_IDLE;
            p_as_n   <= 1'b1;
            p_uds_n  <= 1'b1;
            p_lds_n  <= 1'b1;
            p_vma_n  <= 1'b1;
            p_rw     <= 1'b1;
            p_d_oe   <= 1'b0;
            smp_cnt  <= 3'd0;
            term     <= 1'b0;
            sync_go  <= 1'b0;
            berr_go  <= 1'b0;
            bx_taken <= 1'b0;
            bx_acked <= 1'b0;
            core_dtack_lo <= 1'b0;
            core_berr_lo  <= 1'b0;
            av_valid      <= 1'b0;
        end else begin
            // ---- the core has finished with this cycle -------------------
            // Core-facing DTACK/BERR are held until the core drops its own
            // AS, exactly as a real slave does. (Must live in THIS block:
            // core_dtack_lo is also written by the FSM below, and a second
            // always block driving it would be a multiple-driver error.)
            // Edge, not level: with the early ack the core can negate and
            // re-assert AS inside one of our bus cycles, and a level test
            // would clear the new cycle's ack as well as the old one's.
            if (core_as_n) begin
                bx_taken      <= 1'b0;
                core_dtack_lo <= 1'b0;
                core_berr_lo  <= 1'b0;
                av_valid      <= 1'b0;
            end

            // ---- read data capture ---------------------------------------
            // rd_data TRACKS the bus for as long as the slave is driving it
            // and FREEZES the instant AS negates. The core therefore latches
            // the value the slave presented at the end of the cycle no matter
            // which master clock it happens to latch on. This is what makes
            // ACK_LEAD > 1 safe: without it, acking the core early would let
            // it sample iEdb before the bridge had captured anything.
            // Track for as long as WE hold AS asserted, not just in S6. With
            // the early ack the core can latch iEdb before S6, and a 68000
            // slave guarantees data valid once it asserts DTACK, so the live
            // bus is the right thing to present. Still freezes at AS negation.
            if (bx_rw && ((st == ST_S6) || (st == ST_VPAE && e_pin)))
                rd_data <= cpu_d;

            // ---- delayed sample of the motherboard's response ------------
            // Reading the 2FF output DTACK_LAT clocks after the nominal S4
            // falling edge means we act on the pin value AT that edge: the
            // exact sample point of a real 68000.
            if (smp_cnt != 3'd0) begin
                smp_cnt <= smp_cnt - 3'd1;
                if (smp_cnt == 3'd1) begin
                    if (!s_berr_n[1]) begin
                        berr_go <= 1'b1; term <= 1'b1;
                    end else if (!s_dtack_n[1]) begin
                        term <= 1'b1;
                    end else if (!s_vpa_n[1]) begin
                        // Gary asserts VPA for CIA space AND for FC=7 (IACK).
                        // CIA space -> real 6800 cycle against our E.
                        // IACK      -> terminate here with vector 24+level,
                        //              which is behaviourally identical to a
                        //              VPA autovector but needs no E timing
                        //              and touches no 6800 peripheral. If a
                        //              Zorro card had supplied DTACK + a real
                        //              vector we would already have taken the
                        //              branch above, so vectored interrupts
                        //              still work.
                        if (bx_iack && IACK_AV) begin
                            term     <= 1'b1;
                            av_valid <= 1'b1;
                        end else begin
                            sync_go  <= 1'b1;
                        end
                    end
                end
            end

            case (st)
            // ---------------------------------------------------------------
            ST_IDLE: if (bx_start) begin
                        p_fc     <= core_fc;
                        p_rw     <= 1'b1;            // S0: R/W high
                        bx_a     <= core_a[23:1];
                        bx_fc    <= core_fc;
                        bx_rw    <= core_rw;
                        bx_uds_n <= core_uds_n;
                        bx_lds_n <= core_lds_n;
                        bx_iack  <= (core_fc == 3'b111);
                        av_num   <= av_of_level;
                        av_valid <= 1'b0;
                        term     <= 1'b0;
                        sync_go  <= 1'b0;
                        berr_go  <= 1'b0;
                        bx_taken <= 1'b1;
                        bx_acked <= 1'b0;
                        st       <= ST_S0;
                     end
            // ---------------------------------------------------------------
            ST_S0:  if (tick_f) begin
                        p_a <= bx_a;                 // S1: address valid
                        st  <= ST_S1;
                    end
            ST_S1:  if (tick_r) begin
                        p_as_n <= 1'b0;              // S2: AS low
                        p_rw   <= bx_rw;
                        if (bx_rw) begin
                            p_uds_n <= bx_uds_n;     // reads strobe with AS
                            p_lds_n <= bx_lds_n;
                        end
                        st <= ST_S2;
                    end
            ST_S2:  if (tick_f) begin
                        if (!bx_rw) begin            // S3: drive write data
                            p_d    <= core_dout;
                            p_d_oe <= 1'b1;
                        end
                        st <= ST_S3;
                    end
            ST_S3:  if (tick_r) begin
                        if (!bx_rw) begin            // S4: writes strobe late
                            p_uds_n <= bx_uds_n;
                            p_lds_n <= bx_lds_n;
                        end
                        st <= ST_S4;
                    end
            ST_S4:  if (tick_f) begin                // this IS the S4 fall
                        smp_cnt <= SMP_N;
                        st      <= ST_S5;
                    end
            ST_S5:  begin
                        if (EARLY_ACK && !bx_rw && !bx_iack && s_berr_n[1] && s_vpa_n[1]
                            && !s_dtack_n[1] && !bx_acked) begin
                            core_dtack_lo <= 1'b1;
                            bx_acked      <= 1'b1;
                        end
                        if (tick_r) st <= ST_S6;
                    end
            // ---------------------------------------------------------------
            ST_S6:  begin
                        // Lead the data latch so the core has negated and
                        // re-asserted its AS by our next tick_r -> no bubble.
                        if (tick_ack && term && !bx_acked) begin
                            if (berr_go) core_berr_lo  <= 1'b1;
                            else         core_dtack_lo <= 1'b1;
                            bx_acked <= 1'b1;
                        end
                        // EARLY_ACK: hardware capture (debug_ws.vcd) showed
                        // the core needs ~16 master clocks from our ack to
                        // re-asserting AS. Acking at tick_ack leaves only 8
                        // before the S7 tick_r, so bx_req misses the chain
                        // window and we sit a whole 7M period in ST_IDLE.
                        // Even ACK_LEAD=6 only buys 4 of the 9 clocks needed.
                        // Once DTACK is stable the cycle WILL complete, so
                        // there is nothing to gain by making the core wait
                        // for our S-state bookkeeping.
                        if (EARLY_ACK && !bx_rw && !bx_iack && s_berr_n[1] && s_vpa_n[1]
                            && !s_dtack_n[1] && !bx_acked) begin
                            core_dtack_lo <= 1'b1;
                            bx_acked      <= 1'b1;
                        end
                        if (tick_f) begin
                            if (term) begin
                                p_as_n  <= 1'b1;   // rd_data froze above
                                p_uds_n <= 1'b1;
                                p_lds_n <= 1'b1;
                                st      <= ST_S7;
                            end else if (sync_go) begin
                                st <= ST_VPAW;
                            end else begin
                                smp_cnt <= SMP_N;     // Sw pair
                                st      <= ST_S5;
                            end
                        end
                    end
            // ---------------------------------------------------------------
            ST_S7:  if (tick_r) begin
                        p_rw   <= 1'b1;              // R/W + data held 70 ns
                        p_d_oe <= 1'b0;              // past AS negation
                        if (bx_req && bus_owned) begin
                            p_fc     <= core_fc;
                            bx_a     <= core_a[23:1];
                            bx_fc    <= core_fc;
                            bx_rw    <= core_rw;
                            bx_uds_n <= core_uds_n;
                            bx_lds_n <= core_lds_n;
                            bx_iack  <= (core_fc == 3'b111);
                            bx_taken <= 1'b1;
                            bx_acked <= 1'b0;
                            av_num   <= av_of_level;
                            av_valid <= 1'b0;
                            term     <= 1'b0;
                            sync_go  <= 1'b0;
                            berr_go  <= 1'b0;
                            st       <= ST_S0;       // chain, no bubble
                        end else begin
                            st <= ST_IDLE;
                        end
                    end
            // ---------------------------------------------------------------
            // 6800-style synchronous cycle, run against OUR 709 kHz E.
            // AS stays low throughout, exactly as on a real 68000.
            ST_VPAW: if (tick_r && (e_cnt == E_VMA_AT)) begin
                        p_vma_n <= 1'b0;             // E low, ~700 ns before rise
                        st      <= ST_VPAE;
                     end
            ST_VPAE: begin
                        if (tick_ack && (e_cnt == 4'd9)) core_dtack_lo <= 1'b1;
                        if (tick_f   && (e_cnt == 4'd9)) st <= ST_VPAH;
                     end
            ST_VPAH: if (e_fall_tick) st <= ST_VPAX;        // E falls now
            ST_VPAX: if (tick_f) begin                      // 70 ns of hold
                        p_vma_n <= 1'b1;
                        p_as_n  <= 1'b1;
                        p_uds_n <= 1'b1;
                        p_lds_n <= 1'b1;
                        st      <= ST_S7;
                     end
            default: st <= ST_IDLE;
            endcase

        end
    end

    // ========================================================================
    // 11. Pin drivers
    // ========================================================================
    assign cpu_a     = bus_owned ? (RETIME ? rt_a     : p_a)     : 23'bz;
    assign cpu_as_n  = bus_owned ? (RETIME ? rt_as_n  : p_as_n)  : 1'bz;
    assign cpu_uds_n = bus_owned ? (RETIME ? rt_uds_n : p_uds_n) : 1'bz;
    assign cpu_lds_n = bus_owned ? (RETIME ? rt_lds_n : p_lds_n) : 1'bz;
    assign cpu_rw    = bus_owned ? (RETIME ? rt_rw    : p_rw)    : 1'bz;
    assign cpu_fc    = bus_owned ? (RETIME ? rt_fc    : p_fc)    : 3'bz;
    assign cpu_vma_n = bus_owned ? (RETIME ? rt_vma_n : p_vma_n) : 1'bz;
    assign cpu_d     = RETIME ? ((bus_owned & rt_d_oe) ? rt_d : 16'bz)
                              : ((bus_owned & p_d_oe)  ? p_d  : 16'bz);
    assign cpu_e     = e_pin;         // never tri-stated, as on real silicon
    assign cpu_bg_n  = bg_pin_n;

    reg bus_enable = 1'b0;
    // arb_settled keeps the CBTs open until passive mode has been decided,
    // so we never drive the bus during the window in which another
    // accelerator might already own it.
    always @(posedge clk) bus_enable <= pwrup_done & arb_settled & bus_owned;
    // Open the switchable CBTs on our own cycles so the CPU<->SDRAM traffic
    // is isolated from the motherboard bus.
    assign cbt_oe_d0_7_n   = ~bus_enable | fm_active | tm_active | sd_space;
    assign cbt_oe_d8_15_n  = ~bus_enable | fm_active | tm_active | sd_space;
    assign cbt_oe_ctl_hi_n = ~bus_enable;
    assign cbt_oe_a8_17_n  = ~bus_enable;
    assign cbt_oe_a1_7_n   = ~bus_enable;

    // Autoconfig chain: transparent pass-through while our own boards are
    // stripped out, so downstream cards still configure. REATTACH here.

    // SD card in SPI mode. DAT1/DAT2 are unused by the SPI protocol and are
    // released rather than driven; DAT0 is an input (MISO) and DAT3 is chip
    // select.
    assign sd_clk      = sd_sclk_i;
    assign sd_cmd      = sd_mosi_i;
    assign sd_d[3]     = sd_ss_n_i;
`ifdef YOSYS
    // TG68: yosys turns a constant 1'bz on an inout port into a constant 0
    // driver (the open-source flow has no tristate to put it in), so the
    // pins were driven LOW -- MISO included, which held every reply from
    // the card at $00. Explicit bidirectional buffers with the output
    // permanently off make them true inputs. (Diamond honours 1'bz, so the
    // other branch is the original code.)
    wire sd_miso_pin;
    BB u_sd_d0 (.I(1'b0), .T(1'b1), .O(sd_miso_pin), .B(sd_d[0]));
    BB u_sd_d1 (.I(1'b0), .T(1'b1), .O(),            .B(sd_d[1]));
    BB u_sd_d2 (.I(1'b0), .T(1'b1), .O(),            .B(sd_d[2]));
`else
    assign sd_d[2:1]   = 2'bzz;
    assign sd_d[0]     = 1'bz;
    wire sd_miso_pin   = sd_d[0];
`endif

    // ========================================================================
    // 10b. RETIME mode -- SF2000-style pass-through
    // ========================================================================
    // The bridge re-synthesises a whole S0..S7 cycle on the 7M grid. That
    // costs a full 7M period of S0/S1 address setup that the core has ALREADY
    // done in fast time, plus a quantisation wait in ST_IDLE at the end. Six
    // clocks per cycle, measured, against a stock 68000's four-plus-wait.
    //
    // Retiming instead just gates the core's OWN strobes onto the 7M grid:
    //   * AS goes to the motherboard at the first tick_r after the core
    //     asserts it, and drops immediately when the core drops it
    //   * UDS/LDS are re-sampled at every tick_r, NOT snapshotted once --
    //     which is what makes writes work, since a 68000 asserts them two
    //     clocks after AS on a write
    //   * DTACK is passed back to the core only ON a tick_r
    //
    // That last point is the subtle one, and it is why this is safe where
    // EARLY_ACK was not. Quantising the ack to the 7M grid gives the slave's
    // data up to a full 141 ns after DTACK to settle before the core sees
    // the ack -- the same margin a real 68000 gets from S6 to S7. We are not
    // removing the margin, we are re-deriving it from the motherboard clock.
    // TG68: syn_useioff on the pin registers, as base64.fdc does for
    // Diamond; nextpnr honours the attribute directly.
    // NOT on rt_as_n / rt_vma_n: both are also read by the logic below, an
    // I/O flop can only drive its pad, and nextpnr will not duplicate the
    // register the way Synplify does (yosys merges any hand-made copy). They
    // stay fabric flops, which adds a couple of ns to the ~35 ns AS output
    // path DTACK_LAT was calibrated on. That can only cost a wait state:
    // read data reaches the core no earlier than the next tick_r, >= 141 ns
    // after the slave's DTACK, whichever 7M tick the DTACK sample lands on.
    reg        rt_as_n  = 1'b1;
    (* syn_useioff *) reg        rt_uds_n = 1'b1;
    (* syn_useioff *) reg        rt_lds_n = 1'b1;
    reg        rt_vma_n = 1'b1;
    reg        rt_dtack_lo = 1'b0, rt_av = 1'b0;
    reg [15:0] rt_rd    = 16'hFFFF;
    (* syn_useioff *) reg [15:0] rt_d     = 16'd0;
    (* syn_useioff *) reg [23:1] rt_a     = 23'd0;
    (* syn_useioff *) reg [2:0]  rt_fc    = 3'd0;
    (* syn_useioff *) reg        rt_rw    = 1'b1;
    reg        rt_d_oe = 1'b0;
    reg [1:0]  rt_vst   = 2'd0;
    reg        core_as_d2 = 1'b1;
    always @(posedge clk) core_as_d2 <= core_as_n;
    // TG68: CHIP RAM WRITE BUFFER (POST_CHIP; step 11 posted one write,
    // step 12 buffers WB_N). A CPU write to chip RAM ($000000-$1FFFFF, never
    // an on-chip slave) is recognised from its address and R/W before AS
    // ("postable"), so the path below never starts it on the motherboard
    // itself. Once its data strobes are down it is acknowledged and goes
    // into a FIFO (wb_acc). The drain engine runs the head entry on the
    // motherboard with 68000 timing: AS at a tick_r with the data driven,
    // the data strobes at the next tick_r (S4), the end at the tick_f after
    // a DTACK seen at a later tick_r (S7), address, R/W and data held to the
    // next tick_r, then the entry is popped. Every other motherboard cycle
    // (chip reads, custom/CIA registers, IACK) waits until the buffer is
    // empty and the engine idle (wb_busy), so the Amiga sees every access
    // in program order: a blit started after a screen write sees the write.
    //   rp_act:  the head entry is on the bus
    //   rp_ds:   its data strobes are down
    //   rp_term: its DTACK was seen;  rp_hold: AS/DS up, holding
    localparam integer WB_N = CHIP_WB;
    // (storage always 8 deep, the pointers wrap at 8; WB_N limits the fill)
    reg [23:1] wb_a  [0:7];
    reg [15:0] wb_d  [0:7];
    reg [2:0]  wb_fc [0:7];
    reg [1:0]  wb_ds [0:7];        // {UDS, LDS}, active low
    reg [2:0]  wb_wp = 3'd0, wb_rp = 3'd0;
    reg [3:0]  wb_cnt = 4'd0;
    reg        rp_act = 1'b0, rp_term = 1'b0, rp_hold = 1'b0, rp_ds = 1'b0;
    reg        rp_uds = 1'b1, rp_lds = 1'b1;
    wire       wb_full = (wb_cnt == WB_N[3:0]);
    wire       wb_busy = rp_act || (wb_cnt != 4'd0);
    // TG68 step 14: BRn to the adapter as a register (as HALTn, step 13): as
    // s_br_n | wb_busy straight into bus_free it put the write buffer's
    // state on a 1T path into DECIDE that missed on seeds. Its job is to
    // hide external bus requests while the buffer drains; the buffer only
    // starts draining while the CPU is in the write cycle that filled it,
    // and the adapter grants nothing mid-cycle, so a clock's lag is safe
    // (and external BRn is asynchronous anyway).
    always @(posedge clk) tg_br_n <= s_br_n[1] | wb_busy;   // (declared by tg_halt_n)
    // the core's address is in chip RAM: a registered decode like int_win_r
    // (the address is stable >= 2 clocks before AS, so it is current by AS)
    reg        core_chip_r = 1'b0;
    always @(posedge clk) core_chip_r <= (core_a[23:21] == 3'b000);
    wire       postable = POST_CHIP && !core_as_n && !core_rw && core_chip_r && !int_win_r;
    wire       wb_acc   = postable && (!core_uds_n || !core_lds_n) && !rt_dtack_lo && !wb_full;
    // TG68: above 12x one master clock is under 11 ns (8.81 ns at 16x), so
    // the address/data hold past AS negation below takes two (spd_hold2).
    // rt_hold_done = spd_hold2 ? AS delayed 3 : AS delayed 2, as ONE
    // register fed from one stage earlier of the same delay chain (the
    // same value every clock: spd_hold2 changes only in a speed switch,
    // with AS high for 16+ clocks). As a mux after the chain, spd_hold2 sat
    // in the 1T path from the write buffer into the address pin registers
    // and missed by 0.45 ns.
    reg        rt_hold_done = 1'b1;
    always @(posedge clk) rt_hold_done <= spd_hold2 ? core_as_d2 : core_as_n;

    wire       wb_pop = !ext_reset && wb_busy && rp_act && rp_hold && tick_rq;
    always @(posedge clk) begin
        if (ext_reset) begin
            rt_as_n <= 1'b1; rt_uds_n <= 1'b1; rt_lds_n <= 1'b1;
            rt_vma_n <= 1'b1; rt_dtack_lo <= 1'b0; rt_d_oe <= 1'b0;
            rt_vst <= 2'd0; rt_av <= 1'b0;
            rp_act <= 1'b0; rp_term <= 1'b0; rp_hold <= 1'b0; rp_ds <= 1'b0;
        end else if (wb_busy) begin
            // TG68: draining the chip RAM write buffer. The CPU has its acks;
            // each is dropped once the CPU ends that cycle, and a cycle that
            // cannot be buffered waits here until the buffer is empty.
            if (core_as_n) rt_dtack_lo <= 1'b0;
            if (!rp_act) begin
                // the head entry: address, FC, R/W and data out now, AS at
                // the next tick_r (>= 1.5 7M clocks after the last AS rose)
                rp_act  <= 1'b1;
                rp_ds   <= 1'b0;
                rt_a    <= wb_a[wb_rp];
                rt_fc   <= wb_fc[wb_rp];
                rt_rw   <= 1'b0;
                rt_d    <= wb_d[wb_rp];
                rp_uds  <= wb_ds[wb_rp][1];
                rp_lds  <= wb_ds[wb_rp][0];
            end else begin
                // the data bus is driven whenever this write's AS is down
                if (!rt_as_n) rt_d_oe <= 1'b1;
                if (tick_rq && !rp_term && !rp_hold) begin
                    if (rt_as_n) begin              // S2: AS down, data out
                        rt_as_n <= 1'b0;
                        rt_d_oe <= 1'b1;
                    end else if (!rp_ds) begin      // S4: data strobes down
                        rt_uds_n <= rp_uds;
                        rt_lds_n <= rp_lds;
                        rp_ds    <= 1'b1;
                    end else if (s_berr_n[1] && !s_dtack_n[1])
                        rp_term  <= 1'b1;           // the slave has it
                end
                if (rp_term && tick_f) begin        // end it, as a 68000's S7
                    rt_as_n  <= 1'b1;
                    rt_uds_n <= 1'b1;
                    rt_lds_n <= 1'b1;
                    rp_term  <= 1'b0;
                    rp_hold  <= 1'b1;
                end
                if (rp_hold && tick_rq) begin        // held to here; pop it
                    rp_hold  <= 1'b0;
                    rp_act   <= 1'b0;
                    rp_ds    <= 1'b0;
                    rt_rw    <= 1'b1;
                    rt_d_oe  <= 1'b0;
                    rt_a     <= core_a[23:1];       // the CPU's next cycle
                    rt_fc    <= core_fc;
                end
            end
        end else if (core_as_n) begin
            rt_as_n     <= 1'b1;
            rt_uds_n    <= 1'b1;
            rt_lds_n    <= 1'b1;
            rt_vma_n    <= 1'b1;
            rt_dtack_lo <= 1'b0;
            rt_av       <= 1'b0;
            rt_vst      <= 2'd0;
            // One clock of address/data hold past AS negation before the
            // next cycle's address is allowed through.
            // Address, FC, R/W and the write data are all held one clock
            // past AS negation. A 68000 keeps R/W and data valid after AS
            // goes high, and the slave latches a write ON the AS rising
            // edge -- drop them on the same edge and the write is lost.
            if (rt_hold_done) begin
                rt_a    <= core_a[23:1];
                rt_fc   <= core_fc;
                rt_rw   <= 1'b1;
                rt_d_oe <= 1'b0;
            end
        end else if (!postable) begin
            // (a chip RAM write is never started here: it is buffered)
            if (!core_rw) begin
                rt_d    <= core_dout;
                rt_d_oe <= ~rt_as_n;
            end
            // R/W, UDS and LDS are RE-SAMPLED every tick_r, never snapshotted
            // once. A 68000 drives R/W low at S2 (with AS) and the data
            // strobes at S4 (two clocks after AS) on a write, so anything
            // captured at the AS edge is stale and the cycle goes out as a
            // read. That is what turned the Chip RAM test into a green
            // screen. Until we commit AS, keep tracking R/W so it is stable
            // at the motherboard before AS falls.
            // int_space cycles are answered on-chip: never assert AS to the
            // motherboard for them. This is where the speed comes from --
            // fast RAM runs at the full 42.6 MHz with no 7M quantisation.
            if (tick_r && !int_win_r) begin
                rt_as_n  <= 1'b0;
                rt_rw    <= core_rw;
                rt_uds_n <= core_uds_n;
                rt_lds_n <= core_lds_n;
            end else if (rt_as_n) begin
                rt_rw    <= core_rw;
            end
            if (core_rw && !rt_as_n &&
                (s_vpa_n[1] ? 1'b1 : (!rt_vma_n && e_pin)))
                rt_rd <= cpu_d;
            if (tick_r && !rt_as_n && s_berr_n[1]) begin
                if (!s_dtack_n[1])
                    rt_dtack_lo <= 1'b1;
                else if (!s_vpa_n[1] && (core_fc == 3'b111)) begin
                    rt_av       <= 1'b1;     // IACK -> autovector
                    rt_dtack_lo <= 1'b1;
                end
            end
            // 6800 cycle against OUR E
            if (!s_vpa_n[1] && !rt_as_n && (core_fc != 3'b111)) begin
                if (rt_vst == 2'd0) begin
                    if (!e_pin && (e_cnt == E_VMA_AT)) begin
                        rt_vma_n <= 1'b0; rt_vst <= 2'd1;
                    end
                end else if (rt_vst == 2'd1) begin
                    // E falls on THIS tick (e_fall_tick is tick_r with
                    // e_cnt==9, the same edge that reloads e_pin to 0). Do
                    // not drop VMA here: go to state 3 and hold it to the
                    // next tick_f, 70 ns later, which is what ST_VPAH ->
                    // ST_VPAX does in the bridge FSM below. Deferring the
                    // ack with it also holds AS, UDS/LDS, R/W and the write
                    // data, because the core cannot negate AS until it has
                    // seen DTACK.
                    if (e_fall_tick) begin
                        if (VMA_HOLD) begin
                            rt_vst <= 2'd3;
                        end else begin
                            rt_vma_n    <= 1'b1;
                            rt_dtack_lo <= 1'b1;
                            rt_vst      <= 2'd2;
                        end
                    end
                end else if (rt_vst == 2'd3) begin
                    if (tick_f) begin           // 70 ns of VMA/CS hold
                        rt_vma_n    <= 1'b1;
                        rt_dtack_lo <= 1'b1;
                        rt_vst      <= 2'd2;
                    end
                end
            end
        end
        // TG68: the buffer's input side, in every state: a chip RAM write
        // whose strobes are down is taken (address, FC, data and strobes
        // straight from the CPU) and acknowledged, unless the buffer is full;
        // then the CPU waits for the engine to pop an entry.
        if (ext_reset) begin
            wb_cnt <= 4'd0; wb_wp <= 3'd0; wb_rp <= 3'd0;
        end else begin
            wb_cnt <= wb_cnt + {3'd0, wb_acc} - {3'd0, wb_pop};
            if (wb_pop) wb_rp <= wb_rp + 3'd1;
            if (wb_acc) begin
                wb_wp       <= wb_wp + 3'd1;
                rt_dtack_lo <= 1'b1;
            end
        end
    end
    // the FIFO's storage: written regardless of reset, only the pointers count
    always @(posedge clk)
        if (wb_acc) begin
            wb_a[wb_wp]  <= core_a[23:1];
            wb_fc[wb_wp] <= core_fc;
            wb_d[wb_wp]  <= core_dout;
            wb_ds[wb_wp] <= {core_uds_n, core_lds_n};
        end

    // ========================================================================
    // 13. TG68 step 13: speed switch (12x / 14x / 16x at run time)
    // ========================================================================
    // A keyed write to turbomem +$F00A (spd_wr/spd_val, the SPEED command)
    // asks for a speed. If that clock's PLL is locked:
    //   HOLD  hold the CPU's bus cycles (spd_hold, through the adapter's
    //         HALTn: it starts no bus cycle, SDRAM request or cache lookup)
    //         and wait until nothing is in flight for 16 clocks: the adapter
    //         idle with the SDRAM port free, the chip write buffer empty, AS
    //         high at the CPU and on the motherboard
    //   CL    going to 16x: the SDRAM to CAS latency 3 first (CL3 is in spec
    //         at every speed, CL2 only up to 14x)
    //   SW    switch the clock and the settings (spd), then 64 clocks for the
    //         glitch-free switch to finish (the old clock stops low, the new
    //         one starts; the sequencer itself pauses with them). The 7M
    //         aligner is kept re-acquiring (spd_unlock) from here to SETL
    //   LOCK  8 7M edges for the new period count to settle
    //   CAL   a 7M capture calibration window (section 3, ~290 us)
    //   SETL  the aligner locks with the chosen stream: 8 more 7M edges
    //   CL2   leaving 16x: the SDRAM back to CAS latency 2
    // then release the CPU. A write of the speed already in force runs the
    // same sequence without switching: a recalibration. The speed persists
    // over an Amiga reset; a power cycle (FPGA reload) returns to 12x.
    localparam [2:0] SP_IDLE = 3'd0, SP_HOLD = 3'd1, SP_CL = 3'd2, SP_SW = 3'd3,
                     SP_LOCK = 3'd4, SP_CL2 = 3'd5, SP_CAL = 3'd6, SP_SETL = 3'd7;
    reg  [2:0] sp     = SP_IDLE;
    reg  [1:0] sp_tgt = 2'd0;
    reg  [7:0] sp_cnt = 8'd0;
    reg        sp_swp = 1'b0;           // step 14: this run swaps 7M streams only
`ifdef TG68_X16
    assign spd_stat = {ph_slip, 7'd0, 8'd16};   // fixed 16x, no switching
`else
    wire       sp_ok  = (spd_val == 2'd0) || (spd_val == 2'd1 && pll_lock14)
                     || (spd_val == 2'd2 && pll_lock16);
    wire       sp_quiet = cpu_cyc_idle && !wb_busy && core_as_n && rt_as_n;
    //  15 aligner slipped since the last calibration   14/13 the rising /
    //  falling 7M stream moved since then   12 the rising stream in use
    //  11 switching   10 run-time switching present   9/8 16x/14x PLL lock
    //  7-0 multiplier in force
    assign spd_stat = {ph_slip, cal_jr, cal_jf, smp_r, sp != SP_IDLE, 1'b1,
                       pll_lock16, pll_lock14,
                       (spd == 2'd2) ? 8'd16 : (spd == 2'd1) ? 8'd18 : 8'd12};   // exp-18x
    always @(posedge clk) begin
        cal_go  <= 1'b0;
        swap_go <= 1'b0;
        case (sp)
        SP_IDLE: begin
            spd_hold   <= 1'b0;
            spd_unlock <= 1'b0;
            sp_cnt     <= 8'd0;
            if (spd_wr && sp_ok) begin
                sp_tgt   <= spd_val;
                sp_swp   <= 1'b0;
                spd_hold <= 1'b1;
                sp       <= SP_HOLD;
            end else if (swap_req) begin
                // step 14: the 7M stream in use drifts: the same run with
                // the clock left as it is, swapping streams in LOCK
                // instead of calibrating (a fresh window would likely see
                // neither move, a slow drift, and choose the drifting one
                // again)
                sp_tgt   <= spd;
                sp_swp   <= 1'b1;
                spd_hold <= 1'b1;
                sp       <= SP_HOLD;
            end
        end
        SP_HOLD: begin
            if (!sp_quiet) sp_cnt <= 8'd0;
            else if (sp_cnt != 8'd15) sp_cnt <= sp_cnt + 8'd1;
            else begin
                sp_cnt <= 8'd0;
                sp     <= (sp_tgt != 2'd0 && !sdram_cl3) ? SP_CL : SP_SW;   // exp-18x: CL3 at 16x and 18x
            end
        end
        SP_CL: begin
            sdram_cfg_cl3 <= 1'b1;
            sdram_cfg_req <= 1'b1;
            if (sdram_cl3) begin
                sdram_cfg_req <= 1'b0;
                sp <= SP_SW;
            end
        end
        SP_SW: begin
            clk_sel    <= sp_tgt;
            spd        <= sp_tgt;
            spd_unlock <= 1'b1;
            if (sp_cnt != 8'd63) sp_cnt <= sp_cnt + 8'd1;
            else begin
                sp_cnt <= 8'd0;
                sp     <= SP_LOCK;
            end
        end
        SP_LOCK: begin                      // the new grid settles
            if (edge_7m_f) sp_cnt <= sp_cnt + 8'd1;
            if (sp_cnt == 8'd8) begin
                sp_cnt <= 8'd0;
                if (sp_swp) swap_go <= 1'b1;   // step 14: no calibration
                else        cal_go  <= 1'b1;
                sp     <= SP_CAL;
            end
        end
        SP_CAL: begin                       // cal_busy follows cal_go 2 clocks on
            if (sp_cnt != 8'd3) sp_cnt <= sp_cnt + 8'd1;
            else if (!cal_busy) begin
                sp_cnt     <= 8'd0;
                spd_unlock <= 1'b0;
                sp         <= SP_SETL;
            end
        end
        SP_SETL: begin                      // the aligner locks on the stream
            if (edge_7m) sp_cnt <= sp_cnt + 8'd1;
            if (sp_cnt == 8'd8) begin
                sp_cnt <= 8'd0;
                sp     <= (sp_tgt == 2'd0 && sdram_cl3) ? SP_CL2 : SP_IDLE;   // exp-18x
            end
        end
        SP_CL2: begin
            sdram_cfg_cl3 <= 1'b0;
            sdram_cfg_req <= 1'b1;
            if (!sdram_cl3) begin
                sdram_cfg_req <= 1'b0;
                sp <= SP_IDLE;
            end
        end
        default: sp <= SP_IDLE;
        endcase
    end
`endif

    // ========================================================================
    // 10c. Internal slaves: SDRAM fast RAM + its autoconfig
    // ========================================================================
    // NOT instantiated: autoconfig_zii (the SD card device). It advertises a
    // boot ROM -- board type 4'b1101 "ROM vector valid" at offset 00 and a
    // vector of 0x0001 at offset 2E -- so Kickstart will try to autoboot from
    // it. With no sd_subsystem behind it that hangs at the boot menu. Bring it
    // back in the same commit as the SD controller, not before.
    //
    // fastmem_zii carries its OWN autoconfig (fm_ac_*). That is deliberate and
    // stays: it is welded to the OFFER_SPLIT size negotiation, and its state
    // order encodes the Kickstart config-overflow workaround where 2M must be
    // offered before 4M.
    //
    // turbomem_zii is therefore a THIRD board on the daisy chain, not a
    // refactor of either of the others:
    //
    //     cfgin(pin) -> fastmem_zii -> turbomem_zii -> cfgout(pin)
    //
    // It serves the turbomem DiagArea so expansion.library copies it into RAM
    // and calls DiagPoint -- which is where turbomem_add() hands the
    // $08000000 window to exec via AddMemList().
    wire        fm_space, fm_active, fm_dtack_n;
    wire        fm_win;                        // TG68: for the cache
    wire [15:0] fm_dout;
    wire        fm_ac_access, fm_ac_oe, fm_ac_dtack_n;
    wire        fm_int_win, tm_int_win, sd_int_win, sd_ac_win;   // see int_win
    wire [3:0]  fm_ac_dout;
    wire        tm_space, tm_active, tm_dtack_n;
    wire [15:0] tm_dout;
    wire        tm_ac_access, tm_ac_oe, tm_ac_dtack_n;
    wire [3:0]  tm_ac_dout;
    wire [7:0]  tm_base;
    wire        tm_configured;
    wire        sd_space, sd_dtack_n;
    wire [15:0] sd_dout;
    wire        sd_ac_access, sd_ac_oe, sd_ac_dtack_n;
    wire [3:0]  sd_ac_dout;
    wire [7:0]  base_sd;
    wire        sd_configured;
    wire        maprom_load, maprom_active;   // turbomem $F008 -> fastmem
    wire        ac_chain_n;      // fastmem CFGOUT  -> turbomem CFGIN
    wire        ac_chain2_n;     // turbomem CFGOUT -> SD CFGIN
    wire        sd_req, sd_we, sd_ack, sd_ready, sd_wr_valid, sd_ack_early;
    wire [15:0] sd_rdata_live;
    wire [23:0] sd_saddr;
    wire [15:0] sd_wdata, sd_rdata;
    wire [1:0]  sd_byte_en;

    // ------------------------------------------------------------------
    // SLAVE RESET IS NOT THE CORE RESET. Do not collapse these again.
    //
    // ext_reset needs /RESET *and* /HALT together, which is right for the
    // CPU: a RESET instruction drives /RESET alone and must not reset the
    // processor that issued it. It is WRONG for the three autoconfig boards.
    // A Zorro II board resets from /RESET; /HALT is not even on the
    // connector, and Kickstart re-runs the whole expansion configuration
    // from scratch after a RESET instruction.
    //
    // With the two tied together, a warm reset left fastmem, turbomem and
    // the SD board still `configured`, still shut up, and still decoding
    // their old bases. Kickstart then re-enumerated, found them silent, and
    // handed the first free Zorro II base to whatever board came next -- on
    // top of a window fastmem was still claiming. The reported symptom was
    // an A500+ with a Ripple IDE card dropping to the insert-disk screen
    // after every loadmodule or software reset, needing Ctrl-A-A to boot,
    // which is exactly this: Ctrl-A-A pulls /HALT too, so ext_reset fires
    // and the chain comes back clean.
    //
    // Our own rst_stretch pulls the /RESET pin, so s_reset_n[1] sees it and
    // our boards reset alongside every other board on the bus. That also
    // drops the Zorro II window and mapROM for the duration, which is what
    // a real board does -- ColdReboot runs from ROM with no stack between
    // the RESET and the JMP for exactly that reason, and the mapROM shadow
    // is a verbatim copy, so instruction fetch continues unchanged.
    //
    // REGISTERED, and it has to stay that way. As a plain wire this is a LUT
    // output feeding 111 loads across the three slaves and the SDRAM
    // controller, all inside one 85 MHz clock. The build that introduced it
    // needed SIX place-and-route seeds, five of which failed setup
    // (-0.043, -0.089, -0.216, -0.010, -0.389 ns) before one closed at
    // +0.322 -- against v1.2.1 closing on the first seed. One flop costs a
    // single clock of latency on a reset, which is nothing, and turns the
    // path into s_reset_n -> LUT -> flop (short, low fanout) followed by
    // flop -> 111 loads with no logic in between, which P&R can also
    // replicate if it wants to. Do not collapse it back into the wire.
    // ------------------------------------------------------------------
    reg slave_reset = 1'b1;
    always @(posedge clk) slave_reset <= ext_reset | ~s_reset_n[1];

    // -----------------------------------------------------------------
    // AUTOCONFIG ID ALLOCATION -- manufacturer 5194 ($144A), OAHR
    //
    // This block is the authority for all three IDs. Both modules carry
    // their own PROD_ID defaults, but what the board actually presents is
    // what is overridden here, so change them HERE.
    //
    //   5194/11  SD card         reused from the SF2000 on purpose, so the
    //                            unmodified sfsd.device binds without a
    //                            driver fork. Registered to Niklas Ekstrom
    //                            and Matt Harlum.
    //   5194/13  Fast RAM        Zorro II, up to 8 MB
    //   5194/14  AutoConfig ROM  64 KB Zorro II I/O board carrying the
    //                            DiagArea that AddMemList()s the 16 MB at
    //                            $08000000
    //
    // 13 and 14 were ASSIGNED to Base64 by OAHR in August 2026, and 12 went
    // to SF2000, so the two projects hold contiguous blocks: SF2000 10-12,
    // Base64 13-14. er_SerialNumber is 0 on every board, as declared in the
    // application.
    // -----------------------------------------------------------------
    // TG68: fast RAM + turbomem are built only with ENABLE_FASTMEM.
    generate if (ENABLE_FASTMEM) begin : g_fastmem
    // TG68: BUS_RAM 0 -- the CPU reaches fast RAM (and MapROM) only through
    // the direct path; see tg68_bus.v, DIRECT.
    fastmem_zii #(.PROD_ID(8'd13), .OFFER_SPLIT(1'b1), .BUS_RAM(1'b0)) u_fastmem (
        .clk        (clk),
        .reset      (slave_reset),
        .cfgin_n    (s_cfgin_n[1]),
        .as_n       (core_as_n),
        .uds_n      (core_uds_n),
        .lds_n      (core_lds_n),
        .rw         (core_rw),
        .a          (core_a),
        .d_in       (core_dout),
        .fm_space   (fm_space),
        .fm_dout    (fm_dout),
        .fm_dtack_n (fm_dtack_n),
        .fm_active  (fm_active),
        .fm_win     (fm_win),
        .fm_cfg_on  (fm_cfg_on),
        .fm_cfg_match(fm_cfg_match),
        .dp_req     (dp_req),
        .dp_inc     (dp_inc),
        .a_early    (core_a_early),
        .dp_hold    (dp_hold),
        .dp_we      (dp_we),
        .dp_wdata   (dp_wdata),
        .dp_be      (dp_be),
        .dp_ack     (dp_ack),
        .dp_rdata   (dp_rdata),
        .cfgout_n   (ac_chain_n),
        .fm_ac_access (fm_ac_access),
        .fm_int_win   (fm_int_win),
        .fm_ac_dout   (fm_ac_dout),
        .fm_ac_oe     (fm_ac_oe),
        .fm_ac_dtack_n(fm_ac_dtack_n),
        .req        (sd_req),
        .we         (sd_we),
        .saddr      (sd_saddr),
        .wdata      (sd_wdata),
        .byte_en    (sd_byte_en),
        .wr_valid   (sd_wr_valid),
        .ack        (sd_ack),
        .ack_early  (sd_ack_early),
        .rdata_live (sd_rdata_live),
        .rdata      (sd_rdata),
        .sdram_ready(sd_ready),
        .maprom_load  (maprom_load),
        .maprom_active(maprom_active)
    );

    // ROM_FILE: turbomem.mem MUST BE A MEMBER OF THE DIAMOND PROJECT.
    //
    // Putting it in the directory Synplify runs from is NOT enough. Measured
    // on this design: microrom.mem, nanorom.mem, sfsd.mem and turbomem.mem
    // all sat in prj/base64_fx68k/impl1/, and $readmemh found the project
    // members and not the fourth file. Add it via File > Add > Existing File
    // so it appears in the Input Files list.
    //
    // If it is ever not found, the failure is silent and convincing:
    //
    //   log: CG371 Cannot find data file turbomem.mem for task $readmemh
    //   log: CL279 Pruning register bits 15 to 1 of rom_q[15:0]
    //
    // and the array constant-folds to zero. The board then enumerates
    // perfectly at its assigned base while serving 8 KB of zeroes, an
    // all-zero DiagArea reads as DAC_NIBBLEWIDE/DAC_NEVER with a null
    // BootPoint so expansion.library declines to touch it, and the machine
    // boots normally. Every symptom points at the gateware decode. None of
    // them are the gateware decode.
    //
    // The check that cannot lie is the block RAM count: ROM_AWID 12 is
    // 4096x16, which is four EBRs. If "Number of block RAMs" did not rise by
    // four, the ROM is not in the bitstream.
    //
    // An absolute path here also works and cannot fail, if the project route
    // ever gives trouble.
    turbomem_zii #(
        .MFG_ID   (16'h144A),
        .PROD_ID  (8'd14),        // see the ID allocation block above
        .SERIAL   (32'd0),
        .DIAG_VEC (16'h2000),     // BYTE offset, MUST be non-zero: a zero
                                  // vector enumerates fine and is never
                                  // followed. $2000 needs no decode change
                                  // (the image mirrors every 8 KB) and is
                                  // still safe if read as a word offset.
        .ROM_AWID (12),           // 4096 words = 8 KB = 4 EBRs
        .ROM_FILE ("turbomem.mem")
    ) u_turbomem (
        .status_i   (tm_status),
        .spd_wr     (spd_wr),
        .spd_val    (spd_val),
        .spd_smp    (spd_smp),
        .spd_stat   (spd_stat),
        .spd_stat2  ({8'd0, n_swap}),     // step 14: +$F00C
        .clk        (clk),
        .reset      (slave_reset),
        .cfgin_n    (ac_chain_n),
        .as_n       (core_as_n),
        .uds_n      (core_uds_n),
        .lds_n      (core_lds_n),
        .rw         (core_rw),
        .a          (core_a),
        .d_in       (core_dout),
        .tm_space   (tm_space),
        .tm_dout    (tm_dout),
        .tm_dtack_n (tm_dtack_n),
        .tm_active  (tm_active),
        .tm_ac_access (tm_ac_access),
        .tm_int_win   (tm_int_win),
        .tm_ac_dout   (tm_ac_dout),
        .tm_ac_oe     (tm_ac_oe),
        .tm_ac_dtack_n(tm_ac_dtack_n),
        .cfgout_n     (ac_chain2_n),
        .tm_base      (tm_base),
        .tm_configured(tm_configured),
        .maprom_load  (maprom_load),
        .maprom_active(maprom_active)
    );

    end else begin : g_no_fastmem
    assign fm_space = 1'b0;  assign fm_active = 1'b0; assign fm_dtack_n = 1'b1;
    assign fm_int_win = 1'b0; assign tm_int_win = 1'b0;
    assign fm_win   = 1'b0;
    assign fm_cfg_on = 1'b0; assign fm_cfg_match = 8'h00;
    assign dp_ack   = 1'b0; assign dp_rdata = 16'h0000;
    assign fm_dout  = 16'hFFFF;
    assign fm_ac_access = 1'b0; assign fm_ac_oe = 1'b0; assign fm_ac_dtack_n = 1'b1;
    assign fm_ac_dout = 4'hF;
    assign tm_space = 1'b0;  assign tm_active = 1'b0; assign tm_dtack_n = 1'b1;
    assign tm_dout  = 16'hFFFF;
    assign tm_ac_access = 1'b0; assign tm_ac_oe = 1'b0; assign tm_ac_dtack_n = 1'b1;
    assign tm_ac_dout = 4'hF;
    assign tm_base = 8'h00; assign tm_configured = 1'b0;
    assign maprom_load = 1'b0; assign maprom_active = 1'b0;
    assign spd_wr = 1'b0; assign spd_val = 2'd0; assign spd_smp = 2'd0;   // TG68 step 13
    assign ac_chain2_n = s_cfgin_n[1];        // chain passes straight through
    assign ac_chain_n  = s_cfgin_n[1];
    assign sd_req = 1'b0; assign sd_we = 1'b0; assign sd_saddr = 24'd0;
    assign sd_wdata = 16'd0; assign sd_byte_en = 2'b00; assign sd_wr_valid = 1'b0;
    end endgenerate

    // ---------------------------------------------------------------------
    // SD card: autoconfig shell + subsystem, LAST on the chain.
    //
    // Both are Niklas Ekstrom's SF2000 design. The autoconfig register
    // values and write semantics are byte-identical to it, which is the
    // whole point -- the unmodified sfsd.rom / sfsd.device bind without a
    // driver fork, and that is why this board keeps 5194/11 rather than
    // taking an ID of its own.
    //
    // Two decode changes were needed for Base64 and are documented at the
    // point of change in each file: the a[31:24] == $00 guard (fx68k drives
    // A31-A24; the SF2000's MC68SEC000 physically cannot), and a registered
    // address compare on sd_space.
    //
    // sfsd.mem is a 32 KB byte-wide image = 16 EBRs, taking the design from
    // 5 to 21 of 56. Like turbomem.mem it MUST be a member of the Diamond
    // project, and Clean deletes it from impl1/.
    // ---------------------------------------------------------------------
    wire sd_ss_n_i, sd_sclk_i, sd_mosi_i;
    // TG68: SD card is built only with ENABLE_SD.
    generate if (ENABLE_SD) begin : g_sd
    autoconfig_zii #(
        .MFG_ID     (16'h144A),
        .SD_PROD_ID (8'd11),      // see the ID allocation block above
        .SERIAL     (16'd0)
    ) u_sd_autoconfig (
        .clk          (clk),
        .reset        (slave_reset),
        .cfgin_n      (ac_chain2_n),
        .as_n         (core_as_n),
        .uds_n        (core_uds_n),
        .lds_n        (core_lds_n),
        .rw           (core_rw),
        .a_high       (core_a[31:16]),
        .a_low        (core_a[6:1]),
        .d_in         (core_dout[15:12]),
        .d_out        (sd_ac_dout),
        .data_oe      (sd_ac_oe),
        .ac_access    (sd_ac_access),
        .ac_win       (sd_ac_win),
        .base_sd      (base_sd),
        .sd_configured(sd_configured),
        .cfgout_n     (cfgout_n),
        .dtack_n      (sd_ac_dtack_n)
    );

    // SPI-mode wiring onto the slot's SD pins: CLK -> SCLK, CMD -> MOSI,
    // DAT0 -> MISO, DAT3 -> CS. DAT1/DAT2 are unused in SPI mode and left
    // released. The slot has no card-detect line, so CD_n is tied asserted.
    sd_subsystem #(
`ifdef TG68_X16
        // TG68: at 16x the fastest SCLK settings would exceed SD's limits
        // (56.8 / 28.4 MHz); one extra clock low gives 37.8 / 22.7 MHz
        // (see shifter.v)
        .SD_LO_EXTRA(1),
`endif
        .ROM_INIT_FILE("sfsd.mem")
    ) u_sd (
        .sd_lo_x      (spd_lox),         // TG68 step 13: 16x clock in force
        .clk          (clk),
        .reset        (slave_reset),
        .a            (core_a),
        .as_n         (core_as_n),
        .uds_n        (core_uds_n),
        .lds_n        (core_lds_n),
        .rw           (core_rw),
        .d_in         (core_dout),
        .sd_configured(sd_configured),
        .base_sd      (base_sd),
        .sd_space     (sd_space),
        .sd_int_win   (sd_int_win),
        .d_out        (sd_dout),
        .dtack_n      (sd_dtack_n),
        .rom_we       (1'b0),        // flash_preload not instantiated
        .rom_waddr    (15'd0),
        .rom_wdata    (8'd0),
        .sd_miso      (sd_miso_pin),
        .sd_cd_n      (1'b0),
        .sd_ss_n      (sd_ss_n_i),
        .sd_sclk      (sd_sclk_i),
        .sd_mosi      (sd_mosi_i)
    );

    end else begin : g_no_sd
    assign sd_space = 1'b0; assign sd_dtack_n = 1'b1; assign sd_dout = 16'hFFFF;
    assign sd_int_win = 1'b0; assign sd_ac_win = 1'b0;
    assign sd_ac_access = 1'b0; assign sd_ac_oe = 1'b0; assign sd_ac_dtack_n = 1'b1;
    assign sd_ac_dout = 4'hF; assign base_sd = 8'h00; assign sd_configured = 1'b0;
    assign cfgout_n = ac_chain2_n;
    assign sd_ss_n_i = 1'b1; assign sd_sclk_i = 1'b0; assign sd_mosi_i = 1'b0;
    end endgenerate

    wire sdram_clk_int;
    // TG68: the SDRAM controller only exists with fast RAM. Without it the
    // chip is held deselected with its clock disabled.
    generate if (ENABLE_FASTMEM) begin : g_sdram
`ifdef TG68_X16
    // TG68: at 16x (8.81 ns) the IS42S16160 (-7) needs CL3: CL2 wants
    // tCK >= 10 ns. The other counts stay: the controller adds 1-2 clocks of
    // state overhead to each, so at 113.5 MHz they give tRCD 4 clocks
    // (35 ns, needs 20), tRP 3 (26 ns, 20), tRAS 6 (53 ns, 45) and tRFC 8
    // (70 ns, 65); the fastmem bench's SDRAM model, which checks these in
    // ns, reports no violation at 16x. CLK_HZ sets the init wait.
    sdram_ctrl #(.CLK_HZ(113_500_000), .CAS_LAT(3)) u_sdram (
`else
    sdram_ctrl #(.CLK_HZ(85_130_000), .CAS_LAT(2)) u_sdram (
`endif
        .clk (clk), .reset (slave_reset),
        .req (sd_req), .we (sd_we), .wr_valid (sd_wr_valid),
        .addr (sd_saddr), .wdata (sd_wdata), .byte_en (sd_byte_en),
        // TG68: pair writes come straight from the adapter (fastmem_zii only
        // passes dp_wdata through when BUS_RAM=0, as built here)
        .pair (dp_pair), .wdata_lo (dp_wdata_lo),
        // TG68 step 13: the speed switch's CAS latency change
        .cfg_req (sdram_cfg_req), .cfg_cl3 (sdram_cfg_cl3), .cl3_now (sdram_cl3),
        .rfc_long (spd_rfc),              // exp-18x: tRFC + 1 at 18x
        .ack (sd_ack), .ack_early (sd_ack_early),
        .rdata_live (sd_rdata_live), .rdata (sd_rdata), .ready (sd_ready),
        .sdram_a (sdram_a), .sdram_ba (sdram_ba), .sdram_dq (sdram_dq),
        .sdram_dqm (sdram_dqm), .sdram_clk (sdram_clk_int),
        .sdram_cke (sdram_cke), .sdram_cs_n (sdram_cs_n),
        .sdram_ras_n (sdram_ras_n), .sdram_cas_n (sdram_cas_n),
        .sdram_we_n (sdram_we_n)
    );

    end else begin : g_no_sdram
    assign sd_ack = 1'b0; assign sd_ack_early = 1'b0; assign sd_ready = 1'b0;
    assign sdram_cl3 = sdram_cfg_cl3;     // TG68 step 13: nothing to reload
    assign sd_rdata_live = 16'd0; assign sd_rdata = 16'd0;
    assign sdram_a = 13'd0; assign sdram_ba = 2'd0;
`ifdef YOSYS
    // TG68: the same trap as the SD card pins above: yosys turns a constant
    // 1'bz into a constant 0 driver, so DQ was driven LOW in the min build.
    // Bidirectional buffers with the output permanently off make the pins
    // true inputs. (Diamond honours 1'bz, so the other branch is the original.)
    for (genvar dqi = 0; dqi < 16; dqi = dqi + 1) begin : g_dq
        BB u_dq (.I(1'b0), .T(1'b1), .O(), .B(sdram_dq[dqi]));
    end
`else
    assign sdram_dq = 16'bz;
`endif
    assign sdram_dqm = 2'b11; assign sdram_cke = 1'b0; assign sdram_cs_n = 1'b1;
    assign sdram_ras_n = 1'b1; assign sdram_cas_n = 1'b1; assign sdram_we_n = 1'b1;
    end endgenerate

    // SDRAM clock out through an ODDR so it leaves the die on the same path
    // as the data, rather than through fabric. D0/D1 = 0/1 gives the chip a
    // clock edge in the middle of our data window; swap them if the memory
    // proves marginal.
    ODDRX1F u_sdram_clk (.D0(1'b0), .D1(1'b1), .SCLK(clk),
                         .RST(1'b0), .Q(sdram_clk));

    // A cycle that never reaches the motherboard. A missing term here is
    // silent and nasty: the retime FSM would drive AS out to the motherboard
    // for a cycle we are already answering on-chip.
    // TG68: hi_null. A 68020 drives all 32 address lines and the Amiga
    // bus only has 24, so without this every access with A31-A24 != 0 would
    // reach the motherboard as a mirror of the 24-bit map -- Kickstart's
    // probes of Zorro III space ($FF000000) would land on the ROM. Cycles
    // nobody on-chip claims are answered here with $FFFF and DTACK, which is
    // what an empty 32-bit slot looks like. Exempt: CPU space (FC=7, IACK)
    // must reach Gary, and $08xxxxxx belongs to fast RAM when built.
    // Registered like the slaves' own decodes: the address is stable >= 3
    // clocks before AS falls.
    reg hi_null_r = 1'b0;
    always @(posedge clk)
        hi_null_r <= (core_a[31:24] != 8'h00) && (core_fc != 3'b111)
                     && !(ENABLE_FASTMEM && core_a[31:24] == 8'h08);
    wire hi_space = hi_null_r & ~core_as_n;

    wire int_space = fm_space | fm_ac_access
                   | tm_space | tm_ac_access
                   | sd_space | sd_ac_access
                   | hi_space;                           // TG68

    // TG68: int_space without its AS term, registered. The bridge only asks
    // "is this cycle internal?" while AS is already low (it commits a cycle
    // to the motherboard at tick_r), so the AS term adds nothing there --
    // but it put the core's AS register at the head of a long path through
    // every slave's decode into the clock enables of the pin registers.
    // Every term is a window decode of the address, which changes at
    // DECIDE, two clocks before the AS pin falls; the registered decodes
    // follow it one clock later. So int_win_r is valid from the clock AS
    // falls, and nothing waits for it.
    wire int_win = fm_int_win | tm_int_win | sd_int_win | sd_ac_win | hi_null_r;
    reg  int_win_r = 1'b0;
    always @(posedge clk) int_win_r <= int_win;

    // ========================================================================
    // 11b. Reveal debug bundle
    // ========================================================================
    // syn_keep so none of these get optimised or renamed away -- in Reveal
    // you can then just add the single net "dbg" and get everything.
    //
    //  bit  name            what it tells you
    //  4:0  ph              position on the 7M grid (0 = tick_r, 6 = tick_f)
    //  8:5  st              bridge FSM state (0=IDLE, 1..8=S0..S7)
    //  9    p_as_n          our AS output register
    // 10    cpu_dtack_n     RAW motherboard DTACK, before the 2FF
    // 11    s_dtack_n[1]    DTACK after the 2FF (what the FSM acts on)
    // 12    cpu_vpa_n       RAW VPA (high = normal cycle, low = CIA/IACK)
    // 13    core_as_n       the core's request
    // 14    core_dtack_lo   our ack back to the core
    // 15    bx_req          a cycle is pending in the bridge
    // 16    bus_owned       we own the bus
    // 17    s0_enter        one-clock pulse at the start of every bus cycle
    // 20:18 cpu_a[3:1]      enough address to tell cycles apart
    // 21    p_rw            read(1)/write(0)
    // 22    e_pin           our E clock
    // 23    p_vma_n         our VMA
    // DBG_BUNDLE=0 removes this entirely. syn_keep forces 24 nets to survive
    // optimisation, which costs routing and can push a marginal build over
    // into a Timing Check Error. Turn it off for production builds.
    (* syn_keep = 1 *) wire [23:0] dbg = !DBG_BUNDLE ? 24'd0 : {
        p_vma_n, e_pin, p_rw, p_a[3:1], s0_enter, bus_owned,
        bx_req, core_dtack_lo, core_as_n, cpu_vpa_n, s_dtack_n[1],
        cpu_dtack_n, p_as_n, st, ph
    };

    // ========================================================================
    // 12. LEDs
    // ========================================================================
    // Green: E heartbeat (or blinked cycle length when LAT_DEBUG).
    // Red:   held in reset, OR a sticky 7M phase slip (should never light).
    // Blue:  bus connected.
    reg [20:0] e_div = 21'd0;
    always @(posedge clk) if (e_fall_tick) e_div <= e_div + 21'd1;

    // Shortest observed CYCLE PITCH (S0 -> S0) in 7M clocks.
    //   4 = perfect, chaining back to back like a stock 68000
    //   5 = one extra 7M clock somewhere in the handshake
    // This deliberately measures pitch, NOT AS-low width. AS-low is 2.5
    // clocks on a no-wait 68000 cycle and tells you nothing about whether
    // cycles are chaining; pitch is the number that maps onto SysInfo's
    // chip-speed ratio (4/5 = 0.80).
    reg [7:0] len_ctr = 8'd0, len_min = 8'hFF;
    reg       seen_s0 = 1'b0;
    reg [3:0] st_d    = ST_IDLE;
    always @(posedge clk) st_d <= st;
    // Entry into S0, one master clock after the tick_r that caused it.
    // The previous version tested (tick_r && st == ST_S0), which can NEVER
    // be true: st is assigned ST_S0 ON that tick_r, so it does not read
    // back as ST_S0 until the following clock, by which time tick_r is
    // gone. len_min therefore stayed at its 8'hFF init and the blinker
    // showed the low nibble, 15. Fifteen blinks means "never measured".
    wire s0_enter = (st == ST_S0) && (st_d != ST_S0);
    always @(posedge clk) begin
        if (ext_reset) begin
            len_ctr <= 8'd0; len_min <= 8'hFF; seen_s0 <= 1'b0;
        end else if (s0_enter) begin
            if (seen_s0 && len_ctr != 8'd0 && len_ctr < len_min)
                len_min <= len_ctr;
            len_ctr <= 8'd0;
            seen_s0 <= 1'b1;
        end else if (tick_r && seen_s0 && len_ctr < 8'd60) begin
            len_ctr <= len_ctr + 8'd1;
        end
    end

    reg [23:0] blink_div = 24'd0;
    reg [3:0]  blink_ph  = 4'd0;
    reg        blink_on  = 1'b0, in_pause = 1'b1;
    reg [25:0] pause_div = 26'd0;
    always @(posedge clk) begin
        if (in_pause) begin
            blink_on  <= 1'b0;
            pause_div <= pause_div + 26'd1;
            if (pause_div[25]) begin
                pause_div <= 26'd0; in_pause <= 1'b0;
                blink_ph  <= 4'd0;  blink_div <= 24'd0;
            end
        end else begin
            blink_div <= blink_div + 24'd1;
            if (blink_div == 24'hFFFFFF) begin
                blink_on <= ~blink_on;
                if (blink_on) begin
                    blink_ph <= blink_ph + 4'd1;
                    if (blink_ph + 4'd1 >= len_min[3:0]) in_pause <= 1'b1;
                end
            end
        end
    end

    assign led_g = LAT_DEBUG ? blink_on : e_div[20];
    // TG68: red also means "a bus cycle has waited ~100 ms for DTACK".
    assign led_r = ph_slip | ~core_ohalted_n | tg_stalled;
    // Blue: the core is OUT of reset. This is the diagnostic that matters at
    // cold boot, because it separates the two failure modes:
    //
    //   blue never lights      the core never left reset. Either the pulse
    //                          is not being issued, or cold_armed is still
    //                          waiting because something is holding /RESET
    //                          or /HALT low.
    //   blue lights, red on    the core started and double bus faulted --
    //                          it is running but cannot fetch. Look at OVL
    //                          and the ROM overlay, not at reset.
    //   blue lights, red off,
    //   still no boot          the core is running into a machine that is
    //                          in the wrong state.
    //
    // The previous cold_rst | bus_enable was useless: bus_enable takes over
    // the instant cold_rst drops, so there was no visible transition.
    assign led_b = ~ext_reset;

endmodule

`default_nettype wire
