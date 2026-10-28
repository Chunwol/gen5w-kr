#!/system/bin/sh
# Root background service for USB Wi-Fi dongle kernel module loading.
# Runs as uid=root under NEMESIS service manager so insmod has CAP_SYS_MODULE
# even when system_server (uid 1000) requests wifi_load_driver().

SCRIPT_DIR=${0%/*}
[ "$SCRIPT_DIR" != "$0" ] || SCRIPT_DIR=.
. "$SCRIPT_DIR/common.sh"

MAX_RETRIES=3
fail_count=0

is_dongle_backend() {
    local b
    b=$(getprop persist.gen5w.wifi.backend 2>/dev/null)
    [ "$b" = "dongle" ] || [ "$b" = "usb" ]
}

try_load() {
    [ -x "$LOADER_BIN" ] || return 1
    if [ ! -e /sys/class/net/wlan0 ]; then
        "$LOADER_BIN" >/dev/null 2>&1 || return 1
    fi
    return 0
}

# Initial boot check: if dongle backend is active and hardware is attached, load modules
if is_dongle_backend && has_dongle_hw && [ ! -e /sys/class/net/wlan0 ]; then
    if try_load; then
        fail_count=0
    else
        fail_count=1
    fi
fi

# Background loop: watch for hotplug or HAL load requests from system_server
# Bounded retries (max 3 per hardware attachment or explicit request) prevent infinite insmod loops.
while true; do
    if [ -e /sys/class/net/wlan0 ]; then
        fail_count=0
    else
        req=$(getprop wlan.driver.load.request 2>/dev/null)
        if [ "$req" = "1" ]; then
            setprop wlan.driver.load.request 0 2>/dev/null || true
            fail_count=0
        fi
        if ! has_dongle_hw && [ "$req" != "1" ]; then
            fail_count=0
        elif (is_dongle_backend && has_dongle_hw) || [ "$req" = "1" ]; then
            if [ "$fail_count" -lt "$MAX_RETRIES" ]; then
                if try_load; then
                    fail_count=0
                else
                    fail_count=$((fail_count + 1))
                fi
            fi
        fi
    fi
    sleep 2
done
