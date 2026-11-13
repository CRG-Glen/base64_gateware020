| Fast RAM scattered-read benchmark: four longs in different SDRAM rows,
| read round and round (256 reads), timed on the second pass.
        .org 0
        .long 0x00009000
        .long start
        .org 0x100
start:
        .ifdef SPEED18
        | exp-18x: switch speed first (SPEED16 too: 16x, as a control) and
        | wait until the switch is done
        .ifdef SPEED16
        move.w  #0x5B10,0xEAF00A
        .else
        move.w  #0x5B12,0xEAF00A
        .endif
9:      move.w  0xEAF00A,%d0
        btst    #11,%d0
        bne.s   9b
        .ifdef SPEED16
        cmp.b   #0x10,%d0
        .else
        cmp.b   #0x12,%d0
        .endif
        bne.s   9b
        .endif
        moveq   #1,%d0
        movec   %d0,%cacr
        lea     0x08000000,%a0
        move.w  #255,%d0
fill:   move.l  %d0,(%a0)+
        dbra    %d0,fill
        move.l  #0x7F,0x08000000    | the four longs the loop reads:
        move.l  #0x7F,0x08100040    | 64 x (0x7F+0x7F+0x80+0x80) = 0x7F80
        move.l  #0x80,0x08200080
        move.l  #0x80,0x083000C0
        lea     sumfn,%a0
        lea     0x08004000,%a1
        moveq   #11,%d0
cpf:    move.l  (%a0)+,(%a1)+
        dbra    %d0,cpf
        jsr     0x08004000
        move.b  #1,0x8F00
        jsr     0x08004000
        move.b  #2,0x8F00
        move.l  %d2,0x8100          | sum 0..255 = 0x7F80
        move.l  #0x600DC0DE,0x8FF0
done:   bra.s   done
sumfn:  lea     0x08000000,%a0
        lea     0x08100040,%a1
        lea     0x08200080,%a2
        lea     0x083000C0,%a3
        moveq   #0,%d2
        moveq   #63,%d0             | 4 scattered longs x 64 = 1 KB read
1:      add.l   (%a0),%d2
        add.l   (%a1),%d2
        add.l   (%a2),%d2
        add.l   (%a3),%d2
        dbra    %d0,1b
        rts
        nop
