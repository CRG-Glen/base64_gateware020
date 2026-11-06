#!/bin/sh
# Regenerate the TG68 Verilog from the TG68K.C VHDL.  Needs ghdl + yosys.
#   gen_tg68.sh [barrel 0|1] [bitfield 1|0] [dsp-multiplier 1|0]
set -e
cd "$(dirname "$0")/../rtl/tg68"
B=${1:-0}         # barrel shifter
BF=${2:-1}        # bitfield instructions
MH=${3:-1}        # hardware (DSP) multiplier
OUT=tg68_020_b$B
[ "$BF" = 1 ] || OUT=${OUT}_nobf
[ "$MH" = 1 ] || OUT=${OUT}_smul
OUT=$OUT.v
W=$(mktemp -d)
F="--std=08 -frelaxed -fsynopsys --workdir=$W"
ghdl -a $F TG68K_Pack.vhd TG68K_ALU.vhd TG68KdotC_Kernel.vhd tg68_020.vhd
ghdl --synth $F -gBARREL=$B -gBITFIELD=$BF -gMULHW=$MH --out=verilog tg68_020 > $W/raw.v 2> $W/ghdl.log
python3 -I ../../scripts/fix_latches.py $W/raw.v $OUT ${YOSYS:-yosys}
rm -rf $W
echo "wrote rtl/tg68/$OUT"
