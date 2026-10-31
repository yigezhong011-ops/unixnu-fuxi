#!/usr/bin/env python3
"""Offline replacement for scripts/fetch-adreno-inputs.py: copy the pinned inputs
staged in the device repository into every cache directory the build reads."""
import hashlib
import json
import os
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PINS = json.loads((ROOT / 'scripts/data/adreno-inputs.json').read_text())

# prepare-fuxi-gmu reads .cache/adreno-source; other tools read .cache/adreno-inputs
TARGETS = [ROOT / '.cache/adreno-source', ROOT / '.cache/adreno-inputs']

candidates = []
device = os.environ.get('UNIXNU_DEVICE')
if device:
    candidates.append(Path(device) / 'build/adreno-inputs')
candidates.append(ROOT / '../../../../device/build/adreno-inputs')
candidates.append(ROOT / 'build/adreno-inputs')

print('fetch-adreno-inputs: looking for staged inputs')
for candidate in candidates:
    print('   %s -> %s' % (candidate.resolve(), 'found' if candidate.is_dir() else 'missing'))

STAGED = next((c for c in candidates if c.is_dir()), None)
if STAGED is None:
    raise SystemExit('staged Adreno inputs missing')

copied = 0
for target_root in TARGETS:
    target_root.mkdir(parents=True, exist_ok=True)

for section, info in PINS.items():
    if not isinstance(info, dict):
        continue
    for name, entry in info.get('files', {}).items():
        source = STAGED / name
        if not source.is_file():
            continue
        expected = entry.get('sha256')
        if expected and hashlib.sha256(source.read_bytes()).hexdigest() != expected:
            raise SystemExit('sha256 mismatch in staging for %s' % name)
        for target_root in TARGETS:
            target = target_root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
        copied += 1

print('staged Adreno inputs: %d files into %s from %s' %
      (copied, ', '.join(str(t) for t in TARGETS), STAGED))
