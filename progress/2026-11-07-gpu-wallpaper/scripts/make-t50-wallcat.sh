#!/bin/bash
# t50-auto-storefix2 plus the phone wallpaper catalogue: both gates at once, the store check and the absent Collections.plist. Temp boot only.
# The kernel's third overlay moves to /Library/Wallpaper (a union mount: the sealed collections stay visible), so this image has no private-log overlay.
# The catalogue is the one t50-mine-gpu-wall used: Bokeh 5010 as default, the only collection in the order.
set -euo pipefail
export MTOOLS_SKIP_CHECK=1
# DARK_TEST=1 builds t50-auto-wallred: the same image with a bright dark-mode background on wallpaper 5010.
# WALL17=1 builds t50-auto-wall17: the configuration already on Data (5010) draws the flat iPadOS 17 artwork, as JPEG small enough for the addon's fixed size.
if [ "${WALL17:-0}" = 1 ]; then TAG=wall17; elif [ "${DARK_TEST:-0}" = 1 ]; then TAG=wallred; else TAG=wallcat; fi
E=/mnt/e/DSH-Fuxi; S=$E/dump/wsl; NAME=t50-mine-gpu-$TAG; W=/root/fuxi/t50-$TAG; SRC=/root/fuxi/t50-gpu-wall/root/Library/Wallpaper
[ -f "$SRC/Collections/Bokeh.wallpaperCollection/WallpaperCollection.plist" ]
tr -d '\r' < $S/make-t50-gpu-120.sh > /tmp/g120.sh; tr -d '\r' < $S/make-t50-auto.sh > /tmp/a.sh
export FCNTL_PROTECT=1 PROT_READ=1
bash /tmp/g120.sh $NAME -DPANEL_120 -DUSB_REBOOT -DCLOCK_SECS=$(date +%s)UL
unset FCNTL_PROTECT PROT_READ
rm -rf "$W"; mkdir -p "$W"; cp /root/fuxi/$NAME/vol.img "$W/vol.img"; cd "$W"
mtype -i vol.img ::/EFI/UniXNU/unixnu.toml > toml.txt
mtype -i vol.img ::/EFI/UniXNU/Payloads/kernel.macho.gpuaddon > addon-orig.bin
mcopy -n -i vol.img ::/EFI/UniXNU/Payloads/kernel.macho kernel.orig
SRC="$SRC" python3 -I - <<'EOF'
import os, plistlib, struct, zlib
from pathlib import Path
src = Path(os.environ['SRC'])
BOKEH = 'D4894D14-DB0F-4D04-AB02-07C39C5E5466'
def bin(v): return plistlib.dumps(v, fmt=plistlib.FMT_BINARY)
files = [
    ('DefaultWallpapers~iphone.plist', bin({'default': {'wallpaperIdentifier': 5010, 'collectionIdentifier': BOKEH}})),
    ('Wallpapers~iphone.plist', bin([{'wallpaperType': 'Dynamic'}])),
    ('Collections/Collections~iphone.plist', bin({'order': [BOKEH]})),
    ('Collections/Collections.plist', bin({'order': [BOKEH]})),
]
for f in sorted((src / 'Collections/Bokeh.wallpaperCollection').rglob('*')):
    if f.is_file():
        data = f.read_bytes()
        if os.environ.get('DARK_TEST') == '1' and f.name == 'Wallpaper.plist' and f.parent.name.startswith('5010.'):
            # The dark variant's background is pure black by design, so a working poster and a dead one look alike. Bright colours tell them apart.
            # A plist rewritten by plistlib was refused on the phone ("did not contain a top-level dictionary"), so the original bytes change in place.
            assert data.count(b'#000000') == 1, data.count(b'#000000')
            data = data.replace(b'#000000', b'#FF0000')
            v = plistlib.loads(data)
            assert v['assets']['lockAndHome']['dark']['backgroundColors'] == ['#FF0000', '#FF0000']
            print('5010 dark background set to red in place, bytes', len(data))
        files.append((f.relative_to(src).as_posix(), data))
assert len([n for n, _ in files if n.endswith('/Wallpaper.plist')]) == 9
b = open('addon-orig.bin', 'rb').read()
assert b[:8] == b'NGPUADD2'
count = struct.unpack_from('<I', b, 8)[0]
at, kept, seen = 24, b'', 0
for _ in range(count):
    start = at
    nl, mode, size, packed = struct.unpack_from('<IIQQ', b, at); at += 24
    name = b[at:at + nl - 1].decode()
    at += (nl + 7) // 8 * 8 + (packed + 7) // 8 * 8
    assert not name.startswith('wallpaper/'), name
    if 'filler' in name: continue
    kept += b[start:at]; seen += 1
assert at == len(b)
def entry(n, data):
    name = ('wallpaper/' + n).encode() + b'\0'
    assert len(name) < 150, n
    p = zlib.compress(data, 9)
    return struct.pack('<IIQQ', len(name), 0o644, len(data), len(p)) + name + bytes(-len(name) % 8) + p + bytes(-len(p) % 8)
if os.environ.get('WALL17') == '1':
    # Flat 7570 with JPEG in place of its HEIC images. Layers stretch their contents to their bounds, so the image size only sets the sharpness.
    import io, re
    from PIL import Image
    O = Path('/mnt/e/DSH-Fuxi/wallpaper-overlay')
    PK = 'Collections/Bokeh.wallpaperCollection/Wallpapers/5010.Multicolored.wallpaper/'
    CA = '7570.iPadOS_17_Flat_Background.ca'
    caml = (O / 'main.caml').read_text()
    for s in ('J120-Dark', 'J120'):
        caml = caml.replace(s + '.png', s + '.jpg')
    caml = caml.replace('J120.HEIC', 'J120.jpg')
    assert '.png' not in caml and '.HEIC' not in caml
    plist = plistlib.dumps({'family': 'iPadOS 17', 'logicalScreenClass': 'any', 'appearanceAware': True, 'contentVersion': 2.0, 'identifier': 5010, 'version': 1, 'name': 'iPadOS 17',
        'assets': {'lockAndHome': {'default': {'backgroundAnimationFileName': CA, 'name': 'iPadOS 17', 'identifier': 5010, 'type': 'LayeredAnimation'}}}}, fmt=plistlib.FMT_XML)
    files = [(n, d) for n, d in files if n != PK + 'Wallpaper.plist']
    files += [(PK + 'Wallpaper.plist', plist), (PK + CA + '/main.caml', caml.encode()),
              (PK + CA + '/index.xml', (O / 'index.xml').read_bytes()), (PK + CA + '/assetManifest.caml', (O / 'assetManifest.caml').read_bytes())]
    base = sum(len(entry(n, d)) for n, d in files)
    room = len(b) - (24 + len(kept)) - base - 4096
    print('room for two images', room)
    src = {s: Image.open(O / (s + '.png')).convert('RGB') for s in ('J120', 'J120-Dark')}
    for edge, q in ((2048, 90), (1536, 90), (1366, 88), (1200, 85), (1024, 85), (1024, 75), (800, 75), (640, 70), (512, 70)):
        im = {}
        for s, i in src.items():
            o = io.BytesIO(); i.resize((edge, edge), Image.LANCZOS).save(o, 'JPEG', quality=q, optimize=True); im[s] = o.getvalue()
        total = sum(len(entry(PK + CA + '/' + s + '.jpg', d)) for s, d in im.items())
        print('edge', edge, 'q', q, 'bytes', total)
        if total <= room:
            break
    else:
        raise SystemExit('images do not fit')
    files += [(PK + CA + '/' + s + '.jpg', d) for s, d in im.items()]
for n, data in files:
    kept += entry(n, data)
open('addon-nofill.bin', 'wb').write(b'NGPUADD2' + struct.pack('<IIQ', seen + len(files), 0, 24 + len(kept)) + kept)
print('kept', seen, 'added', len(files))
d = bytearray(open('kernel.orig', 'rb').read())
P = b'/Library/Wallpaper/Collections/iPadOS_17~ipad.wallpaperCollection/Wallpapers/7570.iPadOS_17_Flat-1024w-1366h@2x~ipad.wallpaper/7570.iPadOS_17_Flat_Background-1024w-1366h@2x~ipad.ca'
for old, new in ((P, b'/Library/Wallpaper'),
                 (P + b'/assets/J120.HEIC', b'/Library/Wallpaper/DefaultWallpapers~ipad.plist'),
                 (P + b'/J120.png', b'/Library/Wallpaper/DefaultWallpapers~iphone.plist')):
    s = b'\0' + old + b'\0'
    assert d.count(s) == 1, old[-20:]
    i = d.find(s) + 1
    d[i:i + len(old)] = new + bytes(len(old) - len(new))
open('kernel.macho', 'wb').write(d)
EOF
python3 -I $S/fit-addon.py addon-orig.bin addon-nofill.bin addon-new.bin
[ "$(stat -c%s addon-new.bin)" = "$(stat -c%s addon-orig.bin)" ]
python3 -I $S/fat-inplace.py vol.img ::/EFI/UniXNU/Payloads/kernel.macho.gpuaddon addon-new.bin >/dev/null
python3 -I $S/fat-inplace.py vol.img ::/EFI/UniXNU/Payloads/kernel.macho kernel.macho >/dev/null
mtype -i vol.img ::/EFI/UniXNU/Payloads/kernel.macho.gpuaddon | cmp - addon-new.bin
mcopy -n -i vol.img ::/EFI/UniXNU/Payloads/kernel.macho kernel.back; cmp kernel.back kernel.macho; rm -f kernel.back
mtype -i vol.img ::/EFI/UniXNU/unixnu.toml | cmp - toml.txt
echo "kernel bytes changed by the overlay move: $(cmp -l kernel.orig kernel.macho | wc -l)"
rm -f kernel.orig
bash /tmp/a.sh "$W" 300 t50-auto-$TAG
K=$W/kernel.macho
for r in '0xfffffff00ba9fbc4 0xfffffff00ba9fbc8' '0xfffffff00ba9fc24 0xfffffff00ba9fc28' '0xfffffff00bd2264c 0xfffffff00bd22650' '0xfffffff00bd22b08 0xfffffff00bd22b0c'; do set -- $r; llvm-objdump -d --start-address=$1 --stop-address=$2 $K | tail -n +7 | cut -c1-80; done
strings -a $K | grep -E '^/Library/Wallpaper' | cut -c1-120 | sort -u
ls -la $E/t50-auto-$TAG.img | cut -c20-; sha256sum $E/t50-auto-$TAG.img | cut -c1-16
