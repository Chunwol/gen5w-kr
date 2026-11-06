#!/system/bin/sh
# Root NEMESIS supervisor, system-uid Java daemon; no transport-content logging.
SCRIPT_DIR=${0%/*}
[ "$SCRIPT_DIR" != "$0" ] || SCRIPT_DIR=.
SERVICE_DIR=$(cd "$SCRIPT_DIR/.." && pwd) || exit 1
DATA=${BRIDGE_TEST_DATA:-/data}
# --- boot-loop safety net: count this boot attempt; if the unit has failed to
# reach sys.boot_completed more than the installer-armed limit, restore stock and
# cold-boot. Runs before any bridge-specific check so a patch that broke the
# bridge still gets recovered. Skipped under the mock harness (BRIDGE_TEST_SYS).
_bg=$DATA/nemesis/gen5wkr.bootguard
if [ ! -e "$_bg" ] && [ ! -L "$_bg" ] && [ -d "$_bg.previous" ] && [ ! -L "$_bg.previous" ]; then
    _bg=$_bg.previous
fi
_bg_state=$SERVICE_DIR/scripts/bootguard-state.sh
if [ -z "$BRIDGE_TEST_SYS" ] && [ -f "$_bg/recovery-required" ]; then
    exit 1
fi
if [ -z "$BRIDGE_TEST_SYS" ] && [ -d "$_bg" ] && [ ! -f "$_bg/recovered" ]; then
    [ -f "$_bg_state" ] && [ ! -L "$_bg_state" ] || exit 1
    _boot_id=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null)
    _bg_rc=0
    BOOTGUARD_STATE_DIR="$_bg" BOOTGUARD_BOOT_ID="$_boot_id" \
        /system/bin/sh "$_bg_state" begin || _bg_rc=$?
    if [ "$_bg_rc" -eq 2 ] && [ -f "$SCRIPT_DIR/bootguard-recover.sh" ] && [ ! -L "$SCRIPT_DIR/bootguard-recover.sh" ]; then
        /system/bin/sh "$SCRIPT_DIR/bootguard-recover.sh"
        exit $?
    fi
    [ "$_bg_rc" -eq 0 ] || exit 1
fi
. "$SERVICE_DIR/scripts/common.sh"
. "$SERVICE_DIR/scripts/retry-state.sh"
inspect; _inspect_rc=$?
[ "$_inspect_rc" = 0 ] || { echo "FAIL bridge: inspect rc=$_inspect_rc; service not started"; exit "$_inspect_rc"; }
{ [ "$BRIDGE_STATE" = route-patched ] || [ "$BRIDGE_STATE" = bt-patched ]; } &&
    { [ "$DIPO_STATE" = patched ] || [ "$DIPO_STATE" = relay ]; } &&
    [ "$BRIDGE_OWNED" = yes ] || {
        echo "FAIL bridge: files are not in an installed state (iAP2=$BRIDGE_STATE DiPO=$DIPO_STATE owned=$BRIDGE_OWNED); service not started"
        exit 1
    }
DATA=${BRIDGE_TEST_DATA:-/data}
NEM=${BRIDGE_TEST_NEM:-/system/xbin/nemesis}
STOPPING=$DATA/nemesis/gen5wkr.bridge.stopping
DEX=$SERVICE_DIR/app/bridge.dex
AP_MATCH=$DATA/nemesis/gen5wkr.ap-match
RELAY_GATE=$SERVICE_DIR/scripts/relay-gate.sh
# Runtime restart guard. The OEM PhoneProjection stack owns Wi-Fi/AP setup; this
# supervisor only starts the app-side request/observation service.
APG_MAX=3
apguard_boot() {
    for _p in "$APG" "$APG_COUNT" "$APG_OFF" "$APG/attempt" "$APG/ok"; do [ ! -L "$_p" ] || return 1; done
    if [ ! -d "$APG" ]; then [ ! -e "$APG" ] && mkdir "$APG" || return 1; fi
    if [ -z "$BRIDGE_TEST_SYS" ]; then
        chown 1000:1000 "$APG" 2>/dev/null || chown 1000.1000 "$APG" || return 1
    fi
    chmod 700 "$APG" || return 1
    _apg_boot=${BRIDGE_TEST_BOOT_ID:-$(cat /proc/sys/kernel/random/boot_id 2>/dev/null)}
    _n=$(cat "$APG_COUNT" 2>/dev/null)
    case "$_n" in ''|*[!0-9]*) _n=0;; esac
    if [ -f "$APG/ok" ]; then _n=0; rm -f "$APG/ok"; fi
    if [ -f "$APG/attempt" ] && [ -n "$_apg_boot" ] && [ "$(cat "$APG/attempt" 2>/dev/null)" != "$_apg_boot" ]; then
        _n=$((_n + 1)); rm -f "$APG/attempt"
    fi
    echo "$_n" > "$APG_COUNT" || return 1
    [ "$_n" -lt "$APG_MAX" ] || echo off > "$APG_OFF" || return 1
    return 0
}
case "$DEX" in *[!a-zA-Z0-9_./-]*) echo 'FAIL bridge: unsupported package path'; exit 1;; esac
[ -f "$DEX" ] && [ ! -L "$DEX" ] && [ -x "$NEM" ] || exit 1
trap 'exit 0' HUP INT TERM
while [ ! -f "$STOPPING" ]; do
    if [ "$(getprop sys.boot_completed)" = 1 ]; then
        # Boot reached completion: reset this boot's consecutive-failure count,
        # but keep the guard armed for a later ignition-cycle failure.
        if [ -z "$BRIDGE_TEST_SYS" ] && [ -d "$_bg" ] && [ ! -L "$_bg" ]; then
            [ -f "$_bg_state" ] && [ ! -L "$_bg_state" ] || exit 1
            BOOTGUARD_STATE_DIR="$_bg" BOOTGUARD_BOOT_ID="$_boot_id" \
                /system/bin/sh "$_bg_state" mark-ok || exit 1
        fi
        break
    fi
    sleep 2
done
# Wireless runs only on a working guard; if it cannot be kept, stay wired-only.
apguard_boot || { echo 'FAIL bridge: restart guard unusable; staying wired-only'; [ -n "$BRIDGE_TEST_ONCE" ] && exit 0; while [ ! -f "$STOPPING" ]; do sleep 2; done; exit 0; }
host_started=no
broker_pid=
# One line each time the reason for waiting changes, so the log explains a silent supervisor.
LAST_NOTE=
note() { [ "$LAST_NOTE" = "$1" ] || { LAST_NOTE=$1; echo "WAIT bridge: $1"; }; }
# What the system said about the host just before it was given up on (last 40 matching lines).
host_forensics() {
    typeset total=0 skip line
    logcat -d -v time 2>/dev/null | grep -E 'gen5w|FATAL EXCEPTION|AndroidRuntime|ActivityManager' > "$DATA/nemesis/gen5wkr.hostlog.tmp" 2>/dev/null || :
    while IFS= read -r line || [ -n "$line" ]; do total=$((total + 1)); done < "$DATA/nemesis/gen5wkr.hostlog.tmp"
    skip=$((total - 40))
    while IFS= read -r line || [ -n "$line" ]; do
        if [ "$skip" -gt 0 ]; then skip=$((skip - 1)); continue; fi
        print -r -- "  logcat: $line"
    done < "$DATA/nemesis/gen5wkr.hostlog.tmp"
    rm -f "$DATA/nemesis/gen5wkr.hostlog.tmp"
}
host_count=0; host_stable=0; broker_count=0; broker_stable=0
HOST_READY=${BRIDGE_TEST_READY:-/data/data/kr.gen5w.wirelesshost/files/bridge-ready}
host_alive() {
    [ -f "$HOST_READY" ] && [ ! -L "$HOST_READY" ] || return 1
    IFS= read -r _host_pid < "$HOST_READY" || return 1
    case "$_host_pid" in ''|*[!0-9]*) return 1;; esac
    kill -0 "$_host_pid" 2>/dev/null || return 1
    grep -q 'kr.gen5w.wirelesshost' "/proc/$_host_pid/cmdline" 2>/dev/null
}
pause_pid=
pause() {
    sleep "$1" &
    pause_pid=$!
    wait "$pause_pid" || :
    pause_pid=
}
stop_runtime() {
    # NEMESIS can SIGKILL the supervisor shortly after SIGTERM; stop the
    # privileged child before the potentially slow ActivityManager call.
    [ -n "$broker_pid" ] && kill "$broker_pid" 2>/dev/null || :
    broker_pid=
    if [ "$host_started" = yes ]; then
        am stopservice -n kr.gen5w.wirelesshost/kr.gen5w.wireless.BridgeHostService >/dev/null 2>&1 || :
        host_started=no
    fi
}
terminate_runtime() {
    # NEMESIS may force-kill its service after 200 ms. Do not leave the broker
    # behind while waiting for ActivityManager to stop the host service.
    trap - EXIT
    [ -n "$pause_pid" ] && kill "$pause_pid" 2>/dev/null || :
    [ -n "$broker_pid" ] && kill "$broker_pid" 2>/dev/null || :
    if [ "$host_started" = yes ]; then
        am stopservice -n kr.gen5w.wirelesshost/kr.gen5w.wireless.BridgeHostService >/dev/null 2>&1 &
    fi
    exit 0
}
trap 'terminate_runtime' HUP INT TERM
trap 'stop_runtime' EXIT
while [ ! -f "$STOPPING" ]; do
    if [ -f "$DATA/nemesis/gen5wkr.wireless-disabled" ] || [ -e "$APG_OFF" ]; then
        if [ -e "$APG_OFF" ]; then note 'restart guard is off (too many unfinished starts); wireless stays off'; else note 'wired-only mode is set'; fi
        stop_runtime
        [ -n "$BRIDGE_TEST_ONCE" ] && exit 0
        pause 2
        continue
    fi
    # Dongle edition: stay wired until the USB Wi-Fi interface exists.
    if [ "$(getprop persist.gen5w.wifi.backend 2>/dev/null)" = dongle ] && [ ! -e "${BRIDGE_TEST_NET:-/sys/class/net}/wlan0" ]; then
        note 'dongle edition: no wlan0 yet'
        stop_runtime
        [ -n "$BRIDGE_TEST_ONCE" ] && exit 0
        pause 2
        continue
    fi
    # The feature files take effect only after the installer's reboot. Wireless
    # runs only in match mode; the OEM PhoneProjection stack manages its AP.
    if [ -e "$DATA/nemesis/gen5wkr.noreboot" ] ||
       [ ! -f "$AP_MATCH" ] || [ -L "$AP_MATCH" ] || [ "$(cat "$AP_MATCH" 2>/dev/null)" != match ]; then
        if [ -e "$DATA/nemesis/gen5wkr.noreboot" ]; then note 'installer reboot is pending (noreboot marker present)'
        else note "wireless is not in match mode (ap-match is not 'match')"; fi
        stop_runtime
        [ -n "$BRIDGE_TEST_ONCE" ] && exit 0
        pause 2
        continue
    fi
    [ -f "$RELAY_GATE" ] && [ ! -L "$RELAY_GATE" ] || {
        echo 'FAIL bridge: relay gate missing; wireless suspended'
        stop_runtime
        exit 1
    }
    if sh "$RELAY_GATE" "$SERVICE_DIR" >/dev/null 2>&1; then relay_status=0
    else relay_status=$?; fi
    if [ "$relay_status" -ne 0 ] && [ "$relay_status" -ne 77 ]; then
        echo 'FAIL bridge: incomplete V039 relay package; wireless suspended'
        stop_runtime
        exit 1
    fi
    if [ "$relay_status" -eq 0 ]; then
        RETRY_COUNT=$broker_count; RETRY_STABLE=$broker_stable
        if [ -n "$broker_pid" ] && kill -0 "$broker_pid" 2>/dev/null; then retry_action healthy; else retry_action dead; fi
        broker_count=$RETRY_COUNT; broker_stable=$RETRY_STABLE
        if [ "$RETRY_ACTION" = blocked ]; then
            echo 'FAIL bridge: AP broker repeatedly stopped; wireless suspended until restart'
            stop_runtime
            exit 1
        elif [ "$RETRY_ACTION" = start ]; then
            "$NEM" root 1000 -c "CLASSPATH=$DEX:/system/framework/com.tcc.iap2.jar exec /system/bin/app_process /system/bin kr.gen5w.hotspot.ApBroker $$" >/dev/null 2>&1 &
            broker_pid=$!
        fi
    fi
    RETRY_COUNT=$host_count; RETRY_STABLE=$host_stable
    if host_alive; then retry_action healthy; else retry_action dead; fi
    host_count=$RETRY_COUNT; host_stable=$RETRY_STABLE
    if [ "$RETRY_ACTION" = blocked ]; then
        echo 'FAIL bridge: host repeatedly failed to start; wireless suspended until restart'
        host_forensics
        stop_runtime
        exit 1
    elif [ "$RETRY_ACTION" = start ]; then
        rm -f "$HOST_READY" 2>/dev/null || :
        if [ "$relay_status" -eq 0 ]; then relay_extra='--ez relay_v039 true'; else relay_extra=; fi
        note "starting the host (relay=$relay_status)"
        if am startservice -n kr.gen5w.wirelesshost/kr.gen5w.wireless.BridgeHostService $relay_extra 2>&1; then
            host_started=yes
        else
            echo "FAIL bridge: am startservice rc=$?"
        fi
    fi
    [ -n "$BRIDGE_TEST_ONCE" ] && exit 0
    [ -f "$STOPPING" ] && exit 0
    pause "${BRIDGE_TEST_INTERVAL:-5}"
done
