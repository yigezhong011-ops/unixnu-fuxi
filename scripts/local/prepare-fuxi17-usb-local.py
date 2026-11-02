#!/usr/bin/env python3
"""Add official Linux host steps to the isolated fuxi 21H461 device recipe."""
from pathlib import Path
import shutil
import subprocess

base = Path('/home/xiaomi/fuxi17-usb-local-20261102')
framework, device = base/'UniXNU', base/'device'
p = device/'scripts/fuxi-kernel-baseline.sh'
s = p.read_text()
upstream = (framework/'scripts/build-xnu-4k-baseline.sh').read_text()
start = upstream.index('XNU_HOST_MAKE_ARGS=()')
end = upstream.index('# The first pass', start)
host = upstream[start:end]
anchor = 'python3 scripts/prepare-xnu-source.py\n'
assert s.count(anchor) == 1
if 'XNU_HOST_MAKE_ARGS=()' not in s:
    s = s.replace(anchor, anchor+host)
    s = s.replace('ditto ', 'copy_tree ')
    anchor = 'export KERNEL_SDKROOT=$ROOT/.cache/fakeroot\n'
    s = s.replace(anchor, anchor+'copy_tree() { mkdir -p "$2"; cp -R "$1/." "$2/"; }\n')
    s = s.replace('make -C .cache/xnu-work ', 'make "${XNU_HOST_MAKE_ARGS[@]}" -C .cache/xnu-work ')
    anchor = '# The baseline builds the kernel;'
    assert anchor in s
    s = s.replace(anchor, 'if [ "$(uname -s)" = Linux ]; then\n  python3 scripts/linux/prepare-xnu.py libs\nfi\n'+anchor)
    p.write_text(s)
subprocess.run(['bash','-n',p],check=True)
# Use the same GPU buffer extent as the actual pinned shared driver.
p = device/'package/GpuPowerProbe.cpp'
s = p.read_text().replace('NativeAdrenoGpuContextBuffers(NativeAdrenoGpuBuffer out[5])',
                         'NativeAdrenoGpuContextBuffers(NativeAdrenoGpuBuffer out[GpuBufferCount])')
s = s.replace('NativeAdrenoGpuBuffer gGpuBuffers[5];','NativeAdrenoGpuBuffer gGpuBuffers[GpuBufferCount];')
p.write_text(s)
print('Prepared isolated Linux device recipe and GPU buffer extent')
