#!/usr/bin/env python3
"""Generate isa_test.s, the differential instruction test (step 26a).

Each case loads random registers, flags and 128 bytes of scratch memory,
runs one instruction (or a short fixed sequence: a branch, a call), and
stores D0-D7/A0-A7, SR, the last exception (vector word and stacked PC) and
the scratch bytes into its own result block. tb_isa.sv runs the program;
run.sh isa compares the result area with isa_ref.hex, made on the v2.1
core. Seeded: the same seed gives the same program.

  python3 gen_isa.py [--seed 1] [--out isa_test.s] [--n 10]   (n: variants per form)

Memory map (4 MB): vectors at 0 (all exceptions -> exc), a jump at $400
to the code at $10000 (with its data tables, up to $1FFFFF: ~5,000
cases), scratch $6000-$607F (low, so abs.w reaches it), stack below
$7F00, exception record $7F80, result blocks of 200 bytes from $200000,
the case marker at $3FFFF8, the end at $3FFFF0.
"""
import argparse, random, collections

ap = argparse.ArgumentParser()
ap.add_argument('--seed', type=int, default=1)
ap.add_argument('--out', default='isa_test.s')
ap.add_argument('--n', type=int, default=10)
args = ap.parse_args()
R = random.Random(args.seed)

SCR, SZ = 0x6000, 128
RES, BLK = 0x200000, 200
EDGE = [0, 1, 2, 0x7F, 0x80, 0xFF, 0x7FFF, 0x8000, 0xFFFF, 0x7FFFFFFF, 0x80000000,
        0xFFFFFFFF, 0xFFFFFFFE, 0x00010000, 0x0000FFFF, 0x55555555, 0xAAAAAAAA, 0x12345678]
SIZES = {'b': 1, 'w': 2, 'l': 4}
CONDS = ['t', 'f', 'hi', 'ls', 'cc', 'cs', 'ne', 'eq', 'vc', 'vs', 'pl', 'mi', 'ge', 'lt', 'gt', 'le']
BCONDS = [c for c in CONDS if c not in ('t', 'f')]


def rnd32():
    return R.choice(EDGE) if R.random() < 0.3 else R.getrandbits(32)


def s8(v):
    return v - 256 if v & 0x80 else v


class Case:
    """one test case: register values, CCR, scratch pattern, lines"""
    def __init__(self):
        self.d = [rnd32() for _ in range(8)]
        self.a = [0] * 7
        for i in range(4):          # a0-a3: pointers into the scratch area
            off = 32 + R.randrange(64)
            if R.random() < 0.75:
                off &= ~1
            self.a[i] = SCR + off
        self.a[4] = R.randint(-6, 6) & 0xFFFFFFFF     # index registers
        self.a[5] = R.randint(-6, 6) & 0xFFFFFFFF
        self.a[6] = SCR - 0x1000 + R.randrange(16)    # a far base (full-format modes)
        self.ccr = R.randrange(32)
        self.pat = bytearray(R.getrandbits(8) for _ in range(SZ))
        self.pre = []               # lines after the registers are loaded, before CCR
        self.lines = []
        self.post = []              # data after the case (PC-relative targets)
        self.name = ''
        self.mod = set()            # a0-a3 moved by an earlier operand ((An)+, -(An))

    def aval(self, r):              # signed value of a4 / a5 (index registers)
        v = self.a[r]
        return v - (1 << 32) if v & 0x80000000 else v

    def ptr(self, off, val):        # a long pointer in the scratch pattern
        self.pat[off:off + 4] = val.to_bytes(4, 'big')


def target(c, sz):
    return SCR + 8 + R.randrange(SZ - 16 - sz)


def ea(c, sz, kind, label, an=True):
    """an effective address for an operand of sz bytes. kind: 'd' data
    alterable, 'm' memory alterable, 's' any source, 'c' control; an=False
    leaves An out of a source (data-only operations: and, or, chk, mul, div).
    Returns its text; memory accesses land in the scratch area."""
    modes = []
    if kind in ('d', 's'):
        modes += ['Dn']
    if kind == 's' and sz > 1 and an:
        modes += ['An']
    if kind in ('d', 'm', 's'):
        modes += ['(An)+', '-(An)']
    modes += ['(An)', 'd16(An)', 'd8(An,Xn)', 'bd(An,Xn)', '([bd,An],Xn,od)', '([bd,An,Xn],od)', 'abs.w', 'abs.l']
    if kind in ('s', 'c'):
        modes += ['d16(PC)', 'd8(PC,Xn)']
    if kind == 's':
        modes += ['#imm']
    m = R.choice(modes)
    free = [i for i in range(4) if i not in c.mod] or [0]
    n = R.choice(free)              # a base no earlier operand has moved
    if m in ('(An)+', '-(An)'):
        c.mod.add(n)
    if m == 'Dn':
        return '%%d%d' % R.randrange(8)
    if m == 'An':
        return '%%a%d' % R.randrange(7)
    if m == '(An)+':
        return '(%%a%d)+' % n
    if m == '-(An)':
        return '-(%%a%d)' % n
    if m == '(An)':
        return '(%%a%d)' % n
    t = target(c, sz)
    xr = R.choice([4, 5]); xs = R.choice(['w', 'l']); sc = R.choice([1, 2, 4, 8])
    idx = c.aval(xr) * sc
    X = '%%a%d.%s*%d' % (xr, xs, sc)
    if m == 'd16(An)':
        return '(%d,%%a%d)' % (t - c.a[n], n)
    if m == 'd8(An,Xn)':
        return '(%d,%%a%d,%s)' % (t - c.a[n] - idx, n, X)
    if m == 'bd(An,Xn)':
        return '(%d,%%a6,%s)' % (t - c.a[6] - idx, X)
    if m in ('([bd,An],Xn,od)', '([bd,An,Xn],od)'):
        p = 4 * R.randrange(SZ // 4)              # where the pointer lives
        P = SCR + 64
        c.ptr(p, P)
        if m == '([bd,An],Xn,od)':
            return '([%d,%%a%d],%s,%d)' % (SCR + p - c.a[n], n, X, t - P - idx)
        return '([%d,%%a%d,%s],%d)' % (SCR + p - c.a[n] - idx, n, X, t - P)
    if m == 'abs.w':
        return '(0x%x).w' % t
    if m == 'abs.l':
        return '(0x%x).l' % t
    if m in ('d16(PC)', 'd8(PC,Xn)'):
        if not c.post:
            c.post = ['pcd_%s: .long ' % label + ','.join('0x%08x' % R.getrandbits(32) for _ in range(8))]
        off = R.randrange(32 - sz)
        if m == 'd16(PC)':
            return '(pcd_%s+%d,%%pc)' % (label, off)
        return '(pcd_%s+%d-(%d),%%pc,%s)' % (label, off, idx, X)
    if m == '#imm':
        v = rnd32() & ((1 << (8 * sz)) - 1)
        return '#0x%x' % v
    raise ValueError(m)


def dreg():
    return '%%d%d' % R.randrange(8)


def areg():
    return '%%a%d' % R.randrange(4)


# ---- the instruction forms -----------------------------------------------------
# each returns the case's instruction lines (and may set registers, pre-lines)
FORMS = collections.OrderedDict()


def form(name):
    def reg(f):
        FORMS[name] = f
        return f
    return reg


for op in ('add', 'sub', 'and', 'or', 'cmp'):
    for sz in 'bwl':
        def f(c, L, op=op, sz=sz):
            src = ea(c, SIZES[sz], 's', L, an=op in ('add', 'sub', 'cmp'))
            if src.startswith('%a') and sz == 'b':
                src = dreg()
            return ['%s.%s %s,%s' % (op, sz, src, dreg())]
        form('%s.%s <ea>,Dn' % (op, sz))(f)
        if op != 'cmp':
            def g(c, L, op=op, sz=sz):
                return ['%s.%s %s,%s' % (op, sz, dreg(), ea(c, SIZES[sz], 'm', L))]
            form('%s.%s Dn,<ea>' % (op, sz))(g)
for sz in 'bwl':
    form('eor.%s Dn,<ea>' % sz)(lambda c, L, sz=sz: ['eor.%s %s,%s' % (sz, dreg(), ea(c, SIZES[sz], 'd', L))])
    for op in ('addi', 'subi', 'andi', 'ori', 'eori', 'cmpi'):
        def f(c, L, op=op, sz=sz):
            v = rnd32() & ((1 << (8 * SIZES[sz])) - 1)
            k = 's' if op == 'cmpi' else 'd'
            dst = ea(c, SIZES[sz], k, L)
            while dst.startswith('#') or (dst.startswith('%a')):
                dst = ea(c, SIZES[sz], k, L)
            return ['%s.%s #0x%x,%s' % (op, sz, v, dst)]
        form('%s.%s #,<ea>' % (op, sz))(f)
    for op in ('addq', 'subq'):
        def f(c, L, op=op, sz=sz):
            dst = ea(c, SIZES[sz], 'd', L)
            if sz != 'b' and R.random() < 0.2:
                dst = areg()
            return ['%s.%s #%d,%s' % (op, sz, R.randint(1, 8), dst)]
        form('%s.%s #,<ea>' % (op, sz))(f)
    for op in ('clr', 'neg', 'negx', 'not', 'tst'):
        def f(c, L, op=op, sz=sz):
            k = 's' if op == 'tst' else 'd'
            dst = ea(c, SIZES[sz], k, L)
            if dst.startswith('%a') and sz == 'b':
                dst = dreg()
            return ['%s.%s %s' % (op, sz, dst)]
        form('%s.%s <ea>' % (op, sz))(f)
    form('move.%s <ea>,<ea>' % sz)(lambda c, L, sz=sz: ['move.%s %s,%s' % (sz, (lambda s: dreg() if s.startswith('%a') and sz == 'b' else s)(ea(c, SIZES[sz], 's', L)), ea(c, SIZES[sz], 'd', L))])
    form('addx.%s' % sz)(lambda c, L, sz=sz: ['addx.%s %s,%s' % (sz, dreg(), dreg())] if R.random() < 0.5 else ['addx.%s -(%s),-(%s)' % (sz, areg(), areg())])
    form('subx.%s' % sz)(lambda c, L, sz=sz: ['subx.%s %s,%s' % (sz, dreg(), dreg())] if R.random() < 0.5 else ['subx.%s -(%s),-(%s)' % (sz, areg(), areg())])
    form('cmpm.%s' % sz)(lambda c, L, sz=sz: ['cmpm.%s (%s)+,(%s)+' % (sz, areg(), areg())])
    for sh in ('asl', 'asr', 'lsl', 'lsr', 'rol', 'ror', 'roxl', 'roxr'):
        def f(c, L, sh=sh, sz=sz):
            if R.random() < 0.5:
                return ['%s.%s #%d,%s' % (sh, sz, R.randint(1, 8), dreg())]
            r = R.randrange(8)
            c.d[r] = R.choice([0, 1, 7, 8, 9, 15, 16, 17, 31, 32, 33, 63, 64, R.getrandbits(32)])
            return ['%s.%s %%d%d,%s' % (sh, sz, r, dreg())]
        form('%s.%s count,Dn' % (sh, sz))(f)
for sh in ('asl', 'asr', 'lsl', 'lsr', 'rol', 'ror', 'roxl', 'roxr'):
    form('%s.w <ea>' % sh)(lambda c, L, sh=sh: ['%s.w %s' % (sh, ea(c, 2, 'm', L))])
for sz in 'wl':
    for op in ('adda', 'suba', 'cmpa'):
        form('%s.%s <ea>,An' % (op, sz))(lambda c, L, op=op, sz=sz: ['%s.%s %s,%s' % (op, sz, ea(c, SIZES[sz], 's', L), areg())])
    form('movea.%s <ea>,An' % sz)(lambda c, L, sz=sz: ['movea.%s %s,%s' % (sz, ea(c, SIZES[sz], 's', L), areg())])
    form('chk.%s <ea>,Dn' % sz)(lambda c, L, sz=sz: ['chk.%s %s,%s' % (sz, ea(c, SIZES[sz], 's', L, an=False), dreg())])
form('moveq')(lambda c, L: ['moveq #%d,%s' % (R.randint(-128, 127), dreg())])
form('ext.w')(lambda c, L: ['ext.w ' + dreg()])
form('ext.l')(lambda c, L: ['ext.l ' + dreg()])
form('extb.l')(lambda c, L: ['extb.l ' + dreg()])
form('swap')(lambda c, L: ['swap ' + dreg()])
form('exg')(lambda c, L: ['exg %s,%s' % (R.choice([dreg(), areg()]), R.choice([dreg(), areg()]))])
form('lea')(lambda c, L: ['lea %s,%s' % (ea(c, 4, 'c', L), areg())])
form('pea')(lambda c, L: ['pea ' + ea(c, 4, 'c', L)])
form('scc')(lambda c, L: ['s%s %s' % (R.choice(CONDS), ea(c, 1, 'd', L))])
form('tas')(lambda c, L: ['tas ' + ea(c, 1, 'd', L)])
form('nbcd')(lambda c, L: ['nbcd ' + ea(c, 1, 'd', L)])
form('abcd')(lambda c, L: ['abcd %s,%s' % (dreg(), dreg())] if R.random() < 0.5 else ['abcd -(%s),-(%s)' % (areg(), areg())])
form('sbcd')(lambda c, L: ['sbcd %s,%s' % (dreg(), dreg())] if R.random() < 0.5 else ['sbcd -(%s),-(%s)' % (areg(), areg())])
form('pack')(lambda c, L: ['pack %s,%s,#0x%x' % (dreg(), dreg(), R.getrandbits(16))] if R.random() < 0.5 else ['pack -(%s),-(%s),#0x%x' % (areg(), areg(), R.getrandbits(16))])
form('unpk')(lambda c, L: ['unpk %s,%s,#0x%x' % (dreg(), dreg(), R.getrandbits(16))] if R.random() < 0.5 else ['unpk -(%s),-(%s),#0x%x' % (areg(), areg(), R.getrandbits(16))])
for op in ('btst', 'bset', 'bclr', 'bchg'):
    def f(c, L, op=op):
        if R.random() < 0.5:
            src = '#%d' % R.randrange(64)
        else:
            src = dreg()
        if R.random() < 0.4:
            return ['%s %s,%s' % (op, src, dreg())]
        dst = ea(c, 1, 's' if op == 'btst' else 'm', L)
        while dst.startswith('%a') or (dst.startswith('#') and src.startswith('#')):
            dst = ea(c, 1, 's' if op == 'btst' else 'm', L)
        return ['%s %s,%s' % (op, src, dst)]
    form(op)(f)
for op in ('mulu', 'muls', 'divu', 'divs'):
    def f(c, L, op=op):
        r = R.randrange(8)
        if op[0] == 'd' and R.random() < 0.15:
            c.d[r] = 0                       # divide by zero
        return ['%s.w %%d%d,%s' % (op, r, dreg())] if R.random() < 0.6 else ['%s.w %s,%s' % (op, ea(c, 2, 's', L, an=False), dreg())]
    form(op + '.w')(f)
    def g(c, L, op=op):
        r = R.randrange(8)
        if op[0] == 'd' and R.random() < 0.15:
            c.d[r] = 0
        h, l = R.sample(range(8), 2)
        dst = R.choice(['%%d%d' % l, '%%d%d:%%d%d' % (h, l)])
        return ['%s.l %%d%d,%s' % (op, r, dst)] if R.random() < 0.6 else ['%s.l %s,%s' % (op, ea(c, 4, 's', L, an=False), dst)]
    form(op + '.l')(g)
for op in ('divul', 'divsl'):
    def f(c, L, op=op):
        r = R.randrange(8)
        if R.random() < 0.15:
            c.d[r] = 0
        h, l = R.sample(range(8), 2)
        return ['%s.l %%d%d,%%d%d:%%d%d' % (op, r, h, l)]
    form(op)(f)
for op in ('bftst', 'bfextu', 'bfexts', 'bfffo', 'bfset', 'bfclr', 'bfchg', 'bfins'):
    def f(c, L, op=op):
        if R.random() < 0.5:
            o, w = '#%d' % R.randrange(32), '#%d' % R.randint(1, 32)
        else:
            ro, rw = R.sample(range(8), 2)
            c.d[ro] = R.randint(-24, 40) & 0xFFFFFFFF
            c.d[rw] = R.getrandbits(32)
            o, w = '%%d%d' % ro, '%%d%d' % rw
        dst = dreg() if R.random() < 0.4 else '(%s)' % areg()
        if op in ('bfextu', 'bfexts', 'bfffo'):
            return ['%s %s{%s:%s},%s' % (op, dst, o, w, dreg())]
        if op == 'bfins':
            return ['bfins %s,%s{%s:%s}' % (dreg(), dst, o, w)]
        return ['%s %s{%s:%s}' % (op, dst, o, w)]
    form(op)(f)
for sz in 'bwl':
    def f(c, L, sz=sz):
        return ['cas.%s %s,%s,%s' % (sz, dreg(), dreg(), ea(c, SIZES[sz], 'm', L))]
    form('cas.' + sz)(f)
    form('chk2.' + sz)(lambda c, L, sz=sz: ['%s.%s %s,%s' % (R.choice(['chk2', 'cmp2']), sz, ea(c, 2 * SIZES[sz], 'c', L), R.choice([dreg(), areg()]))])
for sz in 'wl':
    def f(c, L, sz=sz):
        regs = ['%%d%d' % i for i in range(8)] + ['%%a%d' % i for i in range(6)]
        n = R.randint(1, 6)
        lst = '/'.join(sorted(R.sample(regs, n)))
        an = R.randrange(4)
        if R.random() < 0.5:     # to memory
            c.a[an] = SCR + 48 + 2 * R.randrange(16)
            return ['movem.%s %s,%s' % (sz, lst, R.choice(['-(%%a%d)' % an, '(%%a%d)' % an, '(8,%%a%d)' % an]))]
        c.a[an] = SCR + 2 * R.randrange(24)
        return ['movem.%s %s,%s' % (sz, R.choice(['(%%a%d)+' % an, '(%%a%d)' % an, '(4,%%a%d)' % an]), lst)]
    form('movem.' + sz)(f)
def f(c, L):
    k = R.randrange(3)
    if k == 0:
        src = ea(c, 2, 's', L)
        while src.startswith('%a'):
            src = ea(c, 2, 's', L)
        return ['move.w %s,%%ccr' % src]
    if k == 1:
        return ['move.w %%ccr,%s' % ea(c, 2, 'd', L)]
    return ['move.w %%sr,%s' % ea(c, 2, 'd', L)]
form('move ccr/sr')(f)
form('andi/ori/eori ccr')(lambda c, L: ['%s.b #0x%x,%%ccr' % (R.choice(['andi', 'ori', 'eori']), R.getrandbits(8))])
# control flow: a fixed shape, so the result shows the path taken
form('bcc')(lambda c, L: ['b%s.%s 1f' % (R.choice(BCONDS + ['ra']), R.choice('swl')), 'moveq #-1,%d7', '1:'])
# step 26b: a short branch then a trap on each path (the stacked PC after a
# taken and a not-taken branch), and a backward loop (its target is fetched
# uncached the first time, from the cache after)
form('bcc.s+trap')(lambda c, L: ['b%s.s 1f' % R.choice(BCONDS + ['ra']), R.choice(['illegal', 'trap #5', 'divu.w #0,%d1']), '1: ' + R.choice(['illegal', 'trap #6', 'divu.w #0,%d2', 'chk.w #-1,%d3'])])
form('bcc.s loop')(lambda c, L: (c.d.__setitem__(0, R.randrange(-4, 3) & 0xFFFFFFFF), ['2: addq.l #1,%d0', 'cmp.l #3,%d0', 'b%s.s 2b' % R.choice(['lt', 'le', 'ne', 'mi', 'cs'])])[1])
form('dbcc')(lambda c, L: (c.d.__setitem__(1, (c.d[1] & 0xFFFF0000) | R.randrange(5)), ['2: addq.l #1,%d0', 'db%s %%d1,2b' % R.choice(CONDS)])[1])
form('bsr/rts')(lambda c, L: ['bsr.%s 2f' % R.choice('swl'), 'bra.s 3f', '2: addq.l #1,%d0', 'rts', '3:'])
form('jsr/rts')(lambda c, L: ['lea 2f,%a0', 'jsr (%a0)', 'bra.s 3f', '2: addq.l #3,%d0', 'rts', '3:'])
form('jsr d16(pc)')(lambda c, L: ['jsr (2f,%pc)', 'bra.s 3f', '2: subq.l #3,%d0', 'rts', '3:'])
form('jmp')(lambda c, L: ['lea 2f,%a1', 'jmp (%a1)', 'moveq #-1,%d7', '2:'])
form('rtd')(lambda c, L: ['move.l #0x11223344,-(%sp)', 'pea 3f', 'rtd #%d' % R.choice([4, 8, -4]), 'moveq #-1,%d7', '3:'])
form('rtr')(lambda c, L: ['pea 3f', 'move.w #0x%x,-(%%sp)' % R.getrandbits(16), 'rtr', 'moveq #-1,%d7', '3:'])
form('link/unlk')(lambda c, L: ['link.%s %%a3,#%d' % (R.choice('wl'), -4 * R.randint(0, 8)), 'move.l %d0,-4(%a3)', 'move.l -4(%a3),%d1', 'unlk %a3'])
form('trap')(lambda c, L: [R.choice(['trap #%d' % R.randrange(16), 'trapv', 't%s' % R.choice(['rapne', 'rapeq', 'rapcs', 'rapt', 'rapf']), 'illegal'])])

# ---- the program -----------------------------------------------------------------
cases = []
count = collections.Counter()
for name, f in FORMS.items():
    for _ in range(args.n):
        c = Case()
        L = str(len(cases))
        c.lines = f(c, L)
        c.name = name
        cases.append(c)
        count[name.split()[0].split('.')[0]] += 1

o = []
w = o.append
w('| isa_test.s -- made by gen_isa.py --seed %d --n %d: do not edit' % (args.seed, args.n))
w('        .org 0')
w('        .long 0x00007F00, start')
for v in range(2, 256):
    w('        .long exc')
w('        .org 0x400')
w('start:  jmp     main')
w('        .org 0x10000')
w('main:   moveq   #1,%d0')
w('        movec   %d0,%cacr')
for i, c in enumerate(cases):
    res = RES + BLK * i
    w('| case %d: %s' % (i, c.name))
    w('c_%d:    move.l  #%d,(0x3FFFF8).l' % (i, i))
    w('        lea     pat_%d,%%a0' % i)
    w('        lea     0x%x,%%a1' % SCR)
    w('        moveq   #%d,%%d0' % (SZ // 4 - 1))
    w('1:      move.l  (%a0)+,(%a1)+')
    w('        dbra    %d0,1b')
    w('        clr.w   (0x7F80).l')
    w('        clr.l   (0x7F82).l')
    w('        move.l  #k_%d,(0x7F86).l' % i)
    w('        lea     0x7F00,%sp')
    w('        movem.l reg_%d,%%d0-%%d7/%%a0-%%a6' % i)
    for l in c.pre:
        w('        ' + l)
    w('        move.w  #0x%x,%%ccr' % c.ccr)
    for l in c.lines:
        if l.endswith(':') or l.startswith('2:') or l.startswith('3:'):
            w(l)
        else:
            w('        ' + l + ('            | case %d' % i))
    w('k_%d:    movem.l %%d0-%%d7/%%a0-%%a7,(0x%x).l' % (i, res))
    w('        move.w  %%sr,(0x%x).l' % (res + 64))
    w('        move.w  (0x7F80).l,(0x%x).l' % (res + 66))
    w('        move.l  (0x7F82).l,(0x%x).l' % (res + 68))
    w('        lea     0x%x,%%a0' % SCR)
    w('        lea     0x%x,%%a1' % (res + 72))
    w('        moveq   #%d,%%d0' % (SZ // 4 - 1))
    w('1:      move.l  (%a0)+,(%a1)+')
    w('        dbra    %d0,1b')
    if c.post:
        w('        bra.w   9f')
        for l in c.post:
            w(l)
        w('9:')
w('        move.l  #%d,(0x3FFFF8).l' % len(cases))
w('        move.l  #0x600DC0DE,(0x3FFFF0).l')
w('done:   bra.s   done')
w('| every exception: record the vector word and the stacked PC, return past')
w('| the instruction to the case\'s k_ label')
w('exc:    move.w  6(%sp),(0x7F80).l')
w('        move.l  2(%sp),(0x7F82).l')
w('        move.l  (0x7F86).l,2(%sp)')
w('        rte')
w('        .balign 4')
for i, c in enumerate(cases):
    w('reg_%d:  .long %s' % (i, ','.join('0x%08x' % v for v in c.d + c.a)))
    w('pat_%d:  .byte %s' % (i, ','.join(str(b) for b in c.pat)))
open(args.out, 'w').write('\n'.join(o) + '\n')
open(args.out.replace('.s', '_cases.txt'), 'w').write(
    '\n'.join('%d %s | %s' % (i, c.name, ' ; '.join(c.lines)) for i, c in enumerate(cases)) + '\n')
print('%d cases, %d forms' % (len(cases), len(FORMS)))
assert len(cases) * BLK <= 0x1FFFF0, 'too many cases for the result area'
print(', '.join('%s %d' % kv for kv in sorted(count.items())))
