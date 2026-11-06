#!/usr/bin/env python3
"""Neutralise GHDL 'case ... when others => null' feedback defaults.

GHDL translates a VHDL case over std_logic_vector into a one-hot Verilog case
whose default branch holds the previous value.  When the VHDL case already
lists every 0/1 value, that default is only reachable for X/U/Z, but yosys
cannot prove it and infers a latch, which synth_ecp5 rejects.  We ask yosys
which nets it would latch, and turn exactly those defaults into 'bx.
Usage: fix_latches.py in.v out.v [yosys]"""
import re, subprocess, sys
src, dst = sys.argv[1], sys.argv[2]
ys = sys.argv[3] if len(sys.argv) > 3 else 'yosys'
v = open(src).read()
fixed = []
for _ in range(500):
    open(dst, 'w').write(v)
    r = subprocess.run([ys, '-p', 'read_verilog %s; proc' % dst],
                       capture_output=True, text=True)
    out = r.stdout + r.stderr
    m = re.search(r"Latch inferred for signal `\\[^.]+\.\\(\S+?)'", out)
    if not m:
        if r.returncode != 0:
            sys.exit('yosys failed:\n' + out[-2000:])
        break
    n = m.group(1)
    v, c = re.subn(r"(default: " + re.escape(n) + r" = )[^;]+;", r"\1'bx;", v)
    if c == 0:
        sys.exit('latch on %s has no case default to fix - real latch?' % n)
    fixed.append(n)
print('fix_latches: neutralised %d unreachable defaults: %s' % (len(fixed), ' '.join(fixed)))
