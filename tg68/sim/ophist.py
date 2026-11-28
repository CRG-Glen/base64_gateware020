#!/usr/bin/env python3
"""Group a bench's instructions by kind (step 26): reads the "OPH opcode
steps clocks" lines that tb_top.sv prints with -DOPHIST and prints, per
kind, the count, the kernel steps and clocks (total and per instruction)
and the share of all clocks, largest first.

  VLFLAGS=-DOPHIST sh run.sh bench c > c.log; python3 ophist.py < c.log
"""
import sys, collections

EA = ['Dn', 'An', '(An)', '(An)+', '-(An)', 'd16(An)', 'idx(An)', 'x']
EA7 = {0: 'abs.w', 1: 'abs.l', 2: 'd16(pc)', 3: 'idx(pc)', 4: '#imm'}


def ea(mode, reg):
    if mode == 7:
        return EA7.get(reg, '?')
    return EA[mode]


def mem(mode, reg):
    return 'mem' if mode >= 2 and not (mode == 7 and reg == 4) else ('#' if mode == 7 else 'reg')


def kind(op):
    hi = op >> 12
    m, r = (op >> 3) & 7, op & 7
    dm, dr = (op >> 6) & 7, (op >> 9) & 7
    sz = (op >> 6) & 3
    if hi in (1, 2, 3):
        s = {1: 'b', 3: 'w', 2: 'l'}[hi]
        if dm == 1:
            return 'movea.%s %s' % (s, mem(m, r))
        return 'move.%s %s->%s' % (s, mem(m, r), mem(dm, dr))
    if hi == 7:
        return 'moveq'
    if hi == 6:
        c = (op >> 8) & 15
        return 'bra' if c == 0 else 'bsr' if c == 1 else 'bcc'
    if hi == 5:
        if (op & 0xF8) == 0xC8 and sz == 3:
            return 'dbcc'
        if sz == 3:
            return 'scc'
        return '%s %s' % ('subq' if op & 0x100 else 'addq', mem(m, r))
    if hi == 4:
        if op == 0x4E75: return 'rts'
        if op == 0x4E71: return 'nop'
        if op == 0x4E73: return 'rte'
        if op == 0x4E74: return 'rtd'
        if op == 0x4E77: return 'rtr'
        if (op & 0xFFF8) == 0x4E50: return 'link'
        if (op & 0xFFF8) == 0x4E58: return 'unlk'
        if (op & 0xFFF0) == 0x4E40: return 'trap'
        if (op & 0xFFC0) == 0x4E80: return 'jsr'
        if (op & 0xFFC0) == 0x4EC0: return 'jmp'
        if (op & 0xFFF8) == 0x49C0: return 'extb'
        if (op & 0xF1C0) == 0x41C0: return 'lea %s' % ea(m, r)
        if (op & 0xFFC0) == 0x4840: return 'pea' if m else 'swap'
        if (op & 0xFB80) == 0x4880:
            if m == 0: return 'ext'
            return 'movem %s' % ('mem->regs' if op & 0x400 else 'regs->mem')
        if (op & 0xFF00) == 0x4200: return 'clr %s' % mem(m, r)
        if (op & 0xFF00) == 0x4400: return 'neg %s' % mem(m, r)
        if (op & 0xFF00) == 0x4600: return 'not %s' % mem(m, r)
        if (op & 0xFF00) == 0x4A00: return 'tst %s' % mem(m, r)
        if (op & 0xFFC0) == 0x4C00: return 'mul.l'
        if (op & 0xFFC0) == 0x4C40: return 'div.l'
        if (op & 0xFFF8) == 0x49C0: return 'extb'
        return 'misc4 %04x' % (op & 0xFFC0)
    if hi in (8, 9, 0xB, 0xC, 0xD):
        name = {8: 'or', 9: 'sub', 0xB: 'cmp', 0xC: 'and', 0xD: 'add'}[hi]
        om = (op >> 6) & 7
        if om in (3, 7):
            if hi in (9, 0xB, 0xD):
                return '%sa %s' % (name, mem(m, r))
            return {8: 'divu.w', 0xC: 'mulu.w'}[hi] if om == 3 else {8: 'divs.w', 0xC: 'muls.w'}[hi]
        if hi == 0xB and om >= 4:
            return 'cmpm' if m == 1 else 'eor %s' % ('reg' if m == 0 else 'Dn->mem')
        if om >= 4 and m in (0, 1) and hi in (8, 9, 0xC, 0xD):
            return {8: 'sbcd', 9: 'subx', 0xC: 'abcd/exg', 0xD: 'addx'}[hi]
        if om >= 4:
            return '%s Dn->mem' % name
        return '%s %s->Dn' % (name, mem(m, r))
    if hi == 0xE:
        if sz == 3:
            return 'bitfield' if op & 0x800 else 'shift mem'
        return 'shift reg'
    if hi == 0:
        if op & 0x100 or (op & 0xF00) == 0x800:
            return 'bit op %s' % mem(m, r)
        return {0: 'ori', 2: 'andi', 4: 'subi', 6: 'addi', 0xA: 'eori', 0xC: 'cmpi'}.get((op >> 8) & 15, 'misc0') + ' ' + mem(m, r)
    return 'other %x' % hi


tot = collections.defaultdict(lambda: [0, 0, 0])
for l in sys.stdin:
    if not l.startswith('OPH '):
        continue
    _, op, st, ck = l.split()
    k = kind(int(op, 16))
    t = tot[k]; t[0] += 1; t[1] += int(st); t[2] += int(ck)
N = sum(v[0] for v in tot.values()); S = sum(v[1] for v in tot.values()); C = sum(v[2] for v in tot.values())
print('%d instructions, %d steps (%.2f each), %d clocks (%.2f each)' % (N, S, S / N, C, C / N))
print('%-26s %7s %7s %6s %8s %6s %6s' % ('kind', 'count', 'steps', 'st/i', 'clocks', 'ck/i', 'share'))
for k, (n, st, ck) in sorted(tot.items(), key=lambda kv: -kv[1][2]):
    print('%-26s %7d %7d %6.2f %8d %6.1f %5.1f%%' % (k, n, st, st / n, ck, ck / n, 100.0 * ck / C))
