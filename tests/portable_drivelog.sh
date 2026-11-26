#!/bin/bash
# Mock-only tests for the portable USB drive log (simple log, default on).
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
W=$(mktemp -d)
trap 'rc=$?; rm -rf "$W"; exit $rc' EXIT
fail() { echo "FAIL $1"; exit 1; }
ok() { echo "PASS $1"; }
command -v mksh >/dev/null 2>&1 || { echo 'SKIP portable drive log: mksh missing'; exit 0; }

PKG=$W/pkg/drivelog
mkdir -p "$PKG" "$W/data/nemesis"
cp "$ROOT/tools/portable/drivelog.sh" "$PKG/service.sh"
cp "$ROOT/packages/drive-log/scripts/common.sh" "$ROOT/packages/drive-log/scripts/install-hold.sh" "$PKG/"

USB=$W/usb
MOUNTS=$W/mounts
SYS=$W/sys
mkdir -p "$USB" "$SYS/dev/block" "$SYS/devices/platform/soc/usb1/1-1/host0/target0:0:0/block/sda/sda1"
ln -s ../../devices/platform/soc/usb1/1-1/host0/target0:0:0/block/sda/sda1 "$SYS/dev/block/8:1"
printf 'MAJOR=8\nMINOR=1\nDEVNAME=sda1\nDEVTYPE=partition\nPARTN=1\n' > "$SYS/devices/platform/soc/usb1/1-1/host0/target0:0:0/block/sda/sda1/uevent"
printf '/dev/block/vold/8:1 %s vfat rw,relatime 0 0\n' "$USB" > "$MOUNTS"
printf '100.00 1.00\n' > "$W/uptime"
printf '#!/bin/sh\necho 1\n' > "$W/getprop"
printf '#!/bin/sh\necho "Filesystem Size Used Free Blksize"\necho "$1 14G 1G 13G 4096"\n' > "$W/df"
printf '#!/bin/sh\nfor a in "$@"; do case "$a" in "Gen5W KR: "*) echo "$a" >> "%s";; esac; done\n' "$W/toasts" > "$W/am"
# -v time format, as on the unit.
cat > "$W/logcat" <<'EOF'
#!/bin/sh
echo "11-26 10:00:00.100 I/Gen5wDrive( 1234): D1|99999999|2|36|5000|600|10|10|0|0"
echo "11-26 10:00:00.200 I/Gen5wDrive( 1234): D1|99999999|3|38|2|1|-3|0|0|0"
echo "11-26 10:00:00.250 I/Gen5wDrive( 1234): D1|99999999|3|42|87|1|0|350|0|1"
echo "11-26 10:00:00.300 I/Gen5wDrive( 1234): not a record"
echo "11-26 10:00:00.400 I/Gen5wWireless( 2222): path=cp5 event=iap2-connected component=5"
echo "11-26 10:00:00.500 I/BTCMService( 3333): connect device 00:11:22:33:44:55"
echo "11-26 10:00:00.600 I/PhoneProjection( 4444): media Title=My Song"
echo "11-26 10:00:00.700 I/WifiService( 5555): SSID=home"
echo "11-26 10:00:00.800 E/AndroidRuntime( 6666): FATAL EXCEPTION: main"
echo "11-26 10:00:00.801 I/CarPlayService( 6666): onSessionFinalized()"
echo "11-26 10:00:00.802 D/ModeManagerService( 6666): getTopPackageName poll"
echo "11-26 10:00:00.803 D/ModeManagerService( 6666): split_screen_status=1"
echo "11-26 10:00:00.804 D/ModeManagerService( 6666): changeMode=115"
echo "11-26 10:00:00.805 I/Gen5wDrive( 6666): D1|99999999|1|40|7|1|0|0|0|0"
echo "11-26 10:00:00.806 I/Gen5wDrive( 6666): D1|99999999|1|41|8|1|99999998|2|7|0"
echo "11-26 10:00:00.807 D/ModeManagerService( 6666): setMode deviceName=private"
echo "11-26 10:00:00.808 V/ModeManagerService( 6666): ChangeModeAndBroadcast() Mode(1->115)"
echo "11-26 10:00:00.809 D/ModeManagerService( 6666): task-stack polling"
echo "11-26 10:00:00.810 D/ModeManagerService( 6666): splitscreen status : true 1"

sleep 3
EOF
chmod +x "$W/getprop" "$W/df" "$W/am" "$W/logcat"

run() { # seconds
    IT_DATA=$W/data DL_USB=$USB DL_MOUNTS=$MOUNTS DL_SYS=$SYS DL_GETPROP=$W/getprop DL_LOGCAT=$W/logcat \
        DL_DF=$W/df DL_AM=$W/am DL_PROC_UPTIME=$W/uptime "$@"
}

# 1. Default on: no marker needed; records and the unfiltered wire log land on the USB.
run timeout 8 mksh "$PKG/service.sh" > "$W/service.log" 2>&1 || true
grep -qx 'drive-log: recording' "$W/service.log" || { cat "$W/service.log"; fail 'records without any marker (default on)'; }
D=$USB/GEN5W-DRIVELOG
grep -qx 'D1|99999999|2|36|5000|600|10|10|0|0' "$D/drive-00.log" || fail 'core record written'
grep -qx 'D1|99999999|3|38|2|1|-3|0|0|0' "$D/drive-00.log" || fail 'navi adapter record (source 3) written'
grep -qx 'D1|99999999|3|42|87|1|0|350|0|1' "$D/drive-00.log" || fail 'stock navi icon change record written'
! grep -q 'not a record' "$D/drive-00.log" "$D/wire-00.log" || fail 'malformed Gen5wDrive line dropped'
grep -q 'event=iap2-connected' "$D/wire-00.log" || fail 'wireless tag line kept'
grep -q 'onSessionFinalized' "$D/wire-00.log" || fail 'CarPlayService lifecycle kept'
! grep -q 'getTopPackageName poll' "$D/wire-00.log" || fail 'mode polling noise dropped'
grep -q 'split_screen_status=1' "$D/wire-00.log" || fail 'split status kept'
grep -q 'ChangeModeAndBroadcast' "$D/wire-00.log" || fail 'verbose mode change kept'
grep -q 'splitscreen status : true 1' "$D/wire-00.log" || fail 'stock split message kept'
! grep -q 'task-stack polling' "$D/wire-00.log" || fail 'unrelated mode chatter dropped'
grep -q 'changeMode=115'  "$D/wire-00.log" || fail 'mode change kept'
grep -q 'deviceName=private' "$D/wire-00.log" || fail 'mode lines kept unfiltered'
grep -qx 'D1|99999999|1|40|7|1|0|0|0|0' "$D/drive-00.log" || fail 'finalize event accepted'
grep -qx 'D1|99999999|1|41|8|1|99999998|2|7|0' "$D/drive-00.log" || fail 'handover event accepted'
grep -q 'FATAL EXCEPTION'  "$D/wire-00.log" || fail 'crash line kept'
grep -q '00:11:22:33:44:55' "$D/wire-00.log" || fail 'MAC address line kept (no privacy filter)'
grep -qi 'title=' "$D/wire-00.log" || fail 'media title line kept'
grep -qi 'ssid' "$D/wire-00.log" || fail 'SSID line kept'
grep -q 'USB에 주행 로그 기록 중' "$W/toasts" || fail 'start toast shown'
ok 'default-on recording: numeric records + unfiltered wire log on the USB'

# 2. Restart appends after the stored cursor instead of truncating.
before=$(wc -l < "$D/drive-00.log")
run timeout 6 mksh "$PKG/service.sh" > "$W/service.log" 2>&1 || true
after=$(wc -l < "$D/drive-00.log")
[ "$after" -gt "$before" ] || fail 'second run appends'
ok 'restart appends to the existing ring'

# 3. Wire ring rotates within its bound.
rm -rf "$D"
run env DL_TESTING=1 DL_SEGMENT_BYTES_OVERRIDE=120 DL_WIRE_SEGMENTS_OVERRIDE=2 timeout 6 mksh "$PKG/service.sh" > "$W/service.log" 2>&1 || true
[ -f "$D/wire-01.log" ] || fail 'wire ring rotated'
[ ! -e "$D/wire-02.log" ] || fail 'wire ring bounded to its segment count'
ok 'rings rotate and stay bounded'

# 4. GEN5W-LOG-OFF on the USB: nothing written, no toast.
rm -rf "$D" "$W/toasts"
: > "$USB/GEN5W-LOG-OFF"
run timeout 6 mksh "$PKG/service.sh" > "$W/service.log" 2>&1 || true
[ ! -e "$D" ] || fail 'LOG-OFF USB not written'
[ ! -e "$W/toasts" ] || fail 'no toast for an opted-out USB'
rm -f "$USB/GEN5W-LOG-OFF"
ok 'GEN5W-LOG-OFF turns the log off for that USB'

# 5. No USB mounted: silent wait, no toast.
: > "$MOUNTS"
run timeout 6 mksh "$PKG/service.sh" > "$W/service.log" 2>&1 || true
[ ! -e "$W/toasts" ] || fail 'no toast without a USB'
grep -q 'waiting: USB not verified reason=unmounted' "$W/service.log" || fail 'logs the unmounted wait'
ok 'no USB: waits silently'

# 6. Install hold: the service exits immediately during a held install.
printf '/dev/block/vold/8:1 %s vfat rw,relatime 0 0\n' "$USB" > "$MOUNTS"
: > "$W/data/nemesis/gen5wkr.noreboot"
if [ -r /proc/sys/kernel/random/boot_id ]; then
    cat /proc/sys/kernel/random/boot_id > "$W/data/nemesis/gen5wkr.install-hold"
    rm -rf "$D"
    run timeout 6 mksh "$PKG/service.sh" > "$W/service.log" 2>&1 || true
    [ ! -e "$D" ] || fail 'held install: nothing written'
    ok 'install hold defers the service'
fi
echo 'portable drive log: all tests passed'
