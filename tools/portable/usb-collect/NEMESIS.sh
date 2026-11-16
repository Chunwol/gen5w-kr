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
      exit "$status" )
}
alert '로그를 USB로 복사합니다. 1분 정도 걸립니다. USB를 빼지 마세요.'
{ cat /proc/sys/kernel/random/boot_id; cat /proc/uptime; date; } > "$OUT/boot.txt" 2>&1
grab status.txt /system/bin/sh "$APP/boot.sh" status
grab services.txt /system/xbin/nemesis service list
grab packages.txt /system/xbin/nemesis pkg-list
grab state-list.txt ls -l -R "$STATE"
for dir in boot ap; do
    [ -d "$STATE/$dir" ] || continue
    mkdir "$OUT/state-$dir"
    for file in "$STATE/$dir"/*; do
        [ -f "$file" ] && [ ! -L "$file" ] || continue
        cp "$file" "$OUT/state-$dir/" 2>/dev/null
    done
done
cp /data/nemesis/nemesis.log "$OUT/nemesis.log" 2>/dev/null
grab getprop.txt getprop
grab ps.txt ps
grab dmesg.txt dmesg
grab logcat-main.txt logcat -d -v time
grab logcat-system.txt logcat -d -v time -b system
grab logcat-events.txt logcat -d -v time -b events
grab dropbox-list.txt ls -l /data/system/dropbox
mkdir "$OUT/dropbox"
for file in /data/system/dropbox/*; do
    [ -f "$file" ] && [ ! -L "$file" ] || continue
    cp "$file" "$OUT/dropbox/" 2>/dev/null
done
ls -l /storage/log > "$OUT/storage-log-list.txt" 2>&1
sync
echo done > "$OUT/DONE"
sync
alert "로그 복사 완료 (GEN5W-PORTABLE-LOGS-$n). USB를 빼서 PC로 가져오세요."
exit 0
