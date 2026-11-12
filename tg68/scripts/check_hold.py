#!/usr/bin/env python3
"""Hold check between registers on different global clock buffers of one clock.
Shortest register-to-register delay (min corner) for each direction, against
the buffer skew (max corner of the late buffer minus min corner of the early)."""
import re, sys, collections, heapq
txt = open(sys.argv[1]).read()
unesc = lambda s: re.sub(r'\\(.)', r'\1', s)
def trip(tok):
    m = re.findall(r'\(([-\d.]*):([-\d.]*):([-\d.]*)\)', tok)
    lo = min([float(x[0]) for x in m if x[0]] or [0.0]); hi = max([float(x[2]) for x in m if x[2]] or [0.0])
    return lo, hi
tok = r'((?:\\.|[^\s()\\])+)'
ic_re = re.compile(r'\(INTERCONNECT\s+' + tok + r'\s+' + tok + r'\s+(\([^)]*\))')
io_re = re.compile(r'\(IOPATH\s+(\((?:posedge|negedge)\s+' + tok + r'\)|' + tok + r')\s+' + tok + r'\s+(\([^)]*\))')
hd_re = re.compile(r'\((HOLD|SETUPHOLD)\s+(?:\((?:posedge|negedge)\s+' + tok + r'\)|' + tok + r')\s+\((?:posedge|negedge)\s+' + tok + r'\)\s+(\([^)]*\))(\s+\([^)]*\))?')
CLOCK_PINS = {'CLK','CLKA','CLKB','CLK0','CLK1','SCLK','ECLK','WCK','RCLK','WCLK'}
edges = collections.defaultdict(list); clk2q = {}; clk_src = {}; buf_in = {}; dcca = set(); clkmin = {}; clkmax = {}; dpins = collections.defaultdict(set)
for chunk in re.split(r'\n\s*\(CELL\b', txt)[1:]:
    m = re.match(r'\s*\(CELLTYPE\s+"([^"]*)"\)\s*\(INSTANCE\s*((?:\\.|[^)\\])*)\)', chunk)
    if not m: continue
    ctype, inst, body = m.group(1), unesc(m.group(2).strip()), chunk[m.end():]
    if ctype == 'DCCA': dcca.add(inst)
    if inst == '':
        for a, b, d in ic_re.findall(body):
            a, b = unesc(a), unesc(b); lo, hi = trip(d)
            edges[a].append((b, lo))
            if b.endswith('/CLK'): clk_src[b[:-4]] = a.rsplit('/',1)[0]; clkmin[b[:-4]] = lo; clkmax[b[:-4]] = hi
            if b.endswith('/CLKI'): buf_in[b[:-5]] = (lo, hi)
        continue
    for m2 in io_re.finditer(body):
        full, clkp, inp, outp, d = m2.groups(); outp = unesc(outp)
        if not clkp and unesc(inp) in CLOCK_PINS: clkp = unesc(inp)
        lo, hi = trip(d)
        if clkp: clk2q[inst + '/' + outp] = (inst, lo)
        else: edges[inst + '/' + unesc(inp)].append((inst + '/' + outp, lo))
    for pin in re.findall(r'\((?:SETUP|HOLD|SETUPHOLD)\s+(?:\((?:posedge|negedge)\s+' + tok + r'\)|' + tok + r')', body):
        dpins[inst].add(unesc(pin[0] or pin[1]))
bufs = sorted(b for b in set(clk_src.values()) if b in dcca and b in buf_in)
print('buffers:', {b.split('.')[-1]: buf_in[b] for b in bufs})
ends = {inst + '/' + p: inst for inst, ps in dpins.items() for p in ps}
for launch in bufs:
    for cap in bufs:
        if launch == cap: continue
        # skew seen by hold: capture clock late (max) vs launch clock early (min)
        skew = buf_in[cap][1] - buf_in[launch][0]
        dist = {}; pq = []
        for node, (inst, d) in clk2q.items():
            if clk_src.get(inst) == launch:
                dist[node] = d; heapq.heappush(pq, (d, node, inst))
        best = []
        done = set()
        while pq:
            d, n, s = heapq.heappop(pq)
            if n in done: continue
            done.add(n)
            if n in ends and clk_src.get(ends[n]) == cap:
                best.append((d, s, n))
                if len(best) >= 3: break
                continue
            for b, w in edges.get(n, ()):
                if b not in done: heapq.heappush(pq, (d + w, b, s))
        print('%s -> %s: skew %.2f ns (capture late); shortest paths:' % (launch.split('.')[-1], cap.split('.')[-1], skew/1000))
        for d, s, n in best: print('   %.2f ns  %s -> %s   hold margin %.2f ns' % (d/1000, s[-50:], n[-50:], (d - skew)/1000))
