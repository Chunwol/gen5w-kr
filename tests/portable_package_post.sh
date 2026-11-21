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
prepare.sh:*)
    echo prepare >> "$actions/log"
    [ "$2" = --stock-origins ] || exit 40
    mkdir -p "$1"
    printf 'manifest\n' > "$1/manifest"
    printf 'stock-origins\n' > "$1/stock-origins";;
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
boot.sh:persistent-commit)
    echo persistent-commit >> "$actions/log"
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
run() {
    PORTABLE_TEST_ROOT="$root" PORTABLE_TEST_SH="$t/adapter" PORTABLE_TEST_ACTIONS="$actions" \
        PORTABLE_TEST_FAIL_MIGRATE="${PORTABLE_TEST_FAIL_MIGRATE:-0}" PORTABLE_TEST_FAIL_AP="${PORTABLE_TEST_FAIL_AP:-0}" \
        mksh "$pkg/package-post.sh"
}

run
guard=$root/data/local/gen5w-portable/persistent/bootguard
cmp tools/portable/bootguard.sh "$guard/guard.sh"
cmp tools/portable/recovery-usb/restore.sh "$guard/restore.sh"
cmp "$pkg/bin/dex-patch" "$guard/bin/dex-patch"
[ -x "$guard/guard.sh" ] && [ -x "$guard/restore.sh" ] && [ -x "$guard/bin/dex-patch" ]
[ "$(cat "$guard/count")" = 0 ]
[ ! -e "$guard/tripped" ]
[ "$(cat "$actions/log")" = "$(printf 'prepare\nap-prepare\nmigrate\nverify\npersistent-commit\nbluelink-save')" ]
grep -qx '    <long name="extra_remind_time" value="1700000000000" />' "$root/data/nemesis/gen5wkr.bluelink/orig-lines"
[ "$(cat "$root/data/local/gen5w-portable/boot/enabled")" = 1 ]
[ -f "$root/data/nemesis/gen5wkr.debug-on" ]
[ ! -e "$root/data/nemesis/gen5wkr.ui-wireless-off" ]
[ ! -e "$root/data/local/gen5w-portable/persistent/recovery/transaction-committed" ]
[ ! -e "$root/data/local/gen5w-portable/persistent/recovery/transaction-in-progress" ]
! grep -qiE 'zygote|reboot|arm ' "$actions/log"
echo 'PASS package-post commits persistent startup only after original prep, migration and recovery verification'

rm -rf "$root/data/local/gen5w-portable" "$root/data/nemesis" "$actions/log"
mkdir -p "$root/data/nemesis" "$root/data/local/gen5w-portable/boot"
touch "$root/data/nemesis/gen5wkr.ui-wireless-off"
if PORTABLE_TEST_FAIL_MIGRATE=1 run >/dev/null 2>&1; then
    echo 'FAIL package-post accepted an incomplete persistent migration'; exit 1
fi
[ "$(cat "$actions/log")" = "$(printf 'prepare\nap-prepare\nmigrate')" ]
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
[ "$(cat "$actions/log")" = "$(printf 'prepare\nap-prepare')" ]
[ ! -e "$root/data/local/gen5w-portable/boot/enabled" ]
[ -f "$root/data/nemesis/gen5wkr.ui-wireless-off" ]
echo 'PASS package-post prepares AP admission before migration and stops if it fails'
