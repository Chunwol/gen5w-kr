#!/usr/bin/env python3
"""Build private experimental modules; never install or package them.

Run under Linux/WSL with Python 3.12+, make, host GCC and libc headers.
All three archives are downloaded separately from their official publishers.
No vehicle access, firmware modification or networking is performed here.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import tarfile
import zipfile

INPUTS = {
    "upstream": "ed54cf8c3ac6b95fc17b07b3a236bc42719c96fee08fe696cabfb5b8e07f8c1b",
    "mobis": "dae5b7e9f1c7d978878dee05a46e3ff4d9406a23bb535842ea63197a018cde44",
    "toolchain": "26219955973c0a270a2fbf2a5b070d4c9d6799b92fb1c32b3ceb44d2a6caca56",
}
VENDOR_ROOT = "AVNT5W_DaudioKK_kerneltcc/"
BASELINE_SHA256 = "c9a0fa793da65bb4b7eaf08f741dd99152cb707a870593151e50f576f8da3b36"
VERMAGIC = "3.18.24-tcc SMP preempt mod_unload ARMv7 p2v8 "
MODULES = [
    "net/mac80211/mac80211.ko", "drivers/net/wireless/ath/ath.ko",
    "drivers/net/wireless/ath/ath9k/ath9k_hw.ko",
    "drivers/net/wireless/ath/ath9k/ath9k_common.ko",
    "drivers/net/wireless/ath/ath9k/ath9k_htc.ko",
    "crypto/ccm.ko", "crypto/ctr.ko", "crypto/seqiv.ko",
]


def digest(path):
    with path.open("rb") as f:
        return hashlib.file_digest(f, "sha256").hexdigest()


def config(path):
    return dict(re.findall(r"^(CONFIG_\w+)=(.*)$", path.read_text(), re.M))


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    for name in (*INPUTS, "config", "output"):
        ap.add_argument("--" + name, required=True, type=Path)
    args = ap.parse_args()
    out = args.output.resolve()
    repo = Path(__file__).resolve().parents[2]
    if out.is_relative_to(repo) or repo.is_relative_to(out):
        ap.error("output must be outside the authored repository")
    if out.exists():
        ap.error("output must not exist; existing experiments are preserved")
    for name, expected in INPUTS.items():
        if digest(getattr(args, name)) != expected:
            ap.error(name + " checksum mismatch")
    if digest(args.config) != BASELINE_SHA256:
        ap.error("config checksum does not match the inspected V039 baseline")
    baseline = config(args.config)
    expected = {"CONFIG_ARCH_TCC897X": "y", "CONFIG_CFG80211": "y",
                "CONFIG_LOCALVERSION": '"-tcc"', "CONFIG_BCMDHD": "m",
                "CONFIG_BCMDHD_SDMMC": "y"}
    if any(baseline.get(k) != v for k, v in expected.items()):
        ap.error("config does not match the inspected TCC897X SDIO baseline")
    out.mkdir(parents=True)
    with tarfile.open(args.upstream) as archive:
        archive.extractall(out, filter="data")
    tree = out / "linux-3.18.24"
    with zipfile.ZipFile(args.mobis) as archive:
        for info in archive.infolist():
            if not info.filename.startswith(VENDOR_ROOT) or info.is_dir():
                continue
            rel = Path(info.filename[len(VENDOR_ROOT):])
            if rel.is_absolute() or ".." in rel.parts:
                raise ValueError("unsafe vendor archive path")
            target = tree / rel
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(archive.read(info))
    toolchain = out / "toolchain"
    toolchain.mkdir()
    with tarfile.open(args.toolchain) as archive:
        archive.extractall(toolchain, filter="data")
    shutil.copyfile(args.config, out / "baseline.config")
    shutil.copyfile(args.config, tree / ".config")

    def run(command, log):
        print(log, flush=True)
        with (out / log).open("w") as f:
            subprocess.run(command, cwd=tree, stdout=f, stderr=subprocess.STDOUT,
                           check=True)

    run(["scripts/config", "--module", "MAC80211", "--enable", "ATH_CARDS",
         "--module", "ATH9K_HTC", "--disable", "RTL_CARDS"], "options.log")
    make = ["make", "-j4", "ARCH=arm", "CROSS_COMPILE=" + str(toolchain / "bin/arm-eabi-"),
            "HOSTCFLAGS=-fcommon"]
    run(make + ["olddefconfig"], "config.log")
    run(make + ["modules_prepare"], "prepare.log")
    average = out / "average"
    average.mkdir()
    shutil.copyfile(tree / "lib/average.c", average / "average.c")
    (average / "Makefile").write_text(
        "obj-m += gen5w-average.o\ngen5w-average-y := average.o metadata.o\n")
    (average / "metadata.c").write_text('#include <linux/module.h>\nMODULE_LICENSE("GPL");\n')
    for directory, log in [(str(average), "average.log"), ("crypto", "crypto.log"),
                           ("net/mac80211", "mac80211.log"),
                           ("drivers/net/wireless/ath", "ath.log")]:
        run(make + ["M=" + directory, "modules"], log)
    paths = [tree / name for name in MODULES] + [average / "gen5w-average.ko"]
    built = {}
    for path in paths:
        data = path.read_bytes()
        match = re.search(rb"vermagic=([^\0]+)", data)
        if not match:
            raise ValueError("module has no vermagic: " + path.name)
        if match[1].decode("ascii") != VERMAGIC:
            raise ValueError("unexpected vermagic: " + path.name)
        built[path.name] = {"sha256": digest(path), "vermagic": match[1].decode("ascii")}
    after = config(tree / ".config")
    changed = {k: [baseline.get(k, "n"), after.get(k, "n")]
               for k in sorted(baseline.keys() | after.keys())
               if baseline.get(k, "n") != after.get(k, "n")}
    report = {"status": "experimental-build-only", "inputs": INPUTS,
              "baseline_sha256": digest(args.config), "config_changes": changed,
              "modules": built, "runtime_validated": False, "oem_hal_integrated": False}
    (out / "build-report.json").write_text(json.dumps(report, indent=2) + "\n")
    print("Compiled 9 experimental modules; no loading, AP or OEM HAL validation.")


if __name__ == "__main__":
    main()
