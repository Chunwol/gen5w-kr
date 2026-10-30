#!/usr/bin/env python3
"""Conservative, host-side fastboot recovery helper.

The repository deliberately contains no vehicle images.  Images and the
manifest are supplied separately by the operator and are verified before a
write is even planned.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path
from typing import Callable, Iterable, Mapping, Sequence


ALLOWED_PARTITIONS = frozenset({"boot", "system", "recovery", "dtb"})
_SHA256 = re.compile(r"^[0-9a-fA-F]{64}$")
_Runner = Callable[..., subprocess.CompletedProcess[str]]


class RecoveryError(RuntimeError):
    """Raised when a recovery precondition is not met."""


def parse_fastboot_vars(text: str) -> dict[str, str]:
    """Parse ``fastboot getvar`` output from either stdout or stderr."""

    result: dict[str, str] = {}
    for raw in text.splitlines():
        line = raw.strip()
        if line.startswith("(bootloader)"):
            line = line[len("(bootloader)") :].strip()
        if not line or line.startswith("Finished") or line.startswith("FAILED"):
            continue
        if ":" not in line:
            continue
        key, value = line.split(":", 1)
        key = key.strip()
        value = value.strip()
        if key:
            result[key] = value
    return result


def _safe_image_path(root: Path, relative: object) -> Path:
    if not isinstance(relative, str) or not relative:
        raise RecoveryError("manifest image path is empty")
    path = Path(relative)
    if path.is_absolute() or any(part == ".." for part in path.parts):
        raise RecoveryError(f"unsafe image path: {relative}")
    if root.is_symlink():
        raise RecoveryError("image root must not be a symlink")
    candidate = root / path
    probe = candidate
    while probe != root:
        if probe.is_symlink():
            raise RecoveryError(f"image path contains a symlink: {relative}")
        probe = probe.parent
    try:
        resolved_root = root.resolve(strict=True)
        resolved = candidate.resolve(strict=True)
    except OSError as exc:
        raise RecoveryError(f"image is not readable: {relative}") from exc
    try:
        resolved.relative_to(resolved_root)
    except ValueError as exc:
        raise RecoveryError(f"image escapes root: {relative}") from exc
    if not candidate.is_file():
        raise RecoveryError(f"image is not a regular file: {relative}")
    return candidate


def validate_manifest(
    manifest_path: Path | str, images_root: Path | str, *, expected_product: str
) -> list[tuple[str, Path]]:
    """Validate an external stock manifest and return safe image paths."""

    manifest = Path(manifest_path)
    root = Path(images_root)
    if manifest.is_symlink() or not manifest.is_file():
        raise RecoveryError("manifest must be a regular file")
    try:
        data = json.loads(manifest.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise RecoveryError("invalid manifest") from exc
    if not isinstance(data, dict) or data.get("product") != expected_product:
        raise RecoveryError("manifest product does not match expected product")
    partitions = data.get("partitions")
    if not isinstance(partitions, list) or not partitions:
        raise RecoveryError("manifest has no partitions")

    result: list[tuple[str, Path]] = []
    seen: set[str] = set()
    for entry in partitions:
        if not isinstance(entry, dict):
            raise RecoveryError("invalid partition entry")
        name = entry.get("name")
        if not isinstance(name, str) or name not in ALLOWED_PARTITIONS:
            raise RecoveryError(f"partition is not allowlisted: {name}")
        if name in seen:
            raise RecoveryError(f"duplicate partition: {name}")
        seen.add(name)
        digest = entry.get("sha256")
        if not isinstance(digest, str) or not _SHA256.fullmatch(digest):
            raise RecoveryError(f"invalid sha256 for {name}")
        image = _safe_image_path(root, entry.get("file"))
        actual = hashlib.sha256(image.read_bytes()).hexdigest()
        if actual.lower() != digest.lower():
            raise RecoveryError(f"sha256 mismatch for {name}")
        result.append((name, image))
    return result


def build_flash_plan(
    fastboot_vars: Mapping[str, str],
    manifest_path: Path | str,
    images_root: Path | str,
    *,
    expected_product: str,
) -> list[list[str]]:
    """Build commands without executing them; every target is allowlisted."""

    if fastboot_vars.get("product") != expected_product:
        raise RecoveryError("connected product does not match expected product")
    entries = validate_manifest(
        manifest_path, images_root, expected_product=expected_product
    )
    return [["flash", name, str(image)] for name, image in entries]


def _run(
    fastboot_exe: Path | str,
    args: Sequence[str],
    *,
    runner: _Runner = subprocess.run,
) -> subprocess.CompletedProcess[str]:
    try:
        return runner(
            [str(fastboot_exe), *args],
            capture_output=True,
            text=True,
            check=False,
        )
    except OSError as exc:
        raise RecoveryError(f"cannot run fastboot: {exc}") from exc


def probe_fastboot(
    fastboot_exe: Path | str,
    *,
    expected_product: str,
    runner: _Runner = subprocess.run,
) -> dict[str, object]:
    """Read-only device/product probe.  No flash command is issued."""

    devices = _run(fastboot_exe, ["devices"], runner=runner)
    if devices.returncode != 0:
        raise RecoveryError("fastboot devices failed")
    device_lines = [line for line in devices.stdout.splitlines() if line.strip()]
    if not device_lines:
        raise RecoveryError("no fastboot device enumerated")

    getvar = _run(fastboot_exe, ["getvar", "product"], runner=runner)
    variables = parse_fastboot_vars(getvar.stdout + "\n" + getvar.stderr)
    if variables.get("product") != expected_product:
        raise RecoveryError("connected product does not match expected product")
    return {
        "product": variables["product"],
        "device_count": len(device_lines),
        "version_bootloader": variables.get("version-bootloader", ""),
        "read_only": True,
    }


def run_probe(
    fastboot_exe: Path | str,
    expected_product: str,
    *,
    runner: _Runner = subprocess.run,
) -> dict[str, object]:
    """Compatibility wrapper with a short name for callers and scripts."""

    return probe_fastboot(
        fastboot_exe, expected_product=expected_product, runner=runner
    )


def flash_stock(
    fastboot_exe: Path | str,
    manifest_path: Path | str,
    images_root: Path | str,
    *,
    expected_product: str,
    confirm_stock: bool = False,
    no_reboot: bool = False,
    runner: _Runner = subprocess.run,
) -> dict[str, object]:
    """Flash only verified allowlisted stock partitions after explicit consent."""

    if not confirm_stock:
        raise RecoveryError("refusing to flash without --confirm-stock")
    report = probe_fastboot(
        fastboot_exe, expected_product=expected_product, runner=runner
    )
    variables = {"product": str(report["product"])}
    plan = build_flash_plan(
        variables,
        manifest_path,
        images_root,
        expected_product=expected_product,
    )
    for command in plan:
        result = _run(fastboot_exe, command, runner=runner)
        if result.returncode != 0:
            raise RecoveryError(f"fastboot command failed: {command[0]} {command[1]}")
    if not no_reboot:
        result = _run(fastboot_exe, ["reboot"], runner=runner)
        if result.returncode != 0:
            raise RecoveryError("fastboot reboot failed")
    return {**report, "read_only": False, "flashed": [command[1] for command in plan]}


def _write_report(report: Mapping[str, object], path: str | None) -> None:
    text = json.dumps(report, ensure_ascii=False, indent=2) + "\n"
    if path:
        Path(path).write_text(text, encoding="utf-8")
    else:
        print(text, end="")


def main(argv: Iterable[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--fastboot", required=True, help="fastboot executable")
    common.add_argument("--expected-product", required=True)
    common.add_argument("--report")
    sub.add_parser("probe", parents=[common], help="read-only fastboot probe")
    flash = sub.add_parser("flash", parents=[common], help="explicit stock recovery")
    flash.add_argument("--manifest", required=True)
    flash.add_argument("--images-root", required=True)
    flash.add_argument("--confirm-stock", action="store_true")
    flash.add_argument("--no-reboot", action="store_true")
    args = parser.parse_args(list(argv) if argv is not None else None)
    try:
        if args.command == "probe":
            report = probe_fastboot(args.fastboot, expected_product=args.expected_product)
        else:
            report = flash_stock(
                args.fastboot,
                args.manifest,
                args.images_root,
                expected_product=args.expected_product,
                confirm_stock=args.confirm_stock,
                no_reboot=args.no_reboot,
            )
        _write_report(report, args.report)
        return 0
    except RecoveryError as exc:
        print(f"recovery refused: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
