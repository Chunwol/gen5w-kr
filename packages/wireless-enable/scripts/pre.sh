#!/system/bin/sh
. ./scripts/common.sh
log "=== preinstall gen5w.kr.wireless $(date 2>/dev/null) firmware=$(getprop ro.build.product 2>/dev/null)"
preserve_existing_or_skip() {
    _installed=$DATA/nemesis/apps/gen5w.kr.wireless
    if [ -e "$STATE" ] || [ -L "$STATE" ] || [ -e "$_installed" ] || [ -L "$_installed" ] || [ -e "$MARK" ] || [ -L "$MARK" ]; then
        [ -d "$_installed" ] && [ ! -L "$_installed" ] &&
        [ -f "$_installed/NEMESIS.data" ] && [ ! -L "$_installed/NEMESIS.data" ] &&
        grep -q '^id=gen5w\.kr\.wireless$' "$_installed/NEMESIS.data" &&
        [ -f "$STATE/complete" ] && [ ! -L "$STATE/complete" ] && state_check || {
            log 'FAIL: existing wireless ownership or recovery state is incomplete'
            exit 1
        }
        log 'Wireless detection inconclusive; preserve verified existing configuration'
        toast '무선 기능을 확인하지 못해 기존 설정을 유지합니다.'
        exit 78
    fi
    log 'Wireless detection inconclusive; no prior configuration to preserve'
    toast '무선 기능을 확인하지 못해 제외합니다.'
    exit 77
}
if ! has_wireless_code; then
    log 'Wireless projection capability could not be confirmed'
    preserve_existing_or_skip
fi
_w=$(wifi_hw)
if [ $? -ne 0 ]; then
    log "FAIL: temporary Wi-Fi probe could not restore the original disabled state"
    toast "Wi-Fi 확인 후 원래 상태 복원에 실패해 설치를 중단합니다."
    exit 1
fi
if [ "$_w" = unknown ]; then
    preserve_existing_or_skip
fi
state_load || exit 1
if [ -s "$MARK/saved" ]; then
    log "already installed (backup present) - reinstall allowed"
fi
[ -x "$NEM" ] || { log "FAIL: nemesis missing"; exit 1; }
log "checks OK (wireless code present, wifi=$_w)"
exit 0
