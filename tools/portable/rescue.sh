#!/system/bin/sh
# Kept outside the NEMESIS package so uninstall cannot remove an armed rescue.
umask 077
BASE=${0%/*}
ROOT=${PORTABLE_TEST_ROOT:-}
STATE=$ROOT/data/local/gen5w-portable/boot
safe() {
    case "$1" in /*) :;; *) return 1;; esac
    case "$1" in *[!a-zA-Z0-9_./-]*|*/../*|*/./*|*/..|*/.|*//*) return 1;; esac
    local part=$1
    while [ "$part" != / ]; do [ ! -L "$part" ] || return 1; part=${part%/*}; [ -n "$part" ] || part=/; done
}
safe "$BASE" && safe "$STATE" && [ -d "$STATE" ] || exit 1
for file in enabled enabled.new maintenance reason reason.new; do
    [ ! -L "$STATE/$file" ] && { [ ! -e "$STATE/$file" ] || [ -f "$STATE/$file" ]; } || exit 1
done
op() {
    if [ -n "$ROOT" ]; then "$PORTABLE_TEST_BOOT_ADAPTER" "$@"; return $?; fi
    case "$1" in
    boot) cat /proc/sys/kernel/random/boot_id;;
    get) getprop "$2";;
    stop-android) setprop ctl.stop zygote;;
    start-android)
        local dependency result=0
        if safe "$STATE/dependencies" && [ -f "$STATE/dependencies" ]; then
            while read -r dependency; do
                case "$dependency" in ''|*[!a-zA-Z0-9_.-]*) result=1; continue;; esac
                setprop ctl.restart "$dependency" || result=1
            done < "$STATE/dependencies"
        else result=1; fi
        setprop ctl.start zygote || return 1
        return "$result";;
    runtime-disable) /system/bin/sh "$BASE/runtime.sh" disable;;
    overlay-disable) PORTABLE_HELPER=$BASE/bin/dex-patch /system/bin/sh "$BASE/overlay.sh" disable;;
    pause) sleep 1;;
    *) return 1;;
    esac
}
print -r -- 0 > "$STATE/enabled.new" && mv "$STATE/enabled.new" "$STATE/enabled" || exit 1
print -r -- maintenance-recovery > "$STATE/reason.new" && mv "$STATE/reason.new" "$STATE/reason" || exit 1
[ -f "$STATE/maintenance" ] && [ "$(cat "$STATE/maintenance")" = "$(op boot)" ] || exit 0
# Stop any partially restarted framework before changing its active view.
if [ "$(op get init.svc.zygote)" != stopped ]; then op stop-android; fi
count=0
while [ "$(op get init.svc.zygote)" != stopped ]; do
    count=$((count+1)); [ "$count" -lt 10 ] || { op start-android; exit 1; }; op pause
done
restore_step() {
    local count=0
    while ! op "$1"; do
        count=$((count+1)); [ "$count" -lt 3 ] || return 1; op pause
    done
}
result=0
restore_step runtime-disable || result=1
restore_step overlay-disable || result=1
# Starting stock Android takes priority over flushing diagnostics.
op start-android || result=1
[ "$result" = 0 ] && rm -f "$STATE/maintenance"
exit "$result"
