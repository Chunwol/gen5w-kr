#!/usr/bin/env python3
"""Builds deterministic gen5w.kr.dongle.zip for NEMESIS."""
import hashlib
from pathlib import Path
import zipfile
import sys
import stat

LICENSE_FILES = (
    'GPL-SOURCE.md', 'GPL-2.0.txt', 'ath9k-htc-firmware.txt',
    'linux-firmware-WHENCE', 'usb-wifi-firmware-notices.md',
    'LICENCE.atheros_firmware', 'LICENCE.OLPC', 'LICENCE.ralink-firmware.txt',
    'LICENCE.rtlwifi_firmware.txt',
    'LICENCE.atmel-firmware.txt', 'LICENCE.zd1211-firmware.txt',
)
# Debian open-ath9k-htc-firmware 1.4.0-108-gd856466+dfsg1-1.3+deb12u1
# (htc_9271-1.4.0.fw, htc_7010-1.4.0.fw), unchanged.
FIRMWARE_SHA256 = {
    'htc_9271.fw': '6ce17132c3dda25fa509ac57259d97241137f2a79335b3b23137034442f0aa4e',
    'htc_7010.fw': '3c6515e34e6d622ed195adf359a75a6154946419f7322dadd1771a540b3a8171',
    'atmel_at76c503-i3861.bin': '29cb3ae3f00d53a4256181752d2df45f65a24e922a1e4466e82ed091ca8cfd33',
    'atmel_at76c503-i3863.bin': '12c95a4985294fbf9b5a1c3a128d89879be553a87e9b8e4d179ae2b6dcdc2f55',
    'atmel_at76c503-rfmd-acc.bin': 'bae7cbcb67dcfee4d21d18a1ef8c33dd1b4f3fcfcb71e8b9d3589a1d70b53f33',
    'atmel_at76c503-rfmd.bin': '23e0b1bfc2769dbcd9cb612a09431f52168f3f05294ba3d151bfdc0afb85a039',
    'atmel_at76c505-rfmd.bin': '6babfb9c7fa04de6b8b60c9c26989f5ed6517bdc544d3bcc0fb99a3deac6c743',
    'atmel_at76c505-rfmd2958.bin': '1ad40a7ce3fb3f404b2edf13863ff9996a350d8034029f9a5968c1fcf461ecdd',
    'atmel_at76c505a-rfmd2958.bin': '57c9149c9b3764339c99f741e1e22d6ba7b82d8b03397c5e4ea6f858fad77da9',
    'zd1211/zd1211_ub': '283b2d22a1952cb92ad91b00fc992ef5698ba4a6bdd29040c49385fb14f8e3d7',
    'zd1211/zd1211_uphr': '1fce695719db781e6df983111309284703f96c73896cf092a4b1edbee1611fe5',
    'zd1211/zd1211_ur': '7bd68cb61b503e4c2ce00dedac509c649e8deb5bf47640becef7c0eed6646633',
    'zd1211/zd1211b_ub': 'a4e2bda754923da656881db7498f2e4846cf44b3699a788a373357e049efbbbf',
    'zd1211/zd1211b_uphr': 'c2589e2d761a72a88fda208a255bc9eeb6fab35b9f9127165cfb3290b9ede104',
    'zd1211/zd1211b_ur': '7bd68cb61b503e4c2ce00dedac509c649e8deb5bf47640becef7c0eed6646633',
    # Unchanged from linux-firmware (see usb-wifi-firmware-notices.md).
    'rtlwifi/rtl8188fufw.bin': 'e6189d6d7032b83f0ed4284629c43db66262449a866f33fd329e611239f62e1f',
}

def build_dongle_zip(pkg_dir: Path, out_zip: Path):
    # Verify required driver payloads exist before packaging
    required = [
        pkg_dir / 'files' / 'bcmdhd.ko',
        pkg_dir / 'files' / 'modules' / 'ath9k_htc.ko',
        pkg_dir / 'files' / 'firmware' / 'htc_9271.fw',
    ]
    required += [pkg_dir / 'licenses' / name for name in LICENSE_FILES]
    required += [pkg_dir / 'files' / 'modules' / name
                 for name in ('modules.alias', 'modules.profile')]
    for req in required:
        if not req.is_file():
            raise SystemExit(f'Refused to build dongle package: missing required payload {req}')
    # Firmware payloads are immutable copies pinned by per-file SHA-256 and source/license notices.
    for name, digest in FIRMWARE_SHA256.items():
        firmware_path = pkg_dir / 'files' / 'firmware' / Path(name)
        if not firmware_path.is_file() or hashlib.sha256(firmware_path.read_bytes()).hexdigest() != digest:
            raise SystemExit(f'Refused to build dongle package: firmware {name} is not the recorded Debian build')
    # The stock Wi-Fi HAL is never replaced any more; refuse a stale adapter build.
    if (pkg_dir / 'files' / 'libhardware_legacy.so').exists():
        raise SystemExit('Refused to build dongle package: stale libhardware_legacy.so adapter in payload')
    module_dir = pkg_dir / 'files' / 'modules'
    profiles = set()
    for line in (module_dir / 'modules.profile').read_text(encoding='utf-8').splitlines():
        fields = line.split('|')
        if len(fields) != 6:
            raise SystemExit('Refused to build dongle package: malformed modules.profile')
        driver, modules, firmwares, _bands, _ap, status = fields
        if status not in {'ready', 'incomplete'} or not driver or not modules:
            raise SystemExit('Refused to build dongle package: invalid driver profile')
        if driver in profiles:
            raise SystemExit('Refused to build dongle package: duplicate driver profile')
        profiles.add(driver)
        for module in modules.split():
            if not (module_dir / (module + '.ko')).is_file():
                raise SystemExit(f'Refused to build dongle package: profile {driver} missing module {module}')
        if status == 'ready':
            for firmware in firmwares.split():
                if not (pkg_dir / 'files' / 'firmware' / firmware).is_file():
                    raise SystemExit(f'Refused to build dongle package: profile {driver} missing firmware {firmware}')
    alias_modules = {line.split()[-1] for line in
                     (module_dir / 'modules.alias').read_text(encoding='utf-8').splitlines()
                     if line.split()}
    if not alias_modules or not alias_modules.issubset(profiles):
        raise SystemExit('Refused to build dongle package: USB aliases include unknown profiles')

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
