#!/usr/bin/env python3
"""Assemble compiled Linux 3.18 USB WLAN modules and modalias profiles."""
import argparse
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("usb_wifi_targets", HERE / "targets.py")
TARGETS = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(TARGETS)


def module_metadata(path, field):
    result = subprocess.run(["modinfo", "-F", field, str(path)], check=True,
                            text=True, stdout=subprocess.PIPE)
    return [line.strip() for line in result.stdout.splitlines() if line.strip()]


def assemble(module_root: Path, report_path: Path, package: Path, firmware_root: Path,
             extra_module_dir: Path | None = None):
    report = json.loads(report_path.read_text(encoding="utf-8"))
    if report.get("status") != "experimental-build-only":
        raise ValueError("expected the pinned experimental 3.18 build report")
    release_dirs = list((module_root / "lib/modules").iterdir())
    if len(release_dirs) != 1:
        raise ValueError("module root must contain exactly one installed kernel release")
    release = release_dirs[0]
    dep_file = release / "modules.dep"
    alias_file = release / "modules.alias"
    if not dep_file.is_file() or not alias_file.is_file():
        raise ValueError("run depmod on the installed modules before assembly")
    root = release / "kernel"
    deps = {}
    for line in dep_file.read_text(encoding="utf-8").splitlines():
        if ":" not in line:
            continue
        key, values = line.split(":", 1)
        deps[key] = values.split()

    selected = {}
    profiles = []
    ready_profiles = set()
    missing_firmware = set()
    for symbol, item in TARGETS.in_tree_targets().items():
        target = report.get("targets", {}).get(symbol, {})
        if target.get("status") != "compiled":
            continue
        rel = target["modules"][0]["path"]
        target_path = root / rel.removeprefix("drivers/" if rel.startswith("drivers/") else "")
        # Installed module paths are the report's source path beneath kernel/.
        target_path = root / rel
        if not target_path.is_file():
            matches = list(root.rglob(item["module"] + ".ko"))
            if len(matches) != 1:
                raise ValueError(f"compiled target module not found uniquely: {symbol}")
            target_path = matches[0]
        rel_installed = target_path.relative_to(release).as_posix()
        closure = []
        seen = set()

        def visit(module_path):
            if module_path in seen:
                return
            seen.add(module_path)
            for dep in deps.get(module_path, []):
                visit(dep)
            closure.append(module_path)

        visit(rel_installed)
        names = []
        for name in ("ccm", "ctr", "seqiv"):
            crypto_module = release / f"kernel/crypto/{name}.ko"
            if crypto_module.is_file():
                names.append(name)
                selected[crypto_module.name] = crypto_module
        if item["module"] == "ath9k_htc" and extra_module_dir:
            average = extra_module_dir / "gen5w-average.ko"
            if not average.is_file():
                raise ValueError("ath9k_htc requires the gen5w-average helper module")
            selected[average.name] = average
            names.insert(0, "gen5w-average")
        for module_path in closure:
            src = release / module_path
            name = src.name.removesuffix(".ko")
            prior = selected.get(src.name)
            if prior and prior != src:
                raise ValueError(f"module basename collision: {src.name}")
            selected[src.name] = src
            if name not in names:
                names.append(name)
        fw = module_metadata(target_path, "firmware")
        missing = [name for name in fw if not (firmware_root / name).is_file()]
        missing_firmware.update(missing)
        bands = ",".join(sorted(item["bands"])) or "none"
        ap = "yes" if item["ap"] else "no"
        status = "incomplete" if missing else "ready"
        if status == "ready":
            ready_profiles.add(item["module"])
        profiles.append("|".join((item["module"], " ".join(names), " ".join(fw), bands, ap, status)))

    module_dir = package / "files/modules"
    module_dir.mkdir(parents=True, exist_ok=True)
    for path in module_dir.glob("*.ko"):
        path.unlink()
    for name, src in sorted(selected.items()):
        shutil.copyfile(src, module_dir / name)
    (module_dir / "modules.profile").write_text("\n".join(sorted(profiles)) + "\n", encoding="utf-8")

    target_names = {line.split("|", 1)[0] for line in profiles}
    aliases = []
    for line in alias_file.read_text(encoding="utf-8").splitlines():
        parts = line.split()
        if len(parts) == 3 and parts[0] == "alias" and parts[2] in target_names:
            aliases.append(line)
    (module_dir / "modules.alias").write_text("\n".join(sorted(set(aliases))) + "\n", encoding="utf-8")

    firmware_dir = package / "files/firmware"
    firmware_dir.mkdir(parents=True, exist_ok=True)
    for name in sorted({fw for line in profiles for fw in line.split("|")[2].split()}):
        src = firmware_root / name
        if src.is_file():
            dst = firmware_dir / name
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(src, dst)
    return {"compiled_profiles": len(profiles), "modules": len(selected),
            "module_bytes": sum(p.stat().st_size for p in selected.values()),
            "missing_firmware": sorted(missing_firmware), "profiles": sorted(target_names)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--module-root", required=True, type=Path)
    parser.add_argument("--report", required=True, type=Path)
    parser.add_argument("--package", required=True, type=Path)
    parser.add_argument("--firmware-root", required=True, type=Path)
    parser.add_argument("--extra-module-dir", type=Path)
    args = parser.parse_args()
    print(json.dumps(assemble(args.module_root, args.report, args.package,
                              args.firmware_root, args.extra_module_dir), indent=2))


if __name__ == "__main__":
    main()
