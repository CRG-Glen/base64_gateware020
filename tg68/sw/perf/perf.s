| perf -- read the Base64 TG68 performance counters (step 18 test builds).
|
|   perf              freeze the counters, print them all, and let them run
|                     on if they were running
|   perf CLEAR        zero them and start them
|   perf FREEZE       stop them
|   perf RUN          start them (without zeroing)
|   perf >RAM:p.txt   (any of these, into a file)
|
| Typical use: perf CLEAR, run the program to measure, then perf. A program
| that can only be left with a reset: the counters freeze by themselves at
| the reset and keep their numbers, so run perf after the reboot.
|
| Only test bitstreams built with build.py --perf have the counters. The
| gateware (perf_cnt.v) puts them in the AutoConfig ROM board (5194/14),
| board+$F00E and +$F010-$F014, next to the speed register:
|   +$F00E write $5Cxx: xx = 00nnnnnn select counter n, $40 freeze,
|          $80 run, $C0 clear (the run state stays)
|   +$F00E read: bit 15 running, bit 14 frozen by an Amiga reset, bits
|          13-8 the number of counters (0: no counters in this gateware),
|          bits 5-0 the counter selected
|   +$F010 / +$F012 / +$F014: the selected counter, bits 15-0, 31-16, 39-32
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
        .equ    SPD_REG,    0x0A            | offsets in the status window
        .equ    PERF_REG,   0x0E
        .equ    PERF_LO,    0x10
        .equ    PERF_MID,   0x12
        .equ    PERF_HI,    0x14
        .equ    KEY_SEL,    0x5C00
        .equ    KEY_FREEZE, 0x5C40
        .equ    KEY_RUN,    0x5C80
        .equ    KEY_CLEAR,  0x5CC0

| variable block offsets (a5)
        .equ    v_sys,   0
        .equ    v_dos,   4
        .equ    v_exp,   8
        .equ    v_out,   12
        .equ    v_rc,    16
        .equ    v_buf,   20                 | 24 bytes of scratch

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

        | ---- the argument: only its first letter counts ----
        | d6 = 0 report, 1 CLEAR, 2 FREEZE, 3 RUN
        moveq   #0,%d6
        move.l  %a4,%a0
        move.l  %d7,%d1
1:      tst.l   %d1
        beq.s   args_done
        move.b  (%a0)+,%d0
        subq.l  #1,%d1
        cmp.b   #' ',%d0
        beq.s   1b
        cmp.b   #9,%d0
        beq.s   1b
        cmp.b   #10,%d0
        beq.s   args_done
        or.b    #0x20,%d0
        moveq   #1,%d6
        cmp.b   #'c',%d0
        beq.s   args_done
        moveq   #2,%d6
        cmp.b   #'f',%d0
        beq.s   args_done
        moveq   #3,%d6
        cmp.b   #'r',%d0
        beq.s   args_done
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
        | memory: 24 counters, running, every one reading 78187493530
        lea     fakeboard(%pc),%a3
        move.l  %a3,%a2
        add.l   #0xF000,%a2
        move.w  #MAGIC,(%a2)
        move.w  #0x070C,SPD_REG(%a2)
.ifdef TESTNONE
        move.w  #0x0000,PERF_REG(%a2)
.else
.ifdef TESTRST
        move.w  #0x5803,PERF_REG(%a2)       | frozen by a reset, counter 3
.else
        move.w  #0x9800,PERF_REG(%a2)
.endif
.endif
        move.w  #0x789A,PERF_LO(%a2)
        move.w  #0x3456,PERF_MID(%a2)
        move.w  #0x0012,PERF_HI(%a2)
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
        moveq   #0,%d0                      | magic as two byte reads
        move.b  (%a2),%d0
        lsl.w   #8,%d0
        move.b  1(%a2),%d0
        cmp.w   #MAGIC,%d0
        beq.s   3f
        lea     m_nowin(%pc),%a0
        bsr     puts
        bra     close_exp
3:      move.w  PERF_REG(%a2),%d5           | d5 = the counters' state
        move.w  %d5,%d4
        lsr.w   #8,%d4
        and.w   #0x3F,%d4                   | d4 = number of counters
        bne.s   4f
        lea     m_nocnt(%pc),%a0
        bsr     puts
        bra     close_exp
4:      cmp.w   #1,%d6
        bne.s   5f
        move.w  #KEY_CLEAR,PERF_REG(%a2)
        move.w  #KEY_RUN,PERF_REG(%a2)
        lea     m_cleared(%pc),%a0
        bra.s   said
5:      cmp.w   #2,%d6
        bne.s   6f
        move.w  #KEY_FREEZE,PERF_REG(%a2)
        lea     m_frozen(%pc),%a0
        bra.s   said
6:      cmp.w   #3,%d6
        bne.s   report
        move.w  #KEY_RUN,PERF_REG(%a2)
        lea     m_running(%pc),%a0
said:   bsr     puts
        bra     ok_exit

        | ---- report ----
report:
        move.w  #KEY_FREEZE,PERF_REG(%a2)   | one consistent set of numbers
        lea     m_wasrun(%pc),%a0
        btst    #15,%d5
        bne.s   1f
        lea     m_wasrst(%pc),%a0
        btst    #14,%d5
        bne.s   1f
        lea     m_wasfrz(%pc),%a0
1:      bsr     puts
        lea     m_speed(%pc),%a0
        bsr     puts
        moveq   #0,%d0
        move.b  SPD_REG+1(%a2),%d0
        moveq   #0,%d1
        moveq   #2,%d2
        bsr     putdec
        lea     m_x(%pc),%a0
        bsr     puts
        lea     m_head(%pc),%a0
        bsr     puts
        moveq   #0,%d3                      | d3 = counter number
        lea     names(%pc),%a4              | a4 = its name
7:      move.w  %d3,%d0
        or.w    #KEY_SEL,%d0
        move.w  %d0,PERF_REG(%a2)
        moveq   #0,%d0                      | number, 2 wide
        move.w  %d3,%d0
        moveq   #0,%d1
        moveq   #2,%d2
        bsr     putdec
        lea     m_sp(%pc),%a0
        bsr     puts
        move.l  %a4,%a0                     | name, padded to 40
        bsr     puts
        moveq   #-1,%d2
8:      addq.w  #1,%d2
        tst.b   (%a4)+
        bne.s   8b
        tst.b   (%a4)                       | past the last name: stay on ""
        bne.s   9f
        subq.l  #1,%a4
9:      lea     m_sp(%pc),%a0
10:     cmp.w   #40,%d2
        bge.s   11f
        bsr     puts
        addq.w  #1,%d2
        bra.s   10b
11:     move.w  PERF_MID(%a2),%d0           | the value: d1:d0 = bits 39:0
        swap    %d0
        move.w  PERF_LO(%a2),%d0
        moveq   #0,%d1
        move.w  PERF_HI(%a2),%d1
        and.w   #0xFF,%d1
        moveq   #14,%d2
        bsr     putdec
        lea     m_nl(%pc),%a0
        bsr     puts
        addq.w  #1,%d3
        cmp.w   %d4,%d3
        blt.s   7b
        btst    #15,%d5                     | running before: run on
        beq.s   12f
        move.w  #KEY_RUN,PERF_REG(%a2)
        lea     m_runon(%pc),%a0
        bra.s   13f
12:     lea     m_stays(%pc),%a0
13:     bsr     puts
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

| putdec: d1:d0 = a 48-bit number (d1 bits 15-0 are its bits 47-32), printed
| in decimal, right-aligned in d2 columns. Keeps all registers.
| 68000 divu: three 32/16 divisions by 10 per digit, high word first; the
| remainder (< 10) goes in front of the next word, so each quotient fits.
putdec:
        movem.l %d0-%d7/%a0,-(%sp)
        lea     v_buf+23(%a5),%a0           | digits are written backwards
        clr.b   (%a0)
        move.w  %d1,%d5                     | d5:d6:d7 = the number, 3 words
        move.l  %d0,%d6
        swap    %d6
        move.w  %d0,%d7
        moveq   #0,%d4                      | digits so far
1:      moveq   #0,%d3
        move.w  %d5,%d3
        divu    #10,%d3
        move.w  %d3,%d5
        move.w  %d6,%d3                     | remainder:next word
        divu    #10,%d3
        move.w  %d3,%d6
        move.w  %d7,%d3
        divu    #10,%d3
        move.w  %d3,%d7
        swap    %d3                         | the remainder: one digit
        add.b   #'0',%d3
        move.b  %d3,-(%a0)
        addq.w  #1,%d4
        move.w  %d5,%d3
        or.w    %d6,%d3
        or.w    %d7,%d3
        bne.s   1b
2:      cmp.w   %d2,%d4                     | pad on the left
        bge.s   3f
        move.b  #' ',-(%a0)
        addq.w  #1,%d4
        bra.s   2b
3:      bsr     puts
        movem.l (%sp)+,%d0-%d7/%a0
        rts

| ---- text ------------------------------------------------------------------
dosname:    .asciz  "dos.library"
expname:    .asciz  "expansion.library"
verstag:    .asciz  "$VER: perf 1.1 (27.11.2026) Base64"
m_usage:    .asciz  "Usage: perf          print the counters (they run on if they were running)\n       perf CLEAR    zero them and start them\n       perf FREEZE   stop them\n       perf RUN      start them\n"
m_noexp:    .asciz  "cannot open expansion.library\n"
m_noboard:  .asciz  "No Base64 AutoConfig ROM board found (5194/14).\n"
m_nowin:    .asciz  "Board found, but no status window - gateware is too old.\n"
m_nocnt:    .asciz  "This gateware has no performance counters (only the perf test builds do).\n"
m_cleared:  .asciz  "Counters cleared and running.\n"
m_frozen:   .asciz  "Counters frozen.\n"
m_running:  .asciz  "Counters running.\n"
m_wasrun:   .asciz  "The counters were running (frozen for this report).\n"
m_wasrst:   .asciz  "The counters were frozen by an Amiga reset.\n"
m_wasfrz:   .asciz  "The counters were frozen.\n"
m_speed:    .asciz  "System clock now: "
m_x:        .asciz  "x\n"
m_head:     .asciz  "\n # counter                                          count\n"
m_sp:       .asciz  " "
m_runon:    .asciz  "Running again.\n"
m_stays:    .asciz  "Still frozen: perf RUN or perf CLEAR to start them.\n"
m_nl:       .asciz  "\n"
| counter names, in the gateware's order (tg68_bus.v, PERFORMANCE COUNTER
| EVENTS); "bus" is the 68000-style bus to the motherboard and the slow
| slaves; an empty string ends the list
names:      .asciz  "clocks"
            .asciz  "CPU steps"
            .asciz  "  instruction fetches"
            .asciz  "    predicted (4 clocks)"
            .asciz  "    from the instruction cache"
            .asciz  "  data reads from the data cache"
            .asciz  "  internal steps"
            .asciz  "SDRAM fetches (cache misses)"
            .asciz  "SDRAM data reads (cache misses)"
            .asciz  "bus fetches, Chip RAM"
            .asciz  "bus fetches, elsewhere (ROM, slow RAM)"
            .asciz  "bus reads, Chip RAM"
            .asciz  "bus reads, elsewhere (custom, CIA)"
            .asciz  "bus writes, Chip RAM"
            .asciz  "bus writes, elsewhere"
            .asciz  "clocks in bus cycles"
            .asciz  "clocks waiting: Chip write buffer full"
            .asciz  "clocks waiting: fast RAM write"
            .asciz  "code dropped by writes"
            .asciz  "instruction-cache fills"
            .asciz  "fetch misses, same 4-word line as last"
            .asciz  "fetch misses, same 8-word line as last"
            .asciz  "data misses, same 4-word line as last"
            .asciz  "data misses, same 8-word line as last"
            .asciz  ""
        .balign 4
vars:   .space  48
.ifdef TEST
        .balign 4
fakeboard: .space 0x10000
.endif
