#!/usr/bin/env python3
"""Wrap a flat, position-independent 68k binary as a one-hunk AmigaOS
executable: HUNK_HEADER, HUNK_CODE, HUNK_END. No relocations, so the code
must not contain absolute references to itself (maprom.s uses PC-relative
addressing throughout).

    mkhunk.py input.bin output_executable
"""
import struct, sys
data = open(sys.argv[1], 'rb').read()
data += b'\0' * (-len(data) % 4)
n = len(data) // 4
hunk = struct.pack('>IIIII', 0x3F3, 0, 1, 0, 0) + struct.pack('>I', n)
hunk += struct.pack('>II', 0x3E9, n) + data + struct.pack('>I', 0x3F2)
open(sys.argv[2], 'wb').write(hunk)
print('%s: %d bytes of code, %d bytes total' % (sys.argv[2], len(data), len(hunk)))
