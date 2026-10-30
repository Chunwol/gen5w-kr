#!/system/bin/sh
# Boot-loop recovery. The integrated installer armed a boot guard before
# rebooting into patched /system; the runtime service invokes this only after the
# unit has failed to reach sys.boot_completed more than the armed number of times.
# It restores the stock boot-critical ODEX from the backups the installer kept on
# the unit, drops the stale dalvik-cache, and forces a clean cold boot. It touches
# only files already on the unit, so no USB bundle is needed to self-heal.
#
# VEHICLE-UNVERIFIED: never run on a car until it passes the mock harness and one
# supervised real-unit fault-injection test. A wrong restore can deepen a brick.
SCRIPT_DIR=${0%/*}
[ "$SCRIPT_DIR" != "$0" ] || SCRIPT_DIR=.
SYS=${BG_TEST_SYS:-/system}
DATA=${BG_TEST_DATA:-/data}
NEM=${BG_TEST_NEM:-/system/xbin/nemesis}
BG=$DATA/nemesis/gen5wkr.bootguard
DALVIK_ROOTS=${BG_TEST_DALVIK:-"/data/dalvik-cache /data/dalvik-cache/arm /cache/dalvik-cache"}

log() { echo "$1"; [ -d "$BG" ] && echo "$1" >> "$BG/recover.log" 2>/dev/null; }

# Restore one stock original over its target, via a staged temp so a crash mid-copy
# never leaves a half-written boot-critical file in place. Absent backup = the part
# was not installed; its target is already stock, so skip without failing.
restore_one() {
    local src=$1 dst=$2 tmp=$2.gen5wkr-bg.tmp
    [ -e "$src" ] || return 0
    [ -f "$src" ] && [ ! -L "$src" ] && [ ! -L "$dst" ] || { log "FAIL bootguard: bad restore path $dst"; return 1; }
    [ ! -L "$tmp" ] || rm -f "$tmp" || return 1
    if cp "$src" "$tmp" && chmod 644 "$tmp" && { [ -n "$BG_TEST_SYS" ] || chown 0:0 "$tmp"; } && mv "$tmp" "$dst" && cmp -s "$src" "$dst"; then
        log "RESTORED stock: $dst"
        return 0
    fi
    [ -L "$tmp" ] || rm -f "$tmp" 2>/dev/null
    log "FAIL bootguard: restore $dst"
    return 1
}

wipe_dalvik() {
    local d f
    for d in $DALVIK_ROOTS; do
        [ -d "$d" ] || continue
        for f in "$d"/*services* "$d"/*SystemUI* "$d"/*Iap2ServerApp* "$d"/*HKMC_DiPO* "$d"/*HKMC_GPM*; do
            [ -e "$f" ] || continue
            rm -f "$f" || return 1
            [ ! -e "$f" ] || return 1
        done
    done
    return 0
}

[ -f "$BG/armed" ] || { log 'REFUSED bootguard: guard is not armed'; exit 1; }
if [ -z "$BG_TEST_SYS" ]; then
    "$NEM" remount rw >/dev/null 2>&1 || { log 'FAIL bootguard: cannot remount system read-write'; exit 1; }
fi
rc=0
restore_one "$SYS/etc/gen5w-kr-backup/hotspot/original" "$SYS/framework/services.odex" || rc=1
restore_one "$SYS/etc/gen5w-kr-backup/notice/original"  "$SYS/priv-app/SystemUI.odex"  || rc=1
restore_one "$SYS/etc/gen5w-kr-backup/bridge/original" "$SYS/app/Iap2ServerApp.odex" || rc=1
restore_one "$SYS/etc/gen5w-kr-backup/bridge/dipooriginal" "$SYS/app/HKMC_DiPO.odex" || rc=1
restore_one "$SYS/etc/gen5w-kr-backup/bridge/gpmoriginal" "$SYS/app/HKMC_GPM.odex" || rc=1
restore_one "$SYS/etc/gen5w-kr-backup/audio/original" "$SYS/lib/libCarPlayAudio.so" || rc=1
[ "$rc" = 0 ] && wipe_dalvik || rc=1
sync
if [ -z "$BG_TEST_SYS" ]; then
    "$NEM" remount ro >/dev/null 2>&1 || rc=1
fi

# Mark recovery as done so the next boot does not recover again in a loop, and
# clear the attempt counter. The breadcrumb lets the Manager report what happened.
if [ -d "$BG" ]; then
    if [ "$rc" = 0 ]; then
        echo "recovered rc=0" > "$BG/recovered.tmp" && mv "$BG/recovered.tmp" "$BG/recovered" || rc=1
        [ "$rc" = 0 ] && rm -f "$BG/count" 2>/dev/null
    else
        echo 'recovery-required' > "$BG/recovery-required.tmp" && mv "$BG/recovery-required.tmp" "$BG/recovery-required" || true
    fi
    sync
fi
log "bootguard recovery complete rc=$rc"

# Tests stop here; a real unit cold-boots into the restored stock system.
[ -n "$BG_TEST_SYS" ] && exit "$rc"
[ "$rc" = 0 ] || exit 1
sync
[ -x /system/bin/d_audio ] && /system/bin/d_audio -c reboot force_normal 2>/dev/null
/system/bin/reboot force_normal 2>/dev/null
/system/bin/reboot
exit "$rc"
