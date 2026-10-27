#!/system/bin/sh
# USB Wi-Fi dongle module loader for Hyundai/Kia Gen5W
# Loads ath9k_htc and dependency modules for AR9271/AR7010 USB dongles

MOD_DIR=${DONGLE_MOD_DIR:-/system/wifi/dongle}
LOG_FILE=${DONGLE_LOG_FILE:-/data/nemesis/dongle.log}

log() {
    echo "$1"
    [ -d /data/nemesis ] && echo "$1" >> "$LOG_FILE" 2>/dev/null || true
}

# Already available
if [ -e /sys/class/net/wlan0 ]; then
    setprop wlan.driver.status ok 2>/dev/null || true
    setprop gen5w.dongle.ready 1 2>/dev/null || true
    exit 0
fi

if [ ! -d "$MOD_DIR" ]; then
    log "FAIL: dongle module directory $MOD_DIR not found"
    exit 1
fi

load_mod() {
    local mod="$1"
    local name="${mod%.ko}"
    if grep -q "^$name " /proc/modules 2>/dev/null; then
        return 0
    fi
    if [ -f "$MOD_DIR/$mod" ]; then
        insmod "$MOD_DIR/$mod" 2>/dev/null || {
            log "WARN: insmod $mod returned non-zero"
            return 1
        }
    else
        log "WARN: module $mod not found in $MOD_DIR"
        return 1
    fi
    return 0
}

# 1. Crypto & helper modules
load_mod gen5w-average.ko || true
load_mod ccm.ko || true
load_mod ctr.ko || true
load_mod seqiv.ko || true

# 2. mac80211 stack
load_mod mac80211.ko || true

# 3. Atheros core & common
load_mod ath.ko || true
load_mod ath9k_hw.ko || true
load_mod ath9k_common.ko || true

# 4. USB transport driver (triggers firmware load)
load_mod ath9k_htc.ko || true

# Wait for network interface creation
timeout=25
while [ $timeout -gt 0 ]; do
    if [ -e /sys/class/net/wlan0 ]; then
        log "USB Wi-Fi dongle interface wlan0 detected"
        setprop wlan.driver.status ok 2>/dev/null || true
        setprop gen5w.dongle.ready 1 2>/dev/null || true
        exit 0
    fi
    sleep 0.2 2>/dev/null || sleep 1
    timeout=$((timeout - 1))
done

log "WARN: timeout waiting for wlan0"
exit 1
