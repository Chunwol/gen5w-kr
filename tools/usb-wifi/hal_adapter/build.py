#!/usr/bin/env python3
"""Builds ARM libhardware_legacy.so adapter for Gen5W using NDK clang."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[3]

def main():
    p = argparse.ArgumentParser()
    p.add_argument('--ndk', default=os.environ.get('ANDROID_NDK_HOME') or os.environ.get('NDK'))
    a = p.parse_args()
    if not a.ndk:
        # Fallback search if not specified
        sdk = Path(os.environ.get('ANDROID_HOME', Path.home() / 'AppData/Local/Android/Sdk'))
        found = sorted(sdk.glob('ndk/*'))
        if found:
            a.ndk = str(found[-1])
        else:
            p.error('set ANDROID_NDK_HOME or pass --ndk')

    host = 'windows-x86_64' if os.name == 'nt' else 'linux-x86_64'
    tool = Path(a.ndk) / 'toolchains/llvm/prebuilt' / host / 'bin'
    clang = tool / ('clang.exe' if os.name == 'nt' else 'clang')
    if not clang.is_file():
        # Try finding any clang in prebuilt
        candidates = list((Path(a.ndk) / 'toolchains/llvm/prebuilt').glob('*/bin/clang*'))
        for c in candidates:
            if c.name in ('clang', 'clang.exe'):
                clang = c
                break

    adapter_dir = ROOT / 'tools/usb-wifi/hal_adapter'
    src = adapter_dir / 'wifi_hal_adapter.c'
    out_lib = adapter_dir / 'libhardware_legacy.so'
    pkg_files = ROOT / 'tools/usb-wifi/package/files'
    pkg_files.mkdir(parents=True, exist_ok=True)

    cmd = [
        str(clang),
        '--target=armv7a-linux-androideabi21',
        '-shared', '-fPIC', '-O2',
        '-Wl,-soname,libhardware_legacy.so',
        '-Wl,-Bsymbolic',
        '-Wl,--hash-style=both',
        '-llog', '-ldl',
        '-o', str(out_lib),
        str(src),
    ]
    subprocess.run(cmd, check=True)
    shutil.copyfile(out_lib, pkg_files / 'libhardware_legacy.so')
    print(f'Built {out_lib} successfully')

if __name__ == '__main__':
    main()
