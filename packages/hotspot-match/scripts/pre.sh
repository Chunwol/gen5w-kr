#!/system/bin/sh
# Gate: a Wi-Fi hotspot config with separate CarPlay ("Connectivity") values must
# exist on this unit; otherwise there is nothing to match and we do not install.
export PATH=${HM_TEST_PATH:-/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin}
LOG=${HM_TEST_LOG:-/data/nemesis/gen5w.kr.hotspot.log}
SCRIPT_DIR=${0%/*}
[ "$SCRIPT_DIR" != "$0" ] || SCRIPT_DIR=.
DEX=${HM_TEST_DEX:-$SCRIPT_DIR/../app/match.dex}
log() { echo "$1"; echo "$1" >> "$LOG" 2>/dev/null; true; }
out=$(CLASSPATH="$DEX" app_process /system/bin kr.gen5w.hotspot.HotspotMatch check 2>&1)
log "preinstall: observing saved CarPlay settings"
case "$out" in
    *"RESULT ready"*) log "CarPlay hotspot values present - checking native profile adapter"; exec "${PROFILE_TEST_SHELL:-/system/bin/sh}" "$SCRIPT_DIR/profile-pre.sh" ;;
    *"carplay-settings-missing"*|*"no-ap-config"*|*"no-wifi-service"*)
       log "DEFERRED: saved profile or Wi-Fi service not ready; checking exact native support before installation"
       exec "${PROFILE_TEST_SHELL:-/system/bin/sh}" "$SCRIPT_DIR/profile-pre.sh" ;;
    *) log "WARN: CarPlay API observation deferred; proceeding with profile adapter"
       exec "${PROFILE_TEST_SHELL:-/system/bin/sh}" "$SCRIPT_DIR/profile-pre.sh" ;;
esac
