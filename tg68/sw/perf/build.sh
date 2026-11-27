#!/bin/sh
# Build the perf executable (Linux; needs GNU binutils for m68k:
# Debian/Ubuntu package binutils-m68k-linux-gnu). Uses ../maprom/mkhunk.py.
#   sh build.sh          perf
#   sh build.sh test     also perf_test / perf_testrst / perf_testnone: a
#                        fake board in RAM, for amitools' vamos (running;
#                        frozen by a reset; gateware without counters)
set -e
cd "$(dirname "$0")"
one() {   # one <output> [--defsym ...]
    out=$1; shift
    m68k-linux-gnu-as -m68000 "$@" -o $out.o perf.s
    m68k-linux-gnu-ld -Ttext=0 -e _start -o $out.elf $out.o
    m68k-linux-gnu-objcopy -O binary $out.elf $out.bin
    if m68k-linux-gnu-objdump -r $out.o | grep -q "R_68K_32"; then
        echo "absolute reference in perf.s -- needs PC-relative addressing" >&2; exit 1
    fi
    python3 ../maprom/mkhunk.py $out.bin $out
    rm -f $out.o $out.elf $out.bin
}
one perf
if [ "$1" = test ]; then
    one perf_test --defsym TEST=1
    one perf_testrst --defsym TEST=1 --defsym TESTRST=1
    one perf_testnone --defsym TEST=1 --defsym TESTNONE=1
fi
