| Fast RAM read benchmark: sum 256 longs at $08000000, timed on the second
| pass (the first loads the caches). The loop runs from fast RAM.
        .org 0
        .long 0x00009000
        .long start
        .org 0x100
start:  moveq   #1,%d0
        .ifdef NOCACHE
        moveq   #0,%d0              | bench readoff: caches off
        .endif
        movec   %d0,%cacr
        lea     0x08000000,%a0
        move.w  #255,%d0
fill:   move.l  %d0,(%a0)+
        dbra    %d0,fill
        lea     sumfn,%a0
        lea     0x08004000,%a1
        moveq   #7,%d0
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
        moveq   #0,%d2
        move.w  #255,%d0
1:      add.l   (%a0)+,%d2
        dbra    %d0,1b
        rts
        nop
