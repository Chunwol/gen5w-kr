#!/system/bin/sh
SCRIPT_DIR=${0%/*}
[ "$SCRIPT_DIR" != "$0" ] || SCRIPT_DIR=.
. "$SCRIPT_DIR/../scripts/common.sh"

echo "Dongle HW detected: $(has_dongle_hw && echo yes || echo no)"
echo "Dongle backend active: $([ "$(getprop persist.gen5w.wifi.backend 2>/dev/null)" = "dongle" ] && echo yes || echo no)"
echo "WLAN0 interface: $([ -e /sys/class/net/wlan0 ] && echo yes || echo no)"
echo "HAL adapter installed: $([ -f "$STOCK_HAL" ] && echo yes || echo no)"
exit 0
