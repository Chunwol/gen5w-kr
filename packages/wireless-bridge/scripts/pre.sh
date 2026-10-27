#!/system/bin/sh
SCRIPT_DIR=${0%/*}
[ "$SCRIPT_DIR" != "$0" ] || SCRIPT_DIR=.
. "$SCRIPT_DIR/common.sh"
inspect || exit $?
[ -f "$SCRIPT_DIR/../app/bridge.dex" ] && [ ! -L "$SCRIPT_DIR/../app/bridge.dex" ] &&
    [ -f "$SYS/framework/com.tcc.iap2.jar" ] || { log 'FAIL bridge: daemon or iAP2 runtime absent'; exit 1; }
log 'READY bridge: exact stock APK/ODEX pair and recovery ownership verified'
