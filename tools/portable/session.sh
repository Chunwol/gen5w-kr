#!/system/bin/sh
# Foreground session worker; boot.sh owns startup, shutdown and recovery.
umask 077
BASE=${0%/*}; [ "$BASE" != "$0" ] || BASE=.
BASE=$(CDPATH= cd -- "$BASE" && pwd) || exit 1
ROOT=${PORTABLE_TEST_ROOT:-}
ADAPTER=${PORTABLE_TEST_SESSION_ADAPTER:-}
STATE=/data/local/gen5w-portable/session
NEM=/system/xbin/nemesis
export PORTABLE_HELPER=$BASE/bin/dex-patch
safe() { case "$1" in ''|*[!a-zA-Z0-9_./-]*|*/../*|*/./*|*/..|*/.|*//*) return 1;; esac; }
plain() {
    safe "$1" || return 1
    case "$1" in /*) :;; *) return 1;; esac
    local p=$1
    while [ "$p" != / ] && [ -n "$p" ]; do [ ! -L "$p" ] || return 1; p=${p%/*}; [ -n "$p" ] || p=/; done
}
monitoring=0
fail() {
    # Persist evidence before the potentially blocking Android service cleanup
    # EXIT trap. Ignition off may stop DiPO/host before power is cut, so the
    # root controller decides whether to latch after confirming Android stays
    # up. If the controller itself is gone, its start budget bounds retries.
    if [ "$monitoring" = 1 ]; then
        local journal=$ROOT/data/local/gen5w-portable/boot
        if plain "$journal" && [ -d "$journal" ] && plain "$journal/health-lost" && plain "$journal/health-lost.new"; then
            print -r -- "$(cat /proc/sys/kernel/random/boot_id 2>/dev/null)|$*" > "$journal/health-lost.new" && mv "$journal/health-lost.new" "$journal/health-lost"
            sync
            if [ -z "$ROOT" ] && [ -f "$BASE/diagnostics.sh" ]; then
                PORTABLE_DIAG_BROKER_PID=$broker PORTABLE_DIAG_OWNER_PID=$owner \
                    "$BASE/bin/dex-patch" supervise 20 /system/bin/true /system/bin/sh "$BASE/diagnostics.sh" capture "$*" || :
            fi
        fi
    fi
    echo "session: $*" >&2; exit 1
}
if [ -n "$ROOT" ]; then
    plain "$ROOT" && [ "$ROOT" != / ] && [ -d "$ROOT" ] && [ -x "$ADAPTER" ] || fail 'invalid fixture'
    case "$BASE" in "$ROOT"/data/*) :;; *) fail 'fixture bundle outside data';; esac
else
    case "$(id)" in uid=0\(*) :;; *) fail "run the supervisor as root, without a daemon forwarding layer";; esac
    [ -z "$ADAPTER" ] || fail 'adapter outside fixture'
    case "$BASE" in /data/*) :;; *) fail 'bundle outside data';; esac
fi
plain "$BASE" && plain "$ROOT$STATE" || fail 'unsafe path'
STATE=$ROOT$STATE
mkdir -p "$STATE" && chmod 700 "$STATE" || fail 'state unavailable'
for file in stop owner epoch ready worker-broker.log worker-owner.log workers; do [ ! -L "$STATE/$file" ] || fail 'unsafe state'; done
process_key() {
    local pid=$1 line rest count=0
    case "$pid" in ''|*[!0-9]*) return 1;; esac
    IFS= read -r line < "/proc/$pid/stat" || return 1
    rest=${line##*) }; [ "$rest" != "$line" ] || return 1
    set -- $rest; [ "$#" -ge 20 ] || return 1
    case "$1" in Z|X|x) return 1;; esac
    while [ "$count" -lt 19 ]; do shift; count=$((count+1)); done
    print -r -- "$pid:$1"
}
check_worker() {
    local role=$1 pid=$2 result=0
    process_key "$pid" >/dev/null 2>&1 && return 0
    wait "$pid" || result=$?
    fail "owned worker exited worker=$role pid=$pid exit=$result"
}
current_session() {
    local boot epoch
    [ -f "$STATE/epoch" ] && [ -f "$STATE/ready" ] || return 1
    IFS='|' read -r boot epoch < "$STATE/epoch" || return 1
    [ "$boot" = "$(op boot)" ] && [ "$(process_key "${epoch%%:*}" 2>/dev/null)" = "$epoch" ] && [ "$(cat "$STATE/ready")" = "$boot|$epoch" ]
}
has_feature() {
    local feature flag
    while IFS='|' read -r feature flag; do [ "$feature:$flag" != "$1:active" ] || return 0; done <<EOF
$overlay
EOF
    return 1
}
dipo_ready() {
    local file=/data/data/com.daudio.app.dipo/files/gen5w-portable-ready boot pid package extra
    plain "$file" && [ -f "$file" ] || return 1
    { read -r boot; read -r pid; read -r package; read -r extra && return 1; } < "$file"
    [ "$boot" = "boot_id=$(cat /proc/sys/kernel/random/boot_id)" ] && [ "$package" = package=com.daudio.app.dipo ] || return 1
    pid=${pid#pid=}; case "$pid" in ''|*[!0-9]*) return 1;; esac
    [ "$pid" -gt 1 ] && grep -aq '^com.daudio.app.dipo' "/proc/$pid/cmdline" 2>/dev/null && grep -q 'libgen5whook.so' "/proc/$pid/maps" 2>/dev/null
}
service_command() {
    local seconds=$1; shift
    # `am` boots a Dalvik VM: run it at normal priority, not the services' nice 10.
    ( normal_priority; exec "$BASE/bin/dex-patch" supervise "$seconds" /system/bin/true /system/bin/am "$@" )
}
normal_priority() { # this (sub)shell: /proc/self is opened by the builtin read
    local me rest
    IFS=' ' read -r me rest < /proc/self/stat 2>/dev/null && renice 0 "$me" >/dev/null 2>&1
    return 0
}
op() {
    if [ -n "$ROOT" ]; then "$ADAPTER" "$@"; return $?; fi
    case "$1" in
    # Builtin read: the supervisor checks this every second (no exec per check).
    boot) local id; IFS= read -r id < /proc/sys/kernel/random/boot_id && print -r -- "$id";;
    adapter-ready)
        [ "$(getprop sys.boot_completed)" = 1 ] && [ "$(getprop init.svc.zygote)" = running ] && dipo_ready;;
    ready)
        [ "$(getprop sys.boot_completed)" = 1 ] && [ "$(getprop init.svc.zygote)" = running ] || return 1
        if [ "${GEN5W_PERSISTENT:-0}" = 1 ]; then
            plain /data/local/gen5w-portable/persistent/manifest && [ -f /data/local/gen5w-portable/persistent/manifest ] &&
                plain /data/local/gen5w-portable/persistent/recovery/manifest && [ -f /data/local/gen5w-portable/persistent/recovery/manifest ] || return 1
        else
            overlay=$(/system/bin/sh "$BASE/overlay.sh" status) && has_feature bt && has_feature projection || return 1
            runtime=$(/system/bin/sh "$BASE/runtime.sh" status) || return 1
            case "$runtime" in 'runtime|pending'|'runtime|committed') :;; *) return 1;; esac
        fi
        dipo_ready;;
    busy)
        grep -q 'gen5wkr.ap.broker.v1' /proc/net/unix 2>/dev/null && return 0
        local command
        for process in /proc/[0-9]*/cmdline; do
            IFS= read -r -d '' command 2>/dev/null < "$process" || continue
            case "$command" in kr.gen5w.core*|kr.gen5w.wirelesshost*) return 0;; esac
        done
        return 1;;
    broker-ready) grep -q 'gen5wkr.ap.broker.v1' /proc/net/unix 2>/dev/null;;
    wireless-enabled)
        local flag
        for flag in /data/nemesis/gen5wkr.ui-wireless-off /data/nemesis/gen5wkr.wireless-disabled /data/nemesis/gen5wkr.apguard.off; do
            plain "$flag" && [ ! -e "$flag" ] || return 1
        done;;
    wireless-admit) /system/bin/sh "$BASE/ap.sh" check;;
    installed) pm path "$2" | grep -q '^package:';;
    install) pm install -r "$2";;
    # The service scripts run at nice 10; the AP broker and owner VMs serve the
    # live phone connection, so they get normal priority back (root may raise).
    broker) normal_priority; exec "$NEM" root 1000 -c "CLASSPATH=$BASE/app/bridge.dex:/system/framework/com.tcc.iap2.jar exec /system/bin/app_process /system/bin kr.gen5w.hotspot.ApBroker $SUPERVISOR";;
    owner) normal_priority; exec "$NEM" root 1000 -c "CLASSPATH=$BASE/app/gen5w-core.apk:$BASE/dalvik/engine.jar exec /system/bin/app_process /system/bin kr.gen5w.portable.OwnerSupervisor $SUPERVISOR";;
    start-host) service_command 30 startservice -n kr.gen5w.wirelesshost/kr.gen5w.wireless.BridgeHostService --ez relay_v039 true;;
    start-core) service_command 30 startservice -n kr.gen5w.core/.CoreService;;
    stop-host) service_command 10 stopservice -n kr.gen5w.wirelesshost/kr.gen5w.wireless.BridgeHostService
        # Relay shutdown drains a bounded 20-second AP cleanup queue. Keep the
        # root broker alive until that queue has had time to finish.
        sleep 22
        service_command 10 force-stop kr.gen5w.wirelesshost;;
    stop-core) service_command 10 stopservice -n kr.gen5w.core/.CoreService; service_command 10 force-stop kr.gen5w.core;;
    host-ready)
        local marker=/data/data/kr.gen5w.wirelesshost/files/bridge-ready pid boot start extra
        plain "$marker" && [ -f "$marker" ] || return 1
        { read -r pid; read -r boot; read -r start; read -r extra && return 1; } < "$marker"
        [ "$boot" = "boot_id=$(op boot)" ] || return 1
        start=${start#starttime=}
        case "$start" in ''|*[!0-9]*) return 1;; esac
        [ "$(process_key "$pid" 2>/dev/null)" = "$pid:$start" ] || return 1
        case "$pid" in ''|*[!0-9]*) return 1;; esac
        IFS= read -r -d '' extra 2>/dev/null < "/proc/$pid/cmdline" || return 1
        case "$extra" in kr.gen5w.wirelesshost*) return 0;; *) return 1;; esac;;
    pause) sleep 1;;
    *) return 1;;
    esac
}
case "$1" in
ready|adapter-ready) op "$1";;
busy) op busy;;
install-apps)
    fail 'use the complete NEMESIS portability package; direct pm install may trigger an HMG reboot'
    ;;
run)
    op ready || fail 'active bt/projection overlays, runtime and current DiPO adapter marker required'
    op busy && fail 'existing host/core/AP session retained; stop it through its owning installation first'
    for name in app/bridge.dex app/wireless-host.apk app/gen5w-core.apk dalvik/engine.jar; do plain "$BASE/$name" && [ -f "$BASE/$name" ] || fail 'runtime payload missing'; done
    # Publish an already-owned directory. An empty legacy lock can be removed
    # atomically; a concurrently published claim is nonempty and cannot be lost.
    session_epoch="$(op boot)|$(process_key $$)"
    claim="$STATE/lock.claim.$$.${session_epoch##*:}"
    plain "$claim" && mkdir "$claim" || fail 'cannot stage session lock'
    print -r -- "$session_epoch" > "$claim/owner" || {
        rmdir "$claim" 2>/dev/null; fail 'cannot stage session owner'
    }
    stale_owner() {
        local saved_boot saved_key extra
        [ ! -L owner ] && [ -f owner ] || return 1
        IFS='|' read -r saved_boot saved_key extra < owner || return 1
        [ -z "$extra" ] || return 1
        case "$saved_key" in *[!0-9:]*|:*|*:|*:*:*) return 1;; esac
        case "$saved_key" in *:*) :;; *) return 1;; esac
        [ "$saved_boot" != "$(op boot)" ] ||
            [ "$(process_key "${saved_key%%:*}" 2>/dev/null)" != "$saved_key" ]
    }
    reclaim_lock() (
        plain "$STATE/lock" && cd "$STATE/lock" || exit 1
        # Anchor every removal to this directory, never a later replacement.
        if [ -e owner ] || [ -L owner ]; then
            stale_owner && rm owner || exit 1
        elif [ -f "$STATE/epoch" ]; then
            IFS='|' read -r saved_boot saved_key < "$STATE/epoch"
            if [ "$saved_boot" = "$(op boot)" ] &&
               [ "$(process_key "${saved_key%%:*}" 2>/dev/null)" = "$saved_key" ]; then exit 1; fi
        fi
        for nested in lock.claim.*; do
            [ -e "$nested" ] || { [ ! -L "$nested" ] || exit 1; continue; }
            [ -d "$nested" ] && [ ! -L "$nested" ] || exit 1
            ( cd "$nested" && stale_owner && rm owner ) && rmdir "$nested" || exit 1
        done
        rmdir "$STATE/lock"
    )
    acquired=0; tries=0
    while [ "$tries" -lt 4 ]; do
        tries=$((tries+1))
        plain "$STATE/lock" && { [ ! -e "$STATE/lock" ] || [ -d "$STATE/lock" ]; } || break
        if ! mv "$claim" "$STATE/lock" 2>/dev/null; then break; fi
        nested="$STATE/lock/${claim##*/}"
        if [ -d "$nested" ] && [ ! -L "$nested" ]; then
            # A live published owner always wins, even before epoch/ready exist.
            mv "$nested" "$claim" || break
            reclaim_lock 2>/dev/null || break
        elif [ ! -L "$STATE/lock/owner" ] &&
             [ "$(cat "$STATE/lock/owner" 2>/dev/null)" = "$session_epoch" ]; then
            acquired=1; break
        else break; fi
    done
    if [ "$acquired" != 1 ]; then
        rm -f "$claim/owner"; rmdir "$claim" 2>/dev/null
        fail 'session already active or lock recovery unavailable'
    fi
    release_lock() (
        cd "$STATE/lock" 2>/dev/null || exit 0
        [ ! -L owner ] && [ "$(cat owner 2>/dev/null)" = "$session_epoch" ] || exit 1
        rm owner && rmdir "$STATE/lock"
    )
    # Install cleanup before writing journals or querying the parent.
    trap 'release_lock' EXIT
    parent_key=$(process_key "$PPID") || fail 'supervisor parent unavailable'
    [ "$PPID" -gt 1 ] || fail 'orphaned supervisor'
    SUPERVISOR=$$; export SUPERVISOR
    epoch="$session_epoch"
    print -r -- "$epoch" > "$STATE/epoch" || fail epoch
    print -r -- "$$" > "$STATE/owner" || fail 'owner journal failed'
    rm -f "$STATE/stop" || fail 'stop marker unavailable'
    host=0; core=0; wireless_denied=0
    cleanup() {
        local cleanup_result=0
        [ "$host" = 0 ] || op stop-host >/dev/null 2>&1 || cleanup_result=1
        [ "$core" = 0 ] || op stop-core >/dev/null 2>&1 || cleanup_result=1
        # Child workers watch their actual parent; no stale PID is signalled.
        [ "$cleanup_result" = 0 ] || { echo 'session: cleanup incomplete; ownership retained' >&2; return 1; }
        rm -f "$STATE/ready" "$STATE/epoch" "$STATE/owner"; release_lock
    }
    trap cleanup EXIT
    trap 'exit 1' HUP INT TERM
    startup_allowed() {
        [ ! -f "$STATE/stop" ] && [ "$(process_key "$PPID" 2>/dev/null)" = "$parent_key" ] || fail 'startup cancelled'
    }
    startup_allowed
    op broker > "$STATE/worker-broker.log" 2>&1 & broker=$!
    op owner > "$STATE/worker-owner.log" 2>&1 & owner=$!
    print -r -- "$(op boot)|broker=$broker|owner=$owner" > "$STATE/workers"
    startup_allowed
    core=1; op start-core || fail 'HUD start failed'
    startup_allowed
    count=0
    while ! op broker-ready; do
        startup_allowed
        count=$((count+1)); [ "$count" -lt 10 ] || fail 'AP broker readiness timeout'; op pause
    done
    start_host() {
        startup_allowed
        [ "$wireless_denied" = 0 ] || return 0
        op wireless-admit || { wireless_denied=1; return 0; }
        host=1; op start-host || fail 'host start failed'
        startup_allowed
        count=0
        # Match boot.sh's existing 90-second session admission budget. Android
        # accepts startservice before onStartCommand finishes; the former ten
        # polls could abort a live initializing host. The parent deadline and
        # cancellation remain authoritative; this also bounds standalone runs.
        while ! op host-ready; do startup_allowed; count=$((count+1)); [ "$count" -lt 90 ] || fail 'host readiness timeout'; op pause; done
    }
    op wireless-enabled && start_host
    startup_allowed
    print -r -- "$epoch" > "$STATE/ready" || fail readiness
    echo 'session: AP/HUD supervisor running; vehicle connection and display unverified'
    owner_restarts=0
    owner_alive_ticks=0
    owner_cooldown=0
    check_owner_worker() {
        local result=0
        if [ "$owner" = 0 ]; then
            if [ "$owner_cooldown" -gt 0 ]; then
                owner_cooldown=$((owner_cooldown - 1))
                if [ "$owner_cooldown" -eq 0 ]; then
                    owner_restarts=0
                    owner_alive_ticks=0
                    op owner >> "$STATE/worker-owner.log" 2>&1 & owner=$!
                    print -r -- "$(op boot)|broker=$broker|owner=$owner" > "$STATE/workers"
                fi
            fi
            return 0
        fi
        [ -n "$owner" ] || return 0
        if process_key "$owner" >/dev/null 2>&1; then
            owner_alive_ticks=$((owner_alive_ticks + 1))
            if [ "$owner_alive_ticks" -ge 120 ] && [ "$owner_restarts" -gt 0 ]; then
                owner_restarts=0
            fi
            return 0
        fi
        wait "$owner" || result=$?
        owner_alive_ticks=0
        echo "session: HUD owner worker exited pid=$owner exit=$result" >&2
        if [ "$owner_restarts" -lt 5 ]; then
            owner_restarts=$((owner_restarts + 1))
            op owner >> "$STATE/worker-owner.log" 2>&1 & owner=$!
            print -r -- "$(op boot)|broker=$broker|owner=$owner" > "$STATE/workers"
        else
            owner=0
            owner_cooldown=30
            echo 'session: HUD owner worker paused after retries; wireless session kept' >&2
        fi
    }
    monitoring=1
    health_tick=0
    while [ ! -f "$STATE/stop" ]; do
        # Check loaded DiPO/runtime view even when the host process stays alive.
        # No in-drive framework restart: fail only stops our services and latches.
        if [ "$health_tick" = 0 ]; then op ready || fail 'runtime health lost'; fi
        health_tick=$(((health_tick+1)%10))
        [ "$(process_key "$PPID" 2>/dev/null)" = "$parent_key" ] || fail 'supervisor parent exited'
        if op wireless-enabled; then
            if [ "$host" = 0 ]; then start_host; else op host-ready || fail 'host exited; automatic retries disabled'; fi
        else
            wireless_denied=0
            if [ "$host" = 1 ]; then op stop-host || fail 'host shutdown failed'; host=0; fi
        fi
        check_worker broker "$broker"
        check_owner_worker
        op pause
    done
    ;;
stop|stop-maintenance)
    : > "$STATE/stop" || fail 'cannot request foreground stop'
    # SIGKILL bypasses the supervisor's EXIT trap. Only a current-boot owned
    # epoch authorizes cleaning up our exclusively installed app services.
    if [ -f "$STATE/epoch" ] && ! current_session; then
        IFS='|' read -r saved_boot saved_key < "$STATE/epoch"
        if [ "$saved_boot" = "$(op boot)" ] && [ "$(process_key "${saved_key%%:*}" 2>/dev/null)" != "$saved_key" ]; then
            op stop-host && op stop-core || fail 'orphaned authored service cleanup failed'
            rm -f "$STATE/ready" "$STATE/epoch" "$STATE/owner"
            if [ -d "$STATE/lock" ]; then
                ( cd "$STATE/lock" && [ ! -L owner ] &&
                  { [ ! -e owner ] || { [ "$(cat owner)" = "$saved_boot|$saved_key" ] && rm owner; }; } &&
                  rmdir "$STATE/lock" ) || fail 'orphaned lock retained'
            fi
        fi
    fi
    # Explicit package maintenance owns these exclusively installed APKs even
    # when only Manager was opened and no foreground session epoch exists.
    # Never interfere with a published/current starter: its stop marker and
    # EXIT trap perform the cleanup instead. Ordinary stop keeps its stricter
    # no-takeover boundary.
    if [ "$1" = stop-maintenance ] && [ ! -e "$STATE/lock" ] && ! current_session; then
        op stop-host && op stop-core || fail 'idle authored app cleanup failed'
    fi
    ;;
status)
    if current_session; then echo 'session|running'; else echo 'session|stopped'; fi;;
*) fail 'usage: session.sh install-apps | run | stop | status';;
esac
