#!/system/bin/sh
# Exact APK/ODEX gate, atomic replacement, durable original kept on the unit.
set -eu
SYS=${HOTSPOT_TEST_SYS:-/system}
DATA=${HOTSPOT_TEST_DATA:-/data}
NEM=${HOTSPOT_TEST_NEM:-/system/xbin/nemesis}
PATCH=${HOTSPOT_TEST_PATCH:-./bin/hotspot-patch}
TARGET=$SYS/app/HKMC_WifiSettings.odex
APK=$SYS/app/HKMC_WifiSettings.apk
BACKUP=$SYS/etc/gen5w-kr-backup/local-hotspot
LOCK=$DATA/nemesis/gen5wkr.localhotspot.lock
ACTION=${1:-check}
case "$ACTION" in check|install|remove|status) ;; *) exit 2;; esac
safe_paths() {
    for p in "$SYS" "$SYS/app" "$SYS/etc" "$SYS/etc/gen5w-kr-backup" "$BACKUP" "$DATA" "$DATA/nemesis"; do
        [ ! -L "$p" ] || return 1
        [ ! -e "$p" ] || [ -d "$p" ] || return 1
    done
    for p in "$TARGET" "$APK" "$BACKUP/original.odex" "$TARGET.localhotspot.tmp"; do
        [ ! -L "$p" ] || return 1
        [ ! -e "$p" ] || [ -f "$p" ] || return 1
    done
    "$PATCH" verify "$APK" 48edb9bf294fd3ff8346c37beac7ae9252b41b1cbd0320a67ee96b21b9dc4dd6
}
check_target() {
    safe_paths || return 1
    if "$PATCH" original "$TARGET"; then return 0; fi
    "$PATCH" patched "$TARGET" && "$PATCH" original "$BACKUP/original.odex"
}
check_target || { echo 'FAIL: unsupported or modified V039 WifiSettings / missing original backup'; exit 1; }
case "$ACTION" in
    check|status) echo 'OK: exact V039 local hotspot target'; exit 0;;
esac
mkdir -p "$DATA/nemesis"
mkdir "$LOCK" || { echo 'FAIL: local hotspot operation is already running'; exit 1; }
mounted=no
finish() {
    if [ "$mounted" = yes ]; then "$NEM" remount ro >/dev/null 2>&1 || :; fi
    rmdir "$LOCK" 2>/dev/null || :
}
trap finish EXIT
trap 'exit 1' HUP INT TERM
check_target
"$NEM" remount rw
mounted=yes
mkdir -p "$BACKUP"
if [ "$ACTION" = install ]; then
    if "$PATCH" patched "$TARGET"; then echo 'OK: already applied'; exit 0; fi
    if [ -e "$BACKUP/original.odex" ]; then
        "$PATCH" original "$BACKUP/original.odex"
    else
        cp -p "$TARGET" "$BACKUP/original.odex"
        "$PATCH" original "$BACKUP/original.odex"
        sync
    fi
    # Never overwrite a previous incomplete temporary file.
    [ ! -e "$TARGET.localhotspot.tmp" ]
    "$PATCH" apply "$TARGET" "$TARGET.localhotspot.tmp"
    "$PATCH" patched "$TARGET.localhotspot.tmp"
else
    if "$PATCH" original "$TARGET"; then echo 'OK: already stock'; exit 0; fi
    "$PATCH" original "$BACKUP/original.odex"
    [ ! -e "$TARGET.localhotspot.tmp" ]
    cp -p "$BACKUP/original.odex" "$TARGET.localhotspot.tmp"
    "$PATCH" original "$TARGET.localhotspot.tmp"
fi
chmod 0644 "$TARGET.localhotspot.tmp"
chown 0:0 "$TARGET.localhotspot.tmp"
sync
if [ -z "${HOTSPOT_TEST_SYS:-}" ]; then
    am force-stop com.hkmc.wifisettings
fi
mv "$TARGET.localhotspot.tmp" "$TARGET"
if [ "$ACTION" = install ]; then "$PATCH" patched "$TARGET"; else "$PATCH" original "$TARGET"; fi
# Only this app's generated code cache, never other apps' data or settings.
rm -f "$DATA/dalvik-cache/system@app@HKMC_WifiSettings.apk@classes.dex"
sync
echo 'OK: restart the head unit to use the changed hotspot switch; backup retained'
