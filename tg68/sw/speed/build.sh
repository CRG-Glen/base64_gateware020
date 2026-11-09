#!/bin/sh
# Build the speed executable (Linux; needs GNU binutils for m68k:
# Debian/Ubuntu package binutils-m68k-linux-gnu). Uses ../maprom/mkhunk.py.
#   sh build.sh          speed
#   sh build.sh test     also speed_test / speed_testfix: a fake board in RAM,
#                        for amitools' vamos (normal / fixed 16x gateware)
set -e
cd "$(dirname "$0")"
one() {   # one <output> [--defsym ...]
    out=$1; shift
    m68k-linux-gnu-as -m68000 "$@" -o $out.o speed.s
    m68k-linux-gnu-ld -Ttext=0 -e _start -o $out.elf $out.o
    m68k-linux-gnu-objcopy -O binary $out.elf $out.bin
    if m68k-linux-gnu-objdump -r $out.o | grep -q "R_68K_32"; then
        echo "absolute reference in speed.s -- needs PC-relative addressing" >&2; exit 1
    fi
    python3 ../maprom/mkhunk.py $out.bin $out
    rm -f $out.o $out.elf $out.bin
}
one speed
if [ "$1" = test ]; then
    one speed_test --defsym TEST=1
    one speed_testfix --defsym TEST=1 --defsym TESTFIX=1
fi
