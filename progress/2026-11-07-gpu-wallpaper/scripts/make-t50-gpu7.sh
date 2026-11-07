#!/bin/bash
# t50-auto-gpu7: t50-auto-shot plus patch-t50-gpu7.py. Autoreset stays as the fallback. Temp boot only; writes no partition.
set -euo pipefail
export MTOOLS_SKIP_CHECK=1
E=/mnt/e/DSH-Fuxi; S=$E/dump/wsl; B=/root/fuxi/t50-shot; W=/root/fuxi/t50-gpu7
echo '== around the prepare call in bringUp'
llvm-objdump -d --start-address=0xfffffff00c00c3b0 --stop-address=0xfffffff00c00c3e0 "$B/kernel.macho" | tail -12 | sed -E 's/<[^>]*>//' | cut -c1-74
AP=$(llvm-objdump -d --start-address=0xfffffff00c00c3a0 --stop-address=0xfffffff00c00c3e0 "$B/kernel.macho" | grep -E '\bmov\s+w4, #-?0x80000000' | head -1 | cut -d: -f1)
[ -n "$AP" ] || { echo 'aperture mov not found'; exit 1; }
echo "aperture mov at $AP"
rm -rf "$W"; mkdir -p "$W"; cp "$B/vol.img" "$W/vol.img"
mcopy -n -i "$W/vol.img" ::/EFI/UniXNU/Payloads/kernel.macho "$W/kernel.old"
cmp "$W/kernel.old" "$B/kernel.macho"
python3 -I $S/patch-t50-gpu7.py "$W/kernel.old" "$W/kernel.macho" "0x$AP"
python3 -I $S/fat-inplace.py "$W/vol.img" ::/EFI/UniXNU/Payloads/kernel.macho "$W/kernel.macho" >/dev/null
mcopy -n -i "$W/vol.img" ::/EFI/UniXNU/Payloads/kernel.macho "$W/kernel.back"; cmp "$W/kernel.back" "$W/kernel.macho"
echo "kernel bytes changed: $(cmp -l "$W/kernel.old" "$W/kernel.macho" | wc -l)"
echo '== new slot choice'
llvm-objdump -d --no-show-raw-insn --start-address=0xfffffff00c00ec58 --stop-address=0xfffffff00c00eca4 "$W/kernel.macho" | tail -19 | sed -E 's/<[^>]*>//' | cut -c1-66
echo '== other sites'
for a in 0xfffffff00c00ed98 0xfffffff00c045338 0xfffffff00c00f224 0xfffffff00c00c2d4 0xfffffff00c00c3d0 0xfffffff00c0123e4; do llvm-objdump -d --no-show-raw-insn --start-address=$a --stop-address=$(printf '0x%x' $((a + 8))) "$W/kernel.macho" | tail -2 | sed -E 's/<[^>]*>//' | cut -c1-66; done
tr -d '\r' < $S/make-t50-auto.sh > /tmp/make-t50-auto.sh
bash /tmp/make-t50-auto.sh "$W" 420 t50-auto-gpu7
