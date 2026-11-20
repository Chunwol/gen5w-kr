#!/system/bin/sh
# Pre-zygote boot guard. The persistent install inserts one background line
# into /system/etc/qb_runtime.sh (init service qb_uid_check, post-fs-data,
# root, oneshot). Init does not wait for it, so this never delays zygote.
#
# Every boot increments a counter. A boot that keeps sys.boot_completed for
# STABLE seconds clears it. After LIMIT consecutive boots without a stable
# Android, the stock /system files are restored from the immutable recovery
# manifest (same fixed-function restore.sh as the recovery USB), automatic
# startup is disabled, and the unit reboots once into stock.
umask 077
# qb_uid_check is a console service: its shell's exit sends SIGHUP to this background job.
trap '' HUP
PATH=/system/bin:/system/xbin:/sbin:/bin; export PATH
ROOT=${PORTABLE_TEST_ROOT:-}
GUARD=$ROOT/data/local/gen5w-portable/persistent/bootguard
STATE=$ROOT/data/local/gen5w-portable/boot
LIMIT=${GEN5W_BOOTGUARD_LIMIT:-4}
STABLE=${GEN5W_BOOTGUARD_STABLE:-30}
WAIT=${GEN5W_BOOTGUARD_WAIT:-900}
LOG=$GUARD/guard.log
SH=${PORTABLE_TEST_SH:-/system/bin/sh}
getprop_() { if [ -n "$ROOT" ]; then "$PORTABLE_TEST_GETPROP" "$1"; else getprop "$1"; fi; }
nap() { if [ -n "$ROOT" ]; then :; else sleep "$1"; fi; }
log() {
    if [ -f "$LOG" ] && [ ! -L "$LOG" ]; then
        size=$("$GUARD/bin/dex-patch" size "$LOG" 2>/dev/null) || size=0
        [ "${size:-0}" -lt 65536 ] || mv "$LOG" "$LOG.1"
    fi
    [ ! -L "$LOG" ] && print -r -- "$(date +%Y%m%d-%H%M%S 2>/dev/null) $*" >> "$LOG"
}
put() { print -r -- "$2" > "$1.new" && mv "$1.new" "$1"; }
safe_dir() { [ -d "$1" ] && [ ! -L "$1" ]; }

safe_dir "$GUARD" || exit 0
RESULT=$GUARD/GEN5W-RECOVERY-RESULT.txt
for f in count count.new count.svc tripped tripped.new guard.log restore.sh bin bin/dex-patch GEN5W-RECOVERY-RESULT.txt; do [ ! -L "$GUARD/$f" ] || exit 0; done
case "$LIMIT$STABLE$WAIT" in *[!0-9]*) exit 0;; esac
# restore.sh writes result=restored before it reboots (result=success when it
# finds the restore already complete). Anything else means it never finished.
restored() {
    [ -f "$RESULT" ] || return 1
    while IFS= read -r line; do
        case "$line" in result=restored|result=success) return 0;; esac
    done < "$RESULT"
    return 1
}

attempt=0
if [ -e "$GUARD/tripped" ]; then
    if restored; then log 'latched: stock was already restored by the guard'; exit 0; fi
    # A restore cut off by power loss or a failed restore: retry on every boot.
    attempt=$(cat "$GUARD/tripped" 2>/dev/null)
    case "$attempt" in ''|*[!0-9]*) attempt=1;; esac
    log "previous restore did not complete (attempt $attempt); retrying"
    n=$((LIMIT+1))
else
    n=$(cat "$GUARD/count" 2>/dev/null)
    case "$n" in ''|*[!0-9]*) n=0;; esac
    n=$((n+1))
    put "$GUARD/count" "$n" || exit 0
    sync
    log "boot $n/$LIMIT"
fi

if [ "$n" -gt "$LIMIT" ]; then
    [ "$attempt" != 0 ] || log "no stable Android for $LIMIT boots; restoring stock /system files"
    if safe_dir "$STATE"; then
        [ -L "$STATE/enabled" ] || put "$STATE/enabled" 0
        [ -L "$ROOT/data/nemesis/gen5w-hooks-off" ] || ( : > "$ROOT/data/nemesis/gen5w-hooks-off" ) 2>/dev/null
        [ -L "$STATE/reason" ] || put "$STATE/reason" bootguard-restored
        sync
    fi
    [ -f "$GUARD/restore.sh" ] && [ -x "$GUARD/bin/dex-patch" ] || { log 'restore tools missing'; exit 1; }
    # restore.sh uses $GUARD/bin/dex-patch, writes its result next to the guard and requests the reboot
    # itself only after every target is restored and verified.
    # tripped records the attempt; only a restored result report latches it.
    [ "$attempt" != 0 ] || rm -f "$RESULT"
    attempt=$((attempt+1))
    put "$GUARD/tripped" "$attempt" || exit 1
    sync
    GEN5W_RECOVERY_USB_ROOT=$GUARD "$SH" "$GUARD/restore.sh" >> "$LOG" 2>&1
    rc=$?
    # restore.sh re-validates everything on the next attempt.
    [ "$rc" = 0 ] || log "restore failed rc=$rc (attempt $attempt); retrying on the next boot"
    exit "$rc"
fi

# Wait for this boot to become stable, then clear the counter.
i=0
while [ "$(getprop_ sys.boot_completed)" != 1 ]; do
    i=$((i+1)); [ "$i" -lt "$WAIT" ] || { log 'boot_completed not reached'; exit 0; }
    nap 1
done
nap "$STABLE"
[ "$(getprop_ sys.boot_completed)" = 1 ] && [ "$(getprop_ init.svc.zygote)" = running ] || { log 'Android not stable'; exit 0; }
put "$GUARD/count" 0 && sync
log 'stable; counter cleared'
exit 0
