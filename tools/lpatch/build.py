"""Build lpatch (delta/zipadd engine) as a freestanding ARM binary for the head unit.

lpatch.c is from HMG Leafia Plus (GPL-3.0-or-later); see NOTICE.md.
"""
import argparse
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--ndk', default=os.environ.get('ANDROID_NDK_HOME'))
    p.add_argument('--out', type=Path, default=ROOT / 'packages/wireless-bridge/bin/lpatch')
    a = p.parse_args()
    if not a.ndk:
        p.error('--ndk or ANDROID_NDK_HOME required')
    host = 'windows-x86_64' if os.name == 'nt' else 'linux-x86_64'
    clang = Path(a.ndk) / 'toolchains/llvm/prebuilt' / host / 'bin' / ('clang.exe' if os.name == 'nt' else 'clang')
    a.out.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run([str(clang), '--target=armv7a-linux-gnueabi', '-mthumb', '-march=armv7-a',
                    '-mfloat-abi=soft', '-Os', '-ffreestanding', '-fno-builtin', '-nostdlib', '-static',
                    '-fno-stack-protector', '-fno-unwind-tables', '-fno-asynchronous-unwind-tables',
                    '-fno-pie', '-fuse-ld=lld', '-Wl,-e,_start', '-Wl,--build-id=none',
                    '-o', str(a.out), 'tools/lpatch/lpatch.c'], cwd=ROOT, check=True)
    print(f'Built freestanding ARM lpatch: {a.out}')


if __name__ == '__main__':
    main()
