#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only
"""Assemble the GPL source package for the dongle edition's GPL-2.0 binaries.

The dongle ZIP ships nine kernel modules built from Linux 3.18.24 plus the
Mobis Gen5W kernel source, our bcmdhd stand-in module, and the open ath9k_htc
firmware. The package holds what only we can provide: the V039 kernel
configuration, our build scripts and stand-in source, and a README with the
official download addresses and SHA-256 of the third-party archives. We do not
re-host those archives (the Mobis tree also carries Telechips files marked
confidential); the maintainer keeps copies and the written offer covers them.

Run it locally; the kernel configuration is not in the repository.
Output is deterministic.
"""
import argparse
import hashlib
import io
import json
import lzma
from pathlib import Path
import sys
import tarfile

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import experiment  # noqa: E402

STAMP = 1767225600  # 2026-01-01 00:00:00 UTC
FIRMWARE_VERSION = "1.4.0-108-gd856466+dfsg1-1.3+deb12u1"
FIRMWARE = {
    "open-ath9k-htc-firmware_1.4.0-108-gd856466+dfsg1.orig.tar.xz":
        "4cb85451d209ba6da2ce491a79bd039078581a1bcce25bb47a4d3f105639a3dd",
    "open-ath9k-htc-firmware_1.4.0-108-gd856466+dfsg1-1.3+deb12u1.debian.tar.xz":
        "a20d01900ed66bf9448604e22dedbfe0b3201dbeccb32d290a7d765c4db88f8a",
    "open-ath9k-htc-firmware_1.4.0-108-gd856466+dfsg1-1.3+deb12u1.dsc":
        "24bc68a1c686008ae7052e4c3b4ca693a1da8024985cad9384b9c71ddc2f4c5e",
}


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def readme(own):
    i = experiment.INPUTS
    lines = [
        "# Gen5W KR dongle edition: GPL source",
        "",
        "Corresponding source for the GPL-2.0 binaries in `gen5w-kr-dongle.zip`",
        "(files/modules/*.ko, files/bcmdhd.ko) and the source of the ath9k_htc firmware",
        "(files/firmware/htc_9271.fw, htc_7010.fw).",
        "",
        "## In this archive (written by us or specific to this build)",
        "",
    ]
    lines += [f"- `{name}` {digest}" for name, digest in sorted(own.items())]
    lines += [
        "",
        "## Third-party source, from the official publishers",
        "",
        "Download these unchanged files and check their SHA-256:",
        "",
        "- Linux 3.18.24: https://cdn.kernel.org/pub/linux/kernel/v3.x/linux-3.18.24.tar.xz",
        f"  SHA-256 {i['upstream']}",
        "- Hyundai Mobis Gen5W open-source release STD_G5_WIDE R7 (the build uses its",
        "  `AVNT5W_DaudioKK_kerneltcc/` kernel tree):",
        "  https://www.mobis.com/cmm/fms/FileDown.do?fileId=FILE_000000000049653&fileSn=0&fileNm=OSA_202502180203313740.zip",
        f"  SHA-256 {i['mobis']}",
        f"- ath9k_htc firmware source, Debian open-ath9k-htc-firmware {FIRMWARE_VERSION}:",
        "  https://snapshot.debian.org/package/open-ath9k-htc-firmware/1.4.0-108-gd856466%2Bdfsg1-1.3%2Bdeb12u1/",
        "  (also https://deb.debian.org/debian/pool/main/o/open-ath9k-htc-firmware/ while listed;",
        "  upstream https://github.com/qca/open-ath9k-htc-firmware)",
    ]
    lines += [f"  - `{name}` {digest}" for name, digest in FIRMWARE.items()]
    lines += [
        "  The shipped htc_9271.fw / htc_7010.fw are that package's htc_9271-1.4.0.fw /",
        "  htc_7010-1.4.0.fw, unchanged (mostly BSD-3-Clause-Clear; see its debian/copyright).",
        "- Compiler (not part of the GPL source, for reproduction): Android prebuilt arm-eabi-4.8,",
        "  https://android.googlesource.com/platform/prebuilts/gcc/linux-x86/arm/arm-eabi-4.8/+archive/refs/tags/android-6.0.1_r81.tar.gz",
        f"  SHA-256 {i['toolchain']} (googlesource archives may vary; commit 26e93f6af47f7bd3a9beb5c102a5f45e19bfa38a)",
        "",
        "If any of these addresses stops working, ask via https://github.com/Chunwol and we will",
        "provide the same files (written offer, at least three years after the last distribution).",
        "",
        "## Rebuild",
        "",
        "Linux or WSL, Python 3.12+, make, host GCC:",
        "",
        "    python3 build/experiment.py --upstream linux-3.18.24.tar.xz \\",
        "        --mobis <Mobis R7 zip> --toolchain <arm-eabi-4.8 tar.gz> \\",
        "        --config kernel-v039.config --output ~/gen5w-usb-repro",
        "    # then strip each module with arm-eabi-strip --strip-debug",
        "    build/bcmdhd_shim/build.sh ~/gen5w-usb-repro   # stand-in module",
        "",
        "Built in `~/gen5w-usb-repro` and stripped with `--strip-debug`, the nine modules are",
        "byte-identical to the shipped ones (checked 2026-11-02). Elsewhere only the GNU",
        "build-id note (and a source path string in gen5w-average.ko) differ.",
        "",
        "Kernel and modules: GPL-2.0 (some ath files Dual BSD/GPL), text in COPYING.",
        "Stand-in source: GPL-2.0-only. Build scripts: GPL-2.0-only OR GPL-3.0-only.",
        "",
    ]
    return "\n".join(lines).encode()


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--upstream", required=True, type=Path, help="linux-3.18.24.tar.xz (for COPYING)")
    ap.add_argument("--config", required=True, type=Path)
    ap.add_argument("--output", required=True, type=Path)
    args = ap.parse_args()

    if experiment.digest(args.upstream) != experiment.INPUTS["upstream"]:
        ap.error("upstream checksum mismatch")
    files = {}
    with tarfile.open(args.upstream) as t:
        files["COPYING"] = t.extractfile("linux-3.18.24/COPYING").read()
    config = args.config.read_bytes()
    if sha256(config) != experiment.BASELINE_SHA256:
        ap.error("config checksum mismatch")
    files["kernel-v039.config"] = config
    files["build/experiment.py"] = (HERE / "experiment.py").read_bytes()
    for name in ("bcmdhd.c", "Makefile", "build.sh"):
        files["build/bcmdhd_shim/" + name] = (HERE / "bcmdhd_shim" / name).read_bytes()
    files["README.md"] = readme({n: sha256(d) for n, d in files.items()})

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
    print(json.dumps({"output": str(args.output), "sha256": sha256(data), "bytes": len(data)}, indent=2))


if __name__ == "__main__":
    main()
