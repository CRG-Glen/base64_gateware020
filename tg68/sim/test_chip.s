| Chip RAM benchmark (step 11): a loop that runs from chip RAM and writes
| 1 KB to chip RAM, timed on the second pass, like a game whose code is in a
| CODE_C hunk drawing into a chip RAM screen.
        .org 0
        .long 0x00009000
        .long start
        .org 0x100
start:  moveq   #1,%d0
        movec   %d0,%cacr           | instruction cache on
        lea     chipfn,%a0
        movea.l #0x9800,%a1         | the loop goes to chip RAM
        moveq   #7,%d0
cp:     move.l  (%a0)+,(%a1)+
        dbra    %d0,cp
        jsr     0x9800
        move.b  #1,0x8F00
        jsr     0x9800
        move.b  #2,0x8F00
        move.l  0x87FC,%d0          | last long written: posted, read back
        move.l  %d0,0x8100          | 8100: 255*3 = 0x2FD
        move.l  #0x600DC0DE,0x8FF0
done:   bra.s   done
chipfn: lea     0x8400,%a0          | 1 KB of chip RAM
        moveq   #0,%d1
        move.w  #255,%d0
1:      move.l  %d1,(%a0)+
        addq.l  #3,%d1
        dbra    %d0,1b
        rts
