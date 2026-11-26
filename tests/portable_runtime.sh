#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
t=$(mktemp -d /tmp/gen5w-runtime.XXXXXX)
trap 'rc=$?; rm -rf "$t"; exit $rc' EXIT
mkdir -p "$t/root/data/bundle/dalvik" "$t/root/data/bundle/bin" "$t/root/system/lib" "$t/props"
cp tools/portable/runtime.sh tools/portable/wrap-*.sh "$t/root/data/bundle/"
for file in engine.jar adapter.jar libgen5whook.so hook-vm-test.jar; do echo authored > "$t/root/data/bundle/dalvik/$file"; done
echo vm-fixture > "$t/root/system/lib/libdvm.so"
sha256sum "$t/root/system/lib/libdvm.so" | cut -d' ' -f1 > "$t/root/data/bundle/dalvik/abi.sha256"
cat > "$t/root/data/bundle/bin/dex-patch" <<'SH'
#!/bin/bash
sha256sum "$2" | cut -d' ' -f1
SH
chmod +x "$t/root/data/bundle/bin/dex-patch"
cat > "$t/adapter" <<'SH'
#!/bin/bash
case "$1" in
get) cat "$PROPS/$2" 2>/dev/null || :;;
set)
 [ ${#2} -le 31 ] && [ ${#3} -le 91 ] || exit 1
 if [ -f "$PROPS/fail" ] && [ "$(cat "$PROPS/fail")" = "$2" ]; then rm "$PROPS/fail"; exit 1; fi
 printf '%s\n' "$3" > "$PROPS/$2";;
healthy) [ "$(cat "$PROPS/init.svc.zygote")" = running ] && [ "$(cat "$PROPS/sys.boot_completed")" = 1 ] && [ ! -f "$PROPS/framework.notready" ];;
probe) test ! -f "$PROPS/probe.fail";;
feature) test ! -f "$PROPS/feature.$2.missing";;
boot) cat "$PROPS/boot";;
*) exit 1;;
esac
SH
chmod +x "$t/adapter"
export PROPS=$t/props PORTABLE_TEST_ROOT=$t/root PORTABLE_TEST_RUNTIME_ADAPTER=$t/adapter
echo boot1 > "$PROPS/boot"
echo stopped > "$PROPS/init.svc.zygote"
echo usb > "$PROPS/persist.ium.support"
run() { mksh "$t/root/data/bundle/runtime.sh" "$@"; }
preflight() {
 echo running > "$PROPS/init.svc.zygote"; echo 1 > "$PROPS/sys.boot_completed"
 run preflight
 echo stopped > "$PROPS/init.svc.zygote"
}
touch "$PROPS/feature.bt.missing"
if run enable both >/dev/null 2>&1; then echo 'FAIL ignored missing bt prerequisite'; exit 1; fi
[ ! -f "$PROPS/wrap.com.daudio.app.dipo" ]
[ "$(cat "$PROPS/persist.ium.support")" = usb ]
rm "$PROPS/feature.bt.missing"
# A transient readiness failure must be distinguishable from ABI rejection,
# and must retire an earlier same-boot proof before any retry is attempted.
mkdir -p "$t/root/data/local/gen5w-portable/runtime"
echo stale > "$t/root/data/local/gen5w-portable/runtime/preflight"
touch "$PROPS/framework.notready"
rc=0; run preflight >/dev/null 2>&1 || rc=$?
[ "$rc" = 75 ] || { echo 'FAIL transient readiness not classified'; exit 1; }
[ ! -e "$t/root/data/local/gen5w-portable/runtime/preflight" ] || { echo 'FAIL stale preflight proof retained'; exit 1; }
rm "$PROPS/framework.notready"
echo 'PASS transient readiness is retryable and retires its stale proof'

touch "$PROPS/probe.fail"
echo running > "$PROPS/init.svc.zygote"; echo 1 > "$PROPS/sys.boot_completed"
rc=0; run preflight >/dev/null 2>&1 || rc=$?
[ "$rc" = 77 ] || { echo "FAIL accepted failed live ABI probe"; exit 1; }
echo stopped > "$PROPS/init.svc.zygote"
if run enable both >/dev/null 2>&1; then echo "FAIL accepted missing same-boot preflight"; exit 1; fi
[ ! -f "$PROPS/wrap.com.daudio.app.dipo" ]
rm "$PROPS/probe.fail"
echo compatible-unseen-vm > "$t/root/system/lib/libdvm.so"
preflight
# An open console stdin must not become the artifact list or block preflight.
echo running > "$PROPS/init.svc.zygote"
mkfifo "$t/console"
exec 9<> "$t/console"
timeout 5 mksh "$t/root/data/bundle/runtime.sh" preflight <&9
exec 9>&-
seal=$t/root/data/local/gen5w-portable/runtime/preflight
[ "$(wc -l < "$seal")" = 10 ] || { echo 'FAIL incomplete artifact seal'; exit 1; }
echo changed >> "$t/root/data/bundle/dalvik/engine.jar"
echo stopped > "$PROPS/init.svc.zygote"
rc=0; run enable both >/dev/null 2>&1 || rc=$?
[ "$rc" = 77 ] || { echo 'FAIL accepted changed sealed artifact'; exit 1; }
echo authored > "$t/root/data/bundle/dalvik/engine.jar"
preflight
run enable both
[ "$(cat "$PROPS/wrap.com.google.android.project")" = '/system/bin/sh /data/bundle/wrap-gpm.sh' ]
[ "$(cat "$PROPS/persist.ium.support")" = usb ]
echo running > "$PROPS/init.svc.zygote"; echo 1 > "$PROPS/sys.boot_completed"
run commit
run status | grep -qx 'runtime|committed'
if run disable >/dev/null 2>&1; then echo 'FAIL removed wrapper while app could be active'; exit 1; fi
echo stopped > "$PROPS/init.svc.zygote"
run disable
[ -z "$(cat "$PROPS/wrap.com.daudio.app.dipo")" ]
[ "$(cat "$PROPS/persist.ium.support")" = usb ]
echo wrap.com.google.android.project > "$PROPS/fail"
preflight
if run enable both >/dev/null 2>&1; then echo 'FAIL ignored partial property failure'; exit 1; fi
[ -z "$(cat "$PROPS/wrap.com.daudio.app.dipo")" ]
[ "$(cat "$PROPS/persist.ium.support")" = usb ]
run status | grep -qx 'runtime|disabled'
preflight; run enable dipo
echo foreign > "$PROPS/wrap.com.daudio.app.dipo"
if run disable >/dev/null 2>&1; then echo 'FAIL overwrote foreign wrapper'; exit 1; fi
[ "$(cat "$PROPS/wrap.com.daudio.app.dipo")" = foreign ]
echo boot2 > "$PROPS/boot"
run disable
[ "$(cat "$PROPS/wrap.com.daudio.app.dipo")" = foreign ]
if run enable dipo >/dev/null 2>&1; then echo 'FAIL overwrote preexisting wrapper'; exit 1; fi
echo 'PASS portable runtime: KitKat truncation, explicit stopped activation, commit, transaction rollback, ownership, reboot expiry'
# Persistent projection property is still ours after reboot; expired wrappers are not.
printf '\n' > "$PROPS/wrap.com.daudio.app.dipo"
preflight; run enable gpm
echo boot3 > "$PROPS/boot"
printf '\n' > "$PROPS/wrap.com.google.android.project"
run disable
[ "$(cat "$PROPS/persist.ium.support")" = usb ]
# Interrupted transactions can recover after a dead lock owner.
mkdir "$t/root/data/local/gen5w-portable/runtime/lock"
echo 999999999 > "$t/root/data/local/gen5w-portable/runtime/lock/owner"
run status | grep -qx 'runtime|disabled'
echo 'PASS runtime persistent-property and stale-lock recovery'
# Wrapper validates its location and common file before sourcing any code.
mkdir "$t/attack"
cp tools/portable/wrap-dipo.sh "$t/attack/"
printf 'echo compromised > "%s"\n' "$t/compromised" > "$t/malicious"
ln -s "$t/malicious" "$t/attack/wrap-common.sh"
# It never blocks the app: the stock command runs unchanged, without the hook.
printf '#!/bin/sh
echo "stock preload=${LD_PRELOAD:-none} args=$*" > "%s"
' "$t/stock-ran" > "$t/stock"; chmod +x "$t/stock"
mksh "$t/attack/wrap-dipo.sh" "$t/stock" --application >/dev/null 2>&1 || { echo 'FAIL wrapper did not run the stock command'; exit 1; }
[ ! -e "$t/compromised" ]
[ "$(cat "$t/stock-ran")" = 'stock preload=none args=--application' ] || { echo 'FAIL stock command changed'; cat "$t/stock-ran"; exit 1; }
# A missing package (wrapper file gone, build.prop property kept) still starts the app.
rm -f "$t/stock-ran"
mksh -c 'W=/data/nemesis/apps/gen5w.kr.portable-absent/wrap-dipo.sh;[ -f $W ]||W=;exec ${W:+sh $W} '"$t/stock"' --application' || { echo 'FAIL property fallback'; exit 1; }
[ "$(cat "$t/stock-ran")" = 'stock preload=none args=--application' ] || { echo 'FAIL property fallback changed the command'; exit 1; }
echo 'PASS wrapper refuses unsafe sourced path and falls back to the stock start'
# Zygote blocks all app starts until a wrapped child reports its pid; the wrapper
# reports it before anything slow and hands WrapperInit fd 0 (VM 2026-11-20).
for w in wrap-dipo.sh wrap-gpm.sh wrap-navi.sh; do
    rm -f "$t/pid-pipe" "$t/pid-bytes" "$t/stock-ran"; mkfifo "$t/pid-pipe"
    ( od -An -tu1 < "$t/pid-pipe" | tr -s ' ' ' ' > "$t/pid-bytes" ) & reader=$!
    printf '#!/bin/sh\necho "pid=$$ args=$*" > "%s"\n' "$t/stock-ran" > "$t/stock-pid"; chmod +x "$t/stock-pid"
    mksh "tools/portable/$w" /bin/sh "$t/stock-pid" --application '--nice-name=a b' com.android.internal.os.WrapperInit 7 19 x 7> "$t/pid-pipe" ||
        { echo "FAIL $w early pid: command failed"; exit 1; }
    wait "$reader"
    ran=$(cat "$t/stock-ran"); pid=${ran#pid=}; pid=${pid%% *}
    set -- $(cat "$t/pid-bytes")
    [ "$#" = 4 ] && [ $(( ($1 << 24) + ($2 << 16) + ($3 << 8) + $4 )) = "$pid" ] || { echo "FAIL $w reported pid bytes '$*' for $ran"; exit 1; }
    [ "${ran#* }" = 'args=--application --nice-name=a b com.android.internal.os.WrapperInit 0 19 x' ] || { echo "FAIL $w did not hand WrapperInit fd 0: $ran"; exit 1; }
done
# Without a usable pipe the command is unchanged (WrapperInit reports as stock).
mksh tools/portable/wrap-dipo.sh "$t/stock-pid" com.android.internal.os.WrapperInit 9 19 9>/dev/null
case "$(cat "$t/stock-ran")" in *'args=com.android.internal.os.WrapperInit 9 19') :;; *) echo 'FAIL non-pipe fd changed the command'; exit 1;; esac
echo 'PASS wrappers report the app pid to zygote before the slow VM start'
# No priority change in the wrapped app: Dalvik nukes a thread (SIGSTKFLT) that
# cannot reach a GC suspend point in time, and low-priority preload threads on a
# busy unit did not (VM 2026-11-21).
! grep -q renice tools/portable/wrap-dipo.sh tools/portable/wrap-gpm.sh tools/portable/wrap-navi.sh || { echo 'FAIL wrapper changes app priority'; exit 1; }
echo 'PASS wrappers leave the app at stock priority'

# The no-hook startup probe bypasses engine discovery and never writes persist.*.
run enable probe
[ "$(cat "$PROPS/wrap.com.daudio.app.dipo")" = '/system/bin/sh /data/bundle/wrap-probe.sh' ]
[ "$(cat "$PROPS/persist.ium.support")" = usb ]
run disable
echo 'PASS explicit no-hook startup probe and persistent configuration unchanged'

# A cold boot expires owned wrapper transactions without requiring manual disable.
preflight; run enable both
echo boot4 > "$PROPS/boot"
printf '\n' > "$PROPS/wrap.com.daudio.app.dipo"
printf '\n' > "$PROPS/wrap.com.google.android.project"
printf '\n' > "$PROPS/wrap.com.mnsoft.navi"
preflight; run enable both
run status | grep -qx 'runtime|pending'
run disable
# Capability rejection is distinct from an IO/ownership transaction failure.
touch "$PROPS/probe.fail"
rm -f "$t/root/data/local/gen5w-portable/runtime/preflight"
echo running > "$PROPS/init.svc.zygote"; echo 1 > "$PROPS/sys.boot_completed"
rc=0; run preflight || rc=$?
[ "$rc" = 77 ]
echo stopped > "$PROPS/init.svc.zygote"
rc=0; run enable both || rc=$?
[ "$rc" = 77 ]
run status | grep -qx 'runtime|disabled'
[ -z "$(cat "$PROPS/wrap.com.daudio.app.dipo")" ]
echo 'PASS automatic cold-boot wrapper renewal and capability exit status'

LOCK_STATE=$t/root/data/local/gen5w-portable/runtime
LOCK_BOOT_FILE=$PROPS/boot

# Boot-aware identity locks: reused PIDs, PID reuse in the same boot,
# zombies, and interrupted owner/recover publication must all be recoverable.
lock_key() { python3 - "$1" <<'PYKEY'
import sys
pid=sys.argv[1]
print(pid+':'+open('/proc/'+pid+'/stat').read().rsplit(') ',1)[1].split()[19])
PYKEY
}
current_boot=$(cat "$LOCK_BOOT_FILE")
live_key=$(lock_key $$)
mkdir -p "$LOCK_STATE/lock"
printf '%s|%s\n' "$current_boot" "$live_key" > "$LOCK_STATE/lock/owner"
if run status > /dev/null 2>&1; then echo 'FAIL stole live identity lock'; exit 1; fi
[ "$(cat "$LOCK_STATE/lock/owner")" = "$current_boot|$live_key" ]
# A legitimate concurrent status reader releases its lock normally.
( sleep 1; rm "$LOCK_STATE/lock/owner"; rmdir "$LOCK_STATE/lock" ) & reader=$!
if ! run status > /dev/null 2>&1; then
 wait "$reader"
 echo 'FAIL transient status lock treated as permanent failure'; exit 1
fi
wait "$reader"
mkdir -p "$LOCK_STATE/lock"
printf '%s|%s\n' "$current_boot" "$live_key" > "$LOCK_STATE/lock/owner"
echo 'PASS status waits for a transient legitimate reader without stealing ownership'
printf 'previous-boot|%s\n' "$live_key" > "$LOCK_STATE/lock/owner"
run status > /dev/null
[ ! -d "$LOCK_STATE/lock" ]
mkdir "$LOCK_STATE/lock"
printf '%s|%s:0\n' "$current_boot" "$$" > "$LOCK_STATE/lock/owner"
run status > /dev/null
mkdir -p "$LOCK_STATE/lock/recover"
run status > /dev/null
mkdir -p "$LOCK_STATE/lock/lock.claim.999999999.0"
printf '%s|999999999:0\n' "$current_boot" > "$LOCK_STATE/lock/owner"
printf '%s|999999999:0\n' "$current_boot" > "$LOCK_STATE/lock/lock.claim.999999999.0/owner"
run status > /dev/null
# A real zombie deliberately remains unreaped: kill -0 succeeds for it.
python3 - "$t/zombie" <<'PYZOMBIE' &
import os,sys,time
path=sys.argv[1]
pid=os.fork()
if pid == 0: os._exit(0)
while open('/proc/'+str(pid)+'/stat').read().rsplit(') ',1)[1].split()[0] != 'Z': time.sleep(.01)
open(path,'w').write(str(pid))
while not os.path.exists(path+'.release'): time.sleep(.01)
os.waitpid(pid,0)
PYZOMBIE
zombie_parent=$!
count=0
while [ ! -s "$t/zombie" ]; do count=$((count+1)); [ "$count" -lt 100 ] || exit 1; sleep .02; done
zombie=$(cat "$t/zombie")
kill -0 "$zombie"
mkdir "$LOCK_STATE/lock"
printf '%s|%s\n' "$current_boot" "$(lock_key "$zombie")" > "$LOCK_STATE/lock/owner"
run status > /dev/null
touch "$t/zombie.release"
wait "$zombie_parent"
[ ! -d "$LOCK_STATE/lock" ]
# Unsafe persisted records remain untouched.
mkdir "$LOCK_STATE/lock"
ln -s "$LOCK_BOOT_FILE" "$LOCK_STATE/lock/owner"
if run status > /dev/null 2>&1; then echo 'FAIL accepted symlink owner'; exit 1; fi
[ -L "$LOCK_STATE/lock/owner" ]
rm "$LOCK_STATE/lock/owner"; rmdir "$LOCK_STATE/lock"
# Concurrent stale-lock recovery never leaves a wedged directory or parallel
# owner record; losing calls may safely refuse, and the final call must work.
mkdir "$LOCK_STATE/lock"
printf '%s|999999999:0\n' "$current_boot" > "$LOCK_STATE/lock/owner"
workers=''
for worker in 1 2 3 4 5 6 7 8; do (run status >/dev/null 2>&1 || :) & workers="$workers $!"; done
for worker in $workers; do wait "$worker"; done
run status > /dev/null
[ ! -d "$LOCK_STATE/lock" ]
echo 'PASS identity locks: live owner, boot/PID reuse, zombie, incomplete recovery, symlink and concurrent reclamation'

rm "$PROPS/probe.fail"
touch "$PROPS/feature.gpm.missing"
preflight; run enable both
[ -n "$(cat "$PROPS/wrap.com.daudio.app.dipo")" ]
[ -z "$(cat "$PROPS/wrap.com.google.android.project")" ]
run disable
rm "$PROPS/feature.gpm.missing"
echo foreign > "$PROPS/wrap.com.google.android.project"
preflight; run enable both
[ -n "$(cat "$PROPS/wrap.com.daudio.app.dipo")" ]
[ "$(cat "$PROPS/wrap.com.google.android.project")" = foreign ]
run disable
[ "$(cat "$PROPS/wrap.com.google.android.project")" = foreign ]
echo 'PASS optional GPM prerequisite and foreign wrapper do not affect DiPO'
