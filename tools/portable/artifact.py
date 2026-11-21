"""Audit and archive the authored portable package, without private build inputs."""
import argparse
import configparser
import hashlib
from io import BytesIO
import json
from pathlib import Path, PurePosixPath
import re
import struct
import zipfile


def dex(data, fixtures=False):
    assert data[:8] == b'dex\n035\0', 'expected API19 DEX035'
    count, off = struct.unpack_from('<II', data, 56)
    strings = []
    for i in range(count):
        pos = struct.unpack_from('<I', data, off + i*4)[0]
        while data[pos] & 128: pos += 1
        pos += 1
        strings.append(data[pos:data.index(0, pos)].decode('utf-8', errors='strict'))
    count, off = struct.unpack_from('<II', data, 64)
    types = [strings[struct.unpack_from('<I', data, off+i*4)[0]] for i in range(count)]
    count, off = struct.unpack_from('<II', data, 96)
    assert count, 'empty implementation'
    for i in range(count):
        name = types[struct.unpack_from('<I', data, off+i*32)[0]]
        assert name.startswith('Lkr/gen5w/') or (fixtures and re.fullmatch(
            r'L(?:Hook|Loader|Bootstrap|AdapterDiscovery|BootPath)VmTest(?:\$[^/;]+)?;', name)), 'foreign class: '+name


def elf(data, shared=False):
    assert data[:6] == b'\x7fELF\x01\x01', 'expected little-endian ELF32'
    kind, machine = struct.unpack_from('<HH', data, 16)
    assert machine == 40 and kind == (3 if shared else 2), 'wrong ARM ELF type'
    off = struct.unpack_from('<I', data, 28)[0]
    size, count = struct.unpack_from('<HH', data, 42)
    programs = [struct.unpack_from('<I', data, off+i*size)[0] for i in range(count)]
    assert 3 not in programs, 'unexpected dynamic interpreter'
    if not shared:
        assert 2 not in programs, 'helper must be freestanding'
        return
    off = struct.unpack_from('<I', data, 32)[0]
    size, count = struct.unpack_from('<HH', data, 46)
    sections = [struct.unpack_from('<10I', data, off+i*size) for i in range(count)]
    needed = set()
    for section in sections:
        if section[1] != 6: continue
        strings = sections[section[6]]
        for pos in range(section[4], section[4]+section[5], section[9]):
            tag, value = struct.unpack_from('<II', data, pos)
            if tag == 1:
                start = strings[4]+value
                needed.add(data[start:data.index(0, start)].decode('ascii'))
    assert needed == {'libc.so', 'libdl.so'}, 'unexpected native dependency: '+str(needed)


def audit(files):
    assert files and all(PurePosixPath(n).as_posix() == n and not n.startswith('/')
                         and '..' not in PurePosixPath(n).parts for n in files), 'unsafe archive name'
    hashes = {}
    for line in files['SHA256SUMS'].decode('ascii').splitlines():
        digest, name = line.split('  ', 1)
        assert re.fullmatch('[a-f0-9]{64}', digest) and name not in hashes, 'invalid hash member'
        hashes[name] = digest
    assert set(hashes) == set(files)-{'SHA256SUMS'}, 'unhashed or absent member'
    assert all(hashlib.sha256(files[n]).hexdigest() == h for n, h in hashes.items()), 'checksum differs'
    allowed = {'CANDIDATE.json', 'SHA256SUMS', 'LICENSE', 'README.md', 'NOTICE.md', 'SOURCE.md',
               'NEMESIS.data', 'bin/dex-patch', 'bin/audio-patch', 'bin/audio-patch-v035', 'bin/audio-region-patch',
               'audio/recipe.sh', 'audio/recipe-v035.sh', 'app/bridge.dex',
               'app/wireless-host.apk', 'app/gen5w-core.apk', 'dalvik/engine.jar',
               'dalvik/adapter.jar', 'dalvik/hook-vm-test.jar', 'dalvik/libgen5whook.so', 'dalvik/abi.sha256'}
    allowed.update(n+'.sh' for n in ('prepare', 'overlay', 'portable', 'check', 'runtime', 'ap', 'framework', 'persistent-migrate', 'persistent-start', 'wrap-dipo',
                   'wrap-gpm', 'wrap-common', 'wrap-probe', 'session', 'diagnostics', 'debug', 'ui', 'boot', 'rescue', 'rescue-watch', 'bootguard', 'bootguard-restore', 'state-reset',
                   'package-pre', 'package-post', 'package-preun', 'service', 'wifi-backend', 'dongle'))
    allowed.update('permissions/'+n+'.xml' for n in ('com.hkmc.software.connectivity.carplay_wireless',
                   'com.hkmc.software.connectivity.androidauto_wireless', 'com.hkmc.software.wifihotspot'))
    allowed.update('timer/'+n+'.sh' for n in ('common', 'errors', 'install-hold', 'timer'))
    allowed.update('bluelink/'+n+'.sh' for n in ('common', 'errors', 'install-hold', 'quiet', 'post', 'preun'))
    allowed.add('bin/sha256-check')
    required = allowed - {'bin/audio-patch', 'bin/audio-patch-v035', 'bin/audio-region-patch', 'audio/recipe.sh', 'audio/recipe-v035.sh', 'bin/sha256-check'}
    assert required <= set(files), 'missing package member: '+str(required-set(files))
    # USB Wi-Fi dongle payload: a fixed set of names under dongle/ only.
    dongle = {n for n in files if n.startswith('dongle/')}
    assert 'dongle/bcmdhd.ko' in dongle and 'dongle/modules/modules.alias' in dongle and 'dongle/modules/modules.profile' in dongle, 'dongle payload missing'
    assert {'dongle/licenses/GPL-2.0.txt', 'dongle/licenses/GPL-SOURCE.md', 'dongle/licenses/usb-wifi-firmware-notices.md'} <= dongle, 'dongle licences missing'
    for n in dongle:
        assert re.fullmatch(r'dongle/(bcmdhd\.ko|modules/[A-Za-z0-9_-]+\.ko|modules/modules\.(alias|profile)|licenses/[A-Za-z0-9_.-]+|firmware/[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)?)', n), 'unexpected dongle member: '+n
        if n.endswith('.ko'): assert files[n][:4] == b'\x7fELF', 'dongle module is not ELF: '+n
    allowed.update(dongle)
    assert set(files) <= allowed, 'unexpected shipped files: '+str(set(files)-allowed)
    meta = configparser.ConfigParser(interpolation=None)
    meta.read_string(files['NEMESIS.data'].decode('utf-8'))
    assert meta['nemesis']['id'] == 'gen5w.kr.portable'
    for key in ('preinstall', 'postinstall', 'preuninstall'):
        assert meta['nemesis'][key] in files, 'missing install hook'
    assert meta['service.1']['path'] == 'ui.sh' and meta['service.1']['uid'] == 'root'
    info = json.loads(files['CANDIDATE.json'])
    assert info['vehicle_verified'] is False and re.fullmatch('[a-f0-9]{40}', info['source_revision'])
    assert info['activation'] == 'persistent-system-next-boot-wireless'
    assert info['system_changes'] == 'allowlisted-/system-with-immutable-stock-restore'
    assert info['runtime_hooks'] == 'persistent-verified-start-without-zygote-restart'
    assert meta['service.2']['path'] == 'rescue-watch.sh' and meta['service.2']['mode'] == 'restart'
    assert meta['service.3']['path'] == 'debug.sh' and meta['service.3']['uid'] == 'root'
    assert meta['service.4']['path'] == 'timer/timer.sh' and meta['service.4']['uid'] == 'root'
    assert meta['service.5']['path'] == 'bluelink/quiet.sh' and meta['service.5']['uid'] == 'system'
    assert meta['service.6']['path'] == 'dongle.sh' and meta['service.6']['uid'] == 'root' and meta['service.6']['mode'] == 'background'
    assert files.get('bin/sha256-check', b'') == files.get('bin/audio-patch', b''), 'timer helper differs from the audio helper'
    for name, data in files.items():
        if name.endswith(('.sh', '.data', '.xml')): assert b'\r' not in data, 'CRLF: '+name
        if name.startswith('bin/') or name.endswith('.so'): elf(data, shared=name.endswith('.so'))
        if name.endswith('.dex'): dex(data)
        if name.endswith(('.apk', '.jar')):
            with zipfile.ZipFile(BytesIO(data)) as z:
                assert z.testzip() is None
                dex(z.read('classes.dex'), fixtures=name.endswith('hook-vm-test.jar'))
    assert re.fullmatch(b'[a-f0-9]{64}\n', files['dalvik/abi.sha256'])
    return len(files)


def read_directory(root):
    root = root.absolute()
    assert all(not p.is_symlink() for p in (root, *root.parents)), 'symlink input'
    paths = list(root.rglob('*'))
    assert all(not p.is_symlink() for p in paths), 'symlink member'
    return {p.relative_to(root).as_posix(): p.read_bytes() for p in paths if p.is_file()}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('candidate', type=Path)
    p.add_argument('--zip', type=Path)
    args = p.parse_args()
    files = read_directory(args.candidate)
    count = audit(files)
    if args.zip:
        assert all(not part.is_symlink() for part in (args.zip.absolute(), *args.zip.absolute().parents)), 'symlink output'
        with zipfile.ZipFile(args.zip, 'x', zipfile.ZIP_DEFLATED) as z:
            for name, data in sorted(files.items()):
                info = zipfile.ZipInfo(name, (1980, 1, 1, 0, 0, 0))
                info.compress_type = zipfile.ZIP_DEFLATED
                info.external_attr = (0o755 if name.endswith('.sh') or data.startswith(b'\x7fELF') else 0o644) << 16
                z.writestr(info, data)
        with zipfile.ZipFile(args.zip) as z:
            assert z.testzip() is None
            audit({n: z.read(n) for n in z.namelist()})
        print('ZIP SHA256', hashlib.sha256(args.zip.read_bytes()).hexdigest())
    print('AUDITED', count, 'authored portable files; vehicle verification pending')


if __name__ == '__main__': main()
