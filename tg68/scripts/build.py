#!/usr/bin/env python3
"""Base64 TG68 (68020) bitstream build -- open-source flow, any OS.

    python scripts/build.py [min|fastmem|full] [--seed N] [--seeds N]

  min      CPU + motherboard only (Chip RAM, Kickstart).   Start here.
  fastmem  + SDRAM fast RAM: Zorro II and 16 MB at $08000000
  full     + SD card (sfsd.device)

Needs yosys, nextpnr-ecp5 and ecppack on PATH -- all three are in
oss-cad-suite (https://github.com/YosysHQ/oss-cad-suite-build). Without
plain yosys / nextpnr-ecp5 on PATH it uses the pip packages' yowasp-yosys /
yowasp-nextpnr-ecp5 instead (scripts/setup_cloud.sh installs those). Set the
environment variables YOSYS / NEXTPNR / ECPPACK to override either.

--seed S --seeds N places and routes seeds S..S+N-1, --jobs at a time
(default: up to 4, one per CPU), each in build/<cfg>/seed<S>/ (config,
nextpnr.log, report.json, timing.txt; its .sdf is deleted unless it is the
best seed or --keep-sdf is given). It runs them all (--first-pass: stop
starting new seeds once one has passed), prints a table of every seed's
worst slacks (also written to build/<cfg>/seeds.txt), and packs the PASS
seed with the largest worst-1T slack, scored at 14x and 16x as well.

Output: build/<cfg>/base64_tg68_<cfg>.bit (plain) and _fast.bit
(--compress --freq 38.8), from the best seed, with yosys.log,
utilisation.txt and seeds.txt alongside. If no seed passes, nothing is
packed and the exit status is 2.

--x16 (frozen at step 14b, no longer shipped) runs its seeds one at a time
in build/<cfg>_x16/ as before: it can never pass, so the last one is packed.
"""
import argparse, concurrent.futures, os, re, shutil, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CFGS = {'min': (0, 0), 'fastmem': (1, 0), 'full': (1, 1)}

ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
ap.add_argument('cfg', nargs='?', default='min', choices=CFGS)
ap.add_argument('--seed', type=int, default=1)
ap.add_argument('--seeds', type=int, default=8, help='place and route this many seeds, from --seed on')
ap.add_argument('--skip-synth', action='store_true', help='reuse an existing yosys netlist')
ap.add_argument('--jobs', type=int, default=max(1, min(4, os.cpu_count() or 1)),
                help='seeds placed and routed at the same time (default: up to 4)')
ap.add_argument('--first-pass', action='store_true',
                help='stop starting new seeds once one has passed timing')
ap.add_argument('--keep-sdf', action='store_true',
                help="keep every seed's .sdf (23 MB each), not only the best one's")
ap.add_argument('--x16', action='store_true',
                help='EXPERIMENTAL: for a board whose ICS570B is rewired from x12 to x16 '
                     '(113.5 MHz). Defines TG68_X16, output in build/<cfg>_x16. Overclocked: '
                     'check_timing at 113.6 MHz is expected to fail, see README "16x clock"')
a = ap.parse_args()
if a.x16 and '--seeds' not in sys.argv:
    a.seeds = 1   # it never passes at 113.6 MHz, so a search would run every seed

def find_tool(var, *candidates):
    """$var if set, else the first candidate found on PATH, else the first
    candidate (run() then reports it as missing)."""
    if os.environ.get(var):
        return os.environ[var]
    for c in candidates:
        if shutil.which(c):
            return c
    return candidates[0]

YOSYS = find_tool('YOSYS', 'yosys', 'yowasp-yosys')
NEXTPNR = find_tool('NEXTPNR', 'nextpnr-ecp5', 'yowasp-nextpnr-ecp5')
ECPPACK = os.environ.get('ECPPACK', 'ecppack')
fm, sd = CFGS[a.cfg]
name = a.cfg + ('_x16' if a.x16 else '')
out = os.path.join(ROOT, 'build', name)
os.makedirs(out, exist_ok=True)
for f in ('turbomem.mem', 'sfsd.mem'):        # $readmemh looks in the cwd
    shutil.copy(os.path.join(ROOT, 'rtl', 'base64_fx68k', f), out)

def run(cmd):
    print('  $ ' + ' '.join(cmd[:3]) + (' ...' if len(cmd) > 3 else ''), flush=True)
    try:
        r = subprocess.run(cmd, cwd=out)
    except FileNotFoundError:
        sys.exit('%s not found on PATH -- install oss-cad-suite or run '
                 'scripts/setup_cloud.sh (see the docstring in this file)' % cmd[0])
    if r.returncode != 0:
        sys.exit('%s failed (exit %d) -- see the log in %s' % (cmd[0], r.returncode, out))

R = lambda *p: os.path.join(ROOT, 'rtl', *p).replace('\\', '/')
srcs_sv = [R('base64_tg68', 'base64_tg68_top.sv')]
core = 'tg68_020_b0.v'
srcs_v = [R('base64_tg68', 'tg68_bus.v'), R('base64_tg68', 'clkgen.v'), R('tg68', core)] + \
         [R('base64_fx68k', f + '.v') for f in
          ('autoconfig_zii', 'fastmem_zii', 'turbomem_zii', 'sd_subsystem', 'sdcard',
           'sdram_ctrl', 'fifo', 'shifter', 'rx_cpu_buf', 'tx_cpu_buf')]

if not a.skip_synth:
    print('== yosys  (%s: ENABLE_FASTMEM=%d ENABLE_SD=%d)' % (a.cfg, fm, sd))
    # --x16: every 16x change is under `ifdef TG68_X16, so without it yosys
    # reads exactly the 12x text (and the 12x bitstreams stay reproducible)
    dfl = '-DTG68_X16 ' if a.x16 else ''
    script = '\n'.join(['read_verilog %s-sv ' % dfl + f for f in srcs_sv] +
                       ['read_verilog %s' % dfl + f for f in srcs_v] + [
        'read_verilog -lib +/ecp5/cells_bb.v',   # BB: the SD card input pins
        'chparam -set ENABLE_FASTMEM %d -set ENABLE_SD %d base64_tg68_top' % (fm, sd),
        # Keep the TG68 kernel and ALU as separate modules through
        # synthesis. Flattened, yosys maps the GHDL netlist to ~18k LUTs and
        # nextpnr cannot route it; kept apart it is ~8k, which is what the
        # vendor tools give. Flatten afterwards, at cell level, for nextpnr.
        'hierarchy -top base64_tg68_top',
        'setattr -mod -set keep_hierarchy 1 tg68k*',
        'synth_ecp5 -abc9 -top base64_tg68_top',
        'setattr -mod -unset keep_hierarchy tg68k*',
        'flatten',
        'opt_clean -purge',
        # yosys >= 0.39 leaves $scopeinfo cells after flatten; older
        # nextpnr builds reject them, newer ones ignore them.
        'delete t:$scopeinfo',
        'write_json base64_tg68.json',
        'tee -o utilisation.txt stat'])
    open(os.path.join(out, 'synth.ys'), 'w').write(script + '\n')
    run([YOSYS, '-q', '-l', 'yosys.log', '-s', 'synth.ys'])

    # A bidirectional pin tied to a constant means a tristate was lost (yosys
    # turns a constant 1'bz into a 0 driver): the FPGA would fight whatever
    # drives that pin. This is how the SD card's MISO went dead in the first
    # TG68 builds. Refuse to go on.
    #
    # One exception: the SD card's MOSI (sd_cmd) and chip select (sd_d[3]) are
    # real outputs, driven by the SD block, so with ENABLE_SD=0 they are
    # constant on purpose (MOSI low, card deselected). Only those two bits,
    # only at those values, and only in a config without the SD block.
    # Every other inout bit must be driven by logic or a BB buffer.
    import json
    top = json.load(open(os.path.join(out, 'base64_tg68.json')))['modules']['base64_tg68_top']
    tied_ok = {} if sd else {('sd_cmd', 0): '0', ('sd_d', 3): '1'}
    lost = ['%s[%d]=%s' % (p, i, b) for p, v in top['ports'].items() if v['direction'] == 'inout'
            for i, b in enumerate(v['bits'])
            if isinstance(b, str) and tied_ok.get((p, i)) != b]
    if lost:
        sys.exit('ERROR: inout pins tied to constants (tristate lost) in the %s config: ' % a.cfg
                 + ', '.join(lost))

lpf = os.path.join(ROOT, 'constraints', 'base64_tg68.lpf')
CHECK = os.path.join(ROOT, 'scripts', 'check_timing.py')

def nextpnr_cmd(json, seed, log):
    # --timing-allow-fail: nextpnr cannot be told the TG68 kernel is
    # multicycle and always flags it. check_timing.py is the real check.
    # (nextpnr's target frequency makes no difference to the result in this
    # flow: 12, 24 and 86 MHz gave byte-identical routed designs.)
    return [NEXTPNR, '--25k', '--package', 'CABGA256', '--speed', '6',
            '--json', json, '--lpf', lpf,
            '--textcfg', 'base64_tg68.config', '--sdf', 'base64_tg68.sdf',
            '--report', 'report.json', '--timing-allow-fail',
            '--router', 'router2',
            # static placer + router2 gave the best results here. The static
            # placer needs nextpnr >= 0.7 (any current oss-cad-suite); set
            # PLACER=heap for an older nextpnr.
            '--placer', os.environ.get('PLACER', 'static'),
            '--seed', str(seed), '-l', log]

ROW = re.compile(r'^(\S.*?)\s+([1234])T\s+([\d.]+)\s+(-?[\d.]+)\s+\d+', re.M)

def summary(timing_text, freq=86.0):
    """worst 1T slack, worst multicycle slack, worst failing class (or None),
    worst delay/budget ratio, from a check_timing.py report"""
    T = 1000.0 / freq
    rows = [(c.strip(), int(n), float(sl)) for c, n, d, sl in ROW.findall(timing_text)]
    if not rows:
        return None
    w1 = min([sl for c, n, sl in rows if n == 1] or [0.0])
    wm = min([sl for c, n, sl in rows if n != 1] or [0.0])
    bad = min(rows, key=lambda r: r[2])
    ratio = max((n * T - sl) / (n * T) for c, n, sl in rows)
    return w1, wm, (bad if bad[2] < 0 else None), ratio

def ecppack(config, bit, extra):
    run([ECPPACK] + extra + [config, bit])

if a.x16:
    # The board-mod build (frozen at step 14b): one seed at a time in `out`,
    # as before; it never passes at 113.6 MHz, so the last seed is packed.
    for seed in range(a.seed, a.seed + a.seeds):
        print('== nextpnr  (seed %d)' % seed)
        run(nextpnr_cmd('base64_tg68.json', seed, 'nextpnr.log'))
        print('== timing check')
        r = subprocess.run([sys.executable, CHECK, 'base64_tg68.sdf', '--freq', '113.6'],
                           cwd=out, capture_output=True, text=True)
        open(os.path.join(out, 'timing.txt'), 'w').write(r.stdout)
        print('\n'.join(l for l in r.stdout.splitlines()[:12]))
        if r.returncode == 0:
            break
    print('== ecppack')
    bit = 'base64_tg68_%s.bit' % name
    ecppack('base64_tg68.config', bit, os.environ.get('ECPPACK_OPTS', '').split())
    print('== done: %s' % os.path.join(out, bit))
    print('NOTE: x16 is an overclocked build. check_timing at 113.6 MHz fails by design;\n'
          '      the worst slacks in timing.txt say how far past the worst-case model it runs.')
    sys.exit(0)

json_path = os.path.join(out, 'base64_tg68.json')
if not os.path.exists(json_path):
    sys.exit('no netlist at %s -- run without --skip-synth first' % json_path)

def one_seed(seed):
    """place, route and check one seed in out/seed<N>; returns (seed, passed)"""
    d = os.path.join(out, 'seed%d' % seed)
    os.makedirs(d, exist_ok=True)
    for f in ('base64_tg68.sdf', 'timing.txt'):
        if os.path.exists(os.path.join(d, f)):
            os.remove(os.path.join(d, f))
    with open(os.path.join(d, 'nextpnr.out'), 'w') as o:
        try:
            r = subprocess.run(nextpnr_cmd(json_path, seed, 'nextpnr.log'), cwd=d,
                               stdout=o, stderr=subprocess.STDOUT)
        except FileNotFoundError:
            return seed, None, '%s not found on PATH' % NEXTPNR
    if r.returncode != 0:
        return seed, None, 'nextpnr failed (exit %d), see %s' % (r.returncode, d)
    t = subprocess.run([sys.executable, CHECK, 'base64_tg68.sdf', '--paths', '6'],
                       cwd=d, capture_output=True, text=True)
    open(os.path.join(d, 'timing.txt'), 'w').write(t.stdout)
    return seed, t.returncode == 0, None

seeds = list(range(a.seed, a.seed + a.seeds))
jobs = max(1, min(a.jobs, len(seeds)))
print('== nextpnr  seeds %d-%d, %d at a time (each in %s)'
      % (seeds[0], seeds[-1], jobs, os.path.join(out, 'seed<N>')), flush=True)
results = {}
todo = list(seeds)
with concurrent.futures.ThreadPoolExecutor(max_workers=jobs) as ex:
    running = set()
    while todo or running:
        while todo and len(running) < jobs and not (a.first_pass and any(v[0] for v in results.values())):
            running.add(ex.submit(one_seed, todo.pop(0)))
        if not running:
            break
        done, running = concurrent.futures.wait(running, return_when=concurrent.futures.FIRST_COMPLETED)
        for f in done:
            seed, ok, err = f.result()
            results[seed] = (ok, err)
            print('   seed %d: %s' % (seed, err or ('PASS' if ok else 'fail')), flush=True)

# ---- the table ---------------------------------------------------------------
lines = ['seed  result  worst 1T  worst multicycle  worst failing class']
best = None
for seed in sorted(results):
    ok, err = results[seed]
    if err:
        lines.append('%4d  ERROR   %s' % (seed, err))
        continue
    sm = summary(open(os.path.join(out, 'seed%d' % seed, 'timing.txt')).read())
    if sm is None:
        lines.append('%4d  ERROR   timing.txt has no class table' % seed)
        continue
    w1, wm, bad, _ = sm
    lines.append('%4d  %-6s  %+8.2f  %+16.2f  %s' % (seed, 'PASS' if ok else 'FAIL', w1, wm,
                 '%s %+.2f' % (bad[0], bad[2]) if bad else ''))
    if ok and (best is None or w1 > best[1]):
        best = (seed, w1)
table = '\n'.join(lines)
print('== seeds\n' + table)
open(os.path.join(out, 'seeds.txt'), 'w').write(table + '\n')

# free disk: an .sdf is ~23 MB
for seed in results:
    sdf = os.path.join(out, 'seed%d' % seed, 'base64_tg68.sdf')
    if os.path.exists(sdf) and not a.keep_sdf and not (best and seed == best[0]):
        os.remove(sdf)

if best is None:
    print('WARNING: timing check FAILED on every seed tried -- nothing packed; see seeds.txt')
    sys.exit(2)

seed = best[0]
d = os.path.join(out, 'seed%d' % seed)
print('== best seed: %d (worst 1T slack %+.2f ns)' % (seed, best[1]))
# 14x and 16x: the same build scored by the worst delay/budget ratio (it
# cannot pass the worst-case model there; see README "Timing")
for freq, tag in ((99.32, '14x'), (113.51, '16x')):
    t = subprocess.run([sys.executable, CHECK, 'base64_tg68.sdf', '--freq', str(freq), '--paths', '6'],
                       cwd=d, capture_output=True, text=True)
    open(os.path.join(d, 'timing_at%s.txt' % tag), 'w').write(t.stdout)
    sm = summary(t.stdout, freq)
    print('   at %s (%.2f MHz): needs the chip %.3fx faster than the worst-case model' % (tag, freq, sm[3]))

print('== ecppack')
# Plain pack, as in Muse Lab's own iCESugar-Pro examples. The Diamond build's
# SYSCONFIG (compressed, dual SPI, 62 MHz MCCLK) was tried here and the FPGA
# does not configure from flash with it -- tested on hardware: LEDs stay off.
# The _fast file (--compress --freq 38.8, single SPI) loads faster and works.
cfg = os.path.join(d, 'base64_tg68.config')
bit = os.path.join(out, 'base64_tg68_%s.bit' % name)
ecppack(cfg, bit, os.environ.get('ECPPACK_OPTS', '').split())
fast = os.path.join(out, 'base64_tg68_%s_fast.bit' % name)
ecppack(cfg, fast, ['--compress', '--freq', '38.8'])
print('== done: %s\n         %s\n   (seed %d; timing reports in %s)' % (bit, fast, seed, d))
