#!/bin/bash
# Removing bundle validation or touching prior on prepare must fail these tests.
. "$(dirname "$0")/lib.sh"
ROOT=$(cd "$(dirname "$0")/.." && pwd)
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
stubs
mkdir -p "$W/usb" "$W/data/nemesis/gen5w-kr-integrated/prior"
cp "$ROOT/tools/integrated/"*.sh "$W/usb/"
cp "$ROOT/packages/core/scripts/recovery-verify.sh" "$W/usb/"
cp "$ROOT/tools/integrated/bin/zipstore-host" "$W/usb/zipstore"
printf 'sentinel\n' > "$W/data/nemesis/gen5w-kr-integrated/prior/preserved"
run() { (cd "$W/usb" && IT_DATA="$W/data" IT_NEM="${RECOVERY_TEST_NEM:-$W/nemesis}" IT_SYSTEM="$W/system" IT_NO_REBOOT=1 IT_SHELL=$(command -v mksh) PATH="$W/bin:$PATH" mksh ${RECOVERY_TRACE:+-x} recovery.sh "$@"); }
run check > "$W/out" 2>&1
check 'missing published runner is refused' test $? != 0
# The builder provides a complete immutable manifest; this small fixture verifies
# the preparation mechanism, never executes a synthetic rollback.
python3 - "$W/usb" <<'PY'
import hashlib,pathlib,sys
p=pathlib.Path(sys.argv[1]); (p/'payload').write_text('verified')
(p/'RECOVERY.md5').write_text(''.join(hashlib.md5(f.read_bytes()).hexdigest()+'  '+f.name+'\n' for f in sorted(p.iterdir()) if f.is_file()))
(p/'RECOVERY.receipt').write_text(hashlib.md5((p/'RECOVERY.md5').read_bytes()).hexdigest()+'\n')
PY
run prepare > "$W/out" 2>&1
prep_rc=$?; [ "$prep_rc" = 0 ] || cat "$W/out"
check 'verified bundle can be prepared' test "$prep_rc" = 0
check 'prepare preserves prior snapshot' grep -qx sentinel "$W/data/nemesis/gen5w-kr-integrated/prior/preserved"
check 'prepare publishes complete runner' test -f "$W/data/nemesis/gen5wkr.recovery/current/recovery.sh"
printf corrupt >> "$W/usb/payload"
run prepare > "$W/out" 2>&1
check 'corrupt incoming bundle refused' test $? != 0
check 'failed prepare preserves published generation' grep -qx verified "$W/data/nemesis/gen5wkr.recovery/current/payload"
printf recovery-required > "$W/data/nemesis/gen5w-kr-integrated/state"
run check > "$W/out" 2>&1
check 'incomplete snapshot refuses recovery' test $? != 0
check 'incomplete snapshot reason observable' grep -qx snapshot-invalid "$W/out"
ln -s "$W/usb" "$W/data/nemesis/gen5wkr.recovery/foreign"
run unknown > "$W/out" 2>&1
check 'unknown operation refused' test $? != 0
printf '1\n' > "$W/data/nemesis/gen5w-kr-integrated/prior/complete"
printf 'enabled\n' > "$W/data/nemesis/gen5w-kr-integrated/prior/wireless-mode"
: > "$W/data/nemesis/gen5w-kr-integrated/prior/ap-markers"
run check > "$W/out" 2>&1
check 'legacy snapshot without per-file integrity requires USB fallback' test $? != 0
python3 - "$W/data/nemesis/gen5w-kr-integrated/prior" <<'PY'
import pathlib,hashlib,sys
p=pathlib.Path(sys.argv[1]); (p/'RECOVERY.md5').write_text(''.join(hashlib.md5(f.read_bytes()).hexdigest()+'  '+f.name+'\n' for f in sorted(p.iterdir()) if f.is_file() and f.name!='complete'))
(p/'RECOVERY.receipt').write_text(hashlib.md5((p/'RECOVERY.md5').read_bytes()).hexdigest()+'\n')
PY
run check > "$W/out" 2>&1
check 'valid empty prior transaction can recover' test $? = 0
echo stock-recover > "$W/data/nemesis/gen5w-kr-integrated/stock-recovery-mode"
run check > "$W/out" 2>&1; stock_rc=$?
check 'interrupted stock recovery refuses snapshot rollback before running' eval '[ "$stock_rc" != 0 ] && grep -qx stock-recovery-required "$W/out"'
rm "$W/data/nemesis/gen5w-kr-integrated/stock-recovery-mode"
boot=$(cat /proc/sys/kernel/random/boot_id)
mkdir "$W/data/nemesis/gen5w-kr-integrated/acquire-guard.$boot"
run run 711 > "$W/out" 2>&1
check 'interrupted current-boot inspection fails closed' test $? != 0
rmdir "$W/data/nemesis/gen5w-kr-integrated/acquire-guard.$boot"
printf recovery-required > "$W/data/nemesis/gen5w-kr-integrated/state"
mkdir -p "$W/race" "$W/data/nemesis/gen5w-kr-integrated/lock"
echo 99999999 > "$W/data/nemesis/gen5w-kr-integrated/lock/pid"
race() { RACE_USB="$W/usb" RACE_DIR="$W/race" RACE_ROLE="$1" IT_DATA="$W/data" IT_SHELL=$(command -v mksh) PATH="$W/bin:$PATH" mksh "$ROOT/tests/recovery-lock-worker.sh" > "$W/race-$1.out" 2>&1; }
race one & race1=$!
while [ ! -f "$W/race/one-read" ]; do sleep 0.05; done
race two & race2=$!
wait "$race1"; wait "$race2"
check 'concurrent stale reclaimers never enter transaction together' test ! -e "$W/race/overlap"
chmod 771 "$W/data"
run check > "$W/out" 2>&1
check 'platform data directory may be system-group writable' test $? = 0
chmod 755 "$W/data"
cp "$W/data/nemesis/gen5w-kr-integrated/prior/RECOVERY.md5" "$W/snapshot.manifest"
python3 - "$W/data/nemesis/gen5w-kr-integrated/prior/RECOVERY.md5" <<'PY'
import pathlib,sys
p=pathlib.Path(sys.argv[1]); p.write_text(p.read_text().splitlines()[0]+'\n')
PY
run check > "$W/out" 2>&1
check 'truncated but syntactically valid inventory is refused' test $? != 0
cp "$W/snapshot.manifest" "$W/data/nemesis/gen5w-kr-integrated/prior/RECOVERY.md5"
RECOVERY_TEST_NEM="$W/missing" run check > "$W/out" 2>&1
check 'missing package manager refuses recovery before changes' test $? != 0
RECOVERY_TEST_NEM="$W/missing" run run 700 > "$W/out" 2>&1
check 'failed preflight consumes the request instead of auto retrying' grep -qx 'recovery_request=700' "$W/data/nemesis/gen5wkr.recovery-result"
printf corrupt >> "$W/data/nemesis/gen5w-kr-integrated/prior/preserved"
run check > "$W/out" 2>&1
check 'prior file corruption refuses recovery before changes' test $? != 0
printf 'sentinel\n' > "$W/data/nemesis/gen5w-kr-integrated/prior/preserved"
ln -s "$W/usb/payload" "$W/data/nemesis/gen5w-kr-integrated/prior/link"
run check > "$W/out" 2>&1
check 'prior symlink refuses recovery before changes' test $? != 0
rm "$W/data/nemesis/gen5w-kr-integrated/prior/link"
mkdir "$W/data/nemesis/gen5w-kr-integrated/prior/gen5w.kr.core"
: > "$W/data/nemesis/gen5w-kr-integrated/attempt.gen5w.kr.core"
run check > "$W/out" 2>&1
check 'partial prior package without ZIP is refused' test $? != 0
rmdir "$W/data/nemesis/gen5w-kr-integrated/prior/gen5w.kr.core"
rm "$W/data/nemesis/gen5w-kr-integrated/attempt.gen5w.kr.core"
mkdir "$W/data/nemesis/gen5w-kr-integrated/lock"
echo $$ > "$W/data/nemesis/gen5w-kr-integrated/lock/pid"
run run 123 > "$W/out" 2>&1
check 'live installer lock refuses worker' test $? != 0
rm -f "$W/data/nemesis/gen5w-kr-integrated/lock/pid"
rmdir "$W/data/nemesis/gen5w-kr-integrated/lock"
run run 123 > "$W/out" 2>&1
check 'verified worker restores previous state' test $? = 0
check 'worker final result persisted outside core' grep -qx 'recovery_result=restored' "$W/data/nemesis/gen5wkr.recovery-result"
check 'worker records transaction restored' grep -qx rolled-back "$W/data/nemesis/gen5w-kr-integrated/state"
run run 123 > "$W/out" 2>&1
check 'duplicate request does not rerun restoration' test $? != 0
printf recovery-required > "$W/data/nemesis/gen5w-kr-integrated/state"
mkdir "$W/data/nemesis/gen5wkr.bootguard.previous"
run run 456 > "$W/out" 2>&1
check 'bootguard reconciliation failure remains recoverable' test $? != 0
check 'bootguard failure retains recovery required' grep -qx recovery-required "$W/data/nemesis/gen5w-kr-integrated/state"
check 'bootguard failure is recorded separately' grep -qx 'recovery_result=failed' "$W/data/nemesis/gen5wkr.recovery-result"
check 'failed report offers actionable recovery instructions' grep -q 'recovery-prepare' "$W/data/nemesis/gen5wkr.recovery/current/GEN5W-REPORT/RESULT.md"
rmdir "$W/data/nemesis/gen5wkr.bootguard.previous"
printf '#!/bin/sh\nif [ "$1" = "$IT_DATA/nemesis/gen5w-kr-integrated/state.tmp" ] && grep -qx rolled-back "$1"; then exit 1; fi\nexec /bin/mv "$@"\n' > "$W/bin/mv"
chmod +x "$W/bin/mv"
run run 457 > "$W/out" 2>&1
check 'app terminal state write failure is refused' test $? != 0
check 'app terminal state write failure retains recovery and suppression' eval 'grep -qx recovery-required "$W/data/nemesis/gen5w-kr-integrated/state" && test -f "$W/data/nemesis/gen5wkr.noreboot"'
rm "$W/bin/mv"
mkdir -p "$W/app" "$W/ui"
cp "$W/data/nemesis/gen5wkr.recovery/current/common.sh" "$W/common.original"
printf '\necho executed > "%s/unverified-executed"\n' "$W" >> "$W/data/nemesis/gen5wkr.recovery/current/common.sh"
read -r up rest < /proc/uptime
printf 'boot=%s\nexpires=%s\nrecovery=789\n' "$(cat /proc/sys/kernel/random/boot_id)" "$((${up%%.*}+30))" > "$W/app/ui-request"
IT_DATA="$W/data" IT_NEM="$W/nemesis" IT_SYSTEM="$W/system" IT_NO_REBOOT=1 IT_SHELL=$(command -v mksh) \
UILOG_TEST_DATA="$W/data" UILOG_TEST_DIR="$W/ui" UILOG_TEST_REQUEST="$W/app/ui-request" \
UILOG_TEST_SH=$(command -v mksh) UILOG_TEST_ONCE=1 PATH="$W/bin:$PATH" \
    python3 "$ROOT/tests/wait-descendants.py" mksh "$ROOT/packages/core/scripts/uilog.sh" > "$W/out" 2>&1
check 'collector request runs independent real recovery worker' test $? = 0
check 'corrupted bundle code never executes before verification' test ! -e "$W/unverified-executed"
cp "$W/common.original" "$W/data/nemesis/gen5wkr.recovery/current/common.sh"
printf 'boot=%s\nexpires=%s\nrecovery=790\n' "$(cat /proc/sys/kernel/random/boot_id)" "$(($(cut -d. -f1 /proc/uptime)+30))" > "$W/app/ui-request"
IT_DATA="$W/data" IT_NEM="$W/nemesis" IT_SYSTEM="$W/system" IT_NO_REBOOT=1 IT_SHELL=$(command -v mksh) \
UILOG_TEST_DATA="$W/data" UILOG_TEST_DIR="$W/ui" UILOG_TEST_REQUEST="$W/app/ui-request" \
UILOG_TEST_SH=$(command -v mksh) UILOG_TEST_ONCE=1 PATH="$W/bin:$PATH" \
    python3 "$ROOT/tests/wait-descendants.py" mksh "$ROOT/packages/core/scripts/uilog.sh" > "$W/out" 2>&1
check 'collector-triggered worker persists final restoration' grep -qx 'recovery_result=restored' "$W/data/nemesis/gen5wkr.recovery-result"
check 'collector-triggered worker preserves request identity' grep -qx 'recovery_request=790' "$W/data/nemesis/gen5wkr.recovery-result"
printf recovery-required > "$W/data/nemesis/gen5w-kr-integrated/state"
python3 - "$W/data/nemesis/gen5wkr.recovery/current" <<'PY'
import pathlib,hashlib,sys
p=pathlib.Path(sys.argv[1]); f=p/'common.sh'
with f.open('a') as out:
 out.write('\ni=0; while [ "$i" -lt 2000 ]; do echo "'+('diagnostic-line-'*14)+'"; i=$((i+1)); done\n')
 out.write('echo "password=fixture-only-never-export"\n')
m=p/'RECOVERY.md5'; lines=m.read_text().splitlines()
m.write_text('\n'.join(hashlib.md5(f.read_bytes()).hexdigest()+'  common.sh' if x.endswith('  common.sh') else x for x in lines)+'\n')
(p/'RECOVERY.receipt').write_text(hashlib.md5(m.read_bytes()).hexdigest()+'\n')
PY
IT_DATA="$W/data" IT_NEM="$W/nemesis" IT_SYSTEM="$W/system" IT_NO_REBOOT=1 IT_SHELL=$(command -v mksh) PATH="$W/bin:$PATH" \
    mksh "$ROOT/packages/core/scripts/recovery-launch.sh" 9999 > "$W/out" 2>&1
check 'bounded logger drains verbose worker without breaking recovery' test $? = 0
check 'worker output stays under one bounded log' test "$(wc -c < "$W/data/nemesis/gen5wkr.recovery-worker.log")" -le 62500
check 'worker output excludes credential-like content' eval '! grep -q fixture-only-never-export "$W/data/nemesis/gen5wkr.recovery-worker.log"'
done_tests installation-recovery
