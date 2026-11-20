#!/bin/sh
set -eu
SHELL_UNDER_TEST=${SHELL_UNDER_TEST:-bash}
REPO=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
t=$(mktemp -d)
trap 'rc=$?; rm -rf "$t"; exit $rc' EXIT HUP INT TERM
mkdir -p "$t/data/out" "$t/system/app" "$t/state"
printf old > "$t/system/app/Iap2ServerApp.odex"
printf new > "$t/data/out/a"
chmod 644 "$t/data/out/a" "$t/system/app/Iap2ServerApp.odex"
cat > "$t/adapter" <<'MOCK'
#!/bin/sh
set -eu
echo "$*" >> "$PORTABLE_TEST_ROOT/adapter-events"
identity_for() {
    input=$1
    if [ -f "$PORTABLE_TEST_ROOT/mapping" ]; then
        while IFS='|' read -r source target; do
            if [ "$target" = "$input" ] && grep -Fx "$target" "$PORTABLE_TEST_ROOT/mounts" >/dev/null; then input=$source; break; fi
        done < "$PORTABLE_TEST_ROOT/mapping"
    fi
    if [ -n "${PORTABLE_ARM_HELPER:-}" ]; then qemu-arm "$PORTABLE_ARM_HELPER" identity "$input"; else stat -c '%d:%i' "$input"; fi
}
case "$1" in
boot) cat "$PORTABLE_TEST_ROOT/boot";;
identity) identity_for "$2";;
bound) test ! -f "$PORTABLE_TEST_ROOT/bound.fail" && test "$(identity_for "$2")" = "$(identity_for "$3")";;
healthy|namespace|ready) test ! -f "$PORTABLE_TEST_ROOT/$1.fail";;
sha) if [ -n "${PORTABLE_ARM_HELPER:-}" ]; then qemu-arm "$PORTABLE_ARM_HELPER" sha256 "$2"; else sha256sum "$2" | cut -d ' ' -f1; fi;;
meta) if [ -n "${PORTABLE_ARM_HELPER:-}" ]; then qemu-arm "$PORTABLE_ARM_HELPER" metadata "$2"; else stat -c '%u|%g|%a' "$2"; fi;;
visible) grep -Fx "$2" "$PORTABLE_TEST_ROOT/mounts" >/dev/null;;
bind) test ! -f "$PORTABLE_TEST_ROOT/bind.fail"; if [ -f "$PORTABLE_TEST_ROOT/failtarget" ]; then test "$3" != "$(cat "$PORTABLE_TEST_ROOT/failtarget")"; fi; if [ -d "$2" ]; then mv "$3" "$3.backup"; cp -a "$2" "$3"; fi; echo "$2|$3" >> "$PORTABLE_TEST_ROOT/mapping"; echo "$3" >> "$PORTABLE_TEST_ROOT/mounts";;
unmount) if [ -f "$PORTABLE_TEST_ROOT/fail-unmount-target" ] && [ "$2" = "$(cat "$PORTABLE_TEST_ROOT/fail-unmount-target")" ] && [ ! -f "$PORTABLE_TEST_ROOT/unmount-failed-once" ]; then touch "$PORTABLE_TEST_ROOT/unmount-failed-once"; exit 1; fi; if [ -d "$2.backup" ]; then mv "$2" "$2.overlay"; mv "$2.backup" "$2"; rm -r "$2.overlay"; fi; grep -Fxv "$2" "$PORTABLE_TEST_ROOT/mounts" > "$PORTABLE_TEST_ROOT/m.tmp" || :; mv "$PORTABLE_TEST_ROOT/m.tmp" "$PORTABLE_TEST_ROOT/mounts";;
sync) :;;
stop-android|start-android) exit 99;;
esac
MOCK
chmod +x "$t/adapter"
printf boot1 > "$t/boot"
: > "$t/mounts"
export PORTABLE_TEST_ROOT=$t PORTABLE_STATE_DIR=$t/state PORTABLE_TEST_ADAPTER=$t/adapter
hash=$(sha256sum "$t/data/out/a" | cut -d ' ' -f1)
meta=$(stat -c '%u|%g|%a' "$t/data/out/a")
printf 'bt|/data/out/a|/system/app/Iap2ServerApp.odex|%s|%s|static\n' "$hash" "$meta" > "$t/manifest"
run() { "$SHELL_UNDER_TEST" "$REPO/tools/portable/overlay.sh" "$@"; }
fail() { if run "$@" > "$t/error" 2>&1; then echo "unexpected success: $*" >&2; exit 1; fi; }
run prepare "$t/manifest" bt
run apply
run status | grep 'bt|active' >/dev/null
run commit
touch "$t/ready.fail"
fail disable
test -s "$t/mounts"
fail prepare "$t/manifest"
test -s "$t/mounts"
run status | grep 'bt|active' >/dev/null
rm "$t/ready.fail"
run disable
test ! -s "$t/mounts"
# Revalidate source at apply, not merely prepare.
run prepare "$t/manifest"
printf changed > "$t/data/out/a"
fail apply
test ! -s "$t/mounts"
printf new > "$t/data/out/a"
run prepare "$t/manifest"
touch "$t/ready.fail"
fail apply
rm "$t/ready.fail"
run prepare "$t/manifest"
touch "$t/namespace.fail"
fail apply
rm "$t/namespace.fail"
run prepare "$t/manifest"
run apply
printf boot2 > "$t/boot"
fail apply
test ! -s "$t/mounts"
run status | grep 'state|failed' >/dev/null
# Explicit prepare is needed to recover persistent failed guard.
run prepare "$t/manifest"
run apply
run disable
# Duplicate target and symlink rejected.
cat "$t/manifest" "$t/manifest" > "$t/duplicate"
fail prepare "$t/duplicate"
mv "$t/data/out/a" "$t/data/out/real"
ln -s real "$t/data/out/a"
fail prepare "$t/manifest"
echo 'portable overlay tests passed'
# Directory overlays retain all stock XML files and add authored entries.
rm "$t/data/out/a"
mkdir -p "$t/system/etc/permissions" "$t/data/perms"
printf stock > "$t/system/etc/permissions/stock.xml"
cp "$t/system/etc/permissions/stock.xml" "$t/data/perms/stock.xml"
printf extra > "$t/data/perms/extra.xml"
chmod 755 "$t/data/perms" "$t/system/etc/permissions"
chmod 644 "$t/data/perms/"*.xml "$t/system/etc/permissions/stock.xml"
inv() {
    for f in "$1/"*.xml; do
        printf '%s|%s|%s\n' "${f##*/}" "$(sha256sum "$f" | cut -d ' ' -f1)" "$(stat -c '%u|%g|%a' "$f")"
    done
}
inv "$t/data/perms" > "$t/data/perms.inventory"
inv "$t/system/etc/permissions" > "$t/data/perms.stock-inventory"
digest=$(cat "$t/data/perms.inventory" "$t/data/perms.stock-inventory" | sha256sum | cut -d ' ' -f1)
printf 'projection|/data/perms|/system/etc/permissions|%s|%s|directory\n' "$digest" "$(stat -c '%u|%g|%a' "$t/data/perms")" > "$t/directory"
run prepare "$t/directory"
run apply
run status | grep 'projection|active' >/dev/null
run commit
run disable
printf corrupt > "$t/system/etc/permissions/stock.xml"
fail prepare "$t/directory"
printf stock > "$t/system/etc/permissions/stock.xml"
printf hidden > "$t/data/perms/.hidden"
fail prepare "$t/directory"
rm "$t/data/perms/.hidden"
run prepare "$t/directory"
printf changed > "$t/data/perms/extra.xml"
fail apply
echo 'portable directory tests passed'
# Status is read-only: interrupted work is reported, not unmounted while apps
# may still be using it. Explicit maintenance disable performs recovery.
printf extra > "$t/data/perms/extra.xml"
run prepare "$t/directory"
printf applying > "$t/state/state"
printf '/system/etc/permissions|%s\n' "$(stat -c '%d:%i' "$t/data/perms")" > "$t/state/journal"
printf '%s\n' "$t/system/etc/permissions" > "$t/mounts"
run status | grep 'state|failed' >/dev/null
test -s "$t/mounts"
run disable
test ! -s "$t/mounts"
# Dead owner lock is reclaimed, live owner lock is respected.
mkdir "$t/state/lock"
printf '999999999\n' > "$t/state/lock/owner"
run status >/dev/null
mkdir "$t/state/lock"
printf '%s\n' "$$" > "$t/state/lock/owner"
fail status
rm "$t/state/lock/owner"
rmdir "$t/state/lock"
# Group mount failure includes the potentially mounted current journal item.
run prepare "$t/directory"
touch "$t/bound.fail"
fail apply
test ! -s "$t/mounts"
rm "$t/bound.fail"
echo 'portable recovery tests passed'
# Partial feature selection excludes an unsupported unrelated entry.
printf new > "$t/data/out/a"
printf '%s\n' "bt|/data/out/a|/system/app/Iap2ServerApp.odex|$hash|$meta|static" > "$t/manifest"
printf 'unsupported|/data/missing|/system/unknown|bad|0|0|644|runtime\n' >> "$t/manifest"
run prepare "$t/manifest" bt
run apply
# Same-boot apply requires explicit disable/prepare; never stacks binds.
fail apply
printf corrupt > "$t/data/out/a"
run status | grep 'state|failed' >/dev/null
test -s "$t/mounts"
run disable
test ! -s "$t/mounts"
printf new > "$t/data/out/a"
# True multi-file apply failure rolls back already completed binds.
printf second > "$t/data/out/b"
printf oldsecond > "$t/system/app/HKMC_GPM.odex"
chmod 644 "$t/data/out/b" "$t/system/app/HKMC_GPM.odex"
# Retire rollback must prove each source's captured stock identity and static
# metadata before rebinding it. Capture sidecars from the underlying targets
# before any overlay prepare/apply in this two-file scenario.
sha256sum "$t/system/app/Iap2ServerApp.odex" | cut -d ' ' -f1 > "$t/data/out/a.stock"
sha256sum "$t/system/app/HKMC_GPM.odex" | cut -d ' ' -f1 > "$t/data/out/b.stock"
test "$(cat "$t/data/out/a.stock")" = "$(sha256sum "$t/system/app/Iap2ServerApp.odex" | cut -d ' ' -f1)"
test "$(cat "$t/data/out/b.stock")" = "$(sha256sum "$t/system/app/HKMC_GPM.odex" | cut -d ' ' -f1)"
test "$(stat -c '%u|%g|%a' "$t/data/out/a")" = "$(stat -c '%u|%g|%a' "$t/system/app/Iap2ServerApp.odex")"
test "$(stat -c '%u|%g|%a' "$t/data/out/b")" = "$(stat -c '%u|%g|%a' "$t/system/app/HKMC_GPM.odex")"
printf 'bt|/data/out/a|/system/app/Iap2ServerApp.odex|%s|%s|static\nbt|/data/out/b|/system/app/HKMC_GPM.odex|%s|%s|static\n' "$hash" "$meta" "$(sha256sum "$t/data/out/b" | cut -d ' ' -f1)" "$meta" > "$t/multi"
run prepare "$t/multi"
printf '%s\n' "$t/system/app/HKMC_GPM.odex" > "$t/failtarget"
fail apply
test ! -s "$t/mounts"
rm "$t/failtarget"
echo 'portable selection and multi-file tests passed'
# A foreign replacement mount is never unmounted by journal recovery.
run prepare "$t/multi"
printf applying > "$t/state/state"
printf '/system/app/HKMC_GPM.odex|foreign-identity\n' > "$t/state/journal"
printf '%s\n' "$t/system/app/HKMC_GPM.odex" > "$t/mounts"
run status | grep 'state|failed' >/dev/null
test -s "$t/mounts"
fail disable
: > "$t/mounts"
run disable
# Prepare requires a healthy zygote, apply uses the separately checked maintenance state.
touch "$t/healthy.fail"
fail prepare "$t/multi"
rm "$t/healthy.fail"
run prepare "$t/multi"
printf boot3 > "$t/boot"
fail apply
run disable
echo 'portable ownership and boot-proof tests passed'
mkdir -p "$t/system/onebin/osah_kr"
printf stockcfg > "$t/system/onebin/osah_kr/featurexml.cfg"
printf reviewedcfg > "$t/data/out/featurexml.cfg"
chmod 644 "$t/data/out/featurexml.cfg" "$t/system/onebin/osah_kr/featurexml.cfg"
printf 'projection|/data/out/featurexml.cfg|/system/onebin/osah_kr/featurexml.cfg|%s|%s|static\n' "$(sha256sum "$t/data/out/featurexml.cfg" | cut -d ' ' -f1)" "$meta" > "$t/onebin"
run prepare "$t/onebin"
run apply
run disable
mkdir -p "$t/system/onebin/osah_kr/extra"
cp "$t/system/onebin/osah_kr/featurexml.cfg" "$t/system/onebin/osah_kr/extra/featurexml.cfg"
sed 's@onebin/osah_kr/featurexml.cfg@onebin/osah_kr/extra/featurexml.cfg@' "$t/onebin" > "$t/extra-region"
fail prepare "$t/extra-region"
echo 'portable onebin region tests passed'

# Explicit retirement is allowed while Android is running, but only for a
# same-boot committed set whose binds are all still owned and active.
printf boot-retire > "$t/boot"
run prepare "$t/multi"
run apply
run commit
touch "$t/ready.fail"
: > "$t/adapter-events"
touch "$t/bound.fail"
fail retire-live
test "$(cat "$t/state/state")" = committed
test "$(wc -l < "$t/mounts")" -eq 2
rm "$t/bound.fail"
# Missing one active target must be rejected before any unmount.
cp "$t/mounts" "$t/mounts.saved"
sed '$d' "$t/mounts" > "$t/mounts.tmp"
mv "$t/mounts.tmp" "$t/mounts"
fail retire-live
test "$(cat "$t/state/state")" = committed
test "$(wc -l < "$t/mounts")" -eq 1
mv "$t/mounts.saved" "$t/mounts"
# One successful unmount followed by an injected failure must restore all
# owned binds and preserve committed state for a retry.
printf '%s\n' "$t/system/app/HKMC_GPM.odex" > "$t/fail-unmount-target"
fail retire-live
test -f "$t/unmount-failed-once"
test "$(cat "$t/state/state")" = committed
test "$(wc -l < "$t/mounts")" -eq 2
run status | grep 'state|committed' >/dev/null
if grep -E '^(stop-android|start-android)( |$)' "$t/adapter-events" >/dev/null; then echo 'FAIL retire-live controlled Android service'; exit 1; fi
rm "$t/fail-unmount-target" "$t/unmount-failed-once"
run retire-live
test ! -s "$t/mounts"
test "$(cat "$t/state/state")" = retired
if grep -E '^ready( |$)' "$t/adapter-events" >/dev/null; then echo 'FAIL retire-live queried stopped-zygote state'; exit 1; fi
if grep -E '^(stop-android|start-android)( |$)' "$t/adapter-events" >/dev/null; then echo 'FAIL retire-live controlled Android service'; exit 1; fi

LOCK_STATE=$t/state
LOCK_BOOT_FILE=$t/boot

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
