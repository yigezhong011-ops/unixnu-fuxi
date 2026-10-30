#!/usr/bin/env python3
"""Build a link-only stub archive for the symbols whose real providers are
archives that need a prelink candidate to build (a chicken-and-egg the bootstrap
configuration has to break). The kernel built with these stubs is only used to
produce the prelink candidate; the stubs never run.
"""
import argparse
import subprocess
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('--out', type=Path, default=None,
                    help='output directory (default: <repo>/build/fuxi-link-stubs)')
args = parser.parse_args()

ROOT = Path(__file__).resolve().parents[1]
OUT = args.out or (ROOT / 'build/fuxi-link-stubs')
OUT = OUT if OUT.is_absolute() else (Path.cwd() / OUT)
OUT.mkdir(parents=True, exist_ok=True)

STUBS = """
void native_legacy_display_probe(void) {}
void boot_log_tick(void) {}
void fuxi_usb_append(void) {}
void fuxi_usb_debug_start(void) {}
void sheng_pmgr_run(void) {}
"""

(OUT / 'stubs.c').write_text(STUBS)
sdk = subprocess.check_output(['xcrun', '--sdk', 'iphoneos', '--show-sdk-path'], text=True).strip()
subprocess.run(['xcrun', 'clang', '-target', 'arm64-apple-ios17.0', '-isysroot', sdk,
                '-mkernel', '-O2', '-c', str(OUT / 'stubs.c'), '-o', str(OUT / 'stubs.o')], check=True)
archive = OUT / 'libFuxiLinkStubs.a'
archive.unlink(missing_ok=True)
subprocess.run(['xcrun', 'ar', 'rcs', str(archive), str(OUT / 'stubs.o')], check=True)
print('stub archive:', archive)
