#!/system/bin/sh
HOLD_SCRIPT=${0%/*}/install-hold.sh
. "$HOLD_SCRIPT"
install_hold && exit 0
# NEMESIS starts this process as system; no nested root helper survives removal.
SCRIPT_DIR=${0%/*}
[ "$SCRIPT_DIR" != "$0" ] || SCRIPT_DIR=.
PACKAGE_DIR=$(cd "$SCRIPT_DIR/.." && pwd) || exit 1
export CLASSPATH=$PACKAGE_DIR/app/gen5w-core.apk
exec /system/bin/app_process /system/bin kr.gen5w.core.StockOwner
