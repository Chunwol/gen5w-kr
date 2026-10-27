#!/system/bin/sh
SCRIPT_DIR=${0%/*}
[ "$SCRIPT_DIR" != "$0" ] || SCRIPT_DIR=.
. "$SCRIPT_DIR/common.sh"

sys_rw || { log "FAIL dongle: cannot remount /system rw"; exit 1; }
trap 'sys_ro' EXIT
trap 'exit 1' HUP INT TERM

# 1. Restore original HAL
ORIG_SRC=""
if [ -f "$BACKUP_DURABLE/original" ]; then
    ORIG_SRC="$BACKUP_DURABLE/original"
elif [ -f "$BACKUP_RUNTIME/original" ]; then
    ORIG_SRC="$BACKUP_RUNTIME/original"
elif [ -f "$STOCK_HAL" ]; then
    ORIG_SRC="$STOCK_HAL"
fi

if [ -n "$ORIG_SRC" ] && [ -f "$ORIG_SRC" ]; then
    cp -p "$ORIG_SRC" "$TARGET_HAL.tmp" || exit 1
    chmod 644 "$TARGET_HAL.tmp" || true
    chown 0:0 "$TARGET_HAL.tmp" 2>/dev/null || true
    mv -f "$TARGET_HAL.tmp" "$TARGET_HAL" || exit 1
fi

# 2. Remove stock HAL copy
rm -f "$STOCK_HAL" || true

# 3. Remove installed modules
if [ -d "$MOD_DIR" ]; then
    rm -rf "$MOD_DIR" || true
fi

# 4. Remove installed firmware
rm -f "$FW_DIR/htc_9271.fw" "$FW_DIR/htc_7010.fw" 2>/dev/null || true

# 5. Remove loader script
rm -f "$LOADER_BIN" || true

# 6. Reset property
setprop persist.gen5w.wifi.backend "" 2>/dev/null || true

# 7. Clean up backup trees
rm -rf "$BACKUP_DURABLE" "$BACKUP_RUNTIME" 2>/dev/null || true

sync
sys_ro || exit 1
trap - EXIT

log "UNINSTALLED dongle: stock HAL restored byte-identical"
exit 0
