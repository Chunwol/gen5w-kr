# USB Wi-Fi dongle package common functions
# mksh + Android toolbox only.

SYS=${DONGLE_TEST_SYS:-/system}
DATA=${DONGLE_TEST_DATA:-/data}
NEM=${DONGLE_TEST_NEM:-/system/xbin/nemesis}
LOG_FILE=$DATA/nemesis/gen5w.kr.dongle.log

TARGET_HAL=$SYS/lib/libhardware_legacy.so
STOCK_HAL=$SYS/lib/libhardware_legacy_stock.so
LOADER_BIN=$SYS/bin/gen5w-dongle-load
MOD_DIR=$SYS/wifi/dongle
FW_DIR=$SYS/etc/firmware

BACKUP_DURABLE=$SYS/etc/gen5w-kr-backup/dongle
BACKUP_RUNTIME=$DATA/nemesis/backup/gen5w.kr.dongle
OWNER="gen5w.kr.dongle:1.0"

log() {
    echo "$1"
    mkdir -p "$DATA/nemesis" 2>/dev/null || true
    echo "$1" >> "$LOG_FILE" 2>/dev/null || true
}

sys_rw() { "$NEM" remount rw >/dev/null 2>&1; }
sys_ro() { "$NEM" remount ro >/dev/null 2>&1; }

has_dongle_hw() {
    local dev_root=${DONGLE_TEST_SYS_BUS:-/sys/bus/usb/devices}
    # Check for known Atheros USB IDs: 0cf3:9271, 0cf3:7010, 0cf3:7015, 0846:9030, etc.
    if [ -d "$dev_root" ]; then
        for v in "$dev_root"/*/idVendor; do
            [ -f "$v" ] || continue
            p="${v%idVendor}idProduct"
            [ -f "$p" ] || continue
            read -r vid < "$v"
            read -r pid < "$p"
            case "$vid:$pid" in
                0cf3:9271|0cf3:7010|0cf3:7015|0cf3:1006|0846:9030|0846:9018|07d1:3a10)
                    return 0
                    ;;
            esac
        done
    fi
    # Also accept if wlan0 already present with ath9k_htc
    if [ -e "${DONGLE_TEST_SYS:-}/sys/class/net/wlan0" ] || [ -e /sys/class/net/wlan0 ]; then
        grep -q "ath9k_htc" /proc/modules 2>/dev/null && return 0
    fi
    return 1
}

is_owned() {
    [ -f "$BACKUP_DURABLE/owner" ] && [ "$(cat "$BACKUP_DURABLE/owner" 2>/dev/null)" = "$OWNER" ]
}

verify_stock_target() {
    [ -f "$TARGET_HAL" ] && [ ! -L "$TARGET_HAL" ] || return 1
    # Check that target is not already our adapter unless owned
    if [ -f "$STOCK_HAL" ]; then
        is_owned && return 0
        return 1
    fi
    return 0
}
