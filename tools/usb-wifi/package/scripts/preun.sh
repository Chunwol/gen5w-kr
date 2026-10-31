#!/system/bin/sh
SCRIPT_DIR=${0%/*}
[ "$SCRIPT_DIR" != "$0" ] || SCRIPT_DIR=.
. "$SCRIPT_DIR/common.sh"

is_owned && aux_manifest_valid || { log 'FAIL dongle: missing or changed file ownership journal'; exit 1; }
if [ -e "$STOCK_HAL" ] || [ -L "$STOCK_HAL" ]; then
    verify_stock_hash "$STOCK_HAL" || { log 'FAIL dongle: stock copy changed'; exit 1; }
fi
command -v getprop >/dev/null 2>&1 && command -v setprop >/dev/null 2>&1 || exit 1
backend_original=$(cat "$BACKUP_DURABLE/backend.original") || exit 1
backend_current=$(getprop persist.gen5w.wifi.backend) || exit 1
[ "$backend_current" = dongle ] || [ "$backend_current" = "$backend_original" ] || { log 'FAIL dongle: backend setting changed'; exit 1; }

sys_rw || { log "FAIL dongle: cannot remount /system rw"; exit 1; }
trap 'sys_ro' EXIT
trap 'exit 1' HUP INT TERM

# 1. Restore original HAL
ORIG_SRC=""
if [ -f "$BACKUP_DURABLE/original" ] && [ ! -L "$BACKUP_DURABLE/original" ]; then
    ORIG_SRC="$BACKUP_DURABLE/original"
elif [ -f "$BACKUP_RUNTIME/original" ] && [ ! -L "$BACKUP_RUNTIME/original" ]; then
    ORIG_SRC="$BACKUP_RUNTIME/original"
elif [ -f "$STOCK_HAL" ] && [ ! -L "$STOCK_HAL" ]; then
    ORIG_SRC="$STOCK_HAL"
fi

if [ -z "$ORIG_SRC" ] || [ ! -f "$ORIG_SRC" ] || [ -L "$ORIG_SRC" ]; then
    log "FAIL dongle: no stock HAL backup available to restore"
    exit 1
fi

verify_stock_hash "$ORIG_SRC" || { log "FAIL dongle: corrupted stock source on uninstall"; exit 1; }
install_owned_file "$ORIG_SRC" "$TARGET_HAL" original || exit 1

# 2. Remove stock HAL copy
rm -f "$STOCK_HAL" || { log 'FAIL dongle: cannot remove stock copy'; exit 1; }
[ ! -e "$STOCK_HAL" ] && [ ! -L "$STOCK_HAL" ] || exit 1

# 3. Remove only validated files installed by this package. Preserve unrelated files.
while IFS='|' read -r sum rel extra; do
    [ "$rel" = lib/libhardware_legacy.so ] && continue
    rm -f "$SYS/$rel" || exit 1
done < "$BACKUP_DURABLE/files"
rmdir "$MOD_DIR" 2>/dev/null || true

# 6. Reset property
setprop persist.gen5w.wifi.backend "$backend_original" 2>/dev/null &&
[ "$(getprop persist.gen5w.wifi.backend 2>/dev/null)" = "$backend_original" ] || { log 'FAIL dongle: backend restore not confirmed'; exit 1; }

# 7. Clean up backup trees
rm -rf "$BACKUP_RUNTIME" 2>/dev/null || exit 1
rm -rf "$BACKUP_DURABLE" 2>/dev/null || exit 1

sync
sys_ro || exit 1
trap - EXIT

log "UNINSTALLED dongle: stock HAL restored byte-identical"
exit 0
