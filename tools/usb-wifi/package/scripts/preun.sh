#!/system/bin/sh
SCRIPT_DIR=${0%/*}
[ "$SCRIPT_DIR" != "$0" ] || SCRIPT_DIR=.
. "$SCRIPT_DIR/common.sh"

# No system journal at all: nothing on /system is ours to restore.
if [ ! -e "$BACKUP_DURABLE" ] && [ ! -L "$BACKUP_DURABLE" ]; then
    clear_stale_runtime || { log 'FAIL dongle: our files are live without their system journal'; exit 1; }
    exit 0
fi
is_owned && aux_manifest_valid || { log 'FAIL dongle: missing or changed file ownership journal'; exit 1; }
command -v getprop >/dev/null 2>&1 && command -v setprop >/dev/null 2>&1 || exit 1
backend_original=$(cat "$BACKUP_DURABLE/backend.original") || exit 1
backend_current=$(getprop persist.gen5w.wifi.backend) || exit 1
[ "$backend_current" = dongle ] || [ "$backend_current" = "$backend_original" ] || { log 'FAIL dongle: backend setting changed'; exit 1; }

sys_rw || { log "FAIL dongle: cannot remount /system rw"; exit 1; }
trap 'sys_ro' EXIT
trap 'exit 1' HUP INT TERM

# 1. Restore the stock Broadcom module
ORIG_SRC=""
if [ -f "$BACKUP_DURABLE/original" ] && [ ! -L "$BACKUP_DURABLE/original" ] && verify_stock_hash "$BACKUP_DURABLE/original"; then
    ORIG_SRC="$BACKUP_DURABLE/original"
elif [ -f "$BACKUP_RUNTIME/original" ] && [ ! -L "$BACKUP_RUNTIME/original" ] && verify_stock_hash "$BACKUP_RUNTIME/original"; then
    ORIG_SRC="$BACKUP_RUNTIME/original"
fi
[ -n "$ORIG_SRC" ] || { log "FAIL dongle: no stock bcmdhd.ko backup available to restore"; exit 1; }
install_owned_file "$ORIG_SRC" "$TARGET" original || exit 1

# 3. Remove only validated files installed by this package. Preserve unrelated files.
while IFS='|' read -r sum rel extra; do
    [ "$rel" = wifi/bcmdhd.ko ] && continue
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

log "UNINSTALLED dongle: stock bcmdhd.ko restored byte-identical"
exit 0
