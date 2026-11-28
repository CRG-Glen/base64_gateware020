#!/usr/bin/env python3
"""Compare isa_out.hex (this core) with isa_ref.hex (the v2.1 core), case by
case (step 26a). Prints the first differing cases with the instruction and
the fields that differ, the step counts against the reference, and PASS or
FAIL. Run from sim/ (run.sh isa does)."""
import sys
W = 100                                  # words per case block
NAMES = ['d%d' % i for i in range(8)] + ['a%d' % i for i in range(8)]


def load(p):
    return [int(l, 16) for l in open(p) if l.strip()]


out, ref = load('isa_out.hex'), load('isa_ref.hex')
cases = [l.rstrip('\n') for l in open('isa_test_cases.txt')]
n = min(len(out), len(ref)) // W
bad = 0
if len(out) != len(ref):
    print('FAIL: %d cases, the reference has %d' % (len(out) // W, len(ref) // W))
    bad += 1
for i in range(n):
    o, r = out[i * W:(i + 1) * W], ref[i * W:(i + 1) * W]
    if o == r:
        continue
    bad += 1
    if bad <= 20:
        diff = []
        for k in range(16):
            ov, rv = (o[2 * k] << 16) | o[2 * k + 1], (r[2 * k] << 16) | r[2 * k + 1]
            if ov != rv:
                diff.append('%s %08x (ref %08x)' % (NAMES[k], ov, rv))
        if o[32] != r[32]:
            diff.append('SR %04x (ref %04x)' % (o[32], r[32]))
        if o[33:36] != r[33:36]:
            diff.append('exception %04x pc %04x%04x (ref %04x pc %04x%04x)' % (o[33], o[34], o[35], r[33], r[34], r[35]))
        mem = [k for k in range(36, W) if o[k] != r[k]]
        if mem:
            diff.append('scratch words %s' % ','.join('+%d' % (2 * (k - 36)) for k in mem[:8]))
        print('DIFF case %s\n     %s' % (cases[i] if i < len(cases) else i, '; '.join(diff)))
try:
    so = [int(l.split()[1]) for l in open('isa_steps.txt')]
    sr = [int(l.split()[1]) for l in open('isa_ref_steps.txt')]
    if len(so) == len(sr):
        fewer = sum(1 for a, b in zip(so, sr) if a < b)
        more = sum(1 for a, b in zip(so, sr) if a > b)
        print('kernel steps: %d against the reference %d (%+.2f%%); cases with fewer steps %d, more %d'
              % (sum(so), sum(sr), 100.0 * (sum(so) - sum(sr)) / max(1, sum(sr)), fewer, more))
except FileNotFoundError:
    pass
print('%d cases compared, %d differ' % (n, bad))
print('PASS' if bad == 0 else 'FAIL')
sys.exit(1 if bad else 0)
