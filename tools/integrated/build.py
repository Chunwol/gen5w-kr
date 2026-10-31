#!/usr/bin/env python3
"""Build a deterministic integrated USB tree from the six final dist ZIPs."""
import argparse
import configparser
import hashlib
import os
from pathlib import Path, PurePosixPath
import shutil
import subprocess
import sys
import zipfile

HERE = Path(__file__).resolve().parent
IDS = ['gen5w.kr.' + x for x in ('wireless', 'audio', 'hotspot', 'bridge', 'core', 'notice')]


def compiler():
    value = os.environ.get('GEN5W_CLANG') or shutil.which('clang')
    if value:
        return value
    sdk = Path(os.environ.get('ANDROID_HOME', Path.home() / 'AppData/Local/Android/Sdk'))
    found = sorted(sdk.glob('ndk/*/toolchains/llvm/prebuilt/*/bin/clang.exe'))
    if not found:
        raise SystemExit('Set GEN5W_CLANG to NDK clang (freestanding ARM build)')
    return str(found[-1])


def native():
    cc = compiler()
    (HERE / 'bin').mkdir(exist_ok=True)
    for target, name in [('armv7a-linux-androideabi19', 'zipstore'), ('x86_64-linux-gnu', 'zipstore-host')]:
        out = HERE / 'bin' / name
        subprocess.run([cc, '--target=' + target, '-fuse-ld=lld', '-nostdlib', '-static',
                        '-fno-builtin', '-fno-stack-protector', '-fno-unwind-tables',
                        '-fno-asynchronous-unwind-tables', '-O2', '-Wl,-e,_start',
                        str(HERE / 'zipstore.c'), '-o', str(out)], check=True)
        # No interpreter or dynamic table: does not depend on newer Android libc.
        data = out.read_bytes()
        if data[:4] != b'\x7fELF':
            raise SystemExit('Compiler did not produce an ELF executable')
        out.chmod(0o755)


def build(dist, output, variant='standard'):
    if variant not in ('standard', 'dongle', 'safe', 'safe-wireless'):
        raise SystemExit('Unsupported edition variant: ' + variant)
    if output.exists():
        raise SystemExit('Output already exists: ' + str(output))
    pkg_ids = list(IDS)
    if variant == 'dongle':
        dongle_zip = dist / 'gen5w.kr.dongle.zip'
        if not dongle_zip.is_file():
            sys.path.insert(0, str(HERE.parents[1] / 'tools' / 'usb-wifi'))
            import build_dongle_zip
            build_dongle_zip.build_dongle_zip(HERE.parents[1] / 'tools' / 'usb-wifi' / 'package', dongle_zip)
        pkg_ids.insert(0, 'gen5w.kr.dongle')
    # Validate all inputs before creating an output tree.
    payloads = {}
    for ident in pkg_ids:
        path = dist / (ident + '.zip')
        with zipfile.ZipFile(path) as z:
            if z.testzip():
                raise SystemExit('Corrupt ZIP: ' + str(path))
            entries = {}
            for info in z.infolist():
                p = PurePosixPath(info.filename)
                mode = info.external_attr >> 16
                if (p.is_absolute() or '..' in p.parts or '\\' in info.filename or
                        mode & 0o170000 == 0o120000 or info.filename in entries):
                    raise SystemExit('Unsafe ZIP entry: ' + info.filename)
                if not info.is_dir():
                    entries[info.filename] = z.read(info)
            meta = configparser.ConfigParser(interpolation=None)
            meta.read_string(entries['NEMESIS.data'].decode('utf-8'))
            if meta['nemesis']['id'] != ident:
                raise SystemExit('Wrong identity: ' + str(path))
            payloads[ident] = entries
    output.mkdir(parents=True)
    (output / 'packages').mkdir()
    for ident, entries in payloads.items():
        package = dist / (ident + '.zip')
        shutil.copyfile(package, output / 'packages' / package.name)
        stage = output / 'checks' / ident
        stage.mkdir(parents=True)
        sums = []
        for name, data in sorted(entries.items()):
            target = stage / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
            target.chmod(0o755 if name.endswith('.sh') or '/bin/' in '/' + name else 0o644)
            sums.append(hashlib.md5(data).hexdigest() + '  ' + name)
        (stage / 'FILES.md5').write_text('\n'.join(sums) + '\n', encoding='utf-8', newline='\n')
        (stage / 'PACKAGE.md5').write_text(hashlib.md5(package.read_bytes()).hexdigest() + '\n', encoding='ascii', newline='\n')
    # Restore-only legacy migration code, never an installable skip payload.
    stage = output / 'checks/gen5w.kr.consent'
    source = HERE.parents[1] / 'packages/consent-restore'
    shutil.copytree(source, stage)
    sums = [hashlib.md5(p.read_bytes()).hexdigest() + '  ' + p.relative_to(stage).as_posix()
            for p in sorted(stage.rglob('*')) if p.is_file()]
    (stage / 'FILES.md5').write_text('\n'.join(sums) + '\n', encoding='ascii', newline='\n')
    if variant != 'dongle':
        stage = output / 'checks/gen5w.kr.dongle'
        source = HERE.parents[1] / 'tools/usb-wifi/package'
        (stage / 'scripts').mkdir(parents=True)
        for rel in ['NEMESIS.data', 'scripts/common.sh', 'scripts/preun.sh']:
            shutil.copyfile(source / rel, stage / rel)
            (stage / rel).chmod(0o755 if rel.endswith('.sh') else 0o644)
        sums = [hashlib.md5(p.read_bytes()).hexdigest() + '  ' + p.relative_to(stage).as_posix()
                for p in sorted(stage.rglob('*')) if p.is_file()]
        (stage / 'FILES.md5').write_text('\n'.join(sums) + '\n', encoding='ascii', newline='\n')
    for p in HERE.glob('*.sh'):
        shutil.copyfile(p, output / p.name)
        (output / p.name).chmod(0o755)
    shutil.copyfile(HERE / 'bin/zipstore', output / 'zipstore')
    (output / 'zipstore').chmod(0o755)
    guide = HERE.parents[1] / 'docs/vehicle-use.md'
    shutil.copytree(HERE.parents[1] / 'docs', output / 'docs')
    if guide.is_file():
        (output / '사용방법.md').write_text(guide.read_text(encoding='utf-8').replace(
            '](beginner-guide.md)', '](docs/beginner-guide.md)').replace(
            '](validation.md)', '](docs/validation.md)'), encoding='utf-8', newline='\n')
    for source, target in [('LICENSE','LICENSE'), ('NOTICE.md','NOTICE.md'), ('docs/beginner-guide.md','처음설치.md'),
                           ('docs/licensing.md','라이선스와소스.md'), ('SOURCE.md','SOURCE.md'),
                           ('README.md','README.md'), ('CONTRIBUTING.md','CONTRIBUTING.md'),
                           ('SECURITY.md','SECURITY.md'), ('CHANGELOG.md','CHANGELOG.md')]:
        path = HERE.parents[1] / source
        if path.is_file():
            if source == 'docs/beginner-guide.md':
                (output / target).write_text(path.read_text(encoding='utf-8').replace(
                    '](porting.md)', '](docs/porting.md)'), encoding='utf-8', newline='\n')
            elif source == 'docs/licensing.md':
                (output / target).write_text(path.read_text(encoding='utf-8').replace(
                    '](../LICENSE)', '](LICENSE)').replace(
                    '](../NOTICE.md)', '](NOTICE.md)'), encoding='utf-8', newline='\n')
            else: shutil.copyfile(path, output / target)
    (output / 'BUILD-REVISION').write_text(subprocess.check_output(
        ['git','rev-parse','HEAD'], cwd=HERE.parents[1], text=True).strip()+'\n', encoding='ascii', newline='\n')
    (output / 'GEN5W-VARIANT').write_text(variant+'\n', encoding='ascii', newline='\n')
    (output / 'GEN5W-BACKEND').write_text(('dongle' if variant == 'dongle' else 'builtin')+'\n', encoding='ascii', newline='\n')
    (output / 'NEMESIS.data').write_text('[nemesis]\nversion=1.0\ntype=open\nid=gen5w.kr.integrated\nname=Gen5W KR integrated installer\ncompat=gen5w\n', encoding='ascii', newline='\n')
    (output / 'NEMESIS.sh').write_text('''#!/system/bin/sh
case "$0" in */*) cd "${0%/*}" || exit 1;; esac
action=install
if [ -f GEN5W-ACTION ]; then
    IFS= read -r action < GEN5W-ACTION || [ -n "$action" ] || exit 1
    action=${action%$'\\r'}
fi
case "$action" in install|update|rollback|remove|status|repair-hotspot|wired-only) ;;
    *) echo 'REFUSED unknown GEN5W-ACTION'; exit 1;; esac
# Only fixed phase names and exit codes; never copy subprocess output or secrets.
[ ! -L GEN5W-REPORT ] || exit 1
mkdir -p GEN5W-REPORT || exit 1
[ ! -L GEN5W-REPORT/STARTUP.txt ] || exit 1
echo "action=$action" > GEN5W-REPORT/STARTUP.txt || exit 1
/system/bin/sh "./$action.sh" > GEN5W-REPORT/EXEC_LOG.txt 2>&1
status=$?
cat GEN5W-REPORT/EXEC_LOG.txt 2>/dev/null
echo "exit=$status" >> GEN5W-REPORT/STARTUP.txt
sync
exit "$status"
''', encoding='ascii', newline='\n')
    (output / 'NEMESIS.sh').chmod(0o755)
    archive = output.with_suffix('.zip')
    with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED) as z:
        for p in sorted(output.rglob('*')):
            if p.is_file():
                info = zipfile.ZipInfo(p.relative_to(output).as_posix(), (1980, 1, 1, 0, 0, 0))
                info.external_attr = (0o100755 if p.name == 'zipstore' or p.suffix == '.sh' else 0o100644) << 16
                info.compress_type = zipfile.ZIP_DEFLATED
                z.writestr(info, p.read_bytes())
    print('Integrated USB tree:', output)
    print('Integrated ZIP:', archive)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dist', type=Path, default=HERE.parents[1] / 'dist')
    parser.add_argument('--output', type=Path)
    parser.add_argument('--native-only', action='store_true')
    parser.add_argument('--skip-native', action='store_true')
    parser.add_argument('--variant', choices=('standard', 'dongle', 'safe', 'safe-wireless'), default='standard')
    args = parser.parse_args()
    if not args.skip_native:
        native()
    if not args.native_only:
        build(args.dist.resolve(), (args.output or args.dist / 'usb-integrated').resolve(), args.variant)
