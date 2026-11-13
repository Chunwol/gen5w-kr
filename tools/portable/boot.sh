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
for file in enabled enabled.new attempt attempt.new origins origins.new manifest manifest.new maintenance reason reason.new fingerprint fingerprint.new runtime-mode runtime-mode.new bundle-hashes bundle-hashes.new framework-before framework-before.new boot-manifest boot-manifest.new skipped skipped.new dependencies dependencies.new runtime-policy runtime-policy.new reconcile reconcile.new mode mode.new consumed consumed.new; do
    [ ! -L "$STATE/$file" ] && { [ ! -e "$STATE/$file" ] || [ -f "$STATE/$file" ]; } || fail 'unsafe state file'
done
op() {
    if [ -n "$ROOT" ]; then
        case "$1" in framework|framework-ready|launch-dipo|dipo-ready|probe-ready|busy|session-ready)
            "$SUPERVISOR" supervise "${PORTABLE_QUERY_TIMEOUT:-8}" /bin/true "$ADAPTER" "$@";;
        *) "$ADAPTER" "$@";; esac
        return $?
    fi
    case "$1" in
    boot) cat /proc/sys/kernel/random/boot_id;;
    get) getprop "$2";;
    dependencies) /system/bin/sh "$BASE/framework.sh" dependencies;;
    framework) "$SUPERVISOR" supervise 8 /system/bin/true /system/bin/sh "$BASE/framework.sh" identity;;
    framework-ready) "$SUPERVISOR" supervise 8 /system/bin/true /system/bin/sh "$BASE/framework.sh" ready "$(cat "$STATE/framework-before" 2>/dev/null)";;
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
    runtime-probe) /system/bin/sh "$PAYLOAD/runtime.sh" enable probe;;
    probe-ready) /system/bin/sh "$BASE/check.sh" probe-loaded;;
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
    launch-dipo) "$SUPERVISOR" supervise 8 /system/bin/true /system/bin/am startservice -n com.daudio.app.dipo/.service.DipoService;;
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
    clock) local up rest; read -r up rest < /proc/uptime; echo "${up%%.*}";;
    pause) sleep 1;;
    *) return 1;;
    esac
}
put() { print -r -- "$2" > "$STATE/$1.new" && mv "$STATE/$1.new" "$STATE/$1"; }
enabled() { [ -f "$STATE/enabled" ] && [ "$(cat "$STATE/enabled")" = 1 ]; }
backoff() { put enabled 0; put reason "$1"; sync; echo "boot: disabled: $1" >&2; }
# Durable, monotonic stage evidence. No wall-clock assumption after RTC changes.
stage() {
    # Diagnostics must never prevent disable or emergency restoration.
    if [ ! -L "$STATE/timeline" ] && { [ ! -e "$STATE/timeline" ] || [ -f "$STATE/timeline" ]; }; then
        print -r -- "$(clock)|$*" >> "$STATE/timeline" 2>/dev/null || :
    fi
    return 0
}
clock() { local up rest; read -r up rest < /proc/uptime || return 1; echo "${up%%.*}"; }
# Every wait has a monotonic deadline as well as an iteration bound. Each
# potentially blocking Android query is independently supervised below.
deadline() { local seconds=$1; if [ -n "$ROOT" ] && [ -n "${PORTABLE_TEST_DEADLINE_CAP:-}" ]; then seconds=$PORTABLE_TEST_DEADLINE_CAP; fi; limit=$(( $(clock) + seconds )); }
within() { [ "$(clock)" -lt "$limit" ]; }
stop_session() {
    op session-stop || return 1
    local count=0 limit
    deadline 35
    while op busy; do
        count=$((count+1)); [ "$count" -lt 35 ] && within || return 1
        op pause
    done
}

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
    PORTABLE_BOOT_GUARDED=1 "$SUPERVISOR" supervise "$timeout" "$STATE/recovery/rescue.sh" "$BASE/boot.sh" "$1"
}
wait_zygote() {
    local count=0 limit
    deadline 10
    while [ "$(op get init.svc.zygote)" != "$1" ]; do
        count=$((count+1)); [ "$count" -lt 10 ] && within || return 1; op pause
    done
}
wait_framework() {
    local count=0 limit
    deadline 90
    while ! op framework-ready; do
        count=$((count+1)); [ "$count" -lt 90 ] && within || return 1; op pause
    done
}
cancelled() {
    enabled && return 0
    stop_session || fail 'session stop timed out; auto-start disabled'
    bounded recover && wait_framework || fail 'cancelled startup restore/readiness failed'
    put reason disabled-restored
    exit 0
}
finish_static() {
    local count=0 limit
    deadline 90
    while ! op framework-ready; do
        cancelled
        count=$((count+1)); [ "$count" -lt 90 ] && within || return 1; op pause
    done
    op commit-static && put attempt "$current|healthy" && put reason runtime-unavailable && sync || return 1
    echo 'boot: independent static features active; optional CarPlay runtime unavailable'
}
command=${1:-run}; [ "$#" = 0 ] || shift
case "$command" in status) :;; *) stage "$command begin" || fail timeline;; esac
case "$command" in
transact|recover|recover-runtime)
    [ "${PORTABLE_BOOT_GUARDED:-}" = 1 ] || fail 'internal command requires native supervision'
    # The native supervisor has already armed its independent rescue process.
    print -r -- "$(op boot)" > "$STATE/maintenance" || fail maintenance
    previous_framework=$(op framework) || previous_framework=
    put framework-before "$previous_framework" || fail journal
    stage framework-stop || fail timeline
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
        if [ "$(cat "$STATE/mode" 2>/dev/null)" = probe ]; then
            op runtime-probe && put runtime-mode probe || fail 'probe wrapper failed'
        elif [ "$(cat "$STATE/runtime-policy" 2>/dev/null)" = skip-until-rearm ]; then
            put runtime-mode static || fail journal
        else op runtime-enable || result=$?; fi
        case "$result" in
        0) if [ "$(cat "$STATE/mode" 2>/dev/null)" != probe ] && [ "$(cat "$STATE/runtime-policy" 2>/dev/null)" != skip-until-rearm ]; then put runtime-mode full || fail journal; fi;;
        77) static_plan && put runtime-mode static && put runtime-policy skip-until-rearm || fail 'static fallback failed';;
        *) fail 'runtime activation failed';;
        esac
    elif [ "$command" = recover-runtime ]; then
        op runtime-disable && static_plan && put runtime-mode static && put runtime-policy skip-until-rearm || fail 'runtime restore failed'
    else
        op runtime-disable && op overlay-disable || fail 'restore failed'
    fi
    stage framework-start || fail timeline
    op start-android && wait_zygote running || fail 'framework start failed'
    rm -f "$STATE/maintenance" || fail maintenance
    ;;
probe)
    [ "$#" = 1 ] || fail 'probe manifest required'
    # arm does not stop Android. The only mutation window is the native
    # supervisor below; its own setsid worker/guardian survives caller loss.
    "$BASE/boot.sh" arm --probe "$1" || exit 1
    exec "$BASE/boot.sh" activate
    ;;
arm)
    mode=auto
    case "${1:-}" in --trial) mode=trial; shift;; --probe) mode=probe; shift;; esac
    [ "$#" = 1 ] && plain "$ROOT$1" && [ -f "$ROOT$1" ] || fail 'manifest required'
    lock || fail locked
    enabled && fail 'disable the current automatic installation first'
    [ ! -f "$STATE/maintenance" ] || [ "$(cat "$STATE/maintenance")" != "$(op boot)" ] || fail 'independent recovery is still active; wait or cold restart'
    if [ -f "$STATE/attempt" ]; then
        IFS='|' read -r prior_boot prior_phase < "$STATE/attempt" || fail 'attempt state unreadable; inspect recovery state'
        [ "$prior_boot:$prior_phase" != "$(op boot):pending" ] || fail 'unfinished attempt in this boot; cold restart before re-arm'
    fi
    op busy && fail 'another host/core/AP owner is active'
    verify_bundle "$BASE/SHA256SUMS" || fail 'bundle integrity failed'
    op dependencies > "$STATE/dependencies.new" && mv "$STATE/dependencies.new" "$STATE/dependencies" || fail 'stock zygote restart profile unavailable'
    if [ "$mode" = probe ]; then
        # A premise trial must not smuggle a modified OEM file or declarations.
        rows=0
        while IFS='|' read -r feature source target digest uid gid permissions kind extra; do
            rows=$((rows+1))
            [ "$rows:$feature:$target:$kind" = '1:probe:/system/app/HKMC_DiPO.odex:static' ] && [ -z "$extra" ] && plain "$ROOT$source" || fail 'only one identical DiPO probe row is allowed'
            [ "$("$HELPER" sha256 "$ROOT$source")" = "$("$HELPER" sha256 "$ROOT$target")" ] || fail 'probe must be byte-identical to stock'
        done < "$ROOT$1"
        [ "$rows" = 1 ] || fail 'empty probe manifest'
    fi
    op plan "$ROOT$1" || fail 'plan validation failed'
    origins "$ROOT$1" > "$STATE/origins.new" && [ -s "$STATE/origins.new" ] || fail 'prepared stock identity differs or is absent'
    cp "$ROOT$1" "$STATE/manifest.new" && mv "$STATE/manifest.new" "$STATE/manifest" && mv "$STATE/origins.new" "$STATE/origins" || fail manifest
    copy_rescue || fail 'cannot retain independent recovery payload'
    copy_payload || fail 'cannot retain accessible runtime payload'
    cp "$BASE/SHA256SUMS" "$STATE/bundle-hashes.new" && mv "$STATE/bundle-hashes.new" "$STATE/bundle-hashes" || fail 'bundle seal failed'
    if [ "$mode" != probe ]; then op ap-prepare || fail 'AP mode/restart guard preparation failed'; fi
    if [ "$mode" = trial ]; then
        # Every trial, including manual re-arm, begins with authored radio held.
        radio=$ROOT/data/nemesis/gen5wkr.ui-wireless-off
        plain "$radio" && { [ ! -e "$radio" ] || [ -f "$radio" ]; } || fail 'unsafe wireless hold marker'
        mkdir -p "$ROOT/data/nemesis" || fail 'wireless hold directory'
        [ -e "$radio" ] || { : > "$radio" && chmod 600 "$radio"; } || fail 'wireless hold failed'
    fi
    put mode "$mode" && put consumed none || fail journal
    put runtime-policy full && put fingerprint "$(op get ro.build.fingerprint)" && put attempt "$(op boot)|armed" && put reason armed-next-boot && put enabled 1 || fail journal
    sync || { backoff arm-sync-failed; exit 1; }
    echo 'boot: armed for the next boot; current Android retained'
    ;;
run|activate)
    [ "$#" = 0 ] || fail arguments
    enabled || exit 0
    lock || fail locked
    [ ! -f "$STATE/maintenance" ] || [ "$(cat "$STATE/maintenance")" != "$(op boot)" ] || fail 'independent recovery is still active; wait or cold restart'
    IFS='|' read -r previous phase < "$STATE/attempt" || { backoff attempt-unreadable; exit 1; }
    current=$(op boot)
    if [ "$previous:$phase" = "$current:pending" ]; then backoff previous-startup-incomplete; exit 1; fi
    mode=$(cat "$STATE/mode" 2>/dev/null)
    case "$mode" in auto|trial|probe) :;; *) backoff invalid-mode; exit 1;; esac
    if [ "$mode" != auto ] && [ "$(cat "$STATE/consumed" 2>/dev/null)" != none ]; then
        # A resume may reuse boot_id. Never re-enter maintenance for a consumed
        # trial even then; an intact healthy session may simply remain active.
        if [ "$previous:$phase" = "$current:healthy" ] && op active; then exit 0; fi
        backoff trial-consumed
        if [ "$previous" = "$current" ] && op dirty; then
            # A same-id resume can leave our binds without the owned wrappers.
            # Retire that partial trial; never start another activation.
            stop_session || fail 'consumed trial cleanup still busy; cold restart required'
            bounded recover && wait_framework || fail 'consumed trial restore failed; cold restart required'
            put reason trial-consumed-restored && sync || fail journal
        fi
        exit 1
    fi
    if [ "$mode" = probe ] && { [ "$command" != activate ] || [ "$previous:$phase" != "$current:armed" ]; }; then
        backoff probe-not-explicit; exit 1
    fi
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
        ap_result=0
        if [ "$mode" != probe ]; then op ap-check || ap_result=$?; fi
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
        count=0; deadline 90
        while [ "$(op get init.svc.zygote)" != running ]; do
            enabled || exit 0
            count=$((count+1)); [ "$count" -lt 90 ] && within || { backoff initial-zygote-unavailable; exit 1; }; op pause
        done
    fi
    put consumed "$current" && put attempt "$current|pending" && sync || fail journal
    stage maintenance-start || fail timeline
    if [ "$active" = 0 ] && ! bounded transact; then backoff maintenance-failed; exit 1; fi
    cancelled
    count=0; deadline 90
    while ! op framework-ready; do
        cancelled
        count=$((count+1)); [ "$count" -lt 90 ] && within || { backoff boot-timeout; bounded recover; exit 1; }; op pause
    done
    stage framework-ready || fail timeline
    if [ "$mode" = probe ]; then
        op launch-dipo || { backoff probe-start-failed; bounded recover; exit 1; }
        count=0; deadline 30
        while ! op probe-ready; do
            cancelled
            count=$((count+1)); [ "$count" -lt 30 ] && within || { backoff probe-timeout; bounded recover; exit 1; }; op pause
        done
        put attempt "$current|healthy" && put reason probe-ready-one-shot && sync || fail journal
        stage probe-ready
        echo 'boot: supervised no-hook probe active; disable explicitly or cold boot to restore'
        exit 0
    fi
    if [ "$(cat "$STATE/runtime-mode" 2>/dev/null)" = static ]; then
        finish_static || { backoff static-commit-failed; bounded recover; exit 1; }
        exit 0
    fi
    cancelled
    op launch-dipo || { backoff dipo-start-failed; bounded recover; exit 1; }
    count=0; deadline 30
    while ! op dipo-ready; do
        cancelled
        count=$((count+1))
        if [ "$count" -ge 30 ] || ! within; then
            bounded recover-runtime && finish_static || { backoff runtime-fallback-failed; bounded recover; exit 1; }
            exit 0
        fi
        op pause
    done
    cancelled
    op session & child=$!
    count=0; deadline 15
    while ! op session-ready; do
        cancelled
        count=$((count+1)); [ "$count" -lt 15 ] && within || { backoff session-timeout; stop_session || fail 'session cleanup still busy'; bounded recover; exit 1; }; op pause
    done
    cancelled
    op commit && put attempt "$current|healthy" && put reason startup-healthy || { backoff commit-failed; stop_session || fail 'session cleanup still busy'; bounded recover; exit 1; }
    sync
    stage startup-healthy || fail timeline
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
    stop_session || fail 'session has not stopped; auto-start is disabled'
    count=0; deadline 75
    while ! lock; do count=$((count+1)); [ "$count" -lt 75 ] && within || fail 'startup still busy; auto-start is disabled'; op pause; done
    # A surviving supervised worker may not have applied anything yet. Always
    # wait for its marker before inspecting dirtiness or claiming restoration.
    count=0; deadline 75
    while [ -f "$STATE/maintenance" ] && [ "$(cat "$STATE/maintenance")" = "$(op boot)" ]; do
        count=$((count+1)); [ "$count" -lt 75 ] && within || fail 'maintenance remains active; auto-start disabled'; op pause
    done
    if [ "$(cat "$STATE/reason" 2>/dev/null)" != disabled-restored ] && op dirty; then
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
    echo "mode|$(cat "$STATE/mode" 2>/dev/null)"
    echo "consumed|$(cat "$STATE/consumed" 2>/dev/null)"
    echo "runtime-mode|$(cat "$STATE/runtime-mode" 2>/dev/null)"
    echo "runtime-policy|$(cat "$STATE/runtime-policy" 2>/dev/null)"
    [ ! -f "$STATE/skipped" ] || cat "$STATE/skipped"
    ;;
*) fail 'usage: boot.sh arm [--trial] MANIFEST | probe MANIFEST | run | activate | disable | status';;
esac
