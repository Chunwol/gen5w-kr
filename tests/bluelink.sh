#!/bin/bash
# Bluelink reminder: hides the monthly signup screen by keeping its reminder
# time far in the future, keeps every other setting, and puts the car's own
# values back on removal.
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
pass=0; fail=0
check() { local name=$1; shift; if "$@"; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL $name"; fi; }
. "$ROOT/tests/unit/shim.sh"
unit_shim_setup || exit 1
W=$(mktemp -d); trap 'rm -rf "$W"; unit_shim_cleanup' EXIT
PKG=$W/pkg; mkdir -p "$PKG" "$W/bin" "$W/sys/app"
cp -r "$ROOT/packages/bluelink-quiet/scripts" "$ROOT/packages/bluelink-quiet/NEMESIS.data" "$PKG/"
printf '#!/bin/sh\nexit 0\n' > "$W/bin/chown"
printf '#!/bin/sh\n[ "$1" = sys.boot_completed ] && echo 1\n' > "$W/bin/getprop"
chmod 755 "$W/bin/"*
echo vrm > "$W/sys/app/HKMC_TAppVRM.odex"; echo svc > "$W/sys/app/HKMC_TAppService.odex"
VRM=$(md5sum "$W/sys/app/HKMC_TAppVRM.odex" | cut -d' ' -f1)
SVC=$(md5sum "$W/sys/app/HKMC_TAppService.odex" | cut -d' ' -f1)
DIR=$W/data/data/com.hkmc.telematics.service/shared_prefs
PREFS=$DIR/shard_service_activation_start_setting.xml
FAR=4102444800000
run() {
    PATH=$W/bin:$PATH BL_TEST_DATA=$W/data BL_TEST_SYS=$W/sys BL_TEST_ONCE=1 \
    BL_TEST_VRM_MD5=$VRM BL_TEST_SERVICE_MD5=$SVC BL_TEST_GETPROP=$W/bin/getprop \
    mksh "$PKG/scripts/$1.sh" >/dev/null 2>&1
}
fresh() { rm -rf "$W/data"; mkdir -p "$DIR"; }
has() { grep -qF "$1" "$PREFS"; }
dismissed() {
    cat > "$PREFS" <<'X'
<?xml version='1.0' encoding='utf-8' standalone='yes' ?>
<map>
    <string name="other_key">keep &amp; me</string>
    <long name="extra_remind_time" value="1761955200000" />
    <boolean name="extra_remind_value" value="true" />
</map>
X
}

# Gate: only the checked stock apps.
fresh
check 'pre accepts the stock V039 apps' run pre
echo changed > "$W/sys/app/HKMC_TAppVRM.odex"
run pre; check 'pre skips other Bluelink builds (77)' test $? = 77
dismissed; run post; run quiet
check 'other builds keep the stock reminder' has 'value="1761955200000"'
echo vrm > "$W/sys/app/HKMC_TAppVRM.odex"
# The built-in values are the official V039 files' md5 (from the V039 system image).
check 'built-in VRM md5 is the official V039 value' grep -q 'VRM_V039=${BL_TEST_VRM_MD5:-5689fb31a761a5696eb2bbe0801a0f77}' "$PKG/scripts/common.sh"
check 'built-in service md5 is the official V039 value' grep -q 'SERVICE_V039=${BL_TEST_SERVICE_MD5:-0778d4b95ee51a97a555aec4fdcc6c3f}' "$PKG/scripts/common.sh"
echo changed > "$W/sys/app/HKMC_TAppVRM.odex"
out=$(PATH=$W/bin:$PATH BL_TEST_DATA=$W/data BL_TEST_SYS=$W/sys BL_TEST_VRM_MD5=$VRM BL_TEST_SERVICE_MD5=$SVC mksh "$PKG/scripts/pre.sh" 2>&1)
check 'skip message shows this unit md5 values' eval '[[ "$out" == *"VRM=$(md5sum "$W/sys/app/HKMC_TAppVRM.odex" | cut -d" " -f1)"* && "$out" == *"SERVICE=$SVC"* ]]'
echo vrm > "$W/sys/app/HKMC_TAppVRM.odex"

# Car that pressed "30 일간 보지 않기" before.
fresh; dismissed
check 'post saves the original values' run post
check 'saved original time' grep -qF 'value="1761955200000"' "$W/data/nemesis/gen5wkr.bluelink/orig-lines"
check 'service runs' run quiet
check 'reminder time set far ahead' has "name=\"extra_remind_time\" value=\"$FAR\""
check 'reminder value kept true' has 'name="extra_remind_value" value="true"'
check 'old time removed' eval '! grep -qF 1761955200000 "$PREFS"'
check 'other setting kept byte for byte' has '    <string name="other_key">keep &amp; me</string>'
check 'one time entry only' test "$(grep -c extra_remind_time "$PREFS")" = 1
check 'map closed once at the end' test "$(tail -n1 "$PREFS")" = '</map>'
check 'no temp file left' test ! -e "$DIR/.gen5w-bluelink.tmp"
before=$(md5sum < "$PREFS"); run quiet
check 'already hidden: file not rewritten' test "$(md5sum < "$PREFS")" = "$before"
# The stock service restores an older time from a driver profile.
dismissed; run quiet
check 'restored older time is hidden again' has "value=\"$FAR\""
check 'reinstall keeps the first original' run post
check 'original not replaced by our time' eval '! grep -qF "$FAR" "$W/data/nemesis/gen5wkr.bluelink/orig-lines"'
check 'removal succeeds' run preun
check 'second preuninstall after removal succeeds (NEMESIS 1.16)' run preun
check 'removal restores the original time' has 'value="1761955200000"'
check 'removal drops our time' eval '! grep -qF "$FAR" "$PREFS"'
check 'removal keeps other settings' has 'keep &amp; me'
check 'removal clears package state' test ! -e "$W/data/nemesis/gen5wkr.bluelink"

# Car that never dismissed it (no file yet).
fresh; run post; run quiet
check 'missing file is created' has "value=\"$FAR\""
check 'created file is a settings map' has '<map>'
run preun
check 'removal drops our values when there were none' eval '! grep -q extra_remind "$PREFS"'
check 'removal leaves a valid empty map' test "$(grep -c map "$PREFS")" = 2

# Empty map written as <map />.
fresh; printf "<?xml version='1.0' encoding='utf-8' standalone='yes' ?>\n<map />\n" > "$PREFS"
run post; run quiet
check 'empty map gets our values' has "value=\"$FAR\""
check 'empty map opened and closed once' test "$(grep -c '<map>' "$PREFS"):$(grep -c '</map>' "$PREFS")" = 1:1

# Unknown file shape is never touched.
fresh; echo 'not xml' > "$PREFS"; run post; run quiet
check 'unknown file shape left unchanged' test "$(cat "$PREFS")" = 'not xml'

# Stop marker: nothing written while removal runs.
fresh; dismissed; run post; echo stop > "$W/data/nemesis/gen5wkr.bluelink/stopping"; run quiet
check 'stopping service writes nothing' has 'value="1761955200000"'

# Turned off from the in-car screen: the car's own values come back, and stay.
fresh; dismissed; run post; run quiet
check 'screen switch: hidden before turning off' has "value=\"$FAR\""
touch "$W/data/nemesis/gen5wkr.ui-bluelink-off"
run quiet
check 'screen switch off restores the original time' has 'value="1761955200000"'
check 'screen switch off drops our time' eval '! grep -qF "$FAR" "$PREFS"'
check 'screen switch off keeps other settings' has 'keep &amp; me'
before=$(md5sum < "$PREFS"); run quiet
check 'screen switch off: a second pass leaves the file alone' test "$(md5sum < "$PREFS")" = "$before"
rm -f "$W/data/nemesis/gen5wkr.ui-bluelink-off"
run quiet
check 'screen switch on hides the reminder again' has "value=\"$FAR\""
check 'original values are still the first ones after toggling' grep -qF 'value="1761955200000"' "$W/data/nemesis/gen5wkr.bluelink/orig-lines"
# A car that never had the values: turning off removes ours and leaves a valid map.
fresh; run post; run quiet
touch "$W/data/nemesis/gen5wkr.ui-bluelink-off"; run quiet
check 'screen switch off with no original values drops ours' eval '! grep -q extra_remind "$PREFS"'
check 'screen switch off leaves a valid map' test "$(grep -c map "$PREFS")" = 2
rm -f "$W/data/nemesis/gen5wkr.ui-bluelink-off"

# No Bluelink app data: nothing created.
rm -rf "$W/data"; mkdir -p "$W/data"; run post; run quiet
check 'no app data dir: nothing created' test ! -e "$W/data/data"

unit_shim_report || fail=$((fail+1))
echo "== bluelink: $pass passed, $fail failed"
[ $fail = 0 ]
