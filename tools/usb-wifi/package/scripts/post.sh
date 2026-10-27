#!/system/bin/sh
SCRIPT_DIR=${0%/*}
[ "$SCRIPT_DIR" != "$0" ] || SCRIPT_DIR=.
. "$SCRIPT_DIR/common.sh"

verify_stock_target || exit 1

sys_rw || { log "FAIL dongle: cannot remount /system rw"; exit 1; }
trap 'sys_ro' EXIT
trap 'exit 1' HUP INT TERM

# 1. Back up stock library if not already backed up
mkdir -p "$BACKUP_DURABLE" "$BACKUP_RUNTIME" || exit 1
if [ ! -f "$BACKUP_DURABLE/original" ]; then
    cp -p "$TARGET_HAL" "$BACKUP_DURABLE/original" || exit 1
    echo "$OWNER" > "$BACKUP_DURABLE/owner" || exit 1
    chmod 600 "$BACKUP_DURABLE/owner" "$BACKUP_DURABLE/original" || true
fi
cp -p "$BACKUP_DURABLE/original" "$BACKUP_RUNTIME/original" || exit 1
echo "$OWNER" > "$BACKUP_RUNTIME/owner" || exit 1

# 2. Place stock HAL at STOCK_HAL path so adapter can dlopen it
if [ ! -f "$STOCK_HAL" ]; then
    cp -p "$BACKUP_DURABLE/original" "$STOCK_HAL" || exit 1
    chmod 644 "$STOCK_HAL" || true
    chown 0:0 "$STOCK_HAL" 2>/dev/null || true
fi

# 3. Install adapter library as TARGET_HAL
ADAPTER_SRC="$SCRIPT_DIR/../files/libhardware_legacy.so"
if [ -f "$ADAPTER_SRC" ]; then
    cp -p "$ADAPTER_SRC" "$TARGET_HAL.tmp" || exit 1
    chmod 644 "$TARGET_HAL.tmp" || true
    chown 0:0 "$TARGET_HAL.tmp" 2>/dev/null || true
    mv -f "$TARGET_HAL.tmp" "$TARGET_HAL" || exit 1
fi

# 4. Install kernel modules
mkdir -p "$MOD_DIR" || exit 1
if [ -d "$SCRIPT_DIR/../files/modules" ]; then
    for m in "$SCRIPT_DIR/../files/modules"/*.ko; do
        [ -f "$m" ] || continue
        cp -p "$m" "$MOD_DIR/" || exit 1
        chmod 644 "$MOD_DIR/${m##*/}" || true
        chown 0:0 "$MOD_DIR/${m##*/}" 2>/dev/null || true
    done
fi

# 5. Install firmware
mkdir -p "$FW_DIR" || exit 1
if [ -d "$SCRIPT_DIR/../files/firmware" ]; then
    for f in "$SCRIPT_DIR/../files/firmware"/*; do
        [ -f "$f" ] || continue
        cp -p "$f" "$FW_DIR/" || exit 1
        chmod 644 "$FW_DIR/${f##*/}" || true
        chown 0:0 "$FW_DIR/${f##*/}" 2>/dev/null || true
    done
fi

# 6. Install loader script
LOADER_SRC="$SCRIPT_DIR/../bin/gen5w-dongle-load"
if [ -f "$LOADER_SRC" ]; then
    cp -p "$LOADER_SRC" "$LOADER_BIN" || exit 1
    chmod 755 "$LOADER_BIN" || true
    chown 0:0 "$LOADER_BIN" 2>/dev/null || true
fi

# 7. Configure backend property
setprop persist.gen5w.wifi.backend dongle 2>/dev/null || true

sync
sys_ro || exit 1
trap - EXIT

log "APPLIED dongle: adapter and driver installed"
exit 0
