#!/system/bin/sh
# Exact APK/ODEX gate, atomic replacement, durable original kept on the unit.
set -eu
SYS=${HOTSPOT_TEST_SYS:-/system}
DATA=${HOTSPOT_TEST_DATA:-/data}
NEM=${HOTSPOT_TEST_NEM:-/system/xbin/nemesis}
MOUNTS=${HOTSPOT_TEST_MOUNTS:-/proc/self/mounts}
SCRIPT_DIR=${0%/*}
DEFAULT_PATCH=$SCRIPT_DIR/../bin/hotspot-patch
[ ! -f "$SCRIPT_DIR/hotspot-patch" ] || DEFAULT_PATCH=$SCRIPT_DIR/hotspot-patch
PATCH=${HOTSPOT_TEST_PATCH:-$DEFAULT_PATCH}
[ ! -f "$SCRIPT_DIR/errors.sh" ] || . "$SCRIPT_DIR/errors.sh"
TARGET=$SYS/app/HKMC_WifiSettings.odex
APK=$SYS/app/HKMC_WifiSettings.apk
BACKUP=$SYS/etc/gen5w-kr-backup/local-hotspot
LOCK=$DATA/nemesis/gen5wkr.localhotspot.lock
ACTION=${1:-check}
case "$ACTION" in check|install|remove|status) ;; *) exit 2;; esac
if [ -z "${HOTSPOT_TEST_PATCH:-}" ]; then chmod 0755 "$PATCH"; fi
safe_paths() {
    for p in "$SYS" "$SYS/app" "$SYS/etc" "$SYS/etc/gen5w-kr-backup" "$BACKUP" "$DATA" "$DATA/nemesis"; do
        [ ! -L "$p" ] || return 1
        [ ! -e "$p" ] || [ -d "$p" ] || return 1
    done
    for p in "$TARGET" "$APK" "$BACKUP/original.odex" "$TARGET.localhotspot.tmp" "$TARGET.localhotspot.rollback" "$BACKUP/hotspot-patch" "$BACKUP/recover.sh" "$BACKUP/errors.sh"; do
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
if [ -e "$LOCK" ] || [ -L "$LOCK" ]; then
    [ -d "$LOCK" ] && [ ! -L "$LOCK" ] || exit 1
    owner=
    [ ! -L "$LOCK/owner" ] || exit 1
    [ ! -f "$LOCK/owner" ] || IFS= read -r owner < "$LOCK/owner"
    case "$owner" in
        ''|*[!0-9]*)
            # Legacy releases left an empty directory. Only a removal may
            # recover it; a new install must not guess about an unknown owner.
            [ "$ACTION" = remove ] && rmdir "$LOCK" || exit 1;;
        *)
            if kill -0 "$owner" 2>/dev/null; then echo 'FAIL: local hotspot operation is already running'; exit 1; fi
            rm -f "$LOCK/owner"
            rmdir "$LOCK" || exit 1;;
    esac
fi
mkdir "$LOCK" || exit 1
echo "$$" > "$LOCK/owner"
mounted=no
changed=no
restore_stock() {
    "$PATCH" original "$BACKUP/original.odex" || return 1
    cp -p "$BACKUP/original.odex" "$TARGET.localhotspot.rollback" &&
        "$PATCH" original "$TARGET.localhotspot.rollback" &&
        mv "$TARGET.localhotspot.rollback" "$TARGET" &&
        "$PATCH" original "$TARGET"
}
system_readwrite() {
    if command -v err_mount >/dev/null 2>&1; then
        err_mount hotspot rw "$NEM"
    else
        # Older durable recovery copies must still work without a helper.
        "$NEM" remount rw
    fi
}
verified_result() {
    check_target || return 1
    if [ "$ACTION" = install ]; then
        "$PATCH" patched "$TARGET" && "$PATCH" original "$BACKUP/original.odex"
    else
        "$PATCH" original "$TARGET"
    fi
}
system_mount_state() {
    mount_count=0 mount_state=unknown
    if [ -f "$MOUNTS" ] && [ ! -L "$MOUNTS" ]; then
        while IFS=' ' read -r source point kind options rest; do
            [ "$point" = "$SYS" ] || continue
            mount_count=$((mount_count + 1))
            echo "DETAIL local hotspot system mount: $source $point $kind $options"
            case ",$options," in
                *,rw,*) mount_state=rw;;
                *,ro,*) mount_state=ro;;
                *) mount_state=unknown;;
            esac
        done < "$MOUNTS"
    fi
    [ "$mount_count" = 1 ] || mount_state=unknown
}
system_readonly() {
    ro_attempt=0 ro_busy=yes
    sync
    while [ "$ro_attempt" -lt 3 ]; do
        ro_attempt=$((ro_attempt + 1))
        ro_reason=unknown ro_rc=0
        if command -v err_classify_stream >/dev/null 2>&1; then
            if "$NEM" remount ro 2>&1 | err_classify_stream; then
                ro_statuses=("${PIPESTATUS[@]}")
            else
                ro_statuses=("${PIPESTATUS[@]}")
            fi
            ro_rc=${ro_statuses[0]}
            case "${ro_statuses[1]}" in
                10) ro_reason=permission;; 11) ro_reason=busy;; 12) ro_reason=missing;;
                13) ro_reason=no-space;; 14) ro_reason=read-only;; 15) ro_reason=io;; 16) ro_reason=timeout;;
            esac
            [ "$ro_rc" != 0 ] || return 0
            err_event hotspot mount ro failed "$ro_rc" "$ro_reason"
        else
            # Older durable recovery may lack the helper. Never capture raw
            # output; missing diagnostics cannot authorize the busy exception.
            "$NEM" remount ro >/dev/null 2>&1 && return 0
        fi
        echo "DETAIL local hotspot remount ro attempt $ro_attempt: reason=$ro_reason"
        [ "$ro_reason" = busy ] || ro_busy=no
        [ "$ro_attempt" = 3 ] || sleep 1
    done
    system_mount_state
    # A transient busy remount does not invalidate verified bytes. The normal
    # installer reboot mounts /system read-only again. Never suppress unknown
    # errors, missing/ambiguous mount observations or a failed byte validation.
    if [ "$ro_busy" = yes ] && [ "$mount_state" = rw ] && verified_result; then
        echo 'WARN: verified local hotspot files; system read-only remount busy; reboot required'
        return 0
    fi
    echo 'FAIL: could not remount system read-only'
    return 1
}
finish() {
    result=$?
    trap - EXIT
    if [ "$mounted" = yes ] && ! system_readonly; then
        result=1
    fi
    if [ "$result" != 0 ] && [ "$ACTION" = install ] && [ "$changed" = yes ]; then
        if system_readwrite && restore_stock; then
            echo 'RESTORED: installation failed; original WifiSettings restored'
            rm -f "$DATA/dalvik-cache/system@app@HKMC_WifiSettings.apk@classes.dex"
            sync
        else
            echo 'RECOVERY REQUIRED: original backup retained'
        fi
        system_readonly || :
    fi
    rm -f "$LOCK/owner"
    rmdir "$LOCK" 2>/dev/null || :
    exit "$result"
}
trap finish EXIT
trap 'exit 1' HUP INT TERM
check_target
system_readwrite
mounted=yes
mkdir -p "$BACKUP"
# Keep a verified recovery tool on /system, including after /data is reset.
if [ "$ACTION" = install ]; then
    cp "$PATCH" "$BACKUP/hotspot-patch"
    cp "$0" "$BACKUP/recover.sh"
    [ ! -f "$SCRIPT_DIR/errors.sh" ] || cp "$SCRIPT_DIR/errors.sh" "$BACKUP/errors.sh"
    chmod 0755 "$BACKUP/hotspot-patch"
fi
if [ -e "$TARGET.localhotspot.tmp" ]; then
    # Preserve interrupted output rather than overwriting evidence.
    [ ! -e "$BACKUP/interrupted.$$" ] || exit 1
    mv "$TARGET.localhotspot.tmp" "$BACKUP/interrupted.$$"
fi
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
changed=yes
if [ "$ACTION" = install ]; then "$PATCH" patched "$TARGET"; else "$PATCH" original "$TARGET"; fi
# Only this app's generated code cache, never other apps' data or settings.
rm -f "$DATA/dalvik-cache/system@app@HKMC_WifiSettings.apk@classes.dex"
sync
echo 'OK: restart the head unit to use the changed hotspot switch; backup retained'
