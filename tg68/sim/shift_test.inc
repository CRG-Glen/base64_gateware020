| Step 19: shift and rotate matrix, shared by test020.s (bus bench) and
| test_top.s. For each of asl asr lsl lsr rol ror roxl roxr, in byte, word
| and long: counts 0 1 2 7 8 15 16 31 32 33 63 from a register and #1, #8
| immediate, on two data values (entered with X/C clear and with X/N/Z/V/C
| set), then one-bit memory shifts of a word. Every result and its flags
| (X N Z V C) go into a checksum built with MULU/ADD only (not with the
| shifter under test). The expected values are what the b0 core (bit-by-bit
| shifter, on hardware since v1.0) gives; the barrel shifter (b1) must give
| the same.
|   in:  a0 = table for the 25 longwords below (24 groups + memory), in
|        RAM, followed by a word of RAM for the memory shifts (a0 + 100)
|   out: d7 = checksum over everything; a0 advanced past the table
| Clobbers d0-d7, a1-a3.
shift_test:
        lea     100(%a0),%a3        | the memory shifts' word
        moveq   #0,%d7
        .irp    op,asl,asr,lsl,lsr,rol,ror,roxl,roxr
        .irp    sz,b,w,l
        lea     st_cnt,%a1
1:      move.l  (%a1)+,%d1
        bmi.s   2f
        lea     st_dat,%a2
        moveq   #1,%d3
3:      move.l  (%a2)+,%d0
        move.w  (%a2)+,%d4
        move.w  %d4,%ccr
        \op\().\sz %d1,%d0
        move.w  %sr,%d5
        bsr     st_acc
        dbra    %d3,3b
        bra.s   1b
2:      lea     st_dat,%a2
        moveq   #1,%d3
4:      move.l  (%a2),%d0
        move.w  4(%a2),%d4
        move.w  %d4,%ccr
        \op\().\sz #1,%d0
        move.w  %sr,%d5
        bsr     st_acc
        move.l  (%a2)+,%d0
        move.w  (%a2)+,%d4
        move.w  %d4,%ccr
        \op\().\sz #8,%d0
        move.w  %sr,%d5
        bsr     st_acc
        dbra    %d3,4b
        move.l  %d7,(%a0)+
        .endr
        .endr
        | memory: one bit, word, both data values
        .irp    op,asl,asr,lsl,lsr,rol,ror,roxl,roxr
        lea     st_dat,%a2
        moveq   #1,%d3
5:      move.l  (%a2)+,%d0
        move.w  %d0,(%a3)
        move.w  (%a2)+,%d4
        move.w  %d4,%ccr
        \op\().w (%a3)
        move.w  %sr,%d5
        move.w  (%a3),%d0
        bsr     st_acc
        dbra    %d3,5b
        .endr
        move.l  %d7,(%a0)+
        rts
| d7 = (d7 * 31 + d0) * 31 + (sr & 0x1F)
st_acc: mulu.l  #31,%d7
        add.l   %d0,%d7
        mulu.l  #31,%d7
        and.w   #0x1F,%d5
        ext.l   %d5
        add.l   %d5,%d7
        rts
        .even
st_cnt: .long   0,1,2,7,8,15,16,31,32,33,63,-1
st_dat: .long   0x8F3C5A01
        .word   0x0000              | X N Z V C clear
        .long   0x40C0FF7E
        .word   0x001F              | X N Z V C set
