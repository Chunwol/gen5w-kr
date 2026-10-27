#!/system/bin/sh
# check | apply the hotspot<->CarPlay name match. Runs the program as system.
export CLASSPATH=${HM_TEST_DEX:-${0%/*}/../app/match.dex}
exec app_process /system/bin kr.gen5w.hotspot.HotspotMatch "${1:-check}"
