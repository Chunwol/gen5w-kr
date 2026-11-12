#!/system/bin/sh
# One startup attempt, immutable origins, bounded maintenance, explicit disable.
umask 077
LC_ALL=C; export LC_ALL
BASE=${0%/*}; [ "$BASE" != "$0" ] || BASE=.
BASE=$(CDPATH= cd -- "$BASE" && pwd) || exit 1
ROOT=${PORTABLE_TEST_ROOT:-}
STATE=$ROOT/data/local/gen5w-portable/boot
HELPER=$BASE/bin/dex-patch
SUPERVISOR=$HELPER
PAYLOAD=$ROOT/data/local/gen5w-portable/runtime-payload
ADAPTER=${PORTABLE_TEST_BOOT_ADAPTER:-}
fail() { echo "boot: $*" >&2; exit 1; }
plain() {
    case "$1" in /*) :;; *) return 1;; esac
    case "$1" in *[!a-zA-Z0-9_./-]*|*/../*|*/./*|*/..|*/.|*//*) return 1;; esac
    local part=$1
    while [ "$part" != / ]; do [ ! -L "$part" ] || return 1; part=${part%/*}; [ -n "$part" ] || part=/; done
}
if [ -n "$ROOT" ]; then
    plain "$ROOT" && [ "$ROOT" != / ] && [ -d "$ROOT" ] && [ -x "$ADAPTER" ] || fail fixture
    HELPER=$PORTABLE_TEST_HELPER; SUPERVISOR=$PORTABLE_TEST_SUPERVISOR
else
    [ -z "$ADAPTER" ] || fail fixture
    case "$(id)" in uid=0\(*) :;; *) fail 'real root shell required';; esac
    case "$BASE" in /data/*) :;; *) fail 'bundle outside data';; esac
fi
plain "$BASE" && plain "$STATE" && plain "$HELPER" && [ -x "$HELPER" ] || fail 'unsafe bundle/state/helper'
mkdir -p "$STATE" && chmod 700 "$STATE" || fail state
for file in enabled enabled.new attempt attempt.new origins origins.new manifest manifest.new maintenance reason reason.new fingerprint fingerprint.new runtime-mode runtime-mode.new bundle-hashes bundle-hashes.new framework-before framework-before.new boot-manifest boot-manifest.new skipped skipped.new dependencies dependencies.new runtime-policy runtime-policy.new reconcile reconcile.new; do
    [ ! -L "$STATE/$file" ] && { [ ! -e "$STATE/$file" ] || [ -f "$STATE/$file" ]; } || fail 'unsafe state file'
done
op() {
    if [ -n "$ROOT" ]; then "$ADAPTER" "$@"; return $?; fi
    case "$1" in
    boot) cat /proc/sys/kernel/random/boot_id;;
    get) getprop "$2";;
    dependencies) /system/bin/sh "$BASE/framework.sh" dependencies;;
    framework) /system/bin/sh "$BASE/framework.sh" identity;;
    framework-ready) /system/bin/sh "$BASE/framework.sh" ready "$(cat "$STATE/framework-before" 2>/dev/null)";;
    ap-prepare) /system/bin/sh "$BASE/ap.sh" prepare;;
    ap-check) /system/bin/sh "$BASE/ap.sh" check;;
    ap-disable) /system/bin/sh "$BASE/ap.sh" disable;;
    owned-overlays)
        local status=$(/system/bin/sh "$BASE/portable.sh" status) || return 1
        case "$status" in 'state|committed'*|'state|pending'*) return 0;; *) return 1;; esac;;
    plan) PORTABLE_HELPER=$HELPER /system/bin/sh "$BASE/overlay.sh" prepare "$2";;
    plan-boot) PORTABLE_HELPER=$HELPER /system/bin/sh "$BASE/overlay.sh" prepare-boot "$STATE/boot-manifest";;
    plan-static) PORTABLE_HELPER=$HELPER /system/bin/sh "$BASE/overlay.sh" prepare-boot "$STATE/boot-manifest";;
    apply) /system/bin/sh "$BASE/portable.sh" apply;;
    runtime-enable) /system/bin/sh "$PAYLOAD/runtime.sh" enable both;;
    runtime-disable) /system/bin/sh "$BASE/runtime.sh" disable;;
    overlay-disable) /system/bin/sh "$BASE/portable.sh" disable;;
    commit-static) [ ! -s "$STATE/boot-manifest" ] || /system/bin/sh "$BASE/portable.sh" commit;;
    commit) /system/bin/sh "$BASE/portable.sh" commit && /system/bin/sh "$BASE/runtime.sh" commit;;
    stop-android) setprop ctl.stop zygote;;
    start-android)
        local dependency result=0
        while read -r dependency; do
            case "$dependency" in ''|*[!a-zA-Z0-9_.-]*) result=1; continue;; esac
            setprop ctl.restart "$dependency" || result=1
        done < "$STATE/dependencies"
        setprop ctl.start zygote || return 1
        return "$result";;
    launch-dipo) am startservice -n com.daudio.app.dipo/.service.DipoService;;
    dipo-ready) /system/bin/sh "$BASE/session.sh" ready;;
    busy) /system/bin/sh "$BASE/session.sh" busy;;
    dirty)
        local status
        status=$(/system/bin/sh "$BASE/runtime.sh" status) || return 0
        case "$status" in 'runtime|disabled'|'runtime|expired') :;; *) return 0;; esac
        status=$(/system/bin/sh "$BASE/portable.sh" status) || return 0
        case "$status" in 'state|disabled'*|'state|prepared'*) return 1;; *) return 0;; esac;;
    session) exec /system/bin/sh "$BASE/session.sh" run;;
    session-stop) /system/bin/sh "$BASE/session.sh" stop;;
    session-ready) [ "$(/system/bin/sh "$BASE/session.sh" status)" = 'session|running' ];;
    active)
        if [ "$(cat "$STATE/runtime-mode" 2>/dev/null)" != static ]; then
        [ "$(/system/bin/sh "$BASE/runtime.sh" status)" = 'runtime|committed' ] || return 1
        fi
        local active_status=$(/system/bin/sh "$BASE/portable.sh" status)
        case "$active_status" in 'state|committed'*) return 0;; *) return 1;; esac;;
    pause) sleep 1;;
    *) return 1;;
    esac
}
put() { print -r -- "$2" > "$STATE/$1.new" && mv "$STATE/$1.new" "$STATE/$1"; }
enabled() { [ -f "$STATE/enabled" ] && [ "$(cat "$STATE/enabled")" = 1 ]; }
backoff() { put enabled 0; put reason "$1"; echo "boot: disabled: $1" >&2; }
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
unlock() { lock_release; LOCKED=0; }
lock() {
    lock_acquire || return 1
    LOCKED=1
    trap unlock EXIT
    trap 'exit 1' HUP INT TERM
}
origins() {
    local manifest=$1 feature source target digest uid gid mode kind extra expected actual
    while IFS='|' read -r feature source target digest uid gid mode kind extra; do
        [ -z "$extra" ] && plain "$ROOT$source" && plain "$ROOT$target" || return 1
        [ "$kind" = directory ] && continue
        [ "$kind" = static ] && plain "$ROOT$source.stock" && [ -f "$ROOT$source.stock" ] || return 1
        IFS= read -r expected < "$ROOT$source.stock" || return 1
        case "$expected" in ''|*[!a-f0-9]*) return 1;; esac
        [ "${#expected}" = 64 ] || return 1
        actual=$("$HELPER" sha256 "$ROOT$target") || return 1
        [ "$actual" = "$expected" ] || return 1
        print -r -- "$target|$expected|$("$HELPER" metadata "$ROOT$target")"
    done < "$manifest"
}
select_plan() {
    local feature source target digest uid gid mode kind extra origin odigest ouid ogid omode found
    : > "$STATE/boot-manifest.new" && : > "$STATE/skipped.new" || return 1
    while IFS='|' read -r feature source target digest uid gid mode kind extra; do
        [ -z "$extra" ] && plain "$ROOT$source" && plain "$ROOT$target" || return 1
        case "$feature:$(cat "$STATE/runtime-policy" 2>/dev/null)" in
        bt:skip-until-rearm|projection:skip-until-rearm)
            print -r -- "$feature|skipped|wireless-runtime-unavailable" >> "$STATE/skipped.new" || return 1
            continue;;
        esac
        if [ "$kind" = static ]; then
            found=0
            while IFS='|' read -r origin odigest ouid ogid omode; do
                [ "$origin" = "$target" ] || continue
                if [ "$("$HELPER" sha256 "$ROOT$target")" = "$odigest" ] && [ "$("$HELPER" metadata "$ROOT$target")" = "$ouid|$ogid|$omode" ]; then found=1; fi
                break
            done < "$STATE/origins"
            if [ "$found" = 0 ]; then
                case "$feature" in bt|projection) return 1;; esac
                print -r -- "$feature|skipped|stock-changed" >> "$STATE/skipped.new" || return 1
                continue
            fi
        fi
        print -r -- "$feature|$source|$target|$digest|$uid|$gid|$mode|$kind" >> "$STATE/boot-manifest.new" || return 1
    done < "$STATE/manifest"
    mv "$STATE/boot-manifest.new" "$STATE/boot-manifest" && mv "$STATE/skipped.new" "$STATE/skipped"
}
static_plan() {
    local feature rest
    : > "$STATE/boot-manifest.new" || return 1
    while IFS='|' read -r feature rest; do
        case "$feature" in bt|projection) print -r -- "$feature|skipped|wireless-runtime-unavailable" >> "$STATE/skipped";;
        *) print -r -- "$feature|$rest" >> "$STATE/boot-manifest.new";; esac || return 1
    done < "$STATE/boot-manifest"
    mv "$STATE/boot-manifest.new" "$STATE/boot-manifest" || return 1
    op overlay-disable || return 1
    [ ! -s "$STATE/boot-manifest" ] || { op plan-static && op apply; }
}
verify_origins() {
    local target digest uid gid mode extra actual
    [ -s "$STATE/origins" ] || return 1
    while IFS='|' read -r target digest uid gid mode extra; do
        [ -z "$extra" ] && plain "$ROOT$target" || return 1
        selected=0
        while IFS='|' read -r feature source chosen rest; do [ "$chosen" != "$target" ] || selected=1; done < "$STATE/boot-manifest"
        [ "$selected" = 1 ] || continue
        [ "$("$HELPER" sha256 "$ROOT$target")" = "$digest" ] && [ "$("$HELPER" metadata "$ROOT$target")" = "$uid|$gid|$mode" ] || return 1
    done < "$STATE/origins"
}
verify_bundle() {
    local sums=$1 digest name extra count=0
    plain "$sums" && [ -s "$sums" ] || return 1
    while read -r digest name extra; do
        [ -z "$extra" ] || return 1
        case "$digest" in ''|*[!a-f0-9]*) return 1;; esac
        [ "${#digest}" = 64 ] || return 1
        case "$name" in ''|/*|*[!a-zA-Z0-9_./-]*|../*|*/../*|*/./*|*//*) return 1;; esac
        plain "$BASE/$name" && [ -f "$BASE/$name" ] && [ "$("$HELPER" sha256 "$BASE/$name")" = "$digest" ] || return 1
        count=$((count+1))
    done < "$sums"
    [ "$count" -gt 0 ]
}
copy_payload() {
    # Native uninstall ignores a failed preuninstall hook. Live wrap properties
    # therefore must never point into the deletable NEMESIS package directory.
    local name output parent=$ROOT/data/local/gen5w-portable
    plain "$parent" && plain "$PAYLOAD" && plain "$PAYLOAD/bin" && plain "$PAYLOAD/dalvik" || return 1
    mkdir -p "$PAYLOAD/bin" "$PAYLOAD/dalvik" && chmod 755 "$parent" "$PAYLOAD" "$PAYLOAD/bin" "$PAYLOAD/dalvik" || return 1
    for name in runtime.sh overlay.sh framework.sh wrap-common.sh wrap-dipo.sh wrap-gpm.sh wrap-probe.sh bin/dex-patch dalvik/engine.jar dalvik/adapter.jar dalvik/libgen5whook.so dalvik/hook-vm-test.jar; do
        plain "$BASE/$name" && [ -f "$BASE/$name" ] || return 1
        output=$PAYLOAD/$name
        plain "$output" && plain "$output.new" || return 1
        cp "$BASE/$name" "$output.new" || return 1
        case "$name" in *.sh|bin/*) chmod 755 "$output.new";; *) chmod 644 "$output.new";; esac
        [ "$?" = 0 ] && [ "$("$HELPER" sha256 "$output.new")" = "$("$HELPER" sha256 "$BASE/$name")" ] && mv "$output.new" "$output" || return 1
    done
}
copy_rescue() {
    local name output
    plain "$STATE/recovery" && plain "$STATE/recovery/bin" || return 1
    mkdir -p "$STATE/recovery/bin" || return 1
    for name in rescue.sh runtime.sh overlay.sh bin/dex-patch; do
        plain "$BASE/$name" && [ -f "$BASE/$name" ] || return 1
        output=$STATE/recovery/$name
        plain "$output" && plain "$output.new" || return 1
        cp "$BASE/$name" "$output.new" && chmod 700 "$output.new" && mv "$output.new" "$output" || return 1
    done
}
bounded() {
    local timeout=60
    [ -z "$ROOT" ] || timeout=${PORTABLE_BOOT_TIMEOUT:-3}
    "$SUPERVISOR" supervise "$timeout" "$STATE/recovery/rescue.sh" "$BASE/boot.sh" "$1"
}
wait_zygote() {
    local count=0
    while [ "$(op get init.svc.zygote)" != "$1" ]; do
        count=$((count+1)); [ "$count" -lt 10 ] || return 1; op pause
    done
}
wait_framework() {
    local count=0
    while ! op framework-ready; do
        count=$((count+1)); [ "$count" -lt 90 ] || return 1; op pause
    done
}
cancelled() {
    enabled && return 0
    op session-stop
    bounded recover && wait_framework || fail 'cancelled startup restore/readiness failed'
    put reason disabled-restored
    exit 0
}
finish_static() {
    local count=0
    while ! op framework-ready; do
        cancelled
        count=$((count+1)); [ "$count" -lt 90 ] || return 1; op pause
    done
    op commit-static && put attempt "$current|healthy" && put reason runtime-unavailable && sync || return 1
    echo 'boot: independent static features active; optional CarPlay runtime unavailable'
}
command=${1:-run}; [ "$#" = 0 ] || shift
case "$command" in
transact|recover|recover-runtime)
    # The native supervisor has already armed its independent rescue process.
    print -r -- "$(op boot)" > "$STATE/maintenance" || fail maintenance
    previous_framework=$(op framework) || previous_framework=
    put framework-before "$previous_framework" || fail journal
    op stop-android && wait_zygote stopped || fail 'framework stop failed'
    if [ "$command" = transact ]; then
        if [ "$(cat "$STATE/reconcile" 2>/dev/null)" = 1 ]; then
            op runtime-disable && op overlay-disable && select_plan || fail 'owned resume reconciliation failed'
        fi
        enabled && verify_origins || fail 'activation identity failed'
        if [ -s "$STATE/boot-manifest" ]; then op plan-boot && op apply || fail 'activation failed';
        else op overlay-disable || fail 'empty plan restore failed'; fi
        enabled || fail 'activation cancelled'
        # QuickBoot can restore the same kernel boot_id while discarding wrap
        # properties. Retire the owned journal under stopped zygote first.
        op runtime-disable || fail 'previous runtime retirement failed'
        result=0
        if [ "$(cat "$STATE/runtime-policy" 2>/dev/null)" = skip-until-rearm ]; then
            put runtime-mode static || fail journal
        else op runtime-enable || result=$?; fi
        case "$result" in
        0) [ "$(cat "$STATE/runtime-policy" 2>/dev/null)" = skip-until-rearm ] || put runtime-mode full || fail journal;;
        77) static_plan && put runtime-mode static && put runtime-policy skip-until-rearm || fail 'static fallback failed';;
        *) fail 'runtime activation failed';;
        esac
    elif [ "$command" = recover-runtime ]; then
        op runtime-disable && static_plan && put runtime-mode static && put runtime-policy skip-until-rearm || fail 'runtime restore failed'
    else
        op runtime-disable && op overlay-disable || fail 'restore failed'
    fi
    op start-android && wait_zygote running || fail 'framework start failed'
    rm -f "$STATE/maintenance" || fail maintenance
    ;;
arm)
    [ "$#" = 1 ] && plain "$ROOT$1" && [ -f "$ROOT$1" ] || fail 'manifest required'
    lock || fail locked
    enabled && fail 'disable the current automatic installation first'
    op busy && fail 'another host/core/AP owner is active'
    verify_bundle "$BASE/SHA256SUMS" || fail 'bundle integrity failed'
    op dependencies > "$STATE/dependencies.new" && mv "$STATE/dependencies.new" "$STATE/dependencies" || fail 'stock zygote restart profile unavailable'
    op plan "$ROOT$1" || fail 'plan validation failed'
    origins "$ROOT$1" > "$STATE/origins.new" && [ -s "$STATE/origins.new" ] || fail 'prepared stock identity differs or is absent'
    cp "$ROOT$1" "$STATE/manifest.new" && mv "$STATE/manifest.new" "$STATE/manifest" && mv "$STATE/origins.new" "$STATE/origins" || fail manifest
    copy_rescue || fail 'cannot retain independent recovery payload'
    copy_payload || fail 'cannot retain accessible runtime payload'
    cp "$BASE/SHA256SUMS" "$STATE/bundle-hashes.new" && mv "$STATE/bundle-hashes.new" "$STATE/bundle-hashes" || fail 'bundle seal failed'
    op ap-prepare || fail 'AP mode/restart guard preparation failed'
    put runtime-policy full && put fingerprint "$(op get ro.build.fingerprint)" && put attempt "$(op boot)|armed" && put reason armed-next-boot && put enabled 1 || fail journal
    sync || { backoff arm-sync-failed; exit 1; }
    echo 'boot: armed for the next boot; current Android retained'
    ;;
run|activate)
    [ "$#" = 0 ] || fail arguments
    enabled || exit 0
    lock || fail locked
    IFS='|' read -r previous phase < "$STATE/attempt" || { backoff attempt-unreadable; exit 1; }
    current=$(op boot)
    case "$(cat "$STATE/runtime-policy" 2>/dev/null)" in full|skip-until-rearm) :;; *) backoff invalid-runtime-policy; exit 1;; esac
    case "$phase" in pending) backoff previous-startup-incomplete; exit 1;; armed|healthy|degraded) :;; *) backoff invalid-attempt; exit 1;; esac
    if [ "$command:$previous:$phase" = "run:$current:armed" ]; then exit 0; fi
    if [ "$command:$previous:$phase" = "run:$current:degraded" ]; then exit 1; fi
    if [ "$command:$previous:$phase" = "run:$current:healthy" ] && [ "$(cat "$STATE/runtime-policy" 2>/dev/null)" = skip-until-rearm ] && [ ! -s "$STATE/boot-manifest" ]; then exit 0; fi
    op dependencies > "$STATE/dependencies.new" && [ "$("$HELPER" sha256 "$STATE/dependencies.new")" = "$("$HELPER" sha256 "$STATE/dependencies")" ] || { backoff init-profile-changed; exit 1; }
    verify_bundle "$STATE/bundle-hashes" || { backoff bundle-changed; exit 1; }
    [ "$(cat "$STATE/fingerprint")" = "$(op get ro.build.fingerprint)" ] || { backoff firmware-changed; exit 1; }
    active=0
    put reconcile 0 || fail journal
    if op active; then active=1; op busy && exit 0; else
        op busy && { backoff foreign-session; exit 1; }
        ap_result=0; op ap-check || ap_result=$?
        case "$ap_result" in
        0) :;;
        77) put runtime-policy skip-until-rearm || fail journal;;
        *) backoff ap-guard-invalid; exit 1;;
        esac
        if op owned-overlays; then
            # QuickBoot may preserve our binds but discard wrap properties.
            # Unmount only proven owned overlays under the same stopped window,
            # then validate the now-visible stock before reapplying.
            put reconcile 1 || fail journal
        else
            select_plan && verify_origins || { backoff stock-changed; exit 1; }
        fi
    fi
    if [ "$active" = 0 ]; then copy_payload || { backoff runtime-copy-failed; exit 1; }; fi
    if [ "$active" = 0 ]; then
        # NEMESIS may launch before class_start main. Do not start zygote ahead
        # of init's initial main-class launch (Binder/native peers may be absent).
        count=0
        while [ "$(op get init.svc.zygote)" != running ]; do
            enabled || exit 0
            count=$((count+1)); [ "$count" -lt 90 ] || { backoff initial-zygote-unavailable; exit 1; }; op pause
        done
    fi
    put attempt "$current|pending" && sync || fail journal
    if [ "$active" = 0 ] && ! bounded transact; then backoff maintenance-failed; exit 1; fi
    cancelled
    count=0
    while ! op framework-ready; do
        cancelled
        count=$((count+1)); [ "$count" -lt 90 ] || { backoff boot-timeout; bounded recover; exit 1; }; op pause
    done
    if [ "$(cat "$STATE/runtime-mode" 2>/dev/null)" = static ]; then
        finish_static || { backoff static-commit-failed; bounded recover; exit 1; }
        exit 0
    fi
    cancelled
    op launch-dipo || { backoff dipo-start-failed; bounded recover; exit 1; }
    count=0
    while ! op dipo-ready; do
        cancelled
        count=$((count+1))
        if [ "$count" -ge 30 ]; then
            bounded recover-runtime && finish_static || { backoff runtime-fallback-failed; bounded recover; exit 1; }
            exit 0
        fi
        op pause
    done
    cancelled
    op session & child=$!
    count=0
    while ! op session-ready; do
        cancelled
        count=$((count+1)); [ "$count" -lt 15 ] || { op session-stop; backoff session-timeout; bounded recover; exit 1; }; op pause
    done
    cancelled
    op commit && put attempt "$current|healthy" && put reason startup-healthy || { op session-stop; backoff commit-failed; bounded recover; exit 1; }
    sync
    unlock
    trap 'op session-stop; exit 1' HUP INT TERM
    wait "$child"; result=$?
    if enabled; then
        op session-stop
        put attempt "$current|degraded" && put reason session-ended-this-boot && sync || fail journal
        # An ephemeral host exit does not poison the next boot. Do not restart
        # the framework while driving or retry repeatedly within this boot.
        [ "$result" != 0 ] || result=1
    fi
    exit "$result"
    ;;
disable)
    [ "$#" = 0 ] || fail arguments
    put enabled 0 || fail disable
    op session-stop || fail 'session stop request failed'
    count=0
    while op busy; do count=$((count+1)); [ "$count" -lt 35 ] || fail 'session has not stopped; auto-start is disabled'; op pause; done
    count=0
    while ! lock; do count=$((count+1)); [ "$count" -lt 75 ] || fail 'startup still busy; auto-start is disabled'; op pause; done
    if [ "$(cat "$STATE/reason" 2>/dev/null)" != disabled-restored ] && op dirty; then
        # An uninstall can outlive the package service shell, while its native
        # maintenance supervisor still owns a separate worker process group.
        count=0
        while [ -f "$STATE/maintenance" ] && [ "$(cat "$STATE/maintenance")" = "$(op boot)" ]; do
            count=$((count+1)); [ "$count" -lt 75 ] || fail 'maintenance remains active; auto-start disabled'; op pause
        done
        copy_rescue && bounded recover && wait_framework || fail 'auto-start disabled; inspect restore/readiness status or reboot'
    fi
    op ap-disable || fail 'automatic application disabled; AP marker restoration failed'
    put reason disabled-restored
    echo 'boot: automatic application disabled and owned overlays/wrappers restored'
    ;;
status)
    echo "enabled|$(cat "$STATE/enabled" 2>/dev/null)"
    echo "attempt|$(cat "$STATE/attempt" 2>/dev/null)"
    echo "reason|$(cat "$STATE/reason" 2>/dev/null)"
    echo "runtime-mode|$(cat "$STATE/runtime-mode" 2>/dev/null)"
    echo "runtime-policy|$(cat "$STATE/runtime-policy" 2>/dev/null)"
    [ ! -f "$STATE/skipped" ] || cat "$STATE/skipped"
    ;;
*) fail 'usage: boot.sh arm MANIFEST | run | activate | disable | status';;
esac
