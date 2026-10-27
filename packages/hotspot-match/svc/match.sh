#!/system/bin/sh
# Boot-time observation only. The Bluetooth bridge owns AP activation.
# Never replace an ordinary hotspot just because startup settings differ.
export PATH=${HM_TEST_PATH:-/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin}
DEX=${HM_TEST_DEX:-${0%/*}/../app/match.dex}
LOG=${HM_TEST_LOG:-/data/nemesis/gen5w.kr.hotspot.log}
run() { CLASSPATH=$DEX app_process /system/bin kr.gen5w.hotspot.HotspotMatch "$1" 2>&1; }
log() { echo "$1" >> "$LOG" 2>/dev/null; true; }

log "=== match service $(date 2>/dev/null)"
i=0
while [ $i -lt 30 ]; do
    out=$(run check)
    log "check: $out"
    case "$out" in
        *"RESULT ready"*|*"RESULT match"*|*"RESULT mismatch"*) log "settings observed; AP activation belongs to the connection session"; exit 0 ;;
        *)
            if [ $i -lt 5 ]; then
                sleep 1
            else
                sleep 2
            fi
            i=$((i+1))
            ;;
    esac
done
log 'settings unavailable; no AP change'
exit 1
