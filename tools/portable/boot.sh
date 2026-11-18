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
# Android stays running during readiness observation. A stock restart in the
# isolated ARM VM takes 152 seconds; use the same bounded allowance as initial
# framework startup. The independently supervised stopped transaction stays 60s.
FRAMEWORK_READY_SECONDS=300
# Cold session startup also optimizes authored DEX and starts Java workers.
SESSION_READY_SECONDS=90
APP_READY_SECONDS=180
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
for file in enabled enabled.new attempt attempt.new origins origins.new manifest manifest.new maintenance reason reason.new fingerprint fingerprint.new runtime-mode runtime-mode.new bundle-hashes bundle-hashes.new framework-before framework-before.new boot-manifest boot-manifest.new skipped skipped.new dependencies dependencies.new runtime-policy runtime-policy.new reconcile reconcile.new mode mode.new consumed consumed.new rescue-request rescue-request.new rescue-result rescue-result.new reset-baseline reset-baseline.new reset-current reset-scan retry-count retry-count.new health-lost health-lost.new dropbox-baseline dropbox-baseline.new dropbox-current dropbox-scan; do
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
    rescue-requested) /system/bin/sh "$BASE/rescue-watch.sh" check;;
    rescue-alive) /system/xbin/nemesis service list 2>/dev/null | grep -q '^gen5w\.kr\.portable/rescue|restart|running|';;
    get) getprop "$2";;
    dependencies) /system/bin/sh "$BASE/framework.sh" dependencies;;
    framework) "$SUPERVISOR" supervise 8 /system/bin/true /system/bin/sh "$BASE/framework.sh" identity;;
    framework-ready) "$SUPERVISOR" supervise 15 /system/bin/true /system/bin/sh "$BASE/framework.sh" ready "$(cat "$STATE/framework-before" 2>/dev/null)";;
    ap-prepare) /system/bin/sh "$BASE/ap.sh" prepare;;
    ap-check) /system/bin/sh "$BASE/ap.sh" check;;
    ap-disable) /system/bin/sh "$BASE/ap.sh" disable;;
    owned-overlays)
        local status=$(/system/bin/sh "$BASE/portable.sh" status) || return 1
        case "$status" in 'state|committed'*|'state|pending'*) return 0;; *) return 1;; esac;;
    plan) PORTABLE_HELPER=$HELPER /system/bin/sh "$BASE/overlay.sh" prepare "$2";;
    plan-ready)
        local overlay_state=$ROOT/data/local/gen5w-portable/overlay
        [ "$(cat "$overlay_state/state")" = prepared ] &&
        [ "$(cat "$overlay_state/prepareboot")" = "$(op boot)" ] &&
        [ "$("$HELPER" sha256 "$overlay_state/manifest")" = "$("$HELPER" sha256 "$STATE/boot-manifest")" ];;
    plan-boot) PORTABLE_HELPER=$HELPER /system/bin/sh "$BASE/overlay.sh" prepare-boot "$STATE/boot-manifest";;
    plan-static) PORTABLE_HELPER=$HELPER /system/bin/sh "$BASE/overlay.sh" prepare-boot "$STATE/boot-manifest";;
    apply) /system/bin/sh "$BASE/portable.sh" apply;;
    runtime-enable) /system/bin/sh "$PAYLOAD/runtime.sh" enable both;;
    runtime-preflight) /system/bin/sh "$PAYLOAD/runtime.sh" preflight;;
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
        # V039 libcheck_androidreset (system_server start): sys.boot_count other
        # than 0 means "Android Reset" and, with persist.sys.sync.reset=1, a full
        # reboot (vehicle 2026-11-13). Our restart is intentional: mark it first boot.
        setprop sys.boot_count 0 || result=1
        setprop ctl.start zygote || return 1
        return "$result";;
    launch-dipo) "$SUPERVISOR" supervise 8 /system/bin/true /system/bin/am startservice -n com.daudio.app.dipo/.service.DipoService;;
    dipo-ready) "$SUPERVISOR" supervise 8 /system/bin/true /system/bin/sh "$BASE/session.sh" adapter-ready;;
    busy) /system/bin/sh "$BASE/session.sh" busy;;
    dirty)
        local status
        status=$(/system/bin/sh "$BASE/runtime.sh" status) || return 0
        case "$status" in 'runtime|disabled'|'runtime|expired') :;; *) return 0;; esac
        status=$(/system/bin/sh "$BASE/portable.sh" status) || return 0
        case "$status" in 'state|disabled'*|'state|prepared'*|'state|expired'*) return 1;; *) return 0;; esac;;
    session) exec /system/bin/sh "$BASE/session.sh" run;;
    session-stop) "$SUPERVISOR" supervise 90 /system/bin/true /system/bin/sh "$BASE/session.sh" stop-maintenance;;
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
    deadline 120
    while op busy || { [ -n "${child:-}" ] && kill -0 "$child" 2>/dev/null; }; do
        count=$((count+1)); [ "$count" -lt 120 ] && within || return 1
        op pause
    done
    # Retry orphan-owned cleanup if the starter's EXIT handler retained it.
    op session-stop
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
    for name in rescue.sh rescue-watch.sh boot.sh runtime.sh overlay.sh portable.sh ap.sh session.sh framework.sh bin/dex-patch; do
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
    deadline "$FRAMEWORK_READY_SECONDS"
    while ! op framework-ready; do
        count=$((count+1)); [ "$count" -lt "$FRAMEWORK_READY_SECONDS" ] && within || return 1; op pause
    done
}
wait_initial_framework() {
    # NEMESIS starts before Android's main class on some units. A running
    # zygote alone does not make dalvikvm safe: wait for the newly registered
    # package/activity services and ActivityManager mBooted state first.
    local count=0 limit
    deadline "$FRAMEWORK_READY_SECONDS"
    while ! op framework-ready; do
        enabled || return 1
        count=$((count+1)); [ "$count" -lt "$FRAMEWORK_READY_SECONDS" ] && within || return 1
        op pause
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
    deadline "$FRAMEWORK_READY_SECONDS"
    while ! op framework-ready; do
        cancelled
        count=$((count+1)); [ "$count" -lt "$FRAMEWORK_READY_SECONDS" ] && within || return 1; op pause
    done
    op commit-static && put attempt "$current|healthy" && put reason runtime-unavailable && sync || return 1
    echo 'boot: independent static features active; optional CarPlay runtime unavailable'
}
# Bound retained kernel evidence reads: proc files often report st_size=0.
# Absence is not a clean-shutdown acknowledgement; only positive new evidence
# or a reported panic/watchdog reset latches operation off.
reset_snapshot() {
    local path digest flag
    for path in /proc/last_kmsg /sys/fs/pstore/console-ramoops /sys/fs/pstore/console-ramoops-0 /sys/fs/pstore/dmesg-ramoops-0; do
        [ -e "$ROOT$path" ] || [ -L "$ROOT$path" ] || continue
        plain "$ROOT$path" && [ -f "$ROOT$path" ] || return 1
        # dd itself bounds the read to 8 MiB (the toolbox has no wc/stat).
        dd if="$ROOT$path" of="$STATE/reset-scan" bs=65536 count=128 2>/dev/null || return 1
        digest=$("$HELPER" sha256 "$STATE/reset-scan") || return 1
        flag=none
        grep -qE 'Kernel panic - not syncing|BUG: soft lockup|watchdog bite|watchdog bark' "$STATE/reset-scan" && flag=panic
        print -r -- "$path|$digest|$flag"
    done
    rm -f "$STATE/reset-scan"
}
scan_bounded() {
    # A retained backlog of 19 new records takes 27s on V039 ARM emulation.
    # This read-only scan runs while Android stays up, before maintenance.
    # Keep reset reads short and keep the stopped transaction's own budget.
    local seconds=15
    [ "$1" != dropbox-scan ] || seconds=60
    if [ -n "$ROOT" ]; then
        "$SUPERVISOR" supervise "$seconds" /bin/true /usr/bin/mksh "$BASE/boot.sh" "$1"
    else
        "$SUPERVISOR" supervise "$seconds" /system/bin/true /system/bin/sh "$BASE/boot.sh" "$1"
    fi
}
reset_bounded() { scan_bounded reset-snapshot; }
# Android dropbox is the only failure record that survives on V039 (no
# last_kmsg/ramoops). Names are compared with the last admitted boot; wall
# clock timestamps are not trusted. SYSTEM_RESTART is deliberately excluded:
# our own maintenance restarts the runtime every boot.
DROPBOX=$ROOT/data/system/dropbox
dropbox_names() {
    local entry name count=0
    plain "$DROPBOX" || return 1
    [ -e "$DROPBOX" ] || [ -L "$DROPBOX" ] || return 0
    [ -d "$DROPBOX" ] && [ ! -L "$DROPBOX" ] || return 1
    for entry in "$DROPBOX"/system_server_crash@* "$DROPBOX"/system_server_watchdog@* "$DROPBOX"/SYSTEM_TOMBSTONE@* \
        "$DROPBOX"/system_app_crash@* "$DROPBOX"/system_app_native_crash@* "$DROPBOX"/system_app_anr@* \
        "$DROPBOX"/data_app_crash@* "$DROPBOX"/data_app_native_crash@* "$DROPBOX"/data_app_anr@*; do
        [ -e "$entry" ] || [ -L "$entry" ] || continue
        name=${entry##*/}
        case "$name" in *[!a-zA-Z0-9_@.]*) return 1;; esac
        count=$((count+1)); [ "$count" -le 4096 ] || return 1
        print -r -- "$name"
    done
}
# Prints clean or hit|NAME. Framework crash/watchdog names alone are failures;
# App entries identify their failed Process, not incidental CPU-table mentions.
# Native tombstones identify the crashed process in their pid/command header.
dropbox_scan() {
    local name file pattern baseline newline='
'
    [ -f "$STATE/dropbox-baseline" ] || return 1
    dropbox_names > "$STATE/dropbox-current" || return 1
    if cmp "$STATE/dropbox-current" "$STATE/dropbox-baseline" >/dev/null 2>&1; then echo clean; return 0; fi
    # Names contain no shell pattern characters or newlines (dropbox_names).
    # Read once: a grep process per historical file exceeds the native scan
    # budget on the vehicle CPU. Quoted newline boundaries retain exact matches.
    baseline=$(cat "$STATE/dropbox-baseline") || return 1
    while IFS= read -r name; do
        case "$newline$baseline$newline" in *"$newline$name$newline"*) continue;; esac
        case "$name" in system_server_crash@*|system_server_watchdog@*) print -r -- "hit|$name"; return 0;; esac
        # plain() rejects '@'; the directory was checked and the name validated.
        file=$DROPBOX/$name
        [ -f "$file" ] && [ ! -L "$file" ] || return 1
        rm -f "$STATE/dropbox-scan"
        case "$name" in
        *.lost) continue;;
        *.gz) gzip -d -c "$file" 2>/dev/null | dd of="$STATE/dropbox-scan" bs=65536 count=1 2>/dev/null;;
        *) dd if="$file" of="$STATE/dropbox-scan" bs=65536 count=1 2>/dev/null || return 1;;
        esac
        [ -f "$STATE/dropbox-scan" ] || continue
        pattern='^Process:[[:space:]]+'
        case "$name" in
        SYSTEM_TOMBSTONE@*|*_native_crash@*) pattern='^(Process:|Cmd line:|pid:.*(name:|>>>))[[:space:]]+';;
        esac
        pattern="$pattern"'(com\.daudio\.app\.dipo|com\.google\.android\.projection|com\.tcc\.iap2(server)?|com\.hkmc\.wifisettings)([.:[:space:]]|$)'
        if grep -qE "$pattern" "$STATE/dropbox-scan"; then
            rm -f "$STATE/dropbox-scan"; print -r -- "hit|$name"; return 0
        fi
    done < "$STATE/dropbox-current"
    rm -f "$STATE/dropbox-scan"
    echo clean
}
reset_check() {
    local reason path digest flag
    reason=$(op get ro.boot.bootreason) || return 1
    case "$reason" in *panic*|*watchdog*|*wdog*|*wdt*|*PANIC*|*WATCHDOG*) return 77;; esac
    [ -f "$STATE/reset-baseline" ] && reset_bounded > "$STATE/reset-current" || return 1
    while IFS='|' read -r path digest flag; do
        if [ "$flag" = panic ] && ! grep -qFx "$path|$digest|$flag" "$STATE/reset-baseline"; then return 77; fi
    done < "$STATE/reset-current"
}
command=${1:-run}; [ "$#" = 0 ] || shift
case "$command" in status) :;; *) stage "$command begin" || fail timeline;; esac
case "$command" in
reset-snapshot) reset_snapshot;;
dropbox-names) dropbox_names;;
dropbox-scan) dropbox_scan;;
update-retire)
    [ "$#" = 0 ] || fail arguments
    lock || fail locked
    if [ -f "$STATE/update-held" ]; then
        IFS='|' read -r held_boot held_enabled held_overlay held_runtime held_extra < "$STATE/update-held" || fail update-state
        [ -z "$held_extra" ] && [ "$held_boot" = "$(op boot)" ] || fail stale-update-state
        overlay_status=$(/system/bin/sh "$BASE/overlay.sh" status) || fail overlay-status
        case "$held_overlay" in
            committed) case "$overlay_status" in *'state|retired-pending'*) echo 'boot: update retirement already held'; exit 0;; *) fail 'update state is held without its retirement journal';; esac;;
            inactive) case "$overlay_status" in *'state|disabled'*|*'state|expired'*|*'state|prepared'*|*'state|retired'*) echo 'boot: update hold already recorded'; exit 0;; *) fail 'update state is held with an unexpected overlay';; esac;;
            *) fail 'update state has an invalid prior overlay flag';;
        esac
    fi
    prior_enabled=0; enabled && prior_enabled=1
    runtime_status=$(/system/bin/sh "$BASE/runtime.sh" status) || fail runtime-status
    case "$runtime_status" in 'runtime|committed') runtime_kind=committed;; 'runtime|disabled'|'runtime|expired') runtime_kind=inactive;; *) fail 'runtime wrapper state is not safe for update';; esac
    overlay_status=$(/system/bin/sh "$BASE/overlay.sh" status) || fail overlay-status
    case "$overlay_status" in
        *'state|committed'*|*'state|retired-pending'*) overlay_kind=committed;;
        *'state|disabled'*|*'state|expired'*|*'state|prepared'*|*'state|retired'*) overlay_kind=inactive;;
        *) fail 'overlay state is not safe for update';;
    esac
    print -r -- "$(op boot)|$prior_enabled|$overlay_kind|$runtime_kind" > "$STATE/update-held.new" && mv "$STATE/update-held.new" "$STATE/update-held" || fail update-journal
    stop_session || fail 'owned session could not stop for update'
    if ! /system/bin/sh "$BASE/runtime.sh" update-disable; then
        rm -f "$STATE/update-held" "$STATE/update-held.new"
        fail 'owned wrappers could not be retired for update without restarting Android'
    fi
    if [ "$overlay_kind" = committed ] && ! echo "$overlay_status" | grep -q 'state|retired-pending'; then
        if ! /system/bin/sh "$BASE/overlay.sh" retire-live hold; then
            [ "$runtime_kind" != committed ] || /system/bin/sh "$BASE/runtime.sh" update-restore || :
            rm -f "$STATE/update-held" "$STATE/update-held.new"
            fail 'owned overlays could not be retired without restarting Android'
        fi
    fi
    if ! put enabled 0 || ! put reason update-held || ! sync; then
        if [ "$overlay_kind" = committed ]; then /system/bin/sh "$BASE/overlay.sh" retire-restore || :; fi
        [ "$runtime_kind" != committed ] || /system/bin/sh "$BASE/runtime.sh" update-restore || :
        rm -f "$STATE/update-held" "$STATE/update-held.new"
        fail update-disable
    fi
    echo 'boot: owned overlays retired and auto-start held for package update; Android was not restarted'
    ;;
update-restore)
    [ "$#" = 0 ] || fail arguments
    recovery_state=$ROOT/data/local/gen5w-portable/persistent/recovery
    [ ! -L "$recovery_state/transaction-needs-recovery" ] && [ ! -e "$recovery_state/transaction-needs-recovery" ] ||
        fail 'persistent rollback is uncertain; keep the old view retired and use the independent restore USB'
    # Once the persistent writer has committed and its exact live state
    # verifies, an installer failure after that point must never rebind the
    # previous transient view over the new /system payload.
    commit_marker=$recovery_state/transaction-committed
    if [ -e "$commit_marker" ] || [ -L "$commit_marker" ]; then
        [ -f "$commit_marker" ] && [ ! -L "$commit_marker" ] || fail 'persistent commit marker is unsafe; leaving the old view retired'
        lock || fail locked
        /system/bin/sh "$BASE/persistent-start.sh" verify >/dev/null 2>&1 ||
            fail 'persistent commit was recorded but cannot be verified; leaving the old view retired for recovery'
        overlay_status=$(/system/bin/sh "$BASE/overlay.sh" status) || fail overlay-status
        case "$overlay_status" in
            *'state|retired-pending'*) /system/bin/sh "$BASE/overlay.sh" retire-finalize || fail 'committed persistent update could not finalize the held overlay journal';;
            *) :;;
        esac
        stop_session || fail 'committed persistent update could not stop the retired session'
        put enabled 1 && put reason persistent-update-committed &&
            rm -f "$STATE/update-held" "$STATE/update-enabled" "$commit_marker" "$recovery_state/transaction-in-progress" &&
            sync || fail persistent-update-state
        echo 'boot: persistent /system update is verified; prior transient wrappers remain retired'
        exit 0
    fi
    [ ! -L "$recovery_state/transaction-in-progress" ] && [ ! -e "$recovery_state/transaction-in-progress" ] ||
        fail 'persistent write was interrupted; keep the old view retired and use the independent restore USB'
    if [ -f "$STATE/update-held" ] && [ ! -L "$STATE/update-held" ] &&
       /system/bin/sh "$BASE/persistent-start.sh" verify >/dev/null 2>&1; then
        lock || fail locked
        overlay_status=$(/system/bin/sh "$BASE/overlay.sh" status) || fail overlay-status
        case "$overlay_status" in
            *'state|retired-pending'*) /system/bin/sh "$BASE/overlay.sh" retire-finalize || fail 'committed persistent update could not finalize the held overlay journal';;
            *) :;;
        esac
        stop_session || fail 'committed persistent update could not stop the retired session'
        put enabled 1 && put reason persistent-update-committed &&
            rm -f "$STATE/update-held" "$STATE/update-enabled" && sync || fail persistent-update-state
        echo 'boot: persistent /system update is verified; prior transient wrappers remain retired'
        exit 0
    fi
    lock || fail locked
    if [ ! -e "$STATE/update-held" ] && [ ! -L "$STATE/update-held" ]; then
        overlay_status=$(/system/bin/sh "$BASE/overlay.sh" status) || fail overlay-status
        case "$overlay_status" in *'state|committed'*) echo 'boot: update handoff was already restored'; exit 0;; *'state|retired'*) /system/bin/sh "$BASE/persistent-start.sh" verify >/dev/null 2>&1 && { echo 'boot: persistent update is already committed'; exit 0; };; esac
        fail update-not-held
    fi
    [ -f "$STATE/update-held" ] && [ ! -L "$STATE/update-held" ] || fail unsafe-update-state
    IFS='|' read -r held_boot held_enabled held_overlay held_runtime held_extra < "$STATE/update-held" || fail update-state
    [ -z "$held_extra" ] && [ "$held_boot" = "$(op boot)" ] || fail stale-update-state
    stop_session || fail 'owned session could not stop before restoring the held update view'
    if [ "$held_overlay" = committed ]; then
        overlay_status=$(/system/bin/sh "$BASE/overlay.sh" status) || fail overlay-status
        case "$overlay_status" in *'state|retired-pending'*) /system/bin/sh "$BASE/overlay.sh" retire-restore || fail 'held overlay could not be restored';; *'state|committed'*) :;; *) fail 'held overlay state is not safely restorable';; esac
    fi
    if [ "$held_runtime" = committed ]; then
        runtime_status=$(/system/bin/sh "$BASE/runtime.sh" status) || fail runtime-status
        case "$runtime_status" in 'runtime|disabled') /system/bin/sh "$BASE/runtime.sh" update-restore || fail 'held wrapper properties could not be restored';; 'runtime|committed') :;; *) fail 'held wrapper state is not safely restorable';; esac
    fi
    put enabled "$held_enabled" && put reason update-restored && rm -f "$STATE/update-held" "$STATE/update-enabled" && sync || fail update-state-cleanup
    echo 'boot: prior overlay view restored without restarting Android; next cold boot resumes prior startup policy'
    ;;
persistent-commit)
    [ "$#" = 0 ] || fail arguments
    lock || fail locked
    /system/bin/sh "$BASE/persistent-start.sh" verify >/dev/null || fail 'persistent payload and recovery manifest are not verified'
    put enabled 1 && put reason persistent-start-ready && sync || fail persistent-state
    echo 'boot: persistent startup enabled; no per-boot zygote restart is scheduled'
    ;;
transact|recover|recover-runtime)
    [ "${PORTABLE_BOOT_GUARDED:-}" = 1 ] || fail 'internal command requires native supervision'
    # The native supervisor has already armed its independent rescue process.
    print -r -- "$(op boot)" > "$STATE/maintenance" || fail maintenance
    previous_framework=$(op framework) || previous_framework=
    put framework-before "$previous_framework" || fail journal
    stage framework-stop || fail timeline
    op stop-android && wait_zygote stopped || fail 'framework stop failed'
    stage framework-stopped || fail timeline
    if [ "$command" = transact ]; then
        if [ "$(cat "$STATE/reconcile" 2>/dev/null)" = 1 ]; then
            op runtime-disable && op overlay-disable && select_plan || fail 'owned resume reconciliation failed'
            stage reconciled || fail timeline
        fi
        [ ! -f "$STATE/rescue-request" ] && ! op rescue-requested && enabled && verify_origins || fail 'activation identity failed'
        stage identity-verified || fail timeline
        if [ -s "$STATE/boot-manifest" ]; then
            # A running-framework prepare is reusable only for this boot and
            # this exact manifest. apply still revalidates every source while
            # stopped, immediately before the first bind.
            op plan-ready || op plan-boot || fail 'activation planning failed'
            stage overlay-planned || fail timeline
            op apply || fail 'activation apply failed'
            stage overlay-applied || fail timeline
        else
            op overlay-disable || fail 'empty plan restore failed'
            stage overlay-disabled || fail timeline
        fi
        enabled || fail 'activation cancelled'
        # QuickBoot can restore the same kernel boot_id while discarding wrap
        # properties. Retire the owned journal under stopped zygote first.
        op runtime-disable || fail 'previous runtime retirement failed'
        stage runtime-retired || fail timeline
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
        stage runtime-selected || fail timeline
    elif [ "$command" = recover-runtime ]; then
        op runtime-disable && static_plan && put runtime-mode static && put runtime-policy skip-until-rearm || fail 'runtime restore failed'
    else
        op runtime-disable && op overlay-disable || fail 'restore failed'
    fi
    stage framework-start || fail timeline
    op start-android && wait_zygote running || fail 'framework start failed'
    stage framework-running || fail timeline
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
    op rescue-requested && fail 'remove the rescue USB token before re-arm'
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
    reset_bounded > "$STATE/reset-baseline.new" && mv "$STATE/reset-baseline.new" "$STATE/reset-baseline" || fail 'kernel reset baseline unavailable'
    scan_bounded dropbox-names > "$STATE/dropbox-baseline.new" && mv "$STATE/dropbox-baseline.new" "$STATE/dropbox-baseline" || fail 'dropbox baseline unavailable'
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
    rm -f "$STATE/rescue-request" "$STATE/rescue-result" || fail 'rescue interlock retained'
    put retry-count 0 && put mode "$mode" && put consumed none || fail journal
    put runtime-policy full && put fingerprint "$(op get ro.build.fingerprint)" && put attempt "$(op boot)|armed" && put reason armed-next-boot && put enabled 1 || fail journal
    # The watcher writes rescue-request before enabled=0. Re-check after our
    # enabled=1 so a token inserted during arm can never be overruled.
    if [ -f "$STATE/rescue-request" ] || op rescue-requested; then backoff usb-rescue-requested; fail 'rescue USB inserted during arm; remains disabled'; fi
    sync || { backoff arm-sync-failed; exit 1; }
    echo 'boot: armed for the next boot; current Android retained'
    ;;
run|activate)
    [ "$#" = 0 ] || fail arguments
    if [ -f "$STATE/rescue-request" ] || op rescue-requested; then backoff usb-rescue-requested; exit 0; fi
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
    if [ "$previous" != "$current" ]; then
        reset_result=0; reset_check || reset_result=$?
        case "$reset_result" in 0) :;; 77) backoff reset-evidence; exit 1;; *) backoff reset-evidence-unreadable; exit 1;; esac
        cp "$STATE/reset-current" "$STATE/reset-baseline.new" && mv "$STATE/reset-baseline.new" "$STATE/reset-baseline" || { backoff reset-baseline-failed; exit 1; }
        dropbox=$(scan_bounded dropbox-scan) || { backoff dropbox-evidence-unreadable; exit 1; }
        case "$dropbox" in
        clean) :;;
        hit\|*) echo "boot: dropbox failure evidence ${dropbox#hit|}" >&2; backoff dropbox-failure-evidence; exit 1;;
        *) backoff dropbox-evidence-unreadable; exit 1;;
        esac
        cp "$STATE/dropbox-current" "$STATE/dropbox-baseline.new" && mv "$STATE/dropbox-baseline.new" "$STATE/dropbox-baseline" || { backoff dropbox-baseline-failed; exit 1; }
    fi
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
    if [ "$mode" = auto ] && [ "$active" = 0 ]; then
        # Persistent operation relies on the USB rescue watcher. NEMESIS stops
        # restarting a repeatedly failing service, so verify it before any
        # maintenance. Absence keeps this boot stock without a permanent latch.
        count=0; deadline 30
        until op rescue-alive; do
            count=$((count+1))
            [ "$count" -lt 30 ] && within || { put reason rescue-watch-unavailable && sync; echo 'boot: USB rescue watcher not running; this boot stays stock' >&2; exit 1; }
            op pause
        done
    fi
    if [ "$mode" = auto ] && [ "$(cat "$STATE/runtime-policy")" = full ]; then
        retries=$(cat "$STATE/retry-count") || { backoff retry-state-unreadable; exit 1; }
        case "$retries" in 0|1|2) :;; 3) backoff rapid-start-limit; exit 1;; *) backoff retry-state-invalid; exit 1;; esac
        put retry-count "$((retries+1))" || fail journal
    fi
    if [ "$active" = 0 ] && [ "$mode" != probe ] && [ "$(cat "$STATE/runtime-policy")" = full ]; then
        stage runtime-preflight-wait || fail timeline
        wait_initial_framework || { backoff initial-framework-unavailable; exit 1; }
        stage framework-initial-ready || fail timeline
        preflight_result=0
        # A successful ready poll can be followed by a transient busy Binder
        # query during stock startup. Retry only that distinct read-only status;
        # ABI rejection, seal errors and the stopped transaction stay strict.
        deadline 30
        while :; do
            preflight_result=0
            op runtime-preflight || preflight_result=$?
            [ "$preflight_result" = 75 ] || break
            enabled || exit 0
            within || { backoff runtime-preflight-failed; exit 1; }
            stage runtime-preflight-retry
            op pause
        done
        case "$preflight_result" in
        0) stage runtime-preflight || fail timeline;;
        77) stage runtime-preflight-unavailable || fail timeline;;
        *) backoff runtime-preflight-failed; exit 1;;
        esac
        if [ "$(cat "$STATE/reconcile")" = 0 ] && [ -s "$STATE/boot-manifest" ]; then
            op plan "$STATE/boot-manifest" || { backoff activation-prepare-failed; exit 1; }
            stage overlay-prepared-running || fail timeline
        fi
    fi
    put consumed "$current" && put attempt "$current|pending" && sync || fail journal
    stage maintenance-start || fail timeline
    if [ "$active" = 0 ] && ! bounded transact; then backoff maintenance-failed; exit 1; fi
    cancelled
    count=0; deadline "$FRAMEWORK_READY_SECONDS"
    while ! op framework-ready; do
        cancelled
        count=$((count+1)); [ "$count" -lt "$FRAMEWORK_READY_SECONDS" ] && within || { backoff boot-timeout; bounded recover; exit 1; }; op pause
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
    # am is a Binder client: ActivityManager can accept the request before the
    # bounded client returns. A timeout does not retract that accepted request.
    # Only a current-boot live hooked-process marker proves application readiness.
    launch_confirmed=1
    op launch-dipo || { launch_confirmed=0; stage dipo-start-request-unconfirmed; }
    count=0; deadline "$APP_READY_SECONDS"
    while ! op dipo-ready; do
        cancelled
        count=$((count+1))
        if [ "$count" -ge "$APP_READY_SECONDS" ] || ! within; then
            if [ "$launch_confirmed" = 0 ]; then
                backoff dipo-start-failed; bounded recover; exit 1
            fi
            bounded recover-runtime && finish_static || { backoff runtime-fallback-failed; bounded recover; exit 1; }
            exit 0
        fi
        op pause
    done
    cancelled
    # Session health performs a locked overlay status check immediately after
    # publishing readiness. Finish the initial commit before that reader exists;
    # otherwise its valid read lock can make commit fail on a healthy startup.
    # The boot attempt stays pending until the authored services are ready.
    op commit || { backoff commit-failed; bounded recover; exit 1; }
    op session & child=$!
    count=0; deadline "$SESSION_READY_SECONDS"
    while ! op session-ready; do
        cancelled
        count=$((count+1)); [ "$count" -lt "$SESSION_READY_SECONDS" ] && within && kill -0 "$child" 2>/dev/null || { backoff session-timeout; stop_session || fail 'session cleanup still busy'; bounded recover; exit 1; }; op pause
    done
    cancelled
    put attempt "$current|healthy" && put reason startup-healthy || { backoff commit-failed; stop_session || fail 'session cleanup still busy'; bounded recover; exit 1; }
    sync
    stage startup-healthy || fail timeline
    unlock
    trap 'op session-stop; exit 1' HUP INT TERM
    # A momentary healthy marker never forgives a sudden reset loop. Three
    # starts are allowed until a live session has been observed for five minutes.
    # This also bounds resets that leave neither a panic dump nor exit status.
    stable_seconds=300
    [ -z "$ROOT" ] || stable_seconds=${PORTABLE_TEST_STABLE_SECONDS:-300}
    stable_start=$(clock)
    while kill -0 "$child" 2>/dev/null; do
        if [ "$(( $(clock)-stable_start ))" -ge "$stable_seconds" ]; then
            if enabled && op session-ready && op framework-ready && op dipo-ready; then
                put retry-count 0 && sync || { backoff stability-sync-failed; break; }
                stage continuous-session-stable
            fi
            break
        fi
        op pause
    done
    wait "$child"; result=$?
    if enabled; then
        put attempt "$current|degraded" && put reason session-ended-confirming && sync || { op session-stop; backoff journal-failed-after-session; exit 1; }
        op session-stop
        # Ignition off may stop DiPO/host before power is cut. Latch only when
        # Android stays up and is not shutting down for a bounded grace period;
        # otherwise leave operation armed (the start budget bounds repeats).
        # Retain the current view while driving: no framework restart here.
        grace=60; [ -z "$ROOT" ] || grace=${PORTABLE_TEST_LOSS_GRACE:-60}
        grace_start=$(clock); shutting=0
        while [ "$(( $(clock)-grace_start ))" -lt "$grace" ]; do
            if [ -n "$(op get sys.powerctl)" ] || [ "$(op get init.svc.zygote)" != running ]; then shutting=1; break; fi
            enabled || break
            op pause
        done
        if [ "$shutting" = 1 ]; then
            put reason session-ended-at-shutdown && sync
        elif enabled; then
            backoff session-ended-latched
        fi
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
*) fail 'usage: boot.sh arm [--trial] MANIFEST | probe MANIFEST | run | activate | update-retire | update-restore | persistent-commit | disable | status';;
esac
