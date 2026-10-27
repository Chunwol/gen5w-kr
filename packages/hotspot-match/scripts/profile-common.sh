# Owned, hash-verified services ODEX replacement. mksh + Android toolbox only.
# Each entry point sets SCRIPT_DIR explicitly, including bin/status.sh.
. "$SCRIPT_DIR/profile-recipe-v039.sh"
SYS=${PROFILE_TEST_SYS:-/system}
DATA=${PROFILE_TEST_DATA:-/data}
NEM=${PROFILE_TEST_NEM:-/system/xbin/nemesis}
TOOL=${PROFILE_TEST_TOOL:-$SCRIPT_DIR/../bin/hotspot-patch-v039}
TARGET=$SYS/framework/services.odex
STATE=$SYS/etc/gen5w-kr-backup/hotspot
MARK=$DATA/nemesis/backup/gen5w.kr.hotspot
OWNER=gen5w.kr.hotspot:$PROFILE_RECIPE
NOREBOOT=$DATA/nemesis/gen5wkr.noreboot

log() { echo "$1"; }
original() { [ -f "$1" ] && [ ! -L "$1" ] && "$TOOL" original "$1"; }
patched() { [ -f "$1" ] && [ ! -L "$1" ] && "$TOOL" patched "$1"; }
owned() { [ -f "$STATE/owner" ] && [ ! -L "$STATE/owner" ] && [ "$(cat "$STATE/owner")" = "$OWNER" ]; }
select_profile() {
    original "$TARGET" && return 0
    patched "$TARGET" && return 0
    candidate=$SCRIPT_DIR/../bin/hotspot-patch-v035
    if [ -x "$candidate" ] && [ -f "$TARGET" ] && [ ! -L "$TARGET" ] &&
       { "$candidate" original "$TARGET" || "$candidate" patched "$TARGET"; }; then
        TOOL=$candidate
        . "$SCRIPT_DIR/profile-recipe-v035.sh"
        OWNER=gen5w.kr.hotspot:$PROFILE_RECIPE
    fi
    return 0
}
inspect() {
    # NEMESIS extracts files as 0644, regardless of ZIP executable attributes.
    for hotspot_helper in "$SCRIPT_DIR/../bin/hotspot-patch-v039" "$SCRIPT_DIR/../bin/hotspot-patch-v035"; do
        if [ -e "$hotspot_helper" ] || [ -L "$hotspot_helper" ]; then
            [ -f "$hotspot_helper" ] && [ ! -L "$hotspot_helper" ] && chmod 755 "$hotspot_helper" || return 1
        fi
    done
    [ -x "$TOOL" ] && [ -x "$NEM" ] || { log 'FAIL hotspot: helper or NEMESIS absent'; return 1; }
    select_profile || return 1
    for hotspot_path in "$SYS/etc/gen5w-kr-backup" "$DATA/nemesis/backup" "$STATE" "$MARK"; do
        [ ! -L "$hotspot_path" ] || return 1
    done
    PROFILE_OWNED=no
    if [ -e "$STATE" ]; then
        owned || { log 'FAIL hotspot: unknown recovery ownership'; return 1; }
        PROFILE_OWNED=yes
        if [ -e "$STATE/original" ] || [ -L "$STATE/original" ]; then
            original "$STATE/original" || { log 'FAIL hotspot: damaged recovery original'; return 1; }
        fi
    fi
    if [ -e "$MARK" ]; then
        [ -d "$MARK" ] && [ ! -L "$MARK/owner" ] &&
        [ "$(cat "$MARK/owner" 2>/dev/null)" = "$OWNER" ] && original "$MARK/original" || {
            log 'FAIL hotspot: unknown or damaged runtime backup'; return 1;
        }
    fi
    if original "$TARGET"; then PROFILE_STATE=stock
    elif patched "$TARGET"; then PROFILE_STATE=patched
    else
        log 'SKIP hotspot: unknown services ODEX hash'
        [ "$PROFILE_OWNED" = no ] && return 77
        return 1
    fi
    if [ "$PROFILE_STATE" = patched ]; then
        [ "$PROFILE_OWNED" = yes ] && original "$STATE/original" || {
            log 'FAIL hotspot: patched services ODEX lacks owned original'; return 1;
        }
    fi
    return 0
}
dependencies() {
    [ -f "$SYS/framework/framework.odex" ] && [ ! -L "$SYS/framework/framework.odex" ] &&
    "$TOOL" verify "$SYS/framework/framework.odex" "$PROFILE_FRAMEWORK_SHA" && return 0
    log 'SKIP hotspot: unknown framework dependency'
    [ "$PROFILE_OWNED" = no ] && return 77
    return 1
}
sys_ro() { "$NEM" remount ro >/dev/null 2>&1; }
stage_clear() {
    if [ -e "$TARGET.gen5w-kr-hotspot.tmp" ] || [ -L "$TARGET.gen5w-kr-hotspot.tmp" ]; then
        original "$TARGET.gen5w-kr-hotspot.tmp" || patched "$TARGET.gen5w-kr-hotspot.tmp" || return 1
        rm "$TARGET.gen5w-kr-hotspot.tmp" || return 1
    fi
}
restore_target() {
    original "$TARGET" && return 0
    patched "$TARGET" && original "$STATE/original" && stage_clear || return 1
    if cp -p "$STATE/original" "$TARGET.gen5w-kr-hotspot.tmp" &&
       original "$TARGET.gen5w-kr-hotspot.tmp" &&
       mv "$TARGET.gen5w-kr-hotspot.tmp" "$TARGET" && original "$TARGET"; then
        return 0
    fi
    [ -L "$TARGET.gen5w-kr-hotspot.tmp" ] || rm -f "$TARGET.gen5w-kr-hotspot.tmp"
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
    rm -f "$STATE/original" "$STATE/owner" "$STATE/replacement" "$STATE/applied-boot" "$STATE/applied-boot.tmp" || return 1
    rmdir "$STATE" || return 1
    if [ -d "$MARK" ]; then
        [ ! -L "$MARK/owner" ] && [ "$(cat "$MARK/owner" 2>/dev/null)" = "$OWNER" ] || return 1
        rm -f "$MARK/original" "$MARK/owner" || return 1
        rmdir "$MARK" || return 1
    fi
    rmdir "$SYS/etc/gen5w-kr-backup" 2>/dev/null || true
}

READY=$DATA/nemesis/gen5wkr.ap-profile-ready
PROFILE_STOPPING=$DATA/nemesis/gen5wkr.ap-profile-stopping
stop_owner=gen5w.kr.hotspot:profile-transition
stop_guard() {
    [ ! -L "$DATA/nemesis" ] && [ ! -L "$PROFILE_STOPPING" ] && [ ! -L "$PROFILE_STOPPING.tmp" ] || return 1
    [ ! -e "$PROFILE_STOPPING.tmp" ] || [ -f "$PROFILE_STOPPING.tmp" ] || return 1
    if [ -e "$PROFILE_STOPPING" ]; then
        [ -f "$PROFILE_STOPPING" ] && [ "$(cat "$PROFILE_STOPPING")" = "$stop_owner" ] || return 1
    fi
}
begin_stop() {
    stop_guard && mkdir -p "$DATA/nemesis" || return 1
    echo "$stop_owner" > "$PROFILE_STOPPING.tmp" && chmod 600 "$PROFILE_STOPPING.tmp" &&
        mv "$PROFILE_STOPPING.tmp" "$PROFILE_STOPPING" || return 1
    clear_ready || return 1
    if [ -z "$PROFILE_TEST_SYS" ]; then
        /system/bin/am broadcast -a kr.gen5w.wireless.STOP_BRIDGE >/dev/null 2>&1 || return 1
        sleep 2
    fi
}
clear_stop() { stop_guard && rm -f "$PROFILE_STOPPING" "$PROFILE_STOPPING.tmp"; }
read_boot() {
    PROFILE_BOOT=${PROFILE_TEST_BOOT:-$(cat /proc/sys/kernel/random/boot_id 2>/dev/null)}
    case "$PROFILE_BOOT" in *[!a-fA-F0-9-]*|'') return 1;; esac
    [ ${#PROFILE_BOOT} = 36 ] || return 1
    case "$PROFILE_BOOT" in ????????-????-????-????-????????????) ;; *) return 1;; esac
}
clear_ready() {
    [ ! -L "$DATA/nemesis" ] && [ ! -L "$READY" ] && [ ! -L "$READY.tmp" ] || return 1
    [ ! -e "$READY" ] || [ -f "$READY" ] || return 1
    [ ! -e "$READY.tmp" ] || [ -f "$READY.tmp" ] || return 1
    rm -f "$READY" "$READY.tmp"
}
record_boot() {
    read_boot || return 1
    [ ! -L "$STATE/applied-boot" ] && [ ! -L "$STATE/applied-boot.tmp" ] || return 1
    echo "$PROFILE_BOOT" > "$STATE/applied-boot.tmp" && chmod 600 "$STATE/applied-boot.tmp" &&
        mv "$STATE/applied-boot.tmp" "$STATE/applied-boot" && sync
}
