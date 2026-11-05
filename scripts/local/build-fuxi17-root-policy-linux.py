#!/usr/bin/env python3
"""Run the fuxi 21H461 policy builder using the framework's Linux UDIF reader."""
from pathlib import Path
import importlib.util
import os
import sys

base=Path('/home/xiaomi/fuxi17-usb-local-20261102')
framework=base/'UniXNU'
tree=framework/'out/fuxi/tree'
sys.path.insert(0,str(framework/'scripts'))
from unixnu.udif import Image
spec=importlib.util.spec_from_file_location('fuxi_policy',tree/'scripts/build-fuxi-verified-root-policy.py')
policy=importlib.util.module_from_spec(spec);spec.loader.exec_module(policy)

def attach(dmg):
    image=Image(dmg)
    if image.chunks is None:
        return str(dmg)  # SystemOS is already the exact raw disk.
    output=tree/'build/verified-root-fuxi/raw'/dmg.with_suffix('.raw').name
    output.parent.mkdir(parents=True,exist_ok=True)
    if not output.exists() or output.stat().st_size!=image.size:
        temporary=output.with_suffix('.partial')
        with temporary.open('wb') as handle:
            for block in image.blocks():handle.write(block)
        if temporary.stat().st_size!=image.size:raise RuntimeError('Short UDIF decode')
        os.replace(temporary,output)
    return str(output)

policy.image_size=lambda dmg:Image(dmg).size
policy.attach=attach
policy.detach=lambda path:None
# The original builder still checks both compressed and raw SHA256 digests,
# exact sizes and target UUIDs, signs every policy, and builds its probe archive.
policy.main()
