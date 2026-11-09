| Write-burst benchmark (step 12): 1 KB written as bursts of four longwords
| (MOVEM.L) with a little arithmetic between the bursts, as a
| chunky-to-planar loop or a screen clear does. FAST: to fast RAM
| ($08002000); otherwise to Chip RAM ($8400). Timed on the second pass,
| with the loop running from the instruction cache.
        .org 0
        .long 0x00009000
        .long start
        .org 0x100
start:  moveq   #1,%d0
        movec   %d0,%cacr
        bsr.s   wfn                 | warm-up pass: loads the cache
        move.b  #1,0x8F00           | marker: start
        bsr.s   wfn
        move.b  #2,0x8F00           | marker: end
        .ifdef FAST
        move.l  0x080023FC,%d0
        .else
        move.l  0x87FC,%d0
        .endif
        move.l  %d0,0x8100          | last long written
        move.l  #0x600DC0DE,0x8FF0
done:   bra.s   done
wfn:
        .ifdef FAST
        lea     0x08002000,%a0
        .else
        lea     0x8400,%a0
        .endif
        moveq   #0,%d1
        moveq   #63,%d0             | 64 bursts of 16 bytes = 1 KB
1:      move.l  %d1,%d2
        move.l  %d1,%d3
        move.l  %d1,%d4
        addq.l  #1,%d2
        addq.l  #2,%d3
        addq.l  #3,%d4
        movem.l %d1-%d4,(%a0)
        .ifdef MIX
        | about as much arithmetic per burst as a chunky-to-planar merge
        .rept 8
        move.l  %d5,%d6
        lsr.l   #4,%d6
        eor.l   %d7,%d6
        and.l   #0x0F0F0F0F,%d6
        .endr
        .endif
        lea     16(%a0),%a0
        addq.l  #4,%d1
        dbra    %d0,1b
        rts
