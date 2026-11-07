#!/bin/bash
# In-car screen collector: bounded, privacy-filtered copies of every gen5w package log.
. "$(dirname "$0")/lib.sh"
ROOT=$(cd "$(dirname "$0")/.." && pwd)
PKG=$ROOT/packages/core
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
mkdir -p "$W/bin" "$W/data/nemesis/logs" "$W/data/nemesis/apps/gen5w.kr.bridge" "$W/app" "$W/proc"
cat > "$W/bin/getprop" <<FAKE
#!/bin/sh
case "\$1" in
    persist.gen5w.wifi.backend) cat "$W/backend" 2>/dev/null;;
    service.adb.tcp.port) cat "$W/adbport" 2>/dev/null;;
esac
FAKE
cat > "$W/bin/setprop" <<FAKE
#!/bin/sh
[ "\$1" = service.adb.tcp.port ] && echo "\$2" > "$W/adbport"
echo "setprop \$*" >> "$W/adbcalls"
FAKE
cat > "$W/bin/stop" <<FAKE
#!/bin/sh
echo "stop \$*" >> "$W/adbcalls"
FAKE
cat > "$W/bin/start" <<FAKE
#!/bin/sh
echo "start \$*" >> "$W/adbcalls"
FAKE
cat > "$W/bin/pm" <<'FAKE'
#!/bin/sh
echo package:com.redbend.client
echo package:com.hkmc.other
echo package:local.hkmc.nemesis
FAKE
chmod +x "$W/bin/getprop" "$W/bin/setprop" "$W/bin/stop" "$W/bin/start" "$W/bin/pm"
export PATH="$W/bin:$PATH"
printf 'package-version=0.3.47\n' > "$W/data/nemesis/apps/gen5w.kr.bridge/NEMESIS.data"
UI=$W/app/gen5w-ui
LOGS=$W/data/nemesis/logs
mklog() { mkdir -p "$LOGS/$1"; cat > "$LOGS/$1/$2"; }
reset() { rm -rf "$UI" "$LOGS" "$W/data/nemesis/gen5wkr."* "$W/ready" "$W/backend" "$W/adbport" "$W/adbcalls"; mkdir -p "$LOGS"; : > "$W/logcat.out"; }
printf '#!/bin/sh\ncat "%s/logcat.out"\n' "$W" > "$W/logcat"; chmod +x "$W/logcat"
run() {
    UILOG_TEST_DATA=$W/data UILOG_TEST_DIR=${UILOG_DIR:-$UI} UILOG_TEST_ONCE=1 UILOG_TEST_LOGCAT=$W/logcat \
    UILOG_TEST_READY=$W/ready UILOG_TEST_PROC=$W/proc UILOG_TEST_REQUEST=$W/request UILOG_TEST_USB=$W/usb UILOG_TEST_MOUNTS=$W/mounts UILOG_TEST_PM=$W/bin/pm mksh "$PKG/scripts/uilog.sh" > "$W/out" 2>&1
}
# Save and removal run in the background after the request is read: give them a moment.
runs() { run; sleep 0.8; }
runw() { run; sleep 6; }
# By default the files go to a root-owned folder under /data/nemesis, never into an app data folder.
default_dir() { rm -rf "$W/data/nemesis/gen5wkr.ui"; UILOG_TEST_DATA=$W/data UILOG_TEST_ONCE=1 UILOG_TEST_LOGCAT=$W/logcat UILOG_TEST_READY=$W/ready UILOG_TEST_PROC=$W/proc mksh "$PKG/scripts/uilog.sh" > "$W/out" 2>&1; }
status() { grep "^$1=" "$UI/status" | { IFS= read -r l; echo "${l#*=}"; }; }

reset
mklog gen5w.kr.bridge bridge.log <<'EOF'
WAIT bridge: wireless is not in match mode (ap-match is not 'match')
WAIT bridge: starting the host (relay=0)
EOF
mklog gen5w.kr.bluelink bluelink.log <<'EOF'
bluelink: monthly reminder hidden
EOF
run
check 'collector runs once and exits cleanly' test $? = 0
default_dir
check 'default output folder is gen5wkr.ui under nemesis' test -f "$W/data/nemesis/gen5wkr.ui/status" -a -f "$W/data/nemesis/gen5wkr.ui/log"
check 'script names the core app folder only for the read-only request file' eval '[ "$(grep -v "^ *#" "$PKG/scripts/uilog.sh" | grep -c "data/data/kr.gen5w.core")" = 1 ]'
check 'script never writes to the request file' eval '! grep -v "^ *#" "$PKG/scripts/uilog.sh" | grep -Eq ">+ *\"?\$REQUEST|rm .*\$REQUEST|mv .*\$REQUEST"'
run
check 'status has the snapshot keys' eval 'for k in ts host relay backend version apguard wired; do grep -q "^$k=" "$UI/status" || exit 1; done'
check 'status ts is a number' eval '[ -n "$(status ts)" ] && [ -z "$(status ts | tr -d 0-9)" ]'
check 'status reads the bridge version' test "$(status version)" = 0.3.47
check 'backend defaults to builtin' test "$(status backend)" = builtin
check 'host is dead without bridge-ready' test "$(status host)" = dead
check 'apguard on by default' test "$(status apguard)" = on
check 'not wired-only by default' test "$(status wired)" = no
check 'log keeps the bridge line verbatim' grep -qx "bridge|WAIT bridge: wireless is not in match mode (ap-match is not 'match')" "$UI/log"
check 'log includes another package log' grep -qx 'bluelink|bluelink: monthly reminder hidden' "$UI/log"
check 'bridge lines come first' eval '[ "$(head -1 "$UI/log" | cut -d"|" -f1)" = bridge ]'
check 'folder is 755' eval '[ "$(stat -c %a "$UI")" = 755 ]'
check 'files are 644' eval '[ "$(stat -c %a "$UI/status")" = 644 ] && [ "$(stat -c %a "$UI/log")" = 644 ]'
check 'no temp files are left' eval '[ "$(ls -A "$UI" | grep -vc "^\(status\|log\|facts\)$")" = 0 ]'
run
check 'a second run replaces the log instead of growing it' eval '[ "$(grep -c "^bluelink|" "$UI/log")" = 1 ]'
reset
printf 'wireless: AP start requested
wireless: ssid=secretname
' > "$W/data/nemesis/gen5w.kr.wireless.log"
run
check 'the wireless installer log next to the folders is collected' grep -q '^wireless|wireless: AP start requested' "$UI/log"
check 'that log passes the privacy filter' eval '! grep -q secretname "$UI/log"'
LINES=999 run
check 'a LINES value in the environment does not empty the log (mksh treats LINES as special)' grep -q '^wireless|wireless: AP start requested' "$UI/log"
printf 'noise
2026-11-07 started gen5w.kr.bridge/bridge pid=1
WAIT bridge: starting the host
' > "$W/data/nemesis/nemesis.log"
run
check 'our lines from the main NEMESIS log are collected' grep -q '^nemesis|WAIT bridge: starting the host' "$UI/log"
check 'other lines of the main NEMESIS log are not' eval '! grep -q "|noise" "$UI/log"'

# host state, markers, backend
sleep 30 & SP=$!
mkdir -p "$W/proc/$SP"; echo kr.gen5w.wirelesshost > "$W/proc/$SP/cmdline"
echo "$SP" > "$W/ready"; echo dongle > "$W/backend"; : > "$W/data/nemesis/gen5wkr.apguard.off"; : > "$W/data/nemesis/gen5wkr.wireless-disabled"
run
check 'a live pid with the host command line is alive' test "$(status host)" = alive
check 'apguard off marker' test "$(status apguard)" = off
check 'wired-only marker' test "$(status wired)" = yes
check 'dongle backend is reported' test "$(status backend)" = dongle
echo other > "$W/proc/$SP/cmdline"; run
check 'a live pid that is not the host is dead' test "$(status host)" = dead
kill "$SP" 2>/dev/null; wait "$SP" 2>/dev/null

# size limits
reset
for i in $(seq 1 300); do echo "WAIT bridge: line $i"; done | mklog gen5w.kr.bridge bridge.log
for n in $(seq 1 20); do for i in $(seq 1 300); do echo "svc $n line $i"; done | mklog "gen5w.kr.pkg$n" "p$n.log"; done
run
check 'one source keeps only its last 25 lines' test "$(grep -c '^bridge|' "$UI/log")" = 25
check 'the newest line is kept and the oldest is dropped' eval 'grep -q "line 300$" "$UI/log" && ! grep -q "bridge|WAIT bridge: line 1$" "$UI/log"'
check 'whole log is at most 200 lines' eval '[ "$(wc -l < "$UI/log")" -le 200 ]'
check 'whole log is at most 64 KB' eval '[ "$(wc -c < "$UI/log")" -le 65536 ]'
reset
mklog gen5w.kr.bridge bridge.log <<EOF
$(head -c 500 /dev/zero | tr '\0' a)
EOF
run
check 'long lines are cut to 200 characters' eval '[ "$(head -1 "$UI/log" | cut -d"|" -f2 | tr -d "\n" | wc -c)" -le 200 ]'
reset
head -c 135000 /dev/zero | tr '\0' 'a' | fold -w 80 > "$W/big"
mklog gen5w.kr.bluelink big.log < "$W/big"
mklog gen5w.kr.bridge bridge.log <<'EOF'
STEP bridge: host alive
EOF
run
check 'a source over 128 KB is skipped with one note line' eval '[ "$(grep -c "^bluelink|" "$UI/log")" = 1 ] && grep -qx "bluelink|(로그가 너무 커서 건너뜀)" "$UI/log"'
check 'other sources are still collected' grep -qx 'bridge|STEP bridge: host alive' "$UI/log"
reset
for i in $(seq 1 500); do echo "11-06 12:00:00.000 I/Gen5wCore( 1): line $i"; done > "$W/logcat.out"
run
check 'logcat is limited to 40 lines' test "$(grep -c '^logcat|' "$UI/log")" = 40
check 'logcat keeps the newest lines' grep -q 'line 500$' "$UI/log"

# privacy
reset
printf '%s
' '11-06 12:00:00.000 I/Gen5w( 1): peer aa:bb:cc:dd:ee:ff' '11-06 12:00:00.000 I/Gen5w( 1): ok line' > "$W/logcat.out"
run
check 'logcat MAC lines are dropped' eval '! grep -q "aa:bb:cc" "$UI/log" && grep -q "ok line" "$UI/log"'
mklog gen5w.kr.bridge bridge.log <<'EOF'
connected aa:bb:cc:dd:ee:ff
ssid=MyCarWifi
VIN=KMHXXXXXXXXXXXXXX
WAIT bridge: wired-only mode is set
EOF
run
check 'MAC, SSID and VIN lines are dropped' eval '! grep -qi "aa:bb:cc\|ssid\|VIN=" "$UI/log"'
check 'ordinary lines remain' grep -q 'wired-only mode is set' "$UI/log"

# safety
reset
mklog gen5w.kr.bridge bridge.log <<'EOF'
STEP bridge: host alive
EOF
mkdir -p "$W/target"; ln -s "$W/target" "$W/app/linkdir"
UILOG_DIR=$W/app/linkdir run
check 'a symlinked folder is not followed' eval '[ -z "$(ls -A "$W/target")" ]'
for name in status log status.tmp log.tmp filter.tmp; do
    rm -rf "$UI"; mkdir -p "$UI"; echo keep > "$W/victim"; ln -s "$W/victim" "$UI/$name"
    run
    check "a symlink named $name is not written through" test "$(cat "$W/victim")" = keep
done
mkdir -p "$W/target2"; ln -s "$W/target2" "$W/linkparent"
UILOG_DIR=$W/linkparent/gen5w-ui run
check 'a symlinked app folder is not followed' eval '[ -z "$(ls -A "$W/target2")" ]'
rm -rf "$UI"
UILOG_DIR=$W/missing-parent/gen5w-ui run
check 'without the app folder nothing is created and the run ends cleanly' eval 'test $? = 0 && [ ! -e "$W/missing-parent" ]'
rm -rf "$LOGS"
run
check 'status is written even when no package log exists' test -f "$UI/status"

# Switch requests from the screen: fixed words only, markers in the root-owned folder, never a link.
N=$W/data/nemesis
reset; rm -f "$W/request"; run
check 'no request: all switches on' eval '[ "$(status sw_wireless)" = on ] && [ "$(status sw_timer)" = on ] && [ "$(status sw_bluelink)" = on ]'
printf 'wireless=off
timer=off
bluelink=off
' > "$W/request"; run
check 'wireless=off makes its marker' test -f "$N/gen5wkr.ui-wireless-off"
check 'timer=off makes its marker' test -f "$N/gen5wkr.ui-timer-off"
check 'bluelink=off makes its marker' test -f "$N/gen5wkr.ui-bluelink-off"
check 'status reports the switches off' eval '[ "$(status sw_wireless)" = off ] && [ "$(status sw_timer)" = off ] && [ "$(status sw_bluelink)" = off ]'
check 'the installer wired-only marker is not touched' test ! -e "$N/gen5wkr.wireless-disabled"
printf 'wireless=on
' > "$W/request"; run
check 'wireless=on removes the marker' test ! -e "$N/gen5wkr.ui-wireless-off"
check 'other markers stay as requested before' test -f "$N/gen5wkr.ui-timer-off"
printf 'wireless=maybe
foo=off
wireless=off extra
=off
../x=off
' > "$W/request"; rm -f "$N"/gen5wkr.ui-*; run
check 'unknown words are ignored' eval '[ -z "$(ls "$N" | grep gen5wkr.ui-)" ]'
{ i=0; while [ $i -lt 20 ]; do echo 'junk'; i=$((i+1)); done; echo 'wireless=off'; } > "$W/request"; run
check 'only the first 8 lines are read' test ! -e "$N/gen5wkr.ui-wireless-off"
rm -f "$W/request"; echo 'wireless=off' > "$W/real"; ln -s "$W/real" "$W/request"; run
check 'a linked request file is ignored' test ! -e "$N/gen5wkr.ui-wireless-off"
rm -f "$W/request"; printf 'wireless=off
' > "$W/request"; echo keep > "$W/victim"; ln -s "$W/victim" "$N/gen5wkr.ui-wireless-off"; run
check 'a linked marker path is not written through' test "$(cat "$W/victim")" = keep
rm -f "$N/gen5wkr.ui-wireless-off" "$W/request"
{ echo 'wireless=off'; i=0; while [ $i -lt 40 ]; do echo 'padding-padding-padding'; i=$((i+1)); done; } > "$W/request"; run
check 'a request file over 256 bytes is ignored' test ! -e "$N/gen5wkr.ui-wireless-off"
printf 'wireless=off
' > "$W/request"; run
check 'a small request still works after the size limit' test -f "$N/gen5wkr.ui-wireless-off"
rm -f "$N/gen5wkr.ui-wireless-off" "$W/request"

# Facts about the unit (read-only) and the diagnosis save.
reset; run
check 'facts file is written' test -f "$UI/facts"
check 'facts list the update-related packages' grep -q 'package:com.redbend.client' "$UI/facts"
check 'facts list the adb property line' grep -q '^prop persist.sys.usb.config=' "$UI/facts"
check 'facts show the nemesis folder mode' grep -q -- '-- /data/nemesis' "$UI/facts"
check 'facts stay under the line cap' test "$(grep -c '' "$UI/facts")" -le 60
reset; mkdir -p "$W/usb"; echo "tmpfs $W/usb vfat rw 0 0" > "$W/mounts"
printf 'E/AndroidRuntime( 1): FATAL EXCEPTION in kr.gen5w.wirelesshost\n' > "$W/logcat.out"
sed -i "s# $W/usb # $W/usb #" "$W/mounts"
printf 'save=12345
' > "$W/request"; runw
check 'save writes a file on the mounted USB' test -f "$W/usb/gen5w-kr-diag/diag-12345.txt"
check 'saved file holds status, facts and log' eval 'grep -q "===== status" "$W/usb/gen5w-kr-diag/diag-12345.txt" && grep -q "===== facts" "$W/usb/gen5w-kr-diag/diag-12345.txt" && grep -q "===== log" "$W/usb/gen5w-kr-diag/diag-12345.txt"'
check 'saved file has a deep section with the collector self-check' eval 'grep -q "===== deep" "$W/usb/gen5w-kr-diag/diag-12345.txt" && grep -q "collector self-check" "$W/usb/gen5w-kr-diag/diag-12345.txt"'
check 'deep section carries the host crash line from logcat' grep -q 'FATAL EXCEPTION in kr.gen5w.wirelesshost' "$W/usb/gen5w-kr-diag/diag-12345.txt"
check 'deep section never lands in the screen files' eval '! grep -q "FATAL EXCEPTION" "$UI/facts" "$UI/status"'
check 'deep temp files are cleaned up' eval '[ ! -e "$UI/deep-save.tmp" ] && [ ! -e "$UI/deep-in.tmp" ]'
check 'a local copy is kept' test -f "$UI/diag-latest.txt"
check 'status reports the save' test "$(status saved)" = 12345:usb
rm -f "$W/usb/gen5w-kr-diag/diag-12345.txt"; runs
check 'the same save number is not run twice' test ! -e "$W/usb/gen5w-kr-diag/diag-12345.txt"
printf 'save=12346
' > "$W/request"; : > "$W/mounts"; run
check 'no mounted USB gives nousb and keeps the local copy' eval '[ "$(status saved)" = 12346:nousb ] && [ -f "$UI/diag-latest.txt" ] && [ ! -e "$W/usb/gen5w-kr-diag/diag-12346.txt" ]'
printf 'save=../../x
save=
save=12345678901234
' > "$W/request"; runs
check 'a bad save number is ignored' test "$(status saved)" = 12346:nousb
echo "tmpfs $W/usb vfat rw 0 0" > "$W/mounts"; rm -rf "$W/usb/gen5w-kr-diag"; mkdir -p "$W/elsewhere"; ln -s "$W/elsewhere" "$W/usb/gen5w-kr-diag"
printf 'save=12347
' > "$W/request"; run
check 'a linked diag folder on the USB is not written through' eval '[ -z "$(ls -A "$W/elsewhere")" ] && [ "$(status saved)" = 12347:fail ]'
rm -f "$W/usb/gen5w-kr-diag" "$W/request" "$W/mounts"
echo "tmpfs $W/usb ext4 rw 0 0" > "$W/mounts"; rm -rf "$W/usb/gen5w-kr-diag"
printf 'save=12348
' > "$W/request"; run
check 'a stick that is not FAT-type is not written' eval '[ ! -e "$W/usb/gen5w-kr-diag" ] && [ "$(status saved)" = 12348:nousb ]'
echo "tmpfs $W/usb vfat rw 0 0" > "$W/mounts"; mkdir -p "$W/usb/gen5w-kr-diag"; echo keep > "$W/victim2"; ln -s "$W/victim2" "$W/usb/gen5w-kr-diag/diag-12349.txt.tmp"
printf 'save=12349
' > "$W/request"; run
check 'a prepared link at the temp name is not written through' eval '[ "$(cat "$W/victim2")" = keep ] && [ "$(status saved)" = 12349:fail ]'
rm -rf "$W/usb/gen5w-kr-diag" "$W/victim2"

# In-car removal: each package's own hook first, then NEMESIS; the first failure stops; core stays.
mkpkg() { # id [hookrc]
    mkdir -p "$W/data/nemesis/apps/$1/scripts"
    printf '[nemesis]\nid=%s\npreuninstall=scripts/preun.sh\n' "$1" > "$W/data/nemesis/apps/$1/NEMESIS.data"
    printf '#!/system/bin/sh\necho "hook %s" >> "%s/rmcalls"\nexit %s\n' "$1" "$W" "${2:-0}" > "$W/data/nemesis/apps/$1/scripts/preun.sh"
}
cat > "$W/nemesis" <<FAKE
#!/bin/sh
echo "\$*" >> "$W/rmcalls"
[ "\$1" = uninstall ] || exit 0
[ -n "$W/failuninstall" ] && [ "\$2" = "\$(cat "$W/failuninstall" 2>/dev/null)" ] && exit 5
rm -rf "$W/data/nemesis/apps/\$2"
FAKE
chmod +x "$W/nemesis"
rmrun() { UILOG_TEST_NEM=$W/nemesis UILOG_TEST_SH=/bin/sh runs; }
reset; rm -f "$W/rmcalls" "$W/failuninstall"
for id in drivelog bluelink timer bridge audio wireless core; do mkpkg gen5w.kr.$id; done
touch "$N/gen5wkr.wireless-disabled" "$N/gen5wkr.ui-timer-off"
printf 'remove=555\n' > "$W/request"; rmrun
check 'every package except core is uninstalled' eval '[ ! -d "$N/apps/gen5w.kr.bridge" ] && [ ! -d "$N/apps/gen5w.kr.drivelog" ] && [ ! -d "$N/apps/gen5w.kr.wireless" ]'
check 'the core package stays' test -d "$N/apps/gen5w.kr.core"
check 'core is never sent to uninstall' eval '! grep -q "uninstall gen5w.kr.core" "$W/rmcalls"'
check 'the hook runs before the uninstall of the same package' eval 'h=$(grep -n "^hook gen5w.kr.bridge" "$W/rmcalls" | cut -d: -f1); u=$(grep -n "^uninstall gen5w.kr.bridge" "$W/rmcalls" | cut -d: -f1); [ -n "$h" ] && [ -n "$u" ] && [ "$h" -lt "$u" ]'
check 'order follows the USB removal order (bridge before audio before wireless)' eval 'b=$(grep -n "^uninstall gen5w.kr.bridge" "$W/rmcalls" | cut -d: -f1); a=$(grep -n "^uninstall gen5w.kr.audio" "$W/rmcalls" | cut -d: -f1); w=$(grep -n "^uninstall gen5w.kr.wireless" "$W/rmcalls" | cut -d: -f1); [ "$b" -lt "$a" ] && [ "$a" -lt "$w" ]'
check 'markers of removed packages are cleared' eval '[ ! -e "$N/gen5wkr.wireless-disabled" ] && [ ! -e "$N/gen5wkr.ui-timer-off" ]'
check 'status reports the removal as done' test "$(status removed)" = 555:done
rm -f "$W/rmcalls"; rmrun
check 'the same removal number does not run again' test ! -e "$W/rmcalls"
# A failing hook stops the whole removal before anything is uninstalled for that package.
reset; rm -f "$W/rmcalls" "$W/failuninstall"
for id in drivelog bluelink timer bridge audio wireless core; do mkpkg gen5w.kr.$id; done
mkpkg gen5w.kr.audio 1
printf 'remove=556\n' > "$W/request"; rmrun
check 'a failing hook stops the removal at that package' test "$(status removed)" = 556:failed:gen5w.kr.audio
check 'the failing package is not uninstalled' test -d "$N/apps/gen5w.kr.audio"
check 'packages after the failure are untouched' eval '[ -d "$N/apps/gen5w.kr.wireless" ] && ! grep -q "uninstall gen5w.kr.wireless" "$W/rmcalls"'
check 'packages before the failure were removed' test ! -d "$N/apps/gen5w.kr.bridge"
# NEMESIS refusing the uninstall also stops, and nothing is forced.
reset; rm -f "$W/rmcalls"; echo gen5w.kr.timer > "$W/failuninstall"
for id in drivelog bluelink timer bridge audio wireless core; do mkpkg gen5w.kr.$id; done
printf 'remove=557\n' > "$W/request"; rmrun
check 'a refused uninstall stops the removal' test "$(status removed)" = 557:failed:gen5w.kr.timer
check 'no forced uninstall is ever used' eval '! grep -q -- "--force" "$W/rmcalls"'
rm -f "$W/failuninstall"
# Bad numbers and a missing NEMESIS.
reset; rm -f "$W/rmcalls"; mkpkg gen5w.kr.bridge
printf 'remove=../x\nremove=\nremove=12345678901234\n' > "$W/request"; rmrun
check 'a bad removal number is ignored' test ! -e "$W/rmcalls"
printf 'remove=558\n' > "$W/request"; UILOG_TEST_NEM=$W/no-such-nemesis UILOG_TEST_SH=/bin/sh runs
check 'without the NEMESIS tool nothing is removed' eval '[ "$(status removed)" = 558:failed:nemesis ] && [ -d "$N/apps/gen5w.kr.bridge" ]'
check 'a hook path that leaves the package folder is refused' eval 'printf "[nemesis]\npreuninstall=../../evil.sh\n" > "$N/apps/gen5w.kr.bridge/NEMESIS.data"; printf "remove=559\n" > "$W/request"; rmrun; [ "$(status removed)" = 559:failed:gen5w.kr.bridge ]'
rm -f "$W/request" "$W/rmcalls"

# adb over Wi-Fi: a one-time numbered command; runtime property only, adbd restarted only when the state changes.
reset; printf 'adb=on:111
' > "$W/request"; run
check 'adb=on sets the tcp port' test "$(cat "$W/adbport")" = 5555
check 'adb=on restarts adbd once' test "$(grep -c '^stop adbd' "$W/adbcalls")" = 1
check 'status reports adb on' test "$(status sw_adb)" = on
run
check 'adb=on again does not restart adbd' test "$(grep -c '^stop adbd' "$W/adbcalls")" = 1
check 'only the runtime property is set, never a persist one' eval '! grep -q "persist" "$W/adbcalls"'
# A reboot clears the runtime property, but the request file and the stored number stay: it must not come back on.
rm -f "$W/adbport" "$W/adbcalls"; run
check 'the old request file does not switch adb on again after a reboot' eval '[ ! -e "$W/adbcalls" ] && [ "$(status sw_adb)" = off ]'
printf 'adb=on:112
' > "$W/request"; run
check 'a new number switches adb on again' test "$(cat "$W/adbport")" = 5555
printf 'adb=off:113
' > "$W/request"; run
check 'adb=off clears the port' test "$(cat "$W/adbport")" = 0
check 'status reports adb off' test "$(status sw_adb)" = off
rm -f "$W/adbcalls"; run
check 'adb=off again does not restart adbd' test ! -e "$W/adbcalls"
printf 'adb=on
adb=on:
adb=on:x1
adb=on:12345678901
' > "$W/request"; rm -f "$W/adbcalls"; run
check 'adb without a valid number is ignored' test ! -e "$W/adbcalls"
reset; run
check 'with no request adbd is left alone' test ! -e "$W/adbcalls"
# A removal cut off by a restart: the lock and the working state are cleared at start.
reset; : > "$N/gen5wkr.ui-removing"; printf '77 working gen5w.kr.audio
' > "$N/gen5wkr.ui-removed"; run
check 'a stale removal lock is cleared at start' test ! -e "$N/gen5wkr.ui-removing"
check 'an interrupted removal is reported as failed' test "$(status removed)" = 77:failed:gen5w.kr.audio
rm -f "$W/request"
done_tests uilog
