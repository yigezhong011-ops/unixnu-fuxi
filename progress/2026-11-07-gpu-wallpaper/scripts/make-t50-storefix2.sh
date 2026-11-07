#!/bin/bash
# t50-auto-storefix plus: reads of the protection class answer 4 (none) on both paths, the other half of PosterBoard's store check. Temp boot only.
set -euo pipefail
S=/mnt/e/DSH-Fuxi/dump/wsl
tr -d '\r' < $S/make-t50-gpu-120.sh > /tmp/g120.sh; tr -d '\r' < $S/make-t50-auto.sh > /tmp/a.sh; tr -d '\r' < $S/make-t50-privlog.sh > /tmp/pl.sh
export FCNTL_PROTECT=1 PROT_READ=1
bash /tmp/g120.sh t50-mine-gpu-storefix2 -DPANEL_120 -DUSB_REBOOT -DCLOCK_SECS=$(date +%s)UL
unset FCNTL_PROTECT PROT_READ
bash /tmp/pl.sh /root/fuxi/t50-mine-gpu-storefix2 /root/fuxi/t50-priv-storefix2
bash /tmp/a.sh /root/fuxi/t50-priv-storefix2 300 t50-auto-storefix2
K=/root/fuxi/t50-mine-gpu-storefix2/kernel.macho
for r in '0xfffffff00ba9fbc4 0xfffffff00ba9fbc8' '0xfffffff00ba9fc24 0xfffffff00ba9fc28' '0xfffffff00bd2264c 0xfffffff00bd22650' '0xfffffff00bd22b08 0xfffffff00bd22b0c'; do set -- $r; llvm-objdump -d --start-address=$1 --stop-address=$2 $K | tail -n +7 | cut -c1-80; done
sha256sum /mnt/e/DSH-Fuxi/t50-auto-storefix2.img | cut -c1-16
