"""Run the shipped libc-free ARM helper under qemu-arm (Linux/WSL).

The optional private --stock path is only read. Any patched OEM bytes exist
only in a temporary directory outside the repository and are deleted on exit.
"""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--stock', type=Path)
    parser.add_argument('--qemu', default='qemu-arm')
    parser.add_argument('--profile', type=Path, default=ROOT / 'tools/audio/recipe.json')
    parser.add_argument('--helper', type=Path, default=ROOT / 'packages/audio-format/bin/audio-patch')
    args = parser.parse_args()
    helper = args.helper
    elf = helper.read_bytes()
    assert elf[:7] == b'\x7fELF\x01\x01\x01'
    assert struct.unpack_from('<H', elf, 18)[0] == 40, 'not ARM'
    phoff = struct.unpack_from('<I', elf, 28)[0]
    entsize, count = struct.unpack_from('<HH', elf, 42)
    assert all(struct.unpack_from('<I', elf, phoff + i * entsize)[0] not in (2, 3)
               for i in range(count)), 'helper requires dynamic loader/libc'
    checks = 1

    def run(*command, success=True):
        nonlocal checks
        result = subprocess.run([args.qemu, str(helper), *map(str, command)],
                                capture_output=True)
        assert (result.returncode == 0) == success, (command[0], result.returncode)
        checks += 1

    with tempfile.TemporaryDirectory(prefix='gen5w-audio-arm-') as temp:
        source, output = Path(temp) / 'source', Path(temp) / 'result'
        for size in (0, 1, 55, 56, 63, 64, 65, 1024, 4096):
            data = bytes(i % 251 for i in range(size))
            source.write_bytes(data)
            run('verify', source, hashlib.sha256(data).hexdigest())
            run('original', source, success=False)
        run('apply', source, output, success=False)
        assert not output.exists()
        checks += 1
        if args.stock:
            recipe = json.loads(args.profile.read_text())
            before = hashlib.sha256(args.stock.read_bytes()).hexdigest()
            assert before == recipe['original_sha256']
            run('original', args.stock)
            run('apply', args.stock, output)
            assert hashlib.sha256(output.read_bytes()).hexdigest() == recipe['patched_sha256']
            run('patched', output)
            run('original', output, success=False)
            run('apply', args.stock, output, success=False)
            assert hashlib.sha256(args.stock.read_bytes()).hexdigest() == before
            checks += 2
    print('PASS shipped ARM helper checks:', checks, '; private exact recipe:', bool(args.stock))


if __name__ == '__main__':
    main()
