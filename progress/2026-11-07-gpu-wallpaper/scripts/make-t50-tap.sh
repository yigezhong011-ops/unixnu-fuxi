#!/bin/bash
# t50-auto-gpu7tap: t50-gpu7 plus USB TAP and SWP verbs with coordinates (touch-cave2.c). Temp boot only; writes no partition.
# Usage: make-t50-tap.sh [out-name] [seconds] [base dir]
set -euo pipefail
OUT=${1:-t50-auto-gpu7tap}; SECS=${2:-420}; B=${3:-/root/fuxi/t50-gpu7}
export MTOOLS_SKIP_CHECK=1
E=/mnt/e/DSH-Fuxi; S=$E/dump/wsl; W=/root/fuxi/tap-$OUT
rm -rf "$W"; mkdir -p "$W"; cd "$W"; cp "$B/vol.img" vol.img; cp "$B/kernel.macho" kernel.old
N=$W/syms.txt; llvm-nm --defined-only kernel.old > "$N" 2>/dev/null
sym() { local a; a=$(grep -E " $1\$" "$N" | head -1 | cut -d' ' -f1); [ -n "$a" ] || { echo "missing $1" >&2; exit 1; }; echo "0x$a"; }
CAVE=$(python3 -c "print(hex($(sym _copyio_test) + 0x1000))"); CHECK=$(sym _native_legacy_gop_mapping_checkpoint); VERB=$(sym _sxnu_control_parse_verb)
clang --target=aarch64-none-elf -Oz -ffreestanding -fno-builtin -fno-stack-protector -fno-jump-tables -ffixed-x18 -mgeneral-regs-only -fno-pic -fno-unwind-tables -fno-asynchronous-unwind-tables -c $S/touch-cave2.c -o cave.o \
  -DADDR_GOP_VIRTUAL=$(sym _native_legacy_gop_virtual)UL -DADDR_GOP_WIDTH=$(sym _native_legacy_gop_width)UL -DADDR_GOP_HEIGHT=$(sym _native_legacy_gop_height)UL \
  -DADDR_PE_CURRENT_CONSOLE=$(sym _PE_current_console)UL -DADDR_REGISTER_SCREENSHOT=$(sym _qcom_usb_debug_register_screenshot)UL -DADDR_PARSE_VERB=${VERB}UL
ld.lld -e touch_entry -Ttext=$CAVE --image-base=$CAVE -z max-page-size=4096 cave.o -o cave.elf
llvm-objcopy -O binary -j .text -j .rodata cave.elf cave.bin
llvm-objdump -h cave.elf | grep -E ' \.(text|rodata|data|bss) ' | cut -c1-60
ENTRY=$(llvm-nm cave.elf | grep -E ' T touch_entry$' | cut -d' ' -f1); HOOK=$(llvm-nm cave.elf | grep -E ' T verb_hook$' | cut -d' ' -f1)
LOW=$(llvm-objdump -h cave.elf | awk '$2==".text"||$2==".rodata"{print $4}' | sort | head -1)
python3 -I $S/patch-t50-tap.py kernel.old kernel.macho cave.bin "$CAVE" "0x$LOW" "$CHECK" "0x$ENTRY" 0xfffffff00c070b0c "$VERB" "0x$HOOK"
python3 -I $S/fat-inplace.py vol.img ::/EFI/UniXNU/Payloads/kernel.macho kernel.macho >/dev/null
mcopy -n -i vol.img ::/EFI/UniXNU/Payloads/kernel.macho kernel.back; cmp kernel.back kernel.macho
echo "kernel bytes changed: $(cmp -l kernel.old kernel.macho | wc -l)"
for a in "$CHECK" 0xfffffff00c070b0c; do llvm-objdump -d --no-show-raw-insn --start-address=$a --stop-address=$(printf '0x%x' $((a + 4))) kernel.macho | tail -1 | cut -c1-70; done
tr -d '\r' < $S/make-t50-auto.sh > /tmp/make-t50-auto-$OUT.sh
bash /tmp/make-t50-auto-$OUT.sh "$W" "$SECS" "$OUT"
ls -la $E/$OUT.img
