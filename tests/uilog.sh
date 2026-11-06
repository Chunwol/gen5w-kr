#!/bin/bash
# In-car screen collector: bounded, privacy-filtered copies of every gen5w package log.
. "$(dirname "$0")/lib.sh"
ROOT=$(cd "$(dirname "$0")/.." && pwd)
PKG=$ROOT/packages/core
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
mkdir -p "$W/bin" "$W/data/nemesis/logs" "$W/data/nemesis/apps/gen5w.kr.bridge" "$W/app" "$W/proc"
printf '#!/bin/sh\ncat "%s/backend" 2>/dev/null\n' "$W" > "$W/bin/getprop"; chmod +x "$W/bin/getprop"
export PATH="$W/bin:$PATH"
printf 'package-version=0.3.46\n' > "$W/data/nemesis/apps/gen5w.kr.bridge/NEMESIS.data"
UI=$W/app/gen5w-ui
LOGS=$W/data/nemesis/logs
mklog() { mkdir -p "$LOGS/$1"; cat > "$LOGS/$1/$2"; }
reset() { rm -rf "$UI" "$LOGS" "$W/data/nemesis/gen5wkr."* "$W/ready" "$W/backend"; mkdir -p "$LOGS"; : > "$W/logcat.out"; }
printf '#!/bin/sh\ncat "%s/logcat.out"\n' "$W" > "$W/logcat"; chmod +x "$W/logcat"
run() {
    UILOG_TEST_DATA=$W/data UILOG_TEST_DIR=${UILOG_DIR:-$UI} UILOG_TEST_ONCE=1 UILOG_TEST_LOGCAT=$W/logcat \
    UILOG_TEST_READY=$W/ready UILOG_TEST_PROC=$W/proc mksh "$PKG/scripts/uilog.sh" > "$W/out" 2>&1
}
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
check 'status has the snapshot keys' eval 'for k in ts host relay backend version apguard wired; do grep -q "^$k=" "$UI/status" || exit 1; done'
check 'status ts is a number' eval '[ -n "$(status ts)" ] && [ -z "$(status ts | tr -d 0-9)" ]'
check 'status reads the bridge version' test "$(status version)" = 0.3.46
check 'backend defaults to builtin' test "$(status backend)" = builtin
check 'host is dead without bridge-ready' test "$(status host)" = dead
check 'apguard on by default' test "$(status apguard)" = on
check 'not wired-only by default' test "$(status wired)" = no
check 'log keeps the bridge line verbatim' grep -qx "bridge|WAIT bridge: wireless is not in match mode (ap-match is not 'match')" "$UI/log"
check 'log includes another package log' grep -qx 'bluelink|bluelink: monthly reminder hidden' "$UI/log"
check 'bridge lines come first' eval '[ "$(head -1 "$UI/log" | cut -d"|" -f1)" = bridge ]'
check 'folder is 755' eval '[ "$(stat -c %a "$UI")" = 755 ]'
check 'files are 644' eval '[ "$(stat -c %a "$UI/status")" = 644 ] && [ "$(stat -c %a "$UI/log")" = 644 ]'
check 'no temp files are left' eval '[ "$(ls -A "$UI" | grep -vc "^\(status\|log\)$")" = 0 ]'
run
check 'a second run replaces the log instead of growing it' eval '[ "$(grep -c "^bluelink|" "$UI/log")" = 1 ]'

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
done_tests uilog
