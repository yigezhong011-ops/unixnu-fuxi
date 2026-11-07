#!/usr/bin/env python3
# Installs touch-cave2 in a t50 kernel: writes the cave, points the GOP checkpoint at touch_entry and the parse_verb call at verb_hook. Every old word is checked.
import struct, sys
src, dst, cave_file = sys.argv[1:4]
cave, low, check, entry, site, verb, hook = (int(x, 16) for x in sys.argv[4:11])
k = bytearray(open(src, 'rb').read()); c = open(cave_file, 'rb').read()
if low != cave:
    raise SystemExit(f'lowest cave section {low:#x} is not the cave base {cave:#x}')
if not 0 < len(c) <= 8192:
    raise SystemExit(f'cave size {len(c)}')
at, segs = 32, []
for _ in range(struct.unpack_from('<I', k, 16)[0]):
    cmd, size = struct.unpack_from('<II', k, at)
    if cmd == 0x19:
        vm, _vs, off, fs = struct.unpack_from('<QQQQ', k, at + 24)
        segs.append((vm, fs, off, k[at + 8:at + 24].rstrip(b'\0').decode()))
    at += size
def seg(va):
    for s in segs:
        if s[0] <= va < s[0] + s[1]:
            return s
    raise SystemExit(f'{va:#x} not in the file')
def foff(va):
    s = seg(va)
    return s[2] + va - s[0]
def rel(op, frm, to):
    d = (to - frm) // 4
    if not -(1 << 25) <= d < (1 << 25):
        raise SystemExit(f'branch out of range {frm:#x} -> {to:#x}')
    return op | (d & 0x3ffffff)
if 'TEXT_EXEC' not in seg(cave)[3] or seg(cave) != seg(cave + len(c)):
    raise SystemExit('cave is not inside executable text')
if not cave <= entry < cave + len(c) or not cave <= hook < cave + len(c):
    raise SystemExit('entry or hook outside the cave')
# The area is the body of copyio_test, a self test nothing runs at boot; it holds 19620 bytes before the next symbol.
COPYIO_TEST, COPYIO_ROOM = 0xfffffff00bdf1130, 19620
if cave + len(c) > COPYIO_TEST + COPYIO_ROOM:
    raise SystemExit('cave runs past copyio_test')
old = struct.unpack_from('<I', k, foff(check))[0]
if old != 0xd65f03c0 and (old & 0xfc000000) != 0x14000000:
    raise SystemExit(f'checkpoint word {old:#x} is neither ret nor b')
if struct.unpack_from('<I', k, foff(site))[0] != rel(0x94000000, site, verb):
    raise SystemExit('call site is not bl parse_verb')
k[foff(cave):foff(cave) + len(c)] = c
struct.pack_into('<I', k, foff(check), rel(0x14000000, check, entry))
struct.pack_into('<I', k, foff(site), rel(0x94000000, site, hook))
open(dst, 'wb').write(k)
print('cave', hex(cave), 'size', len(c), 'entry', hex(entry), 'hook', hex(hook), 'checkpoint was', hex(old))
