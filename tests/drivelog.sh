#!/bin/bash
# Mock-only tests for the removable USB drive log service.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
COMMON=$ROOT/packages/drive-log/scripts/common.sh
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
fail() { echo "FAIL $1"; exit 1; }
ok() { echo "PASS $1"; }

[ -f "$COMMON" ] || fail 'common helper exists'
. "$COMMON"
if ! command -v print >/dev/null 2>&1; then
    print() {
        [ "$1" = -r ] && shift
        [ "$1" = -- ] && shift
        printf '%s\n' "$*"
    }
fi

USB=$W/usb
MOUNTS=$W/mounts
SYS=$W/sys
mkdir -p "$USB" "$SYS/dev/block" \
    "$SYS/devices/platform/soc/usb1/1-1/host0/target0:0:0/block/sda/sda1" \
    "$SYS/devices/platform/soc/usb1/1-2/host0/target0:0:0/block/sdb/sdb1" \
    "$SYS/devices/platform/mmc/block/mmcblk0/mmcblk0p1"
ln -s ../../devices/platform/soc/usb1/1-1/host0/target0:0:0/block/sda/sda1 "$SYS/dev/block/8:1"
ln -s ../../devices/platform/soc/usb1/1-2/host0/target0:0:0/block/sdb/sdb1 "$SYS/dev/block/8:2"
ln -s ../../devices/platform/mmc/block/mmcblk0/mmcblk0p1 "$SYS/dev/block/179:1"
printf 'MAJOR=8\nMINOR=1\nDEVNAME=sda1\nDEVTYPE=partition\nPARTN=1\n' > "$SYS/devices/platform/soc/usb1/1-1/host0/target0:0:0/block/sda/sda1/uevent"
printf 'MAJOR=8\nMINOR=2\nDEVNAME=sdb1\nDEVTYPE=partition\nPARTN=1\n' > "$SYS/devices/platform/soc/usb1/1-2/host0/target0:0:0/block/sdb/sdb1/uevent"
printf 'MAJOR=179\nMINOR=1\nDEVNAME=mmcblk0p1\nDEVTYPE=partition\nPARTN=1\n' > "$SYS/devices/platform/mmc/block/mmcblk0/mmcblk0p1/uevent"

printf '/dev/block/vold/8:1 %s vfat rw,relatime 0 0\n' "$USB" > "$MOUNTS"
info=$(dl_mount_info "$USB" "$MOUNTS" "$SYS") || fail 'recognizes USB vfat mount'
[ "$info" = '/dev/block/vold/8:1|vfat|8:1' ] || fail 'returns mount identity'
ok 'recognizes USB vfat mount and identity'

printf '/dev/block/vold/8:2 %s exfat rw,relatime 0 0\n' "$USB" > "$MOUNTS"
dl_mount_info "$USB" "$MOUNTS" "$SYS" >/dev/null || fail 'recognizes USB exfat mount'
ok 'recognizes USB exfat mount'

printf '/dev/block/vold/179:1 %s vfat rw,relatime 0 0\n' "$USB" > "$MOUNTS"
if dl_mount_info "$USB" "$MOUNTS" "$SYS" >/dev/null; then fail 'rejects non-USB block source'; fi
printf '/dev/block/vold/8:1 %s ext4 rw,relatime 0 0\n' "$USB" > "$MOUNTS"
if dl_mount_info "$USB" "$MOUNTS" "$SYS" >/dev/null; then fail 'rejects unsupported filesystem'; fi
: > "$MOUNTS"
if dl_mount_info "$USB" "$MOUNTS" "$SYS" >/dev/null; then fail 'rejects an ordinary directory'; fi
ok 'rejects non-USB, unsupported and unmounted paths'

printf '/dev/block/vold/8:1 %s vfat rw,relatime 0 0\n' "$USB" > "$MOUNTS"
: > "$USB/GEN5W-DEBUG-ON"
dl_opt_in "$USB" || fail 'DEBUG-ON enables capture'
: > "$USB/GEN5W-DEBUG-OFF"
if dl_opt_in "$USB"; then fail 'DEBUG-OFF disables capture'; fi
rm "$USB/GEN5W-DEBUG-OFF" "$USB/GEN5W-DEBUG-ON"
ln -s "$W/outside" "$USB/GEN5W-DEBUG-ON"
if dl_opt_in "$USB"; then fail 'symlink marker is rejected'; fi
ok 'requires regular DEBUG-ON and honors DEBUG-OFF'

record='D1|12345|2|21|12|-45|1|7|850|66'
dl_validate_record "$record" || fail 'accepts numeric HUD record'
dl_validate_record 'D1|9999999999999|2|21|12|-45|1|7|850|66' || fail 'accepts long-uptime millisecond timestamp'
[ "$(dl_record_uptime "$record")" = 12345 ] || fail 'extracts monotonic record time'
dl_record_after 12345 "$record" || fail 'accepts record at opt-in timestamp'
if dl_record_after 12346 "$record"; then fail 'rejects pre-opt-in retained logcat row'; fi
if dl_record_after 12345 'D1|00000012344|2|21|12|-45|1|7|850|66'; then fail 'compares zero-padded timestamp numerically'; fi
long_record='D1|2147484000|2|21|12|-45|1|7|850|66'
dl_record_after 2147483999 "$long_record" || fail 'compares uptime beyond signed 32-bit milliseconds'
if dl_record_after 2147484001 "$long_record"; then fail 'rejects pre-opt-in row beyond signed 32-bit milliseconds'; fi
if dl_validate_record 'D1|12345|2|21|12|-45|1|7|850|66|path=Main St'; then fail 'rejects route text'; fi
if dl_validate_record 'D1|12345|2|21|12|-45|1|7|850|mac=AA:BB:CC:DD:EE:FF'; then fail 'rejects address/text field'; fi
if dl_validate_record 'D1|12345678901234|2|21|12|-45|1|7|850|66'; then fail 'rejects oversized timestamp'; fi
ok 'accepts bounded numeric schema and rejects extra text fields'
[ "$(dl_size_from_ls '-rw-r--r-- 1000 1000 1234 Jan 01 00:00 segment-00.log')" = 1234 ] || fail 'reads exact byte size from Android toolbox ls layout'
[ "$(dl_size_from_ls '-rw-r--r-- 1 user group 1234 Jan 01 00:00 segment-00.log')" = 1234 ] || fail 'reads exact byte size from GNU ls layout'
if dl_size_from_ls '-rw-r--r-- 1 user group unknown Jan 01 00:00 segment-00.log'; then
    fail 'rejects an unparseable ls size'
fi
ok 'parses exact segment byte size across ls layouts'
printf '12.34 1.00\n' > "$W/uptime"
DL_PROC_UPTIME="$W/uptime"
[ "$(dl_uptime_ms)" = 12340 ] || fail 'reads monotonic milliseconds for opt-in boundary'
printf '2147484.00 1.00\n' > "$W/uptime"
[ "$(dl_uptime_ms)" = 2147484000 ] || fail 'builds long uptime milliseconds without 32-bit arithmetic'
ok 'reads uptime and ignores retained logcat rows from before opt-in'
dl_read_timeout 10000 12000 || fail 'recognizes idle reader timeout'
if dl_read_timeout 10000 10010; then fail 'distinguishes EOF from idle timeout'; fi
dl_read_timeout 2147483000 2147484000 || fail 'recognizes long-uptime timeout without overflow'
if dl_read_timeout 2147483000 2147483999; then fail 'requires a full timeout at long uptime'; fi
dl_read_timeout 9999999999 10000000999 || fail 'handles decimal carry at long uptime'
ok 'distinguishes idle poll from reader EOF'
if command -v mksh >/dev/null 2>&1; then
    cat > "$W/read-probe.mksh" <<'EOF'
IFS= read -t 1 -r value
[ "$?" != 0 ] || exit 1
IFS= read -t 1 -r value
[ "$?" = 0 ] && [ "$value" = ready ] || exit 2
IFS= read -t 1 -r value
[ "$?" != 0 ] || exit 3
EOF
    (sleep 1.2; printf 'ready\n') | mksh "$W/read-probe.mksh" || fail 'mksh reader times out, resumes, and exits on EOF'
    ok 'mock logcat reader resumes after idle and terminates at EOF'
    printf '2147484.00 1.00\n' > "$W/uptime"
    DL_TESTING=1 DL_SEGMENT_BYTES_OVERRIDE=40 DL_SEGMENTS_OVERRIDE=2 DL_MIN_FREE_KB_OVERRIDE=64 \
        DL_PROC_UPTIME="$W/uptime" mksh -c '
            . "$1"
            [ "$(dl_uptime_ms)" = 2147484000 ] || exit 1
            rec="D1|2147484000|2|21|12|-45|1|7|850|66"
            dl_record_after 2147483999 "$rec" || exit 2
            dl_read_timeout 2147483000 2147484000 || exit 3
            dl_write_record "$3" "$rec" 128 || exit 4
            sz=$(dl_size_from_ls "$(LC_ALL=C ls -ln "$3/segment-00.log")") || exit 5
            expected=$(( ${#rec} + 1 ))
            [ "$sz" = "$expected" ] || exit 6
            dl_write_record "$3" "$rec" 128 || exit 7
            [ -f "$3/segment-01.log" ] || exit 8
        ' drive-log-mksh "$COMMON" "$W/uptime" "$W/mksh-ring" || fail 'mksh handles long uptime and exact ls byte size'
    ok 'mksh R43 executes long-uptime comparisons and segment byte sizing'
fi

RING=$W/ring
DL_SEGMENT_BYTES=96
DL_SEGMENTS=2
DL_MIN_FREE_KB=64
dl_prepare_ring "$RING" || fail 'creates owned ring directory'
: > "$RING/keep-me.txt"
dl_write_record "$RING" "$record" 128 || fail 'writes record above reserve'
dl_write_record "$RING" "$record" 128 || fail 'rotates a full segment'
dl_write_record "$RING" "$record" 128 || fail 'wraps within ring'
[ -f "$RING/keep-me.txt" ] || fail 'preserves unrelated file'
[ "$(find "$RING" -maxdepth 1 -type f -name 'segment-*.log' | wc -l)" -le 2 ] || fail 'ring has bounded segment count'
if dl_write_record "$RING" "$record" 63; then fail 'refuses below free-space reserve'; fi
if dl_write_record "$RING" 'raw log line' 128; then fail 'refuses unstructured record'; fi
[ ! -e "$RING/.cursor.tmp" ] || fail 'no cursor temp remains after normal rotation'
ok 'bounds ring, preserves unrelated files and fails closed on space/schema errors'

STALE=$W/stale-ring
dl_prepare_ring "$STALE" || fail 'creates crash-recovery fixture'
printf '1\n' > "$STALE/.cursor.tmp"
dd if=/dev/zero of="$STALE/segment-00.log" bs=96 count=1 2>/dev/null
if dl_write_record "$STALE" "$record" 128; then fail 'refuses ambiguous interrupted rotation'; fi
[ -f "$STALE/.cursor.tmp" ] && [ "$(cat "$STALE/.cursor.tmp")" = 1 ] || fail 'preserves interrupted cursor temp'
ok 'preserves ambiguous cursor temp and fails closed after interrupted rotation'

echo 'drive log: all tests passed'
