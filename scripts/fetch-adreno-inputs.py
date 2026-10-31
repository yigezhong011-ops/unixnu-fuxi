#!/usr/bin/env python3
"""Offline replacement for scripts/fetch-adreno-inputs.py: copy the pinned inputs
staged in the device repository instead of downloading them."""
import hashlib
import json
import os
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CACHE = ROOT / '.cache/adreno-inputs'
PINS = json.loads((ROOT / 'scripts/data/adreno-inputs.json').read_text())

candidates = []
device = os.environ.get('UNIXNU_DEVICE')
if device:
    candidates.append(Path(device) / 'build/adreno-inputs')
# the tree lives at <workspace>/out/<device>/tree and the device checkout at
# <workspace>/device, so four levels up reaches it
candidates.append(ROOT / '../../../../device/build/adreno-inputs')
candidates.append(ROOT / 'build/adreno-inputs')

print('fetch-adreno-inputs: looking for staged inputs')
for candidate in candidates:
    print('   %s -> %s' % (candidate.resolve(), 'found' if candidate.is_dir() else 'missing'))

STAGED = next((c for c in candidates if c.is_dir()), None)
if STAGED is None:
    raise SystemExit('staged Adreno inputs missing')

CACHE.mkdir(parents=True, exist_ok=True)
copied = 0
missing = []
for section, info in PINS.items():
    if not isinstance(info, dict):
        continue
    for name, entry in info.get('files', {}).items():
        source = STAGED / name
        if not source.is_file():
            missing.append(name)
            continue
        target = CACHE / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
        expected = entry.get('sha256')
        if expected:
            digest = hashlib.sha256(target.read_bytes()).hexdigest()
            if digest != expected:
                raise SystemExit('sha256 mismatch for %s' % name)
        copied += 1
print('staged Adreno inputs: %d files from %s（缺失 %d）' % (copied, STAGED, len(missing)))
for name in missing[:5]:
    print('   missing', name)
