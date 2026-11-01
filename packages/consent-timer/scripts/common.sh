# Shared by pre.sh and timer.sh. mksh + Android toolbox only; writes no system file.
SYS=${TIMER_TEST_SYS:-/system}
PKG=$(cd "$SCRIPT_DIR/.." && pwd) || exit 1
TARGET=$SYS/priv-app/SystemUI.odex
log() { echo "$1"; }
# The log lines and the close request below were checked against these exact
# stock SystemUI builds only. Anything else keeps the stock 10 second timer.
stock_systemui() {
    local tool
    [ -f "$TARGET" ] && [ ! -L "$TARGET" ] || return 1
    for tool in "$PKG/bin/notice-patch-v039" "$PKG/bin/notice-patch-v035"; do
        [ -f "$tool" ] && [ ! -L "$tool" ] || continue
        chmod 755 "$tool" 2>/dev/null
        "$tool" original "$TARGET" >/dev/null 2>&1 && return 0
    done
    return 1
}
