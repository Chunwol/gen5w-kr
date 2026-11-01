#!/bin/bash
# Rebuilds files/bcmdhd.ko (the stand-in for the stock module name) against the
# prepared V039 kernel tree that tools/usb-wifi/experiment.py creates.
# Usage: build.sh <experiment output dir>   (contains linux-3.18.24/ and toolchain/)
set -euo pipefail
OUT=$(cd "$1" && pwd)
HERE=$(cd "$(dirname "$0")" && pwd)
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
cp "$HERE/bcmdhd.c" "$HERE/Makefile" "$WORK/"
make -C "$OUT/linux-3.18.24" ARCH=arm CROSS_COMPILE="$OUT/toolchain/bin/arm-eabi-" M="$WORK" modules
"$OUT/toolchain/bin/arm-eabi-strip" --strip-debug -o "$HERE/../package/files/bcmdhd.ko" "$WORK/bcmdhd.ko"
grep -qa 'vermagic=3.18.24-tcc SMP preempt mod_unload ARMv7 p2v8 ' "$HERE/../package/files/bcmdhd.ko"
sha256sum "$HERE/../package/files/bcmdhd.ko"
