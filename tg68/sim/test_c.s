| bench c: copies the compiled workload (cimg.bin, bench_c.c) from the ROM
| to fast RAM at $08010000 and calls it twice with the caches on and the
| stack in fast RAM; the second call is timed.
        .org 0
        .long 0x00009000
        .long start
        .org 0x100
start:
        .ifdef SPEED18
        | SPEED18 (named in the 18x experiment): switch to 20x first (SPEED16:
        | 16x) and
        | wait until the switch is done
        .ifdef SPEED16
        move.w  #0x5B10,0xEAF00A
        .else
        move.w  #0x5B14,0xEAF00A
        .endif
9:      move.w  0xEAF00A,%d0
        btst    #11,%d0
        bne.s   9b
        .ifdef SPEED16
        cmp.b   #0x10,%d0
        .else
        cmp.b   #0x14,%d0
        .endif
        bne.s   9b
        .endif
        moveq   #1,%d0
        .ifdef NOCACHE
        moveq   #0,%d0
        .endif
        movec   %d0,%cacr
        lea     img,%a0
        lea     0x08010000,%a1
        move.w  #(imgend-img)/4,%d0
cp:     move.l  (%a0)+,(%a1)+
        dbra    %d0,cp
        lea     0x08020000,%sp
        jsr     0x08010000
        move.l  %d0,0x8100          | checksum, pass 1
        move.b  #1,0x8F00
        jsr     0x08010000
        move.b  #2,0x8F00
        move.l  %d0,0x8104          | checksum, pass 2 (timed)
        move.l  #0x600DC0DE,0x8FF0
done:   bra.s   done
        .balign 4
img:    .incbin "cimg.bin"
        .balign 4
imgend:
