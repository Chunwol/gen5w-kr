#!/bin/bash
# Portable screen collector: real tools/portable/ui.sh against a private fixture.
# Mocked boundaries only: Android properties, the boot.sh disable invocation
# (recorded, not executed), sync, /proc boot_id/uptime/mounts and the USB mount.
set -euo pipefail
cd "$(dirname "$0")/.."
command -v mksh >/dev/null || { echo 'SKIP mksh unavailable'; exit 0; }
[ -x .build/portable/dex-patch-host ] || { echo 'FAIL .build/portable/dex-patch-host missing'; exit 1; }
t=$(mktemp -d /tmp/g5p-ui.XXXXXX)
holders=()
cleanup() {
    # Signal only still-owned jobs, then reap them before another suite scans /proc.
    local p
    for p in $(jobs -pr); do kill "$p" 2>/dev/null || :; done
    wait 2>/dev/null || :
    rm -rf "$t"
}
trap 'rc=$?; cleanup; exit $rc' EXIT
fail() { echo "FAIL $*" >&2; [ ! -f "$UI/status" ] || sed 's/^/  status: /' "$UI/status" >&2; exit 1; }
pass() { echo "PASS $*"; }
R=$t/root; B=$R/data/nemesis/apps/gen5w.kr.portable; A=$t/actions
N=$R/data/nemesis; UI=$N/gen5wkr.ui; P=$R/data/local/gen5w-portable
APP=$R/data/data/kr.gen5w.core; REQ=$APP/files/ui-request
mkdir -p "$B/bin" "$N/logs/gen5w.kr.portable" "$P"/{boot,overlay,runtime,session} "$APP/files" \
    "$R/data/data/kr.gen5w.wirelesshost/files" "$R/proc/sys/kernel/random" "$R/sys/class/net/wlan0" "$R/storage/usb0" "$A/props"
cp tools/portable/ui.sh tools/portable/boot.sh tools/portable/diagnostics.sh tools/portable/NEMESIS.data "$B/"
cp .build/portable/dex-patch-host "$B/bin/dex-patch"
chmod 755 "$B/ui.sh" "$B/bin/dex-patch"; chmod 700 "$APP"; chmod 700 "$APP/files"
BOOT=12345678-1234-1234-1234-123456789abc
echo "$BOOT" > "$R/proc/sys/kernel/random/boot_id"
echo '100.25 50.00' > "$R/proc/uptime"
: > "$R/proc/mounts"
: > "$A/calls"
cat > "$t/adapter" <<'SH'
#!/bin/bash
case "$1" in
get) cat "$ACTIONS/props/$2" 2>/dev/null || :;;
disable)
    echo "disable $2" >> "$ACTIONS/calls"
    [ ! -f "$ACTIONS/disable-delay" ] || sleep "$(cat "$ACTIONS/disable-delay")"
    echo 'boot: automatic application disabled and owned overlays/wrappers restored'
    exit "$(cat "$ACTIONS/disable-rc" 2>/dev/null || echo 0)";;
sync) :;;
snapshot) mksh "$2" active "$3";;
*) echo "unexpected $*" >> "$ACTIONS/calls"; exit 1;;
esac
SH
chmod +x "$t/adapter"
export ACTIONS=$A PORTABLE_TEST_ROOT=$R PORTABLE_TEST_UI_ADAPTER=$t/adapter PORTABLE_TEST_HELPER=$B/bin/dex-patch
collect() { PORTABLE_UI_ONCE=1 timeout 30 mksh "$B/ui.sh" > "$t/out" 2>&1 || { cat "$t/out" >&2; fail "collector exited $?"; }; }
st() { grep -x "$1=.*" "$UI/status" | { IFS= read -r l; echo "${l#*=}"; }; }
expect() { [ "$(st "$1")" = "$2" ] || fail "$3: $1=[$(st "$1")] want [$2]"; }
request() { # body lines; writes as the core app does (temp + rename), mode 600
    printf '%s\n' "$@" > "$REQ.tmp"; chmod 600 "$REQ.tmp"; mv "$REQ.tmp" "$REQ"
}
envelope() { request "boot=$BOOT" "expires=${EXPIRES:-120}" "$@"; }
disables() { grep -c '^disable ' "$A/calls" || :; }

# Healthy portable state of this boot, a live host and a live session.
echo 1 > "$P/boot/enabled"; echo "$BOOT|healthy" > "$P/boot/attempt"; echo startup-healthy > "$P/boot/reason"; echo full > "$P/boot/runtime-mode"
echo committed > "$P/overlay/state"; echo "$BOOT" > "$P/overlay/boot"
echo committed > "$P/runtime/phase"; echo "$BOOT" > "$P/runtime/boot"
echo '/system/bin/sh /data/local/gen5w-portable/runtime-payload/wrap-dipo.sh' > "$A/props/wrap.com.daudio.app.dipo"
starttime() { set -- $(sed 's/^.*) //' "/proc/$1/stat"); echo "${20}"; }
HOSTM=$R/data/data/kr.gen5w.wirelesshost/files/bridge-ready
bash -c 'exec -a kr.gen5w.wirelesshost sleep 300' & host=$!; holders+=($host)
for i in $(seq 50); do grep -aq '^kr.gen5w.wirelesshost' "/proc/$host/cmdline" && break; sleep .02; done
printf '%s
boot_id=%s
starttime=%s
' "$host" "$BOOT" "$(starttime "$host")" > "$HOSTM"
sleep 300 & session=$!; holders+=($session)
key="$session:$(starttime "$session")"
echo "$BOOT|$key" > "$P/session/epoch"; echo "$BOOT|$key" > "$P/session/ready"
printf 'session: host/AP/HUD supervisor running\nphone aa:bb:cc:dd:ee:ff paired SSID=home\n' > "$N/logs/gen5w.kr.portable/boot.log"
# Decoys of the old integrated install: must never run.
mkdir -p "$N/apps/gen5w.kr.bridge" "$N/gen5wkr.recovery/current"
printf '[nemesis]\npreuninstall=preun.sh\n' > "$N/apps/gen5w.kr.bridge/NEMESIS.data"
echo "touch $A/OLD-REMOVAL-RAN" > "$N/apps/gen5w.kr.bridge/preun.sh"
echo "touch $A/OLD-RECOVERY-RAN" > "$N/gen5wkr.recovery/current/recovery.sh"

# 1. Status/log schema from portable journals and the live host.
collect
for kv in ts=100 boot=$BOOT host=alive relay=on backend=builtin version=0.3.83 apguard=on wired=no sw_wireless=on \
          sw_timer=on sw_bluelink=on sw_adb=unknown adb_health=unknown adb_result=0:none saved=0:none removed=0:none \
          wlan=present recovery_state=none recovery_available=no recovery_request=0 recovery_result=none \
          portable_enabled=1 portable_phase=healthy portable_mode=full portable_overlay=committed portable_runtime=committed portable_session=running; do
    expect "${kv%%=*}" "${kv#*=}" schema
done
[ "$(stat -c %a "$UI")" = 755 ] && [ "$(stat -c %a "$UI/status")" = 644 ] && [ "$(stat -c %a "$UI/log")" = 644 ] || fail 'ui modes'
[ "$(wc -l < "$UI/status")" -le 50 ] && [ "$(wc -l < "$UI/log")" -le 200 ] || fail 'bounds'
grep -q '^portable|session: host/AP/HUD supervisor running$' "$UI/log" || fail 'package log missing'
! grep -q 'aa:bb:cc' "$UI/log" || fail 'private line in log'
grep -q '^boot|enabled=1 phase=healthy' "$UI/log" || fail 'journal summary missing'
[ ! -e "$APP/files/status" ] && [ "$(ls "$APP/files")" = "" ] || fail 'root wrote into the app folder'
pass 'status/log follow the StatusModel schema from portable journals; private lines dropped; root-owned 755/644'
envelope 'debug=on'; collect
[ -f "$N/gen5wkr.debug-on" ] || fail 'debug switch did not enable'
collect; expect sw_debug on 'debug status enabled'
envelope 'debug=off'; collect
[ ! -e "$N/gen5wkr.debug-on" ] || fail 'debug switch did not disable'
collect; expect sw_debug off 'debug status disabled'
rm -f "$REQ"

# 2. Host marker identity, AP admission guards, host down and static mode.
good=$(cat "$HOSTM")
printf '%s
boot_id=00000000-1234-1234-1234-123456789abc
starttime=%s
' "$host" "$(starttime "$host")" > "$HOSTM"; collect; expect host dead 'marker from another boot'
printf '%s
boot_id=%s
starttime=1
' "$host" "$BOOT" > "$HOSTM"; collect; expect host dead 'reused pid (starttime differs)'
printf '%s
boot_id=%s
starttime=%s
extra
' "$host" "$BOOT" "$(starttime "$host")" > "$HOSTM"; collect; expect host dead 'malformed marker'
echo "$host" > "$HOSTM"; collect; expect host dead 'pid-only marker'
echo "$good" > "$HOSTM"; collect; expect host alive 'valid marker'
mkdir -p "$N/gen5wkr.apguard"; touch "$N/gen5wkr.apguard/attempt"
collect; expect apguard on 'live host owns its current AP attempt'
kill "$host"; wait "$host" 2>/dev/null || :
collect; expect host dead 'host exited'; expect apguard off 'unfinished AP start before host start'
rm "$N/gen5wkr.apguard/attempt"; touch "$R/data/data/kr.gen5w.wirelesshost/files/ap-attempt"; collect; expect apguard off 'host-side unfinished attempt'
rm "$R/data/data/kr.gen5w.wirelesshost/files/ap-attempt"; collect; expect apguard on 'no guard evidence'
touch "$N/gen5wkr.apguard.off"; collect; expect apguard off 'guard off'; rm "$N/gen5wkr.apguard.off"
touch "$N/gen5wkr.wireless-disabled"; collect; expect wired yes 'wired-only'; expect apguard off 'wired-only'; rm "$N/gen5wkr.wireless-disabled"
echo static > "$P/boot/runtime-mode"; echo disabled > "$P/runtime/phase"; rm "$A/props/wrap.com.daudio.app.dipo"
collect; expect host dead static; expect relay off static; expect apguard off static
echo full > "$P/boot/runtime-mode"; echo committed > "$P/runtime/phase"
collect; expect relay unknown 'committed journal without the owned wrapper'
pass 'host marker bound to boot+pid+starttime; AP guard evidence locks the switch unless the host is live; static/missing wrapper not shown working'

# 3. Envelope: stale, forged, oversized, symlinked and foreign requests change nothing.
M=$N/gen5wkr.ui-wireless-off
rejected() { rm -f "$M"; collect; [ ! -e "$M" ] || fail "accepted: $1"; }
request wireless=off; rejected 'no envelope'
request "boot=00000000-1234-1234-1234-123456789abc" expires=120 wireless=off; rejected 'other boot'
EXPIRES=99 envelope wireless=off; rejected 'expired'
EXPIRES=131 envelope wireless=off; rejected 'deadline beyond 30 s'
request "boot=$BOOT" "boot=$BOOT" expires=120 wireless=off; rejected 'duplicate boot'
request expires= "boot=$BOOT" expires=120 wireless=off; rejected 'empty duplicate deadline'
envelope wireless=off wireless=on; rejected 'duplicate action'
envelope wireless=off 'wireless=maybe'; rejected 'invalid value'
envelope wireless=off 'shell=reboot'; rejected 'unknown key'
envelope wireless=off ''; rejected 'blank line'
envelope wireless=off a=1 b=1 c=1 d=1 e=1 f=1 g=1; rejected 'more than ten lines'
envelope wireless=off "save=$(printf '%0250d' 1)"; rejected 'oversized line'
# A valid envelope followed by unterminated padding: line parsing alone would drop the
# padding and accept, so only the 256-byte bound rejects it.
envelope wireless=off; printf '%0300d' 0 >> "$REQ"; rejected 'oversized file with valid lines'
envelope wireless=off; chmod 660 "$REQ"; rejected 'group-writable'
envelope wireless=off; mv "$REQ" "$t/real-request"; ln -s "$t/real-request" "$REQ"; rejected 'symlink'
rm "$REQ"; mkfifo "$REQ"; start=$SECONDS; rejected 'fifo'; [ $((SECONDS - start)) -lt 10 ] || fail 'fifo stalled the collector'; rm "$REQ"
mkdir "$REQ"; rejected 'directory'; rmdir "$REQ"
envelope wireless=off; collect; [ -f "$M" ] || fail 'fresh request ignored'
envelope wireless=on; collect; [ ! -e "$M" ] || fail 'wireless on ignored'; expect sw_wireless on 'marker state'
[ "$(disables)" = 0 ] || fail 'envelope tests invoked disable'
pass 'stale/forged/duplicate/oversized/symlink/fifo/group-writable requests rejected; fresh one manages only gen5wkr.ui-wireless-off'

# 4. Bundled timer/Bluelink switches manage only their markers; adb stays unsupported.
envelope timer=off bluelink=off adb=on:5; collect
for m in timer bluelink; do [ -f "$N/gen5wkr.ui-$m-off" ] || fail "$m marker not written"; done
expect sw_timer off timer; expect sw_bluelink off bluelink
expect adb_result 5:unsupported adb; expect sw_adb unknown adb
grep -q '^ui|UNSUPPORTED Wi-Fi adb' "$UI/log" || fail 'unsupported adb not logged'
envelope timer=on bluelink=on; collect
for m in timer bluelink; do [ ! -e "$N/gen5wkr.ui-$m-off" ] || fail "$m marker kept"; done
expect sw_timer on timer; expect sw_bluelink on bluelink
ln -s "$t/elsewhere" "$N/gen5wkr.ui-timer-off"; envelope timer=off; collect
[ -L "$N/gen5wkr.ui-timer-off" ] && [ ! -e "$t/elsewhere" ] || fail 'symlinked timer marker followed'; rm "$N/gen5wkr.ui-timer-off"
! grep -qv '^disable ' "$A/calls" || fail "unexpected boundary call: $(cat "$A/calls")"
pass 'timer/bluelink switches set only their own markers; adb reported unsupported'

# 5. Removal routes only to this package's boot.sh disable, exactly once per token.
envelope remove=42 wireless=off; collect
[ "$(cat "$A/calls")" = "disable $B/boot.sh" ] || fail "routing: $(cat "$A/calls")"
expect removed 42:done removal; [ ! -e "$M" ] || fail 'removal also applied other actions'
grep -q '^restore|boot: automatic application disabled' "$UI/log" || fail 'restore output not in log'
collect; [ "$(disables)" = 1 ] || fail 'replayed removal'
echo 1 > "$A/disable-rc"; envelope remove=43; collect; expect removed 43:failed:boot-disable 'failed disable'; rm "$A/disable-rc"
[ ! -e "$A/OLD-REMOVAL-RAN" ] && [ ! -e "$A/OLD-RECOVERY-RAN" ] || fail 'old integrated scripts ran'
pass 'remove -> own boot.sh disable only, once per token, failure reported'

# 6. Restore (recovery) is offered only when auto-start is off with live owned changes.
envelope recovery=7; collect; [ "$(disables)" = 2 ] || fail 'recovery while healthy/enabled'
expect recovery_state none 'enabled install'; rm "$REQ"
echo 0 > "$P/boot/enabled"; echo stock-changed > "$P/boot/reason"; collect
expect recovery_state required 'L1-like state'; expect recovery_available yes 'L1-like state'; expect recovery_reason ready 'L1-like state'
envelope recovery=8 wireless=off; collect; [ "$(disables)" = 2 ] || fail 'recovery with extra actions accepted'
envelope recovery=9; collect
[ "$(tail -n1 "$A/calls")" = "disable $B/boot.sh" ] && [ "$(disables)" = 3 ] || fail 'recovery routing'
echo disabled > "$P/overlay/state"; echo disabled > "$P/runtime/phase"; collect
expect recovery_state restored 'after restore'; expect recovery_request 9 'after restore'; expect recovery_result restored 'after restore'
pass 'recovery offered only for disabled-but-dirty state and routed to own boot.sh disable'

# 7. A live restore excludes another; an interrupted one is reported, not hidden.
echo 6 > "$A/disable-delay"
envelope remove=50; collect & first=$!
for i in $(seq 50); do [ -f "$N/gen5wkr.ui-portable-restore/owner" ] && break; sleep .05; done
[ -f "$N/gen5wkr.ui-portable-restore/owner" ] || fail 'worker lock missing'
envelope remove=51; collect
# Read the record right away: the first worker overwrites it when it finishes.
[ "$(cat "$N/gen5wkr.ui-portable-removed")" = '51 failed busy' ] || fail "concurrent removal: $(cat "$N/gen5wkr.ui-portable-removed")"
[ "$(disables)" = 4 ] || fail 'second restore ran concurrently'
rm "$REQ"
wait "$first"; rm "$A/disable-delay"; expect removed 50:done 'first removal'
[ ! -e "$N/gen5wkr.ui-portable-restore" ] || fail 'worker lock left behind'
echo '60 working gen5w.kr.portable' > "$N/gen5wkr.ui-portable-removed"; rm -rf "$N/gen5wkr.ui-portable-restore"
collect; expect removed 60:failed:interrupted 'interrupted removal'
pass 'concurrent restore refused as busy; interrupted restore shown as failed'

# 8. Diagnosis export: bounded status+log; USB only on a verified FAT mount.
envelope save=70; collect; expect saved 70:nousb 'no USB mount'
[ -s "$UI/diag-latest.txt" ] && ! grep -q 'aa:bb:cc\|SSID' "$UI/diag-latest.txt" || fail 'in-car diagnosis copy'
echo '/dev/block/sda1 /storage/usb0 ext4 rw 0 0' > "$R/proc/mounts"; envelope save=71; collect; expect saved 71:nousb 'non-FAT mount'
[ ! -e "$R/storage/usb0/gen5w-kr-diag" ] || fail 'wrote to non-FAT mount'
echo '/dev/block/vold/8:1 /storage/usb0 vfat rw 0 0' > "$R/proc/mounts"; envelope save=72; collect; expect saved 72:usb 'FAT mount'
[ -s "$R/storage/usb0/gen5w-kr-diag/diag-72.txt" ] || fail 'USB file missing'
[ "$(wc -l < "$R/storage/usb0/gen5w-kr-diag/diag-72.txt")" -le 260 ] || fail 'diagnosis not bounded'
! grep -q 'aa:bb:cc' "$R/storage/usb0/gen5w-kr-diag/diag-72.txt" || fail 'private line exported'
echo private > "$t/elsewhere"; ln -s "$t/elsewhere" "$R/storage/usb0/gen5w-kr-diag/diag-73.txt.tmp"
envelope save=73; collect; expect saved 73:fail 'planted link'
[ "$(cat "$t/elsewhere")" = private ] || fail 'followed a planted link'
# Real procfs exposes mounts through the fixed self/mounts link.
mkdir -p "$R/proc/self"
mv "$R/proc/mounts" "$R/proc/self/mounts"
ln -s self/mounts "$R/proc/mounts"
mkdir -p "$P/diagnostics/failure-$BOOT"
echo retained-failure > "$P/diagnostics/failure-$BOOT/START"
envelope save=74; collect; expect saved 74:usb 'normal procfs mounts link'
[ -s "$UI/diagnostics/diag-$BOOT-70.txt" ] || fail 'first local diagnosis was overwritten'
[ -s "$UI/diagnostics/diag-$BOOT-74.txt" ] || fail 'latest local diagnosis archive missing'
grep -q retained-failure "$R/storage/usb0/gen5w-kr-diag/failure-$BOOT/START" || fail 'automatic failure evidence not exported'
rm "$R/proc/mounts"; ln -s "$t/elsewhere" "$R/proc/mounts"
envelope save=75; collect; expect saved 75:nousb 'foreign mounts link'
rm "$R/proc/mounts"; mv "$R/proc/self/mounts" "$R/proc/mounts"

# A persisted interrupted save must not block the next one. Evidence export
# failure must remain visible and a fresh attempt must publish a complete copy.
echo '75 working' > "$N/gen5wkr.ui-portable-saved"
echo "$BOOT|99999999:1" > "$UI/save-worker"
mkdir -p "$P/diagnostics/failure-copy-test"
echo retry-evidence > "$P/diagnostics/failure-copy-test/START"
mkdir "$R/storage/usb0/gen5w-kr-diag/failure-copy-test.part-76"
envelope save=76; collect; expect saved 76:fail 'evidence export failure'
[ ! -e "$R/storage/usb0/gen5w-kr-diag/failure-copy-test/USB-COMPLETE" ] || fail 'incomplete evidence published'
envelope save=77; collect; expect saved 77:usb 'retry after interrupted save'
grep -q retry-evidence "$R/storage/usb0/gen5w-kr-diag/failure-copy-test/START" || fail 'evidence retry absent'
[ -f "$R/storage/usb0/gen5w-kr-diag/failure-copy-test/USB-COMPLETE" ] || fail 'completed export marker absent'

pass 'diagnosis export: in-car copy, USB only on verified FAT mount, links refused, private lines dropped'

# 9. Root-owned output only: a linked UI folder or marker stops all writes.
rm -rf "$UI"; mkdir "$t/elsewhere-ui"; ln -s "$t/elsewhere-ui" "$UI"
collect; [ -z "$(ls "$t/elsewhere-ui")" ] || fail 'wrote through a linked UI folder'
rm "$UI"; ln -s "$t/target" "$M"; envelope wireless=off; collect; [ ! -e "$t/target" ] || fail 'followed a linked marker'
[ ! -e "$UI/status" ] || fail 'status written while a marker is a link'
rm "$M"; collect; [ -f "$UI/status" ] || fail 'did not recover'
pass 'symlinked UI folder or marker: nothing written'
# 10. A missing session epoch (no session yet) must not write a shell error every round (VM 2026-11-20).
rm -f "$P/session/epoch" "$P/session/ready"; collect
! grep -q "can't open\|open: No such" "$t/out" || fail "missing session file reported as a shell error: $(cat "$t/out")"
expect portable_session stopped 'no session'
pass 'missing session files read quietly'
[ -z "${PORTABLE_UI_EXPORT:-}" ] || cp "$UI/status" "$UI/log" "$PORTABLE_UI_EXPORT/"
