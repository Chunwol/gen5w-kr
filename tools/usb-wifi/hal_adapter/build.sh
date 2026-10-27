#!/bin/bash
# Builds ARM libhardware_legacy.so adapter for Gen5W
set -eu
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$SCRIPT_DIR/../../.." && pwd)

NDK_CLANG="/mnt/c/Users/chunwol/AppData/Local/Android/Sdk/ndk/27.2.12479018/toolchains/llvm/prebuilt/windows-x86_64/bin/armv7a-linux-androideabi21-clang.cmd"
SRC="$SCRIPT_DIR/wifi_hal_adapter.c"
OUT_LIB="$SCRIPT_DIR/libhardware_legacy.so"
PKG_FILES="$ROOT/tools/usb-wifi/package/files"

if [ -f "$NDK_CLANG" ]; then
    WIN_NDK=$(wslpath -w "$NDK_CLANG")
    cmd.exe /c "$WIN_NDK" -shared -fPIC -O2 \
        "-Wl,-soname,libhardware_legacy.so" \
        "-Wl,-Bsymbolic" \
        "-Wl,--hash-style=both" \
        -llog -ldl \
        -o "$(wslpath -w "$OUT_LIB")" \
        "$(wslpath -w "$SRC")"
else
    echo "NDK clang not found at $NDK_CLANG"
    exit 1
fi

mkdir -p "$PKG_FILES"
cp "$OUT_LIB" "$PKG_FILES/libhardware_legacy.so"
echo "Built $OUT_LIB successfully"
