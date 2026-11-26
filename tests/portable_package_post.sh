#!/bin/bash
set -eu
cd "$(dirname "$0")/.."
command -v mksh >/dev/null 2>&1 || { echo 'mksh not found'; exit 78; }
t=$(mktemp -d)
trap 'rc=$?; rm -rf "$t"; exit $rc' EXIT
pkg=$t/package; root=$t/root; actions=$t/actions
mkdir -p "$pkg" "$root/data/nemesis" "$root/data/local/gen5w-portable/boot" "$actions"
cp tools/portable/package-post.sh "$pkg/package-post.sh"
cp tools/portable/bootguard.sh "$pkg/bootguard.sh"
cp tools/portable/recovery-usb/restore.sh "$pkg/bootguard-restore.sh"
mkdir -p "$pkg/bin" "$pkg/bluelink"
cp packages/bluelink-quiet/scripts/*.sh "$pkg/bluelink/"
mkdir -p "$root/data/data/com.hkmc.telematics.service/shared_prefs"
printf '%s\n' "<?xml version='1.0' encoding='utf-8' standalone='yes' ?>" '<map>' '    <long name="extra_remind_time" value="1700000000000" />' '</map>' \
    > "$root/data/data/com.hkmc.telematics.service/shared_prefs/shard_service_activation_start_setting.xml"
printf 'fixture helper\n' > "$pkg/bin/dex-patch"
touch "$root/data/nemesis/gen5wkr.ui-wireless-off"
cat > "$t/adapter" <<'EOF'
#!/bin/sh
set -eu
root=$PORTABLE_TEST_ROOT
actions=$PORTABLE_TEST_ACTIONS
script=$1; shift
name=${script##*/}
case "$name:$*" in
core-ready.sh:verify)
    echo core-ready >> "$actions/log"
    [ "${PORTABLE_TEST_FAIL_CORE:-0}" = 0 ] || exit 48;;
prepare.sh:*)
    case " $* " in *' dongle '*) echo prepare-dongle >> "$actions/log";; *) echo prepare >> "$actions/log";; esac
    [ "$2" = --stock-origins ] || exit 40
    [ "$3 $4 $5 $6 $7 $8" = 'bt dipo gpm hotspot audio projection' ] || exit 45
    mkdir -p "$1"
    printf 'manifest\n' > "$1/manifest"
    printf 'stock-origins\n' > "$1/stock-origins";;
wifi-backend.sh:detect)
    echo wifi-detect >> "$actions/log"
    echo "${PORTABLE_TEST_WIFI:-builtin|observed}"
    case "${PORTABLE_TEST_WIFI:-builtin}" in error*) exit 1;; esac;;
wifi-backend.sh:record\ *)
    echo "wifi-record $2" >> "$actions/log";;
ap.sh:prepare)
    echo ap-prepare >> "$actions/log"
    [ "${PORTABLE_TEST_FAIL_AP:-0}" = 0 ] || exit 44;;
persistent-migrate.sh:apply\ *)
    echo migrate >> "$actions/log"
    [ "${PORTABLE_TEST_FAIL_MIGRATE:-0}" = 0 ] || exit 41
    mkdir -p "$root/data/local/gen5w-portable/persistent/recovery/originals"
    printf 'recovery\n' > "$root/data/local/gen5w-portable/persistent/recovery/manifest"
    : > "$root/data/local/gen5w-portable/persistent/recovery/transaction-committed"
    : > "$root/data/local/gen5w-portable/persistent/recovery/transaction-in-progress";;
persistent-start.sh:verify)
    echo verify >> "$actions/log"
    [ -s "$root/data/local/gen5w-portable/persistent/recovery/manifest" ];;
network-adb.sh:apply)
    echo network-adb-apply >> "$actions/log"
    [ "${PORTABLE_TEST_FAIL_ADB:-0}" = 0 ] || exit 46
    mkdir -p "$root/data/local/gen5w-portable/network-adb"
    : > "$root/data/local/gen5w-portable/network-adb/journal";;
restore.sh:restore)
    echo network-adb-restore >> "$actions/log"
    rm -f "$root/data/local/gen5w-portable/network-adb/journal";;
boot.sh:persistent-commit)
    echo persistent-commit >> "$actions/log"
    [ "${PORTABLE_TEST_FAIL_COMMIT:-0}" = 0 ] || exit 47
    printf '1\n' > "$root/data/local/gen5w-portable/boot/enabled";;
post.sh:)
    echo bluelink-save >> "$actions/log"
    [ "$BL_TEST_DATA" = "$root/data" ] || exit 43
    mksh "$script";;
boot.sh:update-restore)
    echo update-restore >> "$actions/log";;
*) echo "unexpected call: $name $*" >&2; exit 42;;
esac
EOF
chmod +x "$t/adapter"
: > "$root/data/local/gen5w-portable/split-default-applied"
run() {
    PORTABLE_TEST_ROOT="$root" PORTABLE_TEST_SH="$t/adapter" PORTABLE_TEST_ACTIONS="$actions" \
        PORTABLE_TEST_FAIL_CORE="${PORTABLE_TEST_FAIL_CORE:-0}" PORTABLE_TEST_FAIL_ADB="${PORTABLE_TEST_FAIL_ADB:-0}" PORTABLE_TEST_FAIL_COMMIT="${PORTABLE_TEST_FAIL_COMMIT:-0}" PORTABLE_TEST_FAIL_MIGRATE="${PORTABLE_TEST_FAIL_MIGRATE:-0}" PORTABLE_TEST_FAIL_AP="${PORTABLE_TEST_FAIL_AP:-0}" PORTABLE_TEST_WIFI="${PORTABLE_TEST_WIFI:-builtin|observed}" \
        mksh "$pkg/package-post.sh"
}

if PORTABLE_TEST_FAIL_CORE=1 run > "$t/core-fail" 2>&1; then
 echo 'FAIL package-post accepted an old installed Core'; exit 1
fi
[ "$(cat "$actions/log")" = core-ready ]
[ ! -e "$root/data/local/gen5w-portable/boot/enabled" ]
[ -f "$root/data/nemesis/gen5wkr.ui-wireless-off" ]
rm -f "$actions/log"
echo 'PASS package-post refuses old Core before Wi-Fi, prepare, migration or system writes'

: > "$root/data/local/gen5w-portable/boot/update-held"
if PORTABLE_TEST_FAIL_CORE=1 run > "$t/core-held-fail" 2>&1; then
 echo 'FAIL package-post accepted old Core during held update'; exit 1
fi
[ "$(cat "$actions/log")" = "$(printf 'core-ready\nupdate-restore')" ]
rm -f "$actions/log" "$root/data/local/gen5w-portable/boot/update-held"
echo 'PASS package-post restores held update after Core admission failure'


: > "$root/data/local/gen5w-portable/split-default-applied"
run
guard=$root/data/local/gen5w-portable/persistent/bootguard
cmp tools/portable/bootguard.sh "$guard/guard.sh"
cmp tools/portable/recovery-usb/restore.sh "$guard/restore.sh"
cmp "$pkg/bin/dex-patch" "$guard/bin/dex-patch"
[ -x "$guard/guard.sh" ] && [ -x "$guard/restore.sh" ] && [ -x "$guard/bin/dex-patch" ]
[ "$(cat "$guard/count")" = 0 ]
[ ! -e "$guard/tripped" ]
[ "$(cat "$actions/log")" = "$(printf 'core-ready\nwifi-detect\nprepare\nap-prepare\nmigrate\nverify\nwifi-record builtin\nnetwork-adb-apply\npersistent-commit\nbluelink-save')" ]
grep -qx '    <long name="extra_remind_time" value="1700000000000" />' "$root/data/nemesis/gen5wkr.bluelink/orig-lines"
[ "$(cat "$root/data/local/gen5w-portable/boot/enabled")" = 1 ]
[ -f "$root/data/nemesis/gen5wkr.debug-on" ]
[ ! -e "$root/data/nemesis/gen5wkr.ui-wireless-off" ]
[ ! -e "$root/data/local/gen5w-portable/persistent/recovery/transaction-committed" ]
[ ! -e "$root/data/local/gen5w-portable/persistent/recovery/transaction-in-progress" ]
[ -e "$root/data/local/gen5w-portable/split-default-applied" ]
! grep -qiE 'zygote|reboot|arm ' "$actions/log"
echo 'PASS package-post commits persistent startup only after original prep, migration and recovery verification'

rm -rf "$root/data/local/gen5w-portable" "$root/data/nemesis" "$actions/log"
mkdir -p "$root/data/nemesis" "$root/data/local/gen5w-portable/boot"
touch "$root/data/nemesis/gen5wkr.ui-wireless-off"
if PORTABLE_TEST_FAIL_MIGRATE=1 run >/dev/null 2>&1; then
    echo 'FAIL package-post accepted an incomplete persistent migration'; exit 1
fi
[ "$(cat "$actions/log")" = "$(printf 'core-ready\nwifi-detect\nprepare\nap-prepare\nmigrate')" ]
[ ! -e "$root/data/local/gen5w-portable/boot/enabled" ]
[ ! -e "$root/data/nemesis/gen5wkr.debug-on" ]
[ -f "$root/data/nemesis/gen5wkr.ui-wireless-off" ]
echo 'PASS package-post refuses before commit and preserves the wireless hold when migration fails'

# Car 2026-11-21: the persistent path never ran ap.sh prepare, so the AP broker
# refused every request ("AP control not ready") and wireless never started.
# The AP admission must be prepared before /system changes, and its failure
# must stop the install before migration.
rm -rf "$root/data/local/gen5w-portable" "$root/data/nemesis" "$actions/log"
mkdir -p "$root/data/nemesis" "$root/data/local/gen5w-portable/boot"
touch "$root/data/nemesis/gen5wkr.ui-wireless-off"
if PORTABLE_TEST_FAIL_AP=1 run >/dev/null 2>&1; then
    echo 'FAIL package-post continued without AP match-mode admission'; exit 1
fi
[ "$(cat "$actions/log")" = "$(printf 'core-ready\nwifi-detect\nprepare\nap-prepare')" ]
[ ! -e "$root/data/local/gen5w-portable/boot/enabled" ]
[ -f "$root/data/nemesis/gen5wkr.ui-wireless-off" ]
echo 'PASS package-post prepares AP admission before migration and stops if it fails'

# Install-time Wi-Fi choice: a dongle adds the stand-in feature and is recorded
# before startup is enabled; a failed Wi-Fi check changes nothing.
rm -rf "$root/data/local/gen5w-portable" "$root/data/nemesis" "$actions/log"
mkdir -p "$root/data/nemesis" "$root/data/local/gen5w-portable/boot"
PORTABLE_TEST_WIFI='dongle|probe-none' run > "$t/out"
grep -qx 'portable install: Wi-Fi dongle|probe-none' "$t/out"
[ "$(cat "$actions/log")" = "$(printf 'core-ready\nwifi-detect\nprepare-dongle\nap-prepare\nmigrate\nverify\nwifi-record dongle\nnetwork-adb-apply\npersistent-commit\nbluelink-save')" ]
echo 'PASS package-post installs the dongle stand-in when the Wi-Fi check chose the dongle'

rm -rf "$root/data/local/gen5w-portable" "$root/data/nemesis" "$actions/log"
mkdir -p "$root/data/nemesis" "$root/data/local/gen5w-portable/boot"
PORTABLE_TEST_WIFI='none|probe-none' run > "$t/out"
grep -qx 'wifi-record none' "$actions/log" && ! grep -q prepare-dongle "$actions/log"
echo 'PASS package-post installs like built-in Wi-Fi and records none when neither is found'

rm -rf "$root/data/local/gen5w-portable" "$root/data/nemesis" "$actions/log"
mkdir -p "$root/data/nemesis" "$root/data/local/gen5w-portable/boot"
touch "$root/data/nemesis/gen5wkr.ui-wireless-off"
if PORTABLE_TEST_WIFI='error|wifi-still-on' run >/dev/null 2>&1; then
    echo 'FAIL package-post continued after Wi-Fi stayed on'; exit 1
fi
[ "$(cat "$actions/log")" = "$(printf 'core-ready\nwifi-detect')" ]
[ ! -e "$root/data/local/gen5w-portable/boot/enabled" ]
[ -f "$root/data/nemesis/gen5wkr.ui-wireless-off" ]
echo 'PASS package-post stops before any change when the Wi-Fi check fails'

# A failed network migration cannot enable boot. A failed boot commit must
# release the external network-ADB ownership journal through its retained helper.
for stage in adb commit; do
 rm -rf "$root/data/local/gen5w-portable" "$root/data/nemesis" "$actions/log"
 mkdir -p "$root/data/nemesis" "$root/data/local/gen5w-portable/boot"
 touch "$root/data/nemesis/gen5wkr.ui-wireless-off"
 if [ "$stage" = adb ]; then
  if PORTABLE_TEST_FAIL_ADB=1 run > "$t/out" 2>&1; then echo 'FAIL accepted ADB migration failure'; exit 1; fi
  ! grep -q persistent-commit "$actions/log"
 else
  if PORTABLE_TEST_FAIL_COMMIT=1 run > "$t/out" 2>&1; then echo 'FAIL accepted commit failure'; exit 1; fi
  [ "$(tail -n 2 "$actions/log")" = "$(printf 'persistent-commit\nnetwork-adb-restore')" ]
  [ ! -e "$root/data/local/gen5w-portable/network-adb/journal" ]
 fi
 [ ! -e "$root/data/local/gen5w-portable/boot/enabled" ]
 [ -f "$root/data/nemesis/gen5wkr.ui-wireless-off" ]
done
echo 'PASS package-post fences ADB failure and restores owned ADB settings on commit failure'
