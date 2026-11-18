#!/system/bin/sh
SCRIPT_DIR=${0%/*}
[ "$SCRIPT_DIR" != "$0" ] || SCRIPT_DIR=.
. "$SCRIPT_DIR/common.sh"

if [ ! -e "$BACKUP_DURABLE" ] && [ ! -L "$BACKUP_DURABLE" ] && [ -e "$BACKUP_RUNTIME" ]; then
    clear_stale_runtime || { log 'FAIL dongle: our files are live without their system journal'; exit 1; }
fi
verify_stock_target || exit 1
aux_install_check || { log 'FAIL dongle: file collision or unknown ownership'; exit 1; }

sys_rw || { log "FAIL dongle: cannot remount /system rw"; exit 1; }
trap 'sys_ro' EXIT
trap 'exit 1' HUP INT TERM

# 1. Back up stock library if not already backed up
mkdir -p "${BACKUP_DURABLE%/*}" "${BACKUP_RUNTIME%/*}" || exit 1
if [ ! -e "$BACKUP_DURABLE" ]; then
    stage="$BACKUP_DURABLE.tmp.$$"
    [ ! -e "$stage" ] && [ ! -L "$stage" ] && mkdir "$stage" || exit 1
    cp -p "$TARGET" "$stage/original" || exit 1
    verify_stock_hash "$stage/original" || exit 1
    echo "$OWNER" > "$stage/owner" || exit 1
    chmod 600 "$stage/owner" || exit 1
    aux_payload_manifest > "$stage/files" || exit 1
    [ -s "$stage/files" ] || exit 1
    digest "$stage/files" > "$stage/files.md5" || exit 1
    getprop persist.gen5w.wifi.backend > "$stage/backend.original" || exit 1
    digest "$stage/backend.original" > "$stage/backend.md5" || exit 1
    sync
    mv "$stage" "$BACKUP_DURABLE" || exit 1
    sync
fi
if [ ! -e "$BACKUP_RUNTIME" ]; then
    runtime_stage="$BACKUP_RUNTIME.tmp.$$"
    [ ! -e "$runtime_stage" ] && [ ! -L "$runtime_stage" ] && mkdir "$runtime_stage" || exit 1
    cp -p "$BACKUP_DURABLE/original" "$runtime_stage/original" || exit 1
    echo "$OWNER" > "$runtime_stage/owner" || exit 1
    sync
    mv "$runtime_stage" "$BACKUP_RUNTIME" || exit 1
    sync
fi

# 2. Put the stand-in module where the stock HAL loads the Broadcom driver
SHIM_SRC="$SCRIPT_DIR/../files/bcmdhd.ko"
[ -f "$SHIM_SRC" ] || { log "FAIL dongle: missing bcmdhd stand-in module payload"; exit 1; }
install_owned_file "$SHIM_SRC" "$TARGET" 644 || exit 1

# 4. Install kernel modules
mkdir -p "$MOD_DIR" || exit 1
[ -d "$SCRIPT_DIR/../files/modules" ] || { log "FAIL dongle: missing modules directory"; exit 1; }
module_count=0
for m in "$SCRIPT_DIR/../files/modules"/*.ko; do
    [ -f "$m" ] || continue
    install_owned_file "$m" "$MOD_DIR/${m##*/}" 644 || exit 1
    module_count=$((module_count + 1))
done
[ "$module_count" -gt 0 ] || { log "FAIL dongle: zero kernel modules installed"; exit 1; }
for meta in modules.alias modules.profile; do
    [ -f "$SCRIPT_DIR/../files/modules/$meta" ] || { log "FAIL dongle: missing driver catalog $meta"; exit 1; }
    install_owned_file "$SCRIPT_DIR/../files/modules/$meta" "$MOD_DIR/$meta" 644 || exit 1
done

install_firmware_tree() {
    local srcdir=$1 relbase=$2 entry name
    for entry in "$srcdir"/*; do
        [ -e "$entry" ] || continue
        [ ! -L "$entry" ] || return 1
        name=${entry##*/}
        case "$name" in ''|*[!a-zA-Z0-9_.-]*) return 1;; esac
        if [ -d "$entry" ]; then
            mkdir -p "$FW_DIR/$relbase/$name" || return 1
            install_firmware_tree "$entry" "$relbase/$name" || return 1
        elif [ -f "$entry" ]; then
            mkdir -p "$FW_DIR/$relbase" || return 1
            install_owned_file "$entry" "$FW_DIR/$relbase/$name" 644 || return 1
        else
            return 1
        fi
    done
}

# 5. Install firmware
mkdir -p "$FW_DIR" || exit 1
[ -d "$SCRIPT_DIR/../files/firmware" ] || { log "FAIL dongle: missing firmware directory"; exit 1; }
install_firmware_tree "$SCRIPT_DIR/../files/firmware" '' || { log "FAIL dongle: firmware installation failed"; exit 1; }

# 6. Install loader script
LOADER_SRC="$SCRIPT_DIR/../bin/gen5w-dongle-load"
if [ -f "$LOADER_SRC" ]; then
    install_owned_file "$LOADER_SRC" "$LOADER_BIN" 755 || exit 1
fi

# 7. Configure backend property
setprop persist.gen5w.wifi.backend dongle 2>/dev/null &&
[ "$(getprop persist.gen5w.wifi.backend 2>/dev/null)" = dongle ] || { log 'FAIL dongle: backend setting not confirmed'; exit 1; }

sync
sys_ro || exit 1
trap - EXIT

log "APPLIED dongle: driver installed; stock Wi-Fi HAL unchanged"
exit 0
