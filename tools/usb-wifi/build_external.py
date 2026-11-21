#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only
"""Cross-build the pinned vendor USB WLAN drivers against a prepared 3.18.24 tree.

Run under Linux/WSL after experiment.py. Sources are fetched from the public
repositories at the commits in targets.py. Nothing here touches a vehicle.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess

from targets import LAYOUT_OPTIONS, vendor_targets

VERMAGIC = "3.18.24-tcc SMP preempt mod_unload ARMv7 p2v8 "


def git(directory, *args):
    subprocess.run(["git", "-C", str(directory), *args], check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)


def fetch(item, directory):
    directory.mkdir(parents=True)
    git(directory, "init", "-q")
    git(directory, "fetch", "-q", "--depth", "1", item["repo"], item["commit"])
    git(directory, "checkout", "-q", "FETCH_HEAD")


def apply_fixes(item, directory):
    if item["build"]["patch"]:
        patch = Path(__file__).resolve().parent / "patches" / item["build"]["patch"]
        git(directory, "apply", "--whitespace=nowarn", str(patch))
    for rel, old, new in item["build"]["fixes"]:
        path = directory / rel
        data = path.read_bytes()
        needle = old.encode()
        if data.count(needle) != 1:
            raise ValueError(f"{item['module']}: fix does not match exactly once in {rel}")
        path.write_bytes(data.replace(needle, new.encode()))


def build(item, args, out):
    module = item["module"]
    directory = out / "src" / module
    log = out / "logs" / (module + ".log")
    fetch(item, directory)
    apply_fixes(item, directory)
    options = item["build"]
    command = ["make", f"-j{args.jobs}", "ARCH=arm", "CROSS_COMPILE=" + args.cross,
               "KSRC=" + str(args.tree), "KVER=3.18.24-tcc",
               "USER_EXTRA_CFLAGS=" + options["flags"], "CONFIG_PLATFORM_I386_PC=y",
               "CONFIG_MP_INCLUDED=" + options["mp"], "CONFIG_RTW_DEBUG=" + options["debug"],
               "CONFIG_LOAD_PHY_PARA_FROM_FILE=n", "KBUILD_MODPOST_WARN=1",
               "HOSTCFLAGS=-fcommon", "modules"]
    command[2:2] = list(options["make"])
    if options["rename"]:
        command[2:2] = ["MODULE_NAME=" + module, "USER_MODULE_NAME=" + module]
    with log.open("w") as f:
        result = subprocess.run(command, cwd=directory, stdout=f, stderr=subprocess.STDOUT)
    built = directory / (module + ".ko")
    if result.returncode or not built.is_file():
        raise RuntimeError(f"{module}: build failed, see {log}")
    target = out / "modules" / built.name
    shutil.copyfile(built, target)
    subprocess.run([args.cross + "strip", "--strip-unneeded", str(target)], check=True)
    data = target.read_bytes()
    vermagic = re.search(rb"vermagic=([^\0]+)", data)
    if not vermagic or vermagic[1].decode() != VERMAGIC:
        raise ValueError(f"{module}: unexpected vermagic")
    return module, {"repo": item["repo"], "commit": item["commit"], "bytes": len(data),
                    "sha256": hashlib.sha256(data).hexdigest()}


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--tree", required=True, type=Path, help="prepared Linux 3.18.24 tree")
    ap.add_argument("--cross", required=True, help="toolchain prefix, ending in arm-eabi-")
    ap.add_argument("--output", required=True, type=Path)
    ap.add_argument("--jobs", type=int, default=4)
    args = ap.parse_args()
    args.tree = args.tree.resolve()
    enabled = set(re.findall(r"^(CONFIG_\w+)=", (args.tree / ".config").read_text(), re.M))
    if enabled.intersection(LAYOUT_OPTIONS):
        ap.error("tree enables options the V039 kernel lacks: "
                 + ", ".join(sorted(enabled.intersection(LAYOUT_OPTIONS))))
    out = args.output.resolve()
    repo = Path(__file__).resolve().parents[2]
    if out.is_relative_to(repo) or repo.is_relative_to(out):
        ap.error("output must be outside the authored repository")
    if out.exists():
        ap.error("output must not exist")
    for name in ("src", "logs", "modules"):
        (out / name).mkdir(parents=True)
    items = list(vendor_targets().values())
    with ThreadPoolExecutor(4) as pool:
        futures = [pool.submit(build, item, args, out) for item in items]
    report, failures = {}, []
    for item, future in zip(items, futures):
        try:
            module, entry = future.result()
            report[module] = entry
        except (OSError, RuntimeError, ValueError, subprocess.CalledProcessError) as error:
            failures.append(f"{item['module']}: {error}")
    (out / "build-report.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print(f"built {len(report)} of {len(items)} vendor drivers")
    if failures:
        raise SystemExit("\n".join(failures))


if __name__ == "__main__":
    main()
