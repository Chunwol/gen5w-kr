#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
t=$(mktemp -d /tmp/gen5w-runtime.XXXXXX)
trap 'rm -rf "$t"' EXIT
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
touch "$PROPS/feature.bt.missing"
if run enable both >/dev/null 2>&1; then echo 'FAIL ignored missing bt prerequisite'; exit 1; fi
[ ! -f "$PROPS/wrap.com.daudio.app.dipo" ]
[ "$(cat "$PROPS/persist.ium.support")" = usb ]
rm "$PROPS/feature.bt.missing"
touch "$PROPS/probe.fail"
if run enable both >/dev/null 2>&1; then echo "FAIL accepted failed live ABI probe"; exit 1; fi
[ ! -f "$PROPS/wrap.com.daudio.app.dipo" ]
rm "$PROPS/probe.fail"
echo compatible-unseen-vm > "$t/root/system/lib/libdvm.so"
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
if run enable both >/dev/null 2>&1; then echo 'FAIL ignored partial property failure'; exit 1; fi
[ -z "$(cat "$PROPS/wrap.com.daudio.app.dipo")" ]
[ "$(cat "$PROPS/persist.ium.support")" = usb ]
run status | grep -qx 'runtime|disabled'
run enable dipo
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
run enable gpm
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
if mksh "$t/attack/wrap-dipo.sh" /system/bin/app_process >/dev/null 2>&1; then echo 'FAIL wrapper accepted unsafe source'; exit 1; fi
[ ! -e "$t/compromised" ]
echo 'PASS wrapper refuses unsafe sourced path'

# The no-hook startup probe bypasses engine discovery and never writes persist.*.
run enable probe
[ "$(cat "$PROPS/wrap.com.daudio.app.dipo")" = '/system/bin/sh /data/bundle/wrap-probe.sh' ]
[ "$(cat "$PROPS/persist.ium.support")" = usb ]
run disable
echo 'PASS explicit no-hook startup probe and persistent configuration unchanged'

# A cold boot expires owned wrapper transactions without requiring manual disable.
run enable both
echo boot4 > "$PROPS/boot"
printf '\n' > "$PROPS/wrap.com.daudio.app.dipo"
printf '\n' > "$PROPS/wrap.com.google.android.project"
run enable both
run status | grep -qx 'runtime|pending'
run disable
# Capability rejection is distinct from an IO/ownership transaction failure.
touch "$PROPS/probe.fail"
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
run enable both
[ -n "$(cat "$PROPS/wrap.com.daudio.app.dipo")" ]
[ -z "$(cat "$PROPS/wrap.com.google.android.project")" ]
run disable
rm "$PROPS/feature.gpm.missing"
echo foreign > "$PROPS/wrap.com.google.android.project"
run enable both
[ -n "$(cat "$PROPS/wrap.com.daudio.app.dipo")" ]
[ "$(cat "$PROPS/wrap.com.google.android.project")" = foreign ]
run disable
[ "$(cat "$PROPS/wrap.com.google.android.project")" = foreign ]
echo 'PASS optional GPM prerequisite and foreign wrapper do not affect DiPO'
