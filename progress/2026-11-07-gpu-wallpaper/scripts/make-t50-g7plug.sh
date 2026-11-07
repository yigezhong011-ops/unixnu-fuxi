#!/bin/bash
# t50-auto-g7plug: gpu7 kernel plus gestures, with the 11-05 plugin files merged into the current addon.
# The wallpaper entries stay; only entries present in the plugin build are replaced. Temp boot only; writes no partition.
set -euo pipefail
export MTOOLS_SKIP_CHECK=1
E=/mnt/e/DSH-Fuxi; S=$E/dump/wsl; B=/root/fuxi/t50-gpu7; P=/root/fuxi/gpu-plugin-1105; W=/root/fuxi/t50-g7plug
rm -rf "$W"; mkdir -p "$W"; cd "$W"
cp "$B/vol.img" vol.img; cp "$B/kernel.macho" kernel.macho
mtype -i vol.img ::/EFI/UniXNU/Payloads/kernel.macho.gpuaddon > addon-cur.bin
mtype -i vol.img ::/EFI/UniXNU/Payloads/kernel.macho.trustcache > trust-cur.bin
python3 -I - addon-cur.bin "$P/gpuaddon.bin" addon-merged.bin <<'EOF'
import struct, sys, zlib
def pad8(n): return n + (-n % 8)
def parse(p):
    b = open(p, 'rb').read(); c = struct.unpack_from('<I', b, 8)[0]; at = 24; r = []
    for _ in range(c):
        nl, m, s, pk = struct.unpack_from('<IIQQ', b, at); at += 24
        n = b[at:at + nl - 1].decode(); at += pad8(nl)
        r.append([n, m, s, b[at:at + pk]]); at += pad8(pk)
    return r
cur, new = parse(sys.argv[1]), {e[0]: e for e in parse(sys.argv[2])}
names = {e[0] for e in cur}
missing = sorted(set(new) - names)
assert not missing, missing
out, swapped = [], 0
for e in cur:
    if '.filler' in e[0]:
        continue
    if e[0] in new and new[e[0]][3] != e[3]:
        swapped += 1
        print('swap', e[0], e[2], '->', new[e[0]][2])
        e = new[e[0]]
    # Same content, tighter stream: the addon cannot grow past the resident size.
    raw = zlib.decompress(e[3])
    assert len(raw) == e[2], e[0]
    if e[0].endswith('/J120-Dark.jpg'):
        # The plugin grew by about 2.9 KB and the addon cannot: give up a little dark-art quality.
        import io
        from PIL import Image
        im = Image.open(io.BytesIO(raw)); size = im.size
        for q in range(92, 30, -2):
            b = io.BytesIO(); im.convert('RGB').save(b, 'JPEG', quality=q, optimize=True); small = b.getvalue()
            if len(zlib.compress(small, 9)) <= len(e[3]) - 3300:
                break
        else:
            raise SystemExit('jpeg did not shrink enough')
        print('jpeg', size, 'quality', q, len(raw), '->', len(small))
        raw = small
        e = [e[0], e[1], len(raw), e[3]]
    co = zlib.compressobj(9, zlib.DEFLATED, 15, 9)
    packed = co.compress(raw) + co.flush()
    assert zlib.decompress(packed) == raw, e[0]
    if len(packed) < len(e[3]):
        print('recompress', e[0], len(e[3]), '->', len(packed))
        e = [e[0], e[1], e[2], packed]
    out.append(e)
body = b''
for n, m, s, pk in out:
    enc = n.encode() + b'\0'
    body += struct.pack('<IIQQ', len(enc), m, s, len(pk)) + enc + bytes(-len(enc) % 8) + pk + bytes(-len(pk) % 8)
open(sys.argv[3], 'wb').write(b'NGPUADD2' + struct.pack('<IIQ', len(out), 0, 24 + len(body)) + body)
print('entries', len(cur), '->', len(out), 'swapped', swapped, 'bytes', 24 + len(body))
EOF
python3 -I $S/fit-addon.py addon-cur.bin addon-merged.bin addon-fitted.bin
[ "$(stat -c %s addon-fitted.bin)" = "$(stat -c %s addon-cur.bin)" ]
python3 -I $S/patch-trustcache.py trust-cur.bin "$P/cdhashes.txt" trust-new.bin | tail -2
python3 -I $S/fat-inplace.py vol.img ::/EFI/UniXNU/Payloads/kernel.macho.gpuaddon addon-fitted.bin >/dev/null
python3 -I $S/fat-inplace.py vol.img ::/EFI/UniXNU/Payloads/kernel.macho.trustcache trust-new.bin >/dev/null
mtype -i vol.img ::/EFI/UniXNU/Payloads/kernel.macho.gpuaddon | cmp - addon-fitted.bin
mtype -i vol.img ::/EFI/UniXNU/Payloads/kernel.macho.trustcache | cmp - trust-new.bin
tr -d '\r' < $S/make-t50-tap.sh > /tmp/make-t50-tap-g7plug.sh
bash /tmp/make-t50-tap-g7plug.sh t50-auto-g7plug 420 "$W" 2>&1 | tail -5
