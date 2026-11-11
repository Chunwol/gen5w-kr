#!/bin/bash
# mock test for tools/integrated/diag.sh (read-only USB diagnosis)
. "$(dirname "$0")/lib.sh"
ROOT=$(cd "$(dirname "$0")/.." && pwd)
W=$(mktemp -d); stubs
D=$W/data/nemesis
mkdir -p "$W/usb" "$D/apps/gen5w.kr.timer" "$D/logs/gen5w.kr.timer" "$D/logs/gen5w.kr.drivelog" \
    "$D/gen5w-kr-integrated" "$W/sysfs/class/net/wlan0" "$W/sysfs/class/net/lo" "$W/proc"
cp "$ROOT/tools/integrated/diag.sh" "$ROOT/tools/integrated/errors.sh" "$ROOT/tools/integrated/history.sh" "$W/usb/"
echo 0123abcd > "$W/usb/BUILD-REVISION"
printf '[nemesis]\nid=gen5w.kr.timer\npackage-version=9.9.9\n' > "$D/apps/gen5w.kr.timer/NEMESIS.data"
echo committed > "$D/gen5w-kr-integrated/state"
{
    for i in $(seq 1 600); do echo "timer: state rejected reason=screen n$i"; done
    echo 'timer: state accepted'
    echo 'wifi SSID=MyHomeNetwork'
} > "$D/logs/gen5w.kr.timer/timer.log"
echo 'drive-log: waiting: USB not verified reason=not-usb-storage' > "$D/logs/gen5w.kr.drivelog/drive-log.log"
echo up > "$W/sysfs/class/net/wlan0/operstate"
printf '/dev/block/vold/8:1 /mnt/media_rw/usb0 vfat rw 0 0\n/dev/fuse /storage/usb0 fuse rw 0 0\n/dev/block/mmcblk0p9 /data ext4 rw 0 0\n' > "$W/proc/mounts"
printf 'bcmdhd 500000 0 - Live 0x0\nsnd_soc 1000 0 - Live 0x0\n' > "$W/proc/modules"
cat > "$W/bin/logcat" <<'EOF'
#!/bin/sh
echo '11-04 22:32:31.000 I/ActivityManager( 597): first buffered line'
echo '11-04 22:33:08.860 I/PhoneProjection( 1165): [ f ] getPPWLDInfo(), Not Exist device info'
echo '11-04 22:33:09.000 D/BluetoothSocket( 1): getState(). Returning 12'
echo '11-04 22:33:10.000 I/Gen5wWireless( 9): session result=17'
echo '11-04 22:33:11.000 I/CarPlay_( 9): onBtAudioStatusUpdate DEVICE_NAME: lsh'
echo '11-04 22:33:12.000 D/CarPlay_( 9): device AA:BB:CC:DD:EE:FF connected'
echo '11-04 22:33:13.000 D/CarPlay_( 9): address: 80:96:98:**:**:**;'
echo '11-04 22:33:14.000 D/WifiService( 9): driving the soft AP state machine'
echo '11-04 22:34:19.000 I/Other( 9): last buffered line'
EOF
chmod +x "$W/bin/logcat"
echo 1 > "$W/props/sys.boot_completed"
# Supervisor markers, the host app's ready file and the recorded relay hashes.
echo match > "$D/gen5wkr.ap-match"
mkdir -p "$D/gen5wkr.apguard" "$W/data/data/kr.gen5w.wirelesshost/files" "$W/sys/app" "$W/sys/etc/gen5w-kr-backup/bridge"
echo 2 > "$D/gen5wkr.apguard.count"
echo boot-1 > "$D/gen5wkr.apguard/attempt"
echo 4321 > "$W/data/data/kr.gen5w.wirelesshost/files/bridge-ready"
echo dipo-apk > "$W/sys/app/HKMC_DiPO.apk"
echo 0123456789abcdef0123456789abcdef > "$W/sys/etc/gen5w-kr-backup/bridge/diporelay.apk.md5"
# Links planted in places the app or the supervisor can write must not be followed.
echo SECRET-OUTSIDE > "$W/outside"
ln -s "$W/outside" "$W/data/data/kr.gen5w.wirelesshost/files/other"
ln -s "$W/outside" "$D/gen5wkr.apguard/linked"
ln -s "$W/outside" "$D/gen5wkr.linked"
printf '#!/bin/sh
echo "package:kr.gen5w.wirelesshost"
echo "package:com.other.app"
' > "$W/bin/pm"; chmod +x "$W/bin/pm"
printf '#!/bin/sh
for f in "$@"; do echo "feedfeedfeedfeedfeedfeedfeedfeed  $f"; done
' > "$W/bin/md5"; chmod +x "$W/bin/md5"
run() { (cd "$W/usb" && PATH="$W/bin:$PATH" IT_DATA="$W/data" IT_SYSFS="$W/sysfs" IT_PROC="$W/proc" IT_SYSTEM="$W/sys" mksh diag.sh > "$W/out" 2>&1); }
O=$W/usb/GEN5W-REPORT/DIAG-1.txt
check 'diagnosis runs after boot' run
check 'reports the saved file' grep -qx 'SAVED GEN5W-REPORT/DIAG-1.txt' "$W/out"
check 'writes the first numbered file' test -f "$O"
check 'kit revision and package versions' eval 'grep -qx 0123abcd "$O" && grep -qx "gen5w.kr.timer 9.9.9" "$O"'
check 'transaction state' grep -qx committed "$O"
check 'network interfaces with state' eval 'grep -qx "wlan0 up" "$O" && grep -q "^lo " "$O"'
check 'wifi driver modules only' eval 'grep -q bcmdhd "$O" && ! grep -q snd_soc "$O"'
check 'usb mounts include the FUSE view and its vold mount' eval 'grep -q "/dev/fuse /storage/usb0 fuse" "$O" && grep -q "/mnt/media_rw/usb0 vfat" "$O"'
check 'internal storage mounts are not listed' eval '! grep -q mmcblk0p9 "$O"'
check 'service log keeps only its last 400 lines' eval 'grep -qx "timer: state accepted" "$O" && grep -qx "timer: state rejected reason=screen n600" "$O" && ! grep -qx "timer: state rejected reason=screen n200" "$O"'
check 'drive-log refusal reason is collected' grep -q 'reason=not-usb-storage' "$O"
check 'stock projection decision is collected' grep -q 'Not Exist device info' "$O"
check 'bridge lines are collected' grep -q 'Gen5wWireless.*result=17' "$O"
check 'supervisor markers are collected' eval 'grep -q "^== bridge runtime state" "$O" && grep -q "first line: match" "$O" && grep -q "gen5wkr.apguard/ (directory)" "$O" && grep -q "attempt: boot-1" "$O"'
check 'symbolic links are never followed' eval '! grep -q SECRET-OUTSIDE "$O"'
check 'restart guard count is collected' grep -q 'first line: 2' "$O"
check 'host app presence and ready file are collected' eval 'grep -q "package:kr.gen5w.wirelesshost" "$O" && ! grep -q "com.other.app" "$O" && grep -q "first line: 4321" "$O"'
check 'relay file hashes are collected next to the recorded ones' eval 'grep -q "HKMC_DiPO.apk" "$O" && grep -qx "diporelay.apk.md5: 0123456789abcdef0123456789abcdef" "$O"'
check 'lines with words such as driving are kept' grep -q 'driving the soft AP' "$O"
check 'network names are dropped' eval '! grep -q MyHomeNetwork "$O"'
check 'device names are dropped' eval '! grep -q "DEVICE_NAME" "$O"'
check 'full and masked addresses are dropped' eval '! grep -q "AA:BB:CC" "$O" && ! grep -q "80:96:98" "$O"'
check 'repeated status noise is dropped' eval '! grep -q "getState()" "$O"'
check 'buffer range shows first and last line' eval 'grep -q "first buffered line" "$O" && grep -q "last buffered line" "$O"'
check 'only the start and completion toasts are sent' eval '[ "$(grep -c . "$W/calls")" = 2 ] && [ "$(grep -c "am broadcast -a com.hkmc.intent.action.TOAST" "$W/calls")" = 2 ] && grep -q "저장 중" "$W/calls" && grep -q "저장 완료" "$W/calls"'
check 'second run keeps the first file' run
check 'second run writes the next number' eval 'test -f "$W/usb/GEN5W-REPORT/DIAG-2.txt" && test -f "$O"'
printf '#!/bin/sh\necho "Permission denied password=secret-diag" >&2\nexit 13\n' > "$W/bin/dmesg"
chmod +x "$W/bin/dmesg"
check 'failed acquisition still saves a classified diagnosis' run
check 'kernel permission failure is distinct from no kernel messages' grep -q 'operation=kernel.*rc=13.*reason=permission' "$W/usb/GEN5W-REPORT/DIAG-3.txt"
check 'acquisition stderr secrets are not exported' eval '! grep -q secret-diag "$W/usb/GEN5W-REPORT/DIAG-3.txt"'
echo 0 > "$W/props/sys.boot_completed"
check 'refuses before boot completes' eval '! run && test ! -e "$W/usb/GEN5W-REPORT/DIAG-4.txt"'
# Saved Android log on /data (logring) is copied whole and unfiltered, oldest first.
mkdir -p "$W/data/nemesis/gen5wkr.logs"
echo 'older-ap-start' > "$W/data/nemesis/gen5wkr.logs/logcat.txt.4"
echo 'middle-line' > "$W/data/nemesis/gen5wkr.logs/logcat.txt.1"
printf 'newer-ap-start
SSID=home-ap aa:bb:cc:dd:ee:ff
Unrelated noise-line
' > "$W/data/nemesis/gen5wkr.logs/logcat.txt"
echo 1 > "$W/props/sys.boot_completed"
rm -f "$W/bin/dmesg"
run
check 'saved Android log copied whole to its own file' eval 'printf "older-ap-start
middle-line
newer-ap-start
SSID=home-ap aa:bb:cc:dd:ee:ff
Unrelated noise-line
" | cmp -s - "$W/usb/GEN5W-REPORT/LOGCAT-4.txt"'
check 'diagnosis points to the saved log file' grep -q 'LOGCAT-4.txt' "$W/usb/GEN5W-REPORT/DIAG-4.txt"
check 'saved log is not dumped into the diagnosis text' eval '! grep -q older-ap-start "$W/usb/GEN5W-REPORT/DIAG-4.txt"'
rm -rf "$W/data/nemesis/gen5wkr.logs"
run
check 'no saved log: no empty log file' test ! -e "$W/usb/GEN5W-REPORT/LOGCAT-5.txt"
done_tests diag
