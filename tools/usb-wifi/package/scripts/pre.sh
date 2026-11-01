#!/system/bin/sh
SCRIPT_DIR=${0%/*}
[ "$SCRIPT_DIR" != "$0" ] || SCRIPT_DIR=.
. "$SCRIPT_DIR/common.sh"

# Verify required payload files exist in package
[ -f "$SCRIPT_DIR/../files/bcmdhd.ko" ] || {
    log "FAIL dongle: missing bcmdhd stand-in module payload"
    exit 1
}
[ -f "$SCRIPT_DIR/../files/modules/ath9k_htc.ko" ] || {
    log "FAIL dongle: missing kernel modules payload"
    exit 1
}
[ -f "$SCRIPT_DIR/../files/firmware/htc_9271.fw" ] || {
    log "FAIL dongle: missing firmware payload"
    exit 1
}
if legacy_owned; then
    # An earlier HAL-adapter install: the installer removes it through its own
    # registered uninstall (stock HAL restored) before this version is applied.
    [ -f "$DATA/nemesis/apps/gen5w.kr.dongle/NEMESIS.data" ] && [ ! -L "$DATA/nemesis/apps/gen5w.kr.dongle/NEMESIS.data" ] || {
        log 'FAIL dongle: earlier HAL adapter install has no registered package to remove it'; exit 1;
    }
    log 'dongle: earlier HAL adapter install will be removed first'
else
    verify_stock_target || { log "FAIL dongle: invalid or damaged stock bcmdhd.ko"; exit 1; }
    aux_install_check || { log 'FAIL dongle: file collision or unknown ownership'; exit 1; }
fi

# Positive hardware detection or explicit install override
if ! has_dongle_hw; then
    if [ ! -f "${DONGLE_TEST_FLAG:-/data/nemesis/GEN5W-DONGLE}" ] && [ ! -f /mnt/usb/GEN5W-DONGLE ]; then
        log "SKIP dongle: no supported USB Wi-Fi dongle detected (0cf3:9271 / 0cf3:7010)"
        exit 77
    fi
fi

log "dongle precheck passed"
exit 0
