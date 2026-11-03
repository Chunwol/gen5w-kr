#!/system/bin/sh
# Copies probe and consent diagnostics to USB. Optional expanded debugging is
# enabled by a GEN5W-DEBUG-ON marker in the USB root; no system setting changes.
export PATH=${GEN5W_TEST_PATH:-/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin}
USB=${PROBE_TEST_USB:-/storage/usb0}
SRC=${PROBE_TEST_SRC:-/data/data/kr.gen5w.probe/files}
TIMER_LOG=${PROBE_TEST_TIMER_LOG:-/data/nemesis/logs/gen5w.kr.timer/timer.log}
STAMP=${PROBE_TEST_STAMP:-$(date +%Y%m%d-%H%M%S 2>/dev/null)}
OUT=$USB/GEN5WKR_PROBE_$STAMP
toast() {
    am broadcast -a com.hkmc.intent.action.TOAST -e com.hkmc.intent.extra.TOAST_MESSAGE "$1" \
        --ez com.hkmc.intent.extra.TOAST_POPUPSHOWING true >/dev/null 2>&1
}
[ -d "$USB" ] || { echo "no USB drive at $USB"; exit 1; }
[ -L "$USB" ] && { echo "refusing USB symlink"; exit 1; }
if [ -e "$OUT" ] || [ -L "$OUT" ]; then
    n=1
    while [ -e "${OUT}_$n" ] || [ -L "${OUT}_$n" ]; do n=$((n+1)); done
    OUT=${OUT}_$n
fi
mkdir -p "$OUT" || exit 1
n=0
for f in "$SRC"/probe.log*; do
    [ -f "$f" ] || continue
    cat "$f" > "$OUT/${f##*/}" && n=$((n+1))
done
{
    echo "date=$(date 2>/dev/null)"
    echo "product=$(getprop ro.build.product)"
    echo "files=$n"
    if [ -f "$USB/GEN5W-DEBUG-ON" ] && [ ! -L "$USB/GEN5W-DEBUG-ON" ] &&
       [ ! -e "$USB/GEN5W-DEBUG-OFF" ] && [ ! -L "$USB/GEN5W-DEBUG-OFF" ]; then
        DEBUG=on
    else
        DEBUG=off
    fi
    echo "debug=$DEBUG"
} > "$OUT/info.txt"
# Always capture the two sources needed to explain why the start-up notice did
# or did not close. The consent state is emitted by stock SystemUI in system.
logcat -d -v time 2>/dev/null | grep -E "Gen5wProbe|AndroidRuntime" > "$OUT/logcat.txt"
logcat -d -v time -b system -s ConsentScreen:V > "$OUT/consent.log" 2>&1
if [ -f "$TIMER_LOG" ] && [ ! -L "$TIMER_LOG" ]; then
    cat "$TIMER_LOG" > "$OUT/timer.log"
else
    echo 'timer log unavailable' > "$OUT/timer.log"
fi
if [ "$DEBUG" = on ]; then
    {
        echo 'Expanded diagnostic capture. Review for personal/device identifiers before sharing.'
        for buffer in main system radio events crash; do
            echo "== logcat $buffer =="
            logcat -d -v time -b "$buffer" 2>&1
        done
        echo '== dmesg =='
        dmesg 2>&1
        for service in bluetooth_manager wifi connectivity; do
            echo "== dumpsys $service =="
            dumpsys "$service" 2>&1
        done
        echo '== service list =='
        service list 2>&1
        echo '== relevant processes =='
        ps 2>&1 | grep -i -E 'gen5w|probe|timer|bridge|dipo|iap2|gpm|hostapd|wpa|bluetooth'
    } > "$OUT/DEBUG.txt"
fi
sync
echo "copied $n log files to $OUT"
if [ "$DEBUG" = on ]; then
    toast "상세 진단 로그를 USB에 저장했습니다. 공유 전에 DEBUG.txt의 개인정보를 확인하세요"
else
    toast "시동 안내 진단 로그를 USB에 저장했습니다"
fi
exit 0
