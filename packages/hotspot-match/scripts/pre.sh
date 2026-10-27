#!/system/bin/sh
# Gate: a Wi-Fi hotspot config with separate CarPlay ("Connectivity") values must
# exist on this unit; otherwise there is nothing to match and we do not install.
export PATH=${HM_TEST_PATH:-/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin}
LOG=${HM_TEST_LOG:-/data/nemesis/gen5w.kr.hotspot.log}
DEX=${HM_TEST_DEX:-$PWD/app/match.dex}
log() { echo "$1"; echo "$1" >> "$LOG" 2>/dev/null; true; }
out=$(CLASSPATH="$DEX" app_process /system/bin kr.gen5w.hotspot.HotspotMatch check 2>&1)
log "preinstall: observing saved CarPlay settings"
case "$out" in
    *"RESULT ready"*) log "CarPlay hotspot values present - checking native profile adapter"; exec "${PROFILE_TEST_SHELL:-/system/bin/sh}" "${0%/*}/profile-pre.sh" ;;
    *"carplay-settings-missing"*|*"no-ap-config"*|*"no-wifi-service"*)
       log "DEFERRED: saved profile or Wi-Fi service not ready; checking exact native support before installation"
       exec "${PROFILE_TEST_SHELL:-/system/bin/sh}" "${0%/*}/profile-pre.sh" ;;
    *) log "FAIL: CarPlay API observation failed"
       am broadcast -a com.hkmc.intent.action.TOAST -e com.hkmc.intent.extra.TOAST_MESSAGE "무선 설정 API를 확인하지 못해 이 기능을 제외합니다." --ez com.hkmc.intent.extra.TOAST_POPUPSHOWING true >/dev/null 2>&1
       exit 77 ;;
esac
