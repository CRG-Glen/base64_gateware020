| Fast RAM copy benchmark: 256 longs $08000000 -> $08002000. The copy loop
| itself is moved into fast RAM first, so its fetches come from the cache.
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
        movec   %d0,%cacr
        lea     0x08000000,%a0
        move.w  #255,%d0
fill:   move.l  %d0,(%a0)+
        dbra    %d0,fill
        lea     copyfn,%a0          | copy the routine to $08004000
        lea     0x08004000,%a1
        moveq   #7,%d0
cpf:    move.l  (%a0)+,(%a1)+
        dbra    %d0,cpf
        jsr     0x08004000          | warm-up pass: loads the cache
        move.b  #1,0x8F00           | marker: start
        jsr     0x08004000
        move.b  #2,0x8F00           | marker: end
        lea     0x08002000,%a1      | verify every long: dest[i] = 255-i
        move.w  #255,%d0
        moveq   #0,%d2              | mismatches
vfy:    cmp.l   (%a1)+,%d0
        beq.s   1f
        addq.l  #1,%d2
1:      dbra    %d0,vfy
        move.l  %d2,0x8108
        move.l  0x08002000,%d1      | first copied long = 255
        move.l  %d1,0x8100
        move.l  0x080023FC,%d1      | last = 0
        move.l  %d1,0x8104
        move.l  #0x600DC0DE,0x8FF0
done:   bra.s   done
copyfn: lea     0x08000000,%a0
        lea     0x08002000,%a1
        move.w  #255,%d0
1:      move.l  (%a0)+,(%a1)+
        dbra    %d0,1b
        rts
        nop
