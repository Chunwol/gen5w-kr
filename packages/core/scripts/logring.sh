#!/system/bin/sh
HOLD_SCRIPT=${0%/*}/install-hold.sh
. "$HOLD_SCRIPT"
install_hold_wait
# Keeps the recent Android log (main + system buffers) on /data so a wireless
# failure can be read later from a USB diagnosis. Bounded: logcat itself rotates
# 5 files of 2 MiB (10 MiB). The script becomes logcat (exec), so a NEMESIS stop ends it
# with no child left behind. Exports copy it whole, unfiltered; this
# directory is root-only and is deleted when the HUD package is removed.
DATA=${LOGRING_TEST_DATA:-/data}
LOGCAT=${LOGRING_TEST_LOGCAT:-/system/bin/logcat}
GETPROP=${LOGRING_TEST_GETPROP:-getprop}
DF=${LOGRING_TEST_DF:-df}
DIR=$DATA/nemesis/gen5wkr.logs
MIN_FREE_KB=102400
until [ "$("$GETPROP" sys.boot_completed 2>/dev/null)" = 1 ]; do sleep 5; done
# Free space on /data in KiB, from toolbox df ("/data  991.9M  104.8M  887.1M  4096").
free_kb() {
    typeset line fs size used free unit n
    line=$("$DF" "$DATA" 2>/dev/null | while IFS= read -r l; do case "$l" in Filesystem*) ;; *) print -r -- "$l";; esac; done)
    set -- $line
    [ "$#" -ge 4 ] || return 1
    free=$4
    case "$free" in
        *G) unit=1048576;; *M) unit=1024;; *K) unit=1;;
        *[!0-9]*) return 1;; *) unit=1;;
    esac
    n=${free%[GMK]}
    case "$n" in ''|*[!0-9.]*) return 1;; esac
    n=${n%%.*}
    [ -n "$n" ] || n=0
    echo $((n * unit))
}
kb=$(free_kb) || { echo 'logring: /data free space unknown; not recording'; exec sleep 2147483647; }
if [ "$kb" -lt "$MIN_FREE_KB" ]; then
    echo "logring: /data free ${kb}K below ${MIN_FREE_KB}K; not recording"
    # Stay alive (one process, no restart loop) so NEMESIS does not retry.
    exec sleep 2147483647
fi
[ ! -L "$DATA/nemesis" ] && [ ! -L "$DIR" ] || { echo 'logring: linked path refused'; exec sleep 2147483647; }
mkdir -p "$DIR" && chmod 700 "$DIR" || { echo 'logring: cannot prepare log directory'; exec sleep 2147483647; }
for f in "$DIR"/logcat.txt "$DIR"/logcat.txt.*; do
    [ ! -L "$f" ] || { echo 'logring: linked log file refused'; exec sleep 2147483647; }
done
echo "logring: recording free=${kb}K"
exec "$LOGCAT" -b main -b system -v time -f "$DIR/logcat.txt" -r 2048 -n 4 '*:D'
