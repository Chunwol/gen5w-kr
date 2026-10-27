"""Build freestanding API19 ARM helpers from authored timer-only recipes."""
import argparse
import json
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ndk', default=os.environ.get('ANDROID_NDK_HOME'))
    args = parser.parse_args()
    if not args.ndk:
        parser.error('--ndk or ANDROID_NDK_HOME required')
    host = 'windows-x86_64' if os.name == 'nt' else 'linux-x86_64'
    clang = Path(args.ndk)/'toolchains/llvm/prebuilt'/host/'bin'/('clang.exe' if os.name == 'nt' else 'clang')
    package = ROOT/'packages/hotspot-match'
    (package/'bin').mkdir(parents=True, exist_ok=True)
    for version in ('v035', 'v039'):
        recipe = json.loads((ROOT/'tools/hotspot'/f'{version}.json').read_text())
        include = ROOT/'.build/hotspot'/version
        include.mkdir(parents=True, exist_ok=True)
        header = [f'#define ORIGINAL_SHA "{recipe["original_sha256"]}"',
                  f'#define PATCHED_SHA "{recipe["patched_sha256"]}"']
        for i, patch in enumerate(recipe['patches']):
            header.append('static const unsigned char replacement%d[]={%s};' %
                          (i, ','.join(map(str, patch['bytes']))))
        header.append('static const struct patch patches[]={'+','.join(
            '{%d,%d,replacement%d}' % (patch['offset'], len(patch['bytes']), i)
            for i, patch in enumerate(recipe['patches']))+'};')
        (include/'recipe.h').write_text('\n'.join(header)+'\n', newline='\n')
        subprocess.run([str(clang), '--target=armv7a-linux-androideabi19',
            '-std=c99', '-Os', '-Wall', '-Wextra', '-Werror', '-fno-builtin',
            '-fno-stack-protector', '-fno-unwind-tables', '-fno-asynchronous-unwind-tables',
            '-fno-pie', '-nostdlib', '-static', '-Wl,-e,_start', '-Wl,--build-id=none',
            '-I', str(include), 'tools/audio/patch.c', 'tools/audio/runtime.c',
            'tools/audio/syscalls.S', '-o', str(package/'bin'/f'hotspot-patch-{version}')],
            cwd=ROOT, check=True)
        (package/'scripts'/f'profile-recipe-{version}.sh').write_text(
            f'PROFILE_RECIPE={version}-memory-only-ap-profile\nPROFILE_FRAMEWORK_SHA={recipe["framework_sha256"]}\n',
            newline='\n')
    print('Built two exact-hash AP selection helpers; ordinary profile never modified')


if __name__ == '__main__':
    main()
