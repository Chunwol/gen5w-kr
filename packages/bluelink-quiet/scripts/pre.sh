#!/system/bin/sh
SCRIPT_DIR=${0%/*}
[ "$SCRIPT_DIR" != "$0" ] || SCRIPT_DIR=.
. "$SCRIPT_DIR/common.sh"
# The two md5 values name only stock system files, so they are safe to log; they show what this unit has.
stock_apps || { log "SKIP bluelink: Bluelink apps are not the checked stock V039 build (VRM=$(file_md5 "$SYS/app/HKMC_TAppVRM.odex") SERVICE=$(file_md5 "$SYS/app/HKMC_TAppService.odex"))"; exit 77; }
log 'READY bluelink: stock V039 Bluelink apps identified; no system file will change'
exit 0
