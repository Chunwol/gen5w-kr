#!/usr/bin/env python3
"""Build the separate opt-in USB kit for the Bluelink reminder package.
Usage: bluelink-kit.py <gen5w.kr.bluelink.zip> <out.zip>"""
from pathlib import Path
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def add(z, name, data):
    info = zipfile.ZipInfo(name, (1980, 1, 1, 0, 0, 0))
    info.compress_type = zipfile.ZIP_DEFLATED
    info.external_attr = 0o644 << 16
    z.writestr(info, data)


def main():
    package, out = Path(sys.argv[1]), Path(sys.argv[2])
    with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
        add(z, 'NEMESIS.data', (ROOT / 'tools/bluelink-usb/NEMESIS.data').read_bytes())
        add(z, 'packages/gen5w.kr.bluelink.zip', package.read_bytes())
        add(z, 'docs/bluelink.md', (ROOT / 'docs/bluelink.md').read_bytes())
        for name in ('LICENSE', 'NOTICE.md', 'SOURCE.md'):
            if (ROOT / name).is_file():
                add(z, name, (ROOT / name).read_bytes())
        add(z, 'BUILD-REVISION', zipfile.ZipFile(package).read('BUILD-REVISION'))


if __name__ == '__main__':
    main()
