| Full-top test: same 68020 checks plus a CIA (VPA/E) cycle, a 32-bit
| null-space read, and the interrupt path through Gary-style VPA autovector.
        .org 0
        .long 0x00009000
        .long start
        .org 0x6C
        .long irq3
        .org 0x80
        .long trap0
        .org 0x100
start:  lea     0x8100,%a5
        moveq   #1,%d0
        movec   %d0,%cacr           | instruction cache on (EI)
        move.l  #0x12345678,%d0
        move.l  #3,%d1
        mulu.l  %d1,%d0
        move.l  %d0,(%a5)+          | 8100 369D0368
        move.l  #1000000,%d3
        divu.l  #7,%d3
        move.l  %d3,(%a5)+          | 8104 00022E09
        move.l  #0xF0F0F0F0,%d4
        bfextu  %d4{#4:#8},%d5
        move.l  %d5,(%a5)+          | 8108 0000000F
        move.b  #0x5A,0x8200
        move.b  #0xCD,0x8201
        move.w  0x8200,%d0
        move.l  %d0,(%a5)+          | 810C 369D5ACD
        move.l  #0xA1B2C3D4,0x8301
        move.l  0x8301,%d1
        move.l  %d1,(%a5)+          | 8110 A1B2C3D4
        moveq   #0,%d2
        trap    #0
        move.l  %d2,(%a5)+          | 8114 00007777
        moveq   #0,%d0
        move.b  0xBFE001,%d0        | CIA: VPA/VMA/E cycle, model returns 0xA5
        move.l  %d0,(%a5)+          | 8118 000000A5
        move.l  0xFF000000,%d0      | 32-bit space: answered on-chip
        move.l  %d0,(%a5)+          | 811C FFFFFFFF
        .ifdef FASTMEM
        moveq   #1,%d0
        movec   %d0,%cacr           | instruction cache on
        move.l  #0x13579BDF,0x08000000
        move.l  #0x2468ACE0,0x08FFFFFC
        move.l  0x08000000,%d0
        move.l  %d0,(%a5)+          | 8124 13579BDF
        move.l  0x08FFFFFC,%d0
        move.l  %d0,(%a5)+          | 8128 2468ACE0
        lea     fastfn,%a0          | copy a routine into fast RAM and run it
        movea.l #0x08000100,%a1
        moveq   #3,%d0
cp:     move.l  (%a0)+,(%a1)+
        dbra    %d0,cp
        jsr     0x08000100
        jsr     0x08000100          | second run comes from the cache
        move.l  %d6,(%a5)+          | 8128 0000FA57
        move.w  #0xBEEF,0x08000104  | patch the immediate in fast RAM
        jsr     0x08000100
        move.l  %d6,(%a5)+          | 812C 0000BEEF
        | -- direct path: prefetch buffer must never go stale --
        move.l  #0x11112222,0x08000200
        move.l  0x08000200,%d0      | long read: 2nd half from the prefetch
        move.l  %d0,0x8150          | 8150 11112222
        move.w  0x08000200,%d1      | prefetches $08000202
        move.w  #0x3333,0x08000202  | ...which this write must invalidate
        move.w  0x08000202,%d2
        move.l  %d2,0x8154          | 8154 xxxx3333 (upper word = d2 junk 0)
        move.l  #0x55556666,0x08000300
        move.w  0x08000300,%d1      | prefetches $08000302
        move.b  #0x44,0x08000303    | byte write into the prefetched word
        moveq   #0,%d3
        move.w  0x08000302,%d3
        move.l  %d3,0x8158          | 8158 00006644
        lea     0x08000400,%a0      | sequential word reads after writes
        move.l  #0xA0A1A2A3,(%a0)
        move.l  #0xA4A5A6A7,4(%a0)
        moveq   #0,%d4
        add.w   (%a0)+,%d4
        add.w   (%a0)+,%d4
        add.w   (%a0)+,%d4
        add.w   (%a0)+,%d4
        move.l  %d4,0x815C          | 815C sum of A0A1+A2A3+A4A5+A6A7 = 0x8E90 (16-bit)
        | -- MapROM through the direct path (the TB drives the control bits) --
        move.b  #1,0x8F40           | TB: LOAD
        move.l  #0xCAFEBABE,0x00F81000  | lands in the shadow
        move.b  #2,0x8F40           | TB: ACTIVE
        move.l  0x00F81000,%d0      | read from the shadow
        move.l  %d0,0x8160          | 8160 CAFEBABE
        move.b  #3,0x8F40           | TB: OFF
        moveq   #0,%d0
        move.w  0x00F81002,%d0      | real ROM again (prefetched shadow word must not leak)
        move.l  %d0,0x8164          | 8164 00000000 (ROM image is zero there)
        | -- data cache --
        move.l  #0x0BADF00D,0x08000500
        move.l  0x08000500,%d0      | miss (word 0) + prefetch fill (word 1)
        move.l  0x08000500,%d1      | both words from the data cache
        cmp.l   %d0,%d1
        bne.s   dcf1
        move.l  %d1,0x8168          | 8168 0BADF00D
dcf1:   move.w  #0,0x08000600
        move.w  0x08000600,%d0      | cache the word
        move.b  #0x5A,0x08000601    | byte write: must drop the entry
        moveq   #0,%d0
        move.w  0x08000600,%d0
        move.l  %d0,0x816C          | 816C xxxx005A (high byte from the write below)
        move.w  #0x1234,0x08000610
        move.w  0x08000610,%d0      | cached
        move.w  #0x5678,0x08000610  | word write: updates the entry
        moveq   #0,%d0
        move.w  0x08000610,%d0
        move.l  %d0,0x8170          | 8170 00005678
        move.l  #0xAAAA1111,0x08000700  | same cache index, 8 KB apart
        move.l  #0xBBBB2222,0x08002700
        move.l  0x08000700,%d0
        move.l  0x08002700,%d1
        move.l  0x08000700,%d2
        add.l   %d1,%d0
        add.l   %d2,%d0
        move.l  %d0,0x8174          | 8174 AAAA1111*2+BBBB2222 = 0x2110F4444 -> 0x110F4444
        move.w  #0x1111,0x08000800
        move.w  0x08000800,%d0      | cached
        moveq   #0,%d0
        movec   %d0,%cacr           | caches off
        move.w  #0x2222,0x08000800  | written while off: entry must go
        moveq   #1,%d0
        movec   %d0,%cacr           | caches on again
        moveq   #0,%d0
        move.w  0x08000800,%d0
        move.l  %d0,0x8178          | 8178 00002222
        move.l  romdat+0xF80000,%d0 | ROM data over the 7M bus, then cached
        move.l  romdat+0xF80000,%d1
        add.l   %d1,%d0
        move.l  %d0,0x817C          | 817C 2*0x01020304 = 0x02040608
        lea     0x08001000,%a0      | 64 words, written then summed twice:
        moveq   #63,%d0             | the second pass is all cache hits
        moveq   #0,%d1
dfill:  move.w  %d1,(%a0)+
        addq.w  #3,%d1
        dbra    %d0,dfill
        moveq   #0,%d4
        moveq   #1,%d5
dpass:  lea     0x08001000,%a0
        moveq   #63,%d0
dsum:   add.w   (%a0)+,%d4
        dbra    %d0,dsum
        dbra    %d5,dpass
        move.l  %d4,0x8180          | 8180 2 * sum(3i, i<64) = 2*6048 = 0x2F40
        | -- a write right after a cache hit on the neighbouring word --
        move.l  #0x11112222,0x08000A00  | both words cached (word writes allocate)
        move.w  0x08000A00,%d0      | hit (and, before step 6, buffered 0A02)
        move.w  #0x7777,0x08000A02  | word write to that word
        moveq   #0,%d1
        move.w  0x08000A02,%d1
        move.l  %d1,0x8184          | 8184 00007777 (not the old 2222)
        move.l  #0xAAAABBBB,0x08000B00
        move.w  0x08000B00,%d0      | hit on the neighbour of 0B02
        move.b  #0xCC,0x08000B03    | byte write into 0B02
        moveq   #0,%d1
        move.w  0x08000B02,%d1
        move.l  %d1,0x8188          | 8188 0000BBCC
        move.l  #0x13131414,0x08000C00
        move.w  0x08000C00,%d0      | hit on the neighbour of 0C02
        moveq   #0,%d0
        movec   %d0,%cacr           | caches off
        move.w  #0x1515,0x08000C02  | written while off
        moveq   #1,%d0
        movec   %d0,%cacr           | caches on again
        moveq   #0,%d1
        move.w  0x08000C02,%d1
        move.l  %d1,0x818C          | 818C 00001515
        | -- MapROM switching flushes the caches --
        move.b  #1,0x8F40           | TB: LOAD
        move.l  #0x11112222,0x00F81000  | shadow words 1111, 2222
        move.b  #2,0x8F40           | TB: ACTIVE: flushes the caches (4096 clocks)
        move.w  #799,%d2            | ...so wait, or the reads below bypass the cache
mrdl0:  dbra    %d2,mrdl0
        move.l  0x00F81000,%d0      | miss, fills the data cache
        move.l  0x00F81000,%d1      | hit, F81002 (2222, the shadow) cached
        move.b  #3,0x8F40           | TB: OFF: flushes again
        move.w  #799,%d2            | let that flush finish too
mrdly:  dbra    %d2,mrdly
        moveq   #0,%d0
        move.w  0x00F81002,%d0      | the real ROM word, not the cached shadow
        move.l  %d0,0x8190          | 8190 00000000
        | -- 32-bit data path: aligned pairs from the caches (step 7) --
        move.l  #0x01010101,0x08000F00  | data for the abs.L add (both words cached)
        lea     fn32,%a0            | copy fn32 into fast RAM (long-aligned)
        movea.l #0x08000E00,%a1
        moveq   #4,%d0
cp32:   move.l  (%a0)+,(%a1)+
        dbra    %d0,cp32
        jsr     0x08000E00          | fills the instruction cache
        jsr     0x08000E00          | from the caches: imm32, abs.L and the long read as pairs
        move.l  %d6,0x8194          | 8194 0x89ABCDEF + 0x01010101 = 0x8AACCEF0
        | a pair whose second word is NOT cached must not be taken as a pair
        move.l  #0x31323334,0x08000D00  | both words cached
        move.b  #0x99,0x08000D03    | byte write: the second word's entry is dropped
        move.l  0x08000D00,%d0      | first word hits, second misses
        move.l  %d0,0x8198          | 8198 31323399 (not the stale 3334)
        | -- 32-bit SDRAM (step 8): pair writes must land in the SDRAM --
        move.l  #0x51525354,0x08004C00  | aligned longword: one pair write
        move.l  #0,0x08006C00       | same cache slots 8 KB up: evicts both words
        move.l  0x08004C00,%d0      | misses: both words come from the SDRAM
        move.l  %d0,0x819C          | 819C 51525354
        move.l  #0x61626364,0x08004D02  | misaligned: two 16-bit writes, no pair
        move.l  #0,0x08006D00       | evict
        move.l  #0,0x08006D04
        move.l  0x08004D02,%d0
        move.l  %d0,0x81A0          | 81A0 61626364
        move.l  #0x71727374,0x08004E00  | both words into the data cache
        move.l  0x08004E00,%d0      | (read back: now cached)
        move.l  #0x81828384,0x08004E00  | pair write over cached words
        move.l  0x08004E00,%d0      | hits: both cache entries updated
        move.l  %d0,0x81A4          | 81A4 81828384
        | -- 32-bit SDRAM reads (step 9): a miss reads both words at once --
        move.w  #0x9192,0x08004F00  | two word writes (no pair)
        move.w  #0x9394,0x08004F02
        move.l  #0,0x08006F00       | same cache slots 8 KB up: evicts both
        move.l  0x08004F00,%d0      | miss: one pair read from the SDRAM
        move.l  0x08004F00,%d1      | both words filled: a pair hit
        move.l  %d0,0x81A8          | 81A8 91929394
        move.l  %d1,0x81AC          | 81AC 91929394
        moveq   #0,%d0
        movec   %d0,%cacr           | caches off: a direct pair read
        move.l  0x08004F00,%d2
        moveq   #1,%d0
        movec   %d0,%cacr           | caches on again
        move.l  %d2,0x81B0          | 81B0 91929394
        .endif
        moveq   #0,%d7
        jsr     romfn+0xF80000      | Kickstart-ROM range: over the 7M bus,
        jsr     romfn+0xF80000      | then from the cache
        move.l  %d7,0x8140          | 8140 -> 0x55
        moveq   #0,%d3
        move.w  #0x2000,%sr
wait:   tst.l   %d3
        beq.s   wait
        move.l  %d3,(%a5)+          | 8120 33333333
        move.l  #0x600DC0DE,0x8FF0
done:   bra.s   done
romfn:  moveq   #0x55,%d7
        rts
        .balign 4
romdat: .long   0x01020304
        .balign 4
fn32:   nop                         | +0
        move.l  #0x89ABCDEF,%d6     | +2 opcode, +4 imm32 (4-byte aligned)
        nop                         | +8
        add.l   0x08000F00,%d6      | +10 opcode, +12 abs.L (aligned); long data read
        rts                         | +16
fastfn: move.l  #0xFA57,%d6
        rts
        nop
        nop
        nop
trap0:  move.l  #0x7777,%d2
        rte
irq3:   move.l  #0x33333333,%d3
        move.b  #1,0x8F80           | ack (kept clear of the stack)
        rte
