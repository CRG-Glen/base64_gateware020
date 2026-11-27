#!/usr/bin/env python3
"""SDRAM data pin -> register timing from nextpnr's SDF (step 23 finding).

check_timing.py times register -> register paths only. The SDRAM read data
(sdram_ctrl rdata_live = sdram_dq) goes from the pins straight into fabric
registers (k_din_dw, dp_q, the cache data), so each seed routes those paths
differently and nothing checks them. At 22x that decided whether a build ran:
step 23 seed 7 (worst 5.01 ns, mean 4.40) crashed at 22x on Glen's board,
seed 4 of the same netlist (4.79 / 4.19) and exp_22x seed 15 (4.79 / 3.93)
ran.

For each sdram_dq pin: the longest pad -> FF D delay plus that FF's setup.
Usage: sdram_pins.py design.sdf [design.sdf ...]
"""
import os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
src = open(os.path.join(HERE, 'check_timing.py')).read().split('# ---- classify')[0]

for sdf in sys.argv[1:]:
    g = {}
    sys.argv = ['check_timing.py', sdf]
    exec(compile(src, 'check_timing.py', 'exec'), g)   # its SDF parser only
    edges, setup, clkpin = g['edges'], g['setup'], g['clkpin_delay']
    res = {}
    for s in [n for n in edges if re.match(r'sdram_dq\[\d+\]\$tr_io/O$', n)]:
        arr, frontier = {s: 0.0}, [s]
        for _ in range(64):
            nf = []
            for n in frontier:
                for b, d in edges.get(n, ()):
                    if arr[n] + d > arr.get(b, -1.0):
                        arr[b] = arr[n] + d; nf.append(b)
            frontier = nf
            if not frontier: break
        best = max(((t + setup[n][1] - clkpin.get(setup[n][0], 0.0), setup[n][0])
                    for n, t in arr.items() if n in setup), default=(0.0, '-'))
        res[int(re.search(r'\[(\d+)\]', s).group(1))] = best
    v = [res[k][0] / 1000 for k in sorted(res)]
    print('%s\n  mean %.2f ns  worst %.2f ns  (pin %d -> %s)' % (sdf, sum(v) / len(v), max(v),
          max(res, key=lambda k: res[k][0]), max(res.values())[1]))
    print('  ' + ' '.join('%d:%.2f' % (k, res[k][0] / 1000) for k in sorted(res)))
