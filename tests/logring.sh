#!/bin/bash
# logring: bounded logcat on /data that becomes logcat itself (no child left).
cd "$(dirname "$0")/.." || exit 1
. tests/lib.sh
W=$(mktemp -d)
mkdir -p "$W/data/nemesis"
printf '#!/bin/sh\necho 1\n' > "$W/getprop"
printf '#!/bin/sh\necho "pid=$$ $*" > "$LR_OUT"\n' > "$W/logcat"
printf '#!/bin/sh\necho "Filesystem Size Used Free Blksize"\necho "/data 991.9M 104.8M ${LR_FREE:-887.1M} 4096"\n' > "$W/df"
chmod +x "$W/getprop" "$W/logcat" "$W/df"
run() {
    LR_OUT="$W/args" LOGRING_TEST_DATA="$W/data" LOGRING_TEST_LOGCAT="$W/logcat" LOGRING_TEST_GETPROP="$W/getprop" \
        LOGRING_TEST_DF="$W/df" IT_DATA="$W/data" timeout 3 mksh packages/core/scripts/logring.sh > "$W/out" 2>&1
}
rm -f "$W/args"; run
check 'records with logcat rotation capped at 4 x 1 MiB' grep -q -- '-f '"$W"'/data/nemesis/gen5wkr.logs/logcat.txt -r 1024 -n 3' "$W/args"
check 'main and system buffers are kept' grep -q -- '-b main -b system' "$W/args"
check 'log folder is root-only' test "$(stat -c %a "$W/data/nemesis/gen5wkr.logs")" = 700
# The script must exec logcat: same PID as the launcher, so a stop leaves no child.
mksh -c 'echo $$ > "$0/launcher"; exec env LR_OUT="$0/args" LOGRING_TEST_DATA="$0/data" LOGRING_TEST_LOGCAT="$0/logcat" LOGRING_TEST_GETPROP="$0/getprop" LOGRING_TEST_DF="$0/df" IT_DATA="$0/data" mksh packages/core/scripts/logring.sh' "$W" > /dev/null 2>&1
check 'logcat replaces the launcher process (exec, no child)' grep -q "pid=$(cat "$W/launcher") " "$W/args"
rm -f "$W/args"; LR_FREE=50.0M run
check 'low /data space: no recording' eval 'test ! -e "$W/args" && grep -q "below" "$W/out"'
rm -rf "$W/data/nemesis/gen5wkr.logs"; ln -s /tmp "$W/data/nemesis/gen5wkr.logs"
rm -f "$W/args"; run
check 'linked log folder refused' test ! -e "$W/args"
rm -f "$W/data/nemesis/gen5wkr.logs"
rm -rf "$W"
done_tests logring
