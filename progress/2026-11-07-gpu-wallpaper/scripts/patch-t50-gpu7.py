#!/usr/bin/env python3
"""GPU clients in a t50 kernel: 7 slots instead of 4, a 3 GiB GPU aperture instead of 2, and three poster processes in the sandbox grant.
Slot bytes keep their place: 0-3 as before, 5-7 in the padding after kernel_client (byte 4), so slot 4 is never handed out. Windows 0-3 are unchanged;
5-7 are 256 MiB each above 2 GiB, which is why the page tables grow: 1 L1 + 3 L2 + 1536 L3 = 1540 pages. Every old word is checked first.
Usage: patch-t50-gpu7.py <in kernel> <out kernel>"""
import struct
import sys

CAVE = 0xfffffff00bdf1130  # _copyio_test; the screenshot provider uses its first 1024 bytes
TABLE = CAVE + 0x400
GRANT = TABLE + 0x80
OLD_TABLE = 0xfffffff0070450b0
OLD_GRANT = 0xfffffff0071433b6
OLD_LIST = b'backboardd,iconservicesagent,WidgetRenderer_Default,PosterBoard\0'
NEW_LIST = OLD_LIST[:-1] + b',AegirPoster,WeatherPoster,PhotosPosterProvider\0'
PICK = 0xfffffff00c00ec58
LIMIT = 0xfffffff00c00ec9c

k = bytearray(open(sys.argv[1], 'rb').read())
segs, at = [], 32
for _ in range(struct.unpack_from('<I', k, 16)[0]):
    cmd, size = struct.unpack_from('<II', k, at)
    if cmd == 0x19:
        vm, _vs, off, fs = struct.unpack_from('<QQQQ', k, at + 24)
        segs.append((vm, fs, off))
    at += size


def foff(va):
    for vm, fs, off in segs:
        if vm <= va < vm + fs:
            return off + va - vm
    raise SystemExit(f'{va:#x} not in the file')


def word(va):
    return struct.unpack_from('<I', k, foff(va))[0]


def put(va, old, new):
    if word(va) != old:
        raise SystemExit(f'{va:#x}: found {word(va):#010x}, expected {old:#010x}')
    struct.pack_into('<I', k, foff(va), new)


def adrp(pc, target, rd):
    d = (target >> 12) - (pc >> 12)
    if not -(1 << 20) <= d < (1 << 20):
        raise SystemExit('adrp out of range')
    return 0x90000000 | ((d & 3) << 29) | (((d >> 2) & 0x7ffff) << 5) | rd


def add_lo12(target, rd):
    return 0x91000000 | ((target & 0xfff) << 10) | (rd << 5) | rd


# --- slot choice in mount: first free of 1,2,3,5,6,7; w24 is 8 when none is free.
for va, want in ((PICK + 4, 0x397c0509), (PICK + 0x1c, 0x397c0929), (PICK + 0x34, 0x397c0d08), (LIMIT, 0x71000f1f)):
    if word(va) != want:
        raise SystemExit(f'slot choice not as expected at {va:#x}: {word(va):#010x}')
code = [
    word(PICK),   # adrp x8, the page of the slot bytes (same pc)
    0x913c0108,   # add x8, x8, #0xf00
    0x52800038,   # mov w24, #1
    0x7100131f,   # loop: cmp w24, #4
    0x54000060,   # b.eq next (+3)
    0x38784909,   # ldrb w9, [x8, w24, uxtw]
    0x36000000 | (((LIMIT - (PICK + 6 * 4)) // 4) << 5) | 9,  # tbz w9, #0, limit
    0x11000718,   # next: add w24, w24, #1
    0x7100231f,   # cmp w24, #8
    0x54ffff43,   # b.lo loop (-6)
]
code += [0xd503201f] * (17 - len(code))
for i, new in enumerate(code):
    struct.pack_into('<I', k, foff(PICK + i * 4), new)
put(LIMIT, 0x71000f1f, 0x71001f1f)  # cmp w24, #7
put(0xfffffff00c00f224, 0x71000d1f, 0x71001d1f)  # close: cmp w8, #7

# --- windows
windows = [struct.unpack_from('<QQ', k, foff(OLD_TABLE + i * 16)) for i in range(4)]
if windows[3] != (0x75552000, 0xaaa9000):
    raise SystemExit(f'window table unexpected: {windows}')
windows += [(0, 0), (0x80000000, 0x10000000), (0x90000000, 0x10000000), (0xa0000000, 0x10000000)]
for i, (start, size) in enumerate(windows):
    struct.pack_into('<QQ', k, foff(TABLE + i * 16), start, size)
SITE = 0xfffffff00c00ed98
put(SITE, adrp(SITE, OLD_TABLE, 8), adrp(SITE, TABLE, 8))
put(SITE + 4, add_lo12(OLD_TABLE, 8), add_lo12(TABLE, 8))

# --- grant list
if bytes(k[foff(OLD_GRANT):foff(OLD_GRANT) + len(OLD_LIST)]) != OLD_LIST:
    raise SystemExit('grant list unexpected')
k[foff(GRANT):foff(GRANT) + len(NEW_LIST)] = NEW_LIST
SITE = 0xfffffff00c045338
put(SITE, adrp(SITE, OLD_GRANT, 2), adrp(SITE, GRANT, 2))
put(SITE + 4, add_lo12(OLD_GRANT, 2), add_lo12(GRANT, 2))

# --- 3 GiB aperture: page tables, leaf budget and its limit, aperture bytes
put(0xfffffff00c00c2d4, 0x914fc341, 0x9157c741)  # table bytes 0x403000 -> 0x604000
put(0xfffffff00c00c2d8, 0x914fc344, 0x9157c744)  # and their allocation budget
put(0xfffffff00c00c3d0, 0x52a00105, 0x52a00185)  # leaf budget 0x80000 -> 0xc0000
put(0xfffffff00c0123e4, 0xd14200a9, 0xd14300a9)  # prepare's limit on it
APERTURE = int(sys.argv[3], 16)
put(APERTURE, 0x52b00004, 0x52b80004)  # w4 = 0x80000000 -> 0xc0000000
open(sys.argv[2], 'wb').write(k)
print('patched', hex(TABLE), hex(GRANT), len(NEW_LIST))
