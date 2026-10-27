#!/usr/bin/env python3
"""Zip a NEMESIS package folder deterministically: sorted names, fixed dates,
LF line endings checked, .sh files executable. Usage: mkpkg.py <folder> <out.zip>"""
import os
from pathlib import Path
import subprocess
import sys
import zipfile


def main():
    src, out = sys.argv[1], sys.argv[2]
    if not os.path.isfile(os.path.join(src, "NEMESIS.data")):
        sys.exit("no NEMESIS.data in " + src)
    names = []
    for root, dirs, files in os.walk(src):
        # Compile-only declarations and sources never belong in an install ZIP.
        dirs[:] = sorted(d for d in dirs if d not in {"src", "stubs", "test", "build", ".build", "__pycache__"})
        for f in sorted(files):
            p = os.path.join(root, f)
            names.append((os.path.relpath(p, src).replace(os.sep, "/"), p))
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        for rel, p in sorted(names):
            data = open(p, "rb").read()
            if rel.endswith((".sh", ".data", ".xml")) and b"\r\n" in data:
                sys.exit("CRLF line endings in " + rel)
            info = zipfile.ZipInfo(rel, (1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = (0o755 if rel.endswith(".sh") or data.startswith(b"\x7fELF") else 0o644) << 16
            z.writestr(info, data)
        project = Path(__file__).resolve().parents[1]
        for filename in ('LICENSE', 'NOTICE.md', 'SOURCE.md'):
            if filename not in {rel for rel, _ in names} and (project / filename).is_file():
                info = zipfile.ZipInfo(filename, (1980, 1, 1, 0, 0, 0))
                info.external_attr = 0o644 << 16
                info.compress_type = zipfile.ZIP_DEFLATED
                z.writestr(info, (project / filename).read_bytes())
        revision = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=project, text=True).strip()
        info = zipfile.ZipInfo('BUILD-REVISION', (1980, 1, 1, 0, 0, 0))
        info.external_attr = 0o644 << 16
        z.writestr(info, revision + '\n')
    print("wrote %s (%d files)" % (out, len(names)))


if __name__ == "__main__":
    main()
