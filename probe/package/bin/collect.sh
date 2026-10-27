#!/system/bin/sh
# Copies the probe's log (and the matching logcat lines) to the USB drive.
# Read-only for the system: writes only to the USB drive.
export PATH=${GEN5W_TEST_PATH:-/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin}
USB=${PROBE_TEST_USB:-/storage/usb0}
SRC=${PROBE_TEST_SRC:-/data/data/kr.gen5w.probe/files}
STAMP=$(date +%Y%m%d-%H%M%S 2>/dev/null)
OUT=$USB/GEN5WKR_PROBE_$STAMP
toast() {
    am broadcast -a com.hkmc.intent.action.TOAST -e com.hkmc.intent.extra.TOAST_MESSAGE "$1" \
        --ez com.hkmc.intent.extra.TOAST_POPUPSHOWING true >/dev/null 2>&1
}
[ -d "$USB" ] || { echo "no USB drive at $USB"; exit 1; }
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
} > "$OUT/info.txt"
# probe lines and crashes only (the unit has no sed; mask MAC addresses on the PC before sharing)
logcat -d -v time 2>/dev/null | grep -E "Gen5wProbe|AndroidRuntime" > "$OUT/logcat.txt"
sync
echo "copied $n log files to $OUT"
toast "기록 $n개를 USB에 복사했습니다"
exit 0
