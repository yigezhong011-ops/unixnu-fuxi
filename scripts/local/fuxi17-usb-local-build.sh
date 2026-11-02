#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
BASE=/home/xiaomi/fuxi17-usb-local-20261102
cd "$BASE/UniXNU"
exec 9>"$BASE/local-build.lock"
flock -n 9 || { echo 'Another local build is already running'; exit 1; }
export UNIXNU_DEVICE="$BASE/device" UNIXNU_TOOLCHAIN=/home/xiaomi/unixnu-linux
export CLT_PREFIX="$UNIXNU_TOOLCHAIN/CommandLineTools/usr"
export XCTOOLCHAIN_PREFIX="$UNIXNU_TOOLCHAIN/XcodeDefault.xctoolchain/usr"
export PATH="$BASE/bin:$CLT_PREFIX/bin:$UNIXNU_TOOLCHAIN/bin:$PATH"
export XNU_TOOLCHAIN_BIN="$CLT_PREFIX/bin $XCTOOLCHAIN_PREFIX/bin"
export CROSS_CLANG="$UNIXNU_TOOLCHAIN/llvm/bin/clang" DARWIN_TRIPLE=arm64-apple-ios17.0
export CROSS_EXTRA_FLAGS='-mllvm -disable-atexit-based-global-dtor-lowering'
export CCC_OVERRIDE_OPTIONS='# +-Wno-missing-designated-field-initializers +-Wno-unused-but-set-global +-Wno-unsafe-buffer-usage +-Wno-shadow-header'
export UNIXNU_SDKROOT="$PWD/out/fuxi/tree/.cache/fakeroot"
IPSW=/mnt/c/Users/Xiaomi/Downloads/iPad_Pro_HFR_17.7.11_21H461_Restore.ipsw
JOBS=${JOBS:-4}
if [ ! -f "$BASE/reference-ready" ]; then
  ./unixnu defconfig fuxi_bootstrap_defconfig -D "$UNIXNU_DEVICE"
  (cd out/fuxi/tree && python3 scripts/build-fuxi-link-stubs.py)
  FUXI_USB_REFERENCE_ONLY=1 ./unixnu build kernel -D "$UNIXNU_DEVICE" -j "$JOBS" --ipsw "$IPSW"
  python3 scripts/ci/fuxi17-stage-reference.py
  touch "$BASE/reference-ready"
fi
if [ ! -f "$BASE/policies-ready" ]; then
  ./unixnu ipsw fetch OS 'Cryptex1,SystemOS' -D "$UNIXNU_DEVICE" --ipsw "$IPSW"
  mkdir -p "$UNIXNU_DEVICE/.cache/firmware/target-volumes"
  ln -sfn "$PWD/out/ipsw/21H461/044-76034-038.dmg" "$UNIXNU_DEVICE/.cache/firmware/target-volumes/044-76034-038.dmg"
  python3 "$SCRIPT_DIR/build-fuxi17-root-policy-linux.py"
  touch "$BASE/policies-ready"
fi
./unixnu defconfig fuxi_full_defconfig -D "$UNIXNU_DEVICE"
./unixnu build kernel -D "$UNIXNU_DEVICE" -j "$JOBS" --ipsw "$IPSW"
mkdir -p out/fuxi17-usb
python3 scripts/ci/fuxi17-check-kernel.py
printf '\nFull fuxi 21H461 USB kernel built. Phone enumeration is not yet tested.\n'
