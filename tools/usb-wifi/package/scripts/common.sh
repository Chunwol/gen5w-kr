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
        [ "$sz" -le 32768 ] || mv -f "$LOG_FILE" "$LOG_FILE.1" 2>/dev/null || return 0
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

# Supported stock HAL library hashes (V039 Gen5W):
STOCK_HAL_MD5_V039="5491a1a37e2c252dc55fc3e2036f0f6b"
STOCK_HAL_SHA256_V039="e173ce9c465ba8df9201372caa761809e70a82ba0098f14421f9032957c8803f"

digest() {
    local v
    v=$(md5 "$1" 2>/dev/null) || v=$(md5sum "$1" 2>/dev/null) || return 1
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
        "$STOCK_HAL_MD5_V039") return 0 ;;
        *) return 1 ;;
    esac
}

verify_stock_target() {
    [ -f "$TARGET_HAL" ] && [ ! -L "$TARGET_HAL" ] || return 1
    # Check if this is a reinstall / update on an already owned system
    if [ -f "$STOCK_HAL" ] || is_owned; then
        is_owned || { log "FAIL dongle: stock copy present without valid owner"; return 1; }
        [ -f "$BACKUP_DURABLE/original" ] && [ ! -L "$BACKUP_DURABLE/original" ] || {
            log "FAIL dongle: missing or invalid durable backup"; return 1;
        }
        verify_stock_hash "$BACKUP_DURABLE/original" || { log "FAIL dongle: corrupted or modified durable backup"; return 1; }
        if [ -e "$STOCK_HAL" ] || [ -L "$STOCK_HAL" ]; then
            verify_stock_hash "$STOCK_HAL" || { log "FAIL dongle: corrupted or modified stock copy"; return 1; }
        else
            aux_manifest_valid || { log 'FAIL dongle: missing stock copy without a valid journal'; return 1; }
        fi
        return 0
    fi
    verify_stock_hash "$TARGET_HAL" || {
        log "FAIL dongle: unsupported or modified target HAL hash $(digest "$TARGET_HAL" 2>/dev/null)"
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
    mv -f "$stage" "$dst" || return 1
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
    for src in "$SCRIPT_DIR/../bin/gen5w-dongle-load" "$SCRIPT_DIR/../files/libhardware_legacy.so"; do
        [ -f "$src" ] && [ ! -L "$src" ] || return 1
        sum=$(digest "$src") || return 1
        case "${src##*/}" in gen5w-dongle-load) name=bin/gen5w-dongle-load;; *) name=lib/libhardware_legacy.so;; esac
        echo "$sum|$name"
    done
}
aux_safe_dirs() {
    local dir
    for dir in "$SYS" "$SYS/lib" "$SYS/wifi" "$MOD_DIR" "$SYS/etc" "$FW_DIR" "$SYS/bin" "$SYS/etc/gen5w-kr-backup" "$BACKUP_DURABLE" "$DATA" "$DATA/nemesis" "$DATA/nemesis/backup" "$BACKUP_RUNTIME"; do
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
        case "$rel" in wifi/dongle/gen5w-average.ko|wifi/dongle/ccm.ko|wifi/dongle/ctr.ko|wifi/dongle/seqiv.ko|wifi/dongle/mac80211.ko|wifi/dongle/ath.ko|wifi/dongle/ath9k_hw.ko|wifi/dongle/ath9k_common.ko|wifi/dongle/ath9k_htc.ko|etc/firmware/htc_9271.fw|etc/firmware/htc_7010.fw|bin/gen5w-dongle-load|lib/libhardware_legacy.so) ;; *) return 1;; esac
        case "$rel" in *..*|*[!a-zA-Z0-9_./-]*) return 1;; esac
        case "$seen" in *"|$rel|"*) return 1;; esac
        seen="$seen$rel|"; path=$SYS/$rel
        [ ! -L "$path" ] || return 1
        if [ -e "$path" ]; then
            [ -f "$path" ] || return 1
            [ "$(digest "$path")" = "$sum" ] || { [ "$rel" = lib/libhardware_legacy.so ] && verify_stock_hash "$path"; } || return 1
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
        [ ! -e "$BACKUP_DURABLE" ] && [ ! -L "$BACKUP_DURABLE" ] && [ ! -e "$STOCK_HAL" ] && [ ! -L "$STOCK_HAL" ] || return 1
        while IFS='|' read -r sum rel extra; do
            [ "$rel" = lib/libhardware_legacy.so ] && continue
            [ ! -e "$SYS/$rel" ] && [ ! -L "$SYS/$rel" ] || { log "FAIL dongle: pre-existing target $rel"; return 1; }
        done <<EOF
$listing
EOF
    fi
}
