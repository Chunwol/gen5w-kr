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
AP_MATCH=$DATA/nemesis/gen5wkr.ap-match
# AP start guard (see AndroidWifiAp): the bridge (uid 1000) leaves "attempt"
# holding the boot id while an AP start is in progress, and "ok" after one stayed
# up. An attempt from an earlier boot means the unit restarted mid-start.
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
apguard_boot || { [ -n "$BRIDGE_TEST_ONCE" ] && exit 0; while [ ! -f "$STOPPING" ]; do sleep 2; done; exit 0; }
bridge_backoff=2
while [ ! -f "$STOPPING" ]; do
    if [ -f "$DATA/nemesis/gen5wkr.wireless-disabled" ] || [ -e "$APG_OFF" ]; then
        [ -n "$BRIDGE_TEST_ONCE" ] && exit 0
        sleep 2
        continue
    fi
    # Dongle edition: stay wired until the USB Wi-Fi interface exists.
    if [ "$(getprop persist.gen5w.wifi.backend 2>/dev/null)" = dongle ] && [ ! -e "${BRIDGE_TEST_NET:-/sys/class/net}/wlan0" ]; then
        [ -n "$BRIDGE_TEST_ONCE" ] && exit 0
        sleep 2
        continue
    fi
    # A patched system_server file cannot take effect in its existing process.
    # Wait for the native profile module's verified post-reboot readiness.
    # Match mode (safe-wireless) keeps services.odex stock and needs no profile
    # module; the installer's reboot is still required for the feature files.
    if [ -e "$DATA/nemesis/gen5wkr.noreboot" ]; then
        [ -n "$BRIDGE_TEST_ONCE" ] && exit 0
        sleep 2
        continue
    fi
    if [ -f "$AP_MATCH" ] && [ ! -L "$AP_MATCH" ] && [ "$(cat "$AP_MATCH" 2>/dev/null)" = match ]; then
        :
    elif [ -L "$PROFILE_READY" ] || [ ! -f "$PROFILE_READY" ] || ! "$PROFILE_SHELL" "$PROFILE_READY"; then
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
