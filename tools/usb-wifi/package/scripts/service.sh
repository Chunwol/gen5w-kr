#!/system/bin/sh
# Root background service for USB Wi-Fi dongle kernel module loading.
# Runs as uid=root under NEMESIS service manager so insmod has CAP_SYS_MODULE
# even when system_server (uid 1000) requests wifi_load_driver().

SCRIPT_DIR=${0%/*}
[ "$SCRIPT_DIR" != "$0" ] || SCRIPT_DIR=.
. "$SCRIPT_DIR/common.sh"

NET_ROOT=${DONGLE_TEST_NET_ROOT:-/sys/class/net}
MAX_RETRIES=3
fail_count=0

is_dongle_backend() {
    local b
    b=$(getprop persist.gen5w.wifi.backend 2>/dev/null)
    [ "$b" = "dongle" ] || [ "$b" = "usb" ]
}

STABLE_SECONDS=${DONGLE_TEST_STABLE:-60}
stable=0

toast() {
    am broadcast -a com.hkmc.intent.action.TOAST -e com.hkmc.intent.extra.TOAST_MESSAGE "$1"         --ez com.hkmc.intent.extra.TOAST_POPUPSHOWING true >/dev/null 2>&1 || true
}

# The mark goes to disk before any insmod. If the unit dies while loading or soon
# after, the next boot finds it and stops automatic loading instead of crashing
# again on every boot.
try_load() {
    [ -x "$LOADER_BIN" ] || return 1
    [ ! -e "$LOAD_BLOCK" ] && [ ! -L "$LOAD_BLOCK" ] || return 1
    if [ ! -e "$NET_ROOT/wlan0" ]; then
        [ ! -L "$LOAD_MARK" ] || return 1
        mkdir -p "${LOAD_MARK%/*}" 2>/dev/null
        echo loading > "$LOAD_MARK" || return 1
        sync
        stable=0
        "$LOADER_BIN" >/dev/null 2>&1 || { rm -f "$LOAD_MARK"; return 1; }
    fi
    return 0
}

# Policy: the car boots as stock (wired). Driver modules are loaded only after
# boot has completed and a supported dongle is attached.
if [ -z "${DONGLE_TEST_NET_ROOT:-}" ]; then
    while [ "$(getprop sys.boot_completed 2>/dev/null)" != 1 ]; do sleep 2; done
fi

# A mark left from the previous boot: that load never finished cleanly.
if [ -e "$LOAD_MARK" ] && [ ! -L "$LOAD_MARK" ]; then
    # Replace whatever is at that name (a link is removed, not followed).
    rm -f "$LOAD_BLOCK"
    echo blocked > "$LOAD_BLOCK"
    sync
    rm -f "$LOAD_MARK"
    log 'BLOCKED dongle: the unit restarted while the dongle driver was loading; automatic loading stopped until the dongle is unplugged'
    toast "USB Wi-Fi 동글 드라이버를 올리던 중 재시작되어 동글 사용을 멈췄습니다. 동글을 뽑았다 다시 꽂으면 한 번 다시 시도합니다."
fi

# Initial check: if dongle backend is active and hardware is attached, load modules
if is_dongle_backend && has_dongle_hw && [ ! -e "$NET_ROOT/wlan0" ]; then
    if try_load; then
        fail_count=0
    else
        fail_count=1
    fi
fi

# Background loop: watch for hotplug or HAL load requests from system_server
# Bounded retries (max 3 per hardware attachment or explicit request) prevent infinite insmod loops.
while true; do
    # Unplugging the dongle clears the block; the next attachment tries once more.
    if [ -e "$LOAD_BLOCK" ] && ! has_dongle_hw; then
        rm -f "$LOAD_BLOCK" && log 'dongle unplugged: automatic loading allowed again'
    fi
    if [ -e "$LOAD_MARK" ]; then
        if [ -e "$NET_ROOT/wlan0" ]; then
            stable=$((stable + 2))
            [ "$stable" -lt "$STABLE_SECONDS" ] || { rm -f "$LOAD_MARK"; stable=0; }
        fi
    fi
    if [ -e "$NET_ROOT/wlan0" ]; then
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
