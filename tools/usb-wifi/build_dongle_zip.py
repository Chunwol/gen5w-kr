#!/usr/bin/env python3
"""Builds deterministic gen5w.kr.dongle.zip for NEMESIS."""
from pathlib import Path
import zipfile
import sys
import stat

def build_dongle_zip(pkg_dir: Path, out_zip: Path):
    # Verify required driver payloads exist before packaging
    required = [
        pkg_dir / 'files' / 'bcmdhd.ko',
        pkg_dir / 'files' / 'modules' / 'ath9k_htc.ko',
        pkg_dir / 'files' / 'firmware' / 'htc_9271.fw',
    ]
    for req in required:
        if not req.is_file():
            raise SystemExit(f'Refused to build dongle package: missing required payload {req}')
    # The stock Wi-Fi HAL is never replaced any more; refuse a stale adapter build.
    if (pkg_dir / 'files' / 'libhardware_legacy.so').exists():
        raise SystemExit('Refused to build dongle package: stale libhardware_legacy.so adapter in payload')

    out_zip.parent.mkdir(parents=True, exist_ok=True)
    if out_zip.exists():
        out_zip.unlink()

    # Fixed timestamp for deterministic zip (2026-01-01 00:00:00)
    fixed_time = (2026, 1, 1, 0, 0, 0)

    files_to_pack = []
    for p in sorted(pkg_dir.rglob('*')):
        if p.is_file() and not p.is_symlink():
            rel = p.relative_to(pkg_dir).as_posix()
            files_to_pack.append((p, rel))

    with zipfile.ZipFile(out_zip, 'w', compression=zipfile.ZIP_STORED) as zf:
        for full_path, rel_path in sorted(files_to_pack, key=lambda x: x[1]):
            data = full_path.read_bytes()
            zinfo = zipfile.ZipInfo(rel_path, date_time=fixed_time)
            # Set permissions: executable if in bin or scripts
            if 'bin/' in rel_path or 'scripts/' in rel_path:
                zinfo.external_attr = (stat.S_IFREG | 0o755) << 16
            else:
                zinfo.external_attr = (stat.S_IFREG | 0o644) << 16
            zf.writestr(zinfo, data)

    print(f"Built {out_zip} ({len(files_to_pack)} files, {out_zip.stat().st_size} bytes)")

if __name__ == '__main__':
    root = Path(__file__).resolve().parent.parent.parent
    pkg = root / 'tools' / 'usb-wifi' / 'package'
    out = root / 'dist' / 'gen5w.kr.dongle.zip'
    build_dongle_zip(pkg, out)
