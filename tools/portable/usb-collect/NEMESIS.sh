#!/system/bin/sh
# Read-only log collector for the portable package. Writes only to this USB.
umask 022
case "$0" in */*) cd "${0%/*}" || exit 1;; esac
USB=$(pwd) || exit 1
AM=/system/bin/am
APP=/data/nemesis/apps/gen5w.kr.portable
STATE=/data/local/gen5w-portable
n=0
while [ -e "$USB/GEN5W-PORTABLE-LOGS-$n" ]; do n=$((n+1)); done
OUT=$USB/GEN5W-PORTABLE-LOGS-$n
mkdir "$OUT" || exit 1
alert() {
    [ -x "$AM" ] || return 0
    "$AM" broadcast -a com.hkmc.intent.action.TOAST -e com.hkmc.intent.extra.TOAST_MESSAGE "Gen5W 로그: $1" \
        --ez com.hkmc.intent.extra.TOAST_POPUPSHOWING true >/dev/null 2>&1 || :
}
# Bounded run: a stuck command never holds the collector.
grab() {
    local name=$1; shift
    ( "$@" > "$OUT/$name" 2>&1 & reader=$!
      ( sleep 30; kill -TERM "$reader" ) >/dev/null 2>&1 & guard=$!
      wait "$reader"; status=$?
      kill "$guard" 2>/dev/null
      echo "$name|$status" >> "$OUT/command-results.txt"
      exit "$status" )
}
alert '연결 상태와 로그를 수집합니다. 완료 안내가 나올 때까지 USB를 빼지 마세요.'
{ cat /proc/sys/kernel/random/boot_id; cat /proc/uptime; date; } > "$OUT/boot.txt" 2>&1
# Preserve the active session's rings before slower service queries rotate them.
grab logcat-main.txt logcat -d -v time
grab logcat-system.txt logcat -d -v time -b system
grab logcat-events.txt logcat -d -v time -b events
# These small status files expose the HUD input/output gate without reading
# destinations, phone identities or application databases.
mkdir "$OUT/app-status"
for file in /data/data/kr.gen5w.core/files/hud-owner.status \
    /data/data/kr.gen5w.core/files/hud-health.status \
    /data/data/kr.gen5w.core/files/hud-variant.status \
    /data/data/com.daudio.app.dipo/files/gen5w-portable-ready \
    /data/data/kr.gen5w.wirelesshost/files/bridge-ready; do
    [ -f "$file" ] && [ ! -L "$file" ] || continue
    dd if="$file" of="$OUT/app-status/${file##*/}" bs=4096 count=4 2>/dev/null
done
grab status.txt /system/bin/sh "$APP/boot.sh" status
grab services.txt /system/xbin/nemesis service list
grab packages.txt /system/xbin/nemesis pkg-list
grab state-list.txt ls -l -R "$STATE"
for dir in boot ap runtime overlay session; do
    [ -d "$STATE/$dir" ] || continue
    mkdir "$OUT/state-$dir"
    for file in "$STATE/$dir"/*; do
        [ -f "$file" ] && [ ! -L "$file" ] || continue
        cp "$file" "$OUT/state-$dir/" 2>/dev/null
    done
done
for source in "$STATE/diagnostics" /data/nemesis/gen5wkr.ui/diagnostics; do
    [ -d "$source" ] && [ ! -L "$source" ] || continue
    case "$source" in "$STATE/diagnostics") name=failure-evidence;; *) name=saved-diagnostics;; esac
    cp -R "$source" "$OUT/$name" 2>/dev/null
done
cp /data/nemesis/nemesis.log "$OUT/nemesis.log" 2>/dev/null
grab getprop.txt getprop
grab ps.txt ps
grab dmesg.txt dmesg
grab audio.txt dumpsys audio
grab audio-flinger.txt dumpsys media.audio_flinger
grab audio-policy.txt dumpsys media.audio_policy
grab wifi.txt dumpsys wifi
grab bluetooth.txt dumpsys bluetooth
grab binder-services.txt service list
grab activity-services.txt dumpsys activity services
grab interfaces.txt ls -l /sys/class/net
grab mounts.txt cat /proc/mounts
grab net-dev.txt cat /proc/net/dev
grab net-unix.txt cat /proc/net/unix
# The selected process maps show loaded libraries. Compare these with the
# overlay journals and mounts; installation preparation alone is insufficient.
mkdir "$OUT/process-state"
for process in /proc/[0-9]*; do
    command=
    IFS= read -r -d '' command < "$process/cmdline" 2>/dev/null || continue
    case "$command" in com.daudio.app.dipo|kr.gen5w.core|kr.gen5w.wirelesshost)
        pid=${process##*/}
        for name in stat status maps; do
            dd if="$process/$name" of="$OUT/process-state/$pid-$name.txt" bs=4096 count=32 2>/dev/null
        done;;
    esac
done
grab dropbox-list.txt ls -l /data/system/dropbox
mkdir "$OUT/dropbox"
for file in /data/system/dropbox/*; do
    [ -f "$file" ] && [ ! -L "$file" ] || continue
    cp "$file" "$OUT/dropbox/" 2>/dev/null
done
ls -l /storage/log > "$OUT/storage-log-list.txt" 2>&1
{ cat /proc/sys/kernel/random/boot_id; cat /proc/uptime; date; } > "$OUT/boot-end.txt" 2>&1
sync
echo done > "$OUT/DONE"
sync
alert "로그 복사 완료 (GEN5W-PORTABLE-LOGS-$n). USB를 빼서 PC로 가져오세요."
exit 0
