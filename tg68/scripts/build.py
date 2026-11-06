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

--seeds N tries placement seeds 1..N and keeps the first that passes the
multicycle timing check (scripts/check_timing.py).

Output: build/<cfg>/base64_tg68_<cfg>.bit, with yosys.log, nextpnr.log,
utilisation.txt and timing.txt alongside it.
"""
import argparse, os, shutil, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CFGS = {'min': (0, 0), 'fastmem': (1, 0), 'full': (1, 1)}

ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
ap.add_argument('cfg', nargs='?', default='min', choices=CFGS)
ap.add_argument('--seed', type=int, default=1)
ap.add_argument('--seeds', type=int, default=8, help='try up to this many seeds (stops at the first that passes)')
ap.add_argument('--skip-synth', action='store_true', help='reuse an existing yosys netlist')
a = ap.parse_args()

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
name = a.cfg
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
srcs_v = [R('base64_tg68', 'tg68_bus.v'), R('tg68', core)] + \
         [R('base64_fx68k', f + '.v') for f in
          ('autoconfig_zii', 'fastmem_zii', 'turbomem_zii', 'sd_subsystem', 'sdcard',
           'sdram_ctrl', 'fifo', 'shifter', 'rx_cpu_buf', 'tx_cpu_buf')]

if not a.skip_synth:
    print('== yosys  (%s: ENABLE_FASTMEM=%d ENABLE_SD=%d)' % (a.cfg, fm, sd))
    script = '\n'.join(['read_verilog -sv ' + f for f in srcs_sv] +
                       ['read_verilog ' + f for f in srcs_v] + [
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
for seed in range(a.seed, a.seed + a.seeds):
    print('== nextpnr  (seed %d)' % seed)
    # --timing-allow-fail: nextpnr cannot be told the TG68 kernel is
    # multicycle and always flags it. check_timing.py is the real check.
    run([NEXTPNR, '--25k', '--package', 'CABGA256', '--speed', '6',
         '--json', 'base64_tg68.json', '--lpf', lpf,
         '--textcfg', 'base64_tg68.config', '--sdf', 'base64_tg68.sdf',
         '--report', 'report.json', '--timing-allow-fail',
         '--router', 'router2',
         # static placer + router2 gave the best results here. The static
         # placer needs nextpnr >= 0.7 (any current oss-cad-suite); set
         # PLACER=heap for an older nextpnr.
         '--placer', os.environ.get('PLACER', 'static'),
         '--seed', str(seed), '-l', 'nextpnr.log'])
    print('== timing check')
    r = subprocess.run([sys.executable, os.path.join(ROOT, 'scripts', 'check_timing.py'),
                        'base64_tg68.sdf'], cwd=out, capture_output=True, text=True)
    open(os.path.join(out, 'timing.txt'), 'w').write(r.stdout)
    print('\n'.join(l for l in r.stdout.splitlines()[:12]))
    if r.returncode == 0 or seed == a.seed + a.seeds - 1:
        break
    print('   timing failed with seed %d, trying the next one' % seed)

print('== ecppack')
# Plain pack, as in Muse Lab's own iCESugar-Pro examples. The Diamond build's
# SYSCONFIG (compressed, dual SPI, 62 MHz MCCLK) was tried here and the FPGA
# does not configure from flash with it -- tested on hardware: LEDs stay off.
# ECPPACK_OPTS="--compress --freq 38.8" gives a faster-loading single-SPI
# image if you want to try it.
bit = 'base64_tg68_%s.bit' % name
run([ECPPACK] + os.environ.get('ECPPACK_OPTS', '').split() + ['base64_tg68.config', bit])
print('== done: %s' % os.path.join(out, bit))
if r.returncode != 0:
    print('WARNING: timing check FAILED on every seed tried -- see timing.txt')
    sys.exit(2)
