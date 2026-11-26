#!/system/bin/sh
# Field recovery (fast): small status capture to this USB, auto-start off, then
# restore stock /system from the immutable recovery manifest with the on-device
# guard restore.sh (atomic rename; it reboots itself after verifying).
umask 022
case "$0" in */*) cd "${0%/*}" || exit 1;; esac
USB=$(pwd) || exit 1
AM=/system/bin/am
GUARD=/data/local/gen5w-portable/persistent/bootguard
REC=/data/local/gen5w-portable/persistent/recovery
B=/data/local/gen5w-portable/boot
n=0
while [ -e "$USB/GEN5W-RECOVER-$n" ]; do n=$((n+1)); done
OUT=$USB/GEN5W-RECOVER-$n
mkdir "$OUT" || exit 1
RES=$OUT/RECOVERY.txt
note() { echo "$(date +%H:%M:%S 2>/dev/null) $*" >> "$RES"; sync; }
# Toast in the background: a busy system_server must never hold this script.
alert() { [ -x "$AM" ] || return 0; ( "$AM" broadcast -a com.hkmc.intent.action.TOAST -e com.hkmc.intent.extra.TOAST_MESSAGE "Gen5W 복구: $1" --ez com.hkmc.intent.extra.TOAST_POPUPSHOWING true >/dev/null 2>&1 & ); }
grab() { local name=$1; shift; ( "$@" > "$OUT/$name" 2>&1 & r=$!; ( sleep 10; kill -TERM "$r" ) >/dev/null 2>&1 & g=$!; wait "$r"; kill "$g" 2>/dev/null ); }
note start
alert '순정 복구를 시작합니다. 1~3분 뒤 자동 재부팅됩니다. USB를 빼지 마세요.'
{ cat /proc/sys/kernel/random/boot_id; cat /proc/uptime; date; } > "$OUT/boot.txt" 2>&1
grab logcat-main.txt logcat -d -v time -t 20000
grab getprop.txt getprop
grab ps.txt ps
grab mounts.txt cat /proc/mounts
grab state-list.txt ls -l -R /data/local/gen5w-portable/boot /data/local/gen5w-portable/persistent
cp /data/nemesis/nemesis.log "$OUT/nemesis.log" 2>/dev/null
[ -d "$GUARD" ] && [ ! -L "$GUARD" ] && for f in guard.log count tripped GEN5W-RECOVERY-RESULT.txt; do
    [ -f "$GUARD/$f" ] && [ ! -L "$GUARD/$f" ] && cp "$GUARD/$f" "$OUT/guard-$f"
done
sync
note 'status captured'
[ -f "$REC/manifest" ] && [ ! -L "$REC/manifest" ] && cp "$REC/manifest" "$OUT/recovery-manifest.txt"
[ -f "$REC/restore.done" ] && [ ! -L "$REC/restore.done" ] && cp "$REC/restore.done" "$OUT/previous-restore.done"
if ! { [ -f "$USB/recovery-restore.sh" ] && [ ! -L "$USB/recovery-restore.sh" ] && [ -x "$GUARD/bin/dex-patch" ] && [ ! -L "$GUARD/bin/dex-patch" ] && [ -f "$REC/manifest" ] && [ ! -L "$REC/manifest" ]; }; then
    note 'restore tools or manifest missing; nothing changed'
    alert '복구 도구가 없어 아무것도 바꾸지 않았습니다. USB를 PC로 가져오세요.'
    exit 1
fi
if [ -d "$B" ] && [ ! -L "$B" ]; then
    [ -L "$B/enabled" ] || { echo 0 > "$B/enabled.new" && mv "$B/enabled.new" "$B/enabled"; }
    [ -L "$B/reason" ] || { echo field-recovery-usb > "$B/reason.new" && mv "$B/reason.new" "$B/reason"; }
    sync
fi
note "auto-start off (enabled=$(cat "$B/enabled" 2>/dev/null))"
if [ -L "$GUARD/GEN5W-RECOVERY-RESULT.txt" ]; then
    note 'linked result file; refused'
    exit 1
fi
if [ -f "$GUARD/GEN5W-RECOVERY-RESULT.txt" ]; then
    cp "$GUARD/GEN5W-RECOVERY-RESULT.txt" "$OUT/previous-result.txt" || exit 1
    rm -f "$GUARD/GEN5W-RECOVERY-RESULT.txt" || exit 1
fi
echo 'result=running' > "$OUT/GEN5W-RECOVERY-RESULT.txt"
sync
alert '순정 /system 복구 중입니다. 끝나면 자동 재부팅됩니다. USB를 빼지 마세요.'
note 'restore.sh start'
( GEN5W_RECOVERY_USB_ROOT=$GUARD GEN5W_RECOVERY_RESTORE_SETTINGS=1 /system/bin/sh "$USB/recovery-restore.sh" > "$OUT/restore.txt" 2>&1
  echo "restore rc=$?" >> "$OUT/restore.txt"; cp "$GUARD/GEN5W-RECOVERY-RESULT.txt" "$OUT/" 2>/dev/null; sync ) &
r=$!
while kill -0 "$r" 2>/dev/null; do sleep 2; cp "$GUARD/GEN5W-RECOVERY-RESULT.txt" "$OUT/" 2>/dev/null; sync; done
wait "$r"
result=
[ -f "$GUARD/GEN5W-RECOVERY-RESULT.txt" ] && while IFS= read -r line; do case "$line" in result=*) result=${line#result=};; esac; done < "$GUARD/GEN5W-RECOVERY-RESULT.txt"
note "restore returned without reboot; result=$result"
case "$result" in
    success) alert '이미 순정으로 복구된 상태입니다. USB를 빼서 PC로 가져오세요.';;
    restored) alert '복원 파일 검증 완료. 재부팅 요청을 전달했습니다. USB를 빼지 마세요.';;
    *) alert "복구 실패($result). 차를 끄지 말고 USB를 PC로 가져오세요.";;
esac
[ "$result" = success ] && exit 0
[ "$result" = restored ] && exit 0
exit 1
