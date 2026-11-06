| 68020 smoke test for tg68_bus + TG68K kernel.  Results go to RAM at $8100.
        .org 0
        .long 0x00009000            | SSP
        .long start                 | PC
        .org 0x60
        .long 0                     | spurious
        .org 0x6C
        .long irq3                  | level-3 autovector (27) - used before VBR moves
        .org 0x80
        .long trap0                 | trap #0 (32)
        .org 0x100
start:  lea     0x8100,%a5
        moveq   #1,%d0
        movec   %d0,%cacr           | instruction cache on (EI)
        move.l  #0x12345678,%d0
        move.l  #3,%d1
        mulu.l  %d1,%d0             | 32x32 -> 0x369D0368
        move.l  %d0,(%a5)+          | 8100
        move.l  #1000000,%d3
        divu.l  #7,%d3              | -> 142857 = 0x22E09
        move.l  %d3,(%a5)+          | 8104
        move.l  #0xF0F0F0F0,%d4
        bfextu  %d4{#4:#8},%d5      | -> 0x0F
        move.l  %d5,(%a5)+          | 8108
        move.b  #0x80,%d6
        extb.l  %d6                 | -> 0xFFFFFF80
        move.l  %d6,(%a5)+          | 810C
        move.l  #0x1234ABCD,%d7
        move.b  %d7,0x8201          | odd byte lane
        move.b  #0x5A,0x8200        | even byte lane
        move.w  0x8200,%d0          | -> 0x5ACD
        move.l  %d0,(%a5)+          | 8110 (upper word of d0 = 0x369D)
        move.l  #0xA1B2C3D4,0x8301  | misaligned long write (020)
        move.l  0x8301,%d1          | misaligned read back
        move.l  %d1,(%a5)+          | 8114 -> 0xA1B2C3D4
        moveq   #0,%d2
        trap    #0                  | handler sets d2 = 0x7777
        move.l  %d2,(%a5)+          | 8118
        move.l  #0x4000,%d7
        movec   %d7,%vbr
        movec   %vbr,%a0
        move.l  %a0,(%a5)+          | 811C -> 0x4000
        moveq   #0,%d7
        movec   %d7,%vbr
        | -- cache: a loop that should run from the cache --
        moveq   #0,%d1
        move.w  #199,%d0
lp:     addq.l  #3,%d1
        dbra    %d0,lp
        move.l  %d1,0x8130          | 8130 -> 600 (0x258)
        | -- cache: self-modifying code must see its own writes --
        move.l  #0x78014e75,0x8400 | moveq #1,d4 ; rts
        jsr     0x8400
        jsr     0x8400              | second call runs from the cache
        move.l  %d4,0x8134          | 8134 -> 1
        move.w  #0x7802,0x8400      | patch: moveq #2,d4
        jsr     0x8400
        move.l  %d4,0x8138          | 8138 -> 2
        moveq   #0,%d3
        move.w  #0x2000,%sr         | enable interrupts (IPL 3 asserted by TB)
wait:   tst.l   %d3
        beq.s   wait
        move.l  %d3,(%a5)+          | 8120 -> 0x33333333
        move.l  #0x600DC0DE,0x8FF0  | done marker
done:   bra.s   done
trap0:  move.l  #0x7777,%d2
        rte
irq3:   move.l  #0x33333333,%d3
        move.b  #1,0x8FFC           | tell the TB to drop IPL
        rte
