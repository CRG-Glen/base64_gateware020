| speed -- show or change the Base64 TG68 system clock while running.
|
|   speed             report the clock in force, change nothing
|   speed 12          85.1 MHz, the ICS570B's own clock (power-on default)
|   speed 14          99.3 MHz, from the FPGA's PLL
|   speed 16          113.5 MHz, from the FPGA's PLL
|   speed 16 RISE     the same, with the 7 MHz sample forced to the rising
|   speed 16 FALL     or falling clock edge (normally calibrated: see below)
|
| Asking for the speed already in force recalibrates the 7 MHz capture.
|
| The gateware (step 13) has a speed register in the AutoConfig ROM board
| (5194/14) at board+$F00A, next to mapROM's control register. A write is
| taken only when the high byte is $5B:
|   $5B0C / $5B0E / $5B10   ask for 12x / 14x / 16x (anything else ignored)
|   +$40 / +$80             force the 7 MHz sample to the rising / falling
|                           clock edge
| A read gives
|   bits 7-0   multiplier in force (12, 14 or 16)
|   bit  8     14x PLL locked
|   bit  9     16x PLL locked
|   bit  10    run-time switching present (0: the fixed-clock board-mod
|              build, or gateware before step 13, which reads 0 here)
|   bit  11    a switch is in progress
|   bit  12    the 7 MHz clock is sampled on the rising edge (else falling)
|   bit  13    the falling-edge sample has moved since the last calibration
|   bit  14    the rising-edge sample has moved since then
|   bit  15    the 7 MHz phase aligner has slipped since then (red LED)
|
| Why the calibration: the clock reaches the FPGA's flip-flops through the
| speed multiplexer, whose delay depends on the speed and the build, and can
| put one of the two samples right on a 7 MHz transition. Power-up (for
| ~0.33 s of the hold) and each switch (65536 cycles, ~9 ms) watch both
| and keep the falling-edge one unless it moves more than the rising-edge
| one. Bits 13-15 show whether
| anything moved later, for testing; RISE / FALL override the choice.
|
| The switch itself is done by the gateware: it holds the CPU between bus
| cycles, waits for the buses and the SDRAM to go idle, changes the SDRAM's
| CAS latency if needed, switches the clock glitch-free and re-locks to the
| Amiga's 7 MHz. That takes a few microseconds; nothing in software has to
| be stopped. Chip DMA, interrupts and the CIAs run on through it.
|
| The speed stays in force over a reset. Only a power cycle (the FPGA
| reloading) goes back to 12x. So if a speed is too fast for a board and the
| machine crashes, switching off and on again undoes it.
|
| The board needs its ICS570B strapped for 12x (the stock setting): the PLLs
| make 14x and 16x from it. With the x16 board mod use the _x16 bitstream,
| which has a fixed clock and no switching.
|
| Position independent (all data PC-relative), no relocations: mkhunk.py
| wraps the flat binary as a one-hunk AmigaOS executable. 68000 code.

        .equ    LVO_CloseLibrary,  -414
        .equ    LVO_OpenLibrary,   -552
        .equ    LVO_Write,         -48
        .equ    LVO_Output,        -60
        .equ    LVO_FindConfigDev, -72
        .equ    cd_BoardAddr,      32

        .equ    MFG_ID,     5194
        .equ    PROD_TURBO, 14
        .equ    MAGIC,      0x544D
        .equ    SPD_REG,    0x0A            | offset in the status window
        .equ    SPD_KEY,    0x5B00
        .equ    B_LOCK14,   8
        .equ    B_LOCK16,   9
        .equ    B_SWITCH,   10
        .equ    B_BUSY,     11
        .equ    B_RISE,     12
        .equ    B_JITF,     13
        .equ    B_JITR,     14
        .equ    B_SLIP,     15

| variable block offsets (a5)
        .equ    v_sys,   0
        .equ    v_dos,   4
        .equ    v_exp,   8
        .equ    v_out,   12
        .equ    v_rc,    16
        .equ    v_buf,   20                 | 16 bytes of scratch

        .text
        .globl  _start
_start:
        movem.l %d2-%d7/%a2-%a6,-(%sp)
        move.l  %a0,%a4                     | command line
        move.l  %d0,%d7                     | its length
        lea     vars(%pc),%a5
        move.l  4.w,%a6
        move.l  %a6,v_sys(%a5)
        moveq   #20,%d0
        move.l  %d0,v_rc(%a5)

        lea     dosname(%pc),%a1
        moveq   #0,%d0
        jsr     LVO_OpenLibrary(%a6)
        move.l  %d0,v_dos(%a5)
        beq     exit
        move.l  %d0,%a6
        jsr     LVO_Output(%a6)
        move.l  %d0,v_out(%a5)

        | ---- the argument first: a bad one needs no hardware ----
        | d6 = requested multiplier, 0 for a report
        moveq   #0,%d6
        move.l  %a4,%a0
        move.l  %d7,%d1
1:      tst.l   %d1                         | skip blanks
        beq   args_done
        move.b  (%a0),%d0
        cmp.b   #' ',%d0
        beq.s   2f
        cmp.b   #9,%d0
        bne.s   3f
2:      addq.l  #1,%a0
        subq.l  #1,%d1
        bra.s   1b
3:      cmp.b   #10,%d0
        beq   args_done
        moveq   #0,%d2                      | decimal number, up to 3 digits
        moveq   #0,%d3                      | digits seen
4:      tst.l   %d1
        beq.s   5f
        move.b  (%a0)+,%d0
        subq.l  #1,%d1
        cmp.b   #'0',%d0
        blt.s   5f
        cmp.b   #'9',%d0
        bgt.s   5f
        sub.b   #'0',%d0
        and.w   #0xFF,%d0
        mulu    #10,%d2
        add.w   %d0,%d2
        addq.w  #1,%d3
        cmp.w   #3,%d3
        bls.s   4b
        bra     usage
5:      tst.w   %d3                         | not a number: STATUS, ? or junk
        beq.s   6f
        cmp.w   #12,%d2
        beq.s   7f
        cmp.w   #14,%d2
        beq.s   7f
        cmp.w   #16,%d2
        bne     usage
7:      move.w  %d2,%d6
        | then RISE or FALL, optional (only the first letter counts)
        cmp.b   #' ',%d0                    | what ended the number
        beq.s   8f
        cmp.b   #9,%d0
        bne     args_done                   | end of line (or "16x")
8:      tst.l   %d1
        beq     args_done
        move.b  (%a0)+,%d0
        subq.l  #1,%d1
        cmp.b   #' ',%d0
        beq.s   8b
        cmp.b   #9,%d0
        beq.s   8b
        cmp.b   #10,%d0
        beq     args_done
        or.b    #0x20,%d0
        cmp.b   #'r',%d0
        bne.s   9f
        or.w    #0x40,%d6
        bra     args_done
9:      cmp.b   #'f',%d0
        bne     usage
        or.w    #0x80,%d6
        bra     args_done
6:      or.b    #0x20,%d0
        cmp.b   #'s',%d0                    | STATUS
        beq   args_done
usage:
        lea     m_usage(%pc),%a0
        bsr     puts
        moveq   #10,%d0
        move.l  %d0,v_rc(%a5)
        bra     close_dos

args_done:
        move.l  v_sys(%a5),%a6
        lea     expname(%pc),%a1
        moveq   #0,%d0
        jsr     LVO_OpenLibrary(%a6)
        move.l  %d0,v_exp(%a5)
        bne.s   1f
        lea     m_noexp(%pc),%a0
        bsr     puts
        bra     close_dos
1:
        | ---- find the AutoConfig ROM board ----
.ifdef TEST
        | test build (vamos): a fake board in RAM whose registers are plain
        | memory; TESTFIX makes it look like the fixed 16x build
        lea     fakeboard(%pc),%a3
        move.l  %a3,%a2
        add.l   #0xF000,%a2
        move.w  #MAGIC,(%a2)
.ifdef TESTFIX
        move.w  #0x0010,SPD_REG(%a2)
.else
.ifdef TESTJIT
        move.w  #0xF70C,SPD_REG(%a2)        | rising, both moved, slipped
.else
        move.w  #0x070C,SPD_REG(%a2)
.endif
.endif
.else
        move.l  %d0,%a6
        sub.l   %a0,%a0
        move.l  #MFG_ID,%d0
        moveq   #PROD_TURBO,%d1
        jsr     LVO_FindConfigDev(%a6)
        tst.l   %d0
        bne.s   2f
        lea     m_noboard(%pc),%a0
        bsr     puts
        bra     close_exp
2:      move.l  %d0,%a0
        move.l  cd_BoardAddr(%a0),%a3       | a3 = board base
        move.l  %a3,%a2
        add.l   #0xF000,%a2                 | a2 = status window
.endif
        | magic as two byte reads, as maprom does
        moveq   #0,%d0
        move.b  (%a2),%d0
        lsl.w   #8,%d0
        move.b  1(%a2),%d0
        cmp.w   #MAGIC,%d0
        beq.s   3f
        lea     m_nowin(%pc),%a0
        bsr     puts
        bra     close_exp
3:      move.w  SPD_REG(%a2),%d5            | d5 = speed register
        btst    #B_SWITCH,%d5
        bne.s   4f
        | no run-time switching: a fixed 16x build reads $0010, an older
        | gateware 0
        lea     m_noswitch(%pc),%a0
        bsr     puts
        bsr     report
        tst.w   %d6
        beq     ok_exit                     | a report is all that was asked
        bra     close_exp
4:      tst.w   %d6
        beq     do_report

        | ---- switch (or recalibrate) ----
        move.w  %d6,%d4                     | d4 = what gets written
        and.w   #0x3F,%d6                   | d6 = the multiplier alone
        moveq   #0,%d0
        move.b  %d5,%d0
        cmp.w   %d6,%d0
        bne.s   5f
        lea     m_recal(%pc),%a0            | same speed: a recalibration
        bsr     puts
5:      cmp.w   #14,%d6                     | its PLL must be locked
        bne.s   6f
        btst    #B_LOCK14,%d5
        bne.s   7f
        lea     m_nolock14(%pc),%a0
        bsr     puts
        bra     close_exp
6:      cmp.w   #16,%d6
        bne.s   7f
        btst    #B_LOCK16,%d5
        bne.s   7f
        lea     m_nolock16(%pc),%a0
        bsr     puts
        bra     close_exp
7:      move.w  %d4,%d0
        or.w    #SPD_KEY,%d0
        move.w  %d0,SPD_REG(%a2)            | the gateware does the rest
.ifdef TEST
        move.w  %d6,%d0                     | fake board: the answer
        or.w    #0x0700,%d0
        btst    #6,%d4
        beq.s   1f
        bset    #B_RISE,%d0
1:      move.w  %d0,SPD_REG(%a2)
.endif
        | the CPU is held while it switches, so the next read normally sees
        | it done; poll anyway, with a limit
        move.l  #100000,%d2
8:      move.w  SPD_REG(%a2),%d5
        btst    #B_BUSY,%d5
        bne.s   9f
        moveq   #0,%d0
        move.b  %d5,%d0
        cmp.w   %d6,%d0
        beq.s   do_report
9:      subq.l  #1,%d2
        bne.s   8b
        lea     m_timeout(%pc),%a0
        bsr     puts
        bsr     report
        bra.s   close_exp

do_report:
        bsr     report
ok_exit:
        clr.l   v_rc(%a5)

close_exp:
        move.l  v_sys(%a5),%a6
        move.l  v_exp(%a5),%a1
        jsr     LVO_CloseLibrary(%a6)
close_dos:
        move.l  v_sys(%a5),%a6
        move.l  v_dos(%a5),%a1
        jsr     LVO_CloseLibrary(%a6)
exit:
        move.l  v_rc(%a5),%d0
        movem.l (%sp)+,%d2-%d7/%a2-%a6
        rts

| ---- report: the speed register (d5) in words ---------------------------
report:
        lea     m_speed(%pc),%a0
        bsr     puts
        lea     m_x12(%pc),%a0
        cmp.b   #12,%d5
        beq.s   1f
        lea     m_x14(%pc),%a0
        cmp.b   #14,%d5
        beq.s   1f
        lea     m_x16(%pc),%a0
        cmp.b   #16,%d5
        beq.s   1f
        lea     m_xunk(%pc),%a0
1:      bsr     puts
        btst    #B_SWITCH,%d5
        beq.s   2f
        lea     m_avail(%pc),%a0
        bsr     puts
        lea     m_a12(%pc),%a0
        bsr     puts
        btst    #B_LOCK14,%d5
        beq.s   3f
        lea     m_a14(%pc),%a0
        bsr     puts
3:      btst    #B_LOCK16,%d5
        beq.s   4f
        lea     m_a16(%pc),%a0
        bsr     puts
4:      lea     m_nl(%pc),%a0
        bsr     puts
        lea     m_smp(%pc),%a0
        bsr     puts
        lea     m_rise(%pc),%a0
        btst    #B_RISE,%d5
        bne.s   5f
        lea     m_fall(%pc),%a0
5:      bsr     puts
        btst    #B_JITF,%d5
        beq.s   6f
        lea     m_jitf(%pc),%a0
        bsr     puts
6:      btst    #B_JITR,%d5
        beq.s   2f
        lea     m_jitr(%pc),%a0
        bsr     puts
2:      btst    #B_SLIP,%d5
        beq.s   7f
        lea     m_slip(%pc),%a0
        bsr     puts
7:      lea     m_reg(%pc),%a0
        bsr     puts
        move.l  %d5,%d0
        bsr     puthex4
        lea     m_nl(%pc),%a0
        bsr     puts
        rts

| ---- output ----------------------------------------------------------------
| puts: a0 = NUL-terminated string. Keeps all registers.
puts:
        movem.l %d0-%d3/%a0-%a1/%a6,-(%sp)
        move.l  %a0,%d2
        moveq   #-1,%d3
1:      addq.l  #1,%d3
        tst.b   (%a0)+
        bne.s   1b
        tst.l   %d3
        beq.s   2f
        move.l  v_dos(%a5),%a6
        move.l  v_out(%a5),%d1
        beq.s   2f
        jsr     LVO_Write(%a6)
2:      movem.l (%sp)+,%d0-%d3/%a0-%a1/%a6
        rts

| puthex4: d0 low word -> 4 hex digits. Keeps all registers.
puthex4:
        movem.l %d0-%d2/%a0,-(%sp)
        swap    %d0
        moveq   #3,%d2
        lea     v_buf(%a5),%a0
1:      rol.l   #4,%d0
        moveq   #15,%d1
        and.b   %d0,%d1
        cmp.b   #10,%d1
        blt.s   2f
        addq.b  #7,%d1
2:      add.b   #'0',%d1
        move.b  %d1,(%a0)+
        dbra    %d2,1b
        clr.b   (%a0)
        lea     v_buf(%a5),%a0
        bsr     puts
        movem.l (%sp)+,%d0-%d2/%a0
        rts

| ---- text ------------------------------------------------------------------
dosname:    .asciz  "dos.library"
expname:    .asciz  "expansion.library"
verstag:    .asciz  "$VER: speed 1.1 (10.11.2026) Base64"
m_usage:    .asciz  "Usage: speed               show the clock in force\n       speed 12            85.1 MHz (power-on default)\n       speed 14            99.3 MHz\n       speed 16           113.5 MHz\n       speed <n> RISE|FALL  force the 7 MHz sampling edge\nThe speed stays over a reset; a power cycle returns to 12.\nThe speed in force again: recalibrate the 7 MHz capture.\n"
m_noexp:    .asciz  "cannot open expansion.library\n"
m_noboard:  .asciz  "No Base64 AutoConfig ROM board found (5194/14).\n"
m_nowin:    .asciz  "Board found, but no status window - gateware is too old.\n"
m_noswitch: .asciz  "This gateware cannot change the clock while running\n(the fixed-clock x16 build, or one older than step 13).\n"
m_recal:    .asciz  "Same speed: recalibrating the 7 MHz capture.\n"
m_nolock14: .asciz  "The 14x PLL is not locked: speed not changed.\n"
m_nolock16: .asciz  "The 16x PLL is not locked: speed not changed.\n"
m_timeout:  .asciz  "The gateware did not finish the switch.\n"
m_speed:    .asciz  "System clock: "
m_x12:      .asciz  "12x  85.1 MHz\n"
m_x14:      .asciz  "14x  99.3 MHz\n"
m_x16:      .asciz  "16x 113.5 MHz\n"
m_xunk:     .asciz  "unknown\n"
m_avail:    .asciz  "Available:    "
m_a12:      .asciz  " 12"
m_a14:      .asciz  " 14"
m_a16:      .asciz  " 16"
m_smp:      .asciz  "7 MHz sample: "
m_rise:     .asciz  "rising edge\n"
m_fall:     .asciz  "falling edge\n"
m_jitf:     .asciz  "  the falling-edge sample has moved since the calibration\n"
m_jitr:     .asciz  "  the rising-edge sample has moved since the calibration\n"
m_slip:     .asciz  "  the 7 MHz phase aligner has slipped since then\n"
m_reg:      .asciz  "Register:     $"
m_nl:       .asciz  "\n"
        .balign 4
vars:   .space  40
.ifdef TEST
        .balign 4
fakeboard: .space 0x10000
.endif
