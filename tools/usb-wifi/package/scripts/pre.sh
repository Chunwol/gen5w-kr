#!/system/bin/sh
SCRIPT_DIR=${0%/*}
[ "$SCRIPT_DIR" != "$0" ] || SCRIPT_DIR=.
. "$SCRIPT_DIR/common.sh"
# Installed on its own, the swapped bcmdhd.ko would be live at the next boot
# without the boot-loop guard, which only the release bundle arms. Every bundle
# step creates the reboot-suppression file before running this check.
if [ -z "${DONGLE_TEST_SYS:-}" ] && [ ! -f "$DATA/nemesis/gen5wkr.noreboot" ]; then
    log 'FAIL: install this package with the release bundle (GEN5W-ACTION), not on its own'
    exit 1
fi

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
verify_stock_target || { log "FAIL dongle: invalid or damaged stock bcmdhd.ko"; exit 1; }
aux_install_check || { log 'FAIL dongle: file collision or unknown ownership'; exit 1; }

# Positive hardware detection or explicit install override. An update or rollback
# of an installed dongle edition (GEN5W_REINSTALL from the installer) does not
# need the dongle plugged in.
if [ -z "${GEN5W_REINSTALL:-}" ] && ! has_dongle_hw; then
    if [ ! -f "${DONGLE_TEST_FLAG:-/data/nemesis/GEN5W-DONGLE}" ] && [ ! -f /mnt/usb/GEN5W-DONGLE ]; then
        log "SKIP dongle: no supported USB Wi-Fi dongle detected (0cf3:9271 / 0cf3:7010)"
        exit 77
    fi
fi

# A car with working built-in Wi-Fi should use the standard edition: the
# dongle edition would switch its built-in Wi-Fi off. Checked on a fresh
# install only, while the stock bcmdhd.ko is still in place. An empty
# GEN5W-FORCE-DONGLE on the USB (GEN5W_FORCE_DONGLE from the installer)
# keeps the dongle on purpose.
if [ -z "${GEN5W_REINSTALL:-}" ] && [ -z "${GEN5W_FORCE_DONGLE:-}" ]; then
    hw=$(builtin_wifi)
    case "$hw" in
        yes)
            log 'REFUSED dongle: built-in Wi-Fi found; use the standard edition (gen5w-kr-standard.zip), or put GEN5W-FORCE-DONGLE on the USB to use the dongle anyway'
            [ -L "$EDITION_HINT" ] || echo standard > "$EDITION_HINT" 2>/dev/null
            exit 1;;
        error)
            log 'FAIL dongle: Wi-Fi could not be turned off again after the built-in Wi-Fi check'
            exit 1;;
    esac
    log "built-in Wi-Fi check: $hw"
fi

log "dongle precheck passed"
exit 0
