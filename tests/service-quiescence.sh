#!/bin/bash
cd "$(dirname "$0")/.." || exit 1
. tests/lib.sh
W=$(mktemp -d)
# Persistent leftovers are refused after this wait; keep the suite fast.
export IT_Q_DRAIN=2
mkdir -p "$W/data/nemesis/pids" "$W/proc" "$W/apps" "$W/tx"
echo "$$" > "$W/data/nemesis/svcmgr.pid"
mkdir -p "$W/tx/lock"
echo "$$" > "$W/tx/lock/pid"
cat > "$W/nemesis" <<'EOF'
#!/bin/sh
case "$1:$2" in
 version:) echo "${QV:-1.16.7}";;
 service:list) [ -z "$QEPOCH" ] || echo "$QEPOCH" > "$QT/data/nemesis/svcmgr.pid"
  if [ -n "$QFLIP" ]; then
   n=$(cat "$QT/listcount" 2>/dev/null || echo 0); n=$((n+1)); echo "$n" > "$QT/listcount"
   # Instance launcher ("am start" shell) ends after the first QFLIP listings.
   [ "$n" -le "$QFLIP" ] || { [ -z "$QFLIPPID" ] || kill "$QFLIPPID" 2>/dev/null; sed -i 's/|running|[0-9]*/|stopped|0/' "$QT/inventory"; }
  fi
  cat "$QT/inventory";;
 service:stop)
  echo "$3" >> "$QT/stops"
  [ "$QSTOPFAIL" != 1 ] || exit 1
  [ -z "$QREALROOT" ] || kill -TERM "$QREALROOT"
  if [ "$QLATE" = 1 ] && [ ! -f "$QT/late-pid" ]; then /usr/bin/setsid /bin/sleep 30 </dev/null >/dev/null 2>&1 & echo "$!" > "$QT/late-pid"; fi
  key=$(echo "$3" | sed 's#/# +#g;s# ##g')
  [ "$QNOMARK" = 1 ] || echo 1 > "$QT/data/nemesis/pids/$key.stopped"
  [ "$QSTILL" = 1 ] || sed -i 's/|running|[0-9]*/|stopped|0/' "$QT/inventory";;
 service:start) echo "$3" >> "$QT/starts";;
 *) exit 1;;
esac
EOF
chmod +x "$W/nemesis"
: > "$W/inventory"
cat > "$W/runner" <<EOF
DATA='$W/data'; APPS='$W/apps'; TX='$W/tx'; NEM='$W/nemesis'
report() { echo "\$*"; }
. '$PWD/tools/integrated/services.sh'
q_begin
EOF
run() { QT="$W" mksh "$W/runner" > "$W/out" 2>&1; }
new_boot() { echo '00000000-0000-0000-0000-000000000000' > "$W/tx/service-uncertain"; }
check 'supported empty inventory permits preparation' run
QV=1.16.3 run
check 'legacy version refuses new install' test $? != 0
QV=1.17.0 run
check 'numeric future version permits preparation with safety checks' test $? = 0
echo 'stock.telephony/main|restart|running|12' > "$W/inventory"
check 'foreign services are not stopped' eval 'run && test ! -s "$W/stops"'
echo 'gen5w.kr.core/uilog|restart|running|0' > "$W/inventory"
check 'contradictory running PID refuses' eval '! run'
echo 'gen5w.kr.core/../uilog|restart|stopped|0' > "$W/inventory"
check 'unsafe qualified service refuses' eval '! run'
echo 'gen5w.kr.core/uilog|restart|stopped|0' > "$W/inventory"
QNOMARK=1 run
check 'stop API success without durable stop proof refuses' test $? != 0
new_boot
check 'stopped registered service is held by supported API' run
# Repeated barriers without an install in between use the short re-check.
cp "$W/runner" "$W/fast-runner"
printf 'q_barrier || exit 1
q_barrier || exit 1
q_invalidate
q_barrier || exit 1
' >> "$W/fast-runner"
new_boot; : > "$W/stops"
QT="$W" mksh "$W/fast-runner" > "$W/out" 2>&1
fast_rc=$?
check 'repeated barrier passes' test "$fast_rc" = 0
check 'repeated barrier without install uses the short re-check' test "$(grep -c 'unchanged since the last full proof' "$W/out")" = 2
check 'after an install the full proof runs again' test "$(grep -c '^QUIESCENT: owned services stopped' "$W/out")" = 2
echo 'gen5w.kr.core/uilog|restart|stopped|0' > "$W/inventory"
cp "$W/runner" "$W/fast-runner2"
sleep 30 & again_pid=$!
printf 'q_barrier || exit 1
echo "gen5w.kr.core/uilog|restart|running|%s" > "%s/inventory"
q_barrier
' "$again_pid" "$W" >> "$W/fast-runner2"
new_boot
QT="$W" mksh "$W/fast-runner2" > "$W/out" 2>&1
kill "$again_pid" 2>/dev/null; wait "$again_pid" 2>/dev/null || true
check 'a service running again is never passed by the short re-check' eval 'test "$(grep -c "unchanged since the last full proof" "$W/out")" = 1 && tail -n 3 "$W/out" | grep -q "^REFUSED"'
echo 'gen5w.kr.core/uilog|restart|stopped|0' > "$W/inventory"
new_boot
sleep 30 & epoch_pid=$!
QEPOCH="$epoch_pid" run
check 'supervisor restart between identity and inventory refuses' test $? != 0
echo "$$" > "$W/data/nemesis/svcmgr.pid"
check 'original supervisor allows retry after failed inventory' run
echo "$epoch_pid" > "$W/data/nemesis/svcmgr.pid"
check 'new runner cannot forget prior supervisor identity' eval '! run'
echo "$$" > "$W/data/nemesis/svcmgr.pid"
kill "$epoch_pid" 2>/dev/null; wait "$epoch_pid" 2>/dev/null || true
QLATE=1 run
check 'child created after ancestry snapshot cannot pass stop proof' test $? != 0
check 'late child evidence survives a new runner' eval '! run'
late_pid=$(cat "$W/late-pid")
kill "$late_pid" 2>/dev/null || true
rm "$W/late-pid"
check 'ambiguous late child requires cold boot even after exit' eval '! run'
echo '00000000-0000-0000-0000-000000000000' > "$W/tx/service-uncertain"
check 'prior-boot uncertainty does not block a fresh proof' run
cat > "$W/session-root" <<'EOF'
import os,signal
middle=os.fork()
if middle == 0:
    child=os.fork()
    if child == 0:
        devnull=os.open('/dev/null',os.O_RDWR)
        for fd in (0,1,2): os.dup2(devnull,fd)
        os.execl('/bin/sleep','sleep','300')
    with open(os.environ['QT']+'/orphan-pid','w') as out: out.write(str(child))
    os._exit(0)
os.waitpid(middle,0)
with open(os.environ['QT']+'/orphan-ready','w') as out: out.write('ready')
signal.pause()
EOF
QT="$W" /usr/bin/setsid /usr/bin/python3 "$W/session-root" & session_root=$!
for attempt in {1..100}; do [ ! -f "$W/orphan-ready" ] || break; sleep 0.01; done
echo "gen5w.kr.core/uilog|restart|running|$session_root" > "$W/inventory"
QREALROOT="$session_root" run
orphan_rc=$?
check 'already-reparented child in owned session cannot pass as baseline stock' test "$orphan_rc" != 0
check 'refusal names the process left behind' grep -q 'still running after 2s wait:.*:sleep' "$W/out"
orphan_pid=$(cat "$W/orphan-pid")
[ "$orphan_rc" != 0 ] || { cat "$W/out"; cat "/proc/$orphan_pid/stat" 2>/dev/null; }
kill "$session_root" "$orphan_pid" 2>/dev/null || true
wait "$session_root" 2>/dev/null || true
echo '00000000-0000-0000-0000-000000000000' > "$W/tx/service-uncertain"
# Real car (v0.3.64 -> v0.3.65 update): a stopped service shell leaves an
# orphaned "sleep" in its session for a few seconds. Waited for, not refused.
sed -e "s#'sleep','300'#'sleep','3'#" -e 's#orphan-#short-#g' "$W/session-root" > "$W/short-root"
QT="$W" /usr/bin/setsid /usr/bin/python3 "$W/short-root" & short_root=$!
for attempt in {1..100}; do [ ! -f "$W/short-ready" ] || break; sleep 0.01; done
echo "gen5w.kr.core/uilog|restart|running|$short_root" > "$W/inventory"
QREALROOT="$short_root" IT_Q_DRAIN=10 run
short_rc=$?
check 'short-lived child left by a stopped service is waited for' test "$short_rc" = 0
[ "$short_rc" = 0 ] || cat "$W/out"
check 'waiting never signals the leftover child' eval '! grep -q "kill" "$W/out"'
wait "$short_root" 2>/dev/null || true
echo '00000000-0000-0000-0000-000000000000' > "$W/tx/service-uncertain"
# Real car: the timer's "logcat -s ConsentScreen" reader outlives its stopped
# shell until the next matching line. Only such a logcat in our session is stopped.
printf '#!/usr/bin/python3
import time
time.sleep(300)
' > "$W/logcat"; chmod +x "$W/logcat"
sed -e "s#os.execl('/bin/sleep','sleep','300')#os.execl(os.environ['QT']+'/logcat','logcat','300')#" -e 's#orphan-#lc-#g' "$W/session-root" > "$W/lc-root"
QT="$W" /usr/bin/setsid /usr/bin/python3 "$W/lc-root" & lc_root=$!
for attempt in {1..100}; do [ ! -f "$W/lc-ready" ] || break; sleep 0.01; done
echo "gen5w.kr.core/uilog|restart|running|$lc_root" > "$W/inventory"
QREALROOT="$lc_root" IT_Q_DRAIN=10 run
lc_rc=$?
lc_pid=$(cat "$W/lc-pid")
check 'leftover logcat of a stopped service is stopped and the proof passes' test "$lc_rc" = 0
[ "$lc_rc" = 0 ] || cat "$W/out"
check 'the leftover logcat is reported' grep -q "STOPPED leftover logcat $lc_pid" "$W/out"
check 'the leftover logcat is gone' eval '! kill -0 "$lc_pid" 2>/dev/null || grep -q " Z " "/proc/$lc_pid/stat"'
wait "$lc_root" 2>/dev/null || true
echo '00000000-0000-0000-0000-000000000000' > "$W/tx/service-uncertain"
echo "gen5w.kr.core/uilog|restart|running|$session_root" > "$W/inventory"
QSTOPFAIL=1 run
check 'stop failure refuses preparation' test $? != 0
new_boot
echo 'gen5w.kr.core/uilog|restart|stopped|0' >> "$W/inventory"
check 'duplicate identities refuse' eval '! run'
: > "$W/inventory"
mkdir -p "$W/apps/gen5w.kr.core"
echo '[service.0]' > "$W/apps/gen5w.kr.core/NEMESIS.data"
echo 'name=uilog' >> "$W/apps/gen5w.kr.core/NEMESIS.data"
check 'missing service registry cannot masquerade as empty installation' eval '! run'
echo 'gen5w.kr.core/uilog|restart|stopped|0' > "$W/inventory"
rm -f "$W/data/nemesis/pids/gen5w.kr.core+uilog.stopped"
echo 1 > "$W/sentinel"
ln -s "$W/sentinel" "$W/data/nemesis/pids/gen5w.kr.core+uilog.stopped"
QNOMARK=1 run
check 'linked stop proof is rejected' test $? != 0
rm "$W/data/nemesis/pids/gen5w.kr.core+uilog.stopped"
new_boot
rm -f "$W/apps/gen5w.kr.core/NEMESIS.data"
# A real surviving process proves parent-status changes alone do not suffice.
/usr/bin/setsid /bin/sleep 30 & child=$!
echo "gen5w.kr.core/uilog|restart|running|$child" > "$W/inventory"
check 'live owned process cannot pass merely because API reports stopped' eval '! run'
check 'quiescence never signals an arbitrary captured PID' kill -0 "$child"
check 'new runner retains evidence after registry loses the parent PID' eval '! run'
cp "$W/runner" "$W/retry-runner"
echo 'q_barrier' >> "$W/retry-runner"
QT="$W" mksh "$W/retry-runner" > "$W/out" 2>&1
check 'same runner cannot forget failed descendant on retry' test $? != 0
kill "$child" 2>/dev/null; wait "$child" 2>/dev/null || true
check 'early stop failure remains blocked after child exit until cold boot' eval '! run'
new_boot
check 'fresh boot can verify that retained process has exited' run
boot=$(cat /proc/sys/kernel/random/boot_id)
printf '%s\nsupervisor=none\n123:1:999:S\ncomplete=2\n' "$boot" > "$W/tx/service-processes"
check 'journal count mismatch refuses' eval '! run'
printf '%s\nsupervisor=none\n123:1:999:S' "$boot" > "$W/tx/service-processes"
check 'truncated journal refuses' eval '! run'
printf '%s\nsupervisor=none\n123\ncomplete=1\n' "$boot" > "$W/tx/service-processes"
check 'malformed process identity refuses' eval '! run'
rm "$W/tx/service-processes"
# The independent worker remains alive even if listed as an owned launch PID.
echo 'echo "gen5w.kr.core/uilog|restart|running|$$" > "$QT/inventory"' > "$W/protect"
cat "$W/runner" | sed '/q_begin/i\echo "gen5w.kr.core/uilog|restart|running|$$" > "$QT/inventory"' > "$W/protected-runner"
QT="$W" mksh "$W/protected-runner" > "$W/out" 2>&1
check 'worker identity is protected while verifying stopped services' test $? = 0
mkdir -p "$W/apps/gen5w.kr.core/scripts"
cat > "$W/apps/gen5w.kr.core/scripts/recovery-launch.sh" <<'EOF'
#!/bin/sh
start=$(/usr/bin/awk '{print $22}' /proc/$$/stat)
export GEN5W_RECOVERY_ROOT=$$:$start
echo "gen5w.kr.core/uilog|restart|running|$$" > "$QT/inventory"
/bin/sleep 300 & writer=$!
/usr/bin/mksh "$QT/runner"
rc=$?
kill "$writer" 2>/dev/null; wait "$writer" 2>/dev/null || true
exit "$rc"
EOF
QT="$W" /usr/bin/setsid /usr/bin/mksh "$W/apps/gen5w.kr.core/scripts/recovery-launch.sh" > "$W/out" 2>&1
check 'validated independent launcher retains worker and report-writer sibling' test $? = 0
# Android component is genuinely alive, while its short-lived launcher is not.
bash -c 'exec -a kr.gen5w.core sleep 30' & app_pid=$!
echo 'gen5w.kr.core/core|background|stopped|0' > "$W/inventory"
cat > "$W/am" <<'EOF'
#!/bin/sh
[ "$1" = force-stop ] || exit 1
[ "$2" != kr.gen5w.core ] || kill -TERM "$Q_APP_PID"
exit 0
EOF
chmod +x "$W/am"
cp "$W/runner" "$W/resume-runner"
echo 'q_resume' >> "$W/resume-runner"
Q_APP_PID="$app_pid" IT_AM="$W/am" QT="$W" mksh "$W/resume-runner" > "$W/out" 2>&1
check 'instance component resumes after safe non-mutating preparation' test $? = 0
check 'actual Android state is preserved despite stopped launcher status' grep -qx 'gen5w.kr.core/core' "$W/starts"
wait "$app_pid" 2>/dev/null || true
# Unknown state never resumes a potentially mixed generation.
echo mystery > "$W/tx/state"
: > "$W/starts"
QT="$W" mksh "$W/resume-runner" > "$W/out" 2>&1
check 'unknown transaction state never resumes services' test ! -s "$W/starts"
check 'unknown generation retains startup hold' test -f "$W/data/nemesis/gen5wkr.install-hold"
rm "$W/tx/state"
# NEMESIS lists an instance service as running only while its short "am start"
# shell lives; package install starts it, so it can end during a capture.
mkdir -p "$W/apps/gen5w.kr.core"
printf '[service.0]
name=core
kind=instance
path=kr.gen5w.core/.CoreService
mode=background
' > "$W/apps/gen5w.kr.core/NEMESIS.data"
rm -f "$W/tx/service-uncertain" "$W/tx/service-tracked" "$W/listcount" "$W/data/nemesis/gen5wkr.install-hold"
: > "$W/stops"
/usr/bin/setsid /bin/sleep 60 & launcher=$!
echo "gen5w.kr.core/core|background|running|$launcher" > "$W/inventory"
QFLIP=2 QFLIPPID=$launcher run
rc=$?; [ "$rc" = 0 ] || cat "$W/out"
check 'instance launcher ending during capture is waited for, not refused' test "$rc" = 0
check 'settled instance launcher needs no forced stop proof failure' eval '! grep -q "launcher changed" "$W/out"'
kill "$launcher" 2>/dev/null; wait "$launcher" 2>/dev/null || true
rm -f "$W/listcount" "$W/apps/gen5w.kr.core/NEMESIS.data" "$W/data/nemesis/gen5wkr.install-hold"
: > "$W/inventory"
# Legacy prerequisite failure is exercised through the actual install entrypoint.
mkdir -p "$W/usb" "$W/sys"
cp tools/integrated/*.sh "$W/usb/"
QV=1.16.3 QT="$W" IT_DATA="$W/data" IT_SYSTEM="$W/sys" IT_NEM="$W/nemesis" IT_SHELL=$(command -v mksh) IT_NO_REBOOT=1 mksh "$W/usb/install.sh" > "$W/out" 2>&1
check 'real installer refuses unsupported platform before snapshot' test $? != 0
check 'platform refusal leaves snapshot untouched' test ! -e "$W/data/nemesis/gen5w-kr-integrated/prior"
check 'platform refusal provides separate update instruction' grep -q 'update NEMESIS separately' "$W/out"
rm -rf "$W"
done_tests service-quiescence
