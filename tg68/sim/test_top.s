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
        | -- fetch predictor (step 15): code that overwrites an instruction
        | just ahead of itself. smc0/1/2 store d5 over a moveq 0, 1 or 2
        | words after the store. Each is run twice unchanged (5, from the
        | cache and the predictor), then with moveq #2: that run gives 2 or 5
        | (the CPU may have fetched the old word already, as on a real
        | 68020; the tb expects what the unpredicted design does), and the
        | run after it must give 2: nothing may come from a stale cache
        | entry or a stale prediction.
        lea     smc0,%a0
        movea.l #0x08007000,%a1
        moveq   #(smcend-smc0)/4,%d0
cpsmc:  move.l  (%a0)+,(%a1)+
        dbra    %d0,cpsmc
        lea     0x8210,%a3
        lea     0x08007000,%a2
        bsr     smcrun
        lea     0x08007000+(smc1-smc0),%a2
        bsr     smcrun
        lea     0x08007000+(smc2-smc0),%a2
        bsr     smcrun
        | the same with a longword store (a pair write): its second word
        | is the instruction; d5's high word is the nop before it
        lea     0x08007000+(smc3-smc0),%a2
        bsr     smcrun
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
        | -- step 11: chip RAM code in the instruction cache --
        lea     chipfn,%a0
        movea.l #0x9800,%a1         | chip RAM (the tb's RAM is $8000-$9FFF)
        move.l  (%a0)+,(%a1)+       | moveq #1,%d4 ; rts
        jsr     0x9800              | fills the instruction cache
        jsr     0x9800              | runs from it (tb counts chip hits)
        move.l  %d4,0x81B4          | 81B4 00000001
        move.w  #0x7802,0x9800      | a CPU write drops the cached entry
        jsr     0x9800
        move.l  %d4,0x81B8          | 81B8 00000002
        move.b  #1,0x8F10           | tb rewrites $9800 behind the CPU, as DMA would
        move.l  #9,%d0              | EI + CI: clear the cache, as CacheClearU does
        movec   %d0,%cacr
        jsr     0x9800
        move.l  %d4,0x81BC          | 81BC 00000003
        moveq   #1,%d0
        movec   %d0,%cacr
        | -- step 11: posted chip RAM writes keep their order --
        move.w  #0x1234,0x8E00      | posted
        move.w  0x8E00,%d0          | the read waits for it
        move.b  #0x56,0x8E01        | posted byte write
        move.w  0x8E00,%d1
        swap    %d0
        move.w  %d1,%d0
        move.l  %d0,0x81C0          | 81C0 12341256
        | -- posted writes at every phase of the 7M grid: the delay loop
        | after each write shifts when the next one starts (the bridge once
        | left the data bus undriven when a write's DS met the AS tick) --
        lea     0x8E40,%a0
        moveq   #0,%d0
        moveq   #47,%d2
ph1:    move.w  %d0,(%a0)+          | posted
        move.w  %d0,%d1
        and.w   #3,%d1
ph2:    dbra    %d1,ph2
        addq.w  #1,%d0
        dbra    %d2,ph1
        lea     0x8E40,%a0
        moveq   #0,%d3
        moveq   #47,%d2
ph3:    add.w   (%a0)+,%d3
        dbra    %d2,ph3
        move.l  %d3,0x81C4          | 81C4 0+1+...+47 = 0x468
        | -- step 12: the write buffer drains before any other motherboard
        | cycle: four buffered writes, then a CIA read (the tb checks that
        | all four are in chip RAM when the CIA cycle starts) --
        move.w  #0x1111,0x8E90
        move.w  #0x2222,0x8E92
        move.w  #0x3333,0x8E94
        move.w  #0x4444,0x8E96
        tst.b   0xBFE001
        move.l  0x8E94,%d0
        move.l  %d0,0x81CC          | 81CC 33334444 (a read of buffered data)
        | -- a burst longer than the buffer: MOVEM.L of 8 registers is 16
        | bus words, so the CPU must wait for room; the sum checks every one
        moveq   #1,%d0
        moveq   #2,%d1
        moveq   #3,%d2
        moveq   #4,%d3
        moveq   #5,%d4
        moveq   #6,%d5
        moveq   #7,%d6
        moveq   #8,%d7
        lea     0x8EA0,%a0
        movem.l %d0-%d7,(%a0)
        moveq   #0,%d3
        moveq   #7,%d2
2:      add.l   (%a0)+,%d3
        dbra    %d2,2b
        move.l  %d3,0x81D0          | 81D0 1+...+8 = 0x24
        .ifdef FASTMEM
        | ...and with a fast RAM read before each write: the SDRAM's latency
        | is not a whole number of CPU steps, so the writes start at every
        | phase of the 7M grid, the DS-on-the-AS-tick one included
        lea     0x8E40,%a0
        movea.l #0x08006000,%a1
        moveq   #0,%d0
        moveq   #95,%d2
pf1:    move.w  (%a1)+,%d5
        move.w  %d0,(%a0)
        move.w  %d0,%d1
        and.w   #3,%d1
pf2:    dbra    %d1,pf2
        addq.w  #1,%d0
        dbra    %d2,pf1
        move.w  (%a0),%d3
        move.l  %d3,0x81C8          | 81C8 last value written: 95 = 0x5F
        | -- step 13: the speed switch, through the real register (the tb
        | forces the turbomem board configured at $EA0000) --
        moveq   #0,%d0
        move.w  0xEAF00A,%d0
        move.l  %d0,0x81D4          | 81D4 0000070C: 12x, switching ok, both PLLs locked
        move.w  #0x5B10,0xEAF00A    | -> 16x
        bsr     spdchk
        move.l  %d3,0x81DC          | 81DC ACF1E135
        moveq   #0,%d0
        move.w  0xEAF00A,%d0
        move.l  %d0,0x81D8          | 81D8 00000710
        move.w  #0x5B0E,0xEAF00A    | -> 14x
        bsr     spdchk
        move.l  %d3,0x81E4          | 81E4 ACF1E135
        moveq   #0,%d0
        move.w  0xEAF00A,%d0
        move.l  %d0,0x81E0          | 81E0 0000070E
        move.w  #0x5B0C,0xEAF00A    | -> 12x
        bsr     spdchk
        move.l  %d3,0x81EC          | 81EC ACF1E135
        moveq   #0,%d0
        move.w  0xEAF00A,%d0
        move.l  %d0,0x81E8          | 81E8 0000070C
        move.w  #0x5B11,0xEAF00A    | not a speed: ignored
        move.w  #0x1210,0xEAF00A    | no key: ignored
        moveq   #0,%d0
        move.w  0xEAF00A,%d0
        move.l  %d0,0x81F0          | 81F0 0000070C
        move.w  #0x5B4C,0xEAF00A    | 12x again, 7M sample forced to the rising edge
        bsr     spdchk
        moveq   #0,%d0
        move.w  0xEAF00A,%d0
        move.l  %d0,0x81F4          | 81F4 0000170C (bit 12: rising stream)
        move.w  #0x5BCC,0xEAF00A    | sample select 3: not valid, ignored
        moveq   #0,%d0
        move.w  0xEAF00A,%d0
        move.l  %d0,0x81F8          | 81F8 0000170C
        move.w  #0x5B0C,0xEAF00A    | 12x, calibration decides again
        bsr     spdchk
        move.l  %d3,0x81FC          | 81FC ACF1E135
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
        .ifdef FASTMEM
| step 13: SDRAM pair writes and uncached reads (the new CAS latency), a
| buffered chip RAM write and its read, a CIA access: at each speed
spdchk: moveq   #0,%d4
        movec   %d4,%cacr           | caches off: every read goes to the SDRAM
        lea     0x08006200,%a0
        move.l  #0x12345678,(%a0)
        move.l  #0x9ABCDEF0,4(%a0)
        move.l  (%a0),%d3
        add.l   4(%a0),%d3          | ACF13568
        move.w  #0xABCD,0x8EC0
        add.w   0x8EC0,%d3          | ACF1E135
        tst.b   0xBFE001
        moveq   #1,%d4
        movec   %d4,%cacr
        rts
        .endif
        .ifdef FASTMEM
| step 15: run the routine at a2 as described above; results to (a3)+
smcrun: move.l  #0x4E717805,%d5     | (nop,) moveq #5,%d4: no change
        jsr     (%a2)
        jsr     (%a2)
        move.l  #0x4E717802,%d5     | (nop,) moveq #2,%d4
        jsr     (%a2)
        move.l  %d4,(%a3)+          | 2 or 5
        jsr     (%a2)
        move.l  %d4,(%a3)+          | 2
        rts
        .balign 4
smc0:   lea     1f(%pc),%a0
        moveq   #0,%d4
        move.w  %d5,(%a0)
1:      moveq   #5,%d4
        rts
        .balign 4
smc1:   lea     1f(%pc),%a0
        moveq   #0,%d4
        move.w  %d5,(%a0)
        nop
1:      moveq   #5,%d4
        rts
        .balign 4
smc2:   lea     1f(%pc),%a0
        moveq   #0,%d4
        move.w  %d5,(%a0)
        nop
        nop
1:      moveq   #5,%d4
        rts
        .balign 4
smc3:   lea     1f(%pc),%a0         | +0  (1f = +8, long-aligned)
        moveq   #0,%d4              | +4
        move.l  %d5,(%a0)           | +6  pair write to +8/+10
1:      nop                         | +8
        moveq   #5,%d4              | +10
        rts
        .balign 4
smcend: nop
        .endif
chipfn: moveq   #1,%d4              | step 11 test routine, copied to $9800
        rts
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
