#!/system/bin/sh
SCRIPT_DIR=${0%/*}
[ "$SCRIPT_DIR" != "$0" ] || SCRIPT_DIR=.
. "$SCRIPT_DIR/common.sh"
stock_apps || { log 'SKIP bluelink: Bluelink apps are not the checked stock V039 build'; exit 77; }
log 'READY bluelink: stock V039 Bluelink apps identified; no system file will change'
exit 0
