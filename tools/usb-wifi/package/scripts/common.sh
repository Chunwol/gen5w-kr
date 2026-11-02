# USB Wi-Fi dongle package common functions
# mksh + Android toolbox only.

SYS=${DONGLE_TEST_SYS:-/system}
DATA=${DONGLE_TEST_DATA:-/data}
NEM=${DONGLE_TEST_NEM:-/system/xbin/nemesis}
LOG_FILE=$DATA/nemesis/gen5w.kr.dongle.log

# The stock Wi-Fi HAL (libhardware_legacy.so) is never changed. Only the stock
# Broadcom module it loads is swapped for a small stand-in (files/bcmdhd.ko) that
# succeeds once the USB dongle interface exists. Not loaded during boot.
TARGET=$SYS/wifi/bcmdhd.ko
LOADER_BIN=$SYS/bin/gen5w-dongle-load
MOD_DIR=$SYS/wifi/dongle
FW_DIR=$SYS/etc/firmware

BACKUP_DURABLE=$SYS/etc/gen5w-kr-backup/dongle
BACKUP_RUNTIME=$DATA/nemesis/backup/gen5w.kr.dongle
# Reboot-loop guard (service.sh): LOAD_MARK is on disk while the kernel modules
# are being loaded and for a while after; finding it at boot means the last load
# was cut short (crash, reboot or power off), so automatic loading stops
# (LOAD_BLOCK) until the dongle is unplugged.
LOAD_MARK=$DATA/nemesis/gen5wkr.dongle-loading
LOAD_BLOCK=$DATA/nemesis/gen5wkr.dongle-blocked
OWNER="gen5w.kr.dongle:2.0"

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

# Built-in (SDIO Broadcom) Wi-Fi, positive evidence only. A wlan interface
# counts only while no dongle driver is loaded, because then it can only be
# the built-in chip.
builtin_wifi_observed() {
    local root=/sys e class
    # Tests: a fake sysfs and kernel log, never the build machine's own.
    [ -z "${DONGLE_TEST_SYS:-}" ] || root=${DONGLE_TEST_SYSFS:-$DONGLE_TEST_SYS/no-sysfs}
    for e in "$root"/bus/sdio/devices/*/class; do
        [ -r "$e" ] || continue
        IFS= read -r class < "$e"
        [ "$class" = 0x07 ] && return 0
    done
    if ! grep -q ath9k_htc /proc/modules 2>/dev/null; then
        for e in "$root"/class/net/wlan*; do [ -e "$e" ] && return 0; done
    fi
    if [ -n "${DONGLE_TEST_SYS:-}" ]; then
        [ -n "${DONGLE_TEST_DMESG:-}" ] && grep -q 'Firmware up' "$DONGLE_TEST_DMESG" 2>/dev/null
        return
    fi
    dmesg 2>/dev/null | grep -q 'Firmware up'
}
# yes / unknown. Turns Wi-Fi on for up to 8 s only when it was off, with the
# stock bcmdhd.ko still in place, and turns it off again (as the standard
# edition's installer does). Prints "error" if Wi-Fi could not be turned off.
builtin_wifi() (
    builtin_wifi_observed && { echo yes; exit 0; }
    [ "$(settings get global wifi_on 2>/dev/null)" = 0 ] || { echo unknown; exit 0; }
    seen=unknown
    if svc wifi enable >/dev/null 2>&1; then
        n=0
        while [ $n -lt 8 ]; do
            builtin_wifi_observed && { seen=yes; break; }
            sleep 1; n=$((n+1))
        done
        svc wifi disable >/dev/null 2>&1
        n=0
        while [ "$(settings get global wifi_on 2>/dev/null)" != 0 ]; do
            [ $n -lt 8 ] || { echo error; exit 0; }
            sleep 1; n=$((n+1))
        done
    fi
    echo "$seen"
)
EDITION_HINT=$DATA/nemesis/gen5wkr.edition-hint

# Supported stock Broadcom module hashes (V039 Gen5W /system/wifi/bcmdhd.ko):
STOCK_KO_MD5_V039="c19ed2e2d065c6c406d0ba95945caebf"
STOCK_KO_SHA256_V039="ef79d002fd2a59e775ab7167f6adf4ecbdac0f2e2a9a2463fd5cc96b12de50c0"

digest() {
    local v
    v=$(md5 "$1" 2>/dev/null) || return 1
    set -- $v
    echo "$1"
}

is_owned() {
    [ -f "$BACKUP_DURABLE/owner" ] && [ ! -L "$BACKUP_DURABLE/owner" ] &&
    [ "$(cat "$BACKUP_DURABLE/owner" 2>/dev/null)" = "$OWNER" ]
}

verify_stock_hash() {
    local target=$1 d
    [ -f "$target" ] && [ ! -L "$target" ] || return 1
    d=$(digest "$target") || return 1
    if [ -n "${DONGLE_TEST_STOCK_MD5:-}" ]; then
        [ "$d" = "$DONGLE_TEST_STOCK_MD5" ] && return 0
        return 1
    fi
    if [ -n "${DONGLE_TEST_SYS:-}" ]; then
        return 0
    fi
    case "$d" in
        "$STOCK_KO_MD5_V039") return 0 ;;
        *) return 1 ;;
    esac
}

verify_stock_target() {
    [ -f "$TARGET" ] && [ ! -L "$TARGET" ] || return 1
    # Reinstall / update on an already owned system
    if is_owned; then
        [ -f "$BACKUP_DURABLE/original" ] && [ ! -L "$BACKUP_DURABLE/original" ] || {
            log "FAIL dongle: missing or invalid durable backup"; return 1;
        }
        verify_stock_hash "$BACKUP_DURABLE/original" || { log "FAIL dongle: corrupted or modified durable backup"; return 1; }
        aux_manifest_valid || { log 'FAIL dongle: missing or changed file ownership journal'; return 1; }
        return 0
    fi
    verify_stock_hash "$TARGET" || {
        log "FAIL dongle: unsupported or modified bcmdhd.ko hash $(digest "$TARGET" 2>/dev/null)"
        return 1
    }
    return 0
}

# Stage on /system in our durable journal, then atomically rename into place.
# An interrupted stage is owned by this journal and may be discarded on retry.
install_owned_file() {
    local src=$1 dst=$2 mode=$3 stage="$BACKUP_DURABLE/stage.${2##*/}"
    [ -f "$src" ] && [ ! -L "$src" ] && [ ! -L "$dst" ] && [ ! -L "$stage" ] || return 1
    if [ -e "$stage" ]; then [ -f "$stage" ] && rm -f "$stage" || return 1; fi
    cp -p "$src" "$stage" || return 1
    [ "$(digest "$src")" = "$(digest "$stage")" ] || return 1
    if [ "$mode" != original ]; then
        chmod "$mode" "$stage" || return 1
        { [ -n "$DONGLE_TEST_SYS" ] || chown 0:0 "$stage"; } || return 1
    fi
    sync || return 1
    mv "$stage" "$dst" || return 1
    [ ! -x /system/bin/restorecon ] || /system/bin/restorecon "$dst" || return 1
    [ "$(digest "$src")" = "$(digest "$dst")" ] || return 1
}

# A versioned list of files created by this package. Legacy installations do not
# contain enough information to identify or restore overwritten auxiliary files.
aux_payload_manifest() {
    local src name sum count=0
    for src in "$SCRIPT_DIR"/../files/modules/*.ko; do
        [ -f "$src" ] && [ ! -L "$src" ] || continue
        name=${src##*/}; case "$name" in gen5w-average.ko|ccm.ko|ctr.ko|seqiv.ko|mac80211.ko|ath.ko|ath9k_hw.ko|ath9k_common.ko|ath9k_htc.ko) ;; *) return 1;; esac
        sum=$(digest "$src") || return 1
        echo "$sum|wifi/dongle/$name"; count=$((count+1))
    done
    [ "$count" -gt 0 ] || return 1
    count=0
    for src in "$SCRIPT_DIR"/../files/firmware/*; do
        [ -f "$src" ] && [ ! -L "$src" ] || continue
        name=${src##*/}; case "$name" in htc_9271.fw|htc_7010.fw) ;; *) return 1;; esac
        sum=$(digest "$src") || return 1
        echo "$sum|etc/firmware/$name"; count=$((count+1))
    done
    [ "$count" -gt 0 ] || return 1
    for src in "$SCRIPT_DIR/../bin/gen5w-dongle-load" "$SCRIPT_DIR/../files/bcmdhd.ko"; do
        [ -f "$src" ] && [ ! -L "$src" ] || return 1
        sum=$(digest "$src") || return 1
        case "${src##*/}" in gen5w-dongle-load) name=bin/gen5w-dongle-load;; *) name=wifi/bcmdhd.ko;; esac
        echo "$sum|$name"
    done
}
aux_safe_dirs() {
    local dir
    for dir in "$SYS" "$SYS/wifi" "$MOD_DIR" "$SYS/etc" "$FW_DIR" "$SYS/bin" "$SYS/etc/gen5w-kr-backup" "$BACKUP_DURABLE" "$DATA" "$DATA/nemesis" "$DATA/nemesis/backup" "$BACKUP_RUNTIME"; do
        [ ! -L "$dir" ] && { [ ! -e "$dir" ] || [ -d "$dir" ]; } || return 1
    done
    for dir in "$BACKUP_RUNTIME/original" "$BACKUP_RUNTIME/owner"; do
        [ ! -L "$dir" ] && { [ ! -e "$dir" ] || [ -f "$dir" ]; } || return 1
    done
    if [ -e "$BACKUP_RUNTIME" ]; then
        [ -f "$BACKUP_RUNTIME/owner" ] && [ "$(cat "$BACKUP_RUNTIME/owner")" = "$OWNER" ] &&
        verify_stock_hash "$BACKUP_RUNTIME/original" || return 1
    fi
}
aux_manifest_valid() {
    local sum rel extra path seen='|'
    aux_safe_dirs || return 1
    [ -f "$BACKUP_DURABLE/files" ] && [ ! -L "$BACKUP_DURABLE/files" ] && [ -s "$BACKUP_DURABLE/files" ] || return 1
    [ -f "$BACKUP_DURABLE/files.md5" ] && [ ! -L "$BACKUP_DURABLE/files.md5" ] &&
    [ "$(digest "$BACKUP_DURABLE/files")" = "$(cat "$BACKUP_DURABLE/files.md5")" ] || return 1
    [ -f "$BACKUP_DURABLE/backend.original" ] && [ ! -L "$BACKUP_DURABLE/backend.original" ] &&
    [ -f "$BACKUP_DURABLE/backend.md5" ] && [ ! -L "$BACKUP_DURABLE/backend.md5" ] &&
    [ "$(digest "$BACKUP_DURABLE/backend.original")" = "$(cat "$BACKUP_DURABLE/backend.md5")" ] || return 1
    while IFS='|' read -r sum rel extra; do
        case "$sum" in ''|*[!a-fA-F0-9]*) return 1;; esac
        [ ${#sum} -eq 32 ] && [ -z "$extra" ] || return 1
        case "$rel" in wifi/dongle/gen5w-average.ko|wifi/dongle/ccm.ko|wifi/dongle/ctr.ko|wifi/dongle/seqiv.ko|wifi/dongle/mac80211.ko|wifi/dongle/ath.ko|wifi/dongle/ath9k_hw.ko|wifi/dongle/ath9k_common.ko|wifi/dongle/ath9k_htc.ko|etc/firmware/htc_9271.fw|etc/firmware/htc_7010.fw|bin/gen5w-dongle-load|wifi/bcmdhd.ko) ;; *) return 1;; esac
        case "$rel" in *..*|*[!a-zA-Z0-9_./-]*) return 1;; esac
        case "$seen" in *"|$rel|"*) return 1;; esac
        seen="$seen$rel|"; path=$SYS/$rel
        [ ! -L "$path" ] || return 1
        if [ -e "$path" ]; then
            [ -f "$path" ] || return 1
            [ "$(digest "$path")" = "$sum" ] || { [ "$rel" = wifi/bcmdhd.ko ] && verify_stock_hash "$path"; } || return 1
        fi
    done < "$BACKUP_DURABLE/files"
}
aux_install_check() {
    local listing sum rel extra current original
    aux_safe_dirs || return 1
    command -v getprop >/dev/null 2>&1 && command -v setprop >/dev/null 2>&1 || return 1
    listing=$(aux_payload_manifest) || return 1
    if is_owned; then
        aux_manifest_valid || { log 'FAIL dongle: missing or changed file ownership journal'; return 1; }
        [ "$listing" = "$(cat "$BACKUP_DURABLE/files")" ] || { log 'FAIL dongle: payload changed; explicit migration required'; return 1; }
        current=$(getprop persist.gen5w.wifi.backend) || return 1
        original=$(cat "$BACKUP_DURABLE/backend.original") || return 1
        [ "$current" = dongle ] || [ "$current" = "$original" ] || return 1
    else
        [ ! -e "$BACKUP_DURABLE" ] && [ ! -L "$BACKUP_DURABLE" ] || return 1
        while IFS='|' read -r sum rel extra; do
            [ "$rel" = wifi/bcmdhd.ko ] && continue
            [ ! -e "$SYS/$rel" ] && [ ! -L "$SYS/$rel" ] || { log "FAIL dongle: pre-existing target $rel"; return 1; }
        done <<EOF
$listing
EOF
    fi
}
# No system journal but /data still says "dongle": a firmware reinstall put
# /system back to stock. Drop the runtime copy and the backend setting, but only
# when none of our files is live (the stand-in or any added module/firmware).
clear_stale_runtime() {
    local listing sum rel extra
    [ ! -e "$BACKUP_DURABLE" ] && [ ! -L "$BACKUP_DURABLE" ] || return 1
    aux_safe_dirs || return 1
    listing=$(aux_payload_manifest) || return 1
    while IFS='|' read -r sum rel extra; do
        [ ! -L "$SYS/$rel" ] || return 1
        [ ! -e "$SYS/$rel" ] || [ "$(digest "$SYS/$rel")" != "$sum" ] || return 1
    done <<EOF2
$listing
EOF2
    command -v getprop >/dev/null 2>&1 && command -v setprop >/dev/null 2>&1 || return 1
    if [ "$(getprop persist.gen5w.wifi.backend)" = dongle ]; then
        setprop persist.gen5w.wifi.backend '' &&
        [ -z "$(getprop persist.gen5w.wifi.backend)" ] || return 1
    fi
    if [ -e "$BACKUP_RUNTIME" ]; then
        rm -f "$BACKUP_RUNTIME/original" "$BACKUP_RUNTIME/owner" && rmdir "$BACKUP_RUNTIME" || return 1
        log 'CLEARED dongle: runtime copy left by a system reinstall'
    fi
    rm -f "$LOAD_MARK" "$LOAD_BLOCK" || return 1
}
