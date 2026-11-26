#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
t=$(mktemp -d /tmp/g5diag.XXXXXX); trap 'rc=$?; rm -rf "$t"; exit $rc' EXIT
R=$t/root; B=$R/data/bundle
mkdir -p "$B/bin" "$R/data/local/gen5w-portable/boot" "$R/data/local/gen5w-portable/persistent" "$R/data/local/tmp" "$R/system/lib" "$R/proc/sys/kernel/random" "$R/proc/net" "$R/data/nemesis/gen5wkr.ui" "$t/bin"
cp tools/portable/diagnostics.sh "$B/"
cp .build/portable/dex-patch-host "$B/bin/dex-patch"
echo 'audio|/data/a|/system/lib/libCarPlayAudio.so' > "$R/data/local/gen5w-portable/persistent/manifest"
printf 'audio-lib-fixture' > "$R/system/lib/libCarPlayAudio.so"
echo fixture-boot > "$R/proc/sys/kernel/random/boot_id"
echo '100 50' > "$R/proc/uptime"
echo 'eth0 00A8C0 00000000 route-fixture' > "$R/proc/net/route"
cat > "$t/bin/getprop" <<'SH'
#!/bin/sh
case "$1" in
persist.service.adb.tcp.enable) echo 1;;
persist.adb.tcp.port) echo 5555;;
*)
    echo '[ro.build.fingerprint]: [v039-fixture]'
    echo '[wrap.com.daudio.app.dipo]: [/system/bin/sh]'
    echo '[ro.serialno]: [SECRET123]'
    echo '[ro.btaddr]: [aa:bb:cc:dd:ee:ff]'
    ;;
esac
SH
cat > "$t/bin/dumpsys" <<'SH'
#!/bin/sh
echo "fixture-dump-$1"
if [ "$1" = wifi ]; then
    echo 'mWifiApState=13'
    echo '0 "HomeNetwork" [CURRENT]'
    echo 'SSID: HomeWiFi'
    echo 'BSSID: 11:22:33:44:55:66'
    echo 'preSharedKey=TopSecret'
elif [ "$1" = bluetooth ] || [ "$1" = bluetooth_manager ]; then
    echo '  enabled: true'
    echo 'bt_name=OwnersPhone'
    echo 'Bonded devices:'
    echo '  MyPhone'
    echo '  11:22:33:44:55:66'
fi
SH
chmod +x "$t/bin/getprop" "$t/bin/dumpsys"
echo 'worker=owner exit=23' > "$R/data/local/gen5w-portable/boot/health-lost"
echo details > "$R/data/nemesis/gen5wkr.ui/diag-latest.txt"
# USB Wi-Fi dongle evidence (with private token to confirm filtering on dongle.log).
echo dongle > "$R/data/local/gen5w-portable/wifi-backend"
mkdir -p "$R/data/local/gen5w-portable/dongle" "$R/data/nemesis/logs/gen5w.kr.portable" "$R/sys/module/firmware_class/parameters" "$R/sys/bus/usb/devices/1-1"
echo blocked > "$R/data/local/gen5w-portable/dongle/blocked"
printf '12.0 wlan0 ready (ath9k_htc)\nbt_name=OwnersPhone\n' > "$R/data/nemesis/logs/gen5w.kr.portable/dongle.log"
echo 'ath9k_htc 61000 0 - Live 0x0' > "$R/proc/modules"
printf '/data/nemesis/apps/gen5w.kr.portable/dongle/firmware' > "$R/sys/module/firmware_class/parameters/path"
echo 0cf3 > "$R/sys/bus/usb/devices/1-1/idVendor"; echo 9271 > "$R/sys/bus/usb/devices/1-1/idProduct"
cat > "$t/bin/logcat" <<'SH'
#!/bin/sh
seq 1 60000
SH
chmod +x "$t/bin/logcat"
mkdir -p "$R/data/local/gen5w-portable/debug"
echo focus-fixture-line > "$R/data/local/gen5w-portable/debug/focus.log"
echo focus-first-line > "$R/data/local/gen5w-portable/debug/focus-first.log"
python3 - "$R/data/local/gen5w-portable/debug/logcat.log" <<'PY'
import sys
p = sys.argv[1]
head = b'HEAD_MARKER\n'
tail = b'TAIL_MARKER\n'
mid = b'M' * ((2 * 1024 * 1024) + 8192 - len(head) - len(tail))
open(p, 'wb').write(head + mid + tail)
PY
export PATH="$t/bin:$PATH" PORTABLE_TEST_ROOT=$R
mksh "$B/diagnostics.sh" capture worker-owner
D=$R/data/local/gen5w-portable/diagnostics/failure-fixture-boot
[ -s "$D/DONE" ] && grep -q worker-owner "$D/START" && grep -q 'exit=23' "$D/boot-health-lost"
[ "$(wc -c < "$D/logcat-main.txt")" -eq 262144 ] && grep -qx 1 "$D/logcat-main.txt" && grep -qx 'logcat-main.txt|0' "$D/commands.txt"
! ls "$D"/*.part "$D"/*.raw "$D"/*.flt "$D"/*.rc >/dev/null 2>&1
! find "$R/data/local/gen5w-portable/diagnostics" -maxdepth 1 -name '.stage-*' | grep -q .
grep -q focus-fixture-line "$D/debug-focus.log"
grep -q focus-first-line "$D/debug-focus-first.log"
grep -q route-fixture "$D/net-route.txt"
grep -qx 1 "$D/network-adb-enable.txt"
grep -qx 5555 "$D/network-adb-port.txt"
grep -qx fixture-dump-gpm "$D/gpm.txt"
# AA evidence must precede slower audio/wifi Binder queries in the bounded capture.
test "$(grep -n '^gpm.txt|' "$D/commands.txt" | cut -d: -f1)" -lt "$(grep -n '^audio.txt|' "$D/commands.txt" | cut -d: -f1)"
grep -qx dongle "$D/wifi-backend.txt" && grep -qx blocked "$D/dongle-blocked"
grep -q 'wlan0 ready' "$D/dongle.log" && ! grep -q 'OwnersPhone' "$D/dongle.log"
grep -q '^ath9k_htc ' "$D/modules.txt"
grep -q 'dongle/firmware' "$D/firmware-path.txt" && grep -qx '1-1 0cf3:9271' "$D/usb-devices.txt"
grep -q 'libCarPlayAudio.so' "$D/persistent-manifest.txt" && [ -s "$D/audio-lib-sha256.txt" ]
grep -q 'ro.build.fingerprint' "$D/properties.txt" && grep -q 'wrap.com.daudio.app.dipo' "$D/properties.txt"
! grep -qE 'SECRET123|aa:bb:cc:dd:ee:ff|ro\.serialno|ro\.btaddr' "$D/properties.txt"
grep -qx 'mWifiApState=13' <(grep -x 'mWifiApState=13' "$D/wifi.txt") && ! grep -qE 'HomeNetwork|HomeWiFi|11:22:33:44:55:66|TopSecret' "$D/wifi.txt"
grep -q 'enabled: true' "$D/bluetooth.txt" && ! grep -qE 'OwnersPhone|MyPhone|11:22:33:44:55:66|Bonded' "$D/bluetooth.txt"
grep -q 'enabled: true' "$D/bluetooth-manager.txt" && ! grep -qE 'OwnersPhone|MyPhone|Bonded' "$D/bluetooth-manager.txt"
cp "$D/START" "$t/before"
mksh "$B/diagnostics.sh" capture second
cmp "$t/before" "$D/START"
[ ! -e "$D/second" ]
mksh "$B/diagnostics.sh" active 7
test -s "$R/data/local/gen5w-portable/diagnostics/active-fixture-boot-7/DONE"
grep -q TAIL_MARKER "$R/data/local/gen5w-portable/diagnostics/active-fixture-boot-7/debug-logcat.log"
! grep -q HEAD_MARKER "$R/data/local/gen5w-portable/diagnostics/active-fixture-boot-7/debug-logcat.log"
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

# Verify usb-collect/NEMESIS.sh internal 0700 staging, supervisor gating, .gz DropBox allowlist, ancestor symlink check, and PII filtering.
rm -rf "$R/data/local/gen5w-portable/diagnostics" "$t/foreign"
mkdir -p "$t/usb-out" "$R/data/nemesis/apps/gen5w.kr.portable/bin" "$R/data/system/dropbox" "$t/symtarget" "$R/data/local/gen5w-portable/diagnostics"
cp .build/portable/dex-patch-host "$R/data/nemesis/apps/gen5w.kr.portable/bin/dex-patch"
ln -s "$t/symtarget" "$R/data/local/gen5w-portable/diagnostics/linkdir"
echo 'should-not-copy' > "$t/symtarget/secret.txt"
printf 'Process: com.daudio.app.dipo\nMAC=aa:bb:cc:dd:ee:ff\ncrash-detail-gz\n' | gzip -c > "$R/data/system/dropbox/data_app_crash@123.txt.gz"
printf 'Process: com.example.banking\ntoken=topsecret\n' > "$R/data/system/dropbox/data_app_crash@999.txt"
echo 'unrelated event log' > "$R/data/system/dropbox/event_log@123.txt"
printf '#!/bin/sh\nexit 0\n' > "$t/bin/am-ok"; chmod +x "$t/bin/am-ok"
PORTABLE_TEST_USB=$t/usb-out PORTABLE_TEST_ROOT=$R PORTABLE_TEST_AM=$t/bin/am-ok mksh tools/portable/usb-collect/NEMESIS.sh
U=$t/usb-out/GEN5W-PORTABLE-LOGS-0
[ -s "$U/DONE" ]
[ ! -e "$U/failure-evidence/linkdir" ]
! find "$U" \( -name '*.part' -o -name '*.raw' -o -name '*.flt' -o -name '*.rc' -o -name '*.tmp' \) | grep -q .
grep -q 'ro.build.fingerprint' "$U/getprop.txt" && grep -qE 'SECRET123|aa:bb:cc:dd:ee:ff' "$U/getprop.txt"
grep -qx 'mWifiApState=13' <(grep -x 'mWifiApState=13' "$U/wifi.txt") && grep -qE 'HomeNetwork|HomeWiFi|11:22:33:44:55:66|TopSecret' "$U/wifi.txt"
grep -q 'crash-detail-gz' "$U/dropbox/data_app_crash@123.txt" && grep -q 'aa:bb:cc:dd:ee:ff' "$U/dropbox/data_app_crash@123.txt"
[ ! -e "$U/dropbox/data_app_crash@123.txt.gz" ]
[ ! -e "$U/dropbox/data_app_crash@999.txt" ]
[ ! -e "$U/dropbox/event_log@123.txt" ]
grep -q 'libCarPlayAudio.so' "$U/persistent-manifest.txt" && [ -s "$U/audio-lib-sha256.txt" ]
mkdir -p "$t/usb-out/sub"
ln -s "$t/usb-out" "$t/usb-link"
if PORTABLE_TEST_USB=$t/usb-link/sub PORTABLE_TEST_ROOT=$R PORTABLE_TEST_AM=$t/bin/am-ok mksh tools/portable/usb-collect/NEMESIS.sh; then
    echo 'FAIL symlinked USB ancestor accepted'; exit 1
fi
echo 'PASS failure snapshot & usb-collect enforce ancestor symlink checks, internal 0700 staging, supervisor gating, DropBox allowlist, and PII filtering'
