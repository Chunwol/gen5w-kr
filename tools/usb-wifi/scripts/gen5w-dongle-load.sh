#!/system/bin/sh
# USB Wi-Fi dongle module loader for Hyundai/Kia Gen5W
# Loads ath9k_htc and dependency modules for AR9271/AR7010 USB dongles

MOD_DIR=${DONGLE_MOD_DIR:-/system/wifi/dongle}
LOG_FILE=${DONGLE_LOG_FILE:-/data/nemesis/dongle.log}

log_size() {
    # GNU ls includes a link-count field; Android toolbox ls does not.
    local size
    set -- $(LC_ALL=C ls -ln "$1" 2>/dev/null) || return 1
    size=${5:-}
    case "$size" in ''|*[!0-9]*) size=${4:-};; esac
    case "$size" in ''|*[!0-9]*) return 1;; esac
    echo "$size"
}

log() {
    echo "$1"
    [ ! -L "$LOG_FILE" ] && [ ! -L "$LOG_FILE.1" ] || return 0
    mkdir -p "${LOG_FILE%/*}" 2>/dev/null || return 0
    if [ -f "$LOG_FILE" ]; then
        local sz
        # Rotate conservatively if file size cannot be read.
        sz=$(log_size "$LOG_FILE") || sz=32769
        [ "$sz" -le 32768 ] || mv "$LOG_FILE" "$LOG_FILE.1" 2>/dev/null || return 0
    fi
    echo "$1" >> "$LOG_FILE" 2>/dev/null || true
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
    local proc_name="$name"
    case "$proc_name" in *-*) proc_name=${proc_name%%-*}_${proc_name#*-};; esac
    if grep -q "^$name " /proc/modules 2>/dev/null || grep -q "^$proc_name " /proc/modules 2>/dev/null; then
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

find_driver() {
    local v p modalias kind pattern module
    for v in /sys/bus/usb/devices/*/idVendor; do
        [ -r "$v" ] || continue
        p=${v%idVendor}modalias
        if [ -r "$p" ]; then read -r modalias < "$p"
        else
            p=${v%idVendor}idProduct; [ -r "$p" ] || continue
            read -r vid < "$v"; read -r pid < "$p"
            modalias="usb:v${vid}p${pid}d0000dc00dsc00dp00ic00isc00ip00in00"
        fi
        while read -r kind pattern module; do
            [ "$kind" = alias ] || continue
            case "$modalias" in $pattern) echo "$module"; return 0;; esac
        done < "$MOD_DIR/modules.alias"
    done
    return 1
}

DRIVER=$(find_driver) || { log 'FAIL: attached USB device has no packaged driver alias'; exit 1; }
PROFILE_MODULE=; MODULES=; FIRMWARES=; PROFILE_STATUS=
while IFS='|' read -r candidate modules firmware bands ap status; do
    [ "$candidate" = "$DRIVER" ] || continue
    PROFILE_MODULE=$candidate; MODULES=$modules; FIRMWARES=$firmware; PROFILE_STATUS=$status; break
done < "$MOD_DIR/modules.profile"
[ "$PROFILE_MODULE" = "$DRIVER" ] && [ -n "$MODULES" ] && [ "$PROFILE_STATUS" = ready ] || { log "FAIL: no ready module profile for $DRIVER"; exit 1; }
for fw in $FIRMWARES; do
    [ -f "/system/etc/firmware/$fw" ] || { log "FAIL: $DRIVER firmware missing: $fw"; exit 1; }
done
log "USB modalias selected driver=$DRIVER"
for mod in $MODULES; do
    load_mod "$mod.ko" || { log "FAIL: could not load $mod for $DRIVER"; exit 1; }
done

# Wait for network interface creation
timeout=5
while [ $timeout -gt 0 ]; do
    if [ -e /sys/class/net/wlan0 ]; then
        log "USB Wi-Fi dongle interface wlan0 detected"
        setprop wlan.driver.status ok 2>/dev/null || true
        setprop gen5w.dongle.ready 1 2>/dev/null || true
        exit 0
    fi
    sleep 1
    timeout=$((timeout - 1))
done

log "WARN: timeout waiting for wlan0"
exit 1
