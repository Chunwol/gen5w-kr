"""Assemble the opt-in portability candidate without touching release outputs."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent


def git_output(*arguments: str) -> str:
    environment = os.environ.copy()
    dotgit = ROOT / '.git'
    if os.name != 'nt' and dotgit.is_file() and not environment.get('GIT_DIR'):
        reference = dotgit.read_text(encoding='utf-8').strip()
        if reference.startswith('gitdir: '):
            path = reference[8:].replace('\\', '/')
            if len(path) > 3 and path[1:3] == ':/':
                translated = Path('/mnt') / path[0].lower() / path[3:]
                if translated.is_dir():
                    environment['GIT_DIR'] = str(translated)
                    environment['GIT_WORK_TREE'] = str(ROOT)
    return subprocess.check_output(
        ['git', *arguments], cwd=ROOT, env=environment,
        text=True, encoding='utf-8', errors='replace'
    ).strip()


def no_symlink(path: Path) -> None:
    for part in (path, *path.parents):
        if part.is_symlink():
            raise ValueError('symlink path component is not permitted: ' + str(part))


def assemble(output: Path, inputs: Path, runtime: bool = False) -> None:
    output = output.absolute()
    inputs = inputs.absolute()
    no_symlink(output)
    no_symlink(inputs)
    resolved = output.resolve()
    # Only .build is a permitted destination inside this checkout.
    if resolved == ROOT or ROOT in resolved.parents:
        allowed = ROOT / '.build'
        if resolved == allowed or allowed not in resolved.parents:
            raise ValueError('candidate output must be outside source/release artifacts')
    if output.exists() or output.is_symlink():
        raise FileExistsError(output)
    files = {
        'bin/dex-patch': inputs / 'dex-patch',
        'prepare.sh': HERE / 'prepare.sh',
        'overlay.sh': HERE / 'overlay.sh',
        'portable.sh': HERE / 'portable.sh',
        'check.sh': HERE / 'check.sh',
        'framework.sh': HERE / 'framework.sh',
        'README.md': ROOT / 'docs/portable-candidate.md',
        'LICENSE': ROOT / 'LICENSE',
        'NOTICE.md': ROOT / 'NOTICE.md',
        'SOURCE.md': ROOT / 'SOURCE.md',
    }
    if runtime:
        for name in ('engine.jar', 'adapter.jar', 'libgen5whook.so', 'abi.sha256', 'hook-vm-test.jar'):
            files['dalvik/' + name] = inputs / 'dalvik' / name
        for name in ('runtime.sh', 'ap.sh', 'framework.sh', 'persistent-migrate.sh', 'persistent-start.sh', 'wrap-dipo.sh', 'wrap-gpm.sh', 'wrap-common.sh', 'wrap-probe.sh', 'session.sh', 'diagnostics.sh', 'debug.sh', 'ui.sh', 'boot.sh', 'rescue.sh', 'rescue-watch.sh', 'bootguard.sh', 'package-pre.sh', 'package-post.sh', 'package-preun.sh', 'service.sh', 'NEMESIS.data'):
            files[name] = HERE / name
        files['bootguard-restore.sh'] = HERE / 'recovery-usb/restore.sh'
        for name, source in (('bridge.dex', inputs / 'apps/bridge.dex'),
                             ('wireless-host.apk', inputs / 'apps/wireless-host.apk'),
                             ('gen5w-core.apk', inputs / 'apps/gen5w-core.apk')):
            files['app/' + name] = source
    for name in ('com.hkmc.software.connectivity.carplay_wireless.xml',
                 'com.hkmc.software.connectivity.androidauto_wireless.xml',
                 'com.hkmc.software.wifihotspot.xml'):
        files['permissions/' + name] = ROOT / 'packages/wireless-enable/files/permissions' / name
    # The reviewed audio helper remains hash-bound; an unknown native ABI skips audio.
    for suffix in ('', '-v035'):
        helper = ROOT / 'packages/audio-format/bin' / ('audio-patch' + suffix)
        if helper.is_file():
            files['bin/audio-patch' + suffix] = helper
            files['audio/recipe' + suffix + '.sh'] = ROOT / 'packages/audio-format/scripts' / ('recipe' + suffix + '.sh')
    regional_audio = inputs / 'audio/audio-region-patch'
    if regional_audio.is_file():
        if (inputs / 'audio/BUILD-FAILED').exists():
            raise ValueError('incomplete regional audio build')
        files['bin/audio-region-patch'] = regional_audio
    for source in files.values():
        no_symlink(source.absolute())
        if not source.is_file():
            raise FileNotFoundError(source)
    output.parent.mkdir(parents=True, exist_ok=True)
    stage = Path(tempfile.mkdtemp(prefix='.portable-candidate-', dir=output.parent))
    try:
        for name, source in files.items():
            target = stage / name
            target.parent.mkdir(parents=True, exist_ok=True)
            # Refuse a source replaced by a symlink after the preflight.
            no_symlink(source.absolute())
            descriptor = os.open(source, os.O_RDONLY | getattr(os, 'O_NOFOLLOW', 0))
            with os.fdopen(descriptor, 'rb') as stream:
                if not stat.S_ISREG(os.fstat(stream.fileno()).st_mode):
                    raise ValueError('candidate input must be a regular file')
                with target.open('xb') as destination:
                    shutil.copyfileobj(stream, destination)
            target.chmod(0o755 if name.endswith('.sh') or name.startswith('bin/') else 0o644)
        metadata = {
            'format': 1,
            'activation': 'persistent-system-next-boot-wireless' if runtime else 'manual',
            'system_changes': 'allowlisted-/system-with-immutable-stock-restore' if runtime else 'none-until-explicit-apply',
            'vehicle_verified': False,
            'structural_patches': ['bt', 'route', 'dipo', 'gpm', 'hotspot'],
            'runtime_hooks': 'persistent-verified-start-without-zygote-restart' if runtime else 'separate-explicit-activation-required',
            'source_revision': git_output('rev-parse', 'HEAD'),
            'source_dirty': bool(git_output('status', '--porcelain')),
            'audio_compatibility': 'reviewed-elf-regions' if 'bin/audio-region-patch' in files else 'legacy-exact-profiles',
        }
        (stage / 'CANDIDATE.json').write_text(json.dumps(metadata, indent=2) + '\n', encoding='utf-8', newline='\n')
        hashes = []
        for path in sorted(stage.rglob('*')):
            if path.is_file():
                hashes.append(hashlib.sha256(path.read_bytes()).hexdigest() + '  ' + path.relative_to(stage).as_posix())
        (stage / 'SHA256SUMS').write_text('\n'.join(hashes) + '\n', encoding='ascii', newline='\n')
        # mkdir reserves the destination without POSIX rename replacing a
        # concurrently created empty directory.
        no_symlink(output)
        for directory in (path for path in stage.rglob('*') if path.is_dir()):
            directory.chmod(0o755)
        output.mkdir(mode=0o755)
        output.chmod(0o755)
        try:
            for child in stage.iterdir():
                child.rename(output / child.name)
            stage.rmdir()
        except BaseException:
            shutil.rmtree(output)
            raise
    except BaseException:
        if stage.exists(): shutil.rmtree(stage)
        raise


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=ROOT / '.build/portable/candidate')
    parser.add_argument('--inputs', type=Path, default=ROOT / '.build/portable')
    parser.add_argument('--build', action='store_true')
    parser.add_argument('--ndk', type=Path)
    parser.add_argument('--runtime', action='store_true', help='include automatic startup and locally probed authored Dalvik adapters')
    args = parser.parse_args()
    if args.build:
        command = [os.sys.executable, str(HERE / 'build.py')]
        if args.ndk:
            command += ['--ndk', str(args.ndk)]
        subprocess.run(command, cwd=ROOT, check=True)
    assemble(args.output, args.inputs, runtime=args.runtime)
    print('Candidate assembled:', args.output)


if __name__ == '__main__':
    main()
