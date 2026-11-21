#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only
"""Add the built vendor drivers to the package catalog. Safe to run repeatedly."""
import argparse
import importlib.util
from pathlib import Path
import shutil
import struct

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("usb_wifi_targets", HERE / "targets.py")
TARGETS = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(TARGETS)


def modinfo(path):
    """Return {field: [values]} from a 32-bit little-endian module's .modinfo."""
    data = path.read_bytes()
    if data[:6] != b"\x7fELF\x01\x01":
        raise ValueError(f"not a 32-bit little-endian ELF: {path.name}")
    shoff = struct.unpack_from("<I", data, 32)[0]
    entsize, count, names_index = struct.unpack_from("<HHH", data, 46)
    sections = [struct.unpack_from("<10I", data, shoff + i * entsize) for i in range(count)]
    names = sections[names_index]
    for section in sections:
        start = names[4] + section[0]
        if data[start:data.index(b"\0", start)] == b".modinfo":
            fields = {}
            for item in data[section[4]:section[4] + section[5]].split(b"\0"):
                if b"=" in item:
                    key, value = item.decode("utf-8", "replace").split("=", 1)
                    fields.setdefault(key, []).append(value)
            return fields
    raise ValueError(f"no .modinfo section: {path.name}")


def merge(built: Path, package: Path, firmware_root: Path):
    module_dir = package / "files/modules"
    firmware_dir = package / "files/firmware"
    items = TARGETS.vendor_targets().values()
    names = {item["module"] for item in items}
    profile_path = module_dir / "modules.profile"
    alias_path = module_dir / "modules.alias"
    profiles = [line for line in profile_path.read_bytes().decode().splitlines()
                if line.split("|", 1)[0] not in names]
    aliases = [line for line in alias_path.read_bytes().decode().splitlines()
               if line.split()[-1] not in names]
    for item in items:
        module = item["module"]
        source = built / (module + ".ko")
        info = modinfo(source)
        patterns = [value for value in info.get("alias", [])
                    if not value.startswith(tuple(item["drop_aliases"]) or ("\0",))]
        if not patterns:
            raise ValueError(f"{module}: no USB aliases")
        firmware = info.get("firmware", [])
        for name in firmware:
            target = firmware_dir / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(firmware_root / name, target)
        shutil.copyfile(source, module_dir / (module + ".ko"))
        bands = ",".join(sorted(item["bands"]))
        profiles.append("|".join((module, module, " ".join(firmware), bands,
                                  TARGETS.profile_ap(item), "ready")))
        aliases.extend(f"alias {pattern} {module}" for pattern in patterns)
    profile_path.write_bytes(("\n".join(sorted(profiles)) + "\n").encode())
    alias_path.write_bytes(("\n".join(sorted(set(aliases))) + "\n").encode())
    return {"vendor_drivers": len(names), "profiles": len(profiles), "aliases": len(set(aliases))}


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--built", required=True, type=Path, help="build_external.py modules folder")
    ap.add_argument("--package", required=True, type=Path)
    ap.add_argument("--firmware-root", required=True, type=Path)
    args = ap.parse_args()
    print(merge(args.built, args.package, args.firmware_root))


if __name__ == "__main__":
    main()
