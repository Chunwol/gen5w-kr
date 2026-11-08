# Shared by pre.sh and timer.sh. mksh + Android toolbox only; writes no system file.
SYS=${TIMER_TEST_SYS:-/system}
. "$SCRIPT_DIR/errors.sh"
PKG=$(cd "$SCRIPT_DIR/.." && pwd) || exit 1
TARGET=$SYS/priv-app/SystemUI.odex
# Set from the in-car screen: the stock 10 second timer then runs unchanged.
UI_OFF=${TIMER_TEST_DATA:-/data}/nemesis/gen5wkr.ui-timer-off
log() { echo "$1"; }
# The log lines and the close request below were checked against these exact
# stock SystemUI builds only (SHA-256). Anything else keeps the stock 10 seconds.
SYSTEMUI_V039=97e7e258df34d76ed61a714f83de4bf0fbc3d6b6188055c941ad2689f72595af
SYSTEMUI_V035=3de39c29f10c8db3ec786f59378f5b716b04e6be473b42989f40ef828ef0867b
stock_systemui() {
    local tool=$PKG/bin/sha256-check sum
    [ -f "$TARGET" ] && [ ! -L "$TARGET" ] && [ -f "$tool" ] && [ ! -L "$tool" ] || return 1
    chmod 755 "$tool" 2>/dev/null
    for sum in $SYSTEMUI_V039 $SYSTEMUI_V035; do
        "$tool" verify "$TARGET" "$sum" >/dev/null 2>&1 && return 0
    done
    return 1
}
