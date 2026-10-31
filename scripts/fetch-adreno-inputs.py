#!/usr/bin/env python3
"""Offline replacement for scripts/fetch-adreno-inputs.py: copy the pinned inputs
staged in the device repository instead of downloading them (the runner's shared
IP hits GitHub's rate limit)."""
import hashlib
import json
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CACHE = ROOT / '.cache/adreno-inputs'
STAGED = Path(__file__).resolve().parents[1] / 'build/adreno-inputs'
PINS = json.loads((ROOT / 'scripts/data/adreno-inputs.json').read_text())

if not STAGED.is_dir():
    raise SystemExit('staged Adreno inputs missing: %s' % STAGED)

CACHE.mkdir(parents=True, exist_ok=True)
copied = 0
for section, info in PINS.items():
    if not isinstance(info, dict):
        continue
    for name, entry in info.get('files', {}).items():
        source = STAGED / name
        if not source.is_file():
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
print('staged Adreno inputs: %d files' % copied)
