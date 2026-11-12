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
fail() { echo "session: $*" >&2; exit 1; }
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
for file in stop owner epoch ready; do [ ! -L "$STATE/$file" ] || fail 'unsafe state'; done
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
op() {
    if [ -n "$ROOT" ]; then "$ADAPTER" "$@"; return $?; fi
    case "$1" in
    boot) cat /proc/sys/kernel/random/boot_id;;
    ready)
        [ "$(getprop sys.boot_completed)" = 1 ] && [ "$(getprop init.svc.zygote)" = running ] || return 1
        overlay=$(/system/bin/sh "$BASE/overlay.sh" status) && has_feature bt && has_feature projection || return 1
        runtime=$(/system/bin/sh "$BASE/runtime.sh" status) || return 1
        case "$runtime" in 'runtime|pending'|'runtime|committed') :;; *) return 1;; esac
        dipo_ready;;
    busy)
        grep -q 'gen5wkr.ap.broker.v1' /proc/net/unix 2>/dev/null && return 0
        for process in /proc/[0-9]*/cmdline; do
            if grep -aq '^kr.gen5w.core' "$process" 2>/dev/null || grep -aq '^kr.gen5w.wirelesshost' "$process" 2>/dev/null; then return 0; fi
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
    broker) exec "$NEM" root 1000 -c "CLASSPATH=$BASE/app/bridge.dex:/system/framework/com.tcc.iap2.jar exec /system/bin/app_process /system/bin kr.gen5w.hotspot.ApBroker $SUPERVISOR";;
    owner) exec "$NEM" root 1000 -c "CLASSPATH=$BASE/app/gen5w-core.apk:$BASE/dalvik/engine.jar exec /system/bin/app_process /system/bin kr.gen5w.portable.OwnerSupervisor $SUPERVISOR";;
    start-host) am startservice -n kr.gen5w.wirelesshost/kr.gen5w.wireless.BridgeHostService --ez relay_v039 true;;
    start-core) am startservice -n kr.gen5w.core/.CoreService;;
    stop-host) am stopservice -n kr.gen5w.wirelesshost/kr.gen5w.wireless.BridgeHostService
        # Relay shutdown drains a bounded 20-second AP cleanup queue. Keep the
        # root broker alive until that queue has had time to finish.
        sleep 22
        am force-stop kr.gen5w.wirelesshost;;
    stop-core) am stopservice -n kr.gen5w.core/.CoreService; am force-stop kr.gen5w.core;;
    host-ready)
        local marker=/data/data/kr.gen5w.wirelesshost/files/bridge-ready pid boot start extra
        plain "$marker" && [ -f "$marker" ] || return 1
        { read -r pid; read -r boot; read -r start; read -r extra && return 1; } < "$marker"
        [ "$boot" = "boot_id=$(op boot)" ] || return 1
        start=${start#starttime=}
        case "$start" in ''|*[!0-9]*) return 1;; esac
        [ "$(process_key "$pid" 2>/dev/null)" = "$pid:$start" ] || return 1
        case "$pid" in ''|*[!0-9]*) return 1;; esac
        grep -aq '^kr.gen5w.wirelesshost' "/proc/$pid/cmdline" 2>/dev/null;;
    pause) sleep 1;;
    *) return 1;;
    esac
}
case "$1" in
ready) op ready;;
busy) op busy;;
install-apps)
    fail 'use the complete NEMESIS portability package; direct pm install may trigger an HMG reboot'
    ;;
run)
    op ready || fail 'active bt/projection overlays, runtime and current DiPO adapter marker required'
    op busy && fail 'existing host/core/AP session retained; stop it through its owning installation first'
    for name in app/bridge.dex app/wireless-host.apk app/gen5w-core.apk dalvik/engine.jar; do plain "$BASE/$name" && [ -f "$BASE/$name" ] || fail 'runtime payload missing'; done
    if ! mkdir "$STATE/lock" 2>/dev/null; then
        [ ! -L "$STATE/lock" ] && [ -f "$STATE/epoch" ] || fail 'malformed session lock'
        IFS='|' read -r saved_boot saved_key < "$STATE/epoch"
        if [ "$saved_boot" = "$(op boot)" ] && [ "$(process_key "${saved_key%%:*}" 2>/dev/null)" = "$saved_key" ]; then fail 'session already active'; fi
        rmdir "$STATE/lock" && mkdir "$STATE/lock" || fail 'cannot recover dead session lock'
    fi
    parent_key=$(process_key "$PPID") || fail 'supervisor parent unavailable'
    [ "$PPID" -gt 1 ] || fail 'orphaned supervisor'
    SUPERVISOR=$$; export SUPERVISOR
    epoch="$(op boot)|$(process_key $$)"
    print -r -- "$epoch" > "$STATE/epoch" || fail epoch
    print -r -- "$$" > "$STATE/owner" || fail 'owner journal failed'
    rm -f "$STATE/stop" || fail 'stop marker unavailable'
    host=0; core=0; wireless_denied=0
    cleanup() {
        [ "$host" = 0 ] || op stop-host >/dev/null 2>&1
        [ "$core" = 0 ] || op stop-core >/dev/null 2>&1
        # Child workers watch their actual parent; no stale PID is signalled.
        rm -f "$STATE/ready" "$STATE/epoch" "$STATE/owner"; rmdir "$STATE/lock" 2>/dev/null
    }
    trap cleanup EXIT
    trap 'exit 1' HUP INT TERM
    op broker & broker=$!
    op owner & owner=$!
    core=1; op start-core || fail 'HUD start failed'
    count=0
    while ! op broker-ready; do
        count=$((count+1)); [ "$count" -lt 10 ] || fail 'AP broker readiness timeout'; op pause
    done
    start_host() {
        [ "$wireless_denied" = 0 ] || return 0
        op wireless-admit || { wireless_denied=1; return 0; }
        host=1; op start-host || fail 'host start failed'
        count=0
        while ! op host-ready; do count=$((count+1)); [ "$count" -lt 10 ] || fail 'host readiness timeout'; op pause; done
    }
    op wireless-enabled && start_host
    print -r -- "$epoch" > "$STATE/ready" || fail readiness
    echo 'session: AP/HUD supervisor running; vehicle connection and display unverified'
    while [ ! -f "$STATE/stop" ]; do
        [ "$(process_key "$PPID" 2>/dev/null)" = "$parent_key" ] || fail 'supervisor parent exited'
        if op wireless-enabled; then
            if [ "$host" = 0 ]; then start_host; else op host-ready || fail 'host exited; automatic retries disabled'; fi
        else
            wireless_denied=0
            if [ "$host" = 1 ]; then op stop-host || fail 'host shutdown failed'; host=0; fi
        fi
        kill -0 "$broker" 2>/dev/null && kill -0 "$owner" 2>/dev/null || fail 'owned worker exited'
        op pause
    done
    ;;
stop)
    : > "$STATE/stop" || fail 'cannot request foreground stop'
    # SIGKILL bypasses the supervisor's EXIT trap. Only a current-boot owned
    # epoch authorizes cleaning up our exclusively installed app services.
    if [ -f "$STATE/epoch" ] && ! current_session; then
        IFS='|' read -r saved_boot saved_key < "$STATE/epoch"
        if [ "$saved_boot" = "$(op boot)" ] && [ "$(process_key "${saved_key%%:*}" 2>/dev/null)" != "$saved_key" ]; then
            op stop-host && op stop-core || fail 'orphaned authored service cleanup failed'
            rm -f "$STATE/ready" "$STATE/epoch" "$STATE/owner"
            [ ! -d "$STATE/lock" ] || rmdir "$STATE/lock" || fail 'orphaned lock retained'
        fi
    fi
    ;;
status)
    if current_session; then echo 'session|running'; else echo 'session|stopped'; fi;;
*) fail 'usage: session.sh install-apps | run | stop | status';;
esac
