#!/system/bin/sh
# Failure evidence only: no service, radio, framework or overlay mutations.
umask 077
BASE=${0%/*}
BASE=$(CDPATH= cd -- "$BASE" && pwd) || exit 1
ROOT=${PORTABLE_TEST_ROOT:-}
plain() {
    case "$1" in /*) :;; *) return 1;; esac
    case "$1" in *[!a-zA-Z0-9_./-]*|*/../*|*/./*|*/..|*/.|*//*) return 1;; esac
    local p=$1
    while [ "$p" != / ]; do [ ! -L "$p" ] || return 1; p=${p%/*}; [ -n "$p" ] || p=/; done
}
if [ -n "$ROOT" ]; then
    plain "$ROOT" && [ "$ROOT" != / ] && [ -d "$ROOT" ] || exit 1
    case "$BASE" in "$ROOT"/data/*) :;; *) exit 1;; esac
else
    case "$(id)" in uid=0\(*) :;; *) exit 1;; esac
    case "$BASE" in /data/*) :;; *) exit 1;; esac
fi
case "$1" in capture|active) :;; *) exit 2;; esac
reason=$2
case "$reason" in ''|*[!a-zA-Z0-9_=.:\ -]* ) reason=unspecified;; esac
boot=$(cat "$ROOT/proc/sys/kernel/random/boot_id") || exit 1
case "$boot" in ''|*[!a-zA-Z0-9-]*) exit 1;; esac
[ "${#boot}" -le 64 ] || exit 1
STATE=$ROOT/data/local/gen5w-portable
STORE=$STATE/diagnostics
plain "$STATE" && [ -d "$STATE" ] && plain "$STORE" || exit 1
[ -d "$STORE" ] || mkdir "$STORE" || exit 1
chmod 700 "$STORE" || exit 1
# At most six failure boots; never overwrite the first failure of a boot.
prefix=failure; limit=6
if [ "$1" = active ]; then
    case "$2" in ''|*[!0-9]*) exit 2;; esac
    [ "${#2}" -le 10 ] || exit 2
    prefix=active; limit=8
    OUT=$STORE/active-$boot-$2
else
    OUT=$STORE/failure-$boot
fi
plain "$OUT" || exit 1
[ ! -e "$OUT" ] || { [ -d "$OUT" ] && exit 0; exit 1; }
count=0
for dir in "$STORE"/"$prefix"-*; do [ ! -d "$dir" ] || count=$((count+1)); done
if [ "$prefix" = active ] && [ "$count" -ge "$limit" ]; then
    # Retire only flat snapshots already copied and synced to USB. Failures and
    # unexported captures remain intact; the next save can capture current rings.
    for dir in "$STORE"/active-*; do
        plain "$dir" && [ -d "$dir" ] && plain "$dir/EXPORTED" && [ -f "$dir/EXPORTED" ] || continue
        safe=1
        for file in "$dir"/*; do plain "$file" && [ -f "$file" ] || safe=0; done
        [ "$safe" = 1 ] || continue
        for file in "$dir"/*; do rm -f "$file" || exit 1; done
        rmdir "$dir" || exit 1
        count=$((count-1)); [ "$count" -lt "$limit" ] && break
    done
fi
[ "$count" -lt "$limit" ] || { echo 'diagnostics: snapshot limit reached; export before collecting more' >&2; exit 1; }
mkdir "$OUT" || exit 1
{
    echo "boot=$boot"
    echo "reason=$reason"
    cat "$ROOT/proc/uptime"
    date
} > "$OUT/START"
copy() {
    plain "$2" && [ -f "$2" ] || return 0
    dd if="$2" of="$OUT/$1" bs=4096 count=32 2>/dev/null
}
for dir in boot session runtime overlay ap; do
    for file in "$STATE/$dir"/*; do
        [ -f "$file" ] && [ ! -L "$file" ] || continue
        copy "$dir-${file##*/}" "$file"
    done
done
for name in status log diag-latest.txt restore.log; do copy "manager-$name" "$ROOT/data/nemesis/gen5wkr.ui/$name"; done
copy meminfo.txt "$ROOT/proc/meminfo"
copy net-dev.txt "$ROOT/proc/net/dev"
for name in hud-owner.status hud-health.status hud-variant.status; do
    copy "$name" "$ROOT/data/data/kr.gen5w.core/files/$name"
done
copy dipo-ready.txt "$ROOT/data/data/com.daudio.app.dipo/files/gen5w-portable-ready"
copy installed-candidate.json "$BASE/CANDIDATE.json"
copy installed-SHA256SUMS "$BASE/SHA256SUMS"
# Wi-Fi chosen at install and the USB dongle service: state, log, loaded
# modules, firmware search path and plugged-in USB device IDs.
copy wifi-backend.txt "$STATE/wifi-backend"
copy wifi-backend-why.txt "$STATE/wifi-backend-why"
for file in "$STATE/dongle"/*; do
    [ -f "$file" ] && [ ! -L "$file" ] || continue
    copy "dongle-${file##*/}" "$file"
done
copy dongle.log "$ROOT/data/nemesis/logs/gen5w.kr.portable/dongle.log"
copy modules.txt "$ROOT/proc/modules"
copy firmware-path.txt "$ROOT/sys/module/firmware_class/parameters/path"
for v in "$ROOT"/sys/bus/usb/devices/*/idVendor; do
    p=${v%idVendor}idProduct
    [ -f "$v" ] && [ -f "$p" ] || continue
    IFS= read -r vid < "$v"; IFS= read -r pid < "$p"
    d=${v%/idVendor}; print -r -- "${d##*/} $vid:$pid"
done > "$OUT/usb-devices.txt" 2>/dev/null
# Four rolling files, each at most 4 MiB; preserve successful-but-broken sessions.
for file in "$STATE/debug"/logcat.log "$STATE/debug"/logcat.log.1 "$STATE/debug"/logcat.log.2 "$STATE/debug"/logcat.log.3; do
    plain "$file" && [ -f "$file" ] || continue
    dd if="$file" of="$OUT/debug-${file##*/}" bs=4096 count=1024 2>/dev/null
done
# Trusted kernel interface: /proc/mounts is normally a symlink to self/mounts.
cat "$ROOT/proc/mounts" > "$OUT/mounts.txt" 2>/dev/null
grab() {
    local name=$1 command cleanup=/system/bin/true; shift
    command=$(command -v "$1") || { echo unavailable > "$OUT/$name"; return 0; }
    shift
    [ -z "$ROOT" ] || cleanup=/bin/true
    ( "$BASE/bin/dex-patch" supervise 3 "$cleanup" "$command" "$@" 2>&1
      echo "$name|$?" >> "$OUT/commands.txt"
    ) | dd of="$OUT/$name" bs=4096 count=64 2>/dev/null
}
# Capture recent rings before slower Binder queries. Parent bounds this entire
# script to 20 seconds; START and early files survive interruption without DONE.
grab logcat-main.txt logcat -d -v time -t 800 -b main
grab logcat-system.txt logcat -d -v time -t 800 -b system
grab logcat-events.txt logcat -d -v time -t 400 -b events
grab processes.txt ps
for role in BROKER OWNER; do
    case "$role" in BROKER) pid=$PORTABLE_DIAG_BROKER_PID;; OWNER) pid=$PORTABLE_DIAG_OWNER_PID;; esac
    case "$pid" in ''|*[!0-9]*) continue;; esac
    for file in status limits stat; do copy "$role-$file" "$ROOT/proc/$pid/$file"; done
    grab "$role-fd.txt" ls -l "$ROOT/proc/$pid/fd"
done
grab properties.txt getprop
grab audio.txt dumpsys audio
grab audio-flinger.txt dumpsys media.audio_flinger
grab audio-policy.txt dumpsys media.audio_policy
grab dipo.txt dumpsys dipo
grab split.txt dumpsys com.mobis.splitscreen.right.SplitScreenHome
grab wifi.txt dumpsys wifi
grab bluetooth.txt dumpsys bluetooth
grab bluetooth-manager.txt dumpsys bluetooth_manager
grab binder-services.txt service list
echo done > "$OUT/DONE"
sync
