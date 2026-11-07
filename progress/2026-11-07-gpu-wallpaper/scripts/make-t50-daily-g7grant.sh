#!/bin/bash
# t50-daily-g7grant: the daily boot arguments on the g7grant kernel (old plugin, longer sandbox grant, full X range), with the new USB firmware. No autoreset.
# Builds only; writes no partition.
set -euo pipefail
export MTOOLS_SKIP_CHECK=1
E=/mnt/e/DSH-Fuxi; S=$E/dump/wsl; T=/root/fuxi/tap-t50-auto-g7grant; W=/root/fuxi/daily-g7grant; OUT=t50-daily-g7grant
rm -rf "$W"; mkdir -p "$W"; cd "$W"
cp "$T/vol.img" vol.img
mtype -i vol.img ::/EFI/UniXNU/unixnu.toml > toml.tap
python3 -I - toml.tap toml <<'PY'
import re, sys
old = open(sys.argv[1], 'rb').read(); t = old.decode()
m = re.search(r'args = "([^"]*)"', t)
args = [a for a in m.group(1).split() if not a.startswith(('sheng-autoreset=', 'boot-ui-focus4='))]
if not any(a == 'qcom-usb-ctl=1' for a in args):
    args.insert(0, 'qcom-usb-ctl=1')
line = ' '.join(args)
new = (t[:m.start()] + 'args = "' + line + '"' + t[m.end():]).encode()
assert len(new) <= len(old), len(new) - len(old)
assert len(line) < 1020
body = new.rstrip(b'\n ')
open(sys.argv[2], 'wb').write(body + b'\n' + b' ' * (len(old) - len(body) - 1))
print('args chars', len(line), 'start', ' '.join(args[:2]))
PY
python3 -I $S/fat-inplace.py vol.img ::/EFI/UniXNU/unixnu.toml toml >/dev/null
mtype -i vol.img ::/EFI/UniXNU/unixnu.toml | cmp - toml
mcopy -n -i vol.img ::/EFI/UniXNU/Payloads/kernel.macho kernel.back; cmp kernel.back "$T/kernel.macho"
grep -a -c 'KaleidoscopePoster,PridePosterExtension,HelloPosterExtension' kernel.back
python3 -I $S/repack-with-vol.py $E/t50-mine.img vol.img $W/noswap.img >/dev/null
python3 -I $S/swap-fd.py $W/noswap.img /root/fuxi/fw/usbstart.fd $E/$OUT.img
python3 -I $S/compare-loaders.py $E/$OUT.img | tail -1
ls -la $E/$OUT.img; sha256sum $E/$OUT.img | cut -c1-16
