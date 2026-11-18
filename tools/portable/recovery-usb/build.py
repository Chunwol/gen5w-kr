#!/usr/bin/env python3
"""Build an isolated emergency restore archive under .build only."""
from __future__ import annotations

import argparse
import hashlib
import os
from pathlib import Path
import stat
import struct
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
SOURCE = HERE / "restore-usb"
FILES = (
    ("NEMESIS.data", SOURCE / "NEMESIS.data", 0o644),
    ("NEMESIS.emergency", SOURCE / "NEMESIS.emergency", 0o644),
    ("NEMESIS.sh", SOURCE / "NEMESIS.sh", 0o755),
    ("RESTORE-STATUS.txt", SOURCE / "RESTORE-STATUS.txt", 0o644),
    ("restore.sh", HERE / "restore.sh", 0o755),
    ("manifest-format.md", HERE / "manifest-format.md", 0o644),
)


def check_arm_static(path: Path) -> bytes:
    data = path.read_bytes()
    if len(data) < 52 or data[:6] != b"\x7fELF\x01\x01":
        raise ValueError("recovery helper must be ELF32 little-endian")
    if struct.unpack_from("<H", data, 16)[0] != 2 or struct.unpack_from("<H", data, 18)[0] != 40:
        raise ValueError("recovery helper must be an ARM executable")
    phoff = struct.unpack_from("<I", data, 28)[0]
    phentsize, phnum = struct.unpack_from("<HH", data, 42)
    if not phentsize or phoff + phentsize * phnum > len(data):
        raise ValueError("invalid recovery helper program headers")
    if any(struct.unpack_from("<I", data, phoff + n * phentsize)[0] == 3 for n in range(phnum)):
        raise ValueError("recovery helper must be statically linked")
    return data


def zip_info(name: str, mode: int) -> zipfile.ZipInfo:
    info = zipfile.ZipInfo(name, date_time=(2026, 1, 1, 0, 0, 0))
    info.create_system = 3
    info.compress_type = zipfile.ZIP_DEFLATED
    info.external_attr = (stat.S_IFREG | mode) << 16
    return info


def assemble(output: Path, patcher: Path) -> None:
    build_root = (ROOT / ".build").resolve()
    output = output.absolute()
    output_parent = output.parent.resolve()
    if output_parent != build_root and build_root not in output_parent.parents:
        raise ValueError("recovery archive output must be inside .build")
    if output.exists() or output.is_symlink():
        raise FileExistsError(output)
    if output.with_suffix(output.suffix + ".sha256").exists():
        raise FileExistsError(output.with_suffix(output.suffix + ".sha256"))
    if not (SOURCE / "NEMESIS.emergency").is_file() or (SOURCE / "NEMESIS.emergency").stat().st_size:
        raise ValueError("emergency marker must exist and be empty")
    if not patcher.is_file() or patcher.is_symlink():
        raise FileNotFoundError(patcher)

    payload: dict[str, tuple[bytes, int]] = {}
    for name, source, mode in FILES:
        if not source.is_file() or source.is_symlink():
            raise FileNotFoundError(source)
        payload[name] = (source.read_bytes(), mode)
    payload["bin/dex-patch"] = (check_arm_static(patcher), 0o755)
    if payload["NEMESIS.data"][0] != b"[nemesis]\nversion=1.0\ntype=execute\npath=NEMESIS.sh\nid=gen5w.kr.portable.restore\nname=Gen5W Portable Restore Only\ncompat=gen5w\n":
        raise ValueError("unexpected NEMESIS emergency execute descriptor")
    sums = "".join(
        hashlib.sha256(data).hexdigest() + "  " + name + "\n"
        for name, (data, _) in sorted(payload.items())
    ).encode("ascii")
    payload["SHA256SUMS"] = (sums, 0o644)

    output.parent.mkdir(parents=True, exist_ok=True)
    fd, temp_name = tempfile.mkstemp(prefix=".recovery-archive-", dir=output.parent)
    os.close(fd)
    temp = Path(temp_name)
    sidecar = output.with_suffix(output.suffix + ".sha256")
    fd2, sidecar_temp_name = tempfile.mkstemp(prefix=".recovery-sha256-", dir=output.parent)
    os.close(fd2)
    sidecar_temp = Path(sidecar_temp_name)
    created_output = False
    try:
        with zipfile.ZipFile(temp, "w") as archive:
            for name, (data, mode) in sorted(payload.items()):
                archive.writestr(zip_info(name, mode), data)
        archive_hash = hashlib.sha256(temp.read_bytes()).hexdigest()
        sidecar_temp.write_text(archive_hash + "  " + output.name + "\n", encoding="ascii", newline="\n")
        os.link(temp, output)
        created_output = True
        os.link(sidecar_temp, sidecar)
    except BaseException:
        if created_output:
            output.unlink(missing_ok=True)
        raise
    finally:
        temp.unlink(missing_ok=True)
        sidecar_temp.unlink(missing_ok=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path,
                        default=ROOT / ".build/portable-recovery-restore-host-only.zip")
    parser.add_argument("--patcher", type=Path, default=ROOT / ".build/portable/dex-patch")
    args = parser.parse_args()
    assemble(args.output, args.patcher)
    print("Assembled host-only restore archive:", args.output)
    print("Not vehicle-verified; do not use before Android-down dispatch and exact-restore proof.")


if __name__ == "__main__":
    main()
