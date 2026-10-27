"""Verify authored timer recipes; optional read-only private OEM/ARM checks.

python tests/notice.py [--private-root /private/consent_private]
Patched OEM bytes are created only in an external temporary directory, deleted
on exit. Neither OEM instructions nor files are copied into the repository.
"""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import zlib

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'tools/notice'))
from timer_patch import Dex, make_recipe


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--private-root', type=Path)
    parser.add_argument('--qemu', default='qemu-arm')
    args = parser.parse_args()
    checks = 0
    for version in ('v035', 'v039'):
        recipe = json.loads((ROOT/'tools/notice'/f'{version}.json').read_text())
        assert recipe['stock_delay_ms'] == 10000 and recipe['delay_ms'] == 3000
        assert recipe['patches'][0]['bytes'] == [184, 11]
        assert len(recipe['patches']) == 2 and len(recipe['patches'][1]['bytes']) == 24
        assert recipe['method'].endswith(('dP()V', 'dS()V'))
        checks += 4
        helper = ROOT/'packages/notice-timer/bin'/f'notice-patch-{version}'
        if not args.private_root:
            continue
        private = args.private_root/('v035' if version == 'v035' else '')
        raw = (private/'SystemUI.odex').read_bytes()
        apk = (private/'SystemUI.apk').read_bytes()
        derived, changed = make_recipe(raw, apk)
        assert derived == recipe
        dex = Dex(changed)
        allowed = set(range(recipe['patches'][0]['offset'], recipe['patches'][0]['offset']+2))
        allowed.update(range(dex.base+8, dex.base+32))
        assert len(raw) == len(changed)
        assert all(a == b or i in allowed for i, (a, b) in enumerate(zip(raw, changed)))
        assert changed[dex.base+12:dex.base+32] == hashlib.sha1(changed[dex.base+32:dex.base+dex.length]).digest()
        assert struct.unpack_from('<I', changed, dex.base+8)[0] == zlib.adler32(changed[dex.base+12:dex.base+dex.length]) & 0xffffffff
        deps = struct.unpack_from('<I', raw, 16)[0]
        opt, size = struct.unpack_from('<II', raw, 24)
        assert changed[deps:opt+size] == raw[deps:opt+size]
        assert changed[36:40] == raw[36:40]
        # Thus spec/visibility checks, message dispatch, all other methods and
        # optimized register maps are unchanged, including stock non-auto specs.
        checks += 7
        with tempfile.TemporaryDirectory(prefix='gen5w-notice-private-') as temp:
            source, output = Path(temp)/'original', Path(temp)/'patched'
            source.write_bytes(raw)
            def run(*parts, success=True):
                result = subprocess.run([args.qemu, str(helper), *map(str, parts)], capture_output=True)
                assert (result.returncode == 0) == success, (parts[0], result.returncode)
            run('original', source)
            run('verify', private/'SystemUI.apk', recipe['apk_sha256'])
            run('apply', source, output)
            assert output.read_bytes() == changed
            run('patched', output)
            run('apply', source, output, success=False)
            tampered = bytearray(changed); tampered[-1] ^= 1; output.write_bytes(tampered)
            run('patched', output, success=False)
            output.unlink(); source.write_bytes(b'unknown')
            run('apply', source, output, success=False)
            assert not output.exists()
            checks += 8
    print('PASS notice:', checks, 'recipe/byte-preservation/ARM checks; private inputs:', bool(args.private_root))


if __name__ == '__main__':
    main()
