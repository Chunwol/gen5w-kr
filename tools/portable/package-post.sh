#!/system/bin/sh
BASE=${0%/*}; [ "$BASE" != "$0" ] || BASE=.
BOOT=$(cat /proc/sys/kernel/random/boot_id) || exit 1
case "$BOOT" in ''|*[!a-f0-9-]*) exit 1;; esac
SH=${PORTABLE_TEST_SH:-/system/bin/sh}
TEST_ROOT=${PORTABLE_TEST_ROOT:-}
PLAN=${TEST_ROOT}/data/local/gen5w-portable/plan-$BOOT-$$
BOOT_STATE=${TEST_ROOT}/data/local/gen5w-portable/boot
NEMESIS_STATE=${TEST_ROOT}/data/nemesis
# APK installation was completed by NEMESIS before this hook.
# Verify the actual installed APK before enabling the modern native AA stream.
"$SH" "$BASE/core-ready.sh" verify || {
    echo "portable install: installed Core APK is not the bundled version; nothing changed" >&2
    if [ -f "$BOOT_STATE/update-held" ]; then "$SH" "$BASE/boot.sh" update-restore || :; fi
    exit 1
}
# Built-in Wi-Fi or USB dongle, decided before any /system change. It may turn
# Wi-Fi on for up to 8 s and off again; if Wi-Fi stays on, nothing is changed.
backend=$("$SH" "$BASE/wifi-backend.sh" detect) || {
    echo "portable install: Wi-Fi check failed ($backend); nothing changed" >&2
    if [ -f "$BOOT_STATE/update-held" ]; then "$SH" "$BASE/boot.sh" update-restore || :; fi
    exit 1
}
echo "portable install: Wi-Fi $backend"
wifi_reason=${backend#*'|'}
backend=${backend%%'|'*}
case "$backend" in
dongle) features='bt dipo gpm hotspot audio projection dongle';;
builtin|none) features='bt dipo gpm hotspot audio projection';;
*) exit 1;;
esac
"$SH" "$BASE/prepare.sh" "$PLAN" --stock-origins $features || {
    if [ -f "$BOOT_STATE/update-held" ]; then "$SH" "$BASE/boot.sh" update-restore || :; fi
    exit 1
}
# AP admission (match marker and system-UID restart guard), as the live-overlay
# arm does. Without it the AP broker refuses every request with "AP control not
# ready" and wireless never starts (car 2026-11-21). Before any /system change.
"$SH" "$BASE/ap.sh" prepare || {
    if [ -f "$BOOT_STATE/update-held" ]; then "$SH" "$BASE/boot.sh" update-restore || :; fi
    exit 1
}
"$SH" "$BASE/persistent-migrate.sh" apply "$PLAN/manifest" "$PLAN/stock-origins" || exit 1
# The migration finalizes any held live-overlay retirement only after all
# persistent targets and /system read-only state have been verified.
# This vehicle trial was explicitly requested with detailed diagnostics enabled.
[ ! -L "$NEMESIS_STATE/gen5wkr.debug-on" ] || exit 1
[ ! -e "$NEMESIS_STATE/gen5wkr.debug-on" ] || [ -f "$NEMESIS_STATE/gen5wkr.debug-on" ] || exit 1
: > "$NEMESIS_STATE/gen5wkr.debug-on" && chmod 644 "$NEMESIS_STATE/gen5wkr.debug-on" || exit 1
"$SH" "$BASE/persistent-start.sh" verify || exit 1
# Read by the dongle service and the in-car screen; before startup is enabled.
"$SH" "$BASE/wifi-backend.sh" record "$backend" "$wifi_reason" || exit 1
# Install the pre-zygote boot guard outside the package so uninstall cannot
# remove it while the /system hook line is still present.
GUARD=$TEST_ROOT/data/local/gen5w-portable/persistent/bootguard
[ ! -L "$GUARD" ] && [ ! -L "$GUARD/bin" ] || exit 1
mkdir -p "$GUARD/bin" && chmod 700 "$GUARD" "$GUARD/bin" || exit 1
for pair in "bootguard.sh guard.sh" "bootguard-restore.sh restore.sh" "bin/dex-patch bin/dex-patch"; do
    set -- $pair
    [ ! -L "$GUARD/$2" ] && cp "$BASE/$1" "$GUARD/$2.new" && chmod 700 "$GUARD/$2.new" && mv "$GUARD/$2.new" "$GUARD/$2" || exit 1
done
rm -f "$GUARD/tripped" "$GUARD/GEN5W-RECOVERY-RESULT.txt" && echo 0 > "$GUARD/count" && sync || exit 1
# Final prerequisite: retire the stock network-ADB switch without changing
# custom/disabled TCP ports. Recovery state is retained outside the package.
"$SH" "$BASE/network-adb.sh" apply || exit 1
"$SH" "$BASE/boot.sh" persistent-commit || {
    ADB_RESCUE=$TEST_ROOT/data/local/gen5w-portable/network-adb/restore.sh
    if [ -e "${ADB_RESCUE%/*}/journal" ]; then
        [ ! -L "$ADB_RESCUE" ] && "$SH" "$ADB_RESCUE" restore || echo "portable install: network ADB restore failed; retain external recovery journal" >&2
    fi
    exit 1
}
rm -f "$TEST_ROOT/data/local/gen5w-portable/persistent/recovery/transaction-committed" "$TEST_ROOT/data/local/gen5w-portable/persistent/recovery/transaction-in-progress" || exit 1
# Clear the authored UI hold only after the persistent transaction and its
# immutable restore originals are verified. AP reset evidence is independent.
[ ! -L "$NEMESIS_STATE/gen5wkr.ui-wireless-off" ] || exit 1
[ ! -e "$NEMESIS_STATE/gen5wkr.ui-wireless-off" ] || [ -f "$NEMESIS_STATE/gen5wkr.ui-wireless-off" ] || exit 1
rm -f "$NEMESIS_STATE/gen5wkr.ui-wireless-off" || exit 1
rm -f "$BOOT_STATE/update-held" "$BOOT_STATE/update-enabled" || exit 1
# split-default-applied is kept on update: the one-time split-screen default must not undo a later user OFF.
# Bundled Bluelink reminder service: keep the car's own reminder values for removal.
# It changes only that app's settings file; a failure leaves the reminder stock.
BL_TEST_DATA=${TEST_ROOT:+$TEST_ROOT/data} "$SH" "$BASE/bluelink/post.sh" || echo "portable install: Bluelink reminder values not saved; reminder left stock"
echo "portable install: persistent payload and immutable recovery manifest verified; one reboot is required; later starts do not restart Android"
