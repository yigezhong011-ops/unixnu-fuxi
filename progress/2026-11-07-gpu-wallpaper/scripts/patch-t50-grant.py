#!/usr/bin/env python3
"""Add the gallery's poster processes to the sandbox grant of a gpu7 kernel. The list stays in its place in the copyio_test cave, well below the gesture code at +0x1000.
Usage: patch-t50-grant.py <in kernel> <out kernel>"""
import struct
import sys

GRANT = 0xfffffff00bdf1130 + 0x400 + 0x80
LIMIT = 0xfffffff00bdf1130 + 0x1000
OLD = b'backboardd,iconservicesagent,WidgetRenderer_Default,PosterBoard,AegirPoster,WeatherPoster,PhotosPosterProvider\0'
NEW = OLD[:-1] + b',KaleidoscopePoster,PridePosterExtension,HelloPosterExtension\0'
assert GRANT + len(NEW) < LIMIT
k = bytearray(open(sys.argv[1], 'rb').read())
at = None
pos = 32
for _ in range(struct.unpack_from('<I', k, 16)[0]):
    cmd, size = struct.unpack_from('<II', k, pos)
    if cmd == 0x19:
        vm, _vs, off, fs = struct.unpack_from('<QQQQ', k, pos + 24)
        if vm <= GRANT < vm + fs:
            at = off + GRANT - vm
    pos += size
if at is None or bytes(k[at:at + len(OLD)]) != OLD:
    raise SystemExit('grant list not as expected')
k[at:at + len(NEW)] = NEW
open(sys.argv[2], 'wb').write(k)
print('grant', len(OLD), '->', len(NEW), 'bytes at', hex(GRANT))
