| SD controller register read-back: each read must return the value just
| written to THAT register, not the previous read's data.
        .org 0
        .long 0x00009000
        .long start
        .org 0x100
start:  moveq   #1,%d0
        movec   %d0,%cacr
        lea     0xE90000,%a0        | SD window (base_sd forced to $E9)
        move.w  #0x55,(%a0)         | CLKDIV (the first write also maps the registers in)
        moveq   #0,%d1
        move.w  (%a0),%d1
        move.l  %d1,0x8100          | 00000055
        move.w  #0xAA,(%a0)
        moveq   #0,%d1
        move.w  (%a0),%d1
        move.l  %d1,0x8104          | 000000AA
        move.w  #1,2(%a0)           | SLAVE_SEL
        moveq   #0,%d1
        move.w  2(%a0),%d1
        move.l  %d1,0x8108          | 00000001
        move.w  #0,2(%a0)
        moveq   #0,%d1
        move.w  2(%a0),%d1
        move.l  %d1,0x810C          | 00000000
        moveq   #0,%d1
        move.w  (%a0),%d1
        move.l  %d1,0x8110          | 000000AA
        | -- SPI loopback (MOSI -> MISO in the test bench) --
        move.w  #0,(%a0)            | CLKDIV 0: fastest SCLK
        move.w  #1,2(%a0)           | select the card
        move.w  #0xC000,8(%a0)      | SHIFT_CTRL: mode BOTH (tx and rx)
        lea     0x10(%a0),%a1       | data register
        move.w  #0x0102,%d0
        moveq   #7,%d2
1:      move.w  %d0,(%a1)           | 8 words = 16 bytes out
        add.w   #0x0202,%d0
        dbra    %d2,1b
2:      move.w  6(%a0),%d1          | STATUS: wait for >= 16 bytes received
        btst    #4,%d1
        beq.s   2b
        moveq   #0,%d3              | mismatches
        move.w  #0x0102,%d0
        moveq   #7,%d2
        moveq   #0,%d4
3:      move.w  (%a1),%d1
        tst.l   %d4
        bne.s   4f
        move.l  %d1,%d4             | keep the first word
        and.l   #0xFFFF,%d4
4:      cmp.w   %d0,%d1
        beq.s   5f
        addq.l  #1,%d3
5:      add.w   #0x0202,%d0
        dbra    %d2,3b
        move.l  %d3,0x8114
        move.l  %d4,0x8118
        | byte path: one byte out, one byte back
        move.b  #0xF1,(%a1)         | byte write (upper lane)
6:      move.w  6(%a0),%d1          | wait: rx buffer not empty
        btst    #0,%d1
        bne.s   6b
        moveq   #0,%d1
        move.b  (%a1),%d1           | byte read
        move.l  %d1,0x811C
        move.w  #0,2(%a0)           | deselect
        move.l  #0x600DC0DE,0x8FF0
done:   bra.s   done
