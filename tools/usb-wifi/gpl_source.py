#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only
"""Assemble the corresponding source for the dongle edition's GPL-2.0 binaries.

The dongle ZIP ships nine kernel modules built from Linux 3.18.24 plus the
Mobis Gen5W kernel source, the bcmdhd stand-in module, and the open
ath9k_htc firmware. GPL-2.0 section 3 asks for the complete source of those
binaries, including the kernel configuration and the build scripts. This
script packs exactly the inputs that rebuild them (checked byte-for-byte):

  linux-3.18.24.tar.xz               kernel.org upstream, unchanged
  mobis-r7-kernel.zip                the kernel part of the Mobis R7 archive, unchanged files
  kernel-v039.config                 the V039 kernel configuration (from the unit's kernel)
  build/experiment.py, build/bcmdhd_shim/*   our build scripts and stand-in source
  firmware/open-ath9k-htc-firmware_*  Debian source of the shipped firmware
  COPYING                            GPL-2.0 text from the kernel source

Run it locally; the inputs are not in the repository. Output is deterministic.
"""
import argparse
import hashlib
import io
import json
import lzma
from pathlib import Path
import sys
import tarfile
import zipfile

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import experiment  # noqa: E402

FIRMWARE = {
    "open-ath9k-htc-firmware_1.4.0-108-gd856466+dfsg1.orig.tar.xz":
        "4cb85451d209ba6da2ce491a79bd039078581a1bcce25bb47a4d3f105639a3dd",
    "open-ath9k-htc-firmware_1.4.0-108-gd856466+dfsg1-1.3+deb12u1.debian.tar.xz":
        "a20d01900ed66bf9448604e22dedbfe0b3201dbeccb32d290a7d765c4db88f8a",
    "open-ath9k-htc-firmware_1.4.0-108-gd856466+dfsg1-1.3+deb12u1.dsc":
        "24bc68a1c686008ae7052e4c3b4ca693a1da8024985cad9384b9c71ddc2f4c5e",
}
FIRMWARE_URL = "https://deb.debian.org/debian/pool/main/o/open-ath9k-htc-firmware/"
STAMP = 1767225600  # 2026-01-01 00:00:00 UTC


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def mobis_subset(path):
    """Copy the kernel part of the Mobis archive into a stored (uncompressed) ZIP.

    Stored entries with fixed metadata make the result identical on any machine,
    so experiment.py can pin its hash.
    """
    out = io.BytesIO()
    with zipfile.ZipFile(path) as src, zipfile.ZipFile(out, "w", zipfile.ZIP_STORED) as dst:
        for info in sorted(src.infolist(), key=lambda i: i.filename):
            if not info.filename.startswith(experiment.VENDOR_ROOT) or info.is_dir():
                continue
            new = zipfile.ZipInfo(info.filename, date_time=(2026, 1, 1, 0, 0, 0))
            new.external_attr = info.external_attr
            new.create_system = 3
            dst.writestr(new, src.read(info))
    return out.getvalue()


def readme(hashes):
    lines = [
        "# Gen5W KR dongle edition: GPL corresponding source",
        "",
        "This archive is the complete corresponding source for the GPL-2.0 binaries in",
        "`gen5w-kr-dongle.zip` (files/modules/*.ko, files/bcmdhd.ko) and the source of the",
        "ath9k_htc firmware (files/firmware/htc_9271.fw, htc_7010.fw).",
        "",
        "## Contents and SHA-256",
        "",
    ]
    lines += [f"- `{name}` {digest}" for name, digest in sorted(hashes.items())]
    lines += [
        "",
        "## Origin",
        "",
        "- Linux 3.18.24: https://cdn.kernel.org/pub/linux/kernel/v3.x/linux-3.18.24.tar.xz",
        "- Mobis Gen5W kernel source: the `AVNT5W_DaudioKK_kerneltcc/` part of the Hyundai Mobis",
        f"  open-source release STD_G5_WIDE R7 (full archive SHA-256 {experiment.INPUTS['mobis']}),",
        "  files unchanged.",
        "- kernel-v039.config: the configuration built into the V039 head-unit kernel (IKCONFIG).",
        "- Firmware: Debian package open-ath9k-htc-firmware 1.4.0-108-gd856466+dfsg1-1.3+deb12u1,",
        f"  {FIRMWARE_URL}. The shipped htc_9271.fw / htc_7010.fw are that package's",
        "  htc_9271-1.4.0.fw / htc_7010-1.4.0.fw, unchanged. Licence: see the package's",
        "  debian/copyright (mostly BSD-3-Clause-Clear).",
        "",
        "## Rebuild",
        "",
        "Linux or WSL, Python 3.12+, make, host GCC. Compiler: the Android prebuilt",
        "arm-eabi-4.8 (android-6.0.1_r81,",
        "https://android.googlesource.com/platform/prebuilts/gcc/linux-x86/arm/arm-eabi-4.8/+archive/refs/tags/android-6.0.1_r81.tar.gz,",
        f"SHA-256 {experiment.INPUTS['toolchain']}).",
        "",
        "    python3 build/experiment.py --upstream linux-3.18.24.tar.xz \\",
        "        --mobis mobis-r7-kernel.zip --toolchain <arm-eabi-4.8 tar.gz> \\",
        "        --config kernel-v039.config --output ~/gen5w-usb-repro",
        "    # modules: strip with arm-eabi-strip --strip-debug",
        "    build/bcmdhd_shim/build.sh ~/gen5w-usb-repro   # stand-in module",
        "",
        "Built in `~/gen5w-usb-repro` and stripped with `--strip-debug`, the nine modules are",
        "byte-identical to the shipped ones. In another directory only the GNU build-id",
        "note (and a source path string in gen5w-average.ko) differ.",
        "",
        "The kernel and modules are GPL-2.0 (some ath files: Dual BSD/GPL); see COPYING.",
        "Our build scripts are GPL-2.0-only OR GPL-3.0-only; the stand-in source is GPL-2.0-only.",
        "",
    ]
    return "\n".join(lines).encode()


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--upstream", required=True, type=Path)
    ap.add_argument("--mobis", required=True, type=Path)
    ap.add_argument("--config", required=True, type=Path)
    ap.add_argument("--firmware-dir", required=True, type=Path)
    ap.add_argument("--output", required=True, type=Path)
    args = ap.parse_args()

    files = {}
    upstream = args.upstream.read_bytes()
    if sha256(upstream) != experiment.INPUTS["upstream"]:
        ap.error("upstream checksum mismatch")
    files["linux-3.18.24.tar.xz"] = upstream
    with tarfile.open(args.upstream) as t:
        files["COPYING"] = t.extractfile("linux-3.18.24/COPYING").read()
    if experiment.digest(args.mobis) != experiment.INPUTS["mobis"]:
        ap.error("mobis checksum mismatch")
    files["mobis-r7-kernel.zip"] = mobis_subset(args.mobis)
    if experiment.MOBIS_SUBSET and sha256(files["mobis-r7-kernel.zip"]) != experiment.MOBIS_SUBSET:
        ap.error("mobis subset differs from the hash pinned in experiment.py")
    config = args.config.read_bytes()
    if sha256(config) != experiment.BASELINE_SHA256:
        ap.error("config checksum mismatch")
    files["kernel-v039.config"] = config
    files["build/experiment.py"] = (HERE / "experiment.py").read_bytes()
    for name in ("bcmdhd.c", "Makefile", "build.sh"):
        files["build/bcmdhd_shim/" + name] = (HERE / "bcmdhd_shim" / name).read_bytes()
    for name, digest in FIRMWARE.items():
        data = (args.firmware_dir / name).read_bytes()
        if sha256(data) != digest:
            ap.error("firmware source checksum mismatch: " + name)
        files["firmware/" + name] = data

    hashes = {name: sha256(data) for name, data in files.items()}
    files["README.md"] = readme(hashes)

    raw = io.BytesIO()
    with tarfile.open(fileobj=raw, mode="w", format=tarfile.USTAR_FORMAT) as tar:
        for name in sorted(files):
            info = tarfile.TarInfo("gen5w-kr-dongle-gpl-source/" + name)
            info.size = len(files[name])
            info.mtime = STAMP
            info.mode = 0o755 if name.endswith((".py", ".sh")) else 0o644
            info.uid = info.gid = 0
            info.uname = info.gname = "root"
            tar.addfile(info, io.BytesIO(files[name]))
    data = lzma.compress(raw.getvalue(), preset=6)
    args.output.write_bytes(data)
    print(json.dumps({"output": str(args.output), "sha256": sha256(data),
                      "mobis_subset_sha256": hashes["mobis-r7-kernel.zip"]}, indent=2))


if __name__ == "__main__":
    main()
