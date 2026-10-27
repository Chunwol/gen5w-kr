#!/system/bin/sh
# Root NEMESIS supervisor, system-uid Java daemon; no transport-content logging.
SCRIPT_DIR=${0%/*}
[ "$SCRIPT_DIR" != "$0" ] || SCRIPT_DIR=.
SERVICE_DIR=$(cd "$SCRIPT_DIR/.." && pwd) || exit 1
. "$SERVICE_DIR/scripts/common.sh"
inspect || exit $?
[ "$BRIDGE_STATE" = patched ] && [ "$DIPO_STATE" = patched ] && [ "$BRIDGE_OWNED" = yes ] || exit 1
DATA=${BRIDGE_TEST_DATA:-/data}
NEM=${BRIDGE_TEST_NEM:-/system/xbin/nemesis}
STOPPING=$DATA/nemesis/gen5wkr.bridge.stopping
DEX=$SERVICE_DIR/app/bridge.dex
PROFILE_READY=${BRIDGE_TEST_PROFILE_READY:-$DATA/nemesis/apps/gen5w.kr.hotspot/scripts/profile-ready.sh}
PROFILE_SHELL=${BRIDGE_TEST_SHELL:-/system/bin/sh}
case "$DEX" in *[!a-zA-Z0-9_./-]*) echo 'FAIL bridge: unsupported package path'; exit 1;; esac
[ -f "$DEX" ] && [ ! -L "$DEX" ] && [ -x "$NEM" ] || exit 1
trap 'exit 0' HUP INT TERM
while [ ! -f "$STOPPING" ]; do
    [ "$(getprop sys.boot_completed)" = 1 ] && break
    sleep 2
done
bridge_backoff=2
while [ ! -f "$STOPPING" ]; do
    if [ -f "$DATA/nemesis/gen5wkr.wireless-disabled" ]; then
        [ -n "$BRIDGE_TEST_ONCE" ] && exit 0
        sleep 2
        continue
    fi
    # A patched system_server file cannot take effect in its existing process.
    # Wait for the native profile module's verified post-reboot readiness.
    if [ -e "$DATA/nemesis/gen5wkr.noreboot" ] || [ -L "$PROFILE_READY" ] ||
       [ ! -f "$PROFILE_READY" ] || ! "$PROFILE_SHELL" "$PROFILE_READY"; then
        [ -n "$BRIDGE_TEST_ONCE" ] && exit 0
        sleep 2
        continue
    fi
    "$NEM" root 1000 -c "CLASSPATH=$DEX:/system/framework/com.tcc.iap2.jar app_process /system/bin kr.gen5w.wireless.WirelessBridge" >/dev/null 2>&1
    [ -n "$BRIDGE_TEST_ONCE" ] && exit 0
    [ -f "$STOPPING" ] && exit 0
    sleep "$bridge_backoff"
    [ "$bridge_backoff" -ge 5 ] || bridge_backoff=$((bridge_backoff + 1))
    [ "$bridge_backoff" -le 5 ] || bridge_backoff=5
done
