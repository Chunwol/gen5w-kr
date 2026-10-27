#!/system/bin/sh
SCRIPT_DIR=${0%/*}
[ "$SCRIPT_DIR" != "$0" ] || SCRIPT_DIR=.
. "$SCRIPT_DIR/common.sh"

# Refuse if target HAL does not exist or has invalid link
verify_stock_target || {
    log "FAIL dongle: invalid or damaged stock HAL library"
    exit 1
}

# Positive hardware detection or explicit install override
if ! has_dongle_hw; then
    if [ ! -f "${DONGLE_TEST_FLAG:-/data/nemesis/GEN5W-DONGLE}" ] && [ ! -f /mnt/usb/GEN5W-DONGLE ]; then
        log "SKIP dongle: no supported USB Wi-Fi dongle detected (0cf3:9271 / 0cf3:7010)"
        exit 77
    fi
fi

log "dongle precheck passed"
exit 0
