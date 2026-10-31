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
