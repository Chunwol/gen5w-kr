"""Build the optional exact-V039 local-hotspot trial, without OEM files."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--ndk', type=Path, required=True)
    args = parser.parse_args()
    work = ROOT / '.build/local-hotspot'
    package = work / 'package'
    package.mkdir(parents=True, exist_ok=True)
    shutil.copytree(ROOT / 'tools/local-hotspot/package', package, dirs_exist_ok=True)
    (package / 'bin').mkdir(exist_ok=True)
    recipe = json.loads((ROOT / 'tools/iap2/hotspot-v039.json').read_text())
    lines = [f'#define ORIGINAL_SHA "{recipe["original_sha256"]}"',
             f'#define PATCHED_SHA "{recipe["patched_sha256"]}"']
    for i, entry in enumerate(recipe['patches']):
        lines.append('static const unsigned char replacement%d[]={%s};' % (i, ','.join(map(str, entry['bytes']))))
    lines.append('static const struct patch patches[]={' + ','.join(
        '{%d,%d,replacement%d}' % (item['offset'], len(item['bytes']), i)
        for i, item in enumerate(recipe['patches'])) + '};')
    (work / 'recipe.h').write_text('\n'.join(lines) + '\n')
    host = 'windows-x86_64' if os.name == 'nt' else 'linux-x86_64'
    clang = args.ndk / 'toolchains/llvm/prebuilt' / host / 'bin' / ('clang.exe' if os.name == 'nt' else 'clang')
    subprocess.run([str(clang), '--target=armv7a-linux-androideabi19', '-std=c99', '-Os',
                    '-Wall', '-Wextra', '-Werror', '-fno-builtin', '-fno-stack-protector',
                    '-fno-unwind-tables', '-fno-asynchronous-unwind-tables', '-fno-pie',
                    '-nostdlib', '-static', '-Wl,-e,_start', '-Wl,--build-id=none',
                    '-I', str(work), 'tools/audio/patch.c', 'tools/audio/runtime.c',
                    'tools/audio/syscalls.S', '-o', str(package / 'bin/hotspot-patch')], cwd=ROOT, check=True)
    for item in list((package / 'scripts').glob('*.sh')) + [package / 'bin/hotspot-patch']:
        item.chmod(0o755)
    subprocess.run(['python' if os.name == 'nt' else 'python3', '-I', 'tools/mkpkg.py',
                    str(package), str(work / 'gen5w.kr.localhotspot-trial.zip')], cwd=ROOT, check=True)


if __name__ == '__main__':
    main()
