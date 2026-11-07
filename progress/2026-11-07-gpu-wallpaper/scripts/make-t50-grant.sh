#!/bin/bash
# A gesture test image with the longer sandbox grant. Temp boot only; writes no partition.
# Usage: make-t50-grant.sh <base dir with vol.img and kernel.macho> <out name>
set -euo pipefail
export MTOOLS_SKIP_CHECK=1
B=$1; OUT=$2; E=/mnt/e/DSH-Fuxi; S=$E/dump/wsl; W=/root/fuxi/grant-$OUT
rm -rf "$W"; mkdir -p "$W"; cd "$W"
cp "$B/vol.img" vol.img
python3 -I $S/patch-t50-grant.py "$B/kernel.macho" kernel.macho
echo "kernel bytes changed: $(cmp -l "$B/kernel.macho" kernel.macho | wc -l)"
tr -d '\r' < $S/make-t50-tap.sh > /tmp/make-t50-tap-$OUT.sh
bash /tmp/make-t50-tap-$OUT.sh "$OUT" 420 "$W" 2>&1 | tail -3
