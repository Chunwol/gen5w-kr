#!/system/bin/sh
SCRIPT_DIR=${0%/*}
[ "$SCRIPT_DIR" != "$0" ] || SCRIPT_DIR=.
. "$SCRIPT_DIR/common.sh"
stock_systemui || { log 'SKIP timer: SystemUI.odex is not a recognised stock file'; exit 77; }
log 'READY timer: stock SystemUI identified; no system file will change'
exit 0
