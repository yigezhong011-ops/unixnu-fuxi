#!/usr/bin/env python3
"""Build a stub archive for the symbols the bootstrap kernel references but whose
real providers are archives that need a prelink candidate (chicken and egg).

The kernel produced with these stubs is only used to generate the prelink
candidate: the stubs are never meant to run.
"""
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'build/fuxi-link-stubs'
OUT.mkdir(parents=True, exist_ok=True)

STUBS = """
/* Link-only stubs: one definition per symbol the bootstrap configuration
 * references while its real archives need a prelink candidate to build. */
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
