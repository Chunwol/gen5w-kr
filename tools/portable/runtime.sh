#!/system/bin/sh
# Explicit per-boot property transaction. No app stop/restart or boot service.
umask 077
BASE=${0%/*}; [ "$BASE" != "$0" ] || BASE=.
BASE=$(CDPATH= cd -- "$BASE" && pwd) || exit 1
ROOT=${PORTABLE_TEST_ROOT:-}
ADAPTER=${PORTABLE_TEST_RUNTIME_ADAPTER:-}
STATE=${PORTABLE_RUNTIME_STATE:-/data/local/gen5w-portable/runtime}
HELPER=${PORTABLE_HELPER:-$BASE/bin/dex-patch}
unsupported() { echo "runtime: optional capability unavailable: $*" >&2; exit 77; }
fail() { echo "runtime: $*" >&2; exit 1; }
safe() { case "$1" in ''|*[!a-zA-Z0-9_./-]*|*/../*|*/./*|*/..|*/.|*//*) return 1;; esac; }
plain() {
    safe "$1" || return 1
    case "$1" in /*) :;; *) return 1;; esac
    local p=$1
    while [ "$p" != / ] && [ -n "$p" ]; do [ ! -L "$p" ] || return 1; p=${p%/*}; [ -n "$p" ] || p=/; done
}
if [ -n "$ROOT" ]; then
    plain "$ROOT" && [ "$ROOT" != / ] && [ -d "$ROOT" ] && [ -x "$ADAPTER" ] || fail 'invalid fixture'
    case "$BASE" in "$ROOT"/data/*) BUNDLE=${BASE#"$ROOT"};; *) fail 'fixture bundle is not in data';; esac
else
    [ -z "$ADAPTER" ] || fail 'test adapter outside fixture'
    BUNDLE=$BASE
fi
case "$BUNDLE" in /data/*) :;; *) fail 'bundle must be in /data';; esac
case "$STATE" in /data/*) :;; *) fail 'state must be in /data';; esac
plain "$BASE" && plain "$ROOT$STATE" || fail 'unsafe path'
STATE=$ROOT$STATE
op() {
    if [ -n "$ROOT" ]; then "$ADAPTER" "$@"; return $?; fi
    case "$1" in
    get) getprop "$2";;
    healthy) /system/bin/sh "$BASE/framework.sh" ready;;
    set) setprop "$2" "$3";;
    feature)
        if [ "${feature_snapshot:-0}" != 1 ]; then
            PORTABLE_HELPER=$HELPER /system/bin/sh "$BASE/overlay.sh" status > "$STATE/overlay.status.tmp" || return 1
            feature_snapshot=1
        fi
        while IFS='|' read -r feature flag; do
            [ "$feature" != "$2" ] || { [ "$flag" = active ] && return 0; }
        done < "$STATE/overlay.status.tmp"
        return 1;;
    probe)
        # Test authored dispatch against this VM before touching application state.
        "$HELPER" supervise 20 /system/bin/true /system/bin/dalvikvm -Xint -cp "$BASE/dalvik/hook-vm-test.jar" HookVmTest "$BASE/dalvik/libgen5whook.so" > "$STATE/abi-probe.log" 2>&1;;
    boot) cat /proc/sys/kernel/random/boot_id;;
    *) return 1;;
    esac
}
phase() { if [ -f "$STATE/phase" ]; then cat "$STATE/phase"; else echo disabled; fi; }
write_phase() { print -r -- "$1" > "$STATE/phase.new" && mv "$STATE/phase.new" "$STATE/phase" && sync; }
mkdir -p "$STATE" && chmod 700 "$STATE" || fail 'state creation failed'
for name in phase phase.new journal journal.new boot overlay.status.tmp abi-probe.log preflight preflight.new preflight.check; do
    [ ! -L "$STATE/$name" ] || fail 'symlink state'
    if [ -e "$STATE/$name" ] && [ ! -f "$STATE/$name" ]; then fail 'nonregular state'; fi
done
runtime_files() {
    echo bin/dex-patch
    echo dalvik/engine.jar
    echo dalvik/adapter.jar
    echo dalvik/libgen5whook.so
    echo dalvik/hook-vm-test.jar
    echo wrap-common.sh
    echo wrap-dipo.sh
    echo wrap-gpm.sh
    echo wrap-navi.sh
}
preflight_record() {
    op boot || return 1
    local name digest
    for name in $(runtime_files); do
        plain "$BASE/$name" && [ -f "$BASE/$name" ] || return 1
        digest=$("$HELPER" sha256 "$BASE/$name") || return 1
        print -r -- "$digest|$name"
    done
}
preflight_ok() {
    [ -s "$STATE/preflight" ] || return 1
    preflight_record > "$STATE/preflight.check" || return 1
    [ "$("$HELPER" sha256 "$STATE/preflight.check")" = "$("$HELPER" sha256 "$STATE/preflight")" ]
}
# Publish complete owner records atomically; reclaimers remain anchored to
# the stale directory so they can never delete a newly published owner.
process_key() {
    local pid=$1 line rest count=0
    case "$pid" in ''|*[!0-9]*) return 1;; esac
    IFS= read -r line < "/proc/$pid/stat" || return 1
    rest=${line##*) }; [ "$rest" != "$line" ] || return 1
    set -- $rest; [ "$#" -ge 20 ] || return 1
    case "$1" in Z|X|x) return 1;; esac
    while [ "$count" -lt 19 ]; do shift; count=$((count+1)); done
    echo "$pid:$1"
}
lock_boot=$(op boot) || exit 1
case "$lock_boot" in ''|*[!a-zA-Z0-9_-]*) exit 1;; esac
lock_process=$(process_key $$) || exit 1
lock_owner="$lock_boot|$lock_process"
lock_claim="$STATE/lock.claim.${lock_process%:*}.${lock_process#*:}"
lock_release() {
    [ "${lock_held:-0}" = 1 ] || return 0
    ( cd "$STATE/lock" && [ ! -L owner ] && [ "$(cat owner 2>/dev/null)" = "$lock_owner" ] &&
      rm owner && rmdir "$STATE/lock" ) 2>/dev/null
    lock_held=0
}
lock_stale_record() {
    [ ! -L owner ] || return 1
    [ -e owner ] || return 0
    [ -f owner ] || return 1
    [ -s owner ] || return 0
    local oldboot oldkey extra
    IFS='|' read -r oldboot oldkey extra < owner
    [ -z "$extra" ] || return 1
    if [ -z "$oldkey" ]; then
        case "$oldboot" in ''|*[!0-9]*) return 1;; esac
        process_key "$oldboot" >/dev/null 2>&1 && return 1
    else
        case "$oldboot" in ''|*[!a-zA-Z0-9_-]*) return 1;; esac
        case "$oldkey" in *[!0-9:]*|:*|*:|*:*:*) return 1;; esac
        case "$oldkey" in *:*) :;; *) return 1;; esac
        if [ "$oldboot" = "$lock_boot" ] &&
           [ "$(process_key "${oldkey%%:*}" 2>/dev/null)" = "$oldkey" ]; then return 1; fi
    fi
    return 0
}
lock_reclaim() (
    [ -d "$STATE/lock" ] && [ ! -L "$STATE/lock" ] || exit 1
    cd "$STATE/lock" || exit 1
    lock_stale_record && [ ! -L recover ] || exit 1
    # A contender killed after mv nested its staged claim must not wedge recovery.
    set +f
    for claim in lock.claim.*; do
        [ -e "$claim" ] || { [ ! -L "$claim" ] || exit 1; continue; }
        [ -d "$claim" ] && [ ! -L "$claim" ] || exit 1
        ( cd "$claim" && lock_stale_record && { [ ! -e owner ] || rm owner; } ) || exit 1
        rmdir "$claim" || exit 1
    done
    [ ! -e owner ] || rm owner || exit 1
    if [ -e recover ]; then [ -d recover ] && rmdir recover || exit 1; fi
    # A newly published lock is nonempty; an anchored old reclaimer cannot remove it.
    rmdir "$STATE/lock"
)
lock_acquire() {
    local count=0 nested=${lock_claim##*/}
    while [ "$count" -lt 4 ]; do
        count=$((count+1))
        [ ! -L "$STATE/lock" ] && { [ ! -e "$STATE/lock" ] || [ -d "$STATE/lock" ]; } || return 1
        mkdir "$lock_claim" || return 1
        echo "$lock_owner" > "$lock_claim/owner" || return 1
        # mv nests the staged directory if lock already exists; that claim
        # withdraws. An absent-destination rename alone publishes ownership.
        if ! mv "$lock_claim" "$STATE/lock" 2>/dev/null; then
            rm -f "$lock_claim/owner"; rmdir "$lock_claim" 2>/dev/null
            return 1
        fi
        if [ -d "$STATE/lock/$nested" ] && [ ! -L "$STATE/lock/$nested" ]; then
            rm "$STATE/lock/$nested/owner" && rmdir "$STATE/lock/$nested" || return 1
            lock_reclaim 2>/dev/null || return 1
        elif [ ! -L "$STATE/lock/owner" ] && [ "$(cat "$STATE/lock/owner" 2>/dev/null)" = "$lock_owner" ]; then
            lock_held=1
            return 0
        else return 1; fi
    done
    return 1
}
lock_acquire_bounded() {
    local up rest until
    IFS=' ' read -r up rest < /proc/uptime || return 1
    until=$((${up%%.*}+10))
    while ! lock_acquire; do
        IFS=' ' read -r up rest < /proc/uptime || return 1
        [ "${up%%.*}" -lt "$until" ] || return 1
        sleep 1
    done
}
lock_acquire_bounded || { echo 'portable: locked or unsafe lock' >&2; exit 1; }
trap lock_release EXIT
trap 'exit 1' HUP INT TERM
stopped() { [ "$(op get init.svc.zygote)" = stopped ]; }
same_boot() { [ -s "$STATE/boot" ] && [ "$(cat "$STATE/boot")" = "$(op boot)" ]; }
key_ok() { case "$1" in wrap.com.daudio.app.dipo|wrap.com.google.android.project|wrap.com.mnsoft.navi) return 0;; *) return 1;; esac; }
restore() {
    local key wanted before current extra rc=0
    [ -f "$STATE/journal" ] || return 0
    while IFS='|' read -r key wanted before extra; do
        key_ok "$key" && [ -z "$extra" ] || { rc=1; continue; }
        # Wrapper properties expire at reboot. No persistent property is written.
        if ! same_boot; then continue; fi
        current=$(op get "$key") || { rc=1; continue; }
        if [ "$current" = "$wanted" ]; then
            op set "$key" "$before" && [ "$(op get "$key")" = "$before" ] || rc=1
        elif [ "$current" != "$before" ]; then rc=1; fi
    done < "$STATE/journal"
    return "$rc"
}
active() {
    local key wanted before extra
    same_boot && [ -s "$STATE/journal" ] || return 1
    while IFS='|' read -r key wanted before extra; do
        key_ok "$key" && [ -z "$extra" ] && [ "$(op get "$key")" = "$wanted" ] || return 1
    done < "$STATE/journal"
}
command=${1:-}; [ $# -eq 0 ] || shift
case "$command" in
preflight)
    [ "$#" = 0 ] || fail 'unexpected preflight arguments'
    # A new observation invalidates the previous proof, including same-boot
    # proofs. A busy Android query is retryable before any wrapper is changed.
    rm -f "$STATE/preflight" || fail 'cannot retire previous preflight proof'
    if ! op healthy; then
        echo 'runtime: Android readiness temporarily unavailable for preflight' >&2
        exit 75
    fi
    # The expensive Dalvik dispatch/GC/monitor proof runs while stock Android
    # remains available. The stopped-framework transaction later accepts only
    # this same-boot, exact-artifact seal.
    op probe || { rm -f "$STATE/preflight.new"; unsupported 'live Dalvik ABI/dispatch probe failed'; }
    preflight_record > "$STATE/preflight.new" && mv "$STATE/preflight.new" "$STATE/preflight" || fail 'runtime preflight seal failed'
    echo 'runtime: live Dalvik preflight passed for this boot and exact bundle'
    ;;
enable)
    stopped || fail 'Android must be stopped before enabling wrappers'
    [ "$#" = 1 ] || fail 'select dipo, gpm, or both'
    probe_only=0
    case "$1" in probe) apps=dipo; probe_only=1;; dipo) apps=dipo;; gpm) apps=gpm;; navi) apps=navi;; both) apps='dipo gpm navi';; *) fail 'unknown app';; esac
    # Cold boot clears wrap properties; only the expired journal is retired.
    # Existing properties are still checked below and never overwritten.
    if [ "$(phase)" != disabled ] && ! same_boot; then
        restore && write_phase disabled || fail 'expired transaction retirement failed'
    fi
    if [ "$1" = both ] && ! op feature gpm; then
        apps=dipo
        echo 'runtime: gpm skipped: static prerequisite unavailable' >&2
    elif [ "$1" = gpm ]; then
        op feature gpm || unsupported 'gpm prerequisite unavailable'
    fi
    case "$probe_only:$apps" in 0:dipo|0:'dipo gpm'|0:'dipo gpm navi') op feature bt && op feature projection || unsupported 'dipo requires active bt and projection overlays';; esac
    case "$(phase)" in disabled) :;; *) fail 'disable the previous runtime transaction first';; esac
    for file in "$HELPER" "$BASE/dalvik/engine.jar" "$BASE/dalvik/adapter.jar" "$BASE/dalvik/libgen5whook.so" "$BASE/dalvik/hook-vm-test.jar" "$BASE/wrap-common.sh"; do
        plain "$file" && [ -f "$file" ] || fail 'missing runtime artifact'
    done
    [ "$probe_only" = 1 ] || preflight_ok || unsupported "same-boot Dalvik preflight unavailable or bundle changed; no wrapper changed"
    : > "$STATE/journal.new"
    for app in $apps; do
        wrapper=$app; [ "$probe_only" = 0 ] || wrapper=probe
        plain "$BASE/wrap-$wrapper.sh" && [ -f "$BASE/wrap-$wrapper.sh" ] || fail 'wrapper missing'
        case "$app" in dipo) key=wrap.com.daudio.app.dipo;; gpm) key=wrap.com.google.android.project;; navi) key=wrap.com.mnsoft.navi;; esac
        wanted="/system/bin/sh $BUNDLE/wrap-$wrapper.sh"
        [ ${#wanted} -le 91 ] || fail 'wrapper property exceeds KitKat value limit'
        [ ${#key} -le 31 ] || fail 'wrapper key exceeds KitKat key limit'
        before=$(op get "$key") || fail 'wrapper property read failed'
        if [ -n "$before" ]; then
            if [ "$app" = gpm ] && [ "$apps" != gpm ]; then
                echo 'runtime: gpm skipped: foreign wrapper retained' >&2
                continue
            fi
            unsupported 'existing foreign wrapper retained; no owned wrapper changed'
        fi
        print -r -- "$key|$wanted|" >> "$STATE/journal.new" || fail 'journal failed'
    done
    op boot > "$STATE/boot" && [ -s "$STATE/boot" ] && mv "$STATE/journal.new" "$STATE/journal" && write_phase enabling || fail 'journal seal failed'
    while IFS='|' read -r key wanted before; do
        if ! op set "$key" "$wanted" || [ "$(op get "$key")" != "$wanted" ]; then
            restore && write_phase disabled || write_phase failed
            fail 'property transaction failed; inspect status'
        fi
    done < "$STATE/journal"
    write_phase pending || fail 'cannot record pending runtime'
    echo 'runtime: pending; wrappers configured for this boot, application operation unverified'
    ;;
commit)
    [ "$#" = 0 ] && [ "$(phase)" = pending ] && active && op healthy || fail 'healthy active runtime required'
    write_phase committed || fail 'commit failed'
    ;;
disable)
    [ "$#" = 0 ] && stopped || fail 'stop Android before removing wrappers'
    restore || { write_phase failed; fail 'foreign property or restore failure retained'; }
    write_phase disabled || fail 'disable failed'
    ;;
update-disable)
    [ "$#" = 0 ] || fail 'unexpected update-disable arguments'
    # The updater has already stopped authored workers. Restore only this
    # transaction's exact current-boot properties; never stop/restart Android.
    if [ "$(phase)" = disabled ] || [ "$(phase)" = expired ]; then exit 0; fi
    active || fail 'owned current-boot wrapper transaction is not provable'
    while IFS='|' read -r key wanted before extra; do
        key_ok "$key" && [ -z "$extra" ] || fail 'malformed update wrapper journal'
        current=$(op get "$key") || fail 'update wrapper property read failed'
        [ "$current" = "$wanted" ] || { write_phase failed; fail 'owned wrapper changed during update retirement'; }
    done < "$STATE/journal"
    while IFS='|' read -r key wanted before extra; do
        current=$(op get "$key") || current=__unreadable__
        [ "$current" = "$before" ] && continue
        if [ "$current" != "$wanted" ] || ! op set "$key" "$before" || [ "$(op get "$key")" != "$before" ]; then
            rollback_failed=0
            while IFS='|' read -r rollback_key rollback_wanted rollback_before; do
                rollback_current=$(op get "$rollback_key") || { rollback_failed=1; continue; }
                if [ "$rollback_current" = "$rollback_before" ]; then op set "$rollback_key" "$rollback_wanted" && [ "$(op get "$rollback_key")" = "$rollback_wanted" ] || rollback_failed=1
                elif [ "$rollback_current" != "$rollback_wanted" ]; then rollback_failed=1; fi
            done < "$STATE/journal"
            [ "$rollback_failed" = 0 ] || write_phase failed
            fail 'update wrapper restore failed; owned values were rolled back when provable'
        fi
    done < "$STATE/journal"
    write_phase disabled || fail 'update wrapper retirement failed'
    echo 'runtime: current-boot wrappers retired for update without restarting Android'
    ;;
update-restore)
    [ "$#" = 0 ] && [ "$(phase)" = disabled ] && same_boot || fail 'no same-boot update wrapper transaction to restore'
    [ -s "$STATE/journal" ] || exit 0
    # Re-enable only the exact owned property values retired for this update.
    # Never overwrite a value changed by another component while installation
    # was in progress; roll back only properties this command itself changed.
    while IFS='|' read -r key wanted before extra; do
        key_ok "$key" && [ -z "$extra" ] || fail 'malformed update wrapper journal'
        current=$(op get "$key") || fail 'update wrapper property read failed'
        [ "$current" = "$wanted" ] && continue
        [ "$current" = "$before" ] || fail 'foreign wrapper value retained during update'
        if ! op set "$key" "$wanted" || [ "$(op get "$key")" != "$wanted" ]; then
            rollback_failed=0
            while IFS='|' read -r rollback_key rollback_wanted rollback_before; do
                rollback_current=$(op get "$rollback_key") || { rollback_failed=1; continue; }
                if [ "$rollback_current" = "$rollback_wanted" ]; then op set "$rollback_key" "$rollback_before" && [ "$(op get "$rollback_key")" = "$rollback_before" ] || rollback_failed=1
                elif [ "$rollback_current" != "$rollback_before" ]; then rollback_failed=1; fi
            done < "$STATE/journal"
            [ "$rollback_failed" = 0 ] || write_phase failed
            fail 'update wrapper re-enable failed; changed values were rolled back when provable'
        fi
    done < "$STATE/journal"
    write_phase committed || fail 'update wrapper state commit failed'
    echo 'runtime: prior owned wrappers restored without restarting Android'
    ;;
status)
    [ "$#" = 0 ] || fail 'unexpected arguments'
    current=$(phase)
    case "$current" in pending|committed|enabling)
        if ! same_boot; then current=expired
        elif ! active; then current=failed; fi;;
    esac
    echo "runtime|$current"
    ;;
*) fail 'usage: runtime.sh preflight | enable probe|dipo|gpm|both | status | commit | disable | update-disable | update-restore';;
esac
