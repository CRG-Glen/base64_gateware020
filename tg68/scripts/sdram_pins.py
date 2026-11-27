#!/usr/bin/env python3
"""SDRAM data pin -> register timing from nextpnr's SDF (steps 23 and 24).

check_timing.py's class table times register -> register paths. The SDRAM
read data (sdram_ctrl rdata_live = sdram_dq) goes from the pins straight
into fabric registers (cpu.k_din_dw, cpu.dp_q, cpu.pf_d through the
dp_rdata multiplexer, and g_sdram.u_sdram.rdata), so each seed routes those
paths differently. At 22x that decided whether a build ran (step 23):

  build                 22x on Glen's board          longest  shortest (cpu.*)
  exp_22x_7m seed 12    ran for a long time            4.47     1.60
  exp_22x seed 15       ran the benchmarks             4.79     2.16
  step23 seed 4         froze halfway through Frontier 4.79     2.47
  step23 seed 7         froze on the switch            5.01     3.04

For each sdram_dq pin: the longest path from the pad buffer's output to a
register's D, plus that register's setup, less the clock's arrival there
(setup side); and the shortest path to a cpu.* register (hold side:
g_sdram.u_sdram.rdata only feeds the 68000-bus side, compiled out with
BUS_RAM = 0). Max-corner delays throughout, as check_timing.py uses.
check_timing.py applies the limits (step 24).

Usage: sdram_pins.py design.sdf [design.sdf ...]
"""
import os, re, sys

PIN = re.compile(r'sdram_dq\[(\d+)\]\$tr_io/O$')


def pin_paths(edges, setup, clkpin):
    """{pin: (longest ps, its register, shortest-to-cpu ps, its register)}"""
    res = {}
    for s in edges:
        m = PIN.match(s)
        if not m:
            continue
        hi, lo, frontier = {s: 0.0}, {s: 0.0}, [s]
        for _ in range(64):              # the paths are a few cells long
            nxt = []
            for n in frontier:
                for b, d in edges.get(n, ()):
                    moved = False
                    if hi[n] + d > hi.get(b, -1.0):
                        hi[b] = hi[n] + d; moved = True
                    if lo[n] + d < lo.get(b, 1e18):
                        lo[b] = lo[n] + d; moved = True
                    if moved:
                        nxt.append(b)
            frontier = nxt
            if not frontier:
                break
        ends = [n for n in hi if n in setup]
        if not ends:
            continue
        cap = lambda n: clkpin.get(setup[n][0], 0.0)
        lng = max(ends, key=lambda n: hi[n] + setup[n][1] - cap(n))
        cpu = [n for n in ends if setup[n][0].startswith('cpu.')] or ends
        sht = min(cpu, key=lambda n: lo[n] - cap(n))
        res[int(m.group(1))] = (hi[lng] + setup[lng][1] - cap(lng), setup[lng][0],
                                lo[sht] - cap(sht), setup[sht][0])
    return res


if __name__ == '__main__':
    here = os.path.dirname(os.path.abspath(__file__))
    src = open(os.path.join(here, 'check_timing.py')).read().split('# ---- classify')[0]
    for sdf in sys.argv[1:]:
        g = {}
        sys.argv = ['check_timing.py', sdf]
        exec(compile(src, 'check_timing.py', 'exec'), g)      # its SDF parser only
        res = pin_paths(g['edges'], g['setup'], g['clkpin_delay'])
        v = [res[k][0] / 1000 for k in sorted(res)]
        wl = max(res, key=lambda k: res[k][0])
        ws = min(res, key=lambda k: res[k][2])
        print('%s\n  %d pins; longest: mean %.2f ns, worst %.2f ns (pin %d -> %s);'
              ' shortest to cpu.*: %.2f ns (pin %d -> %s)'
              % (sdf, len(res), sum(v) / len(v), max(v), wl, res[wl][1],
                 res[ws][2] / 1000, ws, res[ws][3]))
        print('  longest per pin: ' + ' '.join('%d:%.2f' % (k, res[k][0] / 1000) for k in sorted(res)))
