#!/system/bin/sh
# Root background service for USB Wi-Fi dongle kernel module loading.
# Runs as uid=root under NEMESIS service manager so insmod has CAP_SYS_MODULE
# even when system_server (uid 1000) requests wifi_load_driver().

SCRIPT_DIR=${0%/*}
[ "$SCRIPT_DIR" != "$0" ] || SCRIPT_DIR=.
. "$SCRIPT_DIR/common.sh"

REQ_FILE=$DATA/nemesis/gen5w.dongle.request

try_load() {
    [ -x "$LOADER_BIN" ] || return 1
    if [ ! -e /sys/class/net/wlan0 ]; then
        "$LOADER_BIN" >/dev/null 2>&1 || return 1
    fi
    return 0
}

# Initial boot check: if dongle hardware is attached, load modules immediately
if has_dongle_hw && [ ! -e /sys/class/net/wlan0 ]; then
    try_load || true
fi

# Background loop: watch for hotplug or HAL load requests from system_server
while true; do
    if [ ! -e /sys/class/net/wlan0 ]; then
        status=$(getprop wlan.driver.status 2>/dev/null)
        req=$(getprop wlan.driver.load.request 2>/dev/null)
        if [ -f "$REQ_FILE" ] || [ "$status" = "loading" ] || [ "$req" = "1" ] || has_dongle_hw; then
            rm -f "$REQ_FILE" 2>/dev/null || true
            setprop wlan.driver.load.request 0 2>/dev/null || true
            try_load || true
        fi
    fi
    sleep 1
done
