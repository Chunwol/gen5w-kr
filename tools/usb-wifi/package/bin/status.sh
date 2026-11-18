#!/system/bin/sh
BIN_DIR=${0%/*}
[ "$BIN_DIR" != "$0" ] || BIN_DIR=.
SCRIPT_DIR=$BIN_DIR/../scripts
. "$SCRIPT_DIR/common.sh"

echo "Dongle HW detected: $(has_dongle_hw && echo yes || echo no)"
echo "Dongle backend active: $([ "$(getprop persist.gen5w.wifi.backend 2>/dev/null)" = "dongle" ] && echo yes || echo no)"
echo "Dongle test mode: $([ "$(getprop gen5w.dongle.test 2>/dev/null)" = "1" ] && echo active || echo inactive)"
echo "WLAN0 interface: $([ -e /sys/class/net/wlan0 ] && echo yes || echo no)"
echo "bcmdhd stand-in installed: $([ "$(digest "$TARGET" 2>/dev/null)" = "$(digest "${0%/*}/../files/bcmdhd.ko" 2>/dev/null)" ] && echo yes || echo no)"
exit 0
