#!/system/bin/sh
. ./scripts/common.sh
log "=== preinstall gen5w.kr.wireless $(date 2>/dev/null) firmware=$(getprop ro.build.product 2>/dev/null)"
if ! has_wireless_code; then
    log "FAIL: no wireless projection code in the stock apps on this unit"
    toast "무선 기능을 확인하지 못해 제외합니다."
    exit 77
fi
_w=$(wifi_hw)
if [ $? -ne 0 ]; then
    log "FAIL: temporary Wi-Fi probe could not restore the original disabled state"
    toast "Wi-Fi 확인 후 원래 상태 복원에 실패해 설치를 중단합니다."
    exit 1
fi
if [ "$_w" = unknown ]; then
    log "FAIL: Wi-Fi chip state unknown - no changes made"
    toast "Wi-Fi 하드웨어를 확인하지 못해 무선 기능을 제외합니다."
    exit 77
fi
state_load || exit 1
if [ -s "$MARK/saved" ]; then
    log "already installed (backup present) - reinstall allowed"
fi
[ -x "$NEM" ] || { log "FAIL: nemesis missing"; exit 1; }
log "checks OK (wireless code present, wifi=$_w)"
exit 0
