#!/bin/sh
# Build the maprom executable (Linux; needs GNU binutils for m68k:
# Debian/Ubuntu package binutils-m68k-linux-gnu).
set -e
cd "$(dirname "$0")"
m68k-linux-gnu-as -m68000 -o maprom.o maprom.s
m68k-linux-gnu-ld -Ttext=0 -e _start -o maprom.elf maprom.o
m68k-linux-gnu-objcopy -O binary maprom.elf maprom.bin
# position independent? an absolute relocation would show up in the ELF
if m68k-linux-gnu-objdump -r maprom.o | grep -q "R_68K_32"; then
    echo "absolute reference in maprom.s -- needs PC-relative addressing" >&2; exit 1
fi
python3 mkhunk.py maprom.bin maprom
rm -f maprom.o maprom.elf maprom.bin
