#!/system/bin/sh
# The preuninstall hook verifies and restores owned services ODEX bytes.
DATA=${PROFILE_TEST_DATA:-/data}
echo "gen5w.kr.hotspot disk restoration finished; reboot required for loaded services" >> "$DATA/nemesis/gen5w.kr.hotspot.log" 2>/dev/null
sync
[ -n "$PROFILE_TEST_SYS" ] || [ -f "$DATA/nemesis/gen5wkr.noreboot" ] || exec /system/bin/reboot
exit 0
