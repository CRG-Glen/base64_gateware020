| maprom -- show, switch off or (re)load the Base64 mapROM shadow.
|
| A port of the original project's fx68k/sw/turbomem/maprom.c to 68000
| assembly, so it builds with nothing but GNU as. Same commands, same
| procedure, same safety rules:
|
|   maprom            copy Kickstart into the SDRAM shadow and switch over
|   maprom OFF        switch back to the motherboard ROM
|   maprom STATUS     report, change nothing
|
| NOTE: the Base64 boot ROM (turbomem, built with DIAG_MAPROM=1) already
| does the copy-and-switch at every boot, so "maprom STATUS" will normally
| say mapROM is active. "maprom OFF" then "maprom" is how to compare.
|
| The gateware gives two bits in the AutoConfig ROM board (5194/14) at
| board+$F008, both cleared by reset, and only written when the high byte
| is $5A:
|   $5A01 LOAD    writes to $F80000-$FFFFFF and $E00000-$E7FFFF go to the
|                 SDRAM shadow; reads still come from the real ROM
|   $5A02 ACTIVE  reads of those ranges come from the shadow
|   $5A00 OFF
| So the copy is a plain loop with source and destination the same address.
|
| THE DANGEROUS MOMENT is setting ACTIVE: from then on every ROM fetch comes
| from the shadow. So the verify runs with interrupts off and calls nothing
| in ROM until it has decided (Disable() before, Enable() after -- by then
| the shadow has verified, or ACTIVE is already back off). Both banks are
| always copied verbatim: there is one ACTIVE bit for both ranges.
|
| Position independent (all data PC-relative), no relocations: mkhunk.py
| wraps the flat binary as a one-hunk AmigaOS executable. 68000 code, so it
| runs on the fx68k build too.

        .equ    LVO_Disable,       -120
        .equ    LVO_Enable,        -126
        .equ    LVO_CloseLibrary,  -414
        .equ    LVO_OpenLibrary,   -552
        .equ    LVO_Write,         -48
        .equ    LVO_Output,        -60
        .equ    LVO_FindConfigDev, -72
        .equ    cd_BoardAddr,      32

        .equ    MFG_ID,     5194
        .equ    PROD_TURBO, 14
        .equ    MAGIC,      0x544D
        .equ    MR_OFF,     0x5A00
        .equ    MR_LOAD,    0x5A01
        .equ    MR_ACTIVE,  0x5A02
        .equ    BOOT_BASE,  0x00F80000
        .equ    EXT_BASE,   0x00E00000
        .equ    BANK_LONGS, 0x20000         | 512 KB
        .equ    ROMID_256K, 0x11114EF9
        .equ    ROMID_512K, 0x11144EF9

| variable block offsets (a5)
        .equ    v_sys,   0
        .equ    v_dos,   4
        .equ    v_exp,   8
        .equ    v_out,   12
        .equ    v_rc,    16
        .equ    v_bsum,  20
        .equ    v_esum,  24
        .equ    v_buf,   28                 | 16 bytes of scratch

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
        | test build (vamos): a fake board in RAM whose control register
        | is plain memory
        lea     fakeboard(%pc),%a3
        move.l  %a3,%a2
        add.l   #0xF000,%a2
        move.w  #MAGIC,(%a2)
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
        | magic as two byte reads (the habit cfgdump learned the hard way)
        moveq   #0,%d0
        move.b  (%a2),%d0
        lsl.w   #8,%d0
        move.b  1(%a2),%d0
        cmp.w   #MAGIC,%d0
        beq.s   3f
        lea     m_nowin(%pc),%a0
        bsr     puts
        bra     close_exp
3:      lea     m_board1(%pc),%a0
        bsr     puts
        move.l  %a3,%d0
        bsr     puthex8
        lea     m_nl(%pc),%a0
        bsr     puts

        | ---- what was asked for: first non-blank character only ----
        move.l  %a4,%a0
        move.l  %d7,%d1
4:      tst.l   %d1
        beq.s   do_load
        move.b  (%a0)+,%d0
        subq.l  #1,%d1
        cmp.b   #' ',%d0
        beq.s   4b
        cmp.b   #9,%d0
        beq.s   4b
        cmp.b   #10,%d0
        beq.s   do_load
        or.b    #0x20,%d0                   | lower case
        cmp.b   #'s',%d0
        beq     do_status
        cmp.b   #'o',%d0
        beq     do_off
        cmp.b   #'?',%d0
        beq.s   do_usage
        cmp.b   #'h',%d0
        beq.s   do_usage
        bra.s   do_load

do_usage:
        lea     m_usage(%pc),%a0
        bsr     puts
        clr.l   v_rc(%a5)
        bra     close_exp

do_status:
        bsr     report
        clr.l   v_rc(%a5)
        bra     close_exp

do_off:
        move.w  #MR_OFF,8(%a2)
        lea     m_disabled(%pc),%a0
        bsr     puts
        bsr     report
        clr.l   v_rc(%a5)
        bra     close_exp

do_load:
        move.w  8(%a2),%d0
        btst    #1,%d0
        beq.s   5f
        lea     m_already(%pc),%a0
        bsr     puts
        bsr     report
        clr.l   v_rc(%a5)
        bra     close_exp
5:      lea     m_shadow(%pc),%a0
        bsr     puts
        lea     m_boot(%pc),%a0
        move.l  #BOOT_BASE,%a1
        bsr     describe
        lea     m_ext(%pc),%a0
        move.l  #EXT_BASE,%a1
        bsr     describe

        | checksum the real ROM before touching anything
        move.l  #BOOT_BASE,%a0
        bsr     sum_bank
        move.l  %d0,v_bsum(%a5)
        move.l  #EXT_BASE,%a0
        bsr     sum_bank
        move.l  %d0,v_esum(%a5)

        | fill the shadow
        lea     m_copying(%pc),%a0
        bsr     puts
        move.w  #MR_LOAD,8(%a2)
        move.l  #BOOT_BASE,%a0
        bsr     copy_bank
        move.l  #EXT_BASE,%a0
        bsr     copy_bank
        move.w  #MR_OFF,8(%a2)              | close the write window
        lea     m_done(%pc),%a0
        bsr     puts

        | arm and check -- nothing in ROM between ACTIVE and the decision
        lea     m_switch(%pc),%a0
        bsr     puts
        move.l  v_sys(%a5),%a6
        jsr     LVO_Disable(%a6)
        move.w  #MR_ACTIVE,8(%a2)
.ifdef TESTBAD
        not.l   EXT_BASE+0x100              | test build: a bad shadow
.endif
        moveq   #0,%d6                      | bad: bit 0 boot, bit 1 ext
        move.l  #BOOT_BASE,%a0
        bsr     sum_bank
        cmp.l   v_bsum(%a5),%d0
        beq.s   6f
        bset    #0,%d6
6:      move.l  #EXT_BASE,%a0
        bsr     sum_bank
        cmp.l   v_esum(%a5),%d0
        beq.s   7f
        bset    #1,%d6
7:      tst.b   %d6
        beq.s   8f
        move.w  #MR_OFF,8(%a2)              | back to the motherboard
8:      move.l  v_sys(%a5),%a6
        jsr     LVO_Enable(%a6)

        tst.b   %d6
        bne.s   9f
        lea     m_ok(%pc),%a0
        bsr     puts
        bsr     report
        clr.l   v_rc(%a5)
        bra.s   close_exp
9:      lea     m_failed(%pc),%a0
        bsr     puts
        lea     m_bad_both(%pc),%a0
        cmp.b   #3,%d6
        beq.s   10f
        lea     m_bad_boot(%pc),%a0
        btst    #0,%d6
        bne.s   10f
        lea     m_bad_ext(%pc),%a0
10:     bsr     puts
        lea     m_backoff(%pc),%a0
        bsr     puts

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

| ---- report: control register and what it means --------------------------
report:
        move.l  %d2,-(%sp)
        moveq   #0,%d2
        move.w  8(%a2),%d2
        and.w   #3,%d2
        lea     m_ctrl(%pc),%a0
        bsr     puts
        move.l  %d2,%d0
        bsr     puthex4
        lea     m_load(%pc),%a0
        bsr     puts
        lea     m_on(%pc),%a0
        btst    #0,%d2
        bne.s   1f
        lea     m_offw(%pc),%a0
1:      bsr     puts
        lea     m_active(%pc),%a0
        bsr     puts
        lea     m_on(%pc),%a0
        btst    #1,%d2
        bne.s   2f
        lea     m_offw(%pc),%a0
2:      bsr     puts
        lea     m_nl(%pc),%a0
        bsr     puts
        lea     m_from_sdram(%pc),%a0
        btst    #1,%d2
        bne.s   3f
        lea     m_from_mb(%pc),%a0
3:      bsr     puts
        move.l  (%sp)+,%d2
        rts

| ---- describe: a0 = name, a1 = bank base (information only) --------------
describe:
        movem.l %d2/%a2,-(%sp)
        move.l  (%a1),%d2
        move.l  %a1,%a2
        move.l  %a0,-(%sp)
        lea     m_ind(%pc),%a0
        bsr     puts
        move.l  (%sp)+,%a0
        bsr     puts
        lea     m_dollar(%pc),%a0
        bsr     puts
        move.l  %a2,%d0
        bsr     puthex6
        lea     m_first(%pc),%a0
        bsr     puts
        move.l  %d2,%d0
        bsr     puthex8
        lea     m_sig512(%pc),%a0
        cmp.l   #ROMID_512K,%d2
        beq.s   1f
        lea     m_sig256(%pc),%a0
        cmp.l   #ROMID_256K,%d2
        beq.s   1f
        lea     m_signone(%pc),%a0
1:      bsr     puts
        movem.l (%sp)+,%d2/%a2
        rts

| ---- sum_bank: a0 = base -> d0 (order dependent, as in maprom.c) ---------
sum_bank:
        move.l  #BANK_LONGS,%d1
        moveq   #0,%d0
1:      rol.l   #1,%d0
        add.l   (%a0)+,%d0
        subq.l  #1,%d1
        bne.s   1b
        rts

| ---- copy_bank: a0 = base. With LOAD set the read comes from the real ROM
|      and the write lands in the shadow, at the same address. ------------
copy_bank:
        move.l  #BANK_LONGS,%d1
1:      move.l  (%a0),%d0
        move.l  %d0,(%a0)+
        subq.l  #1,%d1
        bne.s   1b
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

| puthex8/6/4: d0 -> that many hex digits. Keeps all registers.
puthex8:
        movem.l %d0-%d2/%a0,-(%sp)
        moveq   #8,%d2
        bra.s   puthex
puthex6:
        movem.l %d0-%d2/%a0,-(%sp)
        lsl.l   #8,%d0
        moveq   #6,%d2
        bra.s   puthex
puthex4:
        movem.l %d0-%d2/%a0,-(%sp)
        swap    %d0
        moveq   #4,%d2
puthex:
        lea     v_buf(%a5),%a0
        subq.w  #1,%d2
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
verstag:    .asciz  "$VER: maprom 1.0 (5.11.2026) Base64"
m_noexp:    .asciz  "cannot open expansion.library\n"
m_noboard:  .asciz  "No Base64 AutoConfig ROM board found (5194/14).\n"
m_nowin:    .asciz  "Board found, but no status window - gateware is too old.\n"
m_board1:   .asciz  "Base64 AutoConfig ROM board at $"
m_nl:       .asciz  "\n"
m_usage:    .asciz  "Usage: maprom          copy Kickstart to SDRAM and switch over\n       maprom OFF      switch back to the motherboard ROM\n       maprom STATUS   report only\n"
m_disabled: .asciz  "mapROM disabled.\n"
m_already:  .asciz  "mapROM is already active. Use OFF first if you want to redo it.\n"
m_shadow:   .asciz  "Shadowing 1 MB, both banks, exactly as the motherboard reads:\n"
m_boot:     .asciz  "boot"
m_ext:      .asciz  "ext "
m_ind:      .asciz  "  "
m_dollar:   .asciz  " $"
m_first:    .asciz  "  first longword $"
m_sig512:   .asciz  "  512 KB Kickstart signature\n"
m_sig256:   .asciz  "  256 KB Kickstart signature\n"
m_signone:  .asciz  "  no Kickstart signature\n"
m_copying:  .asciz  "Copying ... "
m_done:     .asciz  "done.\n"
m_switch:   .asciz  "Switching over ... "
m_ok:       .asciz  "ok.\n"
m_failed:   .asciz  "FAILED.\n"
m_bad_both: .asciz  "  Both the boot and the ext bank did not read back correctly.\n"
m_bad_boot: .asciz  "  The boot bank did not read back correctly.\n"
m_bad_ext:  .asciz  "  The ext bank did not read back correctly.\n"
m_backoff:  .asciz  "mapROM has been turned back off; the machine is running\nfrom the motherboard ROM exactly as before.\n"
m_ctrl:     .asciz  "  control $"
m_load:     .asciz  "  load "
m_active:   .asciz  "  active "
m_on:       .asciz  "on "
m_offw:     .asciz  "off"
m_from_sdram: .asciz "  Kickstart is being served from SDRAM.\n"
m_from_mb:  .asciz  "  Kickstart is being served from the motherboard.\n"
        .balign 4
vars:   .space  48
.ifdef TEST
        .balign 4
fakeboard: .space 0x10000
.endif
