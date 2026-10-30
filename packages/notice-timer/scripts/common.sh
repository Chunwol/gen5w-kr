# Owned, hash-verified SystemUI ODEX replacement. mksh + Android toolbox only.
# Each entry point sets SCRIPT_DIR explicitly, including bin/status.sh.
. "$SCRIPT_DIR/recipe-v039.sh"
SYS=${NOTICE_TEST_SYS:-/system}
DATA=${NOTICE_TEST_DATA:-/data}
NEM=${NOTICE_TEST_NEM:-/system/xbin/nemesis}
TOOL=${NOTICE_TEST_TOOL:-$SCRIPT_DIR/../bin/notice-patch-v039}
TARGET=$SYS/priv-app/SystemUI.odex
STATE=$SYS/etc/gen5w-kr-backup/notice
MARK=$DATA/nemesis/backup/gen5w.kr.notice
OWNER=gen5w.kr.notice:$NOTICE_RECIPE
NOREBOOT=$DATA/nemesis/gen5wkr.noreboot

log() { echo "$1"; }
# Drop any stale optimized copy so the newly written /system ODEX is the one the
# next boot loads. Leaving a mismatched dalvik-cache entry can fail class load.
DALVIK_ROOTS=${NOTICE_TEST_DALVIK:-"/data/dalvik-cache /data/dalvik-cache/arm /cache/dalvik-cache"}
wipe_dalvik() {
    local _d _f
    for _d in $DALVIK_ROOTS; do
        [ -d "$_d" ] || continue
        [ ! -L "$_d" ] || return 1
        for _f in "$_d"/*SystemUI*; do
            [ -e "$_f" ] || continue
            rm -f "$_f" || return 1
            [ ! -e "$_f" ] || return 1
        done
    done
    return 0
}
original() { [ -f "$1" ] && [ ! -L "$1" ] && "$TOOL" original "$1"; }
patched() { [ -f "$1" ] && [ ! -L "$1" ] && "$TOOL" patched "$1"; }
owned() { [ -f "$STATE/owner" ] && [ ! -L "$STATE/owner" ] && [ "$(cat "$STATE/owner")" = "$OWNER" ]; }
select_profile() {
    original "$TARGET" && return 0
    patched "$TARGET" && return 0
    candidate=$SCRIPT_DIR/../bin/notice-patch-v035
    if [ -x "$candidate" ] && [ -f "$TARGET" ] && [ ! -L "$TARGET" ] &&
       { "$candidate" original "$TARGET" || "$candidate" patched "$TARGET"; }; then
        TOOL=$candidate
        . "$SCRIPT_DIR/recipe-v035.sh"
        OWNER=gen5w.kr.notice:$NOTICE_RECIPE
    fi
    return 0
}
inspect() {
    # NEMESIS extracts files as 0644, regardless of ZIP executable attributes.
    for notice_helper in "$SCRIPT_DIR/../bin/notice-patch-v039" "$SCRIPT_DIR/../bin/notice-patch-v035"; do
        if [ -e "$notice_helper" ] || [ -L "$notice_helper" ]; then
            [ -f "$notice_helper" ] && [ ! -L "$notice_helper" ] && chmod 755 "$notice_helper" || return 1
        fi
    done
    [ -x "$TOOL" ] && [ -x "$NEM" ] || { log 'FAIL notice: helper or NEMESIS absent'; return 1; }
    select_profile || return 1
    for notice_path in "$SYS/etc/gen5w-kr-backup" "$DATA/nemesis/backup" "$STATE" "$MARK"; do
        [ ! -L "$notice_path" ] || return 1
    done
    NOTICE_OWNED=no
    if [ -e "$STATE" ]; then
        owned || { log 'FAIL notice: unknown recovery ownership'; return 1; }
        NOTICE_OWNED=yes
        if [ -e "$STATE/original" ] || [ -L "$STATE/original" ]; then
            original "$STATE/original" || { log 'FAIL notice: damaged recovery original'; return 1; }
        fi
    fi
    if [ -e "$MARK" ]; then
        [ -d "$MARK" ] && [ ! -L "$MARK/owner" ] &&
        [ "$(cat "$MARK/owner" 2>/dev/null)" = "$OWNER" ] && original "$MARK/original" || {
            log 'FAIL notice: unknown or damaged runtime backup'; return 1;
        }
    fi
    if original "$TARGET"; then NOTICE_STATE=stock
    elif patched "$TARGET"; then NOTICE_STATE=patched
    else
        log 'SKIP notice: unknown SystemUI ODEX hash'
        [ "$NOTICE_OWNED" = no ] && return 77
        return 1
    fi
    if [ "$NOTICE_STATE" = patched ]; then
        [ "$NOTICE_OWNED" = yes ] && original "$STATE/original" || {
            log 'FAIL notice: patched SystemUI ODEX lacks owned original'; return 1;
        }
    fi
    return 0
}
dependencies() {
    [ -f "$SYS/priv-app/SystemUI.apk" ] && [ ! -L "$SYS/priv-app/SystemUI.apk" ] &&
    "$TOOL" verify "$SYS/priv-app/SystemUI.apk" "$NOTICE_APK_SHA" && return 0
    log 'SKIP notice: unknown SystemUI APK dependency'
    [ "$NOTICE_OWNED" = no ] && return 77
    return 1
}
sys_ro() { "$NEM" remount ro >/dev/null 2>&1; }
stage_clear() {
    if [ -e "$TARGET.gen5w-kr-notice.tmp" ] || [ -L "$TARGET.gen5w-kr-notice.tmp" ]; then
        original "$TARGET.gen5w-kr-notice.tmp" || patched "$TARGET.gen5w-kr-notice.tmp" || return 1
        rm "$TARGET.gen5w-kr-notice.tmp" || return 1
    fi
}
restore_target() {
    original "$TARGET" && return 0
    patched "$TARGET" && original "$STATE/original" && stage_clear || return 1
    if cp -p "$STATE/original" "$TARGET.gen5w-kr-notice.tmp" &&
       original "$TARGET.gen5w-kr-notice.tmp" &&
       mv "$TARGET.gen5w-kr-notice.tmp" "$TARGET" && original "$TARGET"; then
        return 0
    fi
    [ -L "$TARGET.gen5w-kr-notice.tmp" ] || rm -f "$TARGET.gen5w-kr-notice.tmp"
    return 1
}
publish_backup() {
    local destination=$1 source=$2 pending=$1.pending entry
    if [ -e "$destination" ] || [ -L "$destination" ]; then
        [ -d "$destination" ] && [ ! -L "$destination" ] &&
        [ ! -L "$destination/owner" ] &&
        [ "$(cat "$destination/owner" 2>/dev/null)" = "$OWNER" ] &&
        original "$destination/original"
        return $?
    fi
    [ ! -L "$pending" ] || return 1
    mkdir -p "$pending" || return 1
    # Only our fixed staging names may survive an interrupted copy.
    for entry in "$pending"/* "$pending"/.[!.]* "$pending"/..?*; do
        [ -e "$entry" ] || [ -L "$entry" ] || continue
        case "$entry" in "$pending/owner"|"$pending/owner.tmp"|"$pending/original"|"$pending/original.tmp") ;;
            *) return 1;; esac
        [ -f "$entry" ] && [ ! -L "$entry" ] || return 1
    done
    if [ -f "$pending/owner" ]; then
        [ "$(cat "$pending/owner")" = "$OWNER" ] || return 1
    elif [ -e "$pending/original" ] || [ -e "$pending/original.tmp" ]; then return 1
    fi
    original "$source" || return 1
    chmod 700 "$pending" || return 1
    echo "$OWNER" > "$pending/owner.tmp" && chmod 600 "$pending/owner.tmp" &&
        mv "$pending/owner.tmp" "$pending/owner" || return 1
    cp -p "$source" "$pending/original.tmp" && original "$pending/original.tmp" &&
        mv "$pending/original.tmp" "$pending/original" || return 1
    sync
    mv "$pending" "$destination" || return 1
    sync
}
save_original() {
    if [ ! -e "$STATE" ]; then publish_backup "$STATE" "$TARGET" || return 1; fi
    owned && original "$STATE/original" || return 1
    publish_backup "$MARK" "$STATE/original"
}
cleanup_owned() {
    rm -f "$STATE/original" "$STATE/owner" "$STATE/replacement" || return 1
    rmdir "$STATE" || return 1
    if [ -d "$MARK" ]; then
        [ ! -L "$MARK/owner" ] && [ "$(cat "$MARK/owner" 2>/dev/null)" = "$OWNER" ] || return 1
        rm -f "$MARK/original" "$MARK/owner" || return 1
        rmdir "$MARK" || return 1
    fi
    rmdir "$SYS/etc/gen5w-kr-backup" 2>/dev/null || true
}
