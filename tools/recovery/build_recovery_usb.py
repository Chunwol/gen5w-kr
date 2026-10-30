#!/usr/bin/env python3
"""Build a non-destructive recovery USB bundle.

The output contains instructions, the read-only fastboot probe, and an example
manifest only.  It intentionally contains no vehicle image, NEMESIS installer,
GEN5W-ACTION file, bootloader, or automatic flash script.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import zipfile
from pathlib import Path


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]


def _readme() -> str:
    return """# Gen5W 부팅 복구 USB (PC 전용)

이 USB는 차량에 꽂아 자동 플래시하는 설치 USB가 아닙니다. 차량이 fastboot 장치로 실제 열거되는지 PC에서 확인하고, 별도로 확보한 순정 이미지의 해시를 검사할 때만 사용합니다.

1. Android platform-tools의 `fastboot`와 Python 3을 PC에 준비합니다.
2. 차량이 fastboot 모드이고 PC의 `fastboot devices`에 나타날 때만 `probe-fastboot.cmd`를 실행합니다.
3. 제품명이 다르거나 장치가 없으면 아무것도 쓰지 않고 종료합니다.
4. 순정 이미지와 SHA-256 매니페스트를 직접 확보한 경우에만 `fastboot_recovery.py flash`의 명시적 확인 절차를 검토합니다.

이 USB에는 제조사 이미지·키·부트로더·modem·MICOM·NEMESIS 설치기가 없습니다. fastboot 열거 자체가 되지 않으면 이 USB만으로 복구할 수 없습니다.
"""


def _launcher() -> str:
    return r'''param(
    [string]$Fastboot = "fastboot.exe",
    [string]$ExpectedProduct = "kona-gen5w"
)
$ErrorActionPreference = "Stop"
$script = Join-Path $PSScriptRoot "fastboot_recovery.py"
if (Get-Command py -ErrorAction SilentlyContinue) {
    & py -3 $script probe --fastboot $Fastboot --expected-product $ExpectedProduct --report (Join-Path $PSScriptRoot "fastboot-report.json")
} elseif (Get-Command python -ErrorAction SilentlyContinue) {
    & python $script probe --fastboot $Fastboot --expected-product $ExpectedProduct --report (Join-Path $PSScriptRoot "fastboot-report.json")
} else {
    throw "Python 3 is required"
}
exit $LASTEXITCODE
'''


def build(output: Path) -> Path:
    if output.exists():
        raise SystemExit(f"output already exists: {output}")
    output.mkdir(parents=True)
    files = {
        "README.md": _readme().encode("utf-8"),
        "NO-AUTO-FLASH.txt": (
            "이 번들은 자동 플래시·차량 설치를 수행하지 않습니다.\n"
            "fastboot 장치 열거와 순정 이미지 해시 확인 전에는 쓰기 명령을 실행하지 마세요.\n"
        ).encode("utf-8"),
        "probe-fastboot.ps1": _launcher().encode("utf-8"),
        "stock-manifest.example.json": json.dumps(
            {
                "product": "kona-gen5w",
                "partitions": [
                    {"name": "boot", "file": "boot.img", "sha256": "64자리 SHA-256"}
                ],
            },
            ensure_ascii=False,
            indent=2,
        ).encode("utf-8")
        + b"\n",
        "fastboot_recovery.py": (HERE / "fastboot_recovery.py").read_bytes(),
    }
    for name, data in files.items():
        path = output / name
        path.write_bytes(data)
    sums = [
        f"{hashlib.sha256(data).hexdigest()}  {name}"
        for name, data in sorted(files.items())
    ]
    (output / "SHA256SUMS").write_text("\n".join(sums) + "\n", encoding="ascii")
    archive = output.with_suffix(".zip")
    with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as zf:
        for path in sorted(output.rglob("*")):
            if path.is_file():
                info = zipfile.ZipInfo(path.relative_to(output).as_posix(), (1980, 1, 1, 0, 0, 0))
                info.external_attr = 0o100644 << 16
                info.compress_type = zipfile.ZIP_DEFLATED
                zf.writestr(info, path.read_bytes())
    return archive


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    print(build(args.output))
