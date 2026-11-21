#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
t=$(mktemp -d /tmp/g5diag.XXXXXX); trap 'rc=$?; rm -rf "$t"; exit $rc' EXIT
R=$t/root; B=$R/data/bundle
mkdir -p "$B/bin" "$R/data/local/gen5w-portable/boot" "$R/proc/sys/kernel/random" "$R/data/nemesis/gen5wkr.ui" "$t/bin"
cp tools/portable/diagnostics.sh "$B/"
cp .build/portable/dex-patch-host "$B/bin/dex-patch"
echo fixture-boot > "$R/proc/sys/kernel/random/boot_id"
echo '100 50' > "$R/proc/uptime"
echo 'worker=owner exit=23' > "$R/data/local/gen5w-portable/boot/health-lost"
echo details > "$R/data/nemesis/gen5wkr.ui/diag-latest.txt"
# USB Wi-Fi dongle evidence.
echo dongle > "$R/data/local/gen5w-portable/wifi-backend"
mkdir -p "$R/data/local/gen5w-portable/dongle" "$R/data/nemesis/logs/gen5w.kr.portable" "$R/sys/module/firmware_class/parameters" "$R/sys/bus/usb/devices/1-1"
echo blocked > "$R/data/local/gen5w-portable/dongle/blocked"
echo '12.0 wlan0 ready (ath9k_htc)' > "$R/data/nemesis/logs/gen5w.kr.portable/dongle.log"
echo 'ath9k_htc 61000 0 - Live 0x0' > "$R/proc/modules"
printf '/data/nemesis/apps/gen5w.kr.portable/dongle/firmware' > "$R/sys/module/firmware_class/parameters/path"
echo 0cf3 > "$R/sys/bus/usb/devices/1-1/idVendor"; echo 9271 > "$R/sys/bus/usb/devices/1-1/idProduct"
cat > "$t/bin/logcat" <<'SH'
#!/bin/sh
echo failure-ring-buffer
SH
chmod +x "$t/bin/logcat"
export PATH="$t/bin:$PATH" PORTABLE_TEST_ROOT=$R
mksh "$B/diagnostics.sh" capture worker-owner
D=$R/data/local/gen5w-portable/diagnostics/failure-fixture-boot
[ -s "$D/DONE" ] && grep -q worker-owner "$D/START" && grep -q 'exit=23' "$D/boot-health-lost"
grep -q failure-ring-buffer "$D/logcat-main.txt"
grep -qx dongle "$D/wifi-backend.txt" && grep -qx blocked "$D/dongle-blocked"
grep -q 'wlan0 ready' "$D/dongle.log" && grep -q '^ath9k_htc ' "$D/modules.txt"
grep -q 'dongle/firmware' "$D/firmware-path.txt" && grep -qx '1-1 0cf3:9271' "$D/usb-devices.txt"
cp "$D/START" "$t/before"
mksh "$B/diagnostics.sh" capture second
cmp "$t/before" "$D/START"
[ ! -e "$D/second" ]
mksh "$B/diagnostics.sh" active 7
test -s "$R/data/local/gen5w-portable/diagnostics/active-fixture-boot-7/DONE"
cmp "$t/before" "$D/START"
for i in $(seq 8 14); do mkdir "$R/data/local/gen5w-portable/diagnostics/active-fixture-boot-$i"; done
echo exported > "$R/data/local/gen5w-portable/diagnostics/active-fixture-boot-7/EXPORTED"
mksh "$B/diagnostics.sh" active 15
test -s "$R/data/local/gen5w-portable/diagnostics/active-fixture-boot-15/DONE"
test ! -e "$R/data/local/gen5w-portable/diagnostics/active-fixture-boot-7"
test -d "$R/data/local/gen5w-portable/diagnostics/active-fixture-boot-8"
rm -rf "$R/data/local/gen5w-portable/diagnostics"
mkdir "$t/foreign"
ln -s "$t/foreign" "$R/data/local/gen5w-portable/diagnostics"
if mksh "$B/diagnostics.sh" capture forged; then echo FAIL unsafe-link; exit 1; fi
[ -z "$(ls -A "$t/foreign")" ]
echo 'PASS failure snapshot captures logs and local state, preserves first failure, rejects foreign links'
