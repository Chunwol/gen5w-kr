#!/bin/bash
# Private exact-stock end-to-end trial under qemu-arm and the car's mksh.
set -euo pipefail
cd "$(dirname "$0")/.."
if [ -z "${GEN5W_HOTSPOT_STOCK_DIR:-}" ]; then
    echo 'SKIP private local-hotspot install test (stock not supplied)'
    exit 0
fi
fixture=$(mktemp -d /tmp/gen5w-local-hotspot.XXXXXX)
trap 'rm -rf "$fixture"' EXIT
mkdir -p "$fixture/system/app" "$fixture/system/etc" "$fixture/data/dalvik-cache"
cp "$GEN5W_HOTSPOT_STOCK_DIR/HKMC_WifiSettings.odex" "$fixture/system/app/"
cp "$GEN5W_HOTSPOT_STOCK_DIR/HKMC_WifiSettings.apk" "$fixture/system/app/"
helper=$(pwd)/.build/local-hotspot/package/bin/hotspot-patch
printf '#!/bin/sh\nexec qemu-arm "%s" "$@"\n' "$helper" > "$fixture/helper"
printf '#!/bin/sh\nexit 0\n' > "$fixture/nemesis"
chmod 0755 "$fixture/helper" "$fixture/nemesis"
export HOTSPOT_TEST_SYS="$fixture/system" HOTSPOT_TEST_DATA="$fixture/data"
export HOTSPOT_TEST_PATCH="$fixture/helper" HOTSPOT_TEST_NEM="$fixture/nemesis"
run() { mksh tools/local-hotspot/package/scripts/control.sh "$1"; }
target=$fixture/system/app/HKMC_WifiSettings.odex
backup=$fixture/system/etc/gen5w-kr-backup/local-hotspot/original.odex
run check
run install
qemu-arm "$helper" patched "$target"
qemu-arm "$helper" original "$backup"
run install
run remove
cmp "$target" "$GEN5W_HOTSPOT_STOCK_DIR/HKMC_WifiSettings.odex"
run remove
printf x >> "$fixture/system/app/HKMC_WifiSettings.apk"
if run install; then echo 'FAIL: modified APK accepted'; exit 1; fi
cmp "$target" "$GEN5W_HOTSPOT_STOCK_DIR/HKMC_WifiSettings.odex"
cp "$GEN5W_HOTSPOT_STOCK_DIR/HKMC_WifiSettings.apk" "$fixture/system/app/"
run install
mv "$backup" "$backup.saved"
if run install; then echo 'FAIL: patched target without original accepted'; exit 1; fi
mv "$backup.saved" "$backup"
run remove
printf evidence > "$target.localhotspot.tmp"
if run install; then echo 'FAIL: interrupted temporary file overwritten'; exit 1; fi
test "$(cat "$target.localhotspot.tmp")" = evidence
cmp "$target" "$GEN5W_HOTSPOT_STOCK_DIR/HKMC_WifiSettings.odex"
rm "$target.localhotspot.tmp"
mkdir "$fixture/data/nemesis/gen5wkr.localhotspot.lock"
if run install; then echo 'FAIL: concurrent operation accepted'; exit 1; fi
rmdir "$fixture/data/nemesis/gen5wkr.localhotspot.lock"
mv "$target" "$target.saved"
ln -s "$target.saved" "$target"
if run install; then echo 'FAIL: symlink target accepted'; exit 1; fi
rm "$target"
mv "$target.saved" "$target"
cmp "$target" "$GEN5W_HOTSPOT_STOCK_DIR/HKMC_WifiSettings.odex"
echo 'PASS local-hotspot exact ARM install/reinstall/restore/refusal'
